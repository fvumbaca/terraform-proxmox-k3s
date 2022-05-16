# terraform-proxmox-k3s

A module for spinning up an expandable and flexible K3s server for your HomeLab.

## Features

- Fully automated. No need to remote into a VM; even for a kubeconfig
- Built in and automatically configured external loadbalancer (both K3s API and ingress)
- Static(ish) MAC addresses for reproducible DHCP reservations
- Node pools to easily scale and to handle many kinds of workloads
- Pure Terraform - no Ansible needed.

## Prerequisites

- A Proxmox node with sufficient capacity for all nodes
- A cloneable or template VM that supports Cloud-init and is based on Debian
  (ideally ubuntu server)
- 2 cidr ranges for master and worker nodes NOT handed out by DHCP (nodes are
  configured with static IPs from these ranges)

## Usage

> Take a look at the complete auto-generated docs on the
[Official Registry Page](https://registry.terraform.io/modules/fvumbaca/k3s/proxmox/latest).

```terraform
module "k3s" {
  source  = "fvumbaca/k3s/proxmox"
  version = ">= 0.0.0, < 1.0.0" # Get latest 0.X release

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

  # Disable default traefik and servicelb installs for metallb and traefik 2
  k3s_disable_components = [
    "traefik",
    "servicelb"
  ]

  master_nodes_count = 2
  master_node_settings = {
    cores = 2
    memory = 4096
  }

  # 192.168.0.200 -> 192.168.0.207 (6 available IPs for nodes)
  control_plane_subnet = "192.168.0.200/29"

  node_pools = [
    {
      name = "default"
      size = 2
      # 192.168.0.208 -> 192.168.0.223 (14 available IPs for nodes)
      subnet = "192.168.0.208/28"
    }
  ]
}
```

### Retrieve Kubeconfig

To get the kubeconfig for your new K3s first make sure to forward the module
output in your project's output:

```terraform
output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig
  sensitive = true
}
```

Finally output the config file:

```sh
terraform output -raw kubeconfig > config.yaml
# Test out the config:
kubectl --kubeconfig config.yaml get nodes
```

> Make sure your support node is routable from the computer you are running the
command on!

## Runbooks and Documents

- [Basic cluster example](example)
- [How to roll (update) your nodes](docs/roll-node-pools.md)

## Why use nodepools and subnets?

This module is designed with nodepools and subnets to allow for changes to the
cluster composition in the future. If later on, you want to add another master
or worker node, you can do so without needing to teardown/modify existing
nodes. Nodepools are key if you plan to support nodes with different nodepool
capabilities in the future without impacting other nodes.

## Todo

- [ ] Add variable to allow workloads on master nodes
