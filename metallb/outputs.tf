output "controllers_dir" {
  description = "Directory where the MetalLB controller manifests were written."
  value       = local.controllers_dir
}

output "config_dir" {
  description = "Directory where the MetalLB config manifests were written."
  value       = local.config_dir
}

output "rendered_ip_pool" {
  description = "Rendered IPAddressPool manifest (for inspection)."
  value       = templatefile("${path.module}/templates/ip-pool.yaml.tftpl", local.common_vars)
}

output "rendered_l2_advertisement" {
  description = "Rendered L2Advertisement manifest (for inspection)."
  value       = templatefile("${path.module}/templates/l2-advertisement.yaml.tftpl", local.common_vars)
}
