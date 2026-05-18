---
title: kind
date: 2026-05-18
---

kind (Kubernetes in Docker) is great for local dev and CI. The chart's
`test-chart.sh` script in this repo uses kind.

## Cluster

The repo ships a `kind-config.yaml`:

```bash
kind create cluster --config kind-config.yaml --name npa-test
```

That mounts `/dev/net/tun` into the kind node container so the
Publisher can reach the host's tun device. **Without this mount, the
Publisher fails on startup.**

## Recommended values

```yaml
workload:
  type: daemonset
  replicas: 1

networking:
  mode: pod
  disableIPv6: true

tunDevice:
  enabled: true

hostNetwork: false
dnsPolicy: ClusterFirst

persistence:
  enabled: false
```

## Quirks

- The host Docker daemon must have `/dev/net/tun` accessible — on
  Docker Desktop (Mac/Windows) this is not guaranteed; prefer Linux.
- Resource limits in the default `values.yaml` are sized for production.
  For kind on a laptop, halve them.
- kind nodes are ephemeral — `kind delete cluster` wipes the Publisher.
  Pair with `persistence.enabled: false` for clean teardown.
