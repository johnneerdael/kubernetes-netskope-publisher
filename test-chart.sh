#!/bin/bash
# Helm chart validation and testing script for npa-publisher

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

helm() {
    if [ "${1:-}" = "template" ]; then
        shift
        command helm template --kube-version 1.29.0 "$@"
        return
    fi

    command helm "$@"
}

echo "========================================="
echo "NPA Publisher Helm Chart Testing"
echo "========================================="

# Test 1: Helm lint
echo -e "\n${YELLOW}[TEST 1]${NC} Running helm lint..."
if helm lint "${CHART_DIR}"; then
    echo -e "${GREEN}✓ Helm lint passed${NC}"
else
    echo -e "${RED}✗ Helm lint failed${NC}"
    exit 1
fi

# Test 2: Template rendering with default values
echo -e "\n${YELLOW}[TEST 2]${NC} Testing template rendering with default values..."
if helm template test-release "${CHART_DIR}" > /dev/null; then
    echo -e "${GREEN}✓ Template rendering with defaults passed${NC}"
else
    echo -e "${RED}✗ Template rendering with defaults failed${NC}"
    exit 1
fi

# Test 3: Template rendering with token enrollment values
echo -e "\n${YELLOW}[TEST 3]${NC} Testing token enrollment rendering..."
if helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=token \
    --set persistence.enabled=true \
    --set registrationToken.value="test-token-12345" > /dev/null; then
    echo -e "${GREEN}✓ Template rendering with token enrollment passed${NC}"
else
    echo -e "${RED}✗ Template rendering with token enrollment failed${NC}"
    exit 1
fi

# Test 4: Template rendering with proxy values
echo -e "\n${YELLOW}[TEST 4]${NC} Testing proxy rendering..."
if helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=token \
    --set persistence.enabled=true \
    --set registrationToken.value="test-token-12345" \
    --set proxy.enabled=true \
    --set proxy.httpProxy="http://proxy.example.com:8080" \
    --set proxy.httpsProxy="http://proxy.example.com:8080" \
    --set proxy.noProxy="localhost\,127.0.0.1" > /dev/null; then
    echo -e "${GREEN}✓ Template rendering with proxy values passed${NC}"
else
    echo -e "${RED}✗ Template rendering with proxy values failed${NC}"
    exit 1
fi

# Test 5: Template rendering with API enrollment values
echo -e "\n${YELLOW}[TEST 5]${NC} Testing API enrollment rendering..."
if helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=api \
    --set enrollment.commonName="e2eabac9e9f715ff" \
    --set enrollment.api.baseUrl="https://tenant.goskope.com" \
    --set enrollment.api.existingSecret="npa-api-token" \
    --set persistence.enabled=false > /dev/null; then
    echo -e "${GREEN}✓ Template rendering with API enrollment passed${NC}"
else
    echo -e "${RED}✗ Template rendering with API enrollment failed${NC}"
    exit 1
fi

echo -e "\n${YELLOW}[TEST 5b]${NC} Testing API enrollment with OAuth2 credentials..."
OAUTH_RENDERED=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=api \
    --set enrollment.commonName="oauth-publisher" \
    --set enrollment.api.baseUrl="https://tenant.goskope.com" \
    --set enrollment.api.authMode="oauth2" \
    --set enrollment.api.oauth2.tokenUrl="https://tenant.goskope.com/oauth2/token" \
    --set enrollment.api.oauth2.existingSecret="npa-api-oauth" \
    --set enrollment.api.oauth2.clientIdKey="client-id" \
    --set enrollment.api.oauth2.clientSecretKey="client-secret" \
    --set persistence.enabled=false)

if echo "$OAUTH_RENDERED" | grep -q "name: NPA_API_OAUTH_CLIENT_ID" \
    && echo "$OAUTH_RENDERED" | grep -q "name: NPA_API_OAUTH_CLIENT_SECRET" \
    && echo "$OAUTH_RENDERED" | grep -q "NPA_API_AUTH_MODE: \"oauth2\"" \
    && echo "$OAUTH_RENDERED" | grep -q "NPA_API_OAUTH_TOKEN_URL: \"https://tenant.goskope.com/oauth2/token\""; then
    echo -e "${GREEN}✓ Template rendering with OAuth2 API enrollment passed${NC}"
