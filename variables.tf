variable "proxmox_node" {
  description = "Proxmox node to create VMs on."
  type        = string
}

variable "authorized_keys_file" {
  description = "Path to file containing public SSH keys for remoting into nodes."
  type        = string
}

variable "network_gateway" {
  description = "IP address of the network gateway."
  type        = string
  validation {
    # condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", var.network_gateway))
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", var.network_gateway))
    error_message = "The network_gateway value must be a valid ip."
  }
}

variable "lan_subnet" {
  description = <<EOF
Subnet used by the LAN network. Note that only the bit count number at the end
is acutally used, and all other subnets provided are secondary subnets.
EOF
  type        = string
  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", var.lan_subnet))
    error_message = "The lan_subnet value must be a valid cidr range."
  }
}

variable "control_plane_subnet" {
  description = <<EOF
EOF
  type        = string
  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", var.control_plane_subnet))
    error_message = "The control_plane_subnet value must be a valid cidr range."
  }
}

variable "cluster_name" {
  default     = "k3s"
  type        = string
  description = "Name of the cluster used for prefixing cluster components (ie nodes)."
}

variable "node_template" {
  type        = string
  description = <<EOF
Proxmox vm to use as a base template for all nodes. Can be a template or
another vm that supports cloud-init.
EOF
}

variable "proxmox_resource_pool" {
  description = "Resource pool name to use in proxmox to better organize nodes."
  type        = string
  default     = ""
}

variable "support_node_settings" {
  type = object({
    cores        = optional(number),
    sockets      = optional(number),
    memory       = optional(number),
    storage_type = optional(string),
    storage_id   = optional(string),
    disk_size    = optional(string),
    user         = optional(string),
    db_name      = optional(string),
    db_user      = optional(string),
  })
}

variable "master_nodes_count" {
  description = "Number of master nodes."
  default     = 2
  type        = number
}

variable "master_node_settings" {
  type = object({
    cores        = optional(number),
    sockets      = optional(number),
    memory       = optional(number),
    storage_type = optional(string),
    storage_id   = optional(string),
    disk_size    = optional(string),
    user         = optional(string),
  })
}

variable "node_pools" {
  description = "Node pool definitions for the cluster."
  type = list(object({

    name   = string,
    size   = number,
    subnet = string,

    taints = optional(list(string)),

    cores        = optional(number),
    sockets      = optional(number),
    memory       = optional(number),
    storage_type = optional(string),
    storage_id   = optional(string),
    disk_size    = optional(string),
    user         = optional(string),

    template = optional(string),
  }))
}
variable "api_hostnames" {
  description = "Alternative hostnames for the API server."
  type        = list(string)
  default     = []
}

variable "k3s_disable_components" {
  description = "List of components to disable. Ref: https://rancher.com/docs/k3s/latest/en/installation/install-options/server-config/#kubernetes-components"
  type        = list(string)
  default     = []
}
