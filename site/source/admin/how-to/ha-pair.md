---
title: Run an HA pair
date: 2026-05-18
---

Two Publishers in the same cluster, spread across nodes, both enrolled
as distinct Publishers in your tenant. Netskope load-balances NPA
traffic across all online Publishers for a given Private App, so two
healthy replicas survive a single node failure with no manual action.

## Values

```yaml
workload:
  type: statefulset
  replicas: 2

enrollment:
  mode: api
  commonName: prod-eu-publisher  # becomes prod-eu-publisher-0, prod-eu-publisher-1

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: kubernetes-netskope-publisher
        topologyKey: kubernetes.io/hostname  # spread across nodes
        # use topology.kubernetes.io/zone in multi-AZ clusters

resources:
  requests:
    cpu: 500m
    memory: 384Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

## Apply

```bash
helm upgrade --install kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  -n npa-publisher -f my-values.yaml
```

## Verify

```bash
kubectl get pods -n npa-publisher -o wide
# Expect: pods on different nodes
```

In the Netskope console you'll see two Publishers with the suffixed
names. Attach the **same Private App** to both — Netskope handles the
traffic distribution.

## Scaling

`helm upgrade --set workload.replicas=3` adds a third member. Each new
pod enrolls itself via the API; no manual token shuffling.

Scale-down deletes the tenant-side Publisher record automatically via
the pod's preStop hook (since 1.3.0). Disable with
`enrollment.api.cleanupOnDelete=false` if you'd rather prune
manually — see
[delete-publisher](/kubernetes-netskope-publisher/admin/how-to/delete-publisher/).

For CPU-driven scaling without manual `helm upgrade` calls, see
[autoscaling](/kubernetes-netskope-publisher/admin/how-to/autoscaling/).
