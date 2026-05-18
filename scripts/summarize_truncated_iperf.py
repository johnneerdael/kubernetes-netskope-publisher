#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def matching_brace(text, open_index):
    depth = 0
    in_string = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def extract_sum_intervals(text):
    intervals = []
    cursor = 0
    needle = '"sum"'
    while True:
        key_index = text.find(needle, cursor)
        if key_index == -1:
            return intervals

        open_index = text.find("{", key_index + len(needle))
        if open_index == -1:
            return intervals

        close_index = matching_brace(text, open_index)
        if close_index is None:
            return intervals

        try:
            interval = json.loads(text[open_index : close_index + 1])
        except json.JSONDecodeError:
            cursor = close_index + 1
            continue

        if (
            not interval.get("omitted", False)
            and isinstance(interval.get("start"), (int, float))
            and isinstance(interval.get("end"), (int, float))
            and isinstance(interval.get("bytes"), (int, float))
        ):
            intervals.append(interval)

        cursor = close_index + 1


def end_rates(payload):
    end = payload.get("end", {})
    receiver_bps = end.get("sum_received", {}).get("bits_per_second")
    sender_bps = end.get("sum_sent", {}).get("bits_per_second")
    sum_bps = end.get("sum", {}).get("bits_per_second")

    receiver_bps = float(receiver_bps) if receiver_bps is not None else None
    sender_bps = float(sender_bps) if sender_bps is not None else None
    sum_bps = float(sum_bps) if sum_bps is not None else None

    best_available_bps = None
    best_available_source = None
    if receiver_bps and receiver_bps > 0:
        best_available_bps = receiver_bps
        best_available_source = "receiver"
    elif sum_bps and sum_bps > 0:
        best_available_bps = sum_bps
        best_available_source = "sum"
    elif sender_bps and sender_bps > 0:
        best_available_bps = sender_bps
        best_available_source = "sender"

    return {
        "receiver_bps": receiver_bps,
        "sender_bps": sender_bps,
        "sum_bps": sum_bps,
        "best_available_bps": best_available_bps,
        "best_available_source": best_available_source,
    }


def end_rate(payload):
    return end_rates(payload)["best_available_bps"]


def peak_combined_interval_rate(lanes):
    buckets = {}
    for lane in lanes:
        for interval in lane.get("intervals", []):
            start = float(interval["start"])
            end = float(interval["end"])
            seconds = end - start
            if seconds <= 0:
                continue
            key = round(start, 3)
            bucket = buckets.setdefault(
                key,
                {
                    "bucket": None,
                    "start": start,
                    "end": end,
                    "bytes": 0,
                    "lanes": [],
                },
            )
            bucket["start"] = min(bucket["start"], start)
            bucket["end"] = max(bucket["end"], end)
            bucket["bytes"] += int(interval["bytes"])
            bucket["lanes"].append({
                "file": lane["file"],
                "bytes": int(interval["bytes"]),
                "bps": int(interval["bytes"]) * 8 / seconds,
            })

    if not buckets:
        return None

    for bucket in buckets.values():
        bucket["seconds"] = bucket["end"] - bucket["start"]
        bucket["bucket"] = f"{bucket['start']:.3f}-{bucket['end']:.3f}"
        bucket["bps"] = bucket["bytes"] * 8 / bucket["seconds"]
        bucket["mbps"] = bucket["bps"] / 1_000_000
        bucket["gbps"] = bucket["bps"] / 1_000_000_000
    return max(buckets.values(), key=lambda item: item["bps"])


