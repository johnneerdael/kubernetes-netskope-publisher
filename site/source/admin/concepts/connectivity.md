---
title: Connectivity requirements
date: 2026-05-18
---

The Publisher initiates **all** connectivity outbound. Nothing inbound
is required.

## Outbound endpoints

| Destination | Port/proto | Purpose |
|---|---|---|
| `<tenant>.goskope.com` | 443/HTTPS | Enrollment + control plane |
| `gateway-*.gw.npa.goskope.com` (stitchers) | 443/DTLS | Tunnel uplink |
| Docker Hub (`registry-1.docker.io`, `*.cloudfront.net`) | 443/HTTPS | Pulling the Publisher image (or your private registry) |

The stitcher endpoints are resolved by **GSLB** from DNS. The pod must
be able to resolve `*.goskope.com` from inside its network namespace —
this is the most common first-run failure.

## DNS in the pod

In `networking.mode: host` the pod uses the node's `/etc/resolv.conf`.
In `networking.mode: pod` the pod uses cluster DNS (CoreDNS), which on
most clusters forwards to the node resolvers anyway. The chart also runs
a pod-local dnsmasq sidecar in pod mode. It listens on `127.0.0.1:53`
and forwards to the Kubernetes-provided resolver from `/etc/resolv.conf`,
so Kubernetes service discovery and CoreDNS forwarding rules remain in
the resolution path.

If the cluster DNS can't reach public DNS, fix CoreDNS or the node
resolver path. If private domains need authoritative DNS, add
domain-specific forwarding to CoreDNS.

### Forward private domains with CoreDNS

Use this when the Publisher must resolve names such as
`app1.private.example.com`, and those records live on internal DNS
servers instead of public DNS.

First, collect three values from your environment:

| Placeholder | Replace with |
|---|---|
| `private.example.com` | The private DNS zone suffix, without a leading dot. For example: `corp.example.com`, `example.local`, or `ad.company.net`. |
| `10.0.0.10 10.0.0.11` | The IP addresses of the DNS servers authoritative for that private zone. Use IP addresses, not DNS names. |
| `kube-system/coredns` | The CoreDNS ConfigMap. This is the default for kubeadm, EKS, GKE, k3s, kind, and many other clusters. Some managed distributions customize this; check your provider docs if this ConfigMap does not exist. |

Back up the current CoreDNS configuration:

```bash
kubectl -n kube-system get configmap coredns -o yaml > coredns-backup.yaml
```

Open the CoreDNS ConfigMap for editing:

```bash
kubectl -n kube-system edit configmap coredns
```

Find `data.Corefile`. It normally contains an existing root block that
starts with `.:53 {` and includes the Kubernetes DNS plugin:

```text
.:53 {
    errors
    health
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
    }
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
```

Add a second block for the private domain at the same indentation level
as `.:53`. Do not put it inside the `.:53` block:

```text
private.example.com:53 {
    errors
    cache 30
    forward . 10.0.0.10 10.0.0.11
}
```

After saving, restart CoreDNS so the change is applied immediately:

```bash
kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns
```

Test both Kubernetes service discovery and the private zone from a
temporary pod:

```bash
kubectl run dns-test --rm -it --restart=Never \
  --image=busybox:1.36 \
  -- nslookup kubernetes.default.svc.cluster.local

kubectl run dns-test-private --rm -it --restart=Never \
  --image=busybox:1.36 \
  -- nslookup app1.private.example.com
```

Both lookups should succeed before installing or restarting the
Publisher. If the private lookup fails, verify that the DNS server IPs
are reachable from the CoreDNS pods and that the private zone suffix is
correct.

Do not set `bind.forwarders` in pod mode; Helm rejects that
configuration because it bypasses cluster DNS and can break Kubernetes
service discovery. In host mode, `bind.forwarders` still configures the
legacy in-container BIND9 path. See
[troubleshooting](/kubernetes-netskope-publisher/admin/operations/troubleshooting/)
for diagnosing DNS resolution loops.

Kubernetes documents this as CoreDNS stub-domain forwarding with the
CoreDNS `forward` plugin. See
[Customizing DNS Service](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/)
for the upstream Kubernetes reference.

## Egress proxy

Set `proxy.enabled: true` and provide `httpProxy` / `httpsProxy` /
`noProxy`. The init container honors these for the REST API calls; the
Publisher binary honors them for stitcher GSLB resolution.

> ⚠️ The DTLS tunnel itself **cannot** be proxied. Outbound 443/UDP to
> stitcher IPs must be permitted directly.

## NAT / outbound IP

Netskope expects a stable egress IP per Publisher for predictable
policy attribution. Run Publishers behind a NAT gateway with a fixed
public IP, not a per-pod ephemeral SNAT.
