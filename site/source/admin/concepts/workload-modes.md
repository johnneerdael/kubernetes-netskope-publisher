---
title: Workload modes
date: 2026-05-18
---

The chart can deploy the Publisher as either a **DaemonSet** or a
**StatefulSet**. Pick via `workload.type`.

## DaemonSet (`workload.type: daemonset`) — default

```yaml
workload:
  type: daemonset
  replicas: 1   # ignored for DaemonSet
```

- One Publisher pod **per matching node**.
- Use `nodeSelector` / `tolerations` to constrain which nodes get
  Publishers. Otherwise it lands on every schedulable node.
- Each pod registers with the same `enrollment.commonName`. In
  `mode: api` the chart appends the node hostname to disambiguate.
- **Good for:** dedicated "publisher nodes", host-network deployments,
  k3s single-node setups.

## StatefulSet (`workload.type: statefulset`) — API mode only

```yaml
workload:
  type: statefulset
  replicas: 3
```

- N pods with stable identities: `<release>-0`, `<release>-1`, ...
- Each pod's `commonName` becomes `<configured-commonName>-<pod-name>`,
  so they appear as distinct Publishers in the tenant.
- Works **only with `enrollment.mode: api`** — token enrollment cannot
  scale to multiple replicas without manual token-per-pod handling.
- **Good for:** HA pairs, replicated regional deployments inside one
  cluster, autoscaling by replica count.

## Which should I use?

| Scenario | Recommendation |
|---|---|
| Single host, k3s, kind | DaemonSet, replicas 1 |
| Production cluster, HA, want explicit replica count | StatefulSet, replicas 2–3 |
| One Publisher per worker node by design | DaemonSet + node selector |
| Token enrollment (air-gapped tenant) | DaemonSet, replicas 1 |
