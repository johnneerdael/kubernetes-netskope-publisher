---
title: Your first Publisher
date: 2026-05-18
---

Time to install. Replace `tenant.goskope.com`, the Publisher name, and
the DNS forwarders with values for your environment.

## 1. Create the namespace and API token Secret

```bash
kubectl create namespace npa-publisher

kubectl create secret generic npa-api-token \
  --namespace npa-publisher \
  --from-literal=api-token='PASTE_NETSKOPE_API_TOKEN_HERE'
```

## 2. Write `my-values.yaml`

```yaml
image:
  repository: netskopeprivateaccess/publisher_u22
  pullPolicy: IfNotPresent
  tag: latest

workload:
  type: daemonset
  replicas: 1

networking:
  mode: pod              # pod network mode is the default for new deploys
  disableIPv6: true

tunDevice:
  enabled: true
  hostPath: /dev/net/tun
  mountPath: /dev/net/tun

persistence:
  enabled: false

enrollment:
  mode: api
  commonName: prod-k8s-publisher        # name shown in Netskope console
  api:
    baseUrl: https://tenant.goskope.com # no trailing slash
    existingSecret: npa-api-token
    tokenKey: api-token

bind:
  forwarders:
    - "8.8.8.8"
    - "8.8.4.4"
```

> The default chart values use `networking.mode: host` for backward
> compatibility. For new clusters, **prefer `pod`** — it avoids host
> network coupling and works on managed Kubernetes without privileged
> host-network exceptions. See
> [pod-vs-host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/).

## 3. Install

```bash
helm install npa-publisher npa/npa-publisher \
  --namespace npa-publisher \
  -f my-values.yaml
```

You'll see Helm print the rendered NOTES.txt with the next-step
commands. Continue to [verify it's online](/kubernetes-netskope-publisher/starter/07-verify-online/).
