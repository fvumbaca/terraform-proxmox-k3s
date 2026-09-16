# Renders the MetalLB GitOps manifests from variables and writes them into the
# GitOps tree. The module is pure templating (no cluster interaction); run it to
# regenerate the manifests that Flux syncs.

locals {
  controllers_dir = "${var.output_dir}/controllers/metallb"
  config_dir      = "${var.output_dir}/config/metallb"

  common_vars = {
    namespace              = var.namespace
    pool_name              = var.pool_name
    pool_addresses         = var.pool_addresses
    l2_advertisement_name  = var.l2_advertisement_name
    interfaces             = var.interfaces
    chart_version          = var.chart_version
    helm_repo_url          = var.helm_repo_url
    controller_replicas    = var.controller_replicas
    auto_assign            = var.auto_assign
  }
}

resource "local_file" "controllers_namespace" {
  filename = "${local.controllers_dir}/namespace.yaml"
  content  = templatefile("${path.module}/templates/namespace.yaml.tftpl", local.common_vars)
}

resource "local_file" "controllers_helm_repository" {
  filename = "${local.controllers_dir}/helm-repository.yaml"
  content  = templatefile("${path.module}/templates/helm-repository.yaml.tftpl", local.common_vars)
}

resource "local_file" "controllers_helm_release" {
  filename = "${local.controllers_dir}/helm-release.yaml"
  content  = templatefile("${path.module}/templates/helm-release.yaml.tftpl", local.common_vars)
}

resource "local_file" "controllers_kustomization" {
  filename = "${local.controllers_dir}/kustomization.yaml"
  content  = templatefile("${path.module}/templates/controllers-kustomization.yaml.tftpl", local.common_vars)
}

resource "local_file" "config_ip_pool" {
  filename = "${local.config_dir}/ip-pool.yaml"
  content  = templatefile("${path.module}/templates/ip-pool.yaml.tftpl", local.common_vars)
}

resource "local_file" "config_l2_advertisement" {
  filename = "${local.config_dir}/l2-advertisement.yaml"
  content  = templatefile("${path.module}/templates/l2-advertisement.yaml.tftpl", local.common_vars)
}

resource "local_file" "config_kustomization" {
  filename = "${local.config_dir}/kustomization.yaml"
  content  = templatefile("${path.module}/templates/config-kustomization.yaml.tftpl", local.common_vars)
}