else
    echo -e "${RED}✗ OAuth2 API enrollment rendering missing expected configuration${NC}"
    exit 1
fi

# Test 6: Validate API enrollment required values are enforced
echo -e "\n${YELLOW}[TEST 6]${NC} Testing API enrollment required values..."
OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=api \
    --set-string enrollment.commonName="" 2>&1 || true)
if echo "$OUTPUT" | grep -q "enrollment.commonName is required when enrollment.mode=api"; then
    echo -e "${GREEN}✓ API commonName validation working${NC}"
elif echo "$OUTPUT" | grep -q "at '/enrollment/commonName': minLength"; then
    echo -e "${GREEN}✓ API commonName schema validation working${NC}"
else
    echo -e "${RED}✗ API commonName validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=invalid \
    --set registrationToken.value="test-token" 2>&1 || true)
if echo "$OUTPUT" | grep -q "enrollment.mode must be either 'token' or 'api'"; then
    echo -e "${GREEN}✓ Enrollment mode validation working${NC}"
elif echo "$OUTPUT" | grep -q "at '/enrollment/mode': value must be one of 'api', 'token'"; then
    echo -e "${GREEN}✓ Enrollment mode schema validation working${NC}"
else
    echo -e "${RED}✗ Enrollment mode validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set networking.mode=invalid 2>&1 || true)
if echo "$OUTPUT" | grep -q "networking.mode must be one of 'host', 'pod', or 'lwip'"; then
    echo -e "${GREEN}✓ Networking mode validation working${NC}"
elif echo "$OUTPUT" | grep -q "at '/networking/mode': value must be one of 'pod', 'host', 'lwip'"; then
    echo -e "${GREEN}✓ Networking mode schema validation working${NC}"
else
    echo -e "${RED}✗ Networking mode validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set networking.mode=pod \
    --set bind.forwarders="{8.8.8.8}" 2>&1 || true)
if echo "$OUTPUT" | grep -q "bind.forwarders is only supported when networking.mode=host"; then
    echo -e "${GREEN}✓ Pod-mode BIND forwarder validation working${NC}"
else
    echo -e "${RED}✗ Pod-mode BIND forwarder validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set workload.type=invalid 2>&1 || true)
if echo "$OUTPUT" | grep -q "workload.type must be either 'daemonset' or 'statefulset'"; then
    echo -e "${GREEN}✓ Workload type validation working${NC}"
elif echo "$OUTPUT" | grep -q "at '/workload/type': value must be one of 'daemonset', 'statefulset'"; then
    echo -e "${GREEN}✓ Workload type schema validation working${NC}"
else
    echo -e "${RED}✗ Workload type validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set workload.type=statefulset \
    --set enrollment.mode=token \
    --set networking.mode=pod \
    --set registrationToken.value="test-token" 2>&1 || true)
if echo "$OUTPUT" | grep -q "workload.type=statefulset is only supported when enrollment.mode=api"; then
    echo -e "${GREEN}✓ StatefulSet API-only validation working${NC}"
else
    echo -e "${RED}✗ StatefulSet API-only validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set workload.type=statefulset \
    --set enrollment.mode=api \
    --set networking.mode=host 2>&1 || true)
if echo "$OUTPUT" | grep -q "workload.type=statefulset requires networking.mode=pod or networking.mode=lwip"; then
    echo -e "${GREEN}✓ StatefulSet pod-network validation working${NC}"
else
    echo -e "${RED}✗ StatefulSet pod-network validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=api \
    --set enrollment.api.authMode=invalid 2>&1 || true)
if echo "$OUTPUT" | grep -q "enrollment.api.authMode must be either 'token' or 'oauth2'"; then
    echo -e "${GREEN}✓ API auth mode validation working${NC}"
elif echo "$OUTPUT" | grep -q "at '/enrollment/api/authMode': value must be one of 'token', 'oauth2'"; then
    echo -e "${GREEN}✓ API auth mode schema validation working${NC}"
else
    echo -e "${RED}✗ API auth mode validation missing${NC}"
    exit 1
fi

OUTPUT=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=api \
    --set enrollment.api.authMode=oauth2 \
    --set-string enrollment.api.oauth2.tokenUrl="" 2>&1 || true)
if echo "$OUTPUT" | grep -q "enrollment.api.oauth2.tokenUrl is required when enrollment.api.authMode=oauth2"; then
    echo -e "${GREEN}✓ OAuth2 tokenUrl validation working${NC}"
