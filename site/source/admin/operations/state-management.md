---
title: State management
date: 2026-05-18
---

## What state does the Publisher carry?

| State | Where it lives | Survives pod restart? |
|---|---|---|
| Tenant identity (publisher_id) | `/etc/npa/registration-config` | Only if `persistence.enabled: true`, OR re-derived by `mode: api` on every start. |
| Bootstrap token | `/etc/npa/token` | Same — persistent or re-issued. |
| BIND9 / DNS state | tmpfs in container | No (regenerated). |
| Active tunnel state | kernel routes + iptables | No (rebuilt on start). |

## API mode (recommended)

`enrollment.mode: api` makes state restoration **automatic**. The init
container re-derives identity from the `commonName` on every pod start.
You do **not** need persistence.

```yaml
persistence:
  enabled: false
```

## Token mode

`enrollment.mode: token` consumes the registration token on first start.
The pod **must** keep the resulting `/etc/npa` files, or it cannot
restart without manual re-tokening.

```yaml
persistence:
  enabled: true
  storageClass: ""          # cluster default
  accessMode: ReadWriteOnce
  size: 1Gi                 # /etc/npa is small
```

In a StatefulSet the chart provisions one PVC per replica
(`volumeClaimTemplates`). In a DaemonSet, persistence pins the Pod to
its current node — be deliberate about that.

## Reusing an existing PVC

```yaml
persistence:
  enabled: true
  existingClaim: my-publisher-pvc
```

Only valid for `workload.type: daemonset` with `replicas: 1` (one
Publisher, one volume). StatefulSet always generates per-replica claims.

## Backup

The state under `/etc/npa` is small and re-derivable in API mode. Don't
include it in cluster-wide backups; it just creates restore confusion.
