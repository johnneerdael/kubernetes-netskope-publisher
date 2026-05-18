---
title: GKE (Google)
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

```

## Node image

- **Container-Optimized OS (cos_containerd):** `/dev/net/tun` is
  available. **Default and recommended.**
- **Ubuntu (ubuntu_containerd):** also works.
- **GKE Autopilot:** **unsupported.** Autopilot blocks `privileged: true`
  pods and `hostPath` mounts. Use Standard GKE.

## Egress

Use **Cloud NAT** with a reserved static external IP for the node pool
running the Publisher. Without it, GKE assigns ephemeral SNAT IPs that
change.

## PodSecurity (GKE 1.25+)

The install namespace must allow `privileged`:

```bash
kubectl label namespace npa-publisher \
  pod-security.kubernetes.io/enforce=privileged \
  --overwrite
```

## Workload Identity

Not required; the Publisher does not call any GCP API.