elif echo "$OUTPUT" | grep -q "at '/enrollment/api/oauth2/tokenUrl': does not match pattern"; then
    echo -e "${GREEN}✓ OAuth2 tokenUrl schema validation working${NC}"
else
    echo -e "${RED}✗ OAuth2 tokenUrl validation missing${NC}"
    exit 1
fi

# Test 7: Check all expected resources are generated
echo -e "\n${YELLOW}[TEST 7]${NC} Validating expected Kubernetes resources..."
RENDERED=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=token \
    --set persistence.enabled=true \
    --set serviceAccount.create=true \
    --set registrationToken.value="test-token")

EXPECTED_RESOURCES=(
    "kind: DaemonSet"
    "kind: ServiceAccount"
    "kind: ConfigMap"
    "kind: Secret"
    "kind: PersistentVolumeClaim"
)

ALL_FOUND=true
for resource in "${EXPECTED_RESOURCES[@]}"; do
    if echo "$RENDERED" | grep -q "$resource"; then
        echo -e "  ${GREEN}✓${NC} Found: $resource"
    else
        echo -e "  ${RED}✗${NC} Missing: $resource"
        ALL_FOUND=false
    fi
done

if [ "$ALL_FOUND" = true ]; then
    echo -e "${GREEN}✓ All expected resources found${NC}"
else
    echo -e "${RED}✗ Some resources missing${NC}"
    exit 1
fi

# Test 8: Validate YAML syntax
echo -e "\n${YELLOW}[TEST 8]${NC} Validating YAML syntax..."
if command -v yamllint &> /dev/null; then
    if yamllint -c "${SCRIPT_DIR}/../../.yamllint.yml" "${CHART_DIR}" 2>/dev/null; then
        echo -e "${GREEN}✓ YAML syntax validation passed${NC}"
    else
        echo -e "${YELLOW}⚠ YAML linting found issues (non-blocking)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ yamllint not installed, skipping YAML validation${NC}"
fi

# Test 9: Check default pod-network security context configuration
echo -e "\n${YELLOW}[TEST 9]${NC} Validating default pod-network security context..."
if echo "$RENDERED" | grep -q "privileged: false"; then
    echo -e "${GREEN}✓ Default pod-network security context configured${NC}"
else
    echo -e "${RED}✗ Default pod-network security context not found${NC}"
    exit 1
fi

if echo "$RENDERED" | grep -q "hostNetwork: false"; then
    echo -e "${GREEN}✓ Pod networking configured by default${NC}"
else
    echo -e "${RED}✗ Pod networking default not found${NC}"
    exit 1
fi

# Test 10: Validate init container configuration
echo -e "\n${YELLOW}[TEST 10]${NC} Validating init container..."
if echo "$RENDERED" | grep -q "name: enroll"; then
    echo -e "${GREEN}✓ Enrollment init container found${NC}"
else
    echo -e "${RED}✗ Enrollment init container not found${NC}"
    exit 1
fi

# Test 10b: Validate API enrollment DaemonSet configuration
echo -e "\n${YELLOW}[TEST 10b]${NC} Validating API enrollment DaemonSet..."
API_RENDERED=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=api \
    --set enrollment.commonName="e2eabac9e9f715ff" \
    --set enrollment.api.baseUrl="https://tenant.goskope.com" \
    --set enrollment.api.existingSecret="npa-api-token" \
    --set persistence.enabled=false)

if echo "$API_RENDERED" | grep -q "name: enroll"; then
    echo -e "${RED}✗ API enrollment should not render init container${NC}"
    exit 1
else
    echo -e "${GREEN}✓ API enrollment omits init container${NC}"
fi

if echo "$API_RENDERED" | grep -q "kind: Secret"; then
    echo -e "${RED}✗ API enrollment should not render registration token Secret${NC}"
    exit 1
else
    echo -e "${GREEN}✓ API enrollment omits registration token Secret${NC}"
fi

if echo "$API_RENDERED" | grep -q "^apiVersion: apps/v1$"; then
    echo -e "${GREEN}✓ API enrollment DaemonSet starts with apiVersion${NC}"
else
    echo -e "${RED}✗ API enrollment DaemonSet apiVersion not found at line start${NC}"
    exit 1
fi

