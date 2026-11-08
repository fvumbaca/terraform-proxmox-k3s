# terraform-proxmox-k3s-multi-node

This is an example project for setting up your own K3s cluster at home.

## Summary

Target hardware: a single Proxmox host `lagrange` (`10.0.6.0`) — Intel Xeon
E5-2699 v3 (18 cores / 36 threads), 251 GiB RAM, ZFS `fast-local` (~955 GiB)
and `local-lvm` (~365 GiB).

### VMs
This will spin up:

- 1 master node (`8 cores / 16 GiB`, 48G on `local-lvm`) running the embedded-etcd control plane. It is tainted (`CriticalAddonsOnly:NoExecute`), so only critical system pods schedule there.
- 4 general-purpose workers (`4 cores / 24 GiB`, 64G on `fast-local`), one per pool `pool2`..`pool5`.
- 1 dedicated CNPG database worker (`8 cores / 64 GiB`, 100G boot + 300G Longhorn data disk on `fast-local`), in pool `db`. It is labeled `workload=cnpg` and tainted `dedicated=db:NoSchedule` so only CloudNativePG pods land there.
- The support VM is disabled (`support_node_enabled = false`) because embedded etcd removes the MariaDB dependency.

Total: 32 vCPUs / 176 GiB RAM / ~672 GiB `fast-local` + 48 GiB `local-lvm`,
leaving headroom for the Proxmox host and ZFS ARC (capped at 16 GiB).

### Networking

- Control-plane block `10.0.6.16/29`: support `.16` (unused), master `.17`, API VIP `.23`.
- General worker pools on `10.0.6.24/29`, `.32/29`, `.40/29`, `.48/29` (workers `.25`, `.33`, `.41`, `.49`).
- CNPG DB pool on `10.0.6.64/29` (worker `.65`).
- MetalLB pool `10.0.6.80-10.0.6.99`.
- All VMs are addressed with the `/8` mask from `lan_subnet`; the `/29` blocks are just non-overlapping allocation ranges.

> Note: To eliminate potential IP clashing with existing computers on your
network, it is **STRONGLY** recommended that you take IPs out of your DHCP server's rotation. Otherwise other computers
in your network may already be using these IPs and that will create conflicts!
Check your router's manual or google it for a step-by-step guide.

## Usage

To run this example, make sure you `cd` to this directory in your terminal,
then
1. Ensure your SSH keypair exists at `~/.ssh/id_ed25519` /
   `~/.ssh/id_ed25519.pub` (the module reads those paths directly). If you use
   a different key, update `authorized_keys_file` and
   `authorized_private_key_file` in `main.tf`.
2. Find your Proxmox API. It should look something like
   `https://192.168.1.200:8006/api2/json`. Once you found it, update the
   `endpoint` in the `provider proxmox` section of `main.tf` (this example
   points at `https://10.0.6.0:8006/`, the `lagrange` host).
3. Provide the Proxmox API token. The example reads it from the gitignored
   `secrets.auto.tfvars`:
   ```hcl
   pm_token_id     = "root@pam!k3s"
   pm_token_secret = "your-token-secret"
   ```
   Alternatively export `TF_VAR_pm_token_id` and `TF_VAR_pm_token_secret`.

   > Find other ways to auth to proxmox by reading [the provider's docs](https://registry.terraform.io/providers/bpg/proxmox/latest/docs).
4. Run `terraform init` (only needs to be done the first time)
5. Run `terraform apply`
6. Review the plan. Make sure it is doing what you expect!
7. Enter `yes` in the prompt and wait for your cluster to spin up.
8. The module writes the kubeconfig to `example/kubeconfig.yaml` at apply time
   (server = API VIP `10.0.6.23`).
9. Make all your `kubectl` commands work with your cluster for your terminal
   session by running `export KUBECONFIG="./kubeconfig.yaml"`. If you want to add
   the context more permanently globally, [refer to the document on managing Kubernetes configs](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/#create-a-second-configuration-file).

## Remote state (Backblaze B2)

`main.tf` is configured with an S3 backend pointed at Backblaze B2 (S3-compatible).
The non-sensitive settings (bucket, key, region, endpoint) are committed in the
`backend "s3"` block; the **credentials are not** — supply them at init time.

1. Set the bucket/region/endpoint in the `backend "s3"` block of `main.tf` to
   match your B2 bucket (e.g. `us-west-004` -> `https://s3.us-west-004.backblazeb2.com`).
   The state key is `lagrange-k3s/terraform.tfstate`, a fresh state for the new
   single-host deployment (the old `opti-k3s` state is intentionally left alone).
2. Create a B2 Application Key scoped to that bucket, then copy the template:
   ```bash
   cp backend.hcl.example backend.hcl   # Windows: copy backend.hcl.example backend.hcl
   ```
   and fill in `access_key` / `secret_key`. `backend.hcl` is gitignored.
3. **First-time migration** from the existing local `terraform.tfstate` to B2:
   ```bash
   terraform init -migrate-state -backend-config=backend.hcl
   ```
   This uploads the local state to the bucket and removes the local state file.
   Subsequent runs just use the remote state:
   ```bash
   terraform init -backend-config=backend.hcl
   ```
4. Alternatively, skip `backend.hcl` and use env vars:
   `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.

Notes:
- `skip_credentials_validation`, `skip_metadata_api_check`, `skip_region_validation`
  and `use_path_style` are required because B2 is not real AWS.
- Keep the B2 state bucket **versioned** (B2 keeps file versions) so you can recover
  a prior state if a bad apply overwrites it.
- To go back to local state later: `terraform init -migrate-state=false` is not a
  thing — instead `terraform state pull > terraform.tfstate` then remove the backend
  block and re-init with `-reconfigure`.
