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

```bash
helm upgrade kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  -n npa-publisher \
  -f my-values.yaml \
  --set image.tag=100.0.0.5678
```

This triggers a rolling restart:

- **StatefulSet**: pods restart one-by-one. Each goes through init →
  re-enroll → tunnel-up before the next one is touched.
- **DaemonSet**: same rolling behaviour; the chart sets a
  `maxUnavailable: 1` strategy.

There is **no in-place binary upgrade** — the container image is
replaced wholesale, and the pod restarts.

## Upgrading the chart

```bash
helm repo update
helm upgrade kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  -n npa-publisher \
  -f my-values.yaml
```

Read the [changelog](/kubernetes-netskope-publisher/reference/changelog/)
first for any breaking values changes.

## Coordinating with the Netskope tenant

Netskope publishes upgrade profiles that pin which Publisher version is
allowed in a given window. If your tenant has profiles configured:

- The agent honours the profile and **refuses to run a version outside
  the allowed range**, even if you pull a newer image.
- Align `image.tag` with the profile-allowed range before rolling out.

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
