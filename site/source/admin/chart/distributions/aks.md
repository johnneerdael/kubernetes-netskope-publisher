---
title: AKS (Azure)
date: 2026-05-18
---

## Recommended values

```yaml
workload:
  type: statefulset
  replicas: 2

networking:
  mode: pod
  disableIPv6: true

tunDevice:
  enabled: true


affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: kubernetes-netskope-publisher
        topologyKey: topology.kubernetes.io/zone
```

## Egress

AKS clusters need a deterministic outbound IP for stitcher connections.
Use **Azure NAT Gateway** or a **user-defined outbound type** with a
fixed public IP. The default Azure Load Balancer SNAT ports can exhaust
under high tunnel churn.

## Quirks

- **Azure CNI vs kubenet:** both work. Azure CNI overlay is fine.
- **AKS Container Insights** logs the Publisher's `print`-style output
  with no special handling — search for `NPACONNECTED`.
- **Pod Sandboxing (Kata):** unsupported. Privileged + tun device
  cannot work inside Kata Containers.
