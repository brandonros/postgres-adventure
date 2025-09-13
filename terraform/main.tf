variable "instances" {
  description = "Map of instance configurations"
  type = map(object({
    hostname = string
    plan     = optional(string)
    region   = optional(string)
  }))
  default = {
    dc1 = {
      hostname = "dc1"
      plan   = "vc2-2c-4gb"
      region = "atl"
    }
    dc2 = {
     hostname = "dc2"
     plan   = "vc2-2c-4gb"
     region = "atl"
    }
  }
}

module "instances" {
  for_each = var.instances
  source   = "./modules/vultr_instance"
  hostname = each.value.hostname

  # Override defaults if provided
  plan   = each.value.plan
  region = each.value.region
}

# Dynamic outputs for all instances
output "instance_usernames" {
  value = {
    for k, v in module.instances : k => v.instance_username
  }
}

output "instance_ipv4s" {
  value = {
    for k, v in module.instances : k => v.instance_ipv4
  }
}

output "instance_ssh_ports" {
  value = {
    for k, v in module.instances : k => v.instance_ssh_port
  }
}
