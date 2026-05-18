#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


DEFAULT_CLIENTS = ["client1", "client2", "client3", "client4"]
DEFAULT_SERVERS = ["downloadserver1", "downloadserver2", "downloadserver3", "downloadserver4"]
DEFAULT_TARGETS = ["172.31.43.126", "172.31.42.63", "172.31.43.39", "172.31.43.137"]
RETRYABLE_IPERF_ERRORS = (
    "server is busy",
    "unable to connect to server",
    "connection reset by peer",
    "unable to receive control message",
)


def parse_words(value):
    items = value.split()
    if not items:
        raise argparse.ArgumentTypeError("expected at least 1 value")
    return items


def run_checked(command, label):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode != 0:
        if result.stdout:
            print(result.stdout, file=sys.stdout, end="")
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        raise SystemExit(f"{label} failed with exit code {result.returncode}")
    return result


def resolve_monitor_direction(monitor_direction, reverse):
    if monitor_direction != "auto":
        return monitor_direction
    return "rx" if reverse else "tx"


def interface_counter_field(monitor_direction):
    if monitor_direction == "rx":
        return 3
    if monitor_direction == "tx":
        return 11
    raise ValueError(f"unsupported monitor direction: {monitor_direction}")


def read_client_interface_bytes(client, monitor_interface, monitor_direction):
    counter_field = interface_counter_field(monitor_direction)
    remote = f"""
set -euo pipefail
iface='{monitor_interface}'
if [ "$iface" = "default" ]; then
  iface="$(ip route show default 2>/dev/null | awk '{{print $5; exit}}')"
fi
if [ -z "$iface" ] || ! grep -qE "^[[:space:]]*$iface:" /proc/net/dev; then
  iface="$(awk -F: '$1 !~ /lo/ {{gsub(/ /, "", $1); print $1; exit}}' /proc/net/dev)"
fi
awk -F'[: ]+' -v iface="$iface" '$2 == iface {{print ${counter_field} + 0}}' /proc/net/dev
"""
    result = subprocess.run(["connect", "exec", client, "bash", "-lc", remote], text=True, capture_output=True)
    if result.returncode != 0:
        return None
    try:
        return int(result.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        return None


def read_clients_interface_bytes(clients, monitor_interface, monitor_direction):
    values = {}
    for client in clients:
        value = read_client_interface_bytes(client, monitor_interface, monitor_direction)
        if value is not None:
            values[client] = value
    return values


def live_throughput(previous, current, seconds):
    total_bytes = 0
    clients = []
    for client, current_bytes in current.items():
        previous_bytes = previous.get(client)
        if previous_bytes is None:
            continue
        delta = current_bytes - previous_bytes
        if delta < 0:
            continue
        total_bytes += delta
        clients.append({"client": client, "bytes": delta, "bps": delta * 8 / seconds})
    bps = total_bytes * 8 / seconds if seconds > 0 else 0
    return {
        "bytes": total_bytes,
        "bps": bps,
        "mbps": bps / 1_000_000,
        "gbps": bps / 1_000_000_000,
        "clients": clients,
    }


def start_servers(servers, port, restart):
    print()
    print("Starting iperf3 servers")
    for server in servers:
        if restart:
            run_checked(["connect", "exec", server, "bash", "-lc", "pkill -x iperf3 || true"], f"restart {server}")

        remote = f"""
set -euo pipefail
command -v iperf3 >/dev/null
if ! pgrep -x iperf3 >/dev/null 2>&1; then
  nohup iperf3 -s -p '{port}' > /tmp/iperf3-server.log 2>&1 &
fi
sleep 1
pgrep -x iperf3 >/dev/null
"""
        run_checked(["connect", "exec", server, "bash", "-lc", remote], f"start iperf3 on {server}")
        print(f"  {server} listening on {port}")


def lane_rate_bps(payload):
    end = payload.get("end", {})
    for key in ("sum_received", "sum", "sum_sent"):
        value = end.get(key, {}).get("bits_per_second")
        if value is not None:
            return float(value)
    return 0.0


def load_json_if_present(path):
    if not path.exists() or path.stat().st_size == 0:
        return None
    with path.open() as handle:
        return json.load(handle)


def lane_iperf_error(lane):
    try:
        payload = load_json_if_present(lane["json_file"])
    except json.JSONDecodeError as exc:
        return f"invalid JSON output: {exc}"

    if payload is None:
        return "empty JSON output"
    if payload.get("error"):
        return payload["error"]
    return None


def start_lane(lane, args, attempt):
    if lane.get("stdout_handle") and not lane["stdout_handle"].closed:
        lane["stdout_handle"].close()
    if lane.get("stderr_handle") and not lane["stderr_handle"].closed:
        lane["stderr_handle"].close()

    json_file = lane["json_file"]
    stderr_file = lane["stderr_file"]
    if attempt > 1:
        json_file = lane["json_file"].with_name(f"{lane['json_file'].stem}.attempt{attempt}.json")
        stderr_file = lane["stderr_file"].with_name(f"{lane['stderr_file'].stem}.attempt{attempt}.stderr")

    remote = [
        "set -euo pipefail",
        "command -v iperf3 >/dev/null",
        (
            f"iperf3 -c '{lane['target']}' -p '{args.port}' -t '{args.duration}' "
            f"-P '{args.parallel}' --connect-timeout '{args.connect_timeout_ms}' "
            f"--snd-timeout '{args.snd_timeout_ms}' -i '{args.interval}' "
            f"{'-R ' if args.reverse else ''}--json"
        ),
    ]
    command = ["connect", "exec", lane["client"], "bash", "-lc", "\n".join(remote)]
    stdout_handle = json_file.open("w")
    stderr_handle = stderr_file.open("w")
    process = subprocess.Popen(command, stdout=stdout_handle, stderr=stderr_handle, text=True)

    lane.update({
        "attempt": attempt,
        "json_file": json_file,
        "stderr_file": stderr_file,
        "stdout_handle": stdout_handle,
        "stderr_handle": stderr_handle,
        "process": process,
        "start": time.monotonic(),
        "status": None,
        "error": None,
        "retry_at": None,
    })


def close_lane_handles(lane):
    for key in ("stdout_handle", "stderr_handle"):
        handle = lane.get(key)
        if handle and not handle.closed:
            handle.close()


def is_retryable_error(error):
    if not error:
        return False
    normalized = error.lower()
    return any(fragment in normalized for fragment in RETRYABLE_IPERF_ERRORS)


def should_retry_lane(status, attempt, retries, elapsed, retry_window, error):
    return (
        status != 0
        and attempt <= retries
        and elapsed <= retry_window
        and is_retryable_error(error)
    )


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


def main():
    parser = argparse.ArgumentParser(description="Run an iperf3 throughput test through NPA Publisher paths.")
    parser.add_argument("--clients", type=parse_words, default=DEFAULT_CLIENTS, help="connect profiles for client machines")
    parser.add_argument("--servers", type=parse_words, default=DEFAULT_SERVERS, help="connect profiles for server management")
    parser.add_argument("--targets", type=parse_words, default=DEFAULT_TARGETS, help="iperf3 target IPs or hostnames reached by clients")
    parser.add_argument("--duration", type=int, default=120, help="test duration per lane in seconds")
    parser.add_argument("--parallel", type=int, default=4, help="iperf3 parallel streams per lane")
    parser.add_argument("--interval", type=int, default=0, help="iperf3 report interval; 0 keeps JSON small for connect exec")
    parser.add_argument("--port", type=int, default=5201, help="iperf3 server port")
    parser.add_argument("--progress-interval", type=int, default=10, help="progress print interval while lanes run")
    parser.add_argument("--timeout-padding", type=int, default=60, help="extra seconds before killing a lane")
    parser.add_argument("--connect-timeout-ms", type=int, default=10000, help="iperf3 TCP connect timeout in milliseconds")
    parser.add_argument("--snd-timeout-ms", type=int, default=10000, help="iperf3 send timeout in milliseconds")
    parser.add_argument("--stagger-seconds", type=float, default=2.0, help="delay between starting each lane")
    parser.add_argument("--retries", type=int, default=1, help="retries per lane for transient iperf errors")
    parser.add_argument("--retry-delay", type=float, default=0.0, help="seconds to wait before retrying a lane")
    parser.add_argument("--retry-window", type=int, default=30, help="only retry failures within this many seconds of lane start")
    parser.add_argument("--server-warmup-seconds", type=float, default=3.0, help="wait after starting servers before running clients")
    parser.add_argument("--live-throughput", action="store_true", help="print sampled combined client throughput during the run")
    parser.add_argument("--live-interval", type=float, default=5.0, help="seconds between live throughput samples")
    parser.add_argument("--monitor-interface", default="default", help="client network interface to sample, or 'default' for default-route interface")
    parser.add_argument("--monitor-direction", choices=("auto", "rx", "tx"), default="auto", help="client counter direction for live throughput; auto uses tx normally and rx with --reverse")
    parser.add_argument("--result-dir", default=None, help="local directory for JSON output")
    parser.add_argument("--reverse", action="store_true", help="run iperf3 reverse mode (-R)")
    parser.add_argument("--start-servers", action="store_true", help="start iperf3 servers over connect before running clients")
    parser.add_argument("--restart-servers", action="store_true", help="stop existing iperf3 servers before starting; implies --start-servers")
    args = parser.parse_args()

    lane_count = len(args.clients)
    if len(args.servers) != lane_count or len(args.targets) != lane_count:
        parser.error(
            "--clients, --servers, and --targets must contain the same number of whitespace-separated values "
            f"(got {len(args.clients)}, {len(args.servers)}, {len(args.targets)})"
        )

    result_dir = Path(args.result_dir or f"iperf-results/{datetime.now().strftime('%Y%m%d-%H%M%S')}")
    result_dir.mkdir(parents=True, exist_ok=True)

    print(f"Result directory: {result_dir}")
    print(f"Lanes: {lane_count}")
    print(f"Duration: {args.duration}s")
    print(f"Parallel streams per lane: {args.parallel}")
    print(f"Report interval: {args.interval}s")
    print(f"Port: {args.port}")
    print(f"Reverse mode: {str(args.reverse).lower()}")
    print(f"Targets: {' '.join(args.targets)}")
    print(f"Lane timeout: {args.duration + args.timeout_padding}s")
    print(f"Retries per lane: {args.retries}")
    print(f"Retry window: {args.retry_window}s")
    print(f"Lane start stagger: {args.stagger_seconds}s")
    if args.live_throughput:
        monitor_direction = resolve_monitor_direction(args.monitor_direction, args.reverse)
        print(f"Live throughput interval: {args.live_interval}s")
        print(f"Monitor interface: {args.monitor_interface}")
        print(f"Monitor direction: {monitor_direction}")
    else:
        monitor_direction = resolve_monitor_direction(args.monitor_direction, args.reverse)

    if args.restart_servers:
        args.start_servers = True
    if args.start_servers:
        start_servers(args.servers, args.port, args.restart_servers)
        if args.server_warmup_seconds > 0:
            print(f"Waiting {args.server_warmup_seconds:g}s for server paths to settle")
            time.sleep(args.server_warmup_seconds)

    print()
    print(f"Running {lane_count} iperf3 lane{'s' if lane_count != 1 else ''}")
    lanes = []
    for index, (client, server, target) in enumerate(zip(args.clients, args.servers, args.targets), start=1):
        lane_name = f"lane{index}-{client}-to-{server}"
        lane = {
            "name": lane_name,
            "client": client,
            "server": server,
            "target": target,
            "json_file": result_dir / f"{lane_name}.json",
            "stderr_file": result_dir / f"{lane_name}.stderr",
        }
        start_lane(lane, args, 1)
        lanes.append(lane)
        print(f"  {lane_name} ({target}) attempt 1")
        if index < lane_count and args.stagger_seconds > 0:
            time.sleep(args.stagger_seconds)

    try:
        previous_rx = (
            read_clients_interface_bytes(args.clients, args.monitor_interface, monitor_direction)
            if args.live_throughput
            else {}
        )
        previous_rx_time = time.monotonic()
        next_live_at = previous_rx_time + args.live_interval
        while True:
            sleep_interval = args.progress_interval
            if args.live_throughput:
                sleep_interval = min(sleep_interval, max(0.1, next_live_at - time.monotonic()))
            time.sleep(sleep_interval)
            remaining = 0
            now = time.monotonic()
            if args.live_throughput and now >= next_live_at:
                current_rx = read_clients_interface_bytes(args.clients, args.monitor_interface, monitor_direction)
                sample = live_throughput(previous_rx, current_rx, now - previous_rx_time)
                print(f"  live throughput: {sample['mbps']:.1f} Mbps")
                previous_rx = current_rx
                previous_rx_time = now
                next_live_at = now + args.live_interval

            for lane in lanes:
                if lane["status"] == "retry-wait":
                    continue
                if lane["status"] is not None:
                    continue

                process = lane["process"]
                elapsed = int(time.monotonic() - lane["start"])
                status = process.poll()
                if status is None and elapsed > args.duration + args.timeout_padding:
                    process.kill()
                    status = process.wait()
                    lane["status"] = status
                    lane["error"] = f"timeout after {elapsed}s"
                    print(f"  finished {lane['name']}: timeout after {elapsed}s")
                elif status is None:
                    remaining += 1
                    continue
                else:
                    iperf_error = lane_iperf_error(lane) if status == 0 else None
                    if iperf_error:
                        lane["status"] = 1
                        lane["error"] = iperf_error
                        state = f"iperf error: {iperf_error}"
                    else:
                        lane["status"] = status
                        state = "ok" if status == 0 else f"failed ({status})"
                    print(f"  finished {lane['name']}: {state} after {elapsed}s")

                close_lane_handles(lane)

                if should_retry_lane(
                    status=lane["status"],
                    attempt=lane["attempt"],
                    retries=args.retries,
                    elapsed=elapsed,
                    retry_window=args.retry_window,
                    error=lane.get("error"),
                ):
                    lane["status"] = "retry-wait"
                    lane["retry_at"] = time.monotonic() + args.retry_delay
                    print(f"  retry scheduled {lane['name']} after {args.retry_delay:g}s")

            retry_waiting = [lane for lane in lanes if lane.get("status") == "retry-wait"]
            for lane in retry_waiting:
                if time.monotonic() >= lane["retry_at"]:
                    next_attempt = lane["attempt"] + 1
                    start_lane(lane, args, next_attempt)
                    print(f"  retrying {lane['name']} attempt {next_attempt}")
                    remaining += 1

            running = []
            waiting = []
            now = time.monotonic()
            for lane in lanes:
                if lane["status"] is None:
                    running.append(f"{lane['name']}:{int(now - lane['start'])}s")
                elif lane["status"] == "retry-wait":
                    waiting.append(f"{lane['name']}:{max(0, int(lane['retry_at'] - now))}s")

            if running:
                print(f"  progress: {len(running)}/{len(lanes)} lanes still running ({', '.join(running)})")
            elif waiting:
                print(f"  waiting to retry {len(waiting)} lane(s) ({', '.join(waiting)})")
            else:
                break
    except KeyboardInterrupt:
        print()
        print("Interrupted; stopping local lane processes")
        stop_running_lanes(lanes)
        raise SystemExit(130)

    failed = [lane for lane in lanes if lane["status"] != 0]
    if failed:
        print()
        print("One or more lanes failed:")
        for lane in failed:
            detail = f" error={lane['error']}" if lane.get("error") else ""
            print(f"  {lane['name']}: status={lane['status']}{detail} stderr={lane['stderr_file']}")
        raise SystemExit(1)

    records = []
    for lane in lanes:
        payload = load_json_if_present(lane["json_file"])
        bps = lane_rate_bps(payload)
        records.append({
            "lane": lane["name"],
            "target": lane["target"],
            "bps": bps,
            "mbps": bps / 1_000_000,
            "gbps": bps / 1_000_000_000,
        })

    total_bps = sum(record["bps"] for record in records)
    summary = {
        "lanes": records,
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
