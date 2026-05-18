---
title: OpenShift
date: 2026-05-18
---

OpenShift's Security Context Constraints (SCC) gate every capability
the Publisher needs. The chart's ServiceAccount must be granted the
`privileged` SCC.

## Bind SCC to the ServiceAccount

```bash
oc create namespace npa-publisher
helm install npa-publisher npa/npa-publisher \
  --namespace npa-publisher \
  -f my-values.yaml

# Grant privileged SCC to the ServiceAccount the chart created
oc adm policy add-scc-to-user privileged \
  -z $(kubectl get sa -n npa-publisher \
       -l app.kubernetes.io/name=npa-publisher \
       -o jsonpath='{.items[0].metadata.name}') \
  -n npa-publisher

# Force pods to be recreated under the new SCC
kubectl rollout restart -n npa-publisher \
  daemonset/npa-publisher || \
  kubectl rollout restart -n npa-publisher \
  statefulset/npa-publisher
```

## Recommended values

```yaml
workload:
  type: statefulset
  replicas: 2

networking:
  mode: pod
  disableIPv6: true

tunDevice:
  enabled: true

hostNetwork: false
dnsPolicy: ClusterFirst
```

## Quirks

- **SELinux:** the Publisher writes to `/etc/npa`. The default `restricted-v2`
  SCC blocks this; `privileged` is required.
- **OpenShift on ROSA/ARO:** same SCC binding works.
- **OVN-Kubernetes vs OpenShift SDN:** both work in `mode: pod`.
