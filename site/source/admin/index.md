---
title: Admin Guides
date: 2026-05-18
---

Reference, how-tos, and operational guidance for Kubernetes operators
running `kubernetes-netskope-publisher` in production.

## Concepts
- [Architecture overview](/kubernetes-netskope-publisher/admin/concepts/architecture-overview/)
- [Registration flow](/kubernetes-netskope-publisher/admin/concepts/registration-flow/)
- [Workload modes (DaemonSet vs StatefulSet)](/kubernetes-netskope-publisher/admin/concepts/workload-modes/)
- [Connectivity requirements](/kubernetes-netskope-publisher/admin/concepts/connectivity/)

## Chart reference
- [Full values reference](/kubernetes-netskope-publisher/admin/chart/values-reference/)
- Per-distribution notes:
  - [k3s](/kubernetes-netskope-publisher/admin/chart/distributions/k3s/)
  - [kind](/kubernetes-netskope-publisher/admin/chart/distributions/kind/)
  - [EKS (Amazon)](/kubernetes-netskope-publisher/admin/chart/distributions/eks/)
  - [AKS (Azure)](/kubernetes-netskope-publisher/admin/chart/distributions/aks/)
  - [GKE (Google)](/kubernetes-netskope-publisher/admin/chart/distributions/gke/)
  - [OpenShift](/kubernetes-netskope-publisher/admin/chart/distributions/openshift/)

## How-to
- [Run an HA pair](/kubernetes-netskope-publisher/admin/how-to/ha-pair/)
- [Autoscaling (HPA)](/kubernetes-netskope-publisher/admin/how-to/autoscaling/)
- [Bring your own image](/kubernetes-netskope-publisher/admin/how-to/byo-image/)
- [Rotate the API token](/kubernetes-netskope-publisher/admin/how-to/rotate-token/)
- [Delete a Publisher cleanly](/kubernetes-netskope-publisher/admin/how-to/delete-publisher/)
- [Multi-cluster deployments](/kubernetes-netskope-publisher/admin/how-to/multi-cluster/)
- [Pod vs host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/)

## Operations
- [State management (persistence)](/kubernetes-netskope-publisher/admin/operations/state-management/)
- [Secret handling](/kubernetes-netskope-publisher/admin/operations/secret-handling/)
- [Upgrading Publisher software](/kubernetes-netskope-publisher/admin/operations/upgrading-software/)
- [Troubleshooting](/kubernetes-netskope-publisher/admin/operations/troubleshooting/)
