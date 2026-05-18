---
title: Changelog
date: 2026-05-18
---

Hand-maintained — mirrors `Chart.yaml` `version:` bumps. See the
GitHub Releases page for the published artifacts.

## v1.0.1 — 2026-05-18

- Switch chart icon to the Pages-hosted favicon (the previous Netskope
  CDN URL had 404'd). No functional change.

## v1.0.0 — 2026-05-18

- Initial public release of the Helm chart.
- DaemonSet and StatefulSet workload modes.
- API enrollment (`enrollment.mode: api`) and token enrollment.
- `networking.mode: host` (legacy) and `networking.mode: pod` (default
  for new clusters).
- Optional persistence via PVC.
- BIND9 in-pod forwarder with configurable upstream resolvers.
- Optional egress proxy support.
- Optional `customSettings` ConfigMap override of `settings.json`.