if echo "$API_RENDERED" | grep -q "cpu: 1000m"; then
    echo -e "${GREEN}✓ Publisher CPU limit capped at 1000m${NC}"
else
    echo -e "${RED}✗ Publisher CPU limit should be capped at 1000m${NC}"
    exit 1
fi

if echo "$API_RENDERED" | grep -q "memory: 1536Mi"; then
    echo -e "${GREEN}✓ Publisher memory limit set to 1536Mi${NC}"
else
    echo -e "${RED}✗ Publisher memory limit should be 1536Mi${NC}"
    exit 1
fi

for expected in \
    "/home/k8s-bootstrap.sh" \
    "key: k8s-bootstrap.sh" \
    "Kubernetes bootstrap for develop publisher images" \
    "Missing executable /home/k8s-bootstrap.sh" \
    "k8s-api-enroll-and-start.sh" \
    "name: NPA_API_TOKEN" \
    "name: npa-api-token" \
    "key: api-token" \
    "emptyDir: {}" \
    "create_publisher" \
    "jq -n --arg name" \
    "Content-Type: application/json" \
    'payload="$(cat)"' \
    ".common_name ==" \
    ".publisher_name ==" \
    "Publisher creation response summary" \
    "jq -r '.data.id // empty'" \
    "/registration_token"; do
    if echo "$API_RENDERED" | grep -q "$expected"; then
        echo -e "  ${GREEN}✓${NC} Found: $expected"
    else
        echo -e "  ${RED}✗${NC} Missing: $expected"
        exit 1
    fi
done

for expected in \
    "/home/k8s-bootstrap.sh" \
    "key: k8s-bootstrap.sh" \
    "Kubernetes bootstrap for develop publisher images"; do
    if echo "$RENDERED" | grep -q "$expected"; then
        echo -e "  ${GREEN}✓${NC} Found token enrollment bootstrap: $expected"
    else
        echo -e "  ${RED}✗${NC} Missing token enrollment bootstrap: $expected"
        exit 1
    fi
done

# Test 11: Validate BIND forwarders configuration
echo -e "\n${YELLOW}[TEST 11]${NC} Validating BIND forwarders configuration..."
RENDERED_WITH_FORWARDERS=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=token \
    --set networking.mode=host \
    --set persistence.enabled=true \
    --set registrationToken.value="test-token" \
    --set bind.forwarders="{8.8.8.8,8.8.4.4}")

if echo "$RENDERED_WITH_FORWARDERS" | grep -q "^  BIND_FORWARDERS:"; then
    if echo "$RENDERED_WITH_FORWARDERS" | grep -q "8.8.8.8,8.8.4.4"; then
        echo -e "${GREEN}✓ BIND forwarders configuration working${NC}"
    else
        echo -e "${RED}✗ BIND forwarders value incorrect${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ BIND_FORWARDERS environment variable not found${NC}"
    exit 1
fi

if echo "$RENDERED_WITH_FORWARDERS" | grep -q "Applying explicit BIND forwarders"; then
    echo -e "${GREEN}✓ Explicit BIND forwarders are applied by bootstrap${NC}"
else
    echo -e "${RED}✗ Bootstrap does not apply explicit BIND forwarders${NC}"
    exit 1
fi

if echo "$RENDERED_WITH_FORWARDERS" | grep -q 'local named_options="/etc/bind/named.conf.options"' \
    && echo "$RENDERED_WITH_FORWARDERS" | grep -q "apply_bind_forwarders_to_named_config"; then
    echo -e "${GREEN}✓ Explicit BIND forwarders are written to named.conf.options${NC}"
else
    echo -e "${RED}✗ Bootstrap does not write explicit BIND forwarders to named.conf.options${NC}"
    exit 1
fi

# Test that BIND_FORWARDERS is NOT present when forwarders list is empty
RENDERED_WITHOUT_FORWARDERS=$(helm template test-release "${CHART_DIR}" \
    --set enrollment.mode=token \
    --set networking.mode=host \
    --set persistence.enabled=true \
    --set registrationToken.value="test-token" \
    --set bind.forwarders=null)

if echo "$RENDERED_WITHOUT_FORWARDERS" | grep -q "^  BIND_FORWARDERS:"; then
    echo -e "${RED}✗ BIND_FORWARDERS should not be present with empty forwarders${NC}"
    exit 1
else
    echo -e "${GREEN}✓ BIND forwarders correctly omitted when not configured${NC}"
