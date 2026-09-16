---
name: bootstrap-ssh-keys
description: Use when setting up or deploying this terraform-proxmox-k3s cluster and the SSH keypair is missing, unknown, or provisioning fails with "Permission denied (publickey)" / "no supported authentication methods". Generates an ed25519 keypair and wires authorized_keys_file / authorized_private_key_file into the example before terraform apply.
---

# Bootstrap SSH keys before deploy

This cluster's Terraform provisions every node over SSH. Two variables drive it:

- `authorized_keys_file` — the **public** key. Terraform injects this into each VM's `authorized_keys` so the node accepts logins.
- `authorized_private_key_file` — the **private** key. Terraform's `file`/`remote-exec`/`local-exec` provisioners use this to log in. Ignored when `ssh_agent_auth = true`.

Both are set in `example/main.tf` (default to `~/.ssh/id_rsa[.pub]`, which this project overrides to `id_ed25519`). The keypair must exist **before** `terraform apply`, or provisioning fails with `Permission denied (publickey)`.

## When to use

- Before a first `terraform apply` / `terraform destroy` if the keypair is absent.
- After a fresh clone / new machine where `~/.ssh/id_ed25519` doesn't exist.
- When a provisioner errors with `Permission denied (publickey)` or `ssh: no supported authentication methods`.

## Workflow

### 1. Read the configured key paths

Pull the actual paths from `example/main.tf` (do not assume defaults):

```
authorized_keys_file        = "<public key path>"
authorized_private_key_file = "<private key path>"
ssh_binary                  = "<path to ssh.exe>"
```

On Windows these are typically `C:/Users/<user>/.ssh/id_ed25519[.pub]`. Use the **same** base path for both (public = private + `.pub`).

### 2. Check whether the keypair already exists

```powershell
$pub = "C:/Users/jaked/.ssh/id_ed25519.pub"
$priv = "C:/Users/jaked/.ssh/id_ed25519"
Test-Path -LiteralPath $pub
Test-Path -LiteralPath $priv
```

- **Both exist** → skip generation; go to step 5 (verify + wire).
- **Private exists but public missing** → regenerate the public half from the private key (step 4b), do NOT generate a new pair (that would orphan the private key).
- **Neither exists** → generate (step 3).

### 3. Generate an ed25519 keypair (only if missing)

Use the OpenSSH that ships with Windows:

```powershell
& "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -t ed25519 -f "C:\Users\jaked\.ssh\id_ed25519" -N '""' -C "k3s-deployer@$(hostname)"
```

- `-t ed25519` — required; RSA+SHA-1 is distrusted by modern OpenSSH (see `variables.tf` description).
- `-N '""'` — empty passphrase. **Required for unattended Terraform provisioning** (provisioners cannot type a passphrase). Warn the user: the private key is unprotected on disk; protect it with filesystem ACLs / keep it out of backups that leave the machine.
- `-f` — the private key path; the public key is written alongside as `<path>.pub`.
- Do **not** overwrite an existing key. If the file exists, stop and ask before clobbering.

### 4. (Alternatives)

**4b. Public half missing but private present:**
```powershell
& "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -y -f "C:\Users\jaked\.ssh\id_ed25519" > "C:\Users\jaked\.ssh\id_ed25519.pub"
```

**4c. Prefer ssh-agent instead of a file-based private key:** set `ssh_agent_auth = true` in `example/main.tf` and load the key:
```powershell
& "C:\Windows\System32\OpenSSH\ssh-agent.exe"   # if not running; capture env
& "C:\Windows\System32\OpenSSH\ssh-add.exe" "C:\Users\jaked\.ssh\id_ed25519"
```
With `ssh_agent_auth = true`, `authorized_private_key_file` is ignored by the provisioners.

### 5. Wire the paths into the example

Ensure `example/main.tf` points at the generated keypair (forward slashes in Terraform paths):

```hcl
authorized_keys_file        = "C:/Users/jaked/.ssh/id_ed25519.pub"
authorized_private_key_file = "C:/Users/jaked/.ssh/id_ed25519"
ssh_binary                  = "C:/Windows/System32/OpenSSH/ssh.exe"
```

If the user keeps secrets out of `main.tf`, put these in `example/secrets.auto.tfvars` instead (already gitignored).

### 6. Verify before deploying

```powershell
# Public key is well-formed and matches the private key
& "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -l -f "C:\Users\jaked\.ssh\id_ed25519"
& "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -l -f "C:\Users\jaked\.ssh\id_ed25519.pub"
```
Both fingerprints **must** be identical. If they differ, the `.pub` is stale — regenerate it (step 4b).

Confirm the public key line starts with `ssh-ed25519 `:
```powershell
Get-Content "C:\Users\jaked\.ssh\id_ed25519.pub" | Select-String '^ssh-ed25519 '
```

### 7. Then deploy

```powershell
terraform -chdir=example init
terraform -chdir=example apply
```

## Gotchas

- **Passphrase-less key = automation requirement.** Terraform `remote-exec` cannot answer a passphrase prompt. If the key has a passphrase, use `ssh_agent_auth = true` + `ssh-add`, or the deploy will hang/fail.
- **Never commit the private key.** `example/secrets.auto.tfvars` and `example/kubeconfig.yaml` are gitignored; keep the private key under `~/.ssh/`, not in the repo.
- **Windows path style.** Terraform string values use forward slashes (`C:/Users/...`); the `ssh-keygen`/`ssh` binaries accept backslashes. Don't mix within a single value.
- **Changing the key after nodes exist** does not re-inject it — provisioners only run on create. Rotating keys on a live cluster requires re-running the cloud-init or manually updating `authorized_keys` on each node.
- **`ssh_binary` must point at a real `ssh.exe`** on Windows (the bundled `C:/Windows/System32/OpenSSH/ssh.exe`); otherwise the kubeconfig `local-exec` and provisioners fail to find `ssh`.
