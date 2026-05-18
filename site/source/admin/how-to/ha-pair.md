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
            app.kubernetes.io/name: npa-publisher
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
helm upgrade --install npa-publisher npa/npa-publisher \
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
pod enrolls itself; no manual token shuffling.

> ⚠️ Don't scale down by deleting the StatefulSet PVC or kubectl
> deleting pods. Use `helm upgrade --set workload.replicas=N`. The
> orphaned Publisher records in the tenant should then be deleted via
> [delete-publisher](/kubernetes-netskope-publisher/admin/how-to/delete-publisher/).
