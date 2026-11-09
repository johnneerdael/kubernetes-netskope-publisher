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

## StatefulSet (`workload.type: statefulset`)

```yaml
workload:
  type: statefulset
  replicas: 3
```

- N pods with stable identities: `<release>-0`, `<release>-1`, ...
- Each pod's `commonName` becomes `<configured-commonName>-<ordinal>` —
  the chart appends only the StatefulSet ordinal (`0`, `1`, `2`, …), so
  with `commonName: npa-publisher` the replicas register as
  `npa-publisher-0`, `npa-publisher-1`, `npa-publisher-2` and appear as
  distinct Publishers in the tenant.
- Works with `enrollment.mode: api`, or with `enrollment.mode: token` plus
  `registrationToken.keyBy: ordinal`. In token mode replica N enrolls with
  its own pre-provisioned token from Secret key `"N"`, typically issued by
  Terraform ([guide](/kubernetes-netskope-publisher/admin/how-to/terraform-token-enrollment/)).
  HPA is API-mode only.
- **Good for:** HA pairs, replicated regional deployments inside one
  cluster, autoscaling by replica count.

## Which should I use?

| Scenario | Recommendation |
|---|---|
| Single host, k3s, kind | DaemonSet, replicas 1 |
| Production cluster, HA, want explicit replica count | StatefulSet, replicas 2–3 |
| One Publisher per worker node by design | DaemonSet + node selector |
| Token enrollment, one Publisher | DaemonSet pinned to one node, `keyBy: single` |
| Token enrollment, several Publishers (Terraform-issued tokens) | StatefulSet + `keyBy: ordinal`, or DaemonSet + `keyBy: node` |
