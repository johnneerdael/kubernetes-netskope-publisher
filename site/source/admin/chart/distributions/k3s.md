---
title: k3s
date: 2026-05-18
---

k3s is the recommended path for first deployments. Single binary, no
PSA/PSP friction, host network and privileged pods Just Work.

## Install k3s

```bash
curl -sfL https://get.k3s.io | sh -
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
```

## Recommended values

```yaml
workload:
  type: daemonset
  replicas: 1

networking:
  mode: host     # k3s, single node — host network is the simplest path
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet

persistence:
  enabled: false
```

## Quirks

- **klipper service load balancer** consumes ports 80/443 on the host
  by default. The Publisher doesn't need any inbound, so no conflict.
- **Embedded CoreDNS** forwards to the host's `/etc/resolv.conf`. If the
  host can resolve `*.goskope.com`, the pod can too.
- **traefik** ships by default. Harmless for the Publisher; disable
  with `--disable=traefik` if you don't need it.
- **k3s upgrades** restart the kubelet. The Publisher pod re-enrolls
  via the API on restart — no manual intervention needed (with `mode:
  api`).
