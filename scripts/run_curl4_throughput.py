#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from run_iperf4_throughput import DEFAULT_CLIENTS, DEFAULT_SERVERS, DEFAULT_TARGETS, parse_words, run_checked


def parse_curl_writeout(text):
    values = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()

    return {
        "speed_download": float(values.get("speed_download", 0) or 0),
        "time_total": float(values.get("time_total", 0) or 0),
        "size_download": int(float(values.get("size_download", 0) or 0)),
        "http_code": int(values.get("http_code", 0) or 0),
    }


def is_successful_curl_result(status, bytes_downloaded):
    return status == 0 or (status == 28 and bytes_downloaded > 0)


def parse_network_samples(text):
    samples = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            samples.append((float(parts[0]), int(parts[1])))
        except ValueError:
            continue
    return samples


def network_rates_from_samples(client, samples):
    rates = []
    for index, (previous, current) in enumerate(zip(samples, samples[1:]), start=1):
        previous_time, previous_bytes = previous
        current_time, current_bytes = current
        elapsed = current_time - previous_time
        byte_delta = current_bytes - previous_bytes
        if elapsed <= 0 or byte_delta < 0:
            continue
        bps = byte_delta * 8 / elapsed
        rates.append({
            "client": client,
            "sample": index,
            "timestamp": current_time,
            "seconds": elapsed,
            "bytes": byte_delta,
            "bps": bps,
            "mbps": bps / 1_000_000,
            "gbps": bps / 1_000_000_000,
        })
    return rates


def peak_combined_network_rate(rates, bucket_seconds=1.0):
    by_bucket = {}
    for rate in rates:
        bucket = int(rate["timestamp"] // bucket_seconds)
        aggregate = by_bucket.setdefault(
            bucket,
            {
                "bucket": bucket,
                "bucket_start": bucket * bucket_seconds,
                "bucket_seconds": bucket_seconds,
                "bytes": 0,
                "clients": [],
            },
        )
        aggregate["bytes"] += rate["bytes"]
        aggregate["clients"].append(rate)
    if not by_bucket:
        return None
    for aggregate in by_bucket.values():
        aggregate["bps"] = aggregate["bytes"] * 8 / bucket_seconds
    peak = max(by_bucket.values(), key=lambda item: item["bps"])
    peak["mbps"] = peak["bps"] / 1_000_000
    peak["gbps"] = peak["bps"] / 1_000_000_000
    return peak


def start_network_monitor(client, result_dir, sample_interval, duration, monitor_interface):
    output_file = result_dir / f"{client}.netrx"
    remote = f"""
set -euo pipefail
iface='{monitor_interface}'
if [ "$iface" = "default" ]; then
  iface="$(ip route show default 2>/dev/null | awk '{{print $5; exit}}')"
fi
if [ -z "$iface" ] || ! grep -qE "^[[:space:]]*$iface:" /proc/net/dev; then
  iface="$(awk -F: '$1 !~ /lo/ {{gsub(/ /, "", $1); print $1; exit}}' /proc/net/dev)"
fi
echo "# interface=$iface"
end=$(( $(date +%s) + {int(duration)} ))
while [ "$(date +%s)" -le "$end" ]; do
  ts="$(date +%s.%N)"
  rx="$(awk -F'[: ]+' -v iface="$iface" '$2 == iface {{print $3 + 0}}' /proc/net/dev)"
  printf '%s %s\\n' "$ts" "$rx"
  sleep '{sample_interval}'
done
"""
    handle = output_file.open("w")
    process = subprocess.Popen(["connect", "exec", client, "bash", "-lc", remote], stdout=handle, stderr=subprocess.DEVNULL, text=True)
    return {"client": client, "file": output_file, "process": process, "handle": handle}


def stop_network_monitors(monitors):
    for monitor in monitors:
        process = monitor["process"]
        if process.poll() is None:
            process.terminate()
    deadline = time.monotonic() + 5
    for monitor in monitors:
        process = monitor["process"]
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.1)
        if process.poll() is None:
            process.kill()
            process.wait()
        if not monitor["handle"].closed:
            monitor["handle"].close()


def network_summary(monitors, peak_bucket_seconds):
    rates = []
    for monitor in monitors:
        if not monitor["handle"].closed:
            monitor["handle"].close()
        text = monitor["file"].read_text() if monitor["file"].exists() else ""
        rates.extend(network_rates_from_samples(monitor["client"], parse_network_samples(text)))
    peak = peak_combined_network_rate(rates, bucket_seconds=peak_bucket_seconds)
    return {
        "samples": rates,
        "peak_combined": peak,
    }


