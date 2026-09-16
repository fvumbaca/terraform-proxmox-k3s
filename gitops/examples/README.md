# GitOps examples

Reference manifests for this cluster.

## CloudNativePG example (live)

The CNPG example cluster now lives in the Flux-synced tree at
`gitops/apps/postgres/cluster.yaml` and is wired into
`gitops/apps/kustomization.yaml`, so Flux deploys it on bootstrap.

- 2 instances: 1 primary + 1 streaming replica.
- StorageClass `longhorn-cnpg` (single-replica, `WaitForFirstConsumer`, `Retain`).
- HA via Postgres streaming replication, not Longhorn replication.
- Bootstrap secret generated in `apps/kustomization.yaml` with a PLACEHOLDER
  password — replace with SOPS/Sealed Secrets before real use.

Prereqs:
- Longhorn + `longhorn-cnpg` StorageClass
  (`gitops/infrastructure/config/longhorn-cnpg/storageclass.yaml`).
- CloudNativePG operator
  (`gitops/infrastructure/controllers/cloudnative-pg/`).
