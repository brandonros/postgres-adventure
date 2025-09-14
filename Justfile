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

# Setup PostgreSQL replication between dc1 and dc2
setup-replication: (wait-and-accept "dc1") (wait-and-accept "dc2")
    #!/usr/bin/env bash
    set -e

    echo "🔄 Setting up PostgreSQL replication..."

    # Get instance details from terraform
    echo "📋 Loading instance details from terraform..."
    cd {{ script_path }}/terraform

    DC1_IP=$(terraform output -json instance_ipv4s | jq -r '.["dc1"]')
    DC1_USERNAME=$(terraform output -json instance_usernames | jq -r '.["dc1"]')
    DC1_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["dc1"]')

    DC2_IP=$(terraform output -json instance_ipv4s | jq -r '.["dc2"]')
    DC2_USERNAME=$(terraform output -json instance_usernames | jq -r '.["dc2"]')
    DC2_SSH_PORT=$(terraform output -json instance_ssh_ports | jq -r '.["dc2"]')

    echo "   DC1: $DC1_IP"
    echo "   DC2: $DC2_IP"

    # Wait for PostgreSQL pods to be ready
    echo "⏳ Waiting for PostgreSQL pod on dc1 to be ready..."
    while ! ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl get pod postgresql-0 -n postgresql 2>/dev/null | grep -q "1/1.*Running"'; do
        echo "   Waiting for postgresql-0 pod on dc1..."
        sleep 2
    done
    echo "✅ PostgreSQL pod on dc1 is ready"

    echo "⏳ Waiting for PostgreSQL pod on dc2 to be ready..."
    while ! ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl get pod postgresql-0 -n postgresql 2>/dev/null | grep -q "1/1.*Running"'; do
        echo "   Waiting for postgresql-0 pod on dc2..."
        sleep 2
    done
    echo "✅ PostgreSQL pod on dc2 is ready"

    # Additional check: wait for PostgreSQL service to be actually accepting connections
    echo "⏳ Waiting for PostgreSQL service on dc1 to accept connections..."
    while ! ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres -c \"SELECT 1\" > /dev/null 2>&1"'; do
        echo "   Waiting for PostgreSQL service on dc1..."
        sleep 2
    done
    echo "✅ PostgreSQL service on dc1 is accepting connections"

    echo "⏳ Waiting for PostgreSQL service on dc2 to accept connections..."
    while ! ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres -c \"SELECT 1\" > /dev/null 2>&1"'; do
        echo "   Waiting for PostgreSQL service on dc2..."
        sleep 2
    done
    echo "✅ PostgreSQL service on dc2 is accepting connections"

    cd {{ script_path }}

    # Step 1: Setup postgres database on both nodes
    echo "🗄️  Setting up postgres database on dc1..."
    cat sql/node1-postgres-setup.sql | ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres"'

    echo "🗄️  Setting up postgres database on dc2..."
    cat sql/node2-postgres-setup.sql | ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres"'

    # Step 2: Setup my_db database with pglogical on both nodes
    echo "🔧 Setting up my_db with pglogical on dc1..."
    cat sql/node1-my_db-setup.sql | sed 's/__NODE1_IP__/'$DC1_IP'/g; s/__NODE2_IP__/'$DC2_IP'/g' | \
        ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'

    echo "🔧 Setting up my_db with pglogical on dc2..."
    cat sql/node2-my_db-setup.sql | sed 's/__NODE1_IP__/'$DC1_IP'/g; s/__NODE2_IP__/'$DC2_IP'/g' | \
        ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'

    # Step 3: Sync replication
    echo "🔄 Syncing replication on dc1..."
    cat sql/node1-my_db-sync.sql | sed 's/__NODE1_IP__/'$DC1_IP'/g; s/__NODE2_IP__/'$DC2_IP'/g' | \
        ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'

    echo "🔄 Syncing replication on dc2..."
    cat sql/node2-my_db-sync.sql | sed 's/__NODE1_IP__/'$DC1_IP'/g; s/__NODE2_IP__/'$DC2_IP'/g' | \
        ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'

    echo "✅ PostgreSQL replication setup complete!"
