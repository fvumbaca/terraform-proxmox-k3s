# terraform-proxmox-k3s-multi-node

This is an example project for setting up your own K3s cluster at home.

## Summary

Target hardware: 9 identical micro PCs (i5-7500T = 4 cores / 4 threads, 16 GB RAM).

### VMs
This will spin up:

- 1 Support VM (1 core / 1 GB) co-located on `pve-prd0`. With embedded etcd it is a near-idle placeholder (no MariaDB).
- 3 master nodes on `pve-prd0`, `pve-prd1`, `pve-prd2` - HA embedded-etcd control plane. They are **unscheduled-taint-off** (`master_taints = []`), so they also run regular workloads: `master0` 3c/12G (shares the box with support), `master1`/`master2` 4c/12G.
- 6 worker nodes (4 cores / 12 GB each), one per remaining host `pve-prd3`..`pve-prd8`, each in its own single-node pool.

Because workloads share the master boxes, give them resource requests/limits so they can't starve etcd / the API server. Each VM also leaves a few GB of host RAM for Proxmox itself; if you use ZFS, cap the ARC (e.g. `zfs_arc_max=2147483648`).

### Networking

- Control-plane block `10.10.2.0/29`: support `10.10.2.0`, masters `10.10.2.1`-`10.10.2.3`, API VIP `10.10.2.7`.
- Worker pools on `10.10.2.8/29`, `.16/29`, `.24/29`, `.32/29`, `.40/29`, `.48/29` (one worker each: `.9`, `.17`, `.25`, `.33`, `.41`, `.49`).
- All VMs are addressed with the `/16` mask from `lan_subnet`; the `/29` blocks are just non-overlapping allocation ranges.

> Note: To eliminate potential IP clashing with existing computers on your
network, it is **STRONGLY** recommended that you take IPs out of your DHCP server's rotation. Otherwise other computers
in your network may already be using these IPs and that will create conflicts!
Check your router's manual or google it for a step-by-step guide.

## Usage

To run this example, make sure you `cd` to this directory in your terminal,
then
1. Copy your public key to the `authorized_keys` file. In most cases, you
   should be able to do this by running
   `cat ~/.ssh/id_rsa.pub > authorized_keys`.
2. Find your Proxmox API. It should look something like
   `https://192.168.1.200:8006/api2/json`. Once you found it, update the value
   in the `main.tf` file marked as `TODO` in the `provider proxmox` section.
3. Authenticate to the proxmox API **for the current terminal session** by setting the two variables:
  ```bash
  # Update these to be your proxmox user/password.
  # Note that you usually need to keep the @pam at the end of the user.
  export PM_API_TOKEN_ID='root@pam!k3s'
  export PM_API_TOKEN_SECRET="something-something-something-something"
  ```

  > Find other ways to auth to proxmox by reading [the provider's docs](https://registry.terraform.io/providers/bpg/proxmox/latest/docs).
4. Run `terraform init` (only needs to be done the first time)
5. Run `terraform apply`
6. Review the plan. Make sure it is doing what you expect!
7. Enter `yes` in the prompt and wait for your cluster to spin up.
8. Retrieve your kubecontext by running
   `terraform output -raw kubeconfig > config.yaml`
9. Make all your `kubectl` commands work with your cluster for your terminal
   session by running `export KUBECONFIG="config.yaml"`. If you want to add the
   context more perminantly globaly, [refer to the document on managing Kubernetes configs](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/#create-a-second-configuration-file).

## Remote state (Backblaze B2)

`main.tf` is configured with an S3 backend pointed at Backblaze B2 (S3-compatible).
The non-sensitive settings (bucket, key, region, endpoint) are committed in the
`backend "s3"` block; the **credentials are not** — supply them at init time.

1. Set the bucket/region/endpoint in the `backend "s3"` block of `main.tf` to
   match your B2 bucket (e.g. `us-west-004` -> `https://s3.us-west-004.backblazeb2.com`).
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
  and `force_path_style` are required because B2 is not real AWS.
- Keep the B2 state bucket **versioned** (B2 keeps file versions) so you can recover
  a prior state if a bad apply overwrites it.
- To go back to local state later: `terraform init -migrate-state=false` is not a
  thing — instead `terraform state pull > terraform.tfstate` then remove the backend
  block and re-init with `-reconfigure`.
