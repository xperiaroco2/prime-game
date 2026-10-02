"""`test --repeat N` (the nightly flaky-test job, docs/AGENT_WORKFLOW.md "Night jobs"): per-run reports kept, a
per-suite and per-test comparison, and any failed run failing the command."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
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

    def run_repeat(self, runs: list[tuple[int, str, bool]], count: int) -> tuple[int, Path, list[str], str]:
        calls: list[str] = []
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "tests" / "unit").mkdir(parents=True)
            report_dir = root / "tools" / "out" / "gdunit"
            runs_dir = root / "tools" / "out" / "gdunit-runs"

            def fake_godot(args: list[str], *, timeout: float, log: str, echo: bool = False) -> common.Result:
                rc, xml, timed_out = runs[len(calls)]
                calls.append(log)
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
                rc = gdunit.repeat(count, run_import=False)
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

    def test_repeat_below_one_is_refused(self) -> None:
        with self.assertRaises(common.Failure):
            gdunit.repeat(0, run_import=False)


class CliTest(unittest.TestCase):
    def test_test_repeat_goes_to_repeat_and_plain_test_to_main(self) -> None:
        with mock.patch.object(gdunit, "repeat", return_value=0) as rep, mock.patch.object(gdunit, "main", return_value=0) as main:
            self.assertEqual(cli.main(["test", "--repeat", "3", "tests/unit"]), 0)
            self.assertEqual(cli.main(["test"]), 0)
        rep.assert_called_once_with(3, paths=["tests/unit"])
        main.assert_called_once_with(paths=None)


if __name__ == "__main__":
    unittest.main()
