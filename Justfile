#!/usr/bin/env just --justfile

set shell := ["bash", "-euo", "pipefail", "-c"]
set export

script_path := justfile_directory()

# Default recipe - shows available commands
default:
    @just --list

vm:
    #!/usr/bin/env bash
    set -e
    echo "Provisioning VM infrastructure..."
    cd {{ script_path }}/terraform
    terraform init
    terraform apply -auto-approve
    echo "Infrastructure provisioned successfully!"

# Destroy all infrastructure
destroy:
    #!/usr/bin/env bash
    set -e
    echo "Destroying VM infrastructure..."
    cd {{ script_path }}/terraform
    terraform destroy -auto-approve
    echo "Infrastructure destroyed!"

# Wait for host and accept SSH key
wait-and-accept instance_name: vm
    #!/usr/bin/env bash
    set -e

    # Get instance details from terraform
    cd {{ script_path }}/terraform
    INSTANCE_IPV4=$(terraform output -json instance_ipv4s | jq -r '.["{{ instance_name }}"]')
    INSTANCE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ instance_name }}"]')

    if [ "$INSTANCE_IPV4" = "null" ] || [ -z "$INSTANCE_IPV4" ]; then
        echo "Instance '{{ instance_name }}' not found in terraform outputs"
        exit 1
    fi

    # Wait for host to be available
    echo "Waiting for ${INSTANCE_IPV4} to become available on port ${INSTANCE_SSH_PORT}..."
    while ! (echo > /dev/tcp/${INSTANCE_IPV4}/${INSTANCE_SSH_PORT}) 2>/dev/null; do
        sleep 1
    done
    echo "${INSTANCE_IPV4} is now available"

    # Remove old fingerprint if exists
    if ssh-keygen -F ${INSTANCE_IPV4} > /dev/null 2>&1; then
        ssh-keygen -R ${INSTANCE_IPV4}
    fi

    # Accept new SSH fingerprint
    ssh-keyscan -H -p ${INSTANCE_SSH_PORT} ${INSTANCE_IPV4} >> ~/.ssh/known_hosts
    echo "SSH key accepted"

# Connect
connect instance_name: (wait-and-accept instance_name)
    #!/usr/bin/env bash
    set -e

    # Get instance details from terraform
    cd {{ script_path }}/terraform
    INSTANCE_IPV4=$(terraform output -json instance_ipv4s | jq -r '.["{{ instance_name }}"]')
    INSTANCE_USERNAME=$(terraform output -json instance_usernames | jq -r '.["{{ instance_name }}"]')
    INSTANCE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ instance_name }}"]')

    ssh -p ${INSTANCE_SSH_PORT} ${INSTANCE_USERNAME}@${INSTANCE_IPV4}

# Helper: Wait for PostgreSQL pod to be ready
wait-for-postgres instance_name:
    #!/usr/bin/env bash
    set -e

    cd {{ script_path }}/terraform
    INSTANCE_IP=$(terraform output -json instance_ipv4s | jq -r '.["{{ instance_name }}"]')
    INSTANCE_USERNAME=$(terraform output -json instance_usernames | jq -r '.["{{ instance_name }}"]')
    INSTANCE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ instance_name }}"]')

    echo "Waiting for PostgreSQL pod on {{ instance_name }} to be ready..."
    while ! ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP 'KUBECONFIG=/home/debian/.kube/config kubectl get pod postgresql-0 -n postgresql 2>/dev/null | grep -q "1/1.*Running"'; do
        echo "   Waiting for postgresql-0 pod on {{ instance_name }}..."
        sleep 2
    done
    echo "PostgreSQL pod on {{ instance_name }} is ready"

    echo "Waiting for PostgreSQL service on {{ instance_name }} to accept connections..."
    while ! ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres -c \"SELECT 1\" > /dev/null 2>&1"'; do
        echo "   Waiting for PostgreSQL service on {{ instance_name }}..."
        sleep 2
    done
    echo "PostgreSQL service on {{ instance_name }} is accepting connections"

