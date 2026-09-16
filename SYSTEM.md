# SYSTEM.md — k3s on Proxmox (terraform-proxmox-k3s-multinode)

Operational notes, architecture, and the full list of issues found & fixed while
bringing this cluster up on the `opti0`–`opti8` Proxmox cluster. Kept for future
reference / re-deploys.

## 1. What this is

A Terraform module that provisions a HA k3s cluster on Proxmox VE:

- 3 control-plane nodes (embedded etcd, stacked)
- 6 worker nodes (one per pool, `pool0`–`pool5`)
- Floating API VIP via keepalived
- Per-node Debian 13 (trixie) cloud-init templates (no shared storage required)

## 2. Topology / IP plan

| Role            | Node(s)        | IP(s)                          |
|-----------------|----------------|--------------------------------|
| PVE hosts       | opti0–opti8    | 10.0.5.1 – 10.0.5.9          |
| master0/1/2     | opti0/1/2      | 10.0.5.17 / .18 / .19        |
| API VIP         | floats (masters)| 10.0.5.23                    |
| pool0..5        | opti3..opti8   | 10.0.5.25/.33/.41/.49/.57/.65 |

- Control-plane subnet: `10.0.5.16/29`
- Worker pools: `10.0.5.24/29`, `.32/29`, `.40/29`, `.48/29`, `.56/29`, `.64/29`
- Gateway `10.0.0.1`, LAN `10.0.0.1/8`
- VM IDs: masters 902–904, workers 905–910, per-node templates 8000–8008
- Datastores: root disks on `local-lvm` (lvmthin), image import/download on `local` (dir)

## 3. Environment specifics (this deployment)

- Control machine: **Windows** (PowerShell 5.1). Terraform + OpenSSH client.
- Terraform binary: winget-installed `terraform.exe` (v1.16.x).
- SSH keypair: `~/.ssh/id_ed25519` (+ `.pub`), injected into all nodes.
- Proxmox API token: `root@pam!k3s-deployer` (in `example/secrets.auto.tfvars`, gitignored).
- Provider: `bpg/proxmox`, auth via `api_token = "<id>=<secret>"`.

## 4. Issues found & fixed (the important part)

### 4.1 CRLF line endings broke the install scripts (exit 2)
**Symptom:** every master's k3s install failed with `Process exited with status 2`;
`sh -n` reported `Syntax error: word unexpected (expecting "do")`.
**Cause:** the `.sh.tftpl` files were saved with Windows CRLF. The guest runs them
with `#!/bin/sh` (dash); the `\r` before `do`/`then` breaks dash parsing. It also
made the trace filename contain a literal `\r`.
**Fix:** convert `scripts/install-k3s.sh.tftpl`, `scripts/install-keepalived.sh.tftpl`,
and `config/keepalived.conf.tftpl` to **LF** line endings.
**Rule:** any shell script template rendered onto a Linux guest MUST be LF.

### 4.2 `wait_for_api` failed on the API's 401
**Symptom:** joiners (master1/2, workers) timed out in `wait_for_api` even though
the API was up.
**Cause:** the readiness probe used `curl -sfk .../healthz`. k3s's `/healthz`
returns **401** (auth-gated) on this setup, so `-f` made curl fail forever.
**Fix:** drop `-f` (`curl -sk ...`) so ANY HTTP response counts as "API reachable".
The join itself authenticates with the cluster token, so 401 on healthz is fine.

### 4.3 Debian first-boot apt lock
**Symptom:** `E: Could not get lock /var/lib/apt/lists/lock. It is held by process NNN (apt-get)`.
**Cause:** Debian 13 cloud images run `unattended-upgrades` + `apt-daily*` timers at
first boot, holding the apt/dpkg lock while our scripts (and the k3s installer) try
to `apt-get`.
**Fix:** in BOTH `install-k3s.sh.tftpl` and `install-keepalived.sh.tftpl`, before
any apt call:
`systemctl stop` + `systemctl mask` `unattended-upgrades` and the `apt-daily*`
units, then poll `fuser` on the lock files until released.

### 4.4 Proxmox firewall rule casing
**Symptom:** `HTTP 400 ... value 'IN' does not have a value in the enumeration 'in, out, forward, group'`.
**Cause:** the VRRP firewall rules used `type = "IN"`.
**Fix:** lowercase `type = "in"` (in `master_nodes.tf` and `support_node.tf`).

### 4.5 keepalived VRRP child crash (kernel incompat)
**Symptom:** keepalived `active`→`failed`; journal shows the VRRP child dying with a
netlink-attribute dump and a respawn loop.
**Cause:** keepalived 2.3.x + kernel 6.12 crashes when a tracked `vrrp_script`
(health check) is configured.
**Fix:** use a **minimal keepalived config with NO `vrrp_script`/`track_script`**.
The VIP still fails over on node failure via VRRP advertisement timeout; it just
does not move on a k3s-only failure. (Revisit if health-based failover is needed —
would require a keepalived build that doesn't crash on this kernel.)
Also: the VIP binds to the **guest** interface `eth0`, NOT the Proxmox host bridge
`vmbr0` (added `keepalived_interface` variable, default `eth0`).

### 4.6 kubeconfig fetch — platform-aware local-exec
**Symptom:** the kubeconfig `local-exec` failed on Windows with
`The filename, directory name, or volume label syntax is incorrect` /
`The system cannot find the path specified`.
**Cause:** the original used a local `> file` redirect and/or nested quotes that
`cmd.exe` cannot handle; `bash` on this box is a broken WSL stub.
**Fix (platform-agnostic pattern):**
- Run the `sed` rewrite + its `>` redirect **on the remote node** (inside double
  quotes, so the local shell never sees the `>`).
- `scp` the file down.
- Chain the two commands with `;` (works in PowerShell 5.1 and `/bin/sh`; note
  PowerShell 5.1 has no `&&`).
- Set the interpreter via `kubeconfig_interpreter` (PowerShell on Windows,
  `/bin/sh -c` on Unix). **Do not use `cmd.exe`** — it cannot nest double quotes.
- New variables: `scp_binary`, `ssh_null_device` (NUL on Windows, /dev/null on Unix),
  `kubeconfig_interpreter`.

## 5. End-to-end validation

A full `terraform destroy` (37 resources) followed by a fresh `terraform apply`
completed with **all 9 nodes Ready**, VIP active, system pods running, and the
kubeconfig written to `example/kubeconfig.yaml` pointing at the VIP. The pipeline
is reproducible from scratch.

## 6. How to run

```powershell
cd example
# secrets.auto.tfvars holds pm_token_id / pm_token_secret (gitignored)
terraform init
terraform apply -auto-approve
# kubeconfig -> example/kubeconfig.yaml (server = VIP)
```

Verify:
```bash
ssh k3s@10.0.5.17 'sudo k3s kubectl get nodes -o wide'
# expect: 3 control-plane/etcd masters + 6 workers, all Ready
```

## 7. GitOps scaffolding (Flux + MetalLB)

A GitOps tree lives in `gitops/` (see `gitops/README.md` for full bootstrap
steps). Summary:

- **Flux** is the sync engine. `flux bootstrap git --path=clusters/opti-k3s`
  installs the controllers and wires the `GitRepository` → root `Kustomization`.
- **Layered Kustomizations** (in `clusters/opti-k3s/flux-system/`):
  `infra-controllers` → `infra-config` (dependsOn) → `apps` (dependsOn), giving
  ordered, pruned reconciliation.
- **MetalLB** (controller in `infrastructure/controllers/metallb`, config in
  `infrastructure/config/metallb`) provides `LoadBalancer` IPs because k3s's
  `servicelb` is disabled. L2 mode, pool `10.0.5.80-10.0.5.99` (free range —
  verify before use).
- The controllers/config split exists because MetalLB's CRDs must be installed
  (by the HelmRelease) before the `IPAddressPool`/`L2Advertisement` are applied.
- All `gitops/**/*.yaml` are forced to LF via `.gitattributes`.

## 8. Gotchas / rules of thumb

- **LF only** for any script rendered onto a Linux guest.
- **Don't trust `curl -f`** for k3s healthz (it 401s); probe reachability instead.
- **Mask first-boot apt** before installing packages on a fresh Debian cloud VM.
- **keepalived binds the guest NIC** (`eth0`), not the host bridge (`vmbr0`).
- **keepalived health-script crashes** on kernel 6.12 — omit `vrrp_script`.
- **Windows local-exec:** use PowerShell + `;` + remote-side redirect + scp; never `cmd`.
- **No shared storage:** templates are built per-node (`template_vm_id_base`), and
  the image is downloaded to `local` then cloned to `local-lvm`.
- **Interrupted applies orphan VMs:** if an apply is killed mid-clone, the VMs may
  exist on the nodes but not in state; clean them via the PVE API
  (`POST .../status/stop` then `DELETE .../qemu/<id>`) before re-applying.
