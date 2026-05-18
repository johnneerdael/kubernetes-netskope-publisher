---
title: Cluster prep
date: 2026-05-18
---

For the starter path we install **k3s** — a single-binary Kubernetes
distribution that runs comfortably on a 1–2 vCPU VM.

## Install k3s

On the Linux host:

```bash
curl -sfL https://get.k3s.io | sh -
```

That installs k3s as a systemd unit, generates a kubeconfig at
`/etc/rancher/k3s/k3s.yaml`, and starts a single-node control plane +
worker.

## Verify the node is Ready

```bash
sudo k3s kubectl get nodes
```

Expected output:

```text
NAME      STATUS   ROLES                  AGE   VERSION
your-vm   Ready    control-plane,master   1m    v1.30.x+k3s1
```

## Already have a cluster?

You can skip k3s and use any cluster where you have **cluster-admin**.
Just point `KUBECONFIG` at it before continuing. See the
[distribution notes](/kubernetes-netskope-publisher/admin/chart/distributions/)
for tweaks needed on managed Kubernetes (EKS pod security, GKE node
images, etc.).

## Required cluster capabilities

The Publisher needs:

- `privileged: true` (sysctl tuning, iptables, tun device).
- `NET_ADMIN` + `NET_RAW` capabilities.
- Access to `/dev/net/tun` from the host (or via the chart's
  `tunDevice.hostPath` mount in `networking.mode: pod`).
- Outbound HTTPS reachability to `*.goskope.com`.

On k3s this works out of the box. On hardened clusters with PSA
`restricted`, see [pod-vs-host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/).
