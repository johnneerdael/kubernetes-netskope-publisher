---
title: Autoscaling
date: 2026-05-18
---

CPU-based autoscaling on the StatefulSet path, with automatic
tenant-side cleanup on scale-down.

## Prerequisites

- `workload.type: statefulset` (HPA doesn't make sense for a
  DaemonSet — one pod per node is the design).
- `enrollment.mode: api` so the chart can self-enrol new replicas
  without operator intervention.
- A working **metrics-server** in the cluster
  (`kubectl top pods -n npa-publisher` should return data). All
  managed Kubernetes flavours ship it by default; bare-metal
  clusters may need [installation](https://github.com/kubernetes-sigs/metrics-server).

## Enable

```yaml
workload:
  type: statefulset
  replicas: 2          # baseline, also used as HPA minReplicas if you don't override

enrollment:
  mode: api
  commonName: prod-eu-publisher
  api:
    baseUrl: https://tenant.goskope.com
    existingSecret: npa-api-token
    tokenKey: api-token

hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 70
```

Apply with the usual `helm upgrade --install`. The chart renders a
`HorizontalPodAutoscaler` targeting the StatefulSet:

```text
$ kubectl get hpa -n npa-publisher
NAME                              REFERENCE                                  TARGETS    MINPODS   MAXPODS   REPLICAS
kubernetes-netskope-publisher     StatefulSet/kubernetes-netskope-publisher  35%/70%    2         6         2
```

## What happens on scale-up

1. HPA observes average CPU above target → patches the StatefulSet's
   `replicas`.
2. Kubernetes creates a new pod (`<release>-N`).
3. The new pod runs `npa-bootstrap`, calls the Netskope API with
   `commonName-<pod-name>`, gets a publisher_id, enrols.
4. Once `NPACONNECTED` shows up in the publisher logs, Netskope
   load-balancers route new private-app sessions to the new
   replica.

No manual token shuffling. Each replica is an independent
identity in the Netskope console.

## What happens on scale-down

1. HPA observes CPU below target → patches replicas down.
2. Kubernetes terminates the highest-ordinal pod first.
3. The Publisher record stays in the Netskope tenant. **By default
   the chart does not delete it** — see the warning below.

> ⚠️ **Why scale-down doesn't auto-delete by default**
>
> The Netskope API refuses to delete a Publisher that has Private
> Apps attached (`/api/v2/infrastructure/publishers/{id}` returns
> an error). Many tenants attach apps to every Publisher in a
> region for load balancing — including the auto-scaled replicas.
> An automatic DELETE would silently fail on those, leaving both
> orphan Publisher records and stranded app attachments to chase.
>
> Reconciling orphans periodically via the [delete-publisher](/kubernetes-netskope-publisher/admin/how-to/delete-publisher/)
> flow is safer than racing the lifecycle.

## Opt-in: auto-delete on scale-down

If you're certain auto-scaled replicas **never** carry app
assignments — e.g. you only attach apps to a fixed baseline
Publisher and let the scaled replicas inherit traffic via DTLS
load-balancing only:

```yaml
enrollment:
  api:
    cleanupOnDelete: true
```

The pod's preStop hook then fires on termination:

```bash
# Inside the pod, at termination time:
curl -X DELETE \
  -H "Authorization: Bearer $NPA_API_TOKEN" \
  "$NPA_API_BASE_URL/api/v2/infrastructure/publishers/$(cat /home/resources/publisherid)"
```

The hook is **best-effort**. It exits 0 on any failure (including
the "Publisher has apps attached" rejection) so the pod terminates
promptly. If you turn this on and your assumption later changes,
the worst outcome is silent orphans rather than blocked pods.

## Why CPU and not tunnel-count

CPU is what's available without extra infrastructure. The Publisher
does report active SNAT connection counts (`num_snat_conns`)
internally, but it doesn't expose them as Prometheus metrics — they
go up to the Netskope stitcher control plane instead. Wiring those
into HPA would require a sidecar that reads the internal
`publisher_metrics` file and serves Prometheus, plus
`prometheus-adapter` or KEDA in the cluster. That's tracked on the
[roadmap](/kubernetes-netskope-publisher/reference/roadmap/).

In practice, CPU tracks tunnel count well enough: more active
sessions → more packet processing → more CPU. Tune
`targetCPUUtilizationPercentage` based on observed load.

## Tuning scale policies

The HPA `behavior` block (Kubernetes [v2 spec](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior))
lets you slow down scale-up or scale-down. Useful because
Publisher enrollment takes ~30–60 seconds, so you may want to
delay scale-up reactions to avoid flapping:

```yaml
hpa:
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60       # at most 1 new replica per minute
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120      # at most 1 fewer replica every 2 minutes
```

