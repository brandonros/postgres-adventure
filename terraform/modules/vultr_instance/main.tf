terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.0"
    }
  }
}

resource "vultr_ssh_key" "instance_ssh_key" {
  name    = "${var.hostname}_ssh_key"
  ssh_key = file(var.ssh_key_path)
}

resource "vultr_instance" "instance" {
  plan        = var.plan
  region      = var.region
  os_id       = var.os_id
  hostname    = var.hostname
  ssh_key_ids = [vultr_ssh_key.instance_ssh_key.id]
  
  user_data = <<EOF
#cloud-config
users:
  - name: debian
    gecos: "Debian"
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: ${var.user_password_hash}
    ssh_authorized_keys:
      - ${file(var.ssh_key_path)}
package_update: true
package_upgrade: true
packages:
  - curl
runcmd:
  # install k3s
  - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.33.4+k3s1" INSTALL_K3S_EXEC="server" sh -
  - systemctl enable k3s
  - systemctl start k3s
  # configure kubeconfig
  - mkdir -p /home/debian/.kube
  - k3s kubectl config view --raw > /home/debian/.kube/config
  - chmod 600 /home/debian/.kube/config
  - chown -R debian:debian /home/debian/.kube
  - echo "export KUBECONFIG=/home/debian/.kube/config" >> /home/debian/.bashrc
  # install k9s
  - curl -L -O https://github.com/derailed/k9s/releases/download/v0.50.9/k9s_linux_amd64.deb && apt install -y ./k9s_linux_*.deb && rm k9s_linux_*.deb
  # install postgres
  - curl -L -O https://raw.githubusercontent.com/brandonros/postgres-adventure/06f3aad305ad3ade170b699f0cb1d21d7acb74dd/manifests/postgresql.yaml && kubectl apply -f postgresql.yaml
EOF
}