def http_server_command(server_backend, port, file_path):
    root = str(Path(file_path).parent)
    pid_file = f"/tmp/npa-curl-http-{port}.pid"
    nginx_prefix = f"/tmp/npa-nginx-{port}"
    nginx_conf = f"/tmp/npa-nginx-{port}.conf"
    return f"""
set -euo pipefail
mkdir -p '{root}'
if [ -f '{pid_file}' ]; then
  old_pid="$(cat '{pid_file}' || true)"
  if [ -n "$old_pid" ]; then
    kill "$old_pid" >/dev/null 2>&1 || true
  fi
  rm -f '{pid_file}'
fi
backend='{server_backend}'
if [ "$backend" = "auto" ]; then
  if command -v nginx >/dev/null 2>&1; then
    backend='nginx'
  elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx httpd; then
    backend='busybox'
  else
    backend='python'
  fi
fi
case "$backend" in
  nginx)
    command -v nginx >/dev/null
    mkdir -p '{nginx_prefix}'
    cat > '{nginx_conf}' <<'NGINX'
events {{}}
http {{
  access_log off;
  sendfile on;
  tcp_nopush on;
  server {{
    listen 0.0.0.0:{port};
    location / {{
      root {root};
    }}
  }}
}}
NGINX
    nohup nginx -p '{nginx_prefix}' -c '{nginx_conf}' -g 'daemon off;' > /tmp/npa-curl-http-{port}.log 2>&1 &
    ;;
  busybox)
    command -v busybox >/dev/null
    cd '{root}'
    nohup busybox httpd -f -p '0.0.0.0:{port}' -h '{root}' > /tmp/npa-curl-http-{port}.log 2>&1 &
    ;;
  python)
    command -v python3 >/dev/null
    cd '{root}'
    nohup python3 -m http.server '{port}' --bind 0.0.0.0 > /tmp/npa-curl-http-{port}.log 2>&1 &
    ;;
  *)
    echo "unsupported HTTP backend: $backend" >&2
    exit 2
    ;;
esac
echo "$!" > '{pid_file}'
echo "$backend" > /tmp/npa-curl-http-{port}.backend
sleep 1
kill -0 "$(cat '{pid_file}')"
echo "$backend"
"""


def start_servers(servers, port, file_path, file_size_gb, restart, server_backend):
    print()
    print("Starting HTTP download servers")
    for server in servers:
        prepare = f"""
set -euo pipefail
mkdir -p "$(dirname '{file_path}')"
truncate -s '{file_size_gb}G' '{file_path}'
"""
        remote = prepare + http_server_command(server_backend, port, file_path)
        result = run_checked(["connect", "exec", server, "bash", "-lc", remote], f"start HTTP server on {server}")
        backend = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else server_backend
        print(f"  {server} serving {file_path} on {port} with {backend}")


def start_lane(lane, args):
    stdout_file = lane["stdout_file"]
    stderr_file = lane["stderr_file"]
    if lane.get("stdout_handle") and not lane["stdout_handle"].closed:
        lane["stdout_handle"].close()
    if lane.get("stderr_handle") and not lane["stderr_handle"].closed:
        lane["stderr_handle"].close()

    file_name = Path(args.file_path).name
    url = f"http://{lane['target']}:{args.port}/{file_name}"
    writeout = "speed_download=%{speed_download}\\ntime_total=%{time_total}\\nsize_download=%{size_download}\\nhttp_code=%{http_code}\\n"
    remote = [
        "set -euo pipefail",
        "command -v curl >/dev/null",
        (
            f"curl --silent --show-error --output /dev/null "
            f"--connect-timeout '{args.connect_timeout}' --max-time '{args.duration}' "
            f"--write-out '{writeout}' '{url}'"
        ),
    ]
    command = ["connect", "exec", lane["client"], "bash", "-lc", "\n".join(remote)]
    stdout_handle = stdout_file.open("w")
    stderr_handle = stderr_file.open("w")
    process = subprocess.Popen(command, stdout=stdout_handle, stderr=stderr_handle, text=True)
    lane.update({
        "url": url,
        "process": process,
        "stdout_handle": stdout_handle,
        "stderr_handle": stderr_handle,
        "start": time.monotonic(),
        "status": None,
        "error": None,
    })


def close_lane_handles(lane):
    for key in ("stdout_handle", "stderr_handle"):
        handle = lane.get(key)
        if handle and not handle.closed:
            handle.close()


def stop_running_lanes(lanes):
    for lane in lanes:
        process = lane.get("process")
        if process and process.poll() is None:
            process.terminate()

    deadline = time.monotonic() + 5
    for lane in lanes:
        process = lane.get("process")
        if not process:
            continue
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.1)
        if process.poll() is None:
            process.kill()
            process.wait()
        close_lane_handles(lane)


