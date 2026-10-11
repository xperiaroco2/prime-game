"""`test --repeat N` (the nightly flaky-test job, docs/AGENT_WORKFLOW.md "Night jobs"): per-run reports kept, a
per-suite and per-test comparison, and any failed run failing the command."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

from runner import cli, common, gdunit

PASS, FAIL, SKIP = "", '<failure message="Expecting: 1 but was 2" type="FAILURE">line 3</failure>', "<skipped/>"


def results_xml(cases: dict[str, dict[str, str]]) -> str:
    """A GdUnit4-shaped results.xml: {"<package>/<suite>": {"<test>": PASS | FAIL | SKIP}}."""
    suites = []
    for index, (suite, tests) in enumerate(cases.items()):
        package, name = suite.rsplit("/", 1)
        body = "".join(f'<testcase name="{t}" classname="{name}" time="0.001">{v}</testcase>' for t, v in tests.items())
        suites.append(f'<testsuite id="{index}" name="{name}" package="{package}" tests="{len(tests)}">{body}</testsuite>')
    return f'<?xml version="1.0" encoding="UTF-8" ?><testsuites name="report_1">{"".join(suites)}</testsuites>'


def outcome(run: int, cases: dict[str, str], status: str = "passed") -> gdunit.RunOutcome:
    return gdunit.RunOutcome(run, status, "all tests passed", dict(cases))


class CaseResultsTest(unittest.TestCase):
    def test_each_case_is_keyed_by_package_suite_and_name(self) -> None:
        xml = results_xml({"tests/unit/a_test": {"test_ok": PASS, "test_bad": FAIL}, "tests/unit/b_test": {"test_s": SKIP}})
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "results.xml"
            path.write_text(xml, encoding="utf-8")
            cases = gdunit.case_results(path)
        self.assertEqual(
            cases,
            {
                "tests/unit/a_test::test_ok": "passed",
                "tests/unit/a_test::test_bad": "failed",
                "tests/unit/b_test::test_s": "skipped",
            },
        )


class SummarizeTest(unittest.TestCase):
    A, B, C = "tests/unit/a_test::test_1", "tests/unit/a_test::test_2", "tests/net/b_test::test_3"

    def test_a_test_that_passed_once_and_failed_once_is_flaky(self) -> None:
        summary = gdunit.summarize(
            [
                outcome(1, {self.A: "passed", self.B: "failed", self.C: "passed"}, "FAILED"),
                outcome(2, {self.A: "failed", self.B: "failed", self.C: "passed"}, "FAILED"),
                outcome(3, {self.A: "passed", self.B: "failed", self.C: "passed"}, "FAILED"),
            ]
        )
        self.assertEqual(summary["flaky"], [{"test": self.A, "failed_in_runs": [2]}])
        self.assertEqual(summary["failed_every_run"], [self.B])
        self.assertEqual(
            summary["suites"],
            [
                {"suite": "tests/net/b_test", "tests": 1, "failed_per_run": [0, 0, 0]},
                {"suite": "tests/unit/a_test", "tests": 2, "failed_per_run": [1, 2, 1]},
            ],
        )
        self.assertEqual([r["failed"] for r in summary["runs"]], [[self.B], [self.A, self.B], [self.B]])  # type: ignore[index, union-attr]

    def test_a_run_without_results_counts_neither_way(self) -> None:
        summary = gdunit.summarize(
            [
                outcome(1, {self.A: "passed"}),
                gdunit.RunOutcome(2, "FAILED", "timed out after 600s"),
                outcome(3, {self.A: "passed"}),
            ]
        )
        self.assertEqual(summary["flaky"], [])
        self.assertEqual(summary["failed_every_run"], [])
        self.assertEqual([r["status"] for r in summary["runs"]], ["passed", "FAILED", "passed"])  # type: ignore[index, union-attr]
        self.assertEqual([r["tests"] for r in summary["runs"]], [1, 0, 1])  # type: ignore[index, union-attr]

    def test_a_skipped_run_counts_neither_way(self) -> None:
        summary = gdunit.summarize(
            [
                outcome(1, {self.A: "failed", self.B: "skipped"}, "FAILED"),
                outcome(2, {self.A: "skipped", self.B: "passed"}),
                outcome(3, {self.A: "failed", self.B: "failed"}, "FAILED"),
            ]
        )
        self.assertEqual(summary["failed_every_run"], [self.A])
        self.assertEqual(summary["flaky"], [{"test": self.B, "failed_in_runs": [3]}])

    def test_the_markdown_lists_flaky_tests_and_only_the_suites_with_a_failure(self) -> None:
        text = gdunit.summary_markdown(
            gdunit.summarize(
                [outcome(1, {self.A: "passed", self.C: "passed"}), outcome(2, {self.A: "failed", self.C: "passed"}, "FAILED")]
            )
        )
        self.assertIn("## GdUnit4, 2 runs", text)
        self.assertIn(f"- `{self.A}`: failed in run(s) 2", text)
        self.assertIn("### Suites with a failure (1 of 2)", text)
        self.assertIn("| `tests/unit/a_test` | 1 | 0 | 1 |", text)
        self.assertNotIn("tests/net/b_test", text)

    def test_a_clean_night_says_none(self) -> None:
        text = gdunit.summary_markdown(gdunit.summarize([outcome(1, {self.A: "passed"}), outcome(2, {self.A: "passed"})]))
        self.assertIn("### Suites with a failure (0 of 1)", text)
        self.assertEqual(text.count("None."), 3)


class RepeatTest(unittest.TestCase):
    """repeat() with Godot replaced by a stub that writes each run's results.xml as GdUnit4 would."""

    def run_repeat(
        self, runs: list[tuple[int, str, bool]], count: int, **kwargs: Any
    ) -> tuple[int, Path, list[str], str]:
        calls: list[str] = []
        self.args: list[list[str]] = []
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "tests" / "unit").mkdir(parents=True)
            report_dir = root / "tools" / "out" / "gdunit"
            runs_dir = root / "tools" / "out" / "gdunit-runs"

            def fake_godot(args: list[str], *, timeout: float, log: str, echo: bool = False) -> common.Result:
                rc, xml, timed_out = runs[len(calls)]
                calls.append(log)
                self.args.append(args)
                if xml:
                    (report_dir / "report_1").mkdir(parents=True)
                    (report_dir / "report_1" / "results.xml").write_text(xml, encoding="utf-8")
                return common.Result(rc, "", timed_out, 1.0)

            out = io.StringIO()
            with (
                mock.patch.object(gdunit, "ROOT", root),
                mock.patch.object(gdunit, "REPORT_DIR", report_dir),
                mock.patch.object(gdunit, "RUNS_DIR", runs_dir),
                mock.patch.object(gdunit, "ensure_out", return_value=root / "tools" / "out"),
                mock.patch.object(gdunit, "godot", fake_godot),
                contextlib.redirect_stdout(out),
                contextlib.redirect_stderr(out),
            ):
                rc = gdunit.repeat(count, run_import=False, **{"shards": 1, **kwargs})
            kept = sorted(p.relative_to(runs_dir).as_posix() for p in runs_dir.rglob("*") if p.is_file())
            summary = json.loads((runs_dir / "summary.json").read_text(encoding="utf-8"))
            self.assertTrue((runs_dir / "summary.md").is_file())
        self.assertEqual(calls, [f"test-run{i}" for i in range(1, count + 1)])
        self.summary = summary
        return rc, runs_dir, kept, out.getvalue()

    def test_three_green_runs_pass_and_keep_each_report(self) -> None:
        xml = results_xml({"tests/unit/a_test": {"test_ok": PASS}})
        rc, _, kept, _ = self.run_repeat([(0, xml, False)] * 3, 3)
        self.assertEqual(rc, 0)
        self.assertEqual(
            kept,
            ["run-1/report_1/results.xml", "run-2/report_1/results.xml", "run-3/report_1/results.xml",
             "summary.json", "summary.md"],
        )  # fmt: skip
        self.assertEqual(self.summary["flaky"], [])

    def test_one_red_run_fails_the_command_and_names_the_flaky_test(self) -> None:
        green = results_xml({"tests/unit/a_test": {"test_x": PASS}})
        red = results_xml({"tests/unit/a_test": {"test_x": FAIL}})
        rc, _, _, printed = self.run_repeat([(0, green, False), (100, red, False), (0, green, False)], 3)
        self.assertEqual(rc, 1)
        self.assertEqual(self.summary["flaky"], [{"test": "tests/unit/a_test::test_x", "failed_in_runs": [2]}])
        self.assertIn("flaky: tests/unit/a_test::test_x failed in run(s) 2 of 3", printed)
        self.assertEqual([r["status"] for r in self.summary["runs"]], ["passed", "FAILED", "passed"])

    def test_a_timed_out_run_is_recorded_and_the_next_run_still_happens(self) -> None:
        green = results_xml({"tests/unit/a_test": {"test_x": PASS}})
        rc, _, _, _ = self.run_repeat([(0, green, False), (-1, "", True)], 2)
        self.assertEqual(rc, 1)
        self.assertEqual(self.summary["runs"][1]["note"], f"timed out after {gdunit.TIMEOUT}s")

    def test_without_the_flag_no_run_gets_engine_args(self) -> None:
        xml = results_xml({"tests/unit/a_test": {"test_ok": PASS}})
        self.assertEqual(self.run_repeat([(0, xml, False)] * 2, 2, paths=["tests/unit"])[0], 0)
        self.assertTrue(all("--fixed-fps" not in args for args in self.args))
        self.assertNotIn("engine_args", self.summary)

    def test_the_first_line_names_the_clock_flag_given_as_plain_test_does(self) -> None:
        xml = results_xml({"tests/unit/a_test": {"test_ok": PASS}})
        for flag, line in [(None, "test --repeat 1"), (False, "test --repeat 1 --real-time"),
                           (True, "test --repeat 1 --fixed-fps (60)")]:  # fmt: skip
            printed = self.run_repeat([(0, xml, False)], 1, paths=["tests/unit"], fixed_fps=flag)[3]
            self.assertIn(line, printed.splitlines())

    def test_repeat_with_the_flag_passes_engine_args_to_every_run(self) -> None:
        xml = results_xml({"tests/unit/a_test": {"test_ok": PASS}})
        rc, _, _, printed = self.run_repeat([(0, xml, False)] * 2, 2, paths=["tests/unit"], fixed_fps=True)
        self.assertEqual(rc, 0, printed)
        self.assertEqual(len(self.args), 2)
        for args in self.args:
            at = args.index("--fixed-fps")
            self.assertEqual(args[at : at + 2], ["--fixed-fps", "60"])
            self.assertLess(at, args.index("-s"))
        self.assertEqual(self.summary["engine_args"], ["--fixed-fps", "60"])

    def test_repeat_with_the_flag_needs_paths(self) -> None:
        with self.assertRaisesRegex(common.Failure, "needs the paths"):
            gdunit.repeat(2, run_import=False, fixed_fps=True)

    def test_repeat_below_one_is_refused(self) -> None:
        with self.assertRaises(common.Failure):
            gdunit.repeat(0, run_import=False)


