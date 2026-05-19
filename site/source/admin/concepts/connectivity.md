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
domain-specific forwarding to CoreDNS:

```text
private.example.com:53 {
    errors
    cache 30
    forward . 10.0.0.10 10.0.0.11
}
```

Do not set `bind.forwarders` in pod mode; Helm rejects that
configuration because it bypasses cluster DNS and can break Kubernetes
service discovery. In host mode, `bind.forwarders` still configures the
legacy in-container BIND9 path. See
[troubleshooting](/kubernetes-netskope-publisher/admin/operations/troubleshooting/)
for diagnosing DNS resolution loops.

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
