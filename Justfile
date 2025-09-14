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
    echo "🚀 Provisioning VM infrastructure..."
    cd {{ script_path }}/terraform
    terraform init
    terraform apply -auto-approve
    echo "✅ Infrastructure provisioned successfully!"

# Wait for host and accept SSH key
wait-and-accept instance_name: vm
    #!/usr/bin/env bash
    set -e

    # Get instance details from terraform
    cd {{ script_path }}/terraform
    INSTANCE_IPV4=$(terraform output -json instance_ipv4s | jq -r '.["{{ instance_name }}"]')
    INSTANCE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ instance_name }}"]')

    if [ "$INSTANCE_IPV4" = "null" ] || [ -z "$INSTANCE_IPV4" ]; then
        echo "❌ Instance '{{ instance_name }}' not found in terraform outputs"
        exit 1
    fi

    # Wait for host to be available
    echo "⏳ Waiting for ${INSTANCE_IPV4} to become available on port ${INSTANCE_SSH_PORT}..."
    while ! (echo > /dev/tcp/${INSTANCE_IPV4}/${INSTANCE_SSH_PORT}) 2>/dev/null; do
        sleep 1
    done
    echo "✅ ${INSTANCE_IPV4} is now available"

    # Remove old fingerprint if exists
    if ssh-keygen -F ${INSTANCE_IPV4} > /dev/null 2>&1; then
        ssh-keygen -R ${INSTANCE_IPV4}
    fi

    # Accept new SSH fingerprint
    ssh-keyscan -H -p ${INSTANCE_SSH_PORT} ${INSTANCE_IPV4} >> ~/.ssh/known_hosts
    echo "✅ SSH key accepted"

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

    echo "⏳ Waiting for PostgreSQL pod on {{ instance_name }} to be ready..."
    while ! ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP 'KUBECONFIG=/home/debian/.kube/config kubectl get pod postgresql-0 -n postgresql 2>/dev/null | grep -q "1/1.*Running"'; do
        echo "   Waiting for postgresql-0 pod on {{ instance_name }}..."
        sleep 2
    done
    echo "✅ PostgreSQL pod on {{ instance_name }} is ready"

    echo "⏳ Waiting for PostgreSQL service on {{ instance_name }} to accept connections..."
    while ! ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres -c \"SELECT 1\" > /dev/null 2>&1"'; do
        echo "   Waiting for PostgreSQL service on {{ instance_name }}..."
        sleep 2
    done
    echo "✅ PostgreSQL service on {{ instance_name }} is accepting connections"

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

# Helper: Apply SQL template with substitutions
apply-sql-template instance_name database template_file node_name node_ip other_node_name other_node_ip:
    #!/usr/bin/env bash
    set -e

    cd {{ script_path }}/terraform
    INSTANCE_IP=$(terraform output -json instance_ipv4s | jq -r '.["{{ instance_name }}"]')
    INSTANCE_USERNAME=$(terraform output -json instance_usernames | jq -r '.["{{ instance_name }}"]')
    INSTANCE_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["{{ instance_name }}"]')

    # Load sample data if exists
    SAMPLE_DATA=""
    if [ -f "{{ script_path }}/sql/data/{{ node_name }}-data.sql" ]; then
        SAMPLE_DATA=$(cat "{{ script_path }}/sql/data/{{ node_name }}-data.sql")
    fi

    cat {{ script_path }}/{{ template_file }} | \
        sed "s/__NODE_NAME__/{{ node_name }}/g" | \
        sed "s/__NODE_IP__/{{ node_ip }}/g" | \
        sed "s/__OTHER_NODE_NAME__/{{ other_node_name }}/g" | \
        sed "s/__OTHER_NODE_IP__/{{ other_node_ip }}/g" | \
        sed "s/__SAMPLE_DATA__/$SAMPLE_DATA/g" | \
        ssh -p $INSTANCE_SSH_PORT $INSTANCE_USERNAME@$INSTANCE_IP \
            'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d {{ database }}"'

# Setup PostgreSQL replication between dc1 and dc2
setup-replication: (wait-and-accept "dc1") (wait-and-accept "dc2") (wait-for-postgres "dc1") (wait-for-postgres "dc2")
    #!/usr/bin/env bash
    set -e

    echo "🔄 Setting up PostgreSQL replication..."

    # Get instance details from terraform
    echo "📋 Loading instance details from terraform..."
    cd {{ script_path }}/terraform
    DC1_IP=$(terraform output -json instance_ipv4s | jq -r '.["dc1"]')
    DC2_IP=$(terraform output -json instance_ipv4s | jq -r '.["dc2"]')
    echo "   DC1: $DC1_IP"
    echo "   DC2: $DC2_IP"

    cd {{ script_path }}

    # Step 1: Setup postgres database on both nodes (identical for both)
    echo "🗄️  Setting up postgres database on dc1..."
    just exec-psql dc1 postgres sql/common/postgres-setup.sql

    echo "🗄️  Setting up postgres database on dc2..."
    just exec-psql dc2 postgres sql/common/postgres-setup.sql

    # Step 2: Setup my_db database with pglogical on both nodes
    echo "🔧 Setting up my_db with pglogical on dc1..."
    just apply-sql-template dc1 my_db sql/templates/my_db-setup.sql node1 $DC1_IP node2 $DC2_IP

    echo "🔧 Setting up my_db with pglogical on dc2..."
    just apply-sql-template dc2 my_db sql/templates/my_db-setup.sql node2 $DC2_IP node1 $DC1_IP

    # Step 3: Sync replication
    echo "🔄 Syncing replication on dc1..."
    just apply-sql-template dc1 my_db sql/templates/my_db-sync.sql node1 $DC1_IP node2 $DC2_IP

    echo "🔄 Syncing replication on dc2..."
    just apply-sql-template dc2 my_db sql/templates/my_db-sync.sql node2 $DC2_IP node1 $DC1_IP

    echo "✅ PostgreSQL replication setup complete!"
