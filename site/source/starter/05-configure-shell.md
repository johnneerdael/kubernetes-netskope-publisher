---
title: Configure your shell
date: 2026-05-18
---

Two things need to be in place before `helm install`:

1. `kubectl` can talk to the cluster.
2. The Helm chart repository is added locally.

## kubectl

If you installed k3s on the same host you're running commands from:

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes
```

If you're running `kubectl` from a different machine, copy
`/etc/rancher/k3s/k3s.yaml`, replace `127.0.0.1` in the `server:` field
with the VM's reachable IP, and set `KUBECONFIG` to that file.

## Helm chart source

The chart is published in two places that ship the same release —
pick whichever your Helm client supports.

### Option A — Classic Helm repository (works on any Helm 3.x)

```bash
helm repo add npa https://johnneerdael.github.io/kubernetes-netskope-publisher
helm repo update
helm search repo npa/kubernetes-netskope-publisher
```

You should see:

```text
NAME                                 CHART VERSION  APP VERSION  DESCRIPTION
npa/kubernetes-netskope-publisher    1.4.0          1.4.0        Netskope Private Access Publisher for Kubernetes
```

> If the repo doesn't list yet (404 on `index.yaml`), the first chart
> release workflow hasn't run yet. You can install directly from the
> source as a fallback: `git clone … && helm install kubernetes-netskope-publisher ./kubernetes-netskope-publisher`.

### Option B — OCI registry (Helm 3.8+, no `repo add` step)

The chart is also pushed to GitHub Container Registry as an OCI
artifact. There's no equivalent of `helm search repo` for OCI, but
`helm show chart` works against the OCI URL directly:

```bash
helm show chart oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher --version 1.4.0
```

You'll use this URL in place of `npa/kubernetes-netskope-publisher` in
the subsequent `helm install` step.