fi

if echo "$RENDERED_WITHOUT_FORWARDERS" | grep -q "Using DNS forwarders from pod resolv.conf"; then
    echo -e "${GREEN}✓ Bootstrap auto-discovers DNS forwarders from resolv.conf${NC}"
else
    echo -e "${RED}✗ Bootstrap DNS auto-discovery path missing${NC}"
    exit 1
fi

# Test 12: Validate pod network mode rendering
echo -e "\n${YELLOW}[TEST 12]${NC} Validating pod network mode rendering..."
POD_NETWORK_RENDERED=$(helm template test-release "${CHART_DIR}" \
    --set networking.mode=pod \
    --set enrollment.mode=api \
    --set enrollment.commonName="e2eabac9e9f715ff" \
    --set enrollment.api.baseUrl="https://tenant.goskope.com" \
    --set enrollment.api.existingSecret="npa-api-token" \
    --set persistence.enabled=false)

for expected in \
    "hostNetwork: false" \
    "dnsPolicy: ClusterFirst" \
    "privileged: false" \
    "allowPrivilegeEscalation: false" \
    "name: NPA_NETWORKING_MODE" \
    "value: \"pod\"" \
    "name: NPA_DISABLE_IPV6" \
    "value: \"true\"" \
    "mountPath: /dev/net/tun" \
    "path: /dev/net/tun" \
    "type: CharDevice" \
    "Preparing pod network namespace" \
    "Skipping host-level sysctl tuning in pod network mode" \
    "Disabling IPv6 in the pod network namespace" \
    "Removing IPv6 from tun0" \
    "Installed iptables stderr filter" \
    "No chain/target/match by that name." \
    "Installed sysctl stderr filter" \
    "net.ipv4.conf.tun0.route_localnet"; do
    if echo "$POD_NETWORK_RENDERED" | grep -q "$expected"; then
        echo -e "  ${GREEN}✓${NC} Found pod network setting: $expected"
    else
        echo -e "  ${RED}✗${NC} Missing pod network setting: $expected"
        exit 1
    fi
done

for expected in \
    "name: local-dns" \
    "dockurr/dnsmasq:latest" \
    'UPSTREAM_DNS="$(awk' \
    "--listen-address=127.0.0.1" \
    "--bind-interfaces" \
    '--server="${UPSTREAM_DNS}"' \
    "--cache-size=1000" \
    "Using dnsmasq sidecar for pod-local DNS"; do
    if echo "$POD_NETWORK_RENDERED" | grep -F -q -- "$expected"; then
        echo -e "  ${GREEN}✓${NC} Found local DNS setting: $expected"
    else
        echo -e "  ${RED}✗${NC} Missing local DNS setting: $expected"
        exit 1
    fi
done

if echo "$POD_NETWORK_RENDERED" | grep -q "privileged: true"; then
    echo -e "${RED}✗ Pod network mode should not render privileged: true${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Pod network mode omits privileged container setting${NC}"
fi

# Test 13: Validate API StatefulSet multi-pod mode rendering
echo -e "\n${YELLOW}[TEST 13]${NC} Validating API StatefulSet multi-pod mode rendering..."
STATEFULSET_RENDERED=$(helm template test-release "${CHART_DIR}" \
    --set workload.type=statefulset \
    --set workload.replicas=3 \
    --set networking.mode=pod \
    --set enrollment.mode=api \
    --set enrollment.commonName="prod-k8s-publisher" \
    --set enrollment.api.baseUrl="https://tenant.goskope.com" \
    --set enrollment.api.existingSecret="npa-api-token" \
    --set persistence.enabled=false)

for expected in \
    "kind: StatefulSet" \
    "kind: Service" \
    "clusterIP: None" \
    "replicas: 3" \
    "serviceName: test-release-kubernetes-netskope-publisher-headless" \
    "podManagementPolicy: Parallel" \
    "name: NPA_COMMON_NAME_APPEND_POD_NAME" \
    "NPA_PUBLISHER_COMMON_NAME=\"\${NPA_PUBLISHER_COMMON_NAME}-\${POD_NAME}\""; do
    if echo "$STATEFULSET_RENDERED" | grep -q "$expected"; then
        echo -e "  ${GREEN}✓${NC} Found StatefulSet setting: $expected"
    else
        echo -e "  ${RED}✗${NC} Missing StatefulSet setting: $expected"
        exit 1
    fi
