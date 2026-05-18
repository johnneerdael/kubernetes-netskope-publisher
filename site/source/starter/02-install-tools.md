---
title: Install the tools
date: 2026-05-18
---

You need two CLIs on your local workstation (or directly on the Linux VM):

- **kubectl** — talks to the cluster
- **Helm 3** — installs the chart

> The Publisher itself runs in-cluster. You only need these tools where
> you'll run `helm install` from.

## Linux / macOS

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

On macOS, swap `linux/amd64` for `darwin/arm64` (Apple Silicon) or
`darwin/amd64` (Intel), or just use Homebrew:

```bash
brew install kubectl helm
```

## Windows (PowerShell)

```pwsh
winget install -e --id Kubernetes.kubectl
winget install -e --id Helm.Helm
```

## Verify

```bash
kubectl version --client
helm version
```

Both should print versions and exit cleanly. **Next**: spin up a cluster.
