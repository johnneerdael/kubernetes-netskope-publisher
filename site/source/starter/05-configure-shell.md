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

## Helm repository

```bash
helm repo add npa https://johnneerdael.github.io/kubernetes-netskope-publisher
helm repo update
helm search repo npa/kubernetes-netskope-publisher
```

You should see:

```text
NAME                 CHART VERSION  APP VERSION  DESCRIPTION
npa/kubernetes-netskope-publisher    1.0.0          1.0.0        Netskope Private Access Publisher for Kubernetes
```

> If the repo doesn't list yet (404 on `index.yaml`), the first chart
> release workflow hasn't run yet. You can install directly from the
> repo as a fallback: `git clone … && helm install kubernetes-netskope-publisher ./kubernetes-netskope-publisher`.
