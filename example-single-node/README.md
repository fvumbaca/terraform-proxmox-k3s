# Single-node k3s example

This is an alternative to the multi-node example in `../example`. It deploys a
single large k3s VM on the Proxmox host `lagrange` (`10.0.6.0`), with the
control plane and workloads on the same node.

## Summary

Target hardware: a single Proxmox host `lagrange` — Intel Xeon E5-2699 v3
(18 cores / 36 threads), 251 GiB RAM, ZFS `fast-local` (~955 GiB) and
`local-lvm` (~365 GiB).

### VM
- **1 k3s node** (`32 cores / 200 GiB`, 600G on `fast-local`) running the
  embedded-etcd control plane and all workloads.
- The node is **untainted** (`master_taints = []`), so regular pods schedule
  there.
- The support VM is disabled (`support_node_enabled = false`).
- Longhorn is disabled; CNPG uses the k3s `local-path` provisioner.

Total: 32 vCPUs / 200 GiB RAM / 600 GiB `fast-local`, leaving ~4 threads and
~35 GiB for Proxmox + the 16 GiB ZFS ARC.

### Pod capacity
The kubelet `max-pods` limit is raised from the default 110 to **250** via
`--kubelet-arg=max-pods=250`. The default per-node `/24` pod CIDR has ~254 IPs,
so 250 fits without changing the node CIDR mask.

For pods requesting 100m CPU / 128Mi memory, the 32 vCPUs allow roughly
320 pods by CPU, so the 250-pod limit is the binding constraint. For larger
pods, CPU/memory requests determine the practical count.

### Networking
- Node: `10.0.6.9`
- API VIP: `10.0.6.15`
- MetalLB pool: `10.0.6.100-10.0.6.119`
- LAN gateway `10.0.0.1`, LAN `10.0.0.0/8`

## Usage

```sh
cd example-single-node
cp ../example/backend.hcl.example backend.hcl   # fill in B2 credentials
cp ../example/secrets.auto.tfvars secrets.auto.tfvars  # Proxmox token
terraform init -backend-config=backend.hcl
terraform apply
```

The kubeconfig is written to `~/.kube/lagrange-k3s-single.yaml`.

## Notes

- This example uses its own Terraform state key
  (`lagrange-k3s-single/terraform.tfstate`) and its own VM IDs/IPs, so it does
  not conflict with the multi-node example's state.
- It cannot run at the same time as the multi-node example on the same host:
  the single node uses 600G of `fast-local`, and the multi-node example uses
  ~672G, exceeding the ~955G pool.
- The MetalLB manifests are generated into the shared `gitops/infrastructure`
  tree. Re-run `terraform apply` after changing the pool to regenerate them.
