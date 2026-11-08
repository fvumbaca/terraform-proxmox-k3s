# GitOps examples

Reference manifests for this cluster.

## CloudNativePG example (live)

The CNPG example cluster now lives in the Flux-synced tree at
`gitops/apps/postgres/cluster.yaml` and is wired into
`gitops/apps/kustomization.yaml`, so Flux deploys it on bootstrap.

- 1 instance on the dedicated DB node (no cross-node HA).
- StorageClass `local-path` (the k3s default provisioner; no Longhorn on a
  single node).
- Bootstrap secret generated in `apps/kustomization.yaml` with a PLACEHOLDER
  password — replace with SOPS/Sealed Secrets before real use.
- Scheduling: pinned to the dedicated Terraform `db` node pool
  (`workload=cnpg`, taint `dedicated=db:NoSchedule`).

Prereqs:
- CloudNativePG operator
  (`gitops/infrastructure/controllers/cloudnative-pg/`).
- Optional: patch `local-path-config` in `kube-system` so the DB node's path is
  `/mnt/sdb1` (the additional 300G disk provisioned by Terraform). Otherwise
  CNPG volumes land on the boot disk under `/var/lib/rancher/k3s/storage`.
