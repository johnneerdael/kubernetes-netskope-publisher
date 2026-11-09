---
title: Changelog
date: 2026-05-18
---

Hand-maintained — mirrors `Chart.yaml` `version:` bumps. See the
GitHub Releases page for the published artifacts.

## v1.6.0 — 2026-11-09

Token mode for multiple replicas, with Terraform-issued registration tokens.

- **Added — `registrationToken.keyBy`** (`single` | `ordinal` | `node`).
  Token mode now runs as a StatefulSet: replica N enrolls with Secret
  key `"N"`. A DaemonSet can pick its token by node name. This pairs
  with `netskope_npa_publisher` + `netskope_npa_publisher_token` from
  the official Netskope Terraform provider, so the cluster holds no
  Netskope API credential. Start with the customer guide
  [Deploy Publisher replicas with the Netskope Terraform provider](/kubernetes-netskope-publisher/admin/how-to/terraform-replicas/).
  See also
  [Terraform-issued tokens](/kubernetes-netskope-publisher/admin/how-to/terraform-token-enrollment/)
  and `examples/terraform-token-enrollment/`.
- **Added — `registrationToken.tokens`** chart-managed key → token map.
- **Added — idempotent token enrollment.** The `enroll` init container
  skips enrollment when persisted state matches the current token
  fingerprint and re-enrolls when a new token is delivered, restoring
  the previous state on failure. Pod recreation no longer burns or
  re-uses a spent token.
- **Added — `persistence.type: hostPath`** for per-node DaemonSet state.
- **Changed — StatefulSet persistence uses `volumeClaimTemplates`**
  (one PVC per replica) instead of one shared claim. **Upgrade note:**
  `volumeClaimTemplates` is immutable on an existing StatefulSet. If
  you ran `workload.type=statefulset` with `persistence.enabled=true`,
  delete the StatefulSet with `kubectl delete statefulset <name>
  --cascade=orphan` before `helm upgrade`.
- **Validation** — the chart now rejects token mode without a token
  source, `hpa.enabled` with token mode, missing per-replica keys,
  hostPath persistence on StatefulSets, and `existingClaim` on
  StatefulSets.

## v1.5.0 — 2026-06-08

StatefulSet replica naming and API publisher-creation fixes.

- **Fixed — StatefulSet replica names.** Replicas now register as
  `<commonName>-<ordinal>` (e.g. `npa-publisher-0`, `npa-publisher-1`)
  instead of `<commonName>-<full-pod-name>`
  (`npa-publisher-kubernetes-netskope-publisher-0`). The chart appends
  only the StatefulSet ordinal. The internal enrollment toggle was
  renamed `NPA_COMMON_NAME_APPEND_POD_NAME` → `NPA_COMMON_NAME_APPEND_ORDINAL`.
  **Behaviour change:** existing StatefulSet deployments that already
  enrolled under the old long names will create new `<commonName>-N`
  Publisher records on next pod start; prune the stale long-named
  records from the tenant after upgrading.
- **Fixed — publisher creation labels.** The create-Publisher request
  now always includes a `labels` array, fixing
  `Labels are not present in the request` rejections on tenants that
  require it.
- **Added — `enrollment.api.publisherLabels`.** Supply tenant-required
  publisher labels (defaults to `[]`).

## v1.3.2 — 2026-05-19

Ship `values.schema.json` at the chart root.

- Helm now validates `--set` / `-f` overrides against the schema on
  install and upgrade — typos and wrong-type values fail loudly
  instead of rendering quietly bad manifests.
- Artifact Hub renders the schema as an interactive **Values
  schema** tab on the listing.

The schema covers every key the chart actually exposes (image,
workload, hpa, enrollment, networking, persistence, proxy, bind,
etc.) with enum constraints on `enrollment.mode`, `networking.mode`,
`workload.type`, and `image.pullPolicy`. `resources` and `affinity`
stay permissive (pass-through to Kubernetes types).

## v1.3.1 — 2026-05-18

Flip `enrollment.api.cleanupOnDelete` to default **off**. The Netskope
API refuses to delete a Publisher with Private Apps attached, so the
1.3.0 default of `true` could silently fail on scale-down — leaving
orphan Publisher records *and* stranded app assignments to chase. The
hook is still available; you just have to opt in (`cleanupOnDelete:
true`) and confirm that your auto-scaled replicas never carry app
assignments.

If you're already on 1.3.0, the new release also pulls in the
slimmed example values and the AH-aligned install path from the
1.1.1 docs work.

## v1.3.0 — 2026-05-18

Autoscaling and orphan-Publisher cleanup.

- **HorizontalPodAutoscaler** template for the StatefulSet path.
  CPU-based, autoscaling/v2 API. Enable with `hpa.enabled=true` and
  tune `hpa.minReplicas` / `hpa.maxReplicas` /
  `hpa.targetCPUUtilizationPercentage`. Optional `hpa.behavior`
  block for scale-up/scale-down policies. Silently ignored when
  `workload.type=daemonset`.
- **Pod preStop hook** in API mode that deletes the tenant-side
  Publisher record on every pod termination (HPA scale-down,
  `helm uninstall`, node drain). Best-effort: failures do not
  block termination, so a network glitch or expired token just
  leaves the record for manual cleanup. Disable with
  `enrollment.api.cleanupOnDelete=false`.

See [autoscaling](/kubernetes-netskope-publisher/admin/how-to/autoscaling/)
for the full setup.

## v1.2.0 — 2026-05-18

`securityContext`, `hostNetwork`, and `dnsPolicy` are no longer
exposed as values keys. The chart now derives all three from
`networking.mode`:

|  | `networking.mode: pod` (default) | `networking.mode: host` |
|---|---|---|
| `securityContext` | `privileged: false`, `NET_ADMIN`, `NET_RAW`, `runAsUser: 0` | `privileged: true`, `NET_ADMIN`, `NET_RAW`, `runAsUser: 0` |
| `hostNetwork` | `false` | `true` |
| `dnsPolicy` | `ClusterFirst` | `ClusterFirstWithHostNet` |

Previously `securityContext` was overridable via values, but only
in host mode — pod mode silently hardcoded its own block. That
asymmetry made `values.yaml` look like it ran the Publisher
privileged even in pod mode (which it doesn't). The new design
makes the helper authoritative for both modes, and `values.yaml`
honest.

**Upgrade hazard**: if your values file overrode `securityContext`,
`hostNetwork`, or `dnsPolicy`, those overrides are now silently
ignored. Remove them and switch `networking.mode` instead.

## v1.1.1 — 2026-05-18

Docs-only release so Artifact Hub picks up the new README.

- README leads with the published chart install path instead of the
  local-clone path; local-clone install becomes a developer footnote.
- Slimmed example values to only the keys that aren't covered by
  1.1.0 defaults (pod networking, tunDevice, persistence: false, and
  IPv6-disable are all default now).
- Replaced every remaining local-path install/upgrade example in the
  deep-dive sections so the advice stays consistent end-to-end.
- Fixed a stale clone URL in the k3s setup section.
- `release.yml` now also fires on `README.md` changes so future
  README updates ship to Artifact Hub on the next push.

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
