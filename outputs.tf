
output "k3s_db_password" {
  value     = random_password.k3s-master-db-password.result
  sensitive = true
}

output "k3s_db_name" {
  value = var.support_node_settings.db_name
}

output "k3s_db_user" {
  value = var.support_node_settings.db_user
}

output "k3s_db_host" {
  value = "${local.support_node_ip}:3306"
}

output "root_db_password" {
  value     = random_password.support-db-password.result
  sensitive = true
}

output "support_node_ip" {
  value = local.support_node_ip
}

output "support_node_user" {
  value = var.support_node_settings.user
}

output "master_node_ips" {
  value = local.master_node_ips
}

output "k3s_server_token" {
  value     = random_password.k3s-server-token.result
  sensitive = true
}

output "k3s_master_node_ips" {
  value = local.master_node_ips
}

output "k3s_kubeconfig" {
  value     = replace(base64decode(replace(data.external.kubeconfig.result.kubeconfig, " ", "")), "server: https://127.0.0.1:6443", "server: https://${local.support_node_ip}:6443")
  sensitive = true
}

