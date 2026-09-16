variable "pool_name" {
  description = "Name of the MetalLB IPAddressPool."
  type        = string
  default     = "default-pool"
}

variable "pool_addresses" {
  description = <<-EOF
  List of address ranges/CIDRs for the pool, e.g. ["10.0.5.80-10.0.5.99"].
  These MUST be free on the L2 segment (outside DHCP and any VM assignments).
  EOF
  type        = list(string)

  validation {
    condition     = length(var.pool_addresses) > 0
    error_message = "pool_addresses must contain at least one range/CIDR."
  }
}

variable "namespace" {
  description = "Namespace for MetalLB (controller + config)."
  type        = string
  default     = "metallb-system"
}

variable "l2_advertisement_name" {
  description = "Name of the L2Advertisement resource."
  type        = string
  default     = "default"
}

variable "interfaces" {
  description = <<-EOF
  Guest-side interfaces to advertise on. Empty list = all interfaces (MetalLB
  default). Set e.g. ["eth0"] to pin advertisement to a specific NIC.
  EOF
  type        = list(string)
  default     = []
}

variable "chart_version" {
  description = "MetalLB Helm chart version constraint."
  type        = string
  default     = ">=0.14.0 <0.15.0"
}

variable "helm_repo_url" {
  description = "Helm repository URL for the MetalLB chart."
  type        = string
  default     = "https://metallb.github.io/metallb"
}

variable "controller_replicas" {
  description = "Replicas for the MetalLB controller."
  type        = number
  default     = 2
}

variable "auto_assign" {
  description = "Auto-assign pool addresses to LoadBalancer services."
  type        = bool
  default     = true
}

variable "output_dir" {
  description = <<-EOF
  Directory (relative to the calling module) where the rendered GitOps manifests
  are written. The module creates <output_dir>/controllers/metallb and
  <output_dir>/config/metallb.
  EOF
  type        = string
}
