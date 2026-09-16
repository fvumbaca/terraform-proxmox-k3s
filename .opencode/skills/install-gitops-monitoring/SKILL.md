---
name: install-gitops-monitoring
description: Use when installing the GitOps toolchain (Flux CLI + bootstrap) and/or a monitoring stack (kube-prometheus-stack: Prometheus, Grafana, Alertmanager) onto the opti-k3s cluster, or when wiring such add-ons into the gitops/ repo layout. Triggers on "install flux", "install gitops tools", "install monitoring", "prometheus", "grafana", "kube-prometheus-stack".
---

# Install GitOps tools + monitoring (Flux + kube-prometheus-stack)

This repo's GitOps source of truth is the `gitops/` tree, synced by **Flux**. Terraform owns VMs/network; Flux owns cluster add-ons (MetalLB, ingress, monitoring). This skill installs the Flux CLI, bootstraps Flux into the cluster, and adds the monitoring stack — either as a GitOps `HelmRelease` (preferred) or a direct `helm install` (quick test).

## Prerequisites (verify first)

```powershell
$env:KUBECONFIG = "C:\Users\jaked\Desktop\AITest\terraform-proxmox-k3s-multinode\example\kubeconfig.yaml"
kubectl get nodes          # expect 9 Ready
kubectl -n metallb-system get pods   # MetalLB controller+speaker running (LB IPs work)
```

- Kubeconfig server must be the VIP `https://10.0.5.23:6443` (not a single master).
- MetalLB must be installed so `LoadBalancer` services (Grafana) get a pool IP.
- SSH keypair bootstrapped (see the `bootstrap-ssh-keys` skill) — Flux's `flux bootstrap git` needs it for the git transport.

## Part A — Install the Flux CLI (if missing)

```powershell
Get-Command flux -ErrorAction SilentlyContinue
```

If absent, install via winget (or the official script):

```powershell
winget install --id FluxCD.Flux -e
# re-open the shell so PATH updates, then:
flux --version
```

## Part B — Bootstrap Flux

Pre-flight, then bootstrap against this repo's `clusters/opti-k3s` path:

```powershell
flux check --pre

flux bootstrap git `
  --url=ssh://git@YOUR_HOST/YOUR_ORG/opti-k3s-gitops.git `
  --path=clusters/opti-k3s `
  --branch=main `
  --private-key-file=C:/Users/jaked/.ssh/id_ed25519 `
  --components=source-controller,kustomize-controller,helm-controller,notification-controller
```

- Replace `YOUR_HOST/YOUR_ORG/...` with the real git URL (the `gotk-sync.yaml` placeholder).
- `flux bootstrap` installs the controllers **and** commits the `flux-system` manifests to the repo. If the repo already contains `flux-system/` (it does), use `--components` matching what's committed so you don't drift.
- If you only want to install controllers without a git transport (e.g. testing), use `flux install --components=...` instead and apply `gotk-sync.yaml` manually.

Verify:

```powershell
flux -n flux-system get all
kubectl -n flux-system get pods    # 4 controllers Running
flux get kustomizations           # root + infra-controllers + infra-config + apps -> Ready
```

## Part C — Install monitoring (kube-prometheus-stack)

### C1. GitOps pattern (preferred) — add a HelmRelease

Create `gitops/infrastructure/controllers/kube-prometheus-stack/` mirroring the existing `metallb/` layout:

`helm-repository.yaml`:
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 30m
  url: https://prometheus-community.github.io/helm-charts
```

`helm-release.yaml` (trimmed — tune values for a 9-node homelab):
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: monitoring
spec:
  interval: 30m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: ">=60.0.0 <61.0.0"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  install: { createNamespace: true }
  values:
    grafana:
      enabled: true
      adminPassword: ""   # set via SOPS/secret ref, NOT plaintext
      service:
        type: LoadBalancer   # MetalLB assigns 10.0.5.80-99
    prometheus:
      prometheusSpec:
        retention: 7d
        resources:
          requests: { cpu: 200m, memory: 512Mi }
    alertmanager:
      enabled: true
```

Add the new dir to `gitops/infrastructure/controllers/kustomization.yaml` (`- ./kube-prometheus-stack`), commit, and Flux reconciles it. The `infra-controllers` Kustomization already runs before `infra-config`, so ordering is safe.

### C2. Quick test (direct helm, not GitOps)

For a throwaway check before committing to GitOps:

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kps prometheus-community/kube-prometheus-stack `
  -n monitoring --create-namespace `
  --set grafana.adminPassword=admin `
  --set grafana.service.type=LoadBalancer `
  --set prometheus.prometheusSpec.retention=2d
```

> If you later adopt this release into Flux, annotate it for adoption (`meta.helm.sh/release-name`, `meta.helm.sh/release-namespace`, `managed-by=Helm` labels) or `helm uninstall` the direct install first to avoid two owners.

## Part D — Expose + verify Grafana

```powershell
kubectl -n monitoring get pods -w        # prometheus, grafana, alertmanager, operators -> Running
kubectl -n monitoring get svc           # grafana EXTERNAL-IP in 10.0.5.80-99
# Grafana UI:
curl.exe -sk http://<grafana-lb-ip>:3000/api/health
# Prometheus:
curl.exe -sk http://<prometheus-lb-or-port-forward>:9090/-/healthy
```

Port-forward instead of a public LB if you don't want Grafana on the LAN:
```powershell
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
# browse http://localhost:3000  (admin / <adminPassword>)
```

## Gotchas

- **kube-prometheus-stack is heavy.** On a 9-node cluster set explicit `resources.requests`/limits and a short `retention` (2–7d) or Prometheus will eat disk. The default retention (10d) and storage can fill `local-path` quickly.
- **Never commit the Grafana admin password.** Use SOPS/Sealed Secrets (see `gitops/README.md` note) or a `secretRef`. The `adminPassword: ""` above is a placeholder.
- **Grafana as LoadBalancer** gets a MetalLB pool IP (`10.0.5.80-99`). If the pool is exhausted or you don't want Grafana exposed, use `ClusterIP` + `port-forward`, or route it through the Traefik ingress instead.
- **GitOps ownership:** if you `helm install` directly AND add a `HelmRelease`, two controllers fight over the same resources. Pick one. For a clean GitOps takeover of a helm-installed release, see the adoption annotations in C2.
- **CRD wait:** kube-prometheus-stack installs many CRDs; the `HelmRelease` may need `install.crds: create-replace` or a CRD-first step if Flux reports "no matches for kind". The chart's bundled CRDs usually handle this.
- **Flux `flux-system` namespace:** the controllers live in `flux-system`; the monitoring stack lives in `monitoring`. The `HelmRelease`/`HelmRepository` for monitoring can sit in `flux-system` (as above) or in `monitoring` — keep `sourceRef.namespace` consistent with where the `HelmRepository` lives.
- **Restart opencode** after editing skills; skills load at startup.
