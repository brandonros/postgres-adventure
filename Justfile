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

    # -e = echo queries, -v ON_ERROR_STOP=1 = stop on first error
    PSQL_OPTS="-e -v ON_ERROR_STOP=1"

    if [ -z "{{ sql_file }}" ]; then
        ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP \
            "KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c 'PGPASSWORD=\"Test_Password123!\" psql $PSQL_OPTS -U postgres -d {{ database }}'"
    else
        cat {{ script_path }}/{{ sql_file }} | ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP \
            "KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c 'PGPASSWORD=\"Test_Password123!\" psql $PSQL_OPTS -U postgres -d {{ database }}'"
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

    # Run pg_basebackup job (-R creates standby.signal and postgresql.auto.conf)
    echo "Running pg_basebackup to clone from primary..."

    # Delete any existing job first
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl delete job pg-basebackup -n postgresql --ignore-not-found"

    # Apply job with PRIMARY_HOST set
    sed "s/PLACEHOLDER/$DC1_IP/" {{ script_path }}/manifests/pg-basebackup-job.yaml | \
        ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl apply -f -"

    # Wait for job to complete and show logs
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl wait --for=condition=complete job/pg-basebackup -n postgresql --timeout=300s"
    ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP "KUBECONFIG=/home/debian/.kube/config kubectl logs job/pg-basebackup -n postgresql"

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
    echo "Enabling synchronous replication..."
    echo "ALTER SYSTEM SET synchronous_standby_names = 'walreceiver';" | just exec-psql dc1 postgres
    echo "SELECT pg_reload_conf();" | just exec-psql dc1 postgres

    echo ""
    echo "============================================"
    echo "Streaming replication setup complete!"
    echo "============================================"
    echo ""
    echo "Checking replication status..."
    just status

# Check replication status (auto-detects topology)
status:
    #!/usr/bin/env bash
    set -e

    # Detect current topology
    DC1_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc1 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")
    DC2_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc2 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")

    if [ "$DC1_IN_RECOVERY" = "f" ] && [ "$DC2_IN_RECOVERY" = "t" ]; then
        PRIMARY="dc1"
        STANDBY="dc2"
    elif [ "$DC2_IN_RECOVERY" = "f" ] && [ "$DC1_IN_RECOVERY" = "t" ]; then
        PRIMARY="dc2"
        STANDBY="dc1"
    elif [ "$DC1_IN_RECOVERY" = "f" ] && [ "$DC2_IN_RECOVERY" = "f" ]; then
        echo "WARNING: Both nodes are primaries (split-brain)"
        PRIMARY="dc1"
        STANDBY="dc2"
    else
        echo "WARNING: Could not determine topology"
        PRIMARY="dc1"
        STANDBY="dc2"
    fi

    echo ""
    echo "=== Primary ($PRIMARY) - pg_stat_replication ==="
    just exec-psql $PRIMARY postgres sql/templates/verify-replication.sql || true

    echo ""
    echo "=== Standby ($STANDBY) - pg_stat_wal_receiver ==="
    echo "SELECT * FROM pg_stat_wal_receiver;" | just exec-psql $STANDBY postgres || true

