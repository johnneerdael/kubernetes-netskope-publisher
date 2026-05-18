---
title: Roadmap
date: 2026-05-18
---

Direction-of-travel, not commitments. Open an issue if any of these
matter to you and you'd like to influence priority.

## Near-term

- **Tunnel-count HPA**. CPU-based HPA shipped in 1.3.0 —
  see [autoscaling](/kubernetes-netskope-publisher/admin/how-to/autoscaling/).
  The next step is letting the HPA target `num_snat_conns` from the
  Publisher's internal metrics file, which needs a Prometheus
  sidecar + `prometheus-adapter` (or KEDA) in the cluster.
- **Tunnel-aware readiness probe**. The current exec probe checks the
  publisher process plus on-disk config (`publisherid`, `agent.pem`,
  `nsconfig.json`, `loglevel`) — good for "did the agent start", but
  doesn't directly verify the **DTLS tunnel** is up. A probe that
  reports `NPACONNECTED` would let Kubernetes mark a Publisher
  un-ready when its tunnel drops, even if the process is still alive.
- **OpenShift `Restricted-v2`** compatibility, contingent on Netskope
  shipping a rootless Publisher image. The chart already works on
  OpenShift today via a `privileged` SCC binding — see the
  [distribution notes](/kubernetes-netskope-publisher/admin/chart/distributions/openshift/).

## Mid-term

- **GKE Autopilot** path. Pod mode is already unprivileged, but
  Autopilot still blocks the chart for two other reasons that aren't
  in chart scope to fix:
  - **`hostPath` volumes are disallowed** — pod mode mounts
    `/dev/net/tun` from the node so the Publisher can create `tun0`
    inside the pod netns. There is no Autopilot-supported alternative
    that exposes the host tun device.
  - **`capabilities.add` is restricted** to `NET_BIND_SERVICE` —
    Autopilot rejects `NET_ADMIN` and `NET_RAW`, both of which the
    Publisher needs for iptables and raw sockets on `tun0`.
  Unblocking either requires upstream work: Autopilot needs to
  whitelist these for cluster-admin-managed namespaces, or Netskope
  needs to ship a userspace-networking Publisher variant that
  doesn't need a tun device or raw capabilities.
- **Cilium NetworkPolicy** examples for egress-only restriction.
- **Prometheus metrics endpoint**. *Upstream-blocked* — the Publisher
  binary doesn't expose one today. If Netskope adds one, the chart
  will gain a `metrics:` block and a `Service` template.

## Longer-term

- **Operator** (CRD-driven) wrapping the Helm chart for multi-tenant
  installs. Worth noting: for single-tenant setups already on Helm +
  GitOps (ArgoCD/Flux), an Operator wouldn't unlock much beyond a
  different installation surface. The motivating use case is
  per-team Publisher provisioning inside a shared cluster.
- **Air-gapped enrollment** flow that doesn't require any outbound
  control-plane reachability.

## Not planned

- **Fargate / Knative / serverless** runtimes — incompatible with the
  privileged + tun device requirements.
- **Windows nodes** — the Publisher image is Linux-only upstream.
