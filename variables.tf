variable "proxmox_nodes" {
  description = "Proxmox nodes to create VMs on."
  type        = list(string)
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

variable "master_node_settings" {
  type = object({
    cores          = optional(number, 2),
    sockets        = optional(number, 1),
    memory         = optional(number, 4096),
    onboot       = optional(bool, true)
    storage_type   = optional(string, "scsi"),
    storage_id     = optional(string, "local-lvm"),
    disk_size      = optional(string, "20G"),
    user           = optional(string, "k3s"),
    network_bridge = optional(string, "vmbr0"),
    network_tag    = optional(number, -1),
    iothread       = optional(number, 0)
  })
}

variable "node_pools" {
  description = "Node pool definitions for the cluster."
  type = list(object({
    zones  = list(string),
    name   = string,
    size   = number,
    subnet = string,
    template = string,

    taints = optional(list(string)),

    cores        = optional(number, 2),
    sockets      = optional(number, 1),
    memory       = optional(number, 4096),
    onboot       = optional(bool, true)
    storage_type = optional(string, "scsi"),
    storage_id   = optional(string, "local-lvm"),
    disk_size    = optional(string, "20G"),
    iothread     = optional(number, 0)
    user         = optional(string, "k3s"),
    network_tag  = optional(number, -1),

    network_bridge = optional(string, "vmbr0"),
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


variable "http_proxy" {
  default     = ""
  type        = string
  description = "http_proxy"
}

variable "nameserver" {
  default     = ""
  type        = string
  description = "nameserver"
}