class ShardedRepeatTest(unittest.TestCase):
    """repeat() without paths: each run in shards (run_shards, replaced by a stub that writes what it writes), #817."""

    GREEN = results_xml({"tests/unit/a_test": {"test_x": PASS}})
    RED = results_xml({"tests/unit/a_test": {"test_x": FAIL}})

    def run_repeat(
        self, runs: list[tuple[bool | None, str]], env: dict[str, str] | None = None, **kwargs: Any
    ) -> tuple[int, list[Any], list[str], str]:
        """`runs`: per run what run_shards returns (True failed, None too few suites) and the merged results.xml;
        the xml "timeout" marks shard 2 of a failed run as timed out."""
        shard_calls: list[Any] = []
        godot_calls: list[str] = []
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "tests" / "unit").mkdir(parents=True)
            report_dir = root / "tools" / "out" / "gdunit"
            runs_dir = root / "tools" / "out" / "gdunit-runs"
            logs = root / "tools" / "out" / "logs"
            logs.mkdir(parents=True)

            def fake_shards(items: list[str], count: int, why: str, *rest: Any) -> bool | None:
                failed, xml = runs[len(shard_calls)]
                shard_calls.append((items, count, why, rest))
                if failed is None:
                    return None
                report_dir.mkdir(parents=True, exist_ok=True)
                results = xml if xml != "timeout" else ""
                if results:
                    (report_dir / "results.xml").write_text(results, encoding="utf-8")
                for shard in (1, 2):
                    (logs / f"test-shard{shard}.log").write_text(f"shard {shard}", encoding="utf-8")
                (logs / "test.log").write_text("all", encoding="utf-8")
                slow = {"timed_out": True} if xml == "timeout" else {}
                first: dict[str, object] = {"shard": 1, "rc": 0, "seconds": 1.0}
                rc = 100 if failed and not slow else 0  # a failed run without a timeout: shard 2 had failed tests
                second: dict[str, object] = {"shard": 2, "rc": rc, "seconds": 1.0, **slow}
                gdunit._remember([first, second], [])
                return failed

            def fake_godot(args: list[str], *, timeout: float, log: str, echo: bool = False) -> common.Result:
                godot_calls.append(log)
                (report_dir / "report_1").mkdir(parents=True, exist_ok=True)
                (report_dir / "report_1" / "results.xml").write_text(self.GREEN, encoding="utf-8")
                return common.Result(0, "", False, 1.0)

            out = io.StringIO()
            with (
                mock.patch.object(gdunit, "ROOT", root),
                mock.patch.object(gdunit, "REPORT_DIR", report_dir),
                mock.patch.object(gdunit, "RUNS_DIR", runs_dir),
                mock.patch.object(gdunit, "LOGS", logs),
                mock.patch.object(gdunit, "ensure_out", return_value=root / "tools" / "out"),
                mock.patch.object(gdunit, "run_shards", fake_shards),
                mock.patch.object(gdunit, "godot", fake_godot),
                mock.patch.object(gdunit, "app_data_var", return_value="XDG_DATA_HOME"),
                mock.patch.object(gdunit.os, "cpu_count", return_value=4),
                mock.patch.dict(gdunit.os.environ, env or {}),
                contextlib.redirect_stdout(out),
                contextlib.redirect_stderr(out),
            ):
                if not env:
                    gdunit.os.environ.pop(gdunit.SHARDS_VAR, None)
                rc = gdunit.repeat(len(runs), run_import=False, **kwargs)
            kept = sorted(p.relative_to(root / "tools" / "out").as_posix() for p in (root / "tools" / "out").rglob("*") if p.is_file())
            self.summary = json.loads((runs_dir / "summary.json").read_text(encoding="utf-8"))
        self.godot_calls = godot_calls
        return rc, shard_calls, kept, out.getvalue()

    def test_each_run_is_sharded_real_time_by_the_cpu_count_as_plain_test_is(self) -> None:
        rc, calls, _, printed = self.run_repeat([(False, self.GREEN)] * 3)
        self.assertEqual(rc, 0, printed)
        self.assertEqual(self.godot_calls, [])
        self.assertEqual(len(calls), 3)
        for items, count, why, rest in calls:
            self.assertEqual((items, count, rest), (["res://tests/unit"], 2, (False, False)), "2 shards, real-time")
            self.assertIn("4 CPUs", why)

    def test_the_shards_option_and_the_environment_set_the_count_the_option_first(self) -> None:
        self.assertEqual(self.run_repeat([(False, self.GREEN)], shards=3)[1][0][1], 3)
        self.assertEqual(self.run_repeat([(False, self.GREEN)], env={gdunit.SHARDS_VAR: "3"})[1][0][1], 3)
        self.assertEqual(self.run_repeat([(False, self.GREEN)], env={gdunit.SHARDS_VAR: "3"}, shards=4)[1][0][1], 4)

    def test_one_shard_or_named_paths_run_in_one_process_as_before(self) -> None:
        for kwargs in ({"shards": 1}, {"paths": ["tests/unit"]}):
            rc, calls, _, printed = self.run_repeat([(False, self.GREEN)] * 2, env={gdunit.SHARDS_VAR: "2"}, **kwargs)
            self.assertEqual((rc, calls), (0, []), printed)
            self.assertEqual(self.godot_calls, ["test-run1", "test-run2"])

    def test_a_run_with_fewer_than_two_suites_falls_back_to_one_process(self) -> None:
        rc, calls, _, printed = self.run_repeat([(None, self.GREEN)])
        self.assertEqual((rc, len(calls), self.godot_calls), (0, 1, ["test-run1"]), printed)

    def test_every_run_keeps_its_merged_report_and_its_logs(self) -> None:
        _, _, kept, _ = self.run_repeat([(False, self.GREEN)] * 2)
        for run in (1, 2):
            self.assertIn(f"gdunit-runs/run-{run}/results.xml", kept)
            self.assertIn(f"logs/test-run{run}.log", kept)
            self.assertIn(f"logs/test-run{run}-shard1.log", kept)
            self.assertIn(f"logs/test-run{run}-shard2.log", kept)
        self.assertIn("gdunit-runs/summary.md", kept)

    def test_the_runs_are_still_compared_per_test_across_shards(self) -> None:
        rc, _, _, printed = self.run_repeat([(False, self.GREEN), (True, self.RED), (False, self.GREEN)])
        self.assertEqual(rc, 1)
        self.assertEqual(self.summary["flaky"], [{"test": "tests/unit/a_test::test_x", "failed_in_runs": [2]}])
        self.assertEqual([r["status"] for r in self.summary["runs"]], ["passed", "FAILED", "passed"])
        self.assertEqual(self.summary["runs"][0]["note"], "2 processes")
        self.assertIn("flaky: tests/unit/a_test::test_x failed in run(s) 2 of 3", printed)

    def test_a_shard_that_timed_out_is_named_in_the_runs_note(self) -> None:
        rc, _, _, _ = self.run_repeat([(False, self.GREEN), (True, "timeout")])
        self.assertEqual(rc, 1)
        self.assertEqual(self.summary["runs"][1]["note"], f"2 processes, shard 2 timed out after {gdunit.TIMEOUT}s")
        self.assertEqual(self.summary["runs"][1]["tests"], 0)

    def test_a_failed_shard_says_why_in_the_runs_note(self) -> None:
        rc, _, _, _ = self.run_repeat([(False, self.GREEN), (True, self.RED)])
        self.assertEqual(rc, 1)
        self.assertEqual(self.summary["runs"][1]["note"], "2 processes; shard 2: exit 100, tests failed")

    def test_named_paths_at_fixed_fps_in_shards_keep_the_fixed_clock(self) -> None:
        rc, calls, _, printed = self.run_repeat(
            [(False, self.GREEN)] * 2, paths=["tests/unit"], fixed_fps=True, shards=2
        )
        self.assertEqual(rc, 0, printed)
        for items, count, _why, rest in calls:
            self.assertEqual((items, count, rest), (["res://tests/unit"], 2, (True, True)), "every named suite fixed")
        self.assertIn(f"--fixed-fps ({gdunit.FIXED_FPS})", printed)
        self.assertEqual(self.summary["engine_args"], list(gdunit.FIXED_FPS_ARGS))


