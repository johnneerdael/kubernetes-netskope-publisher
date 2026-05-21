---
title: Your first Publisher
date: 2026-05-18
---

Time to install. Replace `tenant.goskope.com`, the Publisher name, and
credential values with values for your environment.

## 1. Create the namespace and API credential Secret

The default starter path uses a static API token:

```bash
kubectl create namespace npa-publisher

kubectl create secret generic npa-api-token \
  --namespace npa-publisher \
  --from-literal=api-token='PASTE_NETSKOPE_API_TOKEN_HERE'
```

If you use OAuth2 client credentials instead, create this Secret:

```bash
kubectl create namespace npa-publisher

kubectl create secret generic npa-api-oauth \
  --namespace npa-publisher \
  --from-literal=client-id='PASTE_CLIENT_ID_HERE' \
  --from-literal=client-secret='PASTE_CLIENT_SECRET_HERE'
```

## 2. Write `my-values.yaml`

For a static API token:

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
```

For OAuth2 client credentials, use the same file but replace the
`enrollment.api` block with:

```yaml
enrollment:
  mode: api
  commonName: prod-k8s-publisher
  api:
    baseUrl: https://tenant.goskope.com
    authMode: oauth2
    oauth2:
      tokenUrl: https://tenant.goskope.com/oauth2/token
      existingSecret: npa-api-oauth
      clientIdKey: client-id
      clientSecretKey: client-secret
```

> The default chart values use `networking.mode: pod`. It avoids host
> network coupling and uses a pod-local dnsmasq sidecar that forwards to
> Kubernetes cluster DNS. See
> [pod-vs-host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/).

## 3. Install

```bash
helm install kubernetes-netskope-publisher oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher \
  --version 1.4.2 \
  --namespace npa-publisher \
  -f my-values.yaml
```

You'll see Helm print the rendered NOTES.txt with the next-step
commands. Continue to [verify it's online](/kubernetes-netskope-publisher/starter/07-verify-online/).
