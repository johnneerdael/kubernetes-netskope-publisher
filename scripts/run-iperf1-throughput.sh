#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'USAGE'
Run a single-lane iperf3 throughput test through one NPA Publisher path.

Defaults:
  client: client1
  server: downloadserver1
  target: 172.31.43.126

Usage:
  scripts/run-iperf1-throughput.sh [options]

This wrapper accepts the same options as run-iperf4-throughput.sh.
Use --clients, --servers, or --targets to override the single-lane defaults.

USAGE
      exec python3 "${script_dir}/run_iperf4_throughput.py" --help
      ;;
  esac
done

exec python3 "${script_dir}/run_iperf4_throughput.py" \
  --clients "client1" \
  --servers "downloadserver1" \
  --targets "172.31.43.126" \
  "$@"
