"""`test` in shards (#182): K GdUnit4 processes at once, balanced by the last per-suite times, each with a user:// of
its own; every shard judged as a one-process run is, the merged results checked against a one-process scan."""

import contextlib
import io
import json
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any
from unittest import mock

from runner import cli, common, gdunit

SUITE = "extends GdUnitTestSuite\n\n\nfunc test_one() -> void:\n\tpass\n\n\nfunc test_two() -> void:\n\tpass\n"
# The fixture project's scripts: path -> source. Four suites (one through a class_name base, one through a quoted
# path), two scripts that are no suites, one suite in a folder with a .gdignore and one in the scratch folder.
SCRIPTS = {
    "tests/unit/a_test.gd": SUITE,
    "tests/unit/b_test.gd": "class_name BTest extends GdUnitTestSuite\n\n\nfunc test_b() -> void:\n\tpass\n",
    "tests/harness/net_suite.gd": "class_name NetSuite\nextends GdUnitTestSuite\n",
    "tests/harness/helper.gd": "class_name Helper\nextends RefCounted\n\n\nfunc test_not_a_test() -> void:\n\tpass\n",
    "tests/integration/c_test.gd": "extends NetSuite\n\n\nfunc test_c() -> void:\n\tpass\n",
    "tests/integration/d_test.gd": 'extends "../harness/net_suite.gd"\n\n\nfunc test_d() -> void:\n\tpass\n',
    "tests/integration/outside.gd": 'extends "../../../outside.gd"\n\n\nfunc test_never() -> void:\n\tpass\n',
    "tests/ignored/e_test.gd": SUITE,
    "tests/scratch/probe_test.gd": SUITE,
}
SUITES = {
    "res://tests/harness/net_suite.gd": [],
    "res://tests/integration/c_test.gd": ["test_c"],
    "res://tests/integration/d_test.gd": ["test_d"],
    "res://tests/unit/a_test.gd": ["test_one", "test_two"],
    "res://tests/unit/b_test.gd": ["test_b"],
}
FAILURE = '<failure message="FAILED: res://tests/unit/a_test.gd:5" type="FAILURE">Expecting: 1 but was 2</failure>'


def results_xml(suites: list[str], fail: str = "", seconds: dict[str, float] | None = None) -> str:
    """A GdUnit4-shaped results.xml of the given suites (res:// paths), with `fail`'s first test failing."""
    body = []
    for res in suites:
        path = res.removeprefix("res://")
        package, name = path.rsplit("/", 1)
        name = name.removesuffix(".gd")
        cases = "".join(
            f'<testcase name="{t}" classname="{name}" time="0.01">{FAILURE if (res, i) == (fail, 0) else ""}</testcase>'
            for i, t in enumerate(SUITES[res])
        )
        time = (seconds or {}).get(res, 1.0)
        body.append(f'<testsuite id="0" name="{name}" package="{package}" tests="{len(SUITES[res])}" time="{time}">'
                    f"{cases}</testsuite>")  # fmt: skip
    failures = 1 if fail in suites else 0
    total = sum(len(SUITES[s]) for s in suites)
    return (f'<?xml version="1.0" encoding="UTF-8" ?><testsuites id="2026-10-02" name="report_1" tests="{total}" '
            f'failures="{failures}" skipped="0" flaky="0" time="0.000">{"".join(body)}</testsuites>')  # fmt: skip


