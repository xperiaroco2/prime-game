"""`perf` (#187): its arguments, the report it makes from the harness's raw samples, the comparison with a baseline
(a report, never a failure) and the run it starts. The match itself is tested by tests/scenarios/perf_run_test.gd."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, perf, verify
from runner.common import ROOT, Failure


def raw(**changes: object) -> dict:
    """perf_main.gd's file for two remote peers over two seconds of host time (20 ticks a second)."""
    data = {
        "transport": "loopback",
        "bots": 3,
        "seconds": 20,
        "seed": 187000000001,
        "ticks_per_second": 20,
        "frames": 120,
        "host_ticks": 40,
        "tick_usec": [100, 200, 300, 400, 1000],
        "physics_usec": [5000, 7000],
        "events_per_tick": [3, 0, 0, 1],
        "memory_static": {"end": 900, "max": 1000},
        "budgets": {
            "snapshot_payload_cap": 1024,
            "voice_down_payload_cap": 510,
            "frame_header_bytes": 3,
            "peer_bytes_per_second": 16384.0,
            "peer_voice_frames_per_second": 50.0,
        },
        # Peer 2 gets traffic in seconds 0 and 1, peer 3 in seconds 0 and 2 (second 1 empty).
        "down": {"2": {"0": 100, "19": 50, "20": 300}, "3": {"5": 200, "45": 400}},
        "down_voice": {"2": {"0": 13}, "3": {"5": 13}},
        "snapshots": {"2": {"0": 97, "20": 297}, "3": {"5": 197, "45": 397}},
        "up": {"2": {"1": 30}, "3": {"2": 40, "3": 40}},
        "up_voice_frames": {"2": {"1": 1, "2": 1}, "3": {"2": 1}},
        "failures": [],
        "ends": ["dissidents"],
    }
    data.update(changes)
    return data


def report(**changes: object) -> dict:
    return perf.summarize(raw(**changes), date="2026-10-02", commit="abc123")


class ArgsTest(unittest.TestCase):
    def test_the_entry_script_exists(self) -> None:
        self.assertTrue((ROOT / perf.TARGET).is_file())

    def test_bots_and_seconds_stay_in_range(self) -> None:
        perf.check_args(10, 60)
        perf.check_args(2, 20)
        for bots, seconds in ((1, 60), (11, 60), (10, 19), (10, 601)):
            with self.subTest(bots=bots, seconds=seconds), self.assertRaises(Failure):
                perf.check_args(bots, seconds)

    def test_user_args(self) -> None:
        out = Path("D:/x/raw.json")
        self.assertEqual(perf.user_args(10, 60, out), ["--bots=10", "--seconds=60", "--out=D:/x/raw.json"])
        self.assertEqual(perf.user_args(4, 30, out, 24000)[-2:], ["--enet", "--port=24000"])

    def test_the_command_line_reaches_main(self) -> None:
        args = cli.build_parser().parse_args(["perf"])
        self.assertEqual((args.bots, args.seconds, args.enet, args.baseline), (10, 60, False, None))
        args = cli.build_parser().parse_args(["perf", "--bots", "4", "--seconds", "30", "--enet", "--baseline", "b"])
        self.assertEqual((args.bots, args.seconds, args.enet, args.baseline), (4, 30, True, "b"))
        with mock.patch.object(perf, "main", return_value=0) as main:
            self.assertEqual(cli.main(["perf", "--bots", "4"]), 0)
        main.assert_called_once_with(bots=4, seconds=60, enet=False, baseline=None)


class ReportTest(unittest.TestCase):
    def test_percentiles_are_nearest_rank(self) -> None:
        values = list(range(1, 101))
        self.assertEqual(perf.percentile(values, 0.5), 50)
        self.assertEqual(perf.percentile(values, 0.95), 95)
        self.assertEqual(perf.percentile([7], 0.95), 7)
        self.assertEqual(perf.percentile([], 0.5), 0)
        self.assertEqual(perf.stats([3, 1, 2]), {"p50": 2, "p95": 3, "max": 3})
        self.assertEqual(perf.stats([]), {"p50": 0, "p95": 0, "max": 0})

    def test_per_second_sums_ticks_and_keeps_empty_seconds_between(self) -> None:
        self.assertEqual(perf.per_second({"0": 1, "19": 2, "20": 4}, 20), [3, 4])
        self.assertEqual(perf.per_second({"5": 1, "45": 1}, 20), [1, 0, 1])
        self.assertEqual(perf.per_second({"5": 1, "6": 1}, 20, extra=3), [8])
        self.assertEqual(perf.per_second({}, 20), [])

    def test_the_report_has_every_metric_and_the_budgets_headroom(self) -> None:
        got = report()
        m = got["metrics"]
        self.assertEqual(m["host_tick_usec"], {"p50": 300, "p95": 1000, "max": 1000})
        self.assertEqual(m["physics_process_usec"]["max"], 7000)
        self.assertEqual(m["events_per_tick"], {"p50": 0, "p95": 3, "max": 3, "mean": 1.0})
        self.assertEqual(m["snapshot_payload_bytes"], {"p50": 197, "p95": 397, "max": 397})
        # Per peer per second: peer 2 [150, 300], peer 3 [200, 0, 400].
        self.assertEqual(m["down_bytes_per_second"], {"p50": 200, "p95": 400, "max": 400})
        # Snapshots with their 3-byte header: peer 2 [100, 300], peer 3 [200, 0, 400].
        self.assertEqual(m["down_snapshot_bytes_per_second"]["max"], 400)
        self.assertEqual(m["up_bytes_per_second"], {"p50": 30, "p95": 80, "max": 80})
        self.assertEqual(m["up_voice_frames_per_second"]["max"], 2)
        self.assertEqual(m["memory_static_bytes"], {"end": 900, "max": 1000})
        self.assertEqual((got["remote_peers"], got["host_ticks"], got["commit"]), (2, 40, "abc123"))
        budgets = got["budgets"]
        self.assertEqual(budgets["snapshot_payload"], {"max": 397, "limit": 1024, "headroom": 0.612})
        self.assertEqual(budgets["up_bytes_per_second"]["limit"], 16384.0)
        self.assertEqual(budgets["up_voice_frames_per_second"]["headroom"], 0.96)

    def test_the_summary_names_the_wire_budgets_next_to_the_numbers(self) -> None:
        got = report()
        got["comparison"] = perf.compare(got, None)
        text = "\n".join(perf.lines(got))
        for part in ("cap 1024 B", "E16", "E7 budget 16384 B/s", "E7 budget 50/s", "E11", "headroom 61%"):
            self.assertIn(part, text)
        self.assertIn("compared: no baseline", text)


class CompareTest(unittest.TestCase):
    def test_no_baseline_and_a_different_run_compare_nothing(self) -> None:
        self.assertEqual(perf.compare(report(), None)["changes"], [])
        for key, value in (("bots", 10), ("seconds", 60), ("transport", "enet")):
            with self.subTest(key=key):
                other = perf.compare(report(), report(**{key: value}), name="b.json")
                self.assertEqual(other["changes"], [])
                self.assertIn(key, other["note"])

    def test_changes_beyond_the_threshold_are_listed_both_ways_and_small_ones_are_not(self) -> None:
        base = report()
        now = report(tick_usec=[100, 200, 300, 400, 1300], physics_usec=[5000, 5000])
        now["metrics"]["memory_static_bytes"]["end"] = 950  # +5.6%: within the threshold
        result = perf.compare(now, base, 0.20, "base.json")
        moved = {change["metric"]: change["change"] for change in result["changes"]}
        self.assertEqual(
            moved,
            {
                "host_tick_usec.p95": 0.3,
                "host_tick_usec.max": 0.3,
                "physics_process_usec.p95": -0.286,
                "physics_process_usec.max": -0.286,
            },
        )
        self.assertEqual((result["baseline"], result["threshold"]), ("base.json", 0.20))
        self.assertNotIn("note", result)
        text = "\n".join(perf.lines({**now, "comparison": result}))
        self.assertIn("4 change(s) beyond 20%", text)
        self.assertIn("host_tick_usec.max: 1000 -> 1300 (+30%)", text)

    def test_a_metric_that_was_zero_is_reported_from_zero(self) -> None:
        base = report(events_per_tick=[0, 0])
        now = report(events_per_tick=[0, 2])
        changes = perf.compare(now, base)["changes"]
        self.assertIn({"metric": "events_per_tick.max", "baseline": 0, "now": 2, "change": None}, changes)
        self.assertIn("(from 0)", "\n".join(perf.lines({**now, "comparison": {"baseline": "b", "changes": changes}})))


