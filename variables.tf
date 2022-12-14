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

variable "default_node_settings" {
  type = object({
    cores           = optional(number, 2),
    sockets         = optional(number, 1),
    disk_type       = optional(string, "scsi"),
    storage_id      = string,
    disk_size       = optional(string, "10G"),
    firewall        = optional(bool, true),
    image_id        = string,
    full_clone      = bool,
    memory          = number,
    target_pool     = optional(string, "local-lvm")
    nameserver      = string,
    searchdomain    = string
    network_bridge  = optional(string, "vmbr0"),
    network_tag     = optional(number, -1),
    subnet          = string,
    gw              = string,
    target_node     = optional(string),
    target_pool     = string,
    authorized_keys = string
    ciuser          = string
  })
}

variable "support_node_settings" {
  type = object({
    authorized_keys = optional(string),
    cores           = optional(number),
    db_name         = optional(string, "k3s"),
    db_user         = optional(string, "k3s"),
    disk_size       = optional(string),
    disk_type       = optional(string),
    firewall        = optional(bool),
    full_clone      = optional(bool),
    gw              = optional(string),
    image_id        = optional(string),
    ip_offset       = optional(number),
    memory          = optional(number),
    nameserver      = optional(string),
    network_bridge  = optional(string),
    network_tag     = optional(number),
    searchdomain    = optional(string),
    sockets         = optional(number),
    storage_id      = optional(string),
    target_node     = optional(string),
    target_pool     = optional(string),
    ciuser          = optional(string)
  })
}

variable "master_nodes_count" {
  description = "Number of master nodes."
  default     = 2
  type        = number
}

variable "master_node_settings" {
  type = object({
    authorized_keys = optional(string),
    cores           = optional(number),
    disk_size       = optional(string),
    disk_type       = optional(string),
    firewall        = optional(bool),
    full_clone      = optional(bool),
    gw              = optional(string),
    image_id        = optional(string),
    subnet          = optional(string),
    ip_offset       = optional(number),
    memory          = optional(number),
    nameserver      = optional(string),
    network_bridge  = optional(string),
    network_tag     = optional(number),
    searchdomain    = optional(string),
    sockets         = optional(number),
    storage_id      = optional(string),
    target_node     = optional(string),
    target_pool     = optional(string),
    ciuser          = optional(string)
  })
}

variable "node_pools" {
  description = "Node pool definitions for the cluster."
  type = list(object({
    name            = string,
    size            = number,
    taints          = optional(list(string)),
    authorized_keys = optional(string),
    cores           = optional(number),
    disk_size       = optional(string),
    disk_type       = optional(string),
    firewall        = optional(bool),
    full_clone      = optional(bool),
    gw              = optional(string),
    image_id        = optional(string),
    subnet          = optional(string),
    ip_offset       = optional(number),
    memory          = optional(number),
    nameserver      = optional(string),
    network_bridge  = optional(string),
    network_tag     = optional(number),
    searchdomain    = optional(string),
    sockets         = optional(number),
    storage_id      = optional(string),
    target_node     = optional(string),
    target_pool     = optional(string),
    ciuser          = optional(string)
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

variable "insecure_registries" {
  type        = list(string)
  description = "FQDNs of 'insecure' (private, untrusted CA signed cert, or plaintext HTTP) Docker registries that should be accessible to k3s"
  default     = []
}