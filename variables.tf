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

variable "support_node_settings" {
  type = object({
    cores           = optional(number, 2),
    sockets         = optional(number, 1),
    memory          = optional(number, 4096),
    balloon         = optional(number, 4096),
    storage_type    = optional(string, "scsi"),
    storage_id      = optional(string, "local-lvm"),
    disk_size       = optional(string, "10G"),
    image_id        = string,
    authorized_keys = string,
    db_name         = optional(string, "k3s"),
    db_user         = optional(string, "krs"),
    network_bridge  = optional(string, "vmbr0"),
    network_tag     = optional(number, -1),
    ip_offset       = optional(number, 10),
    full_clone      = optional(bool, true),
    firewall        = optional(bool, true),
    nameserver      = string,
    searchdomain    = string,
    gw              = string,
    target_node     = string,
    target_pool     = string
  })
}

variable "master_nodes_count" {
  description = "Number of master nodes."
  default     = 2
  type        = number
}

variable "master_node_settings" {
  type = object({
    cores          = optional(number, 2),
    sockets        = optional(number, 1),
    memory         = optional(number, "4096"),
    balloon        = optional(number, "4096"),
    storage_type   = optional(string, "scsi"),
    storage_id     = optional(string, "local-lvm"),
    disk_size      = optional(string, "20G"),
    image_id       = string,
    authorized_keys = string,
    network_bridge = optional(string, "vmbr0"),
    network_tag    = optional(number, -1),
    ip_offset      = optional(number, 2),
    full_clone     = optional(bool, true),
    firewall       = optional(bool, true)
    nameserver     = string,
    searchdomain   = string,
    gw             = string,
    target_node    = string,
    target_pool    = string

  })
}

variable "node_pools" {
  description = "Node pool definitions for the cluster."
  type = list(object({
    name            = string,
    size            = number,
    subnet          = string,

    taints          = optional(list(string)),

    cores           = optional(number, 2),
    sockets         = optional(number, 1),
    memory          = optional(number, 4096),
    balloon         = optional(number, 4096),
    image_id        = string,
    storage_type    = optional(string, "scsi"),
    storage_id      = optional(string, "local-lvm"),
    disk_size       = optional(string, "20G"),
    authorized_keys = string,
    network_tag     = optional(number, -1),
    full_clone      = optional(bool, true),
    firewall        = optional(bool, true),

    nameserver      = string,
    searchdomain    = string,
    gw              = string

    template        = optional(string),

    network_bridge  = optional(string, "vmbr0"),
    ip_offset       = optional(number, 10),

    target_node     = string,
    target_pool     = string

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

variable "ciuser" {
  type = string
  description = "Cloud-Init User"
}

variable "insecure_registries" {
  type = list(string)
  description = "FQDNs of 'insecure' (private, untrusted CA signed cert, or plaintext HTTP) Docker registries that should be accessible to k3s"
  default = []
}