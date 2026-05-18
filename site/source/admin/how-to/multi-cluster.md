---
title: Multi-cluster deployments
date: 2026-05-18
---

For multiple regions or independent clusters, deploy **one Helm release
per cluster** with a distinct `enrollment.commonName`. There is no
cluster-to-cluster coordination; each Publisher is an independent
participant in the Netskope mesh.

## Pattern

```text
eu-cluster   → helm release npa-publisher  → commonName: prod-eu-publisher (replicas: 2)
us-cluster   → helm release npa-publisher  → commonName: prod-us-publisher (replicas: 2)
apac-cluster → helm release npa-publisher  → commonName: prod-apac-publisher (replicas: 2)
```

Each cluster needs its **own API token Secret** with a tenant-scoped
token (you can use the same token across clusters, but rotating it
becomes a coordinated activity — easier to keep them separate).

## Values diffs

```yaml
# eu-cluster: my-values-eu.yaml
enrollment:
  commonName: prod-eu-publisher
  api:
    baseUrl: https://tenant.goskope.com

# us-cluster: my-values-us.yaml
enrollment:
  commonName: prod-us-publisher
  api:
    baseUrl: https://tenant.goskope.com
```

Keep the rest of the values file identical across clusters so the only
diff is the `commonName`.

## Attaching apps to per-region Publishers

In the Netskope console, attach each Private App to the geo-appropriate
Publisher(s). Steering policy then resolves users to the closest healthy
Publisher.

## GitOps tip

Use ArgoCD / Flux with one `Application` per cluster, all pointing at
the same Helm chart but with different values overlays
(`overlays/eu.yaml`, `overlays/us.yaml`, ...).
