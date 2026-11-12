# GitOps — Flux + MetalLB

GitOps scaffolding for the `lagrange-k3s` cluster. [Flux](https://fluxcd.io) is the
sync engine; [MetalLB](https://metallb.io) provides `LoadBalancer` IPs (k3s's
built-in `servicelb` is disabled in the Terraform module).

## Layout

```
gitops/
├── clusters/lagrange-k3s/flux-system/   # Flux sync objects (GitRepository + Kustomizations)
│   ├── gotk-sync.yaml                # GitRepository + root Kustomization
│   ├── infra-controllers.yaml        # -> infrastructure/controllers (MetalLB controller)
│   ├── infra-config.yaml             # -> infrastructure/config (dependsOn controllers)
│   └── apps.yaml                     # -> apps/
├── infrastructure/
│   ├── controllers/metallb/          # namespace + HelmRepo + HelmRelease (the controller)
│   └── config/metallb/               # IPAddressPool + L2Advertisement (the config)
└── apps/                             # your workloads go here
```

The controllers/config split is deliberate: MetalLB's CRDs (`IPAddressPool`,
`L2Advertisement`) must exist before the pool is applied, so `infra-config`
declares `dependsOn: [infra-controllers]`.

## MetalLB IP pool

The pool is `10.0.6.80-10.0.6.99` (L2 mode). This range is chosen to be free on
the LAN: the Proxmox host `lagrange` uses `10.0.6.0`, the master `17`, VIP `23`,
general workers `25/33/41/49`, and the CNPG DB worker `65`. DHCP only covers
`10.0.0.86-10.0.4.254` (not `10.0.6.x`). **Confirm `10.0.6.80-99` is unassigned
on your network before use** and edit `infrastructure/config/metallb/ip-pool.yaml`
if needed.

## Bootstrap Flux

Flux is installed with `flux bootstrap`, which installs the controllers and
commits the `flux-system` manifests to your git repo. Point it at this repo's
`clusters/lagrange-k3s` path:

```bash
export KUBECONFIG=./example/kubeconfig.yaml   # server = VIP 10.0.6.23

flux bootstrap git \
  --url=ssh://git@YOUR_HOST/YOUR_ORG/lagrange-k3s-gitops.git \
  --path=clusters/lagrange-k3s \
  --branch=main \
  --private-key-file=~/.ssh/id_ed25519 \
  --components=source-controller,kustomize-controller,helm-controller,notification-controller
```

After bootstrap, Flux reconciles `infrastructure/controllers` (installs MetalLB)
then `infrastructure/config` (creates the pool), then `apps/`.

### Verify

```bash
flux check --pre                      # pre-flight
flux get kustomizations              # all "Reconciled" / Ready
kubectl -n metallb-system get pods   # controller + speaker running
kubectl -n metallb-system get ipaddresspool,l2advertisement
```

### Smoke-test a LoadBalancer

```bash
kubectl create deploy nginx --image=nginx --port=80
kubectl expose deploy nginx --port=80 --type=LoadBalancer
kubectl get svc nginx -w   # EXTERNAL-IP should land in 10.0.6.80-99
```

## CNPG native backups (Barman Cloud plugin)

The GitOps tree installs the prerequisites for native CloudNativePG backups:

| Path | What it does |
| --- | --- |
| `infrastructure/controllers/cert-manager/` | cert-manager HelmRelease (the plugin's webhook certificates need it) |
| `infrastructure/controllers/barman-cloud/` | `plugin-barman-cloud` HelmRelease in `cnpg-system`; `dependsOn` cert-manager + cloudnative-pg |
| `apps/postgres/object-store.yaml` | `ObjectStore` pointing at Backblaze B2, 30-day retention |
| `apps/postgres/scheduled-backup.yaml` | daily `ScheduledBackup` using `method: plugin` |
| `apps/postgres/cluster.yaml` | `spec.plugins` with `isWALArchiver: true` |

The plugin chart requires **CloudNativePG ≥ 1.30** and **cert-manager**. Both are
declared under `infrastructure/controllers`, so Flux installs them before the
plugin (the HelmRelease uses `dependsOn`).

### B2 credentials (never committed)

The `ObjectStore` references a secret with Barman-shaped keys. Create it
out-of-band, or encrypt it with SOPS/Sealed Secrets:

```bash
kubectl -n postgres create secret generic pg-sample-b2-creds \
  --from-literal=ACCESS_KEY_ID=<b2-key-id> \
  --from-literal=ACCESS_SECRET_KEY=<b2-app-key>
```

For the live `cepo` cluster, the same pattern uses `cepo-b2-creds` in the
`cepo` namespace (derived from the existing `cepo-secrets` B2 keys) and an
`ObjectStore` named `cepo-b2-store` at `s3://cepo-archive/cepo-postgres`.

### Verify

```bash
kubectl -n cnpg-system get deploy plugin-barman-cloud
kubectl -n postgres get objectstore,scheduledbackup
kubectl -n postgres get cluster pg-sample -o jsonpath='{.spec.plugins}'
kubectl -n postgres get cluster pg-sample -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'
```

Trigger an on-demand backup:

```bash
kubectl -n postgres apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: pg-sample-manual-1
spec:
  cluster:
    name: pg-sample
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
kubectl -n postgres get backup
```

### Restore / PITR

Recovery uses the plugin's `externalClusters` stanza. Create a new Cluster with
`bootstrap.recovery.source` pointing at the ObjectStore and the original
`serverName`:

```yaml
spec:
  bootstrap:
    recovery:
      source: pg-sample-source
  externalClusters:
    - name: pg-sample-source
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: pg-sample-b2-store
          serverName: pg-sample
```

The `serverName` is the original cluster name; it is what lets Barman locate the
backup set. Add `spec.plugins` to the restored cluster if it should keep
archiving WALs.

> The existing `pg_dump` cronjob in the CEPO repo remains a portable secondary
> backup; native CNPG backups add continuous WAL archiving (minutes-level RPO).

## Notes

- **Why not Terraform helm?** Flux is the GitOps source of truth for cluster
  add-ons; Terraform owns the VMs/network. Keeping MetalLB in Flux means its
  lifecycle is reconciled continuously, not just at `terraform apply`.
- **Ingress:** with `traefik` disabled in k3s, add Traefik 2 (or another ingress)
  as another HelmRelease under `infrastructure/controllers/` when ready.
- **Secrets in git:** use SOPS/Sealed Secrets; do not commit plaintext.