class CliTest(unittest.TestCase):
    def test_shards_reach_repeat_when_given(self) -> None:
        with mock.patch.object(gdunit, "repeat", return_value=0) as rep:
            self.assertEqual(cli.main(["test", "--repeat", "3", "--shards", "2"]), 0)
        rep.assert_called_once_with(3, paths=None, shards=2)

    def test_test_repeat_goes_to_repeat_and_plain_test_to_main(self) -> None:
        with mock.patch.object(gdunit, "repeat", return_value=0) as rep, mock.patch.object(gdunit, "main", return_value=0) as main:
            self.assertEqual(cli.main(["test", "--repeat", "3", "tests/unit"]), 0)
            self.assertEqual(cli.main(["test"]), 0)
        rep.assert_called_once_with(3, paths=["tests/unit"])
        main.assert_called_once_with(paths=None)

    def test_the_clock_flags_reach_repeat_only_when_given(self) -> None:
        with mock.patch.object(gdunit, "repeat", return_value=0) as rep:
            self.assertEqual(cli.main(["test", "--repeat", "2", "tests/unit", "--fixed-fps"]), 0)
            self.assertEqual(cli.main(["test", "--repeat", "2", "--real-time"]), 0)
        self.assertEqual(rep.call_args_list, [mock.call(2, paths=["tests/unit"], fixed_fps=True),
                                              mock.call(2, paths=None, fixed_fps=False)])  # fmt: skip


if __name__ == "__main__":
    unittest.main()