def lane_result(lane):
    text = lane["stdout_file"].read_text() if lane["stdout_file"].exists() else ""
    metrics = parse_curl_writeout(text)
    bps = metrics["speed_download"] * 8
    return {
        "lane": lane["name"],
        "target": lane["target"],
        "url": lane["url"],
        "status": lane["status"],
        "http_code": metrics["http_code"],
        "bytes": metrics["size_download"],
        "time_seconds": metrics["time_total"],
        "bytes_per_second": metrics["speed_download"],
        "bps": bps,
        "mbps": bps / 1_000_000,
        "gbps": bps / 1_000_000_000,
    }


def aggregate_lane_records(records):
    by_lane = {}
    for record in records:
        lane_name = record["lane"]
        aggregate = by_lane.setdefault(
            lane_name,
            {
                "lane": lane_name,
                "target": record.get("target"),
                "url": record.get("url"),
                "streams": 0,
                "bytes": 0,
                "bps": 0,
                "mbps": 0,
                "gbps": 0,
                "stream_records": [],
            },
        )
        aggregate["streams"] += 1
        aggregate["bytes"] += record.get("bytes", 0)
        aggregate["bps"] += record.get("bps", 0)
        aggregate["stream_records"].append(record)

    lanes = list(by_lane.values())
    for lane in lanes:
        lane["mbps"] = lane["bps"] / 1_000_000
        lane["gbps"] = lane["bps"] / 1_000_000_000
    return lanes


def lane_state(status, bytes_downloaded):
    if status == 0:
        return "ok"
    if status == 28 and bytes_downloaded > 0:
        return "timed sample"
    return f"failed ({status})"


