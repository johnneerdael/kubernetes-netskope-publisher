---
title: Next steps
date: 2026-05-18
---

You have a working Publisher. Where to from here?

## Productionise the deployment

- **Switch to `networking.mode: pod`** if you haven't already. Lower
  blast radius, works on managed Kubernetes, no privileged host network
  required.
  → [pod-vs-host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/)
- **Run an HA pair** (two replicas across nodes, anti-affinity).
  → [HA pair](/kubernetes-netskope-publisher/admin/how-to/ha-pair/)
- **Enable persistence** so settings survive node failures.
  → [State management](/kubernetes-netskope-publisher/admin/operations/state-management/)
- **Pin the image tag** to a tested version instead of `latest`.
  → [BYO image](/kubernetes-netskope-publisher/admin/how-to/byo-image/)

## Roll out to your real cluster

- **EKS / AKS / GKE / OpenShift** — see
  [distributions](/kubernetes-netskope-publisher/admin/chart/distributions/) for the
  per-platform tweaks (PSA, GKE node images, OpenShift SCC, etc.).
- **Multiple clusters / regions** — one Helm release per cluster, one
  `enrollment.commonName` per cluster.
  → [Multi-cluster](/kubernetes-netskope-publisher/admin/how-to/multi-cluster/)

## Operate it

- [Rotate the API token](/kubernetes-netskope-publisher/admin/how-to/rotate-token/)
- [Upgrade Publisher software](/kubernetes-netskope-publisher/admin/operations/upgrading-software/)
- [Troubleshooting](/kubernetes-netskope-publisher/admin/operations/troubleshooting/)
- [Full chart values reference](/kubernetes-netskope-publisher/admin/chart/values-reference/)
