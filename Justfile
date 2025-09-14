#!/usr/bin/env just --justfile

# Cloud VM Provisioner - Justfile
# This replicates the functionality of ./cli script

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
    
    # After successful terraform apply, create instance detail files
    echo "📋 Creating instance detail files..."
    
    # Check if terraform outputs exist
    if [ "$(terraform output -json 2>/dev/null)" = "{}" ]; then
        echo "❌ No terraform outputs found after apply"
        exit 1
    fi
    
    # Get all outputs
    instance_ipv4s=$(terraform output -json instance_ipv4s 2>/dev/null) || { echo "❌ instance_ipv4s output not found"; exit 1; }
    instance_usernames=$(terraform output -json instance_usernames 2>/dev/null) || { echo "❌ instance_usernames output not found"; exit 1; }
    instance_ssh_ports=$(terraform output -json instance_ssh_ports 2>/dev/null) || { echo "❌ instance_ssh_ports output not found"; exit 1; }
    
    # Create instance detail files for each instance
    echo "$instance_ipv4s" | jq -r 'keys[]' | while read -r instance_name; do
        echo "💾 Creating details file for instance: $instance_name"
        
        instance_ipv4=$(echo "$instance_ipv4s" | jq -r --arg name "$instance_name" '.[$name]')
        instance_username=$(echo "$instance_usernames" | jq -r --arg name "$instance_name" '.[$name]')
        instance_ssh_port=$(echo "$instance_ssh_ports" | jq -r --arg name "$instance_name" '.[$name]')
        
        # Validate that we got actual values (not null)
        if [ "$instance_ipv4" = "null" ] || [ -z "$instance_ipv4" ]; then
            echo "❌ No IP address found for instance '$instance_name'"
            continue
        fi
        
        if [ "$instance_username" = "null" ] || [ -z "$instance_username" ]; then
            echo "❌ No username found for instance '$instance_name'"
            continue
        fi
        
        if [ "$instance_ssh_port" = "null" ] || [ -z "$instance_ssh_port" ]; then
            echo "❌ No SSH port found for instance '$instance_name'"
            continue
        fi
        
        # Create instance-specific details file
        cat > {{ script_path }}/.instance_details_${instance_name} << EOF
    export INSTANCE_NAME="$instance_name"
    export INSTANCE_IPV4="$instance_ipv4"
    export INSTANCE_USERNAME="$instance_username"
    export INSTANCE_SSH_PORT="$instance_ssh_port"
    EOF
        
        echo "✅ Instance details saved for '$instance_name':"
        echo "   IP: $instance_ipv4"
        echo "   Username: $instance_username"
        echo "   SSH Port: $instance_ssh_port"
    done
    
    echo "🎉 All instance detail files created successfully!"

# Wait for host and accept SSH key
wait-and-accept: vm
    #!/usr/bin/env bash
    set -e

    if [ -z "$INSTANCE_NAME" ]; then
        echo "❌ INSTANCE_NAME not set. Please set it before running this command."
        echo "   Example: INSTANCE_NAME=myvm just wait-and-accept"
        exit 1
    fi

    # Load instance details from instance-specific file
    details_file="{{ script_path }}/.instance_details_${INSTANCE_NAME}"
    if [ ! -f "$details_file" ]; then
        echo "❌ Instance details file not found: $details_file"
        echo "   Have you run 'just vm' and does instance '$INSTANCE_NAME' exist?"
        exit 1
    fi
    
    source "$details_file"
    
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
connect: wait-and-accept
    #!/usr/bin/env bash
    set -e

    if [ -z "$INSTANCE_NAME" ]; then
        echo "❌ INSTANCE_NAME not set. Please set it before running this command."
        echo "   Example: INSTANCE_NAME=myvm just connect"
        exit 1
    fi

    # Load instance details from instance-specific file
    details_file="{{ script_path }}/.instance_details_${INSTANCE_NAME}"
    if [ ! -f "$details_file" ]; then
        echo "❌ Instance details file not found: $details_file"
        echo "   Have you run 'just vm' and does instance '$INSTANCE_NAME' exist?"
        exit 1
    fi
    
    source "$details_file"

    ssh -p ${INSTANCE_SSH_PORT} ${INSTANCE_USERNAME}@${INSTANCE_IPV4}
