# terraform-proxmox-k3s

## Features

- Fully automated. No need to remote into a VM; even for a kubeconfig
- Built in and automatically configured external (to the cluster) loadbalancer
- Static(ish) MAC addresses for reproducible DHCP reservations
- Node pools to easily scale and to handle many kinds of workloads
- Pure Terraform - no Ansible needed.

## Usage

> Take a look at the complete auto-generated docs on the
[Official Registry Page](https://registry.terraform.io/modules/fvumbaca/k3s/proxmox/latest).

```terraform
module "k3s" {
  source  = "fvumbaca/k3s/proxmox"
  version = "0.0.0"

  authorized_keys_file = "authorized_keys"

  proxmox_node = "my-proxmox-node"

  node_template = "ubuntu-template"
  proxmox_resource_pool = "my-k3s"

  network_gateway = "192.168.0.1"
  lan_subnet = "192.168.0.0/24"

  support_node_settings = {
    cores = 2
    memory = 4096
  }

  master_nodes_count = 2
  master_node_settings = {
    cores = 2
    memory = 4096
  }

  # 192.168.0.200 -> 192.168.0.207 (6 nodes)
  control_plane_subnet = "192.168.0.200/29"

  node_pools = [
    {
      name = "default"
      size = 2
      # 192.168.0.208 -> 192.168.0.223 (14 nodes)
      subnet = "192.168.0.208/28" # 14 ips
    }
  ]
}
```

## Todo

- [ ] Setup external nginx load balancer to stream to traefik
- [ ] Handle LAN subnet settings better