def main():
    parser = argparse.ArgumentParser(
        description="Run a curl download throughput test through NPA Publisher paths.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--clients", type=parse_words, default=DEFAULT_CLIENTS, help="connect profiles for client machines")
    parser.add_argument("--servers", type=parse_words, default=DEFAULT_SERVERS, help="connect profiles for server management")
    parser.add_argument("--targets", type=parse_words, default=DEFAULT_TARGETS, help="HTTP target IPs or hostnames reached by clients")
    parser.add_argument("--duration", type=int, default=120, help="curl max-time per lane in seconds")
    parser.add_argument("--parallel", type=int, default=4, help="parallel curl downloads per client lane")
    parser.add_argument("--port", type=int, default=8080, help="HTTP server port")
    parser.add_argument("--file-path", default="/tmp/npa-throughput.bin", help="remote file served by download servers")
    parser.add_argument("--file-size-gb", type=int, default=32, help="sparse file size to create on download servers")
    parser.add_argument("--server-backend", choices=("auto", "nginx", "busybox", "python"), default="auto", help="HTTP server backend to start on download servers")
    parser.add_argument("--connect-timeout", type=int, default=10, help="curl TCP connect timeout in seconds")
    parser.add_argument("--sample-interval", type=float, default=1.0, help="client RX byte sample interval for peak throughput")
    parser.add_argument("--peak-bucket-seconds", type=float, default=1.0, help="time bucket width for combined peak throughput")
    parser.add_argument("--monitor-interface", default="default", help="client network interface to sample, or 'default' for default-route interface")
    parser.add_argument("--progress-interval", type=int, default=10, help="progress print interval while lanes run")
    parser.add_argument("--timeout-padding", type=int, default=20, help="extra seconds before killing a lane")
    parser.add_argument("--server-warmup-seconds", type=float, default=3.0, help="wait after starting servers before running clients")
    parser.add_argument("--result-dir", default=None, help="local directory for output")
    parser.add_argument("--start-servers", action="store_true", help="start HTTP servers over connect before running clients")
    parser.add_argument("--restart-servers", action="store_true", help="restart HTTP servers before running; implies --start-servers")
    parser.add_argument("--setup-only", action="store_true", help="start HTTP servers and exit without running clients")
    args = parser.parse_args()

    lane_count = len(args.clients)
    if len(args.servers) != lane_count or len(args.targets) != lane_count:
        parser.error(
            "--clients, --servers, and --targets must contain the same number of whitespace-separated values "
            f"(got {len(args.clients)}, {len(args.servers)}, {len(args.targets)})"
        )

    result_dir = Path(args.result_dir or f"curl-results/{datetime.now().strftime('%Y%m%d-%H%M%S')}")
    result_dir.mkdir(parents=True, exist_ok=True)

    print(f"Result directory: {result_dir}")
    print(f"Lanes: {lane_count}")
    print(f"Parallel downloads per lane: {args.parallel}")
    print(f"Duration: {args.duration}s")
    print(f"Peak sample interval: {args.sample_interval}s")
    print(f"Peak bucket width: {args.peak_bucket_seconds}s")
    print(f"Monitor interface: {args.monitor_interface}")
    print(f"Port: {args.port}")
    print(f"Targets: {' '.join(args.targets)}")
    print(f"Lane timeout: {args.duration + args.timeout_padding}s")

    if args.restart_servers or args.setup_only:
        args.start_servers = True
    if args.start_servers:
        start_servers(args.servers, args.port, args.file_path, args.file_size_gb, args.restart_servers, args.server_backend)
        if args.setup_only:
            print()
            print("HTTP download server setup complete")
            return
        if args.server_warmup_seconds > 0:
            print(f"Waiting {args.server_warmup_seconds:g}s for server paths to settle")
            time.sleep(args.server_warmup_seconds)

    print()
    print(f"Running {lane_count} curl download lane{'s' if lane_count != 1 else ''}")
    monitors = []
    if args.sample_interval > 0:
        monitor_duration = args.duration + args.timeout_padding
        monitors = [
            start_network_monitor(client, result_dir, args.sample_interval, monitor_duration, args.monitor_interface)
            for client in args.clients
        ]

    lanes = []
    for index, (client, server, target) in enumerate(zip(args.clients, args.servers, args.targets), start=1):
        lane_name = f"lane{index}-{client}-to-{server}"
        print(f"  {lane_name} (http://{target}:{args.port}/{Path(args.file_path).name}) x{args.parallel}")
        for stream in range(1, args.parallel + 1):
            lane = {
                "name": lane_name,
                "stream": stream,
                "client": client,
                "server": server,
                "target": target,
                "stdout_file": result_dir / f"{lane_name}.stream{stream}.curl",
                "stderr_file": result_dir / f"{lane_name}.stream{stream}.stderr",
            }
            start_lane(lane, args)
            lanes.append(lane)

    try:
        while True:
            time.sleep(args.progress_interval)
            for lane in lanes:
                if lane["status"] is not None:
                    continue
                elapsed = int(time.monotonic() - lane["start"])
                status = lane["process"].poll()
                if status is None and elapsed > args.duration + args.timeout_padding:
                    lane["process"].kill()
                    status = lane["process"].wait()
                    lane["status"] = status
                    lane["error"] = f"timeout after {elapsed}s"
                    close_lane_handles(lane)
                    print(f"  finished {lane['name']} stream{lane['stream']}: timeout after {elapsed}s")
                elif status is None:
                    continue
                else:
                    lane["status"] = status
                    close_lane_handles(lane)
                    record = lane_result(lane)
                    state = lane_state(status, record["bytes"])
                    print(f"  finished {lane['name']} stream{lane['stream']}: {state} after {elapsed}s")

            running = []
            now = time.monotonic()
            for lane in lanes:
                if lane["status"] is None:
                    running.append(f"{lane['name']}.s{lane['stream']}:{int(now - lane['start'])}s")
            if running:
                print(f"  progress: {len(running)}/{len(lanes)} downloads still running ({', '.join(running)})")
            else:
                break
    except KeyboardInterrupt:
        print()
        print("Interrupted; stopping local lane processes")
        stop_running_lanes(lanes)
        stop_network_monitors(monitors)
        raise SystemExit(130)

    stop_network_monitors(monitors)

    stream_records = [lane_result(lane) for lane in lanes]
    failed = [
        lane
        for lane, record in zip(lanes, stream_records)
        if not is_successful_curl_result(lane["status"], record["bytes"])
    ]
    if failed:
        print()
        print("One or more lanes failed:")
        for lane in failed:
            print(f"  {lane['name']}: status={lane['status']} stderr={lane['stderr_file']}")
        raise SystemExit(1)

    records = aggregate_lane_records(stream_records)
    net_summary = network_summary(monitors, args.peak_bucket_seconds) if monitors else {"samples": [], "peak_combined": None}
    total_bps = sum(record["bps"] for record in records)
    summary = {
        "lanes": records,
        "streams": stream_records,
        "network": net_summary,
        "peak_combined_bps": net_summary["peak_combined"]["bps"] if net_summary["peak_combined"] else None,
        "peak_combined_mbps": net_summary["peak_combined"]["mbps"] if net_summary["peak_combined"] else None,
        "peak_combined_gbps": net_summary["peak_combined"]["gbps"] if net_summary["peak_combined"] else None,
        "total_bps": total_bps,
        "total_mbps": total_bps / 1_000_000,
        "total_gbps": total_bps / 1_000_000_000,
    }
    summary_file = result_dir / "summary.json"
    summary_file.write_text(json.dumps(summary, indent=2) + "\n")

    print()
    print("Aggregated result")
    print(json.dumps(summary, indent=2))
    print()
    print(f"Summary written to {summary_file}")


if __name__ == "__main__":
    main()
