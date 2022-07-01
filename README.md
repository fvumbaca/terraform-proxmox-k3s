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
- SSH agent configured for a private key to authenticate to K3s nodes

## Usage

> Take a look at the complete auto-generated docs on the
[Official Registry Page](https://registry.terraform.io/modules/fvumbaca/k3s/proxmox/latest).


Set up Terraform vars in `terraform.tfvars`:

```terraform
pm_api_url = "https://my.pve.server:8006/api2/json"
pm_api_token_id = "my-terraform-api-token@pve!terraform-ve2"
pm_api_token_secret = "my-api-secret"

vm_defaults = {
  cores = 2
  ciuser = "terraform"
  cipassword = "passwordtosetforCloudInitUser"
  nameserver = "10.41.0.1"
  searchdomain = "terraform.lab"
  target_node = "ve2"
  target_pool = "k8s"
  image_id = "template-cloudinit-ubuntu2104"
  full_clone = false
  firewall = false
  disk_size = "20G"
  memory = 2048
  storage_id = "zfs"
  subnet = "10.41.0.0/16"
  gw = "10.41.0.1"
  network_bridge = "vmbr1"
  network_tag = 2000
  # put your authorized_keys content below this line, before the end-of-file marker
  authorized_keys = <<EOF
    ssh-rsa AAAAB3N...mkbNl user@host
    EOF
}
``` 

```terraform
terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "2.9.3"
    }

    macaddress = {
      source = "ivoronin/macaddress"
      version = "0.3.0"
    }
  }

  experiments = [module_variable_optional_attrs]
}

locals {
  node_pools = [
    merge(var.vm_defaults, {
      name = "compute"
      size = 12
      subnet = "10.41.2.0/24"
      memory = 2048
    }),
    merge(var.vm_defaults, {
      name = "mem"
      size = 2
      subnet = "10.41.3.0/24"
      memory = 4096
    })
  ]
} 

module "k3s" {
  source  = "github.com/jan-tee/terraform-proxmox-k3s"
  # source = "./terraform-proxmox-k3s/"
  # version = ">= 0.0.0, < 1.0.0" # Get latest 0.X release

  cluster_name = "demo"
  lan_subnet = "10.41.0.0/16"

  support_node_settings = merge(var.vm_defaults, {
    memory = 2048
  })

  # Disable default traefik and servicelb installs for metallb and traefik 2
  k3s_disable_components = [
    "traefik",
    "servicelb"
  ]

  master_nodes_count = 2
  master_node_settings = merge(var.vm_defaults, {
    memory = 4096
  })

  control_plane_subnet = "10.41.1.0/24"
  node_pools = local.node_pools 
}

output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig
  sensitive = true
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

- [Basic cluster example](example) // not updated yet!
- [How to roll (update) your nodes](docs/roll-node-pools.md)

## Why use nodepools and subnets?

This module is designed with nodepools and subnets to allow for changes to the
cluster composition in the future. If later on, you want to add another master
or worker node, you can do so without needing to teardown/modify existing
nodes. Nodepools are key if you plan to support nodes with different nodepool
capabilities in the future without impacting other nodes.

## Todo

- [ ] Add variable to allow workloads on master nodes