# Helper: Execute PostgreSQL command
exec-psql instance_name database sql_file="":
    #!/usr/bin/env bash
    set -e

    cd {{ script_path }}/terraform
    INSTANCE_IP=$(terraform output -json instance_ipv4s | jq -r '.["{{ instance_name }}"]')
    INSTANCE_USERNAME=$(terraform output -json instance_usernames | jq -r '.["{{ instance_name }}"]')
    INSTANCE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ instance_name }}"]')

    if [ -z "{{ sql_file }}" ]; then
        ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP \
            'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d {{ database }}"'
    else
        cat {{ script_path }}/{{ sql_file }} | ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP \
            'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d {{ database }}"'
    fi

# Helper: Execute shell command on instance
exec-ssh instance_name cmd:
    #!/usr/bin/env bash
    set -e

    cd {{ script_path }}/terraform
    INSTANCE_IP=$(terraform output -json instance_ipv4s | jq -r '.["{{ instance_name }}"]')
    INSTANCE_USERNAME=$(terraform output -json instance_usernames | jq -r '.["{{ instance_name }}"]')
    INSTANCE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ instance_name }}"]')

    ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP "{{ cmd }}"

# Setup primary node (dc1)
setup-primary: (wait-and-accept "dc1") (wait-for-postgres "dc1")
    #!/usr/bin/env bash
    set -e

    echo "Setting up primary node (dc1)..."

    # Create database, replication user, and replication slot
    echo "Running postgres-setup.sql on dc1..."
    just exec-psql dc1 postgres sql/common/postgres-setup.sql

    # Create schema
    echo "Running schema.sql on dc1..."
    just exec-psql dc1 my_db sql/templates/schema.sql

    # Insert sample data
    echo "Running sample-data.sql on dc1..."
    just exec-psql dc1 my_db sql/data/sample-data.sql

    echo "Primary node (dc1) setup complete!"

# Setup standby node (dc2) - clones from primary using pg_basebackup
setup-standby: (wait-and-accept "dc2") (wait-for-postgres "dc2")
    #!/usr/bin/env bash
    set -e

    echo "Setting up standby node (dc2)..."

    cd {{ script_path }}/terraform
    DC1_IP=$(terraform output -json instance_ipv4s | jq -r '.["dc1"]')
    DC2_IP=$(terraform output -json instance_ipv4s | jq -r '.["dc2"]')
    DC2_USERNAME=$(terraform output -json instance_usernames | jq -r '.["dc2"]')
    DC2_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["dc2"]')

    echo "Primary (dc1) IP: $DC1_IP"
    echo "Standby (dc2) IP: $DC2_IP"

    # Scale down postgresql to stop the pod
    echo "Stopping PostgreSQL pod on dc2..."
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl scale statefulset postgresql -n postgresql --replicas=0'
    sleep 5

    # Clear the data directory and run pg_basebackup
    echo "Running pg_basebackup to clone from primary..."
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl run pg-basebackup --rm -i --restart=Never --image=bitnami/postgresql:17 -- bash -c '
        # Wait for primary to be reachable
        until PGPASSWORD=test pg_isready -h $DC1_IP -p 30432 -U replicator; do
            echo \"Waiting for primary...\"
            sleep 2
        done

        # Run pg_basebackup
        PGPASSWORD=test pg_basebackup -h $DC1_IP -p 30432 -U replicator -D /tmp/pgdata -Fp -Xs -P -R -S standby1_slot

        # Show what was created
        echo \"Base backup complete. Files:\"
        ls -la /tmp/pgdata/
        cat /tmp/pgdata/postgresql.auto.conf
    '"

    # Copy the backup to the PVC
    echo "Copying backup to PVC..."
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl run pg-restore --rm -i --restart=Never \
        --overrides='{\"spec\":{\"containers\":[{\"name\":\"pg-restore\",\"image\":\"bitnami/postgresql:17\",\"command\":[\"bash\",\"-c\",\"rm -rf /bitnami/postgresql/data/* && PGPASSWORD=test pg_basebackup -h $DC1_IP -p 30432 -U replicator -D /bitnami/postgresql/data -Fp -Xs -P -R -S standby1_slot && chown -R 1001:1001 /bitnami/postgresql/data && ls -la /bitnami/postgresql/data/\"],\"volumeMounts\":[{\"name\":\"data\",\"mountPath\":\"/bitnami/postgresql\"}]}],\"volumes\":[{\"name\":\"data\",\"persistentVolumeClaim\":{\"claimName\":\"data-postgresql-0\"}}]}}' \
        -- true"

    # Create standby.signal file
    echo "Creating standby.signal..."
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl run pg-signal --rm -i --restart=Never \
        --overrides='{\"spec\":{\"containers\":[{\"name\":\"pg-signal\",\"image\":\"bitnami/postgresql:17\",\"command\":[\"bash\",\"-c\",\"touch /bitnami/postgresql/data/standby.signal && echo standby.signal created && ls -la /bitnami/postgresql/data/standby.signal\"],\"volumeMounts\":[{\"name\":\"data\",\"mountPath\":\"/bitnami/postgresql\"}]}],\"volumes\":[{\"name\":\"data\",\"persistentVolumeClaim\":{\"claimName\":\"data-postgresql-0\"}}]}}' \
        -- true"

    # Update primary_conninfo with correct settings
    echo "Updating primary_conninfo..."
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl run pg-config --rm -i --restart=Never \
        --overrides='{\"spec\":{\"containers\":[{\"name\":\"pg-config\",\"image\":\"bitnami/postgresql:17\",\"command\":[\"bash\",\"-c\",\"echo \\\"primary_conninfo = '\\''host=$DC1_IP port=30432 user=replicator password=test application_name=standby1'\\''\\\" > /bitnami/postgresql/data/postgresql.auto.conf && echo \\\"primary_slot_name = '\\''standby1_slot'\\''\\\" >> /bitnami/postgresql/data/postgresql.auto.conf && cat /bitnami/postgresql/data/postgresql.auto.conf\"],\"volumeMounts\":[{\"name\":\"data\",\"mountPath\":\"/bitnami/postgresql\"}]}],\"volumes\":[{\"name\":\"data\",\"persistentVolumeClaim\":{\"claimName\":\"data-postgresql-0\"}}]}}' \
        -- true"

    # Scale back up
    echo "Starting PostgreSQL pod on dc2..."
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl scale statefulset postgresql -n postgresql --replicas=1'

    # Wait for standby to be ready
    just wait-for-postgres dc2

    echo "Standby node (dc2) setup complete!"

