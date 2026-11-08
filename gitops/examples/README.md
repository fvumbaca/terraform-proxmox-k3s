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
- Scheduling: pinned to the dedicated Terraform `db` node pool
  (`workload=cnpg`, taint `dedicated=db:NoSchedule`) with required anti-affinity
  so the two instances land on different DB nodes.

Prereqs:
- Longhorn + `longhorn-cnpg` StorageClass
  (`gitops/infrastructure/config/longhorn-cnpg/storageclass.yaml`).
- Longhorn's `longhorn-manager` DaemonSet must tolerate
  `dedicated=db:NoSchedule` so it runs on the DB nodes, and its data path there
  should be `/mnt/sdb1` (the additional 100G disk provisioned by Terraform).
- CloudNativePG operator
  (`gitops/infrastructure/controllers/cloudnative-pg/`).
