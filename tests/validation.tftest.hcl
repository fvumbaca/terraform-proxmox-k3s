# Native Terraform tests for the module's validation / local logic.
# The proxmox provider is mocked so no live PVE API is required; the random
# provider runs for real (password generation needs no network).

mock_provider "proxmox" {}

run "valid_vip_config" {
  command = plan

  variables {
    authorized_keys_file = "tests/fixtures/test_key.pub"
    ssh_agent_auth       = true
    network_gateway      = "10.10.1.1"
    lan_subnet           = "10.10.1.1/16"
    control_plane_subnet = "10.10.2.0/29"
    cluster_name         = "test"
    template_vm_id       = 8003
    vm_id_start          = 900
    api_vip              = "10.10.9.99"
    vrrp_auth_pass       = "k3svip1"
    node_pools           = []

    master_nodes = [
      { target_node = "pve", cores = 2, sockets = 1, memory = 2048, storage_id = "local-lvm", disk_size = "24G", user = "k3s", network_bridge = "vmbr0", network_tag = -1 },
      { target_node = "pve", cores = 2, sockets = 1, memory = 2048, storage_id = "local-lvm", disk_size = "24G", user = "k3s", network_bridge = "vmbr0", network_tag = -1 },
    ]
  }

  assert {
    condition     = output.api_endpoint == "10.10.9.99"
    error_message = "api_endpoint must be the VIP when api_vip is set."
  }

  assert {
    condition = (
      contains(output.effective_no_proxy, "10.42.0.0/16") &&
      contains(output.effective_no_proxy, "10.43.0.0/16") &&
      contains(output.effective_no_proxy, "10.10.2.0/29") &&
      contains(output.effective_no_proxy, "10.10.9.99")
    )
    error_message = "effective_no_proxy must include the pod/service CIDRs, the control-plane subnet and the VIP."
  }
}

run "no_vip_uses_first_master" {
  command = plan

  variables {
    authorized_keys_file = "tests/fixtures/test_key.pub"
    ssh_agent_auth       = true
    network_gateway      = "10.10.1.1"
    lan_subnet           = "10.10.1.1/16"
    control_plane_subnet = "10.10.2.0/29"
    cluster_name         = "test"
    template_vm_id       = 8003
    vm_id_start          = 900
    api_vip              = null
    node_pools           = []

    master_nodes = [
      { target_node = "pve", cores = 2, sockets = 1, memory = 2048, storage_id = "local-lvm", disk_size = "24G", user = "k3s", network_bridge = "vmbr0", network_tag = -1 },
    ]
  }

  assert {
    condition     = output.api_endpoint == cidrhost("10.10.2.0/29", 1)
    error_message = "api_endpoint must fall back to the first master when no VIP is set."
  }
}

run "vip_collision_detected" {
  command = plan

  variables {
    authorized_keys_file = "tests/fixtures/test_key.pub"
    ssh_agent_auth       = true
    network_gateway      = "10.10.1.1"
    lan_subnet           = "10.10.1.1/16"
    control_plane_subnet = "10.10.2.0/29"
    cluster_name         = "test"
    template_vm_id       = 8003
    vm_id_start          = 900
    # Deliberately collide with the first master's IP (control_plane_subnet host 1).
    api_vip        = cidrhost("10.10.2.0/29", 1)
    vrrp_auth_pass = "k3svip1"
    node_pools     = []

    master_nodes = [
      { target_node = "pve", cores = 2, sockets = 1, memory = 2048, storage_id = "local-lvm", disk_size = "24G", user = "k3s", network_bridge = "vmbr0", network_tag = -1 },
    ]
  }

  expect_failures = [check.api_vip_collision]
}
