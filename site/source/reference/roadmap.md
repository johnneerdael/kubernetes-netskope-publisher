---
title: Roadmap
date: 2026-05-18
---

Direction-of-travel, not commitments. Open an issue if any of these
matter to you and you'd like to influence priority.

## Near-term

- **HorizontalPodAutoscaler** support for the StatefulSet path, driven
  by tunnel count or CPU.
- **Native readiness probe** that checks tunnel state, not just the TCP
  listener.
- **OpenShift `Restricted-v2`** compatibility once Netskope publishes a
  rootless Publisher image.

## Mid-term

- **GKE Autopilot** path once Autopilot relaxes `privileged` for
  cluster-admin-managed namespaces (or a non-privileged Publisher
  variant lands).
- **Cilium NetworkPolicy** examples for egress-only restriction.
- **Prometheus metrics endpoint** exposed by the Publisher binary.

## Longer-term

- **Operator** (CRD-driven) wrapping the Helm chart for multi-tenant
  installs.
- **Air-gapped enrollment** flow that doesn't require any outbound
  control-plane reachability.

## Not planned

- **Fargate / Knative / serverless** runtimes — incompatible with the
  privileged + tun device requirements.
- **Windows nodes** — the Publisher image is Linux-only upstream.
