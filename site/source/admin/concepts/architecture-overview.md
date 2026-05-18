---
title: Architecture overview
date: 2026-05-18
---

```text
            Netskope tenant ( *.goskope.com )
                    ▲
                    │  outbound 443 + DTLS to stitchers
                    │
  ┌─────────────────┴─────────────────┐
  │             Pod (publisher)        │
  │                                    │
  │  init: npa-bootstrap               │
  │    - resolves tenant URL           │
  │    - mints/looks up Publisher via  │
  │      Netskope REST API             │
  │    - writes /etc/npa registration  │
  │                                    │
  │  container: publisher              │
  │    - starts BIND9 forwarder        │
  │    - configures iptables + sysctl  │
  │    - creates tun0                  │
  │    - runs npa_publisher binary     │
  └────────────────────────────────────┘
```

## What the chart deploys

| Object | Purpose |
|---|---|
| `DaemonSet` *or* `StatefulSet` | Hosts the Publisher pod(s). Choice via `workload.type`. |
| `Headless Service` | Stable network identity for StatefulSet members. |
| `ConfigMap` | Optional override of `settings.json` (`customSettings.enabled`). |
| `Secret` | Receives the registration token in `mode: token`. In `mode: api` you bring your own API-token Secret. |
| `PersistentVolumeClaim` | Optional, when `persistence.enabled: true`. |
| `ServiceAccount` | For API-mode pods to call kube API if needed (currently no in-cluster RBAC required). |

## Container layout

A single pod contains:

1. **init container** (`npa-bootstrap`) — performs enrollment exactly
   once per pod start, then exits.
2. **publisher container** — runs the long-lived `npa_publisher` binary,
   plus a BIND9 forwarder for stitcher GSLB resolution.

The publisher binary owns the `tun0` interface inside the pod (or the
host, depending on `networking.mode`).

## What it does **not** do

- Run any controller pod.
- Mutate cluster-wide resources outside the install namespace.
- Provide a CRD. Configuration is plain Helm values.
