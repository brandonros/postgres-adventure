output "instance_username" {
  value       = "debian"
  description = "Username for SSH connection"
}

output "instance_ipv4" {
  value       = vultr_instance.instance.main_ip
  description = "IPv4 address of the instance"
}

output "instance_ssh_port" {
  value       = 22
  description = "SSH port for the instance"
}

output "instance_id" {
  value       = vultr_instance.instance.id
  description = "Instance ID"
}