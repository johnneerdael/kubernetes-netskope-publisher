---
title: Configure your shell
date: 2026-05-18
---

Two things need to be in place before `helm install`:

1. `kubectl` can talk to the cluster.
2. Helm can read the published OCI chart or a local chart clone.

## kubectl

If you installed k3s on the same host you're running commands from:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes
```

If you're running `kubectl` from a different machine, copy
`/etc/rancher/k3s/k3s.yaml`, replace `127.0.0.1` in the `server:` field
with the VM's reachable IP, and set `KUBECONFIG` to that file.

## Helm chart source

The chart is listed on
[Artifact Hub](https://artifacthub.io/packages/helm/kubernetes-netskope-publisher/kubernetes-netskope-publisher)
and published as an OCI chart in GitHub Container Registry.

### Option A — OCI chart

```bash
helm show chart oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher --version 1.4.2
```

You should see chart metadata for `kubernetes-netskope-publisher` with
`version: 1.4.2`.

### Option B — local clone

If you cloned the repository locally, run Helm from the directory that
contains the clone and use the local chart path:

```bash
helm install kubernetes-netskope-publisher ./kubernetes-netskope-publisher \
  --namespace npa-publisher \
  -f my-values.yaml
```

Use the OCI URL in the next install step unless you are intentionally
testing a local checkout.
