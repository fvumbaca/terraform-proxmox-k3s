# terraform-proxmox-k3s

A module for spinning up an expandable and flexible K3s server for your HomeLab.

## Features

- Fully automated. No need to remote into a VM; even for a kubeconfig
- Built in and automatically configured external loadbalancer (both K3s API and ingress)
- Static(ish) MAC addresses for reproducible DHCP reservations
- Node pools to easily scale and to handle many kinds of workloads
- Pure Terraform - no Ansible needed.
- Support for a private Docker registry (requires changes on each node, performed by this module)

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

1. Set up Terraform vars in `terraform.tfvars`.  
   Use the file from (examples/)[examples/terraform.tfvars] as a starter.
1. Set up a `main.tf` to use the module. Edit as needed (for cluster size, node pool configuration).  
   Use the file from (examples/)[examples/main.tf] as a starter.
1. Run `terraform plan`, `terraform apply`.
1. Retrieve the `kubeconfig` file from the terraform outputs:  
  ```sh
  terraform output -raw kubeconfig > config.yaml
  # Test out the config:
  kubectl --kubeconfig config.yaml get nodes
  ```

> Make sure your support node is routable from the computer you are running the command on!

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
