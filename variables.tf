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
    cores          = optional(number),
    sockets        = optional(number),
    memory         = optional(number),
    balloon        = optional(number),
    storage_type   = optional(string),
    storage_id     = optional(string),
    disk_size      = optional(string),
    image_id       = string,
    authorized_keys = string,
    db_name        = optional(string),
    db_user        = optional(string),
    network_bridge = optional(string),
    network_tag    = optional(number),
    full_clone     = optional(bool),
    firewall       = optional(bool),
    nameserver     = string,
    searchdomain   = string,
    gw             = string,
    target_node    = string,
    target_pool    = string
  })
}

variable "master_nodes_count" {
  description = "Number of master nodes."
  default     = 2
  type        = number
}

variable "master_node_settings" {
  type = object({
    cores          = optional(number),
    sockets        = optional(number),
    memory         = optional(number),
    balloon        = optional(number),
    storage_type   = optional(string),
    storage_id     = optional(string),
    disk_size      = optional(string),
    image_id       = string,
    authorized_keys = string,
    network_bridge = optional(string),
    network_tag    = optional(number),
    full_clone     = optional(bool),
    firewall       = optional(bool)
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

    name   = string,
    size   = number,
    subnet = string,

    taints = optional(list(string)),

    cores        = optional(number),
    sockets      = optional(number),
    memory       = optional(number),
    balloon       = optional(number),
    image_id       = string,
    storage_type = optional(string),
    storage_id   = optional(string),
    disk_size    = optional(string),
    authorized_keys = string,
    network_tag  = optional(number),
    full_clone   = optional(bool),
    firewall     = optional(bool),

    nameserver     = string,
    searchdomain   = string,
    gw             = string

    template = optional(string),

    network_bridge = optional(string),

    target_node    = string,
    target_pool    = string

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

variable "private_registry_url" {
  type = string
  description = "FQDN of a private Docker registry that should be accessible to k3s"
  default = null
}