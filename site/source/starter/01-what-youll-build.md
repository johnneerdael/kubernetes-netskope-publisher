---
title: What you'll build
date: 2026-05-18
---

By the end of this guide you'll have:

- A **single-node k3s cluster** on a Linux host (Ubuntu 22.04 recommended).
- One **NPA Publisher pod** running in namespace `npa-publisher`, enrolled
  with your Netskope tenant via the **API enrollment** flow.
- The Publisher visible as **Online** in **Netskope NG SASE → Steering →
  Publishers**.

```text
   Linux host (1 vCPU, 2 GB)
   ├── k3s (single node)
   │     └── ns: npa-publisher
   │           └── pod: npa-publisher-xxxxx
   │                 ├── init: npa-bootstrap
   │                 └── publisher container ← talks outbound to *.goskope.com
   └── kubeconfig at /etc/rancher/k3s/k3s.yaml
```

## Why k3s for the first run?

- Single binary, one command to install, no etcd to babysit.
- The chart's default pod-networking mode renders an unprivileged
  pod, which k3s schedules without PSP/PSA tweaks.
- Same Helm chart works unchanged on EKS/AKS/GKE later
  ([distributions](/kubernetes-netskope-publisher/admin/chart/distributions/)).

## What you'll need

- A Linux VM you can SSH into as root (or with `sudo`).
- Outbound HTTPS reachability to `*.goskope.com` and Docker Hub.
- A Netskope tenant with **NPA** licensed and an API token with
  `policy/npa/publishers` write scope (see
  [Netskope tenant prep](/kubernetes-netskope-publisher/starter/04-netskope-tenant-prep/)).

Hit **Next** when you're ready.