done

if echo "$STATEFULSET_RENDERED" | grep -q "kind: DaemonSet"; then
    echo -e "${RED}✗ StatefulSet mode should not render a DaemonSet${NC}"
    exit 1
else
    echo -e "${GREEN}✓ StatefulSet mode omits DaemonSet${NC}"
fi

# Test 14: Validate rootless lwIP mode rendering
echo -e "\n${YELLOW}[TEST 14]${NC} Validating rootless lwIP mode rendering..."
LWIP_RENDERED=$(helm template test-release "${CHART_DIR}" \
    --set networking.mode=lwip \
    --set enrollment.mode=api \
    --set enrollment.commonName="lwip-publisher" \
    --set enrollment.api.baseUrl="https://tenant.goskope.com" \
    --set enrollment.api.existingSecret="npa-api-token" \
    --set persistence.enabled=false)

for expected in \
    "hostNetwork: false" \
    "dnsPolicy: ClusterFirst" \
    "privileged: false" \
    "allowPrivilegeEscalation: false" \
    "drop:" \
    "- ALL" \
    "runAsNonRoot: true" \
    "runAsUser: 65532" \
    "runAsGroup: 65532" \
    "fsGroup: 65532" \
    "fsGroupChangePolicy: OnRootMismatch" \
    "name: NPA_NETWORKING_MODE" \
    "value: \"lwip\"" \
    "image: \"netskopeprivateaccess/publisher_u22_test:10827\"" \
    "imagePullPolicy: IfNotPresent" \
    "name: DATA_PLANE" \
    "value: \"lwip\"" \
    "Skipping hosts alias update in lwIP mode" \
    "Skipping tun network namespace preparation in lwIP mode" \
    "Skipping DNS daemon startup in lwIP mode" \
    "Skipping root-managed system services in lwIP mode" \
    "Skipping network sysctl tuning in lwIP mode"; do
    if echo "$LWIP_RENDERED" | grep -F -q -- "$expected"; then
        echo -e "  ${GREEN}✓${NC} Found lwIP setting: $expected"
    else
        echo -e "  ${RED}✗${NC} Missing lwIP setting: $expected"
        exit 1
    fi
done

for unexpected in \
    "NET_ADMIN" \
    "NET_RAW" \
    "mountPath: /dev/net/tun" \
    "path: /dev/net/tun" \
    "type: CharDevice" \
    "mountPath: /etc/passwd" \
    "name: fake-root-passwd" \
    "name: NPA_DISABLE_IPV6" \
    "name: local-dns" \
    "dockurr/dnsmasq"; do
    if echo "$LWIP_RENDERED" | grep -F -q -- "$unexpected"; then
        echo -e "  ${RED}✗${NC} lwIP mode rendered forbidden setting: $unexpected"
        exit 1
    else
        echo -e "  ${GREEN}✓${NC} lwIP mode omits forbidden setting: $unexpected"
    fi
done

LWIP_FAKE_ROOT_RENDERED=$(helm template test-release "${CHART_DIR}" \
    --set networking.mode=lwip \
    --set lwipRootlessCompat.fakeRootPasswd=true \
    --set enrollment.mode=api \
    --set enrollment.commonName="lwip-publisher" \
    --set enrollment.api.baseUrl="https://tenant.goskope.com" \
    --set enrollment.api.existingSecret="npa-api-token" \
    --set persistence.enabled=false)

for expected in \
    "fake-root-passwd: |" \
    "root:x:65532:65532:root:/home:/usr/sbin/nologin" \
    "name: fake-root-passwd" \
    "mountPath: /etc/passwd" \
    "subPath: passwd" \
    "readOnly: true"; do
    if echo "$LWIP_FAKE_ROOT_RENDERED" | grep -F -q -- "$expected"; then
        echo -e "  ${GREEN}✓${NC} Found lwIP fake-root passwd setting: $expected"
    else
        echo -e "  ${RED}✗${NC} Missing lwIP fake-root passwd setting: $expected"
        exit 1
    fi
done

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}All tests passed!${NC}"
echo -e "${GREEN}=========================================${NC}"

echo -e "\nTo install the chart, run:"
echo -e "  helm install npa-publisher ${CHART_DIR} \\"
echo -e "    -f my-api-config.yaml"
