variable "proxmox_node" {
  description = "Proxmox node to create VMs on."
  type        = string
  default     = ""
}
variable "proxmox_support_node" {
  description = "Proxmox node to create VMs on."
  type        = string
  default     = ""
}
variable "authorized_keys_file" {
  description = "Path to file containing public SSH keys for remoting into nodes."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
variable "authorized_private_key_file" {
  description = "Path to file containing private SSH keys for remoting into nodes."
  type        = string
  default     = "~/.ssh/id_rsa"
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

variable "master_node_target_nodes" {
  description = "Names of master nodes, distributes the master in order of this list. Must be one to one mapping."
  default     = []
  type        = list(string)
}
variable "support_node_settings" {
  description = "Default settings values for support nodes"
  type = object({
    cores          = number,
    sockets        = number,
    memory         = number,
    storage_type   = string,
    storage_id     = string,
    disk_size      = string,
    user           = string,
    db_user        = string,
    db_name        = string,
    network_bridge = string,
    network_tag    = number,
  })
  default = {
    cores   = 2
    sockets = 1
    memory  = 4096
    storage_type = "scsi"
    storage_id   = "local-lvm"
    disk_size    = "10G"
    user         = "support"
    network_tag  = -1
    db_name = "k3s"
    db_user = "k3s"
    network_bridge = "vmbr0"
  }
}
variable "master_node_settings" {
  description = "Default settings values for master nodes"
  type = object({
    cores          = number,
    sockets        = number,
    memory         = number,
    storage_type   = string,
    storage_id     = string,
    disk_size      = string,
    user           = string,
    network_bridge = string,
    network_tag    = number,
  })
  default = {
    cores          = 2
    sockets        = 1
    memory         = 4096
    storage_type   = "scsi"
    storage_id     = "local-lvm"
    disk_size      = "20G"
    user           = "k3s"
    network_bridge = "vmbr0"
    network_tag    = -1
    user           = "k3s"
  }
}


variable "node_pools" {
  description = "Node pool definitions for the cluster."
  type = list(object({
    size   = number,
    subnet = string,
    target_node  = string,
    node_pool_settings = object({
    name           = string,
    taints         = list(string),
    cores          = number,
    sockets        = number,
    memory         = number,
    storage_type   = string,
    storage_id     = string,
    disk_size      = string,
    user           = string,
    network_bridge = string,
    network_tag    = number,
  })
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