# Manual failover - promote standby to primary (idempotent, bidirectional)
failover:
    #!/usr/bin/env bash
    set -e

    echo "MANUAL FAILOVER PROCEDURE"
    echo "========================="
    echo ""

    # Check both nodes to determine current topology
    echo "Detecting current topology..."
    DC1_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc1 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")
    DC2_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc2 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")

    echo "  dc1 in recovery: $DC1_IN_RECOVERY"
    echo "  dc2 in recovery: $DC2_IN_RECOVERY"
    echo ""

    # Determine which node to promote
    if [ "$DC1_IN_RECOVERY" = "t" ] && [ "$DC2_IN_RECOVERY" = "f" ]; then
        STANDBY="dc1"
        PRIMARY="dc2"
    elif [ "$DC2_IN_RECOVERY" = "t" ] && [ "$DC1_IN_RECOVERY" = "f" ]; then
        STANDBY="dc2"
        PRIMARY="dc1"
    elif [ "$DC1_IN_RECOVERY" = "f" ] && [ "$DC2_IN_RECOVERY" = "f" ]; then
        echo "ERROR: Both nodes are primaries (split-brain). Manual intervention required."
        exit 1
    elif [ "$DC1_IN_RECOVERY" = "t" ] && [ "$DC2_IN_RECOVERY" = "t" ]; then
        echo "ERROR: Both nodes are standbys. No primary available."
        exit 1
    else
        echo "ERROR: Could not determine topology. Check node connectivity."
        exit 1
    fi

    echo "Current topology: $PRIMARY is primary, $STANDBY is standby"
    echo ""

    echo "Step 1: Verify standby is caught up..."
    just status

    echo ""
    echo "Step 2: Stopping old primary ($PRIMARY) to prevent split-brain..."
    cd {{ script_path }}/terraform
    PRIMARY_IP=$(terraform output -json instance_ipv4s | jq -r ".[\"$PRIMARY\"]")
    PRIMARY_USERNAME=$(terraform output -json instance_usernames | jq -r ".[\"$PRIMARY\"]")
    PRIMARY_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r ".[\"$PRIMARY\"]")
    ssh -p $PRIMARY_SSH_PORT $PRIMARY_USERNAME@$PRIMARY_IP 'KUBECONFIG=/home/debian/.kube/config kubectl scale statefulset postgresql -n postgresql --replicas=0'

    echo ""
    echo "Step 3: Promoting $STANDBY to primary..."
    echo "SELECT pg_promote();" | just exec-psql $STANDBY postgres

    echo ""
    echo "Failover complete! $STANDBY is now primary, $PRIMARY is stopped."
    echo ""
    echo "Next step: Rebuild $PRIMARY as standby:"
    echo "  just rebuild-standby $PRIMARY"