class BaselineTest(unittest.TestCase):
    def test_explicit_then_baseline_json_then_the_newest_report_of_the_transport(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertIsNone(perf.find_baseline(None, "loopback", folder))
            for name in ("2026-09-30.json", "2026-10-01.json", "2026-10-02-enet.json", "summary.json"):
                (folder / name).write_text("{}", encoding="utf-8")
            self.assertEqual(perf.find_baseline(None, "loopback", folder), folder / "2026-10-01.json")
            self.assertEqual(perf.find_baseline(None, "enet", folder), folder / "2026-10-02-enet.json")
            (folder / "baseline.json").write_text("{}", encoding="utf-8")
            self.assertEqual(perf.find_baseline(None, "loopback", folder), folder / "baseline.json")
            explicit = folder / "2026-09-30.json"
            self.assertEqual(perf.find_baseline(explicit, "loopback", folder), explicit)
            with self.assertRaises(Failure):
                perf.find_baseline(folder / "missing.json", "loopback", folder)

    def test_a_run_of_another_setup_is_not_the_baseline_of_the_default_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            for name in ("2026-10-01.json", "2026-10-02-4b20s.json", "2026-10-02-enet-4b20s.json"):
                (folder / name).write_text("{}", encoding="utf-8")
            self.assertEqual(perf.find_baseline(None, "loopback", folder), folder / "2026-10-01.json")
            self.assertEqual(perf.find_baseline(None, "loopback", folder, 4, 20), folder / "2026-10-02-4b20s.json")
            self.assertEqual(perf.find_baseline(None, "enet", folder, 4, 20), folder / "2026-10-02-enet-4b20s.json")
            self.assertIsNone(perf.find_baseline(None, "enet", folder))
            self.assertIsNone(perf.find_baseline(None, "loopback", folder, 10, 20))

    def test_report_names(self) -> None:
        self.assertEqual(perf.report_name("2026-10-02", "loopback"), "2026-10-02.json")
        self.assertEqual(perf.report_name("2026-10-02", "enet"), "2026-10-02-enet.json")
        self.assertEqual(perf.report_name("2026-10-02", "loopback", 4, 20), "2026-10-02-4b20s.json")
        self.assertEqual(perf.report_name("2026-10-02", "enet", 10, 30), "2026-10-02-enet-10b30s.json")


class RunTest(unittest.TestCase):
    # A fixed date: two runs straddling midnight UTC would otherwise write two reports.
    date = "2026-10-02"

    def run_main(self, folder: Path, code: int, written: dict | None, **kwargs: object) -> tuple[int, list]:
        def fake_launch(target: str, **options: object) -> int:
            out = [arg for arg in options["user_args"] if arg.startswith("--out=")][0].removeprefix("--out=")
            if written is not None:
                Path(out).write_text(json.dumps(written), encoding="utf-8")
            return code

        with (
            mock.patch.object(perf, "PERF_OUT", folder),
            mock.patch.object(perf, "RAW_DIR", folder / "raw"),
            mock.patch.object(perf, "SUMMARY", folder / "summary.md"),
            mock.patch.object(perf, "ROOT", folder),
            mock.patch.object(perf, "rel", lambda path: path.relative_to(folder).as_posix()),
            mock.patch.object(perf.launch, "main", side_effect=fake_launch) as launched,
            mock.patch.object(verify, "free_udp_port", return_value=24242),
            mock.patch.object(perf, "say"),
            mock.patch.object(perf, "today", return_value=self.date),
        ):
            return perf.main(**kwargs), launched.call_args_list  # type: ignore[arg-type]

    def test_a_loopback_run_writes_the_report_and_the_summary_and_compares_with_the_last(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            code, calls = self.run_main(folder, 0, raw(bots=10, seconds=60), bots=10, seconds=60)
            self.assertEqual(code, 0)
            options = calls[0].kwargs
            self.assertEqual(options["engine_args"], ["--fixed-fps", "60"])
            self.assertEqual(options["seconds"], 60 + perf.TIMEOUT_MARGIN_SECONDS)
            self.assertTrue(options["headless"])
            reports = sorted(folder.glob("*.json"))
            self.assertEqual([path.name for path in reports], ["2026-10-02.json"])
            first = json.loads(reports[0].read_text(encoding="utf-8"))
            self.assertEqual(first["comparison"]["note"], "no baseline: nothing compared")
            self.assertIn("host_tick_usec", (folder / "summary.md").read_text(encoding="utf-8"))
            # A run of another setup the same day keeps the default report and compares with nothing.
            short = raw(bots=4, seconds=20)
            self.assertEqual(self.run_main(folder, 0, short, bots=4, seconds=20)[0], 0)
            other = json.loads((folder / "2026-10-02-4b20s.json").read_text(encoding="utf-8"))
            self.assertEqual(other["comparison"]["note"], "no baseline: nothing compared")
            self.assertEqual(json.loads(reports[0].read_text(encoding="utf-8")), first)
            # A second default run the same day compares with the first, and a change never fails it.
            slower = raw(bots=10, seconds=60, tick_usec=[1000, 2000, 3000, 4000, 10000])
            code, _ = self.run_main(folder, 0, slower, bots=10, seconds=60)
            self.assertEqual(code, 0)
            second = json.loads(reports[0].read_text(encoding="utf-8"))
            self.assertEqual(second["comparison"]["baseline"], reports[0].name)
            self.assertTrue(second["comparison"]["changes"])

    def test_enet_runs_on_a_free_port_on_the_real_clock(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            code, calls = self.run_main(folder, 0, raw(transport="enet"), enet=True, bots=3, seconds=20)
            self.assertEqual(code, 0)
            self.assertIsNone(calls[0].kwargs["engine_args"])
            self.assertIn("--port=24242", calls[0].kwargs["user_args"])
            self.assertTrue((folder / "2026-10-02-enet-3b20s.json").is_file())

    def test_a_failed_match_fails_and_writes_no_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertEqual(self.run_main(folder, 1, raw(failures=["bot 2 ..."]))[0], 1)
            self.assertEqual(self.run_main(folder, 0, None)[0], 1)
            self.assertEqual(list(folder.glob("*.json")), [])


if __name__ == "__main__":
    unittest.main()
