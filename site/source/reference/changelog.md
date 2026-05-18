---
title: Changelog
date: 2026-05-18
---

Hand-maintained — mirrors `Chart.yaml` `version:` bumps. See the
GitHub Releases page for the published artifacts.

## v1.1.0 — 2026-05-18

Defaults overhaul. Values surface unchanged — only defaults moved.

- **`networking.mode`** defaults to **`pod`** (was `host`). Together
  with this, the default `hostNetwork` flips to `false` and
  `dnsPolicy` to `ClusterFirst`. This makes the out-of-the-box install
  work on EKS / AKS / GKE / OpenShift without privileged-host-network
  exemptions. **Upgrade hazard for existing 1.0.x installs** — if
  you've been running host-mode and haven't pinned `networking.mode`,
  set it explicitly in your values before `helm upgrade`.
- **`serviceAccount.create`** defaults to `false`. The chart makes no
  Kubernetes API calls; the namespace's default ServiceAccount is
  sufficient. Re-enable creation if you want to attach IRSA, Workload
  Identity, or per-SA imagePullSecrets.
- **Memory resources** bumped — `limits.memory` `1Gi` → `1536Mi`,
  `requests.memory` `384Mi` → `1024Mi`. CPU unchanged.
- **Removed** the dead `livenessProbe:` / `readinessProbe:` value
  blocks. They were never read — the DaemonSet/StatefulSet template
  hardcodes `exec` probes that check the publisher process plus its
  on-disk state. Probes are not parameterisable today.
- Annotated `securityContext`, `hostNetwork`, and `dnsPolicy` in
  `values.yaml` to make explicit that they only take effect in
  `networking.mode: host`.

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
