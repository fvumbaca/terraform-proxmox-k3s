# GitOps — Flux + MetalLB

GitOps scaffolding for the `opti-k3s` cluster. [Flux](https://fluxcd.io) is the
sync engine; [MetalLB](https://metallb.io) provides `LoadBalancer` IPs (k3s's
built-in `servicelb` is disabled in the Terraform module).

## Layout

```
gitops/
├── clusters/opti-k3s/flux-system/   # Flux sync objects (GitRepository + Kustomizations)
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

The pool is `10.0.5.80-10.0.5.99` (L2 mode). This range is chosen to be free on
the LAN: PVE hosts use `10.0.5.1-9`, masters `17-19`, VIP `23`, workers
`25/33/41/49/57/65`, and DHCP only covers `10.0.0.86-10.0.4.254` (not
`10.0.5.x`). **Confirm `10.0.5.80-99` is unassigned on your network before use**
and edit `infrastructure/config/metallb/ip-pool.yaml` if needed.

## Bootstrap Flux

Flux is installed with `flux bootstrap`, which installs the controllers and
commits the `flux-system` manifests to your git repo. Point it at this repo's
`clusters/opti-k3s` path:

```bash
export KUBECONFIG=./example/kubeconfig.yaml   # server = VIP 10.0.5.23

flux bootstrap git \
  --url=ssh://git@YOUR_HOST/YOUR_ORG/opti-k3s-gitops.git \
  --path=clusters/opti-k3s \
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
kubectl get svc nginx -w   # EXTERNAL-IP should land in 10.0.5.80-99
```

## Notes

- **Why not Terraform helm?** Flux is the GitOps source of truth for cluster
  add-ons; Terraform owns the VMs/network. Keeping MetalLB in Flux means its
  lifecycle is reconciled continuously, not just at `terraform apply`.
- **Ingress:** with `traefik` disabled in k3s, add Traefik 2 (or another ingress)
  as another HelmRelease under `infrastructure/controllers/` when ready.
- **Secrets in git:** use SOPS/Sealed Secrets; do not commit plaintext.
