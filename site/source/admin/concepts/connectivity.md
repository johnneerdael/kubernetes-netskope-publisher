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
most clusters forwards to the node resolvers anyway.

If the cluster DNS can't reach public DNS, set explicit forwarders:

```yaml
bind:
  forwarders:
    - "8.8.8.8"
    - "8.8.4.4"
```

The chart's built-in BIND9 forwarder will then use those for everything
under `*.goskope.com`. See
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
