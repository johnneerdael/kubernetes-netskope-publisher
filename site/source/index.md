---
title: kubernetes-netskope-publisher
date: 2026-05-18
---

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/kubernetes-netskope-publisher)](https://artifacthub.io/packages/helm/kubernetes-netskope-publisher/kubernetes-netskope-publisher)

Deploy Netskope Private Access (NPA) Publishers on **any Kubernetes
distribution** from a single Helm chart — k3s, kind, EKS, AKS, GKE,
OpenShift, or bare-metal.

- New to Kubernetes? → [Starter Guide](/kubernetes-netskope-publisher/starter/)
- Looking for chart values, distribution notes? → [Admin Guides](/kubernetes-netskope-publisher/admin/)
- Kubernetes/Helm matrix, changelog, roadmap → [Reference](/kubernetes-netskope-publisher/reference/)

## Install

Use the Artifact Hub package page to inspect releases and values, then
install the OCI chart from GitHub Container Registry.

```bash
helm install kubernetes-netskope-publisher oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher \
  --version 1.4.2 \
  --namespace npa-publisher --create-namespace \
  -f my-values.yaml
```

For local chart development, clone the repository and run Helm from the
directory that contains the clone:

```bash
helm install kubernetes-netskope-publisher ./kubernetes-netskope-publisher \
  --namespace npa-publisher --create-namespace \
  -f my-values.yaml
```

A working `my-values.yaml` for API enrollment is in the
[Quickstart](/kubernetes-netskope-publisher/starter/06-first-publisher/).