def summarize_file(path):
    text = path.read_text(errors="replace")
    result = {
        "file": path.name,
        "bytes_captured": path.stat().st_size,
        "complete_json": False,
        "samples": 0,
        "covered_seconds": 0.0,
        "total_bytes": 0,
        "bps": None,
        "mbps": None,
        "gbps": None,
        "receiver_bps": None,
        "sender_bps": None,
        "best_available_bps": None,
        "best_available_source": None,
        "intervals": [],
    }

    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        result["json_error"] = str(exc)
        intervals = extract_sum_intervals(text)
    else:
        result["complete_json"] = True
        if payload.get("error"):
            result["iperf_error"] = payload["error"]
        rates = end_rates(payload)
        result.update(rates)
        if rates["best_available_bps"] is not None:
            result["bps"] = rates["best_available_bps"]
            result["mbps"] = result["bps"] / 1_000_000
            result["gbps"] = result["bps"] / 1_000_000_000
        intervals = [
            interval.get("sum", {})
            for interval in payload.get("intervals", [])
            if isinstance(interval.get("sum"), dict) and not interval.get("sum", {}).get("omitted", False)
        ]

    if intervals:
        start = min(interval["start"] for interval in intervals)
        end = max(interval["end"] for interval in intervals)
        covered_seconds = end - start
        total_bytes = sum(interval["bytes"] for interval in intervals)
        result["samples"] = len(intervals)
        result["covered_seconds"] = covered_seconds
        result["total_bytes"] = total_bytes
        result["intervals"] = intervals
        if covered_seconds > 0 and result["bps"] is None:
            result["bps"] = total_bytes * 8 / covered_seconds
            result["mbps"] = result["bps"] / 1_000_000
            result["gbps"] = result["bps"] / 1_000_000_000
            result["best_available_bps"] = result["bps"]
            result["best_available_source"] = "intervals"

    return result


def main():
    parser = argparse.ArgumentParser(description="Recover approximate throughput from complete iperf interval blocks.")
    parser.add_argument("result_dir", type=Path, help="directory containing lane*.json iperf output files")
    parser.add_argument("--output", type=Path, default=None, help="write summary JSON to this path")
    args = parser.parse_args()

    files = sorted(args.result_dir.glob("lane*.json"))
    if not files:
        raise SystemExit(f"no lane*.json files found in {args.result_dir}")

    lanes = [summarize_file(path) for path in files]
    receiver_lanes = [lane for lane in lanes if lane["receiver_bps"] is not None and lane["receiver_bps"] > 0]
    sender_lanes = [lane for lane in lanes if lane["sender_bps"] is not None and lane["sender_bps"] > 0]
    usable = [lane for lane in lanes if lane["best_available_bps"] is not None]
    total_receiver_bps = sum(lane["receiver_bps"] for lane in receiver_lanes)
    total_sender_bps = sum(lane["sender_bps"] for lane in sender_lanes)
    total_bps = sum(lane["best_available_bps"] for lane in usable)
    peak = peak_combined_interval_rate(lanes)
    summary = {
        "result_dir": str(args.result_dir),
        "note": "Truncated files are estimated from complete per-interval sum blocks only.",
        "lanes": lanes,
        "peak_combined_interval": peak,
        "total_receiver_bps": total_receiver_bps,
        "total_receiver_mbps": total_receiver_bps / 1_000_000,
        "total_receiver_gbps": total_receiver_bps / 1_000_000_000,
        "total_sender_bps": total_sender_bps,
        "total_sender_mbps": total_sender_bps / 1_000_000,
        "total_sender_gbps": total_sender_bps / 1_000_000_000,
        "total_bps": total_bps,
        "total_mbps": total_bps / 1_000_000,
        "total_gbps": total_bps / 1_000_000_000,
        "usable_lanes": len(usable),
        "lane_files": len(lanes),
    }

    output = args.output or args.result_dir / "salvaged-summary.json"
    output.write_text(json.dumps(summary, indent=2) + "\n")

    print(f"Recovered {len(usable)}/{len(lanes)} lanes")
    for lane in lanes:
        if lane["best_available_bps"] is None:
            error = lane.get("iperf_error") or lane.get("json_error") or "no usable rate"
            print(f"  {lane['file']}: no throughput ({error})")
            continue
        completeness = "complete" if lane["complete_json"] else "partial"
        print(
            f"  {lane['file']}: {lane['mbps']:.1f} Mbps "
            f"over {lane['covered_seconds']:.1f}s ({completeness}, {lane['samples']} samples, "
            f"{lane['best_available_source']})"
        )
    if peak:
        print(f"Peak interval throughput: {peak['mbps']:.1f} Mbps ({peak['bucket']})")
    print(f"Total receiver-confirmed throughput: {summary['total_receiver_mbps']:.1f} Mbps")
    print(f"Total sender-side throughput: {summary['total_sender_mbps']:.1f} Mbps")
    print(f"Total best-available throughput: {summary['total_mbps']:.1f} Mbps")
    print(f"Summary written to {output}")


if __name__ == "__main__":
    main()
