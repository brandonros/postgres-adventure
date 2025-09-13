variable "hostname" {
  description = "Hostname for the instance"
  type        = string
}

variable "plan" {
  description = "Vultr instance plan"
  type        = string
  default     = "vc2-2c-4gb"
}

variable "region" {
  description = "Vultr region"
  type        = string
  default     = "atl"
}

variable "os_id" {
  description = "Operating system ID"
  type        = number
  default     = 2136
}

variable "ssh_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "user_password_hash" {
  description = "Hashed password for the debian user"
  type        = string
  default     = "$6$ovSvGqIVXC9lTasZ$T3YJyx/ew41tndVvqPCV3xZ6tpGTQyQJNXfn/mQ7s9xfvjUy.1g2xLccyW9CattET53xi9Z4REzoNY7iO3Bhw1"
}