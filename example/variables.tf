variable "default_node_settings" {
  type = object({
    cores           = optional(number, 2),
    sockets         = optional(number, 1),
    storage_id      = string,
    disk_type       = optional(string, "scsi"),
    disk_size       = optional(string),
    firewall        = optional(bool, false),
    image_id        = string,
    full_clone      = optional(bool, false),
    memory          = number,
    target_pool     = optional(string)
    nameserver      = string,
    searchdomain    = string
    network_bridge  = optional(string, "vmbr0"),
    network_tag     = optional(number, -1),
    subnet          = optional(string),
    gw              = string,
    target_node     = optional(string),
    target_pool     = string,
    authorized_keys = string,
    ciuser          = string,
  })
}

variable "node_pools" {
  type = list(object({
    name      = string,
    size      = number,
    subnet    = optional(string),
    ip_offset = number,
    memory    = optional(number),
    cores     = optional(number),
    sockets   = optional(number),
    disk_size = optional(string),
    node_labels = optional(list(string))
  }))
  description = "The definition of node pools to create"
}

variable "master_node_settings" {
  type = object({
    count     = optional(number, 2),
    subnet    = optional(string),
    ip_offset = number,
    memory    = optional(number),
    cores     = optional(number),
    sockets   = optional(number),
    disk_size = optional(string),
    node_labels = optional(list(string))
  })
  description = "The definition of master nodes"
}

variable "support_node_settings" {
  type = object({
    subnet    = optional(string),
    ip_offset = number,
    memory    = optional(number),
    cores     = optional(number),
    sockets   = optional(number),
    disk_size = optional(string)
  })
  description = "The definition of support node settings"
}

variable "cluster_name" {
  type = string
}

variable "insecure_registries" {
  type    = list(string)
  default = []
}