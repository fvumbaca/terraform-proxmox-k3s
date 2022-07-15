variable "pm_api_url" {
  type = string
}

variable "pm_api_token_id" {
  type = string
}

variable "pm_api_token_secret" {
  type = string
}

variable "ciuser" {
  type = string
}

variable "vm_defaults" {
  type = object({
    vcpus = optional(number),
    cores = optional(number),
    sockets = optional(number),
    storage_id = string,
    disk_type = optional(string),
    disk_size = optional(string),
    firewall = optional(bool),
    image_id = string,
    full_clone = bool,
    memory = number,
    balloon = number,
    target_pool = optional(string)

    nameserver = string,
    searchdomain = string
    network_bridge = optional(string),
    network_tag = optional(number),
    subnet = optional(string),
    gw = string,

    target_node = optional(string),
    target_pool = string,
    authorized_keys = string
  })
} 
