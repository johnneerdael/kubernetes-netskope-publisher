#!/bin/bash
# Kubernetes bootstrap for develop publisher images.
# This script avoids a custom image by replacing systemd-only startup with
# direct daemon management inside the pod.

set -euo pipefail

cd /home
source /home/monitor_service.sh

NAMED_PID=""
RSYSLOGD_PID=""
CRON_PID=""
WIZARD_PID=""
PUBLISHER_PID=""
IPV6_CLEANUP_PID=""

LOGLEVEL_FILE="/home/resources/loglevel"
NSCONFIG_FILE="/home/resources/nsconfig.json"
NETINFO_IPTABLES="/home/netinfo/iptables"

log() {
  echo "k8s-bootstrap: $*"
}

start_process() {
  local name="$1"
  shift

  log "Starting ${name}: $*"
  "$@" &
  local pid=$!
  sleep 1

  if kill -0 "${pid}" >/dev/null 2>&1; then
    log "${name} started with PID ${pid}"
    echo "${pid}"
    return 0
  fi

  log "ERROR - ${name} failed to start"
  return 1
}

stop_process() {
  local name="$1"
  local pid="$2"

  if [ -z "${pid}" ] || ! kill -0 "${pid}" >/dev/null 2>&1; then
    return 0
  fi

  log "Stopping ${name} PID ${pid}"
  kill -TERM "${pid}" >/dev/null 2>&1 || true
  for _ in $(seq 1 10); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  kill -KILL "${pid}" >/dev/null 2>&1 || true
}

cleanup() {
  log "Received shutdown signal"
  stop_process "publisher" "${PUBLISHER_PID}"
  stop_process "IPv6 cleanup" "${IPV6_CLEANUP_PID}"
  stop_process "wizard companion" "${WIZARD_PID}"
  stop_process "cron" "${CRON_PID}"
  stop_process "rsyslogd" "${RSYSLOGD_PID}"
  stop_process "named" "${NAMED_PID}"
}

trap cleanup SIGTERM SIGINT

install_systemctl_shim() {
  local shim_dir="/tmp/k8s-systemctl"
  mkdir -p "${shim_dir}"
  cat > "${shim_dir}/systemctl" <<'SHIM'
#!/bin/bash
set -euo pipefail

action="${1:-}"
service="${2:-}"

case "${action}:${service}" in
  enable:*)
    exit 0
    ;;
  restart:named|start:named|start:bind9)
    pkill -TERM -x named >/dev/null 2>&1 || true
    sleep 1
    pkill -KILL -x named >/dev/null 2>&1 || true
    rm -f /run/named/named.pid /var/run/named/named.pid
    /usr/sbin/named -f -c /etc/bind/named.conf &
    exit 0
    ;;
  start:rsyslog)
    pgrep -x rsyslogd >/dev/null 2>&1 || /usr/sbin/rsyslogd
    exit 0
    ;;
  start:cron)
    pgrep -x cron >/dev/null 2>&1 || /usr/sbin/cron
    exit 0
    ;;
  *)
    echo "k8s systemctl shim does not support: ${action} ${service}" >&2
    exit 1
    ;;
esac
SHIM
  chmod +x "${shim_dir}/systemctl"
  export PATH="${shim_dir}:${PATH}"
}

wait_for_artifacts() {
  local required=(
    "/home/resources/publisherid"
    "/home/resources/sslcert/agent.key"
    "/home/resources/sslcert/agent.pem"
    "/home/resources/sslcert/tenantca.pem"
    "/home/resources/settings.json"
  )

  log "Waiting for enrollment artifacts"
  while true; do
    local missing=()
    for artifact in "${required[@]}"; do
      if [ ! -s "${artifact}" ]; then
        missing+=("${artifact}")
      fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
      log "Enrollment artifacts detected"
      return 0
    fi

    log "Still waiting for artifacts: ${missing[*]}"
    sleep 2
  done
}

