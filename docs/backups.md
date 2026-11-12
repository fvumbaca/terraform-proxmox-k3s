# Backups and Restore

Two datastore modes are supported: **embedded etcd** and **MariaDB**. Backups
differ per mode.

## Embedded etcd

When `cluster_enable_embedded_etcd = true` and `etcd_snapshot_schedule_cron` is
set, each master takes scheduled snapshots via k3s:

- Location: `/var/lib/rancher/k3s/server/db/snapshots/` on each master
- On-demand snapshot:

  ```sh
  sudo k3s etcd-snapshot save --name manual-$(date +%s)
  ```

### Restore (embedded etcd)

Restore must run on a single node and replaces the whole cluster DB:

```sh
# 1. Stop k3s on ALL masters and workers
sudo systemctl stop k3s k3s-agent

# 2. On the node holding the snapshot, restore and start as a fresh single-node cluster
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-name>

# 3. Once healthy, start the remaining masters (they rejoin), then the workers
sudo systemctl start k3s   # other masters
sudo systemctl start k3s-agent
```

> Copy snapshots off-host regularly - a snapshot on a dead VM is worthless.

## MariaDB

When `cluster_enable_embedded_etcd = false`, the support node runs MariaDB and a
nightly cron (`db_backup_schedule`, default `0 2 * * *`):

- Script: `/usr/local/bin/k3s-db-backup.sh` on the support node
- Output: `/var/backups/k3s/k3s-<timestamp>.sql.gz` (7-day retention)
- Log: `/var/log/k3s-db-backup.log`

### Restore (MariaDB)

```sh
# 1. Stop k3s on all masters
sudo systemctl stop k3s

# 2. Restore the dump
gunzip -c /var/backups/k3s/k3s-<timestamp>.sql.gz | sudo mariadb k3s

# 3. Start masters, then workers
sudo systemctl start k3s
sudo systemctl start k3s-agent
```

## Off-host copies

Neither mechanism copies off the VM. Add your own sync (rsync/restic/borg) of
`/var/backups/k3s` (MariaDB) or the etcd snapshot dir to external storage.

## CloudNativePG native backups (Barman Cloud plugin)

The GitOps tree installs cert-manager and the `plugin-barman-cloud` HelmRelease
under `gitops/infrastructure/controllers`, and declares an `ObjectStore` plus a
daily `ScheduledBackup` for `pg-sample` under `gitops/apps/postgres`. Native
CNPG backups add continuous WAL archiving (minutes-level RPO) alongside the
existing `pg_dump` cronjob.

See `gitops/README.md` → **CNPG native backups (Barman Cloud plugin)** for the
credentials secret, verification commands, and point-in-time restore recipe.

For the live `cepo` cluster the same pattern uses the `cepo-b2-creds` secret and
an `ObjectStore` named `cepo-b2-store` at `s3://cepo-archive/cepo-postgres`.
The backup objects are committed under `gitops/apps/cepo/`.

### Apostas

`apostas-postgres` uses the same plugin architecture: `ObjectStore
apostas-b2-store` at `s3://apostas-archive/cnpg` (14-day retention) and a daily
`ScheduledBackup` at 03:00 UTC. The manifests live under `gitops/apps/apostas/`.

The nightly `apostas-pg-backup` CronJob is a secondary logical dump on a
`local-path` PVC; it is **not** off-node, so the native CNPG backup is the
primary recovery path. Verify it monthly by restoring into a scratch cluster:

```sh
kubectl -n apostas create -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: apostas-postgres-restore-test
  namespace: apostas
spec:
  instances: 1
  storage:
    size: 5Gi
    storageClass: local-path
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  bootstrap:
    recovery:
      source: apostas-postgres
      recoveryTarget:
        targetTime: "2026-11-12T22:00:00Z"
  externalClusters:
    - name: apostas-postgres
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: apostas-b2-store
          serverName: apostas-postgres
EOF
```

Wait for the cluster to become healthy, verify row counts in `weather_signals`,
`orders`, and `positions`, then delete the scratch cluster.

The `apostas-deadman` CronJob alerts on a stale heartbeat, a missing/stale
`pg_dump`, or stale data sources. Set `ALERT_WEBHOOK` in
`apostas-backup-secrets` and `HEALTHCHECK_PING_URL` in
`apostas-engine-secrets`; the engine logs a warning at startup when either is
unset.

