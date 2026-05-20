# Unoffical Netskope NPA Publisher — Kubernetes Deployment Guide

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/kubernetes-netskope-publisher)](https://artifacthub.io/packages/helm/kubernetes-netskope-publisher/kubernetes-netskope-publisher)

The Helm chart is published on [Artifact Hub](https://artifacthub.io/packages/helm/kubernetes-netskope-publisher/kubernetes-netskope-publisher) and served as a Helm repository at
<https://johnneerdael.github.io/kubernetes-netskope-publisher>.

This guide walks you through deploying the Netskope Private Access (NPA) Publisher with Helm. The recommended beginner path uses a single-node k3s cluster because it keeps the Kubernetes setup small, local to one Linux host, and friendly to operators who have not run Kubernetes before.

The same Helm chart can also run on managed or self-managed Kubernetes platforms. Those architectures are covered as reference options after the k3s path so the first deployment stays simple.

---

## Quickstart

Use this path to deploy with API enrollment, then validate startup from logs. Replace the tenant URL, API token, and Publisher name for your environment. Everything else uses chart defaults (pod networking, pod-local dnsmasq, daemonset workload, no persistence).

```bash
# Add the chart repository (one-time)
helm repo add npa https://johnneerdael.github.io/kubernetes-netskope-publisher
helm repo update

# Create namespace + API-token Secret
kubectl create namespace npa-publisher

kubectl create secret generic npa-api-token \
  --namespace npa-publisher \
  --from-literal=api-token='PASTE_NETSKOPE_API_TOKEN_HERE'

# Tenant-specific values (only the keys the chart can't infer)
cat > my-api-config.yaml <<'EOF'
enrollment:
  mode: api
  commonName: "prod-k8s-publisher"
  api:
    baseUrl: "https://tenant.goskope.com"
    existingSecret: "npa-api-token"
    tokenKey: "api-token"
EOF

helm install kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  --namespace npa-publisher \
  -f my-api-config.yaml
```

> Developing on the chart? Clone the repo and swap `npa/kubernetes-netskope-publisher`
> for `.` in the install command to install from the local source instead of the
> published release.

Watch the pod and then follow the publisher container logs:

```bash
kubectl get pods -n npa-publisher -w

kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher \
  -n npa-publisher \
  -c publisher \
  -f
```

Successful startup includes these log lines:

```text
[npa-api-enrollment] API enrollment mode active
[npa-api-enrollment] Selected publisher_id=
[npa-api-enrollment] Enrollment complete; starting publisher
k8s-bootstrap: Preparing pod network namespace
k8s-bootstrap: Starting NPA Publisher
NPACONNECTED
```

The pod is ready when `kubectl get pods -n npa-publisher` shows `2/2 Running`. Connectivity is working when the logs show `NPACONNECTED` or `ConnectedResolvedByGSLB`. If the logs repeat `Connect to stitcher status: Resolving`, check cluster DNS resolution from the pod.

---

## Recommended k3s Setup

Use this when you do not already have a Kubernetes cluster or kubeconfig. A single Ubuntu 22.04 server or EC2 instance is enough for a first deployment. The steps install k3s locally and write a kubeconfig for the current user.

Install kubectl and Helm:

```bash
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Install k3s:

```bash
curl -sfL https://get.k3s.io | sh -

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config
chmod 600 ~/.kube/config
```

Verify the node is ready:

```bash
kubectl get nodes
kubectl get pods -A
```

Verify the host exposes `/dev/net/tun`, which pod network mode needs:

```bash
ls -l /dev/net/tun
```

If `/dev/net/tun` is missing:

```bash
sudo modprobe tun
ls -l /dev/net/tun
```

You can install directly from the published Helm repository — see the
[Quickstart](#quickstart) for the commands. If you'd rather develop on
the chart locally:

```bash
git clone https://github.com/johnneerdael/kubernetes-netskope-publisher
```

For horizontal-scaling tests on a single node, make sure the node has enough allocatable CPU and memory for every replica. Kubernetes schedules based on `resources.requests`, so extra replicas will stay `Pending` if the node cannot satisfy their requested CPU or memory.

---

## Platform Compatibility

The chart supports two network modes. Use `host` for the legacy highest-compatibility deployment, or `pod` to avoid host networking and full privileged mode.

| Mode | Value | Security profile | Best for |
|---|---|---|---|
| Host network | `networking.mode=host` | `hostNetwork: true`, `privileged: true`, `NET_ADMIN`, `NET_RAW` | Existing deployments and clusters that already allow privileged host-network pods |
| Pod network | `networking.mode=pod` | `hostNetwork: false`, `privileged: false`, `NET_ADMIN`, `NET_RAW`, `/dev/net/tun` mounted as a hostPath character device | Managed Kubernetes clusters where full privileged mode or host networking is blocked |

Pod network mode still needs a namespace or policy exception. Kubernetes Pod Security `restricted` policies, and many `baseline`-style policies, reject `NET_ADMIN` and hostPath device volumes. This exception is narrower than privileged host networking, but it is still required.

Enable pod network mode with:

```yaml
networking:
  mode: pod
  # Best-effort inside the pod network namespace. This prevents IPv6
  # link-local traffic on tun0 from reaching the IPv4-only Publisher path.
  disableIPv6: true
```

Pod network mode renders these required privileges:

```yaml
securityContext:
  privileged: false
  allowPrivilegeEscalation: false
  runAsUser: 0
  runAsNonRoot: false
  capabilities:
    add:
      - NET_ADMIN
      - NET_RAW

volumes:
  - name: dev-net-tun
    hostPath:
      path: /dev/net/tun
      type: CharDevice
```

In pod network mode the Kubernetes bootstrap avoids host-level preparation that is not writable in a pod sandbox. It prepares only the pod network namespace pieces the Publisher needs, skips host-level sysctl tuning, filters known non-fatal startup noise, and removes IPv6 link-local addresses from `tun0` when `networking.disableIPv6=true`.

Pod network mode also avoids the Publisher image's in-container BIND9 path. The chart starts a `local-dns` dnsmasq sidecar that listens only on `127.0.0.1:53`, reads the Kubernetes-provided upstream resolver from `/etc/resolv.conf`, and forwards to cluster DNS/CoreDNS. This preserves Kubernetes service discovery and any cluster-level forwarding or stub-domain rules. Do not set `bind.forwarders` in pod mode; configure CoreDNS forwarding instead when private domains need authoritative external DNS.

## Horizontal Scaling In Pod Mode

Pod network mode unlocks horizontal scaling on Kubernetes because each pod has its own network namespace. That means each Publisher pod can have its own `tun0`, routes, iptables rules, and pod-local dnsmasq listener even when multiple pods are scheduled on the same node.

Use StatefulSet mode for horizontal scaling. StatefulSet mode is API-only and requires pod networking:

```yaml
workload:
  type: statefulset
  replicas: 3

networking:
  mode: pod
  disableIPv6: true
```

Why StatefulSet instead of Deployment: each Publisher needs a stable identity in Netskope. StatefulSet pod names are stable, so the chart can safely append the pod name to `enrollment.commonName`. The chart sets `podManagementPolicy: Parallel` in StatefulSet mode, so replicas start independently instead of waiting for ordinal `0` to become ready first. For example, with:

```yaml
enrollment:
  mode: api
  commonName: "prod-k8s-publisher"
```

three replicas create or reuse Publisher identities like:

```text
prod-k8s-publisher-kubernetes-netskope-publisher-0
prod-k8s-publisher-kubernetes-netskope-publisher-1
prod-k8s-publisher-kubernetes-netskope-publisher-2
```

### Scaled API Values Example

```yaml
# my-api-statefulset-config.yaml

image:
  repository: "netskopeprivateaccess/publisher_u22"
  pullPolicy: IfNotPresent
  tag: "latest"

workload:
  type: statefulset
  replicas: 3

networking:
  mode: pod
  disableIPv6: true

tunDevice:
  enabled: true
  hostPath: /dev/net/tun
  mountPath: /dev/net/tun

persistence:
  enabled: false

enrollment:
  mode: api
  commonName: "prod-k8s-publisher"
  api:
    baseUrl: "https://tenant.goskope.com"
    existingSecret: "npa-api-token"
    tokenKey: "api-token"

bind:
  forwarders:
    - "8.8.8.8"      # Replace with internal DNS servers if needed
    - "8.8.4.4"
```

### AWS T3 Sizing Guidance

Use these profiles when running multiple Publisher pods on one AWS T3 node to increase aggregate throughput where upstream service limits cap bandwidth per Publisher pod. The guidance assumes a `t3.medium` node, pod network mode, and the observed Publisher behavior that one `npa_publisher` process saturates roughly one CPU core around 17,000 concurrent connections. T3 instances are burstable, so sustained traffic above the instance baseline consumes CPU credits or T3 Unlimited surplus.

| Goal | Replicas | Publisher resources | When to use |
|---|---:|---|---|
| Conservative scaling | 2 | `requests.cpu=500m`, `limits.cpu=1000m`, `requests.memory=384Mi`, `limits.memory=1Gi` | Use for lower connection counts, CPU-heavy traffic, or when preserving node headroom matters more than maximizing per-pod upstream capacity. |
| Balanced 10k target | 3 | `requests.cpu=300m`, `limits.cpu=750m`, `requests.memory=256Mi`, `limits.memory=768Mi` | Recommended starting point for about 10,000 total concurrent connections when per-pod upstream bandwidth is the limiting factor. |
| Bandwidth-oriented 10k-12k target | 4 | `requests.cpu=250m`, `limits.cpu=600m`, `requests.memory=256Mi`, `limits.memory=768Mi` | Use when testing shows the per-pod upstream bandwidth cap is still the bottleneck and node CPU remains below about 75-80% during steady traffic. |

Do not treat higher replica counts as free throughput. More pods improve aggregate bandwidth only when traffic is distributed across Publisher identities and the bottleneck is per-pod upstream capacity, not local CPU, TLS handshakes, reconnect churn, DNS, logging, or node networking. For sustained 15,000+ concurrent connections on one node, prefer a non-burstable instance or scale across more nodes instead of adding more pods to a `t3.medium`.

Example 3-pod `t3.medium` profile:

```yaml
workload:
  type: statefulset
  replicas: 3

networking:
  mode: pod
  disableIPv6: true

resources:
  requests:
    cpu: 300m
    memory: 256Mi
  limits:
    cpu: 750m
    memory: 768Mi
```

Example 4-pod bandwidth-oriented profile:

```yaml
workload:
  type: statefulset
  replicas: 4

networking:
  mode: pod
  disableIPv6: true

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 600m
    memory: 768Mi
```

Install or upgrade with the scaled values file:

```bash
helm upgrade --install kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  --namespace npa-publisher \
  --create-namespace \
  -f my-api-statefulset-config.yaml
```

Validate the StatefulSet and pods:

```bash
kubectl get statefulset kubernetes-netskope-publisher -n npa-publisher
kubectl get pods -n npa-publisher -l app.kubernetes.io/name=kubernetes-netskope-publisher -o wide
```

Validate that every replica enrolled and connected:

```bash
kubectl logs -n npa-publisher -l app.kubernetes.io/name=kubernetes-netskope-publisher -c publisher \
  | grep -E 'API enrollment mode active|NPACONNECTED|ConnectedResolvedByGSLB'
```

To scale after deployment, change `workload.replicas` and run `helm upgrade` again:

```yaml
workload:
  type: statefulset
  replicas: 5
```

Constraints:

- StatefulSet mode is supported only with `enrollment.mode=api`.
- StatefulSet mode requires `networking.mode=pod`.
- Each scaled Publisher consumes its own Netskope Publisher identity.
- Namespace policy must still allow `NET_ADMIN`, `NET_RAW`, and the `/dev/net/tun` hostPath character device.
- If the scheduler does not place multiple replicas on one node, check node resources, node selectors, taints, tolerations, affinity, and cluster scheduling policy.

### Provider Support

| Platform | Host mode | Pod mode | Notes |
|---|---:|---:|---|
| EKS managed/self-managed EC2 nodes | Supported | Supported | Pod mode is preferred when cluster policy allows `NET_ADMIN` and `/dev/net/tun`. |
| AKS Linux node pools | Supported | Supported | Azure Policy, Gatekeeper, or namespace Pod Security settings may need an exception. |
| GKE Standard | Supported | Supported | Autopilot restrictions do not apply to Standard clusters, but project/cluster policy can still block capabilities or hostPath. |
| IBM Cloud Kubernetes Service | Supported | Likely supported | Validate cluster policy allows `NET_ADMIN` and the `/dev/net/tun` hostPath device. |
| DigitalOcean Kubernetes | Supported | Likely supported | Validate admission policy and node access to `/dev/net/tun`. |
| OpenShift / ARO / ROSA | Possible | Possible | Requires an SCC that allows `NET_ADMIN` and `/dev/net/tun`; full privileged SCC may not be needed for pod mode. |

Unsupported or not recommended:

| Platform | Status | Reason |
|---|---|---|
| EKS Fargate | Unsupported | Does not support DaemonSets, host devices/hostPath, or the required Linux capability/device profile. |
| GKE Autopilot | Unsupported | Drops `CAP_NET_ADMIN` and only allows very limited hostPath use. |
| Azure Container Apps | Unsupported | Does not expose the required TUN device and Linux capabilities. |
| Azure Container Instances / AKS Virtual Nodes | Unsupported | Container sandbox does not provide the required `/dev/net/tun` plus `NET_ADMIN` model. |
| Clusters enforcing restricted Pod Security without exceptions | Unsupported | `NET_ADMIN` and hostPath device mounts are rejected. |

---

## What You Are Deploying

The NPA Publisher is a container that connects your private network to the Netskope cloud. Once running, it acts as an outbound-only secure tunnel — your users reach internal apps through Netskope without any inbound firewall rules needed.

By default, the Helm chart deploys a DaemonSet with one Publisher pod per matching node. API mode can also run as a StatefulSet when you need multiple Publisher pods that may land on the same node. The pod always includes the **main container** (`publisher`) that runs the tunnel process after enrollment completes. Enrollment can run in either of two modes:

- **API mode**: the Kubernetes-native default. The main container starts a chart-mounted wrapper script, looks up or creates the Publisher object through the Netskope API, generates a registration token, enrolls, and then starts the tunnel process.
- **Token mode**: an `enroll` init container consumes a one-time registration token and writes enrollment artifacts before the main container starts.

For storage, API mode defaults to pod-local `emptyDir` storage and re-enrolls when the pod is recreated. That makes the deployment easier to move between nodes or clusters because the pod depends on declarative Helm values plus a Kubernetes Secret, not attached registration state. Token mode usually uses a **PersistentVolumeClaim** so certificates and config survive pod recreation.

### Workload Types

| Type | Value | Enrollment modes | Best for |
|---|---|---|---|
| DaemonSet | `workload.type=daemonset` | `api` or `token` | One Publisher pod per matching node |
| StatefulSet | `workload.type=statefulset` | `api` only | Multiple Publisher pods with stable identities, including multiple pods on one node |

StatefulSet mode requires `networking.mode=pod`. Each replica gets a stable pod name and appends it to `enrollment.commonName`; for example, `prod-k8s-publisher-kubernetes-netskope-publisher-0`. This gives every Publisher instance a unique API-created identity while allowing Kubernetes to restart the same replica with the same name.

---

## Choose an Enrollment Mode

The chart supports two enrollment modes. Pick one before creating your configuration file.

| Mode | Best for | How enrollment works | Storage model |
|---|---|---|---|
| `api` | Kubernetes-style deployments where pods should be disposable and movable without attached registration state | The main container starts a chart-mounted wrapper script, looks up a Publisher by common name or publisher name, creates it if missing, generates a registration token through the Netskope API, enrolls, then starts the Publisher | Default: `persistence.enabled=false`, backed by pod-local `emptyDir` |
| `token` | Environments that cannot grant the pod a Netskope API token or intentionally want persisted registration artifacts | An `enroll` init container consumes a one-time registration token and writes Publisher certificates/config before the main container starts | Usually `persistence.enabled=true`, backed by a PVC |

Use **API mode** unless you have a specific reason to avoid API-driven startup enrollment. If a Publisher with the configured common name or publisher name already exists, the chart reuses it. If it does not exist, the chart creates it with `enrollment.commonName` as the Publisher `name`. Multiple matches still fail because the lookup is ambiguous.

Use **token mode** when your deployment must avoid storing a Netskope API credential in Kubernetes or when you explicitly want certificate/config artifacts persisted on a PVC.

---

## Part 1 — Requirements

### Recommended First Deployment: k3s

For the lowest entry barrier, deploy to a single-node k3s cluster on a Linux host. k3s provides Kubernetes, containerd, kubeconfig, and basic cluster services without asking the user to design a full production cluster first.

| Requirement | Detail |
|---|---|
| Host OS | Ubuntu 22.04 LTS recommended |
| Host CPU | 1 vCPU available for the Publisher; add capacity for k3s, DNS, logging, and any extra replicas |
| Host RAM | 2 GB available for a small lab; 4 GB or more recommended for production-like testing |
| Outbound internet | Port 443 TCP open to Netskope cloud from the host |
| Linux TUN device | `/dev/net/tun` present; load it with `sudo modprobe tun` if missing |
| Kubernetes distribution | k3s installed with the commands in the Recommended k3s Setup section |
| Deployment tools | Helm 3 and `kubectl` available on the k3s host or an admin workstation |

The chart default Publisher resources request `500m` CPU and `384Mi` memory, cap CPU at `1000m` because `npa_publisher` does not use more than one core, and cap memory at `1Gi`.

### Kubernetes Requirements

| Requirement | Detail |
|---|---|
| Kubernetes version | 1.21 or later |
| Node OS | Linux (Ubuntu 22.04 or CentOS/RHEL 8+ recommended) |
| Node CPU | At least 1 vCPU available per Publisher pod, plus node and system overhead |
| Node RAM | At least 2 GB available for a small deployment; 4 GB or more recommended for production-like testing |
| Outbound internet | Port 443 TCP open to Netskope cloud from the node |
| Host mode policy | Must permit privileged containers and host networking when `networking.mode=host` |
| Pod mode policy | Must permit `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun` hostPath device mount when `networking.mode=pod` |
| Storage | A working StorageClass that can provision PersistentVolumeClaims for token/PVC deployments. API enrollment can run with `persistence.enabled=false`. |

> **Note:** Host mode requires `hostNetwork: true` and privileged mode. Pod mode avoids both, but still requires `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun` so the Publisher can create its container-local tunnel interface and manage routes/iptables inside the pod network namespace.

### Other Deployment Architectures

Use k3s for the first deployment unless an existing platform is already ready. Larger or managed architectures use the same Helm chart, but add cluster-specific tooling and policy work.

| Architecture | Typical tools involved | When to use it |
|---|---|---|
| Single-node k3s | k3s, Helm, kubectl | First deployment, lab validation, small self-managed edge host |
| Multi-node k3s | k3s server/agent nodes, Helm, kubectl, external datastore or backup plan | Small production or edge deployment that needs node redundancy without a managed service |
| Amazon EKS | AWS CLI, `eksctl` or Terraform, Helm, kubectl, IAM, VPC CNI | AWS-managed control plane and EC2 worker nodes |
| Azure AKS | Azure CLI or Terraform, Helm, kubectl, Azure Policy/Gatekeeper review | Azure-managed Kubernetes with Linux node pools |
| Google GKE Standard | Google Cloud CLI or Terraform, Helm, kubectl, project/cluster policy review | Google-managed Kubernetes where Standard mode can allow the required capabilities |
| OpenShift / ROSA / ARO | OpenShift CLI, Helm, SCC configuration | Red Hat environments that need SecurityContextConstraint approval |

Avoid serverless container targets such as EKS Fargate, GKE Autopilot, Azure Container Apps, Azure Container Instances, and AKS Virtual Nodes for this Publisher. They do not expose the required Linux TUN device and capability model.

### Workstation Requirements

You need two tools on the machine where you run deployment commands: **kubectl** configured for the k3s or Kubernetes cluster, and **Helm 3**.

**macOS:**
```bash
brew install kubectl helm
```

**Windows (PowerShell as Administrator):**
```powershell
winget install Kubernetes.kubectl
winget install Helm.Helm
```

**Linux (Ubuntu/Debian):**
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify your cluster connection before proceeding:
```bash
kubectl get nodes
```

You should see your cluster nodes listed with `Ready` status. If this fails, resolve your kubeconfig access before continuing — the rest of this guide assumes `kubectl` is working.

---

## Part 2 — Prepare Enrollment Credentials

### API Mode: Create API Credentials

API mode needs Netskope API credentials instead of a static one-time registration token. The credential must be allowed to list NPA Publishers, create NPA Publishers, and generate Publisher registration tokens.

Before deploying, choose the Publisher name to use. If no Publisher with that `common_name` or `publisher_name` exists, API mode creates one automatically using the same value as the Publisher `name`. Netskope may generate a separate `common_name` value during creation.

By default, API mode uses a Kubernetes Secret containing a static Netskope API token:

```bash
kubectl create namespace npa-publisher
kubectl create secret generic npa-api-token \
  --namespace npa-publisher \
  --from-literal=api-token='PASTE_NETSKOPE_API_TOKEN_HERE'
```

Alternatively, set `enrollment.api.authMode: oauth2` and create a Secret containing OAuth2 client credentials:

```bash
kubectl create secret generic npa-api-oauth \
  --namespace npa-publisher \
  --from-literal=client-id='PASTE_CLIENT_ID_HERE' \
  --from-literal=client-secret='PASTE_CLIENT_SECRET_HERE'
```

OAuth2 mode also requires `enrollment.api.oauth2.tokenUrl`, the full token endpoint URL used for the client credentials flow.

### Token Mode: Get Your Registration Token

Token mode needs a one-time registration token from your Netskope tenant. This token is how the Publisher authenticates and receives its certificates.

1. Log in to your **Netskope Admin Console**
2. Go to **Settings → Security Cloud Platform → Private Access → Publishers**
3. Click **New Publisher** or **NPA Publisher Wizard**
4. Give the Publisher a name (e.g. `prod-k8s-publisher`)
5. Copy the **Registration Token** — it is a long string, keep it secure

> **Important:** The token is single-use. Once the Publisher registers successfully, the token is consumed. If you need to re-register (e.g. after deleting and recreating the deployment), generate a new token from the console.

---

## Part 3 — Obtain the Helm Chart

The chart is distributed as a folder containing `Chart.yaml`, `values.yaml`, and a `templates/` directory. Obtain it from your internal artifact repository, package registry, or the distribution archive provided by your team.

Once you have the chart folder, confirm its contents:
```bash
ls ./kubernetes/
# Expected: Chart.yaml  values.yaml  templates/  guide.md  ...
```

All `helm` commands in this guide assume you are running them from the directory **containing** the chart folder — i.e. the chart folder itself is `./kubernetes/`.

---

## Part 4 — Create Your Configuration File

Create a values file in your working directory. This file overrides the chart defaults with your specific settings. Keeping it separate from the chart means your tokens and environment-specific values are never accidentally committed alongside the chart.

### API Mode Configuration

Use this configuration for API enrollment in legacy host network mode. Host mode uses privileged host networking and keeps the in-container BIND9 forwarder path.

```yaml
# my-api-host-config.yaml

image:
  repository: "netskopeprivateaccess/publisher_u22"
  pullPolicy: IfNotPresent
  tag: "latest"

networking:
  mode: host

persistence:
  enabled: false

enrollment:
  mode: api
  commonName: "prod-k8s-publisher"
  api:
    baseUrl: "https://tenant.goskope.com"
    existingSecret: "npa-api-token"
    tokenKey: "api-token"
```

Use this configuration for API enrollment with pod network mode. This avoids `hostNetwork` and full privileged mode, but the namespace policy must allow `NET_ADMIN`, `NET_RAW`, and the `/dev/net/tun` hostPath character device.

```yaml
# my-api-pod-network-config.yaml

image:
  repository: "netskopeprivateaccess/publisher_u22"
  pullPolicy: IfNotPresent
  tag: "latest"

networking:
  mode: pod
  disableIPv6: true

tunDevice:
  enabled: true
  hostPath: /dev/net/tun
  mountPath: /dev/net/tun

persistence:
  enabled: false

enrollment:
  mode: api
  commonName: "prod-k8s-publisher"
  api:
    baseUrl: "https://tenant.goskope.com"
    existingSecret: "npa-api-token"
    tokenKey: "api-token"
```

In API mode, the pod looks up the Publisher by `commonName` against the API response fields `common_name` and `publisher_name`. When one matching Publisher exists, it reuses that Publisher ID. When none exists, it creates a Publisher with `{"name":"<commonName>"}` and uses the returned ID. If multiple Publishers match, startup fails because the configured name is ambiguous. If the matched Publisher is already connected, startup fails until the existing connection is cleared.

For multiple API-enrolled Publisher pods, use StatefulSet mode from the Horizontal Scaling section above.

### Token Mode Configuration

Use this host network configuration when `enrollment.mode` is `token`:

```yaml
# my-token-host-config.yaml

image:
  repository: "netskopeprivateaccess/publisher_u22"
  pullPolicy: IfNotPresent
  tag: "latest"

networking:
  mode: host

persistence:
  enabled: true

enrollment:
  mode: token

registrationToken:
  value: "PASTE_YOUR_TOKEN_HERE"

# DNS Forwarders — the Publisher runs its own BIND9 DNS forwarder inside the container.
# These are the upstream DNS servers it will forward queries to.
# This MUST be set correctly or the Publisher cannot resolve the Netskope stitcher hostname
# and will fail to connect (you will see "Resolving" loop indefinitely in the logs).
bind:
  forwarders:
    - "8.8.8.8"      # Replace with your internal DNS server IPs if resolving private hostnames
    - "8.8.4.4"

# Proxy settings — only required if your nodes need a proxy to reach the internet
# proxy:
#   enabled: true
#   httpProxy: "http://proxy.yourcompany.com:8080"
#   httpsProxy: "http://proxy.yourcompany.com:8080"
#   noProxy: "localhost,127.0.0.1,.cluster.local,10.0.0.0/8"
```

Use this pod network configuration when `enrollment.mode` is `token`:

```yaml
# my-token-pod-network-config.yaml

image:
  repository: "netskopeprivateaccess/publisher_u22"
  pullPolicy: IfNotPresent
  tag: "latest"

networking:
  mode: pod
  disableIPv6: true

tunDevice:
  enabled: true
  hostPath: /dev/net/tun
  mountPath: /dev/net/tun

persistence:
  enabled: true

enrollment:
  mode: token

registrationToken:
  value: "PASTE_YOUR_TOKEN_HERE"
```

### Choosing DNS Forwarders

In host network mode, `bind.forwarders` determines what DNS the Publisher's in-container BIND9 uses internally. Set it based on your environment:

| Environment | Recommended forwarders |
|---|---|
| Internet-connected / lab | `8.8.8.8`, `8.8.4.4` |
| Corporate on-premises | Your internal DNS server IPs (e.g. `10.0.0.5`) |
| AWS VPC | VPC resolver: your VPC CIDR base + 2 (e.g. `172.31.0.2`) |
| Azure VNet | `168.63.129.16` |
| GCP VPC | `169.254.169.254` or your VPC DNS IP |

If the Publisher needs to reach both internal private apps **and** the Netskope cloud, use your internal DNS servers — they should already forward public queries upstream.

In pod network mode, leave `bind.forwarders` unset. The chart runs a `local-dns` dnsmasq sidecar that forwards to Kubernetes cluster DNS/CoreDNS. If the Publisher must resolve private domains that CoreDNS does not already know, add domain-specific forwarding in CoreDNS so Kubernetes service discovery and private authoritative DNS both work.

For the default CoreDNS `kube-system/coredns` ConfigMap:

```bash
kubectl -n kube-system get configmap coredns -o yaml > coredns-backup.yaml
kubectl -n kube-system edit configmap coredns
```

In `data.Corefile`, add a domain block for your private zone at the same
level as the existing `.:53` block. Replace `private.example.com` with
your private DNS suffix and `10.0.0.10 10.0.0.11` with your internal DNS
server IPs:

```text
private.example.com:53 {
    errors
    cache 30
    forward . 10.0.0.10 10.0.0.11
}
```

Then roll CoreDNS and test both cluster DNS and the private zone:

```bash
kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns

kubectl run dns-test --rm -it --restart=Never \
  --image=busybox:1.36 \
  -- nslookup kubernetes.default.svc.cluster.local

kubectl run dns-test-private --rm -it --restart=Never \
  --image=busybox:1.36 \
  -- nslookup app1.private.example.com
```

See the GitHub Pages
[Connectivity requirements](https://johnneerdael.github.io/kubernetes-netskope-publisher/admin/concepts/connectivity/#forward-private-domains-with-coredns)
page for the detailed walkthrough.

---

## Part 5 — Deploy

From the directory containing both the chart folder (`./kubernetes/`) and your config file (`./my-api-config.yaml`), run:

```bash
helm install kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  --namespace npa-publisher \
  --create-namespace \
  -f my-api-config.yaml
```

What each part does:
- `kubernetes-netskope-publisher` — the name of this Helm release (used in all future `helm upgrade`/`uninstall` commands)
- `./kubernetes` — path to the chart folder
- `--namespace npa-publisher --create-namespace` — deploys into an isolated namespace, creating it if it doesn't exist
- `-f my-api-config.yaml` — applies your tenant URL, API token Secret name, Publisher name, and DNS settings on top of the chart defaults. The default image is `netskopeprivateaccess/publisher_u22:latest`.

Expected output:
```
NAME: kubernetes-netskope-publisher
LAST DEPLOYED: ...
NAMESPACE: npa-publisher
STATUS: deployed
NOTES: ...
```

If you see `Error: INSTALLATION FAILED`, check the error message — the most common causes are covered in the Troubleshooting section at the end of this guide.

For token mode:

```bash
helm install kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  --namespace npa-publisher \
  --create-namespace \
  -f my-token-config.yaml
```

---

## Part 6 — Verify the Deployment

### Step 1: Watch the Pod Come Up

```bash
kubectl get pods -n npa-publisher -w
```

The pod goes through these stages in order:

| Status | Meaning |
|---|---|
| `Init:0/1` | Token mode only: the `enroll` init container is registering with Netskope |
| `0/2 Running` with restarts | In API mode, main-container enrollment is failing before publisher startup; check main container logs |
| `PodInitializing` | Enrollment complete, main container starting |
| `1/2 Running` | Publisher process is running, waiting for readiness (connecting to stitcher) |
| `2/2 Running` | **Fully ready** — Publisher and local DNS sidecar are ready |

Press `Ctrl+C` to stop watching once you see `2/2 Running`. The transition from `1/2` to `2/2` typically takes 30–90 seconds after enrollment.

### Step 2: Verify Enrollment Succeeded

In API mode, enrollment logs are in the main container because there is no `enroll` init container:

```bash
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher \
  -n npa-publisher \
  -c publisher
```

In token mode, the init container handles registration. Check its logs:

```bash
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher -c enroll
```

Look for:

```text
[npa-api-enrollment] API enrollment mode active
[npa-api-enrollment] Selected publisher_id=
[npa-api-enrollment] Enrollment complete; starting publisher
```

A successful enrollment looks like:
```
Registering with your Netskope address: ns-XXXXX.npa.goskope.com
Publisher certificate CN: <fingerprint>
Attempt 1 to register publisher via ns-XXXXX.npa.goskope.com.
Publisher registered successfully.
Verifying connectivity to the Netskope Dataplane...
Connectivity to the Netskope Dataplane was successfully verified.
```

Verify that the registration files were written:
```bash
kubectl exec -n npa-publisher \
  $(kubectl get pod -n npa-publisher -o name) \
  -c publisher -- ls /home/resources/
```

You should see: `publisherid`, `sslcert/`, `settings.json`, `nsconfig.json`, `tenant`, `orgkey`. If the directory is empty or missing these files, enrollment did not complete — see Troubleshooting.

### Step 3: Check the Publisher Logs

```bash
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher -c publisher -f
```

A healthy publisher shows periodic NsConfig pulls:
```
NsConfig Pull & Save successfully completed
conntrack v1.x.x: 0 flow entries have been shown.
```

If you see `Connect to stitcher status: Resolving` repeating for more than 2 minutes without progressing, this is a DNS issue — see Troubleshooting.

### Step 4: Confirm in the Netskope Console

Go to **Settings → Security Cloud Platform → Private Access → Publishers**.

The Publisher you created in Part 2 should now show status **Connected**. This is the definitive confirmation that the deployment is working end-to-end.

---

## Part 7 — Updating the Deployment

### Change Configuration (DNS, Proxy, Log Level, etc.)

Edit your values file, then run `helm upgrade` with the same file you used for install.

For API mode:
```bash
helm upgrade kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  --namespace npa-publisher \
  -f my-api-config.yaml
```

For token mode:
```bash
helm upgrade kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  --namespace npa-publisher \
  -f my-token-config.yaml
```

If pods do not restart automatically after the upgrade:
```bash
kubectl rollout restart daemonset/kubernetes-netskope-publisher -n npa-publisher
```

For StatefulSet mode:
```bash
kubectl rollout restart statefulset/kubernetes-netskope-publisher -n npa-publisher
```

### Pin or Change the Publisher Image

The chart defaults to the standard published image:

```yaml
image:
  repository: "netskopeprivateaccess/publisher_u22"
  pullPolicy: IfNotPresent
  tag: "latest"
```

To pin a specific published build or release, change `image.tag` in your values file, then run the same `helm upgrade` command above. The DaemonSet or StatefulSet will perform a rolling restart automatically.

### Re-enroll in Token Mode

If you need to re-register (e.g. the existing registration is broken or you are moving tenants):

1. Delete the existing PVC to clear the old certificates:
```bash
kubectl delete pvc -n npa-publisher --all
```
2. Update `registrationToken.value` in `my-token-config.yaml` with a new token from the console
3. Run `helm upgrade` — the pod will restart, enrollment will run again with the new token

### Re-enroll in API Mode

API mode generates a fresh registration token during pod startup. If you need to re-register:

1. Confirm the Publisher is not currently connected in Netskope.
2. Delete the pod-local state by restarting or recreating the pod:
```bash
kubectl rollout restart daemonset/kubernetes-netskope-publisher -n npa-publisher
```
3. The main container will look up `enrollment.commonName`, request a new registration token, enroll, and then start the Publisher.

---

## Part 8 — Uninstalling

```bash
# Remove the Helm release and all Kubernetes resources
helm uninstall kubernetes-netskope-publisher -n npa-publisher

# Delete the namespace (also removes the PVC and stored certificates)
kubectl delete namespace npa-publisher
```

> **Warning:** In token mode with persistent storage, deleting the namespace removes the PersistentVolumeClaim, which contains the registration certificates. After this, the Publisher entry in your Netskope console will show as disconnected. You will need to re-enroll with a new token if you reinstall.

---

## Troubleshooting

### Pod stuck in `Init:0/1` with no log output

The init container may have exited immediately without output. Check its exit status:
```bash
kubectl describe pod -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher | grep -A 20 "Init Containers"
```

If `Exit Code` is `0` but completed in under 2 seconds, the registration token was likely empty. Verify:
```bash
kubectl get secret npa-publisher-token -n npa-publisher \
  -o jsonpath='{.data.token}' | base64 -d | head -c 20
```
If this returns nothing, the token was not set in `my-token-config.yaml`. Correct it and run `helm upgrade`.

### Publisher logs show `Connect to stitcher status: Resolving` indefinitely

The Publisher cannot resolve the Netskope stitcher hostname. This is a DNS configuration issue.

In pod network mode, fix Kubernetes cluster DNS/CoreDNS. The default chart runs dnsmasq as a thin pod-local proxy to the cluster resolver; overriding per-pod forwarders is intentionally blocked so Kubernetes service discovery keeps working.

In host network mode, fix `bind.forwarders` in your values file with DNS servers that work in your network, then:
```bash
helm upgrade kubernetes-netskope-publisher npa/kubernetes-netskope-publisher -n npa-publisher -f my-api-config.yaml
kubectl rollout restart daemonset/kubernetes-netskope-publisher -n npa-publisher
```

To test DNS resolution from inside the pod before restarting:
```bash
kubectl exec -n npa-publisher \
  $(kubectl get pod -n npa-publisher -o name) \
  -c publisher -- nslookup gateway.gslb.goskope.com
```

### Pod status is `CrashLoopBackOff`

Retrieve logs from the previous (crashed) container instance:
```bash
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher -c publisher --previous
```

Common causes:
- **Registration incomplete** — `publisherid` or `sslcert/` missing from `/home/resources/`; in API mode, restart the pod after fixing API errors; in token mode, delete the PVC and re-enroll with a fresh token
- **Proxy required** — enable and configure `proxy:` in your values file
- **Port 443 blocked** — verify outbound TCP 443 from the node to `*.goskope.com` and `*.npa.goskope.com`

### API enrollment fails before Publisher startup

Check the previous main container logs:

```bash
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher \
  -n npa-publisher \
  -c publisher \
  --previous
```

Common causes:
- **Publisher creation failed** - verify the API token can create NPA Publishers and `enrollment.commonName` is an accepted Publisher name.
- **Multiple publishers matched** - common names must be unique for this deployment.
- **Publisher already connected** - registration token generation is blocked while the Publisher is connected.
- **API request failed** - verify `enrollment.api.baseUrl`, the API token Secret, and the API token permissions.
- **Token response missing** - verify the API credential can call `POST /api/v2/infrastructure/publishers/{publisher_id}/registration_token`.

### Pod stuck in `Pending`

```bash
kubectl describe pod -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher
```

Check the **Events** section at the bottom. Common causes:
- **Insufficient resources** — the pod requests 500m CPU and 384Mi RAM; verify the node has enough headroom with `kubectl describe node`
- **No matching node** — if you have `nodeSelector` or `tolerations` configured, ensure nodes match
- **PVC cannot be provisioned** — token mode only: check your cluster's default StorageClass with `kubectl get storageclass`; if none is marked `(default)`, specify one via `persistence.storageClass` in your token-mode values file

### `helm install` fails with `cluster unreachable`

Your kubeconfig is not accessible. Common fixes:
```bash
# Fix ownership if copied with sudo
sudo chown $USER:$USER ~/.kube/config

# Verify the correct context is active
kubectl config current-context
kubectl config get-contexts
```

### Pod rejected by cluster policy

If the pod fails with an admission error mentioning `privileged`, `hostNetwork`, `NET_ADMIN`, or `hostPath`, your cluster has Pod Security Admission, OPA Gatekeeper, Kyverno, Azure Policy, or another admission policy blocking the required security profile.

For pod network mode, the exception should allow `NET_ADMIN`, `NET_RAW`, and the `/dev/net/tun` hostPath character device. Full privileged mode and host networking are not required in pod network mode.

Work with your cluster administrator to create an exception for the `npa-publisher` namespace. If you are using Kubernetes Pod Security Admission and need the broad built-in label, apply:
```bash
kubectl label namespace npa-publisher \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

Use a narrower policy exception when your policy engine supports one.

---

## Quick Reference

```bash
# Check pod status
kubectl get pods -n npa-publisher

# Watch pod events and status in real time
kubectl describe pod -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher

# Enrollment logs in token mode (init container)
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher -c enroll

# Enrollment logs in API mode (main container)
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher -c publisher

# Publisher logs (main container, follow mode)
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher -n npa-publisher -c publisher -f

# Check registration files on the volume
kubectl exec -n npa-publisher $(kubectl get pod -n npa-publisher -o name) \
  -c publisher -- ls /home/resources/

# Upgrade after API mode config change
helm upgrade kubernetes-netskope-publisher npa/kubernetes-netskope-publisher -n npa-publisher -f my-api-config.yaml

# Upgrade after token mode config change
helm upgrade kubernetes-netskope-publisher npa/kubernetes-netskope-publisher -n npa-publisher -f my-token-config.yaml

# Force pod restart without config change
kubectl rollout restart daemonset/kubernetes-netskope-publisher -n npa-publisher

# Remove everything including PVC
helm uninstall kubernetes-netskope-publisher -n npa-publisher && kubectl delete namespace npa-publisher
```