ensure_nsconfig() {
  local wizard_sha="$1"

  if [ -s "${NSCONFIG_FILE}" ]; then
    log "nsconfig.json already present"
    return 0
  fi

  log "Pulling nsconfig.json"
  /usr/bin/logger "SHA256 sum of wizard ${wizard_sha} for pulling nsconfig"
  /home/npa_publisher_wizard -pull_nsconfig

  if [ ! -s "${NSCONFIG_FILE}" ]; then
    log "ERROR - nsconfig.json is missing after wizard pull"
    exit 1
  fi
}

ensure_loglevel() {
  mkdir -p "$(dirname "${LOGLEVEL_FILE}")"
  if [ ! -s "${LOGLEVEL_FILE}" ]; then
    echo "3" > "${LOGLEVEL_FILE}"
  fi
}

resolve_iptables() {
  local target=""

  if [ -e "${NETINFO_IPTABLES}" ]; then
    target="$(readlink -f "${NETINFO_IPTABLES}" 2>/dev/null || true)"
    if [ -n "${target}" ] && [ -x "${target}" ]; then
      echo "${target}"
      return 0
    fi
  fi

  command -v iptables
}

create_iptables_wrapper() {
  local wrapper_dir="$1"
  local name="$2"
  local real_cmd=""

  real_cmd="$(command -v "${name}" 2>/dev/null || true)"
  if [ -z "${real_cmd}" ]; then
    return 0
  fi

  cat > "${wrapper_dir}/${name}" <<WRAPPER
#!/bin/bash
stderr_file="\$(mktemp)"
"${real_cmd}" "\$@" 2>"\${stderr_file}"
status=\$?
grep -F -v "iptables: No chain/target/match by that name." "\${stderr_file}" >&2 || true
rm -f "\${stderr_file}"
exit "\${status}"
WRAPPER
  chmod +x "${wrapper_dir}/${name}"
}

install_iptables_stderr_filter() {
  local wrapper_dir="/tmp/k8s-iptables"

  mkdir -p "${wrapper_dir}"
  create_iptables_wrapper "${wrapper_dir}" iptables-legacy
  create_iptables_wrapper "${wrapper_dir}" iptables-nft
  export PATH="${wrapper_dir}:${PATH}"
  log "Installed iptables stderr filter in ${wrapper_dir}"
}

install_sysctl_stderr_filter() {
  local wrapper_dir="/tmp/k8s-sysctl"
  local real_cmd=""

  real_cmd="$(command -v sysctl 2>/dev/null || true)"
  if [ -z "${real_cmd}" ]; then
    return 0
  fi

  mkdir -p "${wrapper_dir}"
  cat > "${wrapper_dir}/sysctl" <<WRAPPER
#!/bin/bash
stderr_file="\$(mktemp)"
"${real_cmd}" "\$@" 2>"\${stderr_file}"
status=\$?
grep -F -v 'sysctl: setting key "net.ipv4.conf.tun0.route_localnet", ignoring: Read-only file system' "\${stderr_file}" >&2 || true
rm -f "\${stderr_file}"
exit "\${status}"
WRAPPER
  chmod +x "${wrapper_dir}/sysctl"
  export PATH="${wrapper_dir}:${PATH}"
  log "Installed sysctl stderr filter in ${wrapper_dir}"
}

run_sysctl() {
  local key="$1"
  local value="$2"
  local output=""

  if output="$(sysctl -w "${key}=${value}" 2>&1)"; then
    log "${output}"
    return 0
  fi

  log "Skipping sysctl ${key}=${value}; ${output}"
  return 0
}

disable_ipv6_if_requested() {
  if [ "${NPA_DISABLE_IPV6:-false}" != "true" ]; then
    return 0
  fi

  log "Disabling IPv6 in the pod network namespace"
  run_sysctl net.ipv6.conf.all.disable_ipv6 1
  run_sysctl net.ipv6.conf.default.disable_ipv6 1
}

