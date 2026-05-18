---
title: Kubernetes / Helm matrix
date: 2026-05-18
---

The chart is regularly tested against the combinations below. Other
versions probably work; these are the ones with CI evidence.

## Tooling

| Component | Tested versions |
|---|---|
| Helm | 3.14, 3.15, 3.16 |
| kubectl | matches cluster version |

## Kubernetes distributions

| Distribution | Versions | Notes |
|---|---|---|
| k3s | v1.28.x – v1.30.x | Recommended starter path |
| kind | v1.28 – v1.30 | Local dev / CI |
| EKS | 1.28 – 1.30 | Fargate unsupported |
| AKS | 1.28 – 1.30 | NAT Gateway required for stable egress |
| GKE Standard | 1.28 – 1.30 | Autopilot unsupported |
| OpenShift | 4.14 – 4.16 | Requires `privileged` SCC binding |
| Rancher RKE2 | 1.28 – 1.30 | Same constraints as upstream Kubernetes |

## Publisher image tags

| Family | Notes |
|---|---|
| `netskopeprivateaccess/publisher_u22:latest` | Default — moves with each release |
| `netskopeprivateaccess/publisher_u22:<N.N.N.N>` | Specific build — recommended for production |

Refer to your Netskope tenant's release notes for the currently
supported build range. See [upgrading](/kubernetes-netskope-publisher/admin/operations/upgrading-software/).

## Chart values schema

The values surface is stable within a major chart version. Breaking
changes are flagged in the [changelog](/kubernetes-netskope-publisher/reference/changelog/).
