---
title: Upgrading Publisher software
date: 2026-05-18
---

There are two version axes:

1. **Chart version** (`Chart.yaml` → `version:`) — controls templates,
   values schema, RBAC.
2. **Publisher version** (`image.tag` → the binary) — controls the agent.

You can move them independently.

## Upgrading the Publisher binary

Prefer a pinned published image tag for upgrades. Choose the tag from
the published Publisher image tags on Docker Hub:
<https://hub.docker.com/r/netskopeprivateaccess/publisher_u22/tags>.

```bash
helm upgrade kubernetes-netskope-publisher oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher \
  --version 1.4.2 \
  -n npa-publisher \
  -f my-values.yaml \
  --set image.tag=10784
```

Changing `image.tag` changes the pod template, so Kubernetes performs a
rolling restart:

- **StatefulSet**: pods restart one-by-one. Each goes through init →
  re-enroll → tunnel-up before the next one is touched.
- **DaemonSet**: same rolling behaviour; the chart sets a
  `maxUnavailable: 1` strategy.

There is **no in-place binary upgrade** — the container image is
replaced wholesale, and the pod restarts.

### About `latest`

The chart defaults to `image.tag=latest` for first-time installs, but
`latest` is not a deterministic upgrade target. With the default
`image.pullPolicy=IfNotPresent`, a node can reuse its cached
`latest` image, and if the rendered pod spec does not change, Kubernetes
has no reason to restart the pods.

Use `latest` only for disposable test environments. If you do, force a
pull and a rollout explicitly:

```bash
helm upgrade kubernetes-netskope-publisher oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher \
  --version 1.4.2 \
  -n npa-publisher \
  -f my-values.yaml \
  --set image.tag=latest \
  --set image.pullPolicy=Always

kubectl rollout restart daemonset/kubernetes-netskope-publisher -n npa-publisher
```

For StatefulSet mode, restart the StatefulSet instead:

```bash
kubectl rollout restart statefulset/kubernetes-netskope-publisher -n npa-publisher
```

## Upgrading the chart

```bash
helm upgrade kubernetes-netskope-publisher oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher \
  --version 1.4.2 \
  -n npa-publisher \
  -f my-values.yaml
```

Read the [changelog](/kubernetes-netskope-publisher/reference/changelog/)
first for any breaking values changes.

## Netskope auto-upgrade profiles

Do not assign chart-managed Publishers to a Netskope auto-upgrade
profile. The Helm chart controls the container image tag and Kubernetes
rollout. A cloud-side auto-upgrade profile cannot update the Helm
release, change `image.tag`, or trigger the Kubernetes rollout needed to
replace the Publisher container image.

Keep Publisher binary changes in source-controlled Helm values and roll
them out with `helm upgrade`. If an existing Publisher record has an
auto-upgrade profile assigned, remove that assignment before managing it
with this chart.

## Rollback

```bash
helm rollback kubernetes-netskope-publisher <revision> -n npa-publisher
```

Helm tracks revision history. `helm history kubernetes-netskope-publisher -n npa-publisher`
shows what's available.

## Drain windows

Each Publisher restart drops in-flight DTLS tunnels. End-user app
sessions reconnect — typically <5 s — but it's not invisible. For
zero-impact upgrades, run an [HA pair](/kubernetes-netskope-publisher/admin/how-to/ha-pair/)
and roll one at a time.