prepare_network_namespace() {
  if [ "${NPA_NETWORKING_MODE:-host}" != "pod" ]; then
    /home/prepare_host.sh
    return 0
  fi

  log "Preparing pod network namespace"
  sed -i '/[[:space:]]tunrt$/d' /etc/iproute2/rt_tables
  echo "1 tunrt" >> /etc/iproute2/rt_tables
}

apply_bind_forwarders_override() {
  if [ -z "${BIND_FORWARDERS:-}" ]; then
    log "Using DNS forwarders from pod resolv.conf"
    return 0
  fi

  log "Applying explicit BIND forwarders: ${BIND_FORWARDERS}"
  cp /etc/resolv.conf /etc/resolv.conf.k8s-original
  : > /etc/resolv.conf

  local forwarder
  local old_ifs="${IFS}"
  IFS=","
  for forwarder in ${BIND_FORWARDERS}; do
    forwarder="${forwarder#"${forwarder%%[![:space:]]*}"}"
    forwarder="${forwarder%"${forwarder##*[![:space:]]}"}"
    if [ -n "${forwarder}" ]; then
      echo "nameserver ${forwarder}" >> /etc/resolv.conf
    fi
  done
  IFS="${old_ifs}"
}

bind_forwarders_block() {
  local forwarder
  local old_ifs="${IFS}"
  local found_forwarder="false"

  echo "	forwarders {"
  IFS=","
  for forwarder in ${BIND_FORWARDERS}; do
    forwarder="${forwarder#"${forwarder%%[![:space:]]*}"}"
    forwarder="${forwarder%"${forwarder##*[![:space:]]}"}"
    if [ -n "${forwarder}" ]; then
      found_forwarder="true"
      echo "		${forwarder};"
    fi
  done
  IFS="${old_ifs}"
  echo "	};"

  if [ "${found_forwarder}" != "true" ]; then
    return 1
  fi
}

apply_bind_forwarders_to_named_config() {
  if [ -z "${BIND_FORWARDERS:-}" ]; then
    return 0
  fi

  local named_options="/etc/bind/named.conf.options"
  local forwarders_block=""
  local tmp_options=""

  if [ ! -s "${named_options}" ]; then
    log "ERROR - missing ${named_options}; cannot apply explicit BIND forwarders"
    return 1
  fi
  if ! grep -q '^[[:space:]]*forwarders[[:space:]]*{' "${named_options}"; then
    log "ERROR - ${named_options} has no forwarders block to replace"
    return 1
  fi

  forwarders_block="$(bind_forwarders_block)" || {
    log "ERROR - BIND_FORWARDERS is set but contains no usable forwarder addresses"
    return 1
  }

  log "Updating ${named_options} with explicit BIND forwarders: ${BIND_FORWARDERS}"
  cp "${named_options}" "${named_options}.k8s-original"
  tmp_options="$(mktemp)"
  awk -v block="${forwarders_block}" '
    /^[[:space:]]*forwarders[[:space:]]*\{/ {
      print block
      skipping = 1
      next
    }
    skipping && /^[[:space:]]*\};/ {
      skipping = 0
      next
    }
    !skipping {
      print
    }
  ' "${named_options}" > "${tmp_options}"
  mv "${tmp_options}" "${named_options}"

  systemctl restart named
}

cleanup_tun0_ipv6_if_requested() {
  if [ "${NPA_DISABLE_IPV6:-false}" != "true" ]; then
    return 0
  fi

  for _ in $(seq 1 60); do
    if ip link show tun0 >/dev/null 2>&1; then
      log "Removing IPv6 from tun0"
      ip -6 addr flush dev tun0 >/dev/null 2>&1 || true
      ip -6 route flush dev tun0 >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done

  log "tun0 not found; skipping IPv6 cleanup"
}

apply_network_sysctls() {
  if [ "${NPA_NETWORKING_MODE:-host}" = "pod" ]; then
    log "Skipping host-level sysctl tuning in pod network mode"
    return 0
  fi

  run_sysctl net.ipv4.ip_forward 1
  run_sysctl net.core.netdev_max_backlog 10000
  run_sysctl net.core.rmem_max 8388608
  run_sysctl net.core.wmem_max 8388608
  run_sysctl net.ipv4.tcp_rmem "4096 87380 16777216"
  run_sysctl net.ipv4.tcp_wmem "4096 87380 16777216"
  run_sysctl net.ipv4.tcp_mem "12206844 16275792 24413688"
  run_sysctl net.netfilter.nf_conntrack_tcp_timeout_established 86400
}

install_systemctl_shim
install_iptables_stderr_filter
install_sysctl_stderr_filter

if [ -f /home/resources/proxy_settings.sh ]; then
  source /home/resources/proxy_settings.sh
fi

disable_ipv6_if_requested

echo '127.0.0.1 guacamole-frontend' >> /etc/hosts

prepare_network_namespace
apply_bind_forwarders_override
/home/configure_bind.sh "${HOST_OS_TYPE:-ubuntu}"
apply_bind_forwarders_to_named_config
NAMED_PID="$(pgrep -x named | head -1 || true)"

ulimit -n 32000

systemctl enable rsyslog
systemctl start rsyslog
monitor_service "rsyslog" "rsyslogd" &
RSYSLOGD_PID="$(pgrep -x rsyslogd | head -1 || true)"

systemctl enable cron
systemctl start cron
monitor_service "cron" "cron" &
CRON_PID="$(pgrep -x cron | head -1 || true)"

cp -f /home/npa_publisher_collect_host_os_info.sh /home/resources/npa_publisher_collect_host_os_info.sh
cp -f /home/npa_publisher_collect_metrics.sh /home/resources/npa_publisher_collect_metrics.sh
cp -f /home/npa_publisher_auto_upgrade.sh /home/resources/npa_publisher_auto_upgrade.sh
cp -f /home/.npa_publisher_cronjob_env /home/resources/.npa_publisher_cronjob_env
cp -f /home/ba_any_app_expand_drive.sh /home/resources/ba_any_app_expand_drive.sh

wait_for_artifacts

sha_value="$(/usr/bin/sha256sum /home/npa_publisher_wizard)"
ensure_nsconfig "${sha_value}"
ensure_loglevel

rm -rf /home/resources/.killSwitch
touch /home/resources/.killSwitch

/usr/bin/logger "SHA256 sum of wizard ${sha_value} for running companion"
( while true; do
  /home/npa_publisher_wizard -companion
done ) &
WIZARD_PID=$!

stitcherport=443
stitcher="$(</home/resources/stitcher)"
tenant="$(</home/resources/tenant)"
loglevel="$(<"${LOGLEVEL_FILE}")"
if [ -z "${loglevel}" ]; then
  loglevel=3
fi

DISCOVERY_REFRESH=1
if [ -f /home/resources/.prc_dp ]; then
  DISCOVERY_REFRESH=
fi

apply_network_sysctls

IPTABLES_CMD="$(resolve_iptables)"
log "IPTABLES_CMD is ${IPTABLES_CMD}"

log "Starting NPA Publisher"
LD_PRELOAD=/home/libjemalloc.so.2 \
  DISCOVERY_REFRESH="${DISCOVERY_REFRESH}" \
  HOST_OS_TYPE="${HOST_OS_TYPE:-ubuntu}" \
  IPTABLES_CMD="${IPTABLES_CMD}" \
  /home/npa_publisher -a "${stitcher}" -p "${stitcherport}" -l "${loglevel}" -n "${tenant}" -c resources/settings.json &
PUBLISHER_PID=$!

cleanup_tun0_ipv6_if_requested &
IPV6_CLEANUP_PID=$!

wait "${PUBLISHER_PID}"
