---
title: EKS (Amazon)
date: 2026-05-18
---

## Recommended values

```yaml
workload:
  type: statefulset    # HA across AZs
  replicas: 2

networking:
  mode: pod
  disableIPv6: true

tunDevice:
  enabled: true

hostNetwork: false
dnsPolicy: ClusterFirst

# Spread replicas across AZs
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: npa-publisher
        topologyKey: topology.kubernetes.io/zone
```

## Pod Security Admission

The Publisher needs `privileged`. On clusters where the namespace
enforces PSA `baseline` or `restricted`, label the install namespace:

```bash
kubectl label namespace npa-publisher \
  pod-security.kubernetes.io/enforce=privileged \
  --overwrite
```

## NAT gateway

Place worker nodes behind a NAT gateway with a stable Elastic IP so the
Publisher's egress address is predictable for Netskope policy.

## IRSA

The chart's ServiceAccount doesn't need AWS permissions; the Publisher
makes no AWS API calls. Don't attach an IRSA role unless you have
other reasons to.

## Quirks

- **Bottlerocket nodes:** `/dev/net/tun` is present but PSA defaults
  are stricter — label the namespace as above.
- **Fargate is unsupported.** Fargate disallows privileged pods, so the
  Publisher cannot run there. Use EC2 node groups.
- **EKS Auto Mode:** still requires privileged pod allowance in the
  namespace; otherwise compatible.