class Fixture(unittest.TestCase):
    """A throwaway project with gdunit's paths pointed into it and Godot replaced by a stub that writes each run's
    results.xml for the suites it was given, and a file under the user:// root its environment names."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = root = Path(tmp.name)
        for rel, text in SCRIPTS.items():
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text, encoding="utf-8")
        (root / "tests" / "ignored" / ".gdignore").write_text("", encoding="utf-8")
        out = root / "tools" / "out"
        self.calls: list[dict[str, Any]] = []
        self.behaviour: dict[int, dict[str, Any]] = {}
        self.seconds: dict[str, float] = {}
        self.siblings = ""
        patches = [
            mock.patch.object(gdunit, "ROOT", root),
            mock.patch.object(gdunit, "REPORT_DIR", out / "gdunit"),
            mock.patch.object(gdunit, "SHARD_USER", out / "gdunit-user"),
            mock.patch.object(gdunit, "LOGS", out / "logs"),
            mock.patch.object(gdunit, "TIMES", out / "logs" / "gdunit-times.json"),
            mock.patch.object(gdunit, "ensure_out", side_effect=lambda: (out / "logs").mkdir(parents=True, exist_ok=True)),
            mock.patch.object(gdunit, "require_godot", return_value="godot"),
            mock.patch.object(gdunit, "app_data_var", return_value="APPDATA"),
            mock.patch.object(gdunit, "godot", self.fake_godot),
            mock.patch.object(gdunit, "git", side_effect=lambda *a, **k: common.Result(0, self.siblings, False, 0.0)),
            mock.patch.dict(os.environ, {gdunit.SHARDS_VAR: ""}),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.addCleanup(gdunit.take_last_run)  # no run's record outlives its test (a worker runs many tests)

    def fake_godot(self, args: list[str], *, timeout: float, log: str, echo: bool = False,
                   env: dict[str, str] | None = None, on_start: Any = None) -> common.Result:  # fmt: skip
        selected = [args[i + 1] for i, arg in enumerate(args) if arg == "-a"]
        index = int(log.removeprefix("test-shard")) if log.startswith("test-shard") else 0
        how = self.behaviour.get(index, {})
        self.calls.append({"log": log, "selected": selected, "env": env, "args": args})
        if env and not how.get("shared_user_dir"):
            (Path(next(iter(env.values()))) / "Godot" / "app_userdata").mkdir(parents=True)
        files: list[str] = []
        for item in selected:
            path = self.root / item.removeprefix("res://")
            files += [gdunit._res(p) for p in gdunit._walk(path)] if path.is_dir() else [item]
        # GdUnit4 reports no suite that has no test case (a base class).
        suites = [f for f in files if SUITES.get(f) and f not in how.get("drop", ())]
        report = self.root / args[args.index("-rd") + 1].removeprefix("res://") / "report_1"
        if not how.get("crash"):  # a crashed process writes no results.xml
            report.mkdir(parents=True)
            text = results_xml(suites, how.get("fail", ""), self.seconds)
            (report / "results.xml").write_text(text, encoding="utf-8")
        return common.Result(how.get("rc", 0), how.get("out", ""), how.get("timed_out", False), 2.0)

    def run_test(self, **kwargs: Any) -> tuple[int, str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = gdunit.main(run_import=False, **kwargs)
        return rc, out.getvalue()


class ShardRunTest(Fixture):
    def test_three_shards_run_every_script_once_each_with_its_own_user_dir(self) -> None:
        rc, text = self.run_test(shards=3)
        self.assertEqual(rc, 0, text)
        calls = sorted(self.calls, key=lambda call: call["log"])  # the shards start at once, in any order
        self.assertEqual([c["log"] for c in calls], ["test-shard1", "test-shard2", "test-shard3"])
        selected = [item for call in calls for item in call["selected"]]
        expected = gdunit.script_files(gdunit.selectors(None, self.root / "tests"))
        self.assertEqual(sorted(selected), sorted(expected))
        self.assertEqual(len(selected), len(set(selected)))
        self.assertNotIn("res://tests/scratch/probe_test.gd", selected)
        self.assertNotIn("res://tests/ignored/e_test.gd", selected)
        users = [call["env"]["APPDATA"] for call in calls]
        self.assertEqual(len(set(users)), 3)
        reports = [call["args"][call["args"].index("-rd") + 1] for call in calls]
        self.assertEqual(reports, [f"res://tools/out/gdunit/shard-{i}" for i in (1, 2, 3)])
        merged = ET.parse(self.root / "tools" / "out" / "gdunit" / "results.xml").getroot()
        self.assertEqual(merged.get("tests"), "5")
        self.assertEqual([s.get("id") for s in merged.iter("testsuite")], ["0", "1", "2", "3"])
        self.assertIn("4 suites and 5 test cases ran in 3 processes; a one-process scan finds 4 suites with 5", text)
        self.assertIn("5 tests passed in 3 processes", text)
        log = (self.root / "tools" / "out" / "logs" / "test.log").read_text(encoding="utf-8")
        self.assertEqual(log.count("===== shard "), 3)
        times = json.loads((self.root / "tools" / "out" / "logs" / "gdunit-times.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted(times["suites"]), sorted(k for k, v in SUITES.items() if v))

    def test_a_failure_in_one_shard_fails_the_run(self) -> None:
        self.behaviour[1] = {"rc": 100, "fail": "res://tests/unit/a_test.gd"}
        self.seconds = {"res://tests/unit/a_test.gd": 9.0}  # the slowest suite goes to shard 1
        (self.root / "tools" / "out" / "logs").mkdir(parents=True)
        times = {"suites": {**dict.fromkeys(SUITES, 1.0), **self.seconds}}
        (self.root / "tools" / "out" / "logs" / "gdunit-times.json").write_text(json.dumps(times), encoding="utf-8")
        rc, text = self.run_test(shards=2)
        self.assertEqual(rc, 1)
        self.assertIn("FAIL  shard 1: exit 100: tests failed", text)
        self.assertIn("a_test::test_one: FAILED", text)
        self.assertIn("test: FAILED", text)

    def test_orphans_in_one_shard_fail_the_run_and_name_the_test(self) -> None:
        log = "Run Test Suite: res://tests/unit/b_test.gd\n  res://tests/unit/b_test.gd > test_b PASSED\n"
        self.behaviour[2] = {"rc": 101, "out": log + "WARNING: Detected 2 possible orphan nodes.\n"}
        rc, text = self.run_test(shards=2)
        self.assertEqual(rc, 1)
        self.assertIn("shard 2: exit 101: orphan nodes detected", text)
        self.assertIn("shard 2: res://tests/unit/b_test.gd > test_b: 2 orphan node(s)", text)

    def test_a_suite_that_never_ran_fails_the_run(self) -> None:
        self.behaviour[1] = self.behaviour[2] = {"drop": ["res://tests/integration/c_test.gd"]}
        rc, text = self.run_test(shards=2)
        self.assertEqual(rc, 1)
        self.assertIn("would run but that never ran (1): res://tests/integration/c_test.gd", text)

    def test_a_shard_without_its_own_user_dir_fails_the_run(self) -> None:
        self.behaviour[2] = {"shared_user_dir": True}
        rc, text = self.run_test(shards=2)
        self.assertEqual(rc, 1)
        self.assertIn("shard 2: Godot put nothing under tools/out/gdunit-user/shard-2", text)

    def test_the_last_times_balance_the_shards(self) -> None:
        heavy = "res://tests/integration/c_test.gd"
        (self.root / "tools" / "out" / "logs").mkdir(parents=True)
        times = {"suites": {**dict.fromkeys(SUITES, 1.0), heavy: 30.0}}
        (self.root / "tools" / "out" / "logs" / "gdunit-times.json").write_text(json.dumps(times), encoding="utf-8")
        rc, text = self.run_test(shards=2)
        self.assertEqual(rc, 0, text)
        calls = sorted(self.calls, key=lambda call: call["log"])
        suites = [[s for s in call["selected"] if SUITES.get(s)] for call in calls]
        self.assertEqual(suites[0], [heavy])
        self.assertIn("balanced by tools/out/logs/gdunit-times.json", text)

    def test_a_fresh_worktree_takes_the_newest_times_of_another_checkout(self) -> None:
        other = self.root / "elsewhere"
        (other / "tools" / "out" / "logs").mkdir(parents=True)
        (other / "tools" / "out" / "logs" / "gdunit-times.json").write_text(
            json.dumps({"suites": {"res://tests/unit/a_test.gd": 4.0}}), encoding="utf-8"
        )
        self.siblings = f"worktree {self.root.as_posix()}\nHEAD 1\n\nworktree {other.as_posix()}\nHEAD 2\n"
        times, source = gdunit.read_times()
        self.assertEqual(times, {"res://tests/unit/a_test.gd": 4.0})
        self.assertIn("(this checkout has no times yet)", source)
        self.siblings = ""
        self.assertEqual(gdunit.read_times(), ({}, "no times yet: every suite counts the same"))


class HistoryRecordTest(Fixture):
    """What a run leaves for verify's history record (#273): each process's exit and seconds, the failing tests."""

    def last_run(self, **kwargs: Any) -> tuple[int, str, dict[str, Any]]:
        rc, text = self.run_test(**kwargs)
        record = gdunit.take_last_run()
        assert record is not None, text
        self.assertIsNone(gdunit.take_last_run(), "taken once")
        return rc, text, record

    def test_a_green_run_records_each_shard_and_no_tests(self) -> None:
        rc, _text, record = self.last_run(shards=2)
        self.assertEqual(rc, 0)
        shards = [{"shard": 1, "rc": 0, "seconds": 2.0}, {"shard": 2, "rc": 0, "seconds": 2.0}]
        self.assertEqual(record, {"shards": shards})

    def test_a_red_shard_records_its_failing_tests_with_the_first_line_of_the_failure(self) -> None:
        self.behaviour[2] = {"rc": 100, "fail": "res://tests/unit/a_test.gd"}
        self.seconds = {"res://tests/unit/a_test.gd": 9.0}
        (self.root / "tools" / "out" / "logs").mkdir(parents=True)
        times = {"suites": {**dict.fromkeys(SUITES, 1.0), "res://tests/integration/c_test.gd": 20.0}}
        (self.root / "tools" / "out" / "logs" / "gdunit-times.json").write_text(json.dumps(times), encoding="utf-8")
        rc, _text, record = self.last_run(shards=2)
        self.assertEqual(rc, 1)
        self.assertEqual([(s["shard"], s["rc"]) for s in record["shards"]], [(1, 0), (2, 100)])
        self.assertEqual(record["failed_tests"], [{"test": "a_test::test_one", "message": "Expecting: 1 but was 2"}])

    def test_a_crashed_shard_records_its_exit_code_without_results(self) -> None:
        self.behaviour[2] = {"rc": 3221225477, "crash": True}
        rc, text, record = self.last_run(shards=2)
        self.assertEqual(rc, 1)
        self.assertIn("shard 2: GdUnit4 crashed or exited unexpectedly (exit 3221225477)", text)
        self.assertEqual(record["shards"][1], {"shard": 2, "rc": 3221225477, "seconds": 2.0, "results": False})
        self.assertEqual(record["shards"][0], {"shard": 1, "rc": 0, "seconds": 2.0})
        self.assertNotIn("failed_tests", record)

    def test_a_timed_out_shard_says_so(self) -> None:
        self.behaviour[1] = {"rc": -1, "crash": True, "timed_out": True}
        rc, _text, record = self.last_run(shards=2)
        self.assertEqual(rc, 1)
        self.assertEqual(record["shards"][0], {"shard": 1, "rc": -1, "seconds": 2.0, "timed_out": True,
                                               "results": False})  # fmt: skip

    def test_orphans_are_recorded_as_such_with_the_suite_and_test_names(self) -> None:
        log = "Run Test Suite: res://tests/unit/b_test.gd\n  res://tests/unit/b_test.gd > test_b PASSED\n"
        self.behaviour[2] = {"rc": 101, "out": log + "WARNING: Detected 2 possible orphan nodes.\n"}
        rc, _text, record = self.last_run(shards=2)
        self.assertEqual(rc, 1)
        self.assertEqual(record["failed_tests"], [{"test": "b_test::test_b", "orphans": 2}])
        self.assertEqual(record["shards"][1]["rc"], 101)

    def test_a_one_process_run_records_its_process_as_shard_1(self) -> None:
        self.behaviour[0] = {"rc": 100, "fail": "res://tests/unit/a_test.gd"}
        rc, _text, record = self.last_run(paths=["tests/unit"])
        self.assertEqual(rc, 1)
        self.assertEqual(record["shards"], [{"shard": 1, "rc": 100, "seconds": 2.0}])
        self.assertEqual([t["test"] for t in record["failed_tests"]], ["a_test::test_one"])

    def test_the_record_is_capped(self) -> None:
        many = [{"test": f"s::test_{i}", "message": "x"} for i in range(gdunit.RECORD_CAP + 5)]
        gdunit._remember([], many)
        record = gdunit.take_last_run()
        assert record is not None
        self.assertEqual(len(record["failed_tests"]), gdunit.RECORD_CAP)
        self.assertEqual(record["failed_tests_more"], 5)
        clipped = gdunit.clip("Expecting:\n" + "x" * 1000)
        self.assertEqual(len(clipped), gdunit.MESSAGE_CAP)
        self.assertTrue(clipped.startswith("Expecting: xxx") and clipped.endswith("..."))

    def test_a_failure_without_a_body_keeps_its_message(self) -> None:
        path = self.root / "r.xml"
        path.write_text('<testsuites><testsuite name="s"><testcase name="t" classname="s">'
                        '<error message="ERROR: res://tests/s.gd:3" type="ABORT"/></testcase></testsuite></testsuites>',
                        encoding="utf-8")  # fmt: skip
        self.assertEqual(gdunit.failed_cases(path), [{"test": "s::t", "message": "ERROR: res://tests/s.gd:3"}])
        self.assertEqual(gdunit.failed_cases(self.root / "missing.xml"), [])

    def test_a_failure_over_several_lines_is_one_line_without_its_stack(self) -> None:
        # As GdUnit4 6.2.1 writes it (the #273 probe's results.xml).
        path = self.root / "r.xml"
        path.write_text(
            '<testsuites><testsuite name="p_test"><testcase name="test_x" classname="p_test">'
            '<failure message="FAILED: res://tests/scratch/p_test.gd:9" type="FAILURE"><![CDATA[\n'
            "Expecting:\n 3\n but was\n 2\n\tat 'test_x' in res://tests/scratch/p_test.gd:9\n]]></failure>"
            "</testcase></testsuite></testsuites>",
            encoding="utf-8",
        )
        self.assertEqual(gdunit.failed_cases(path), [{"test": "p_test::test_x", "message": "Expecting: 3 but was 2"}])


class OneProcessTest(Fixture):
    def test_named_paths_run_in_one_process_as_before(self) -> None:
        rc, text = self.run_test(paths=["tests/unit", "res://tests/integration/c_test.gd"])
        self.assertEqual(rc, 0, text)
        self.assertEqual(len(self.calls), 1)
        call = self.calls[0]
        self.assertEqual(call["log"], "test")
        self.assertIsNone(call["env"])
        self.assertEqual(
            call["args"],
            ["--headless", "-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "--ignoreHeadlessMode", "-c",
             "-a", "res://tests/unit", "-a", "res://tests/integration/c_test.gd",
             "-rd", "res://tools/out/gdunit", "-rc", "1"],
        )  # fmt: skip
        self.assertIn("4 tests passed (report: tools/out/gdunit/report_1/results.xml)", text)

    def test_one_shard_is_the_one_process_run_of_every_folder(self) -> None:
        rc, _ = self.run_test(shards=1)
        self.assertEqual(rc, 0)
        self.assertEqual([c["log"] for c in self.calls], ["test"])
        folders = ["res://tests/harness", "res://tests/ignored", "res://tests/integration", "res://tests/unit"]
        self.assertEqual([a for a in self.calls[0]["args"] if a.startswith("res://tests")], folders)

    def test_named_paths_stay_one_process_with_the_environment_variable_set(self) -> None:
        # mutants (#200) calls gdunit.main(paths, run_import=False) and reads report_*/results.xml
        with mock.patch.dict(os.environ, {gdunit.SHARDS_VAR: "4"}):
            rc, text = self.run_test(paths=["tests/unit"])
        self.assertEqual(rc, 0, text)
        self.assertEqual([c["log"] for c in self.calls], ["test"])
        self.assertIsNone(self.calls[0]["env"])
        self.assertIn("report: tools/out/gdunit/report_1/results.xml", text)

    def test_the_environment_variable_sets_the_count_for_a_run_without_paths(self) -> None:
        with mock.patch.dict(os.environ, {gdunit.SHARDS_VAR: "1"}):
            self.run_test()
        self.assertEqual([c["log"] for c in self.calls], ["test"])


class CountTest(unittest.TestCase):
    def test_half_the_logical_cpus_at_most_the_cap(self) -> None:
        cap = gdunit.SHARD_CAP
        self.assertEqual([gdunit.default_shards(n) for n in (1, 2, 4, 6)], [1, 1, 2, min(3, cap)])
        self.assertEqual(gdunit.default_shards(64), cap)

    def test_the_count_and_why(self) -> None:
        with (
            mock.patch.object(gdunit, "app_data_var", return_value="APPDATA"),
            mock.patch.dict(os.environ, {gdunit.SHARDS_VAR: ""}),
        ):
            self.assertEqual(gdunit.shard_count(None, 4), (4, "--shards 4"))
            self.assertEqual(gdunit.shard_count(["tests/unit"], None), (1, "named paths"))
            self.assertEqual(gdunit.shard_count(["tests/unit"], 2), (2, "--shards 2"))
            with mock.patch.dict(os.environ, {gdunit.SHARDS_VAR: "4"}):
                self.assertEqual(gdunit.shard_count(["tests/unit"], None), (1, "named paths"))
            with mock.patch.object(gdunit, "default_shards", return_value=3):
                self.assertEqual(gdunit.shard_count(None, None)[0], 3)
            with mock.patch.dict(os.environ, {gdunit.SHARDS_VAR: "2"}):
                self.assertEqual(gdunit.shard_count(None, None), (2, f"{gdunit.SHARDS_VAR}=2"))
            for wrong in ("0", "two"):
                with self.subTest(wrong=wrong), mock.patch.dict(os.environ, {gdunit.SHARDS_VAR: wrong}):
                    with self.assertRaises(common.Failure):
                        gdunit.shard_count(None, None)
            with self.assertRaises(common.Failure):
                gdunit.shard_count(None, 0)

    def test_no_shards_without_a_per_process_user_dir(self) -> None:
        with mock.patch.object(gdunit, "app_data_var", return_value=None), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(gdunit.shard_count(None, 3), (1, "no per-process user://"))


class PlanTest(Fixture):
    def test_the_scan_finds_the_suites_a_one_process_run_finds(self) -> None:
        files = gdunit.script_files(gdunit.selectors(None, self.root / "tests"))
        self.assertNotIn("res://tests/ignored/e_test.gd", files)
        self.assertEqual(gdunit.static_suites(files), SUITES)
        twice = gdunit.script_files(["res://tests/unit", "res://tests/unit/a_test.gd", "res://tests/none"])
        self.assertEqual(twice, ["res://tests/unit/a_test.gd", "res://tests/unit/b_test.gd"])

    def test_longest_first_to_the_least_loaded_shard(self) -> None:
        costs = {"a": 10.0, "b": 6.0, "c": 5.0, "d": 4.0, "e": 0.0, "f": 0.0}
        plan = gdunit.plan_shards(costs, 2)
        self.assertEqual(plan, [["a", "d"], ["b", "c", "e", "f"]])
        self.assertEqual(gdunit.plan_shards(costs, 4), [["a"], ["b"], ["c"], ["d", "e", "f"]])

    def test_a_suite_without_a_time_counts_as_the_mean(self) -> None:
        suites = {"x": ["test_a"], "y": ["test_b"], "z": []}
        costs = gdunit.estimates(["x", "y", "z", "helper"], suites, {"x": 4.0, "z": 2.0})
        self.assertEqual(costs, {"x": 4.0, "y": 3.0, "z": 2.0, "helper": 0.0})
        self.assertEqual(gdunit.estimates(["x"], suites, {}), {"x": 1.0})

    def test_times_merge_and_forget_deleted_suites(self) -> None:
        report = self.root / "results.xml"
        report.write_text(results_xml(["res://tests/unit/a_test.gd"], seconds={"res://tests/unit/a_test.gd": 7.5}),
                          encoding="utf-8")  # fmt: skip
        gdunit.TIMES.parent.mkdir(parents=True)
        old = {
            "res://tests/unit/a_test.gd": 1.0,
            "res://tests/unit/b_test.gd": 2.0,
            "res://tests/unit/gone_test.gd": 3.0,
        }
        gdunit.TIMES.write_text(json.dumps({"suites": old}), encoding="utf-8")
        gdunit.record_times([report])
        self.assertEqual(
            json.loads(gdunit.TIMES.read_text(encoding="utf-8"))["suites"],
            {"res://tests/unit/a_test.gd": 7.5, "res://tests/unit/b_test.gd": 2.0},
        )


class MergeTest(unittest.TestCase):
    def test_merge_sums_the_totals_and_coverage_counts_against_the_scan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            one, two = Path(tmp) / "1.xml", Path(tmp) / "2.xml"
            one.write_text(results_xml(["res://tests/unit/b_test.gd", "res://tests/unit/a_test.gd"],
                                       fail="res://tests/unit/a_test.gd"), encoding="utf-8")  # fmt: skip
            two.write_text(results_xml(["res://tests/integration/c_test.gd", "res://tests/unit/b_test.gd"]),
                           encoding="utf-8")  # fmt: skip
            merged = gdunit.merge_junit([one, two])
        self.assertEqual({k: merged.get(k) for k in ("tests", "failures", "name")},
                         {"tests": "5", "failures": "1", "name": "merged"})  # fmt: skip
        keys = [gdunit.suite_key(s) for s in merged.iter("testsuite")]
        self.assertEqual(keys, ["res://tests/integration/c_test.gd", "res://tests/unit/a_test.gd",
                                "res://tests/unit/b_test.gd", "res://tests/unit/b_test.gd"])  # fmt: skip
        expected = {k: v for k, v in SUITES.items() if k != "res://tests/harness/net_suite.gd"}
        expected["res://tests/unit/a_test.gd"] = ["test_one", "test_two", "test_three"]
        problems, warnings, line = gdunit.coverage(expected, merged, 2)
        self.assertEqual(
            problems,
            [
                "suites that a one-process run would run but that never ran (1): res://tests/integration/d_test.gd",
                "suites that ran in more than one shard (1): res://tests/unit/b_test.gd",
                "suites that ran without some of their test functions (1): res://tests/unit/a_test.gd (test_three)",
            ],
        )
        self.assertEqual(warnings, [])
        self.assertEqual(line, "3 suites and 5 test cases ran in 2 processes; "
                               "a one-process scan finds 4 suites with 6 test functions")  # fmt: skip
        _, warnings, _ = gdunit.coverage({}, merged, 2)
        self.assertIn("suites that ran (once each) but the runner's scan did not expect (3)", warnings[0])


class CliTest(unittest.TestCase):
    def test_shards_reach_main_and_refuse_repeat(self) -> None:
        with mock.patch.object(gdunit, "main", return_value=0) as main, mock.patch.object(gdunit, "repeat") as rep:
            self.assertEqual(cli.main(["test", "--shards", "1"]), 0)
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(cli.main(["test", "--repeat", "2", "--shards", "2"]), 1)
        main.assert_called_once_with(paths=None, shards=1)
        rep.assert_not_called()
        self.assertIn("--repeat runs one process per run", out.getvalue())


if __name__ == "__main__":
    unittest.main()