# Main setup - sets up primary then standby
setup-replication: setup-primary setup-standby
    #!/usr/bin/env bash
    set -e

    echo ""
    echo "============================================"
    echo "Streaming replication setup complete!"
    echo "============================================"
    echo ""
    echo "Checking replication status..."
    just status

# Check replication status
status:
    #!/usr/bin/env bash
    set -e

    echo ""
    echo "=== Primary (dc1) - pg_stat_replication ==="
    just exec-psql dc1 postgres sql/templates/verify-replication.sql || true

    echo ""
    echo "=== Standby (dc2) - pg_stat_wal_receiver ==="
    echo "SELECT * FROM pg_stat_wal_receiver;" | just exec-psql dc2 postgres || true

# Manual failover - promote standby to primary
failover:
    #!/usr/bin/env bash
    set -e

    echo "MANUAL FAILOVER PROCEDURE"
    echo "========================="
    echo ""
    echo "Step 1: Verify standby is caught up..."
    just status

    echo ""
    echo "Step 2: Promoting standby (dc2) to primary..."
    echo "SELECT pg_promote();" | just exec-psql dc2 postgres

    echo ""
    echo "Failover complete!"
    echo ""
    echo "IMPORTANT: Update your application connection strings to point to dc2."
    echo "The old primary (dc1) should be rebuilt as a standby or decommissioned."

# Verify data is replicated
verify-data:
    #!/usr/bin/env bash
    set -e

    echo ""
    echo "=== Data on Primary (dc1) ==="
    echo "SELECT * FROM users; SELECT * FROM orders;" | just exec-psql dc1 my_db

    echo ""
    echo "=== Data on Standby (dc2) ==="
    echo "SELECT * FROM users; SELECT * FROM orders;" | just exec-psql dc2 my_db

# Insert test data on primary
insert-test:
    #!/usr/bin/env bash
    set -e

    echo "Inserting test row on primary (dc1)..."
    echo "INSERT INTO users (email, name) VALUES ('test-$(date +%s)@example.com', 'Test User');" | just exec-psql dc1 my_db
    echo "Done. Run 'just verify-data' to see replication."
