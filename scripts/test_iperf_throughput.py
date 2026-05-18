#!/usr/bin/env python3
import subprocess
import unittest
from pathlib import Path

import run_iperf4_throughput
import run_curl4_throughput
import summarize_truncated_iperf


SCRIPT_DIR = Path(__file__).resolve().parent


class IperfThroughputScriptsTest(unittest.TestCase):
    def test_parse_words_accepts_single_lane_values(self):
        self.assertEqual(run_iperf4_throughput.parse_words("client1"), ["client1"])

    def test_single_lane_wrapper_exposes_expected_defaults(self):
        result = subprocess.run(
            [str(SCRIPT_DIR / "run-iperf1-throughput.sh"), "--help"],
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("client1", result.stdout)
        self.assertIn("downloadserver1", result.stdout)
        self.assertIn("172.31.43.126", result.stdout)

    def test_retries_early_connect_timeout(self):
        self.assertTrue(
            run_iperf4_throughput.should_retry_lane(
                status=1,
                attempt=1,
                retries=1,
                elapsed=14,
                retry_window=30,
                error="unable to connect to server: Connection timed out",
            )
        )

    def test_does_not_retry_late_broken_pipe(self):
        self.assertFalse(
            run_iperf4_throughput.should_retry_lane(
                status=1,
                attempt=1,
                retries=1,
                elapsed=142,
                retry_window=30,
                error="unable to send control message: Broken pipe",
            )
        )

    def test_iperf_lane_rates_prefer_receiver_but_keep_sender_fallback(self):
        payload = {
            "end": {
                "sum_received": {"bits_per_second": 0, "bytes": 0, "seconds": 120},
                "sum_sent": {"bits_per_second": 64000000, "bytes": 960000000, "seconds": 120},
            }
        }

        rates = summarize_truncated_iperf.end_rates(payload)

        self.assertEqual(rates["receiver_bps"], 0)
        self.assertEqual(rates["sender_bps"], 64000000)
        self.assertEqual(rates["best_available_bps"], 64000000)
        self.assertEqual(rates["best_available_source"], "sender")

    def test_iperf_interval_peak_combines_by_time_bucket(self):
        lanes = [
            {"file": "lane1.json", "intervals": [{"start": 0, "end": 5.1, "bytes": 100}]},
            {"file": "lane2.json", "intervals": [{"start": 0, "end": 5.2, "bytes": 150}]},
            {"file": "lane1.json", "intervals": [{"start": 5, "end": 10, "bytes": 200}]},
        ]

        peak = summarize_truncated_iperf.peak_combined_interval_rate(lanes)

        self.assertEqual(peak["bucket"], "0.000-5.200")
        self.assertEqual(peak["bytes"], 250)
        self.assertAlmostEqual(peak["bps"], 384.6153846153846)

    def test_format_live_throughput(self):
        previous = {"client1": 100, "client2": 200}
        current = {"client1": 1100, "client2": 2200}

        result = run_iperf4_throughput.live_throughput(previous, current, seconds=2)

        self.assertEqual(result["bps"], 12000)

    def test_monitor_direction_defaults_to_tx_for_normal_iperf(self):
        self.assertEqual(run_iperf4_throughput.resolve_monitor_direction("auto", reverse=False), "tx")

    def test_monitor_direction_defaults_to_rx_for_reverse_iperf(self):
        self.assertEqual(run_iperf4_throughput.resolve_monitor_direction("auto", reverse=True), "rx")

    def test_interface_counter_field(self):
        self.assertEqual(run_iperf4_throughput.interface_counter_field("rx"), 3)
        self.assertEqual(run_iperf4_throughput.interface_counter_field("tx"), 11)

    def test_parse_curl_writeout(self):
        result = run_curl4_throughput.parse_curl_writeout(
            "speed_download=12500000\n"
            "time_total=10.5\n"
            "size_download=131250000\n"
            "http_code=200\n"
        )

        self.assertEqual(result["speed_download"], 12500000)
        self.assertEqual(result["time_total"], 10.5)
        self.assertEqual(result["size_download"], 131250000)
        self.assertEqual(result["http_code"], 200)

    def test_curl_connect_timeout_with_no_bytes_is_failure(self):
        self.assertFalse(run_curl4_throughput.is_successful_curl_result(status=28, bytes_downloaded=0))

    def test_curl_max_time_with_bytes_is_usable_sample(self):
        self.assertTrue(run_curl4_throughput.is_successful_curl_result(status=28, bytes_downloaded=1024))

    def test_aggregate_lane_records_sums_parallel_streams(self):
        records = [
            {"lane": "lane1-client1-to-downloadserver1", "bps": 100, "bytes": 10},
            {"lane": "lane1-client1-to-downloadserver1", "bps": 200, "bytes": 20},
            {"lane": "lane2-client2-to-downloadserver2", "bps": 300, "bytes": 30},
        ]

        aggregated = run_curl4_throughput.aggregate_lane_records(records)

        self.assertEqual(aggregated[0]["lane"], "lane1-client1-to-downloadserver1")
        self.assertEqual(aggregated[0]["streams"], 2)
        self.assertEqual(aggregated[0]["bps"], 300)
        self.assertEqual(aggregated[0]["bytes"], 30)
        self.assertEqual(aggregated[1]["streams"], 1)

    def test_nginx_backend_command_is_preferred(self):
        command = run_curl4_throughput.http_server_command("nginx", 8080, "/tmp/npa-throughput.bin")

        self.assertIn("nginx", command)
        self.assertIn("sendfile on", command)
        self.assertIn("python3 -m http.server", command)

    def test_parse_network_samples(self):
        samples = run_curl4_throughput.parse_network_samples("100 1000\n101 3000\nbad\n102 4500\n")

        self.assertEqual(samples, [(100.0, 1000), (101.0, 3000), (102.0, 4500)])

    def test_network_rates_from_samples(self):
        rates = run_curl4_throughput.network_rates_from_samples("client1", [(100.0, 1000), (101.0, 3000), (102.0, 4500)])

        self.assertEqual(rates[0]["client"], "client1")
        self.assertEqual(rates[0]["bps"], 16000)
        self.assertEqual(rates[1]["bps"], 12000)

    def test_peak_combined_network_rate(self):
        rates = [
            {"client": "client1", "sample": 1, "timestamp": 100.1, "seconds": 0.5, "bytes": 100},
            {"client": "client2", "sample": 1, "timestamp": 100.6, "seconds": 0.5, "bytes": 200},
            {"client": "client1", "sample": 2, "timestamp": 101.1, "seconds": 0.5, "bytes": 500},
            {"client": "client2", "sample": 2, "timestamp": 101.6, "seconds": 0.5, "bytes": 300},
        ]

        peak = run_curl4_throughput.peak_combined_network_rate(rates, bucket_seconds=1.0)

        self.assertEqual(peak["bucket"], 101)
        self.assertEqual(peak["bytes"], 800)
        self.assertEqual(peak["bps"], 6400)

    def test_peak_combined_network_rate_does_not_group_by_sample_index(self):
        rates = [
            {"client": "client1", "sample": 1, "timestamp": 100.1, "seconds": 0.5, "bytes": 100},
            {"client": "client2", "sample": 1, "timestamp": 105.1, "seconds": 0.5, "bytes": 900},
        ]

        peak = run_curl4_throughput.peak_combined_network_rate(rates, bucket_seconds=1.0)

        self.assertEqual(peak["bytes"], 900)
        self.assertEqual(peak["bps"], 7200)

    def test_peak_combined_network_rate_does_not_sum_sample_bps(self):
        rates = [
            {"client": "client1", "sample": 1, "timestamp": 100.1, "seconds": 0.5, "bytes": 100, "bps": 1600},
            {"client": "client1", "sample": 2, "timestamp": 100.6, "seconds": 0.5, "bytes": 100, "bps": 1600},
        ]

        peak = run_curl4_throughput.peak_combined_network_rate(rates, bucket_seconds=1.0)

        self.assertEqual(peak["bytes"], 200)
        self.assertEqual(peak["bps"], 1600)

    def test_curl_wrapper_help_exposes_defaults(self):
        result = subprocess.run(
            [str(SCRIPT_DIR / "run-curl4-throughput.sh"), "--help"],
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("curl download throughput", result.stdout)
        self.assertIn("172.31.43.126", result.stdout)
        self.assertIn("--parallel", result.stdout)
        self.assertIn("--server-backend", result.stdout)
        self.assertIn("--setup-only", result.stdout)

    def test_curl_setup_wrapper_help_exposes_setup_only(self):
        result = subprocess.run(
            [str(SCRIPT_DIR / "setup-curl-downloadservers.sh"), "--help"],
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("--setup-only", result.stdout)
        self.assertIn("172.31.43.126", result.stdout)


if __name__ == "__main__":
    unittest.main()