# Rebuild a node as standby of the current primary
rebuild-standby node:
    #!/usr/bin/env bash
    set -e

    echo "REBUILD STANDBY: {{ node }}"
    echo "=========================="
    echo ""

    # Determine which node is the current primary
    DC1_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc1 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")
    DC2_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc2 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")

    if [ "$DC1_IN_RECOVERY" = "f" ] && [ "$DC2_IN_RECOVERY" = "t" ]; then
        PRIMARY="dc1"
    elif [ "$DC2_IN_RECOVERY" = "f" ] && [ "$DC1_IN_RECOVERY" = "t" ]; then
        PRIMARY="dc2"
    elif [ "$DC1_IN_RECOVERY" = "f" ] && [ "$DC2_IN_RECOVERY" = "f" ]; then
        # Split-brain: the node we're NOT rebuilding becomes the primary
        if [ "{{ node }}" = "dc1" ]; then
            PRIMARY="dc2"
            echo "WARNING: Split-brain detected. Treating dc2 as primary."
        else
            PRIMARY="dc1"
            echo "WARNING: Split-brain detected. Treating dc1 as primary."
        fi
    else
        echo "ERROR: Could not find a primary node (both in recovery or unreachable)."
        exit 1
    fi

    echo "Primary is: $PRIMARY"
    echo "Rebuilding {{ node }} as standby..."
    echo ""

    cd {{ script_path }}/terraform
    PRIMARY_IP=$(terraform output -json instance_ipv4s | jq -r ".[\"$PRIMARY\"]")
    NODE_IP=$(terraform output -json instance_ipv4s | jq -r '.["{{ node }}"]')
    NODE_USERNAME=$(terraform output -json instance_usernames | jq -r '.["{{ node }}"]')
    NODE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ node }}"]')

    echo "Primary IP: $PRIMARY_IP"
    echo "Target IP: $NODE_IP"

    # Stop postgresql on target
    echo "Stopping PostgreSQL on {{ node }}..."
    ssh -p $NODE_SSH_PORT $NODE_USERNAME@$NODE_IP 'KUBECONFIG=/home/debian/.kube/config kubectl scale statefulset postgresql -n postgresql --replicas=0'
    sleep 5

    # Ensure replication slot exists on primary (may not exist after failover)
    echo "Ensuring replication slot exists on $PRIMARY..."
    echo "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'standby1_slot') THEN PERFORM pg_create_physical_replication_slot('standby1_slot'); END IF; END \$\$;" | just exec-psql $PRIMARY postgres

    # Run pg_basebackup job (-R creates standby.signal and postgresql.auto.conf)
    echo "Running pg_basebackup from $PRIMARY..."

    # Delete any existing job first
    ssh -p $NODE_SSH_PORT $NODE_USERNAME@$NODE_IP "KUBECONFIG=/home/debian/.kube/config kubectl delete job pg-basebackup -n postgresql --ignore-not-found"

    # Apply job with PRIMARY_HOST set
    sed "s/PLACEHOLDER/$PRIMARY_IP/" {{ script_path }}/manifests/pg-basebackup-job.yaml | \
        ssh -p $NODE_SSH_PORT $NODE_USERNAME@$NODE_IP "KUBECONFIG=/home/debian/.kube/config kubectl apply -f -"

    # Wait for job to complete and show logs
    ssh -p $NODE_SSH_PORT $NODE_USERNAME@$NODE_IP "KUBECONFIG=/home/debian/.kube/config kubectl wait --for=condition=complete job/pg-basebackup -n postgresql --timeout=300s"
    ssh -p $NODE_SSH_PORT $NODE_USERNAME@$NODE_IP "KUBECONFIG=/home/debian/.kube/config kubectl logs job/pg-basebackup -n postgresql"

    # Start postgresql
    echo "Starting PostgreSQL on {{ node }}..."
    ssh -p $NODE_SSH_PORT $NODE_USERNAME@$NODE_IP 'KUBECONFIG=/home/debian/.kube/config kubectl scale statefulset postgresql -n postgresql --replicas=1'

    just wait-for-postgres {{ node }}

    echo ""
    echo "{{ node }} rebuilt as standby of $PRIMARY"
    just status

# Verify data is replicated
verify-data:
    #!/usr/bin/env bash
    set -e

    echo ""
    echo "=== Data on dc1 ==="
    echo "SELECT * FROM users; SELECT * FROM orders;" | just exec-psql dc1 my_db || true

    echo ""
    echo "=== Data on dc2 ==="
    echo "SELECT * FROM users; SELECT * FROM orders;" | just exec-psql dc2 my_db || true

# Insert test data on current primary
insert-test:
    #!/usr/bin/env bash
    set -e

    # Find the primary (check both nodes to detect split-brain)
    DC1_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc1 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")
    DC2_IN_RECOVERY=$(echo "SELECT pg_is_in_recovery();" | just exec-psql dc2 postgres 2>/dev/null | grep -E '^ (t|f)' | tr -d ' ' || echo "error")

    if [ "$DC1_IN_RECOVERY" = "f" ] && [ "$DC2_IN_RECOVERY" = "t" ]; then
        PRIMARY="dc1"
    elif [ "$DC2_IN_RECOVERY" = "f" ] && [ "$DC1_IN_RECOVERY" = "t" ]; then
        PRIMARY="dc2"
    elif [ "$DC1_IN_RECOVERY" = "f" ] && [ "$DC2_IN_RECOVERY" = "f" ]; then
        echo "ERROR: Both nodes are primaries (split-brain). Run 'just rebuild-standby <node>' first."
        exit 1
    else
        echo "ERROR: Could not determine primary. Check node connectivity."
        exit 1
    fi

    echo "Inserting test row on primary ($PRIMARY)..."
    echo "INSERT INTO users (email, name) VALUES ('test-$(date +%s)@example.com', 'Test User');" | just exec-psql $PRIMARY my_db
    echo "Done. Run 'just verify-data' to see replication."
