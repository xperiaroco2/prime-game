"""`mutants` (#184) against a real temporary repository, with the steps that start Godot stubbed: the task's tree stays
untouched, a dirty tree is refused, a leftover scratch worktree goes at the next start, the cleanup follows a test step
that raises, and the spec, the verdicts and the table."""

import inspect
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import check, cli, gdunit, guard, mutants, permissions
from runner.common import ROOT
from runner.mutants import ERROR, KILLED, SURVIVED, Outcome
from runner.tests.test_githooks import _rmtree

SOURCE = "extends RefCounted\n\n\nfunc allowed(tick: int, paid_at: int) -> bool:\n\treturn tick - paid_at >= 10\n"
TEST = "extends GdUnitTestSuite\n"
BOUNDARY = {
    "file": "core/cooldown.gd",
    "line": 5,
    "original": ">= 10",
    "replacement": "> 10",
    "tests": ["tests/unit/cooldown_test.gd"],
}
ALWAYS = {**BOUNDARY, "original": "tick - paid_at >= 10", "replacement": "true"}


def git(where: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", *args], cwd=where, capture_output=True, text=True, encoding="utf-8", timeout=120,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )  # fmt: skip
    if res.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
    return res.stdout


class RepoCase(unittest.TestCase):
    """A committed repository `work` with one production script and its test; the spec file lies outside it."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="mutants-")).resolve()
        self.addCleanup(_rmtree, self.tmp)
        self.work = self.tmp / "work"
        self.work.mkdir()
        git(self.work, "init", "-q", "-b", "main")
        for key, value in (
            ("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false"), ("core.autocrlf", "false"),
        ):  # fmt: skip
            git(self.work, "config", key, value)
        self.write(".gitignore", "tools/out/\n.godot/\n")
        self.write(".gitattributes", "* text eol=lf\n")
        self.write("core/cooldown.gd", SOURCE)
        self.write("tests/unit/cooldown_test.gd", TEST)
        self.write("content/modes/base.tres", "[gd_resource]\n")
        git(self.work, "add", ".")
        git(self.work, "commit", "-q", "-m", "c1")
        self.head = git(self.work, "rev-parse", "HEAD").strip()
        self.tree = self.work / "tools" / "out" / "mutants" / "tree-work"
        self.calls: list[dict[str, object]] = []
        self.imports: list[Path] = []
        self.out = io.StringIO()
        for patch in (
            mock.patch.object(mutants, "import_step", side_effect=self.imports.append),
            mock.patch.object(mutants, "test_step", side_effect=self.fake_test),
            mock.patch("sys.stdout", self.out),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def write(self, name: str, text: str) -> None:
        path = self.work / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))

    def fake_test(self, tree: Path, paths: list[str], seconds: float) -> Outcome:
        """A suite that catches `> 10` but not `true`; it records what it saw in both trees."""
        planted = (tree / "core" / "cooldown.gd").read_text(encoding="utf-8")
        self.calls.append(
            {
                "tree": tree,
                "paths": paths,
                "planted": planted,
                "task": (self.work / "core" / "cooldown.gd").read_text(encoding="utf-8"),
                "cache": (tree / ".godot" / "cache.cfg").is_file(),
                "registered": str(tree.as_posix()).lower() in git(self.work, "worktree", "list").lower(),
            }
        )
        if "> 10" in planted:
            return Outcome(1, "  FAIL  exit 100: tests failed\n", tests=3, failing=["cooldown_test::test_boundary"])
        return Outcome(0, "  ok    3 tests passed\n", tests=3)

    def spec(self, *entries: dict[str, object], name: str = "spec.json") -> str:
        path = self.tmp / name
        path.write_text(json.dumps({"mutants": list(entries)}), encoding="utf-8")
        return str(path)

    def run_spec(self, *entries: dict[str, object]) -> int:
        return mutants.main(self.spec(*entries), root=self.work)

    def assert_clean_end(self) -> None:
        """No scratch worktree left, registered or on disk, and the task's tree is HEAD, unchanged."""
        listed = git(self.work, "worktree", "list", "--porcelain")
        self.assertEqual(listed.count("worktree "), 1, listed)
        folder = self.work / "tools" / "out" / "mutants"
        self.assertEqual([p.name for p in folder.glob("tree-*") if p.is_dir()], [])
        self.assertEqual(git(self.work, "status", "--porcelain", "--untracked-files=all"), "")
        self.assertEqual(git(self.work, "rev-parse", "HEAD").strip(), self.head)
        self.assertEqual((self.work / "core" / "cooldown.gd").read_bytes(), SOURCE.encode("utf-8"))

    def report(self) -> str:
        return (self.work / "tools" / "out" / "mutants" / "spec.md").read_text(encoding="utf-8")


class RunTest(RepoCase):
    def test_the_mutants_run_in_a_scratch_tree_and_the_task_tree_stays_untouched(self) -> None:
        self.write(".godot/cache.cfg", "cached\n")  # ignored, like the real import cache
        self.assertEqual(self.run_spec(BOUNDARY, ALWAYS), mutants.DONE)
        self.assertEqual(len(self.imports), 1, "one import for the whole run")
        self.assertEqual(self.imports[0], self.tree)
        baseline, boundary, always = self.calls
        self.assertEqual(baseline["paths"], ["tests/unit/cooldown_test.gd"])
        self.assertEqual(baseline["planted"], SOURCE, "the baseline runs HEAD without a mutant")
        self.assertIn("> 10", str(boundary["planted"]))
        self.assertIn("return true", str(always["planted"]))
        for call in self.calls:
            self.assertEqual(call["tree"], self.tree)
            self.assertTrue(call["registered"], "a git worktree of its own")
            self.assertTrue(call["cache"], "the .godot import cache was copied in")
            self.assertEqual(call["task"], SOURCE, "the task's own file never changes")
        self.assert_clean_end()
        report = self.report()
        self.assertIn(f"mutants of {self.head[:10]} (spec.json)", report)
        self.assertIn("| 1 | `core/cooldown.gd:5` `>= 10` -> `> 10` | killed | cooldown_test::test_boundary |", report)
        self.assertIn("| 2 | `core/cooldown.gd:5` `tick - paid_at >= 10` -> `true` | survived |", report)
        self.assertIn("mutants: 1 killed, 1 survived, 0 error", report)
        self.assertIn("the task's tree is unchanged", self.out.getvalue())

    def test_a_dirty_tree_is_refused_before_anything_is_made(self) -> None:
        for name, text in (("core/cooldown.gd", SOURCE + "# edit\n"), ("notes.txt", "untracked\n")):
            with self.subTest(name=name):
                self.write(name, text)
                self.assertEqual(self.run_spec(BOUNDARY), mutants.INVALID)
                self.assertIn("uncommitted changes", self.out.getvalue())
                self.assertEqual(self.calls, [])
                self.assertFalse((self.work / "tools" / "out" / "mutants").exists())
                self.assertEqual(git(self.work, "worktree", "list", "--porcelain").count("worktree "), 1)
                git(self.work, "checkout", "--", ".")
                (self.work / "notes.txt").unlink(missing_ok=True)

    def test_a_leftover_scratch_worktree_is_removed_at_the_next_start(self) -> None:
        # A run killed half-way: its worktree with a planted fault, a folder git no longer knows, and an entry whose
        # folder was deleted by hand.
        git(self.work, "worktree", "add", "-q", "--detach", str(self.tree), "HEAD")
        (self.tree / "core" / "cooldown.gd").write_text("planted\n", encoding="utf-8")
        old = self.work / "tools" / "out" / "mutants" / "tree-old"
        (old / "core").mkdir(parents=True)
        (old / "core" / "x.gd").write_text("x\n", encoding="utf-8")
        gone = self.work / "tools" / "out" / "mutants" / "tree-gone"
        git(self.work, "worktree", "add", "-q", "--detach", str(gone), "HEAD")
        _rmtree(gone)
        # The report of a spec named tree-x.json is a file, never a leftover.
        report = self.work / "tools" / "out" / "mutants" / "tree-x.md"
        report.write_text("an earlier report\n", encoding="utf-8")
        self.assertEqual(self.run_spec(BOUNDARY), mutants.DONE)
        self.assertEqual(self.calls[0]["planted"], SOURCE, "a fresh scratch tree, not the leftover")
        self.assert_clean_end()
        self.assertIn("1 killed", self.report())
        self.assertTrue(report.is_file())

    def test_the_scratch_tree_goes_when_the_test_step_raises(self) -> None:
        def explode(tree: Path, paths: list[str], seconds: float) -> Outcome:
            if "> 10" in (tree / "core" / "cooldown.gd").read_text(encoding="utf-8"):
                raise RuntimeError("the test step crashed")
            return self.fake_test(tree, paths, seconds)

        with mock.patch.object(mutants, "test_step", side_effect=explode):
            self.assertEqual(self.run_spec(BOUNDARY), mutants.INVALID, "a crash is a run that could not finish")
        self.assert_clean_end()
        self.assertIn("stopped: RuntimeError: the test step crashed", self.report())
        self.assertIn("| 1 | `core/cooldown.gd:5` `>= 10` -> `> 10` | not run |", self.report())
        self.assertIn("the task's tree is unchanged", self.out.getvalue())
        # The lock went with the run: the next one works.
        self.assertEqual(self.run_spec(BOUNDARY), mutants.DONE)
        self.assert_clean_end()

    def stuck_at_the_end(self) -> mock._patch:  # type: ignore[type-arg]
        """remove_trees that removes the tree but reports it left at the end of the run (its second call)."""
        real = mutants.remove_trees
        removals: list[int] = []

        def stuck(root: Path) -> list[str]:
            left = real(root)
            removals.append(1)
            return left + (["tools/out/mutants/tree-work"] if len(removals) == 2 else [])

        return mock.patch.object(mutants, "remove_trees", side_effect=stuck)

    def test_a_crash_with_a_stuck_scratch_tree_exits_2(self) -> None:
        for crash in (RuntimeError("the test step crashed"), OSError("disk full"), KeyboardInterrupt()):
            with self.subTest(crash=type(crash).__name__):
                with mock.patch.object(mutants, "test_step", side_effect=crash), self.stuck_at_the_end():
                    self.assertEqual(self.run_spec(BOUNDARY), mutants.LEFTOVER)
                self.assertIn("EXIT 2: the scratch worktree could not be removed", self.report())
                self.assertIn(f"stopped: {type(crash).__name__}", self.report())

    def test_ctrl_c_still_cleans_up_and_keeps_its_own_exit(self) -> None:
        with mock.patch.object(mutants, "test_step", side_effect=KeyboardInterrupt()):
            with self.assertRaises(KeyboardInterrupt):
                self.run_spec(BOUNDARY)
        self.assert_clean_end()
        self.assertIn("stopped: KeyboardInterrupt", self.report())
        self.assertIn("the task's tree is unchanged", self.out.getvalue())

    def test_a_failed_import_stops_the_run_with_exit_1_and_cleans_up(self) -> None:
        with mock.patch.object(mutants, "import_step", side_effect=mutants.Failure("the import broke")):
            self.assertEqual(self.run_spec(BOUNDARY), mutants.INVALID)
        self.assertEqual(self.calls, [])
        self.assert_clean_end()
        self.assertIn("stopped: the import broke", self.report())
        self.assertIn("| 1 | `core/cooldown.gd:5` `>= 10` -> `> 10` | not run |", self.report())

    def test_a_scratch_tree_that_cannot_be_removed_exits_2(self) -> None:
        with self.stuck_at_the_end():
            self.assertEqual(self.run_spec(BOUNDARY), mutants.LEFTOVER)
        self.assertIn("could not be removed (exit 2)", self.out.getvalue())
        self.assertIn("EXIT 2: the scratch worktree could not be removed", self.report())

    def test_a_leftover_that_cannot_be_removed_at_the_start_exits_2(self) -> None:
        with mock.patch.object(mutants, "remove_trees", return_value=["tools/out/mutants/tree-work"]):
            self.assertEqual(self.run_spec(BOUNDARY), mutants.LEFTOVER)
        self.assertEqual(self.calls, [])
        self.assertIn("left by an earlier run cannot be removed", self.out.getvalue())

    def test_a_change_to_the_task_tree_exits_2(self) -> None:
        def stray(tree: Path, paths: list[str], seconds: float) -> Outcome:
            self.write("stray.txt", "x\n")
            return self.fake_test(tree, paths, seconds)

        with mock.patch.object(mutants, "test_step", side_effect=stray):
            self.assertEqual(self.run_spec(BOUNDARY), mutants.LEFTOVER)
        self.assertIn("the task's git status changed", self.out.getvalue())
        self.assertEqual(git(self.work, "worktree", "list", "--porcelain").count("worktree "), 1)

    def test_another_run_in_the_checkout_is_refused(self) -> None:
        held = mutants.Lock(self.work / "tools" / "out" / "mutants" / "lock")
        held.acquire()
        try:
            self.assertEqual(self.run_spec(BOUNDARY), mutants.INVALID)
        finally:
            held.release()
        self.assertIn("another mutants run is active", self.out.getvalue())
        self.assertEqual(self.calls, [])
        self.assertEqual(self.run_spec(BOUNDARY), mutants.DONE)

    def test_a_red_baseline_makes_every_mutant_an_error(self) -> None:
        red = Outcome(1, "  FAIL  exit 100: tests failed\n", tests=3, failing=["cooldown_test::test_flaky"])
        with mock.patch.object(mutants, "test_step", return_value=red) as step:
            self.assertEqual(self.run_spec(BOUNDARY, ALWAYS), mutants.DONE)
        self.assertEqual(step.call_count, 1, "no mutant runs on a red baseline")
        report = self.report()
        self.assertEqual(report.count("| error | red baseline: failing without a mutant: cooldown_test::test_flaky"), 2)
        self.assertIn("baseline RED", report)
        self.assert_clean_end()


class SpecTest(RepoCase):
    def problems(self, raw: str) -> str:
        path = self.tmp / "bad.json"
        path.write_text(raw, encoding="utf-8")
        self.assertEqual(mutants.main(str(path), root=self.work), mutants.INVALID, raw)
        self.assertEqual(self.calls, [])
        self.assertFalse((self.work / "tools" / "out" / "mutants").exists(), "an invalid spec makes nothing")
        return self.out.getvalue()

    def test_invalid_specs_are_refused_with_every_problem(self) -> None:
        cases = [
            ("{", "is not JSON"),
            ("[]", 'one key, "mutants"'),
            ('{"mutants": []}', "at least one mutant"),
            ('{"mutants": [1]}', "mutant 1: an object with file, line"),
            (json.dumps({"mutants": [{**BOUNDARY, "test": []}]}), "mutant 1: unknown key 'test'"),
            (json.dumps({"mutants": [{k: v for k, v in BOUNDARY.items() if k != "tests"}]}), "mutant 1: no 'tests'"),
            (json.dumps({"mutants": [{**BOUNDARY, "file": "tests/unit/cooldown_test.gd"}]}), "outside core/"),
            (json.dumps({"mutants": [{**BOUNDARY, "file": "content/modes/base.tres"}]}), "(production code only)"),
            (json.dumps({"mutants": [{**BOUNDARY, "file": "core/../core/cooldown.gd"}]}), "not a repo-relative"),
            (json.dumps({"mutants": [{**BOUNDARY, "file": "C:/work/core/cooldown.gd"}]}), "not a repo-relative"),
            (json.dumps({"mutants": [{**BOUNDARY, "file": "core/missing.gd"}]}), "not a tracked file of HEAD"),
            (json.dumps({"mutants": [{**BOUNDARY, "line": 0}]}), "line must be a whole number"),
            (json.dumps({"mutants": [{**BOUNDARY, "line": "5"}]}), "line must be a whole number"),
            (json.dumps({"mutants": [{**BOUNDARY, "line": True}]}), "line must be a whole number"),
            (json.dumps({"mutants": [{**BOUNDARY, "line": 9}]}), "core/cooldown.gd has 5 lines, not 9"),
            (json.dumps({"mutants": [{**BOUNDARY, "line": 4}]}), "is not on line 4 of core/cooldown.gd, which reads"),
            (json.dumps({"mutants": [{**BOUNDARY, "original": "t"}]}), "starts 3 times on line 5"),
            (json.dumps({"mutants": [{**BOUNDARY, "original": ""}]}), "original must be non-empty"),
            (json.dumps({"mutants": [{**BOUNDARY, "replacement": ">= 10"}]}), "replacement equals original"),
            (json.dumps({"mutants": [{**BOUNDARY, "replacement": None}]}), "replacement must be text"),
            (json.dumps({"mutants": [{**BOUNDARY, "tests": []}]}), "at least one test file or folder"),
            (json.dumps({"mutants": [{**BOUNDARY, "tests": ["core/cooldown.gd"]}]}), "is not a path under tests/"),
            (json.dumps({"mutants": [{**BOUNDARY, "tests": ["tests/scratch/p_test.gd"]}]}), "not tracked in HEAD"),
        ]
        for raw, expected in cases:
            with self.subTest(expected=expected):
                self.out.truncate(0)
                self.out.seek(0)
                self.assertIn(expected, self.problems(raw))
        # Every problem of every mutant at once, then the hint.
        text = self.problems(json.dumps({"mutants": [{**BOUNDARY, "line": 0}, {**ALWAYS, "tests": []}]}))
        self.assertIn("mutant 1: line must be", text)
        self.assertIn("mutant 2: tests must be", text)
        self.assertIn("invalid spec: nothing ran", text)

    def test_paths_are_normalized_and_an_original_may_span_lines(self) -> None:
        spanning = {
            **BOUNDARY,
            "file": "res://core\\cooldown.gd",
            "line": 4,
            "original": "-> bool:\n\treturn",
            "replacement": "",
            "tests": ["res://tests/unit/", "tests/unit/cooldown_test.gd", "./tests/unit/cooldown_test.gd"],
        }
        path = self.spec(spanning)
        (found,) = mutants.load_spec(Path(path), self.work)
        self.assertEqual(found.file, "core/cooldown.gd")
        self.assertEqual(found.tests, ["tests/unit", "tests/unit/cooldown_test.gd"])
        self.assertEqual(self.run_spec(spanning), mutants.DONE)
        self.assertNotIn("-> bool:", str(self.calls[1]["planted"]))
        self.assert_clean_end()

    def test_a_spec_written_with_a_bom_reads(self) -> None:
        path = self.tmp / "bom.json"
        path.write_bytes(b"\xef\xbb\xbf" + json.dumps({"mutants": [BOUNDARY]}).encode("utf-8"))
        self.assertEqual(len(mutants.load_spec(path, self.work)), 1)


class LocateTest(unittest.TestCase):
    def test_locate(self) -> None:
        self.assertEqual(mutants.locate(SOURCE, 5, ">= 10"), [SOURCE.index(">= 10")])
        self.assertEqual(mutants.locate(SOURCE, 4, ">= 10"), [])
        self.assertEqual(mutants.locate(SOURCE, 6, "x"), [], "the empty line after the last newline is no line")
        self.assertEqual(mutants.locate("a\nab", 2, "a"), [2])
        self.assertEqual(mutants.locate("aa\n", 1, "a"), [0, 1])
        self.assertEqual(mutants.locate("ab\ncd\n", 1, "b\nc"), [1])
        self.assertEqual([mutants.line_count(t) for t in ("", "a", "a\n", "a\nb", "a\n\n")], [0, 1, 1, 2, 2])


class JudgeTest(unittest.TestCase):
    FILE = "core/combat/cooldown.gd"

    def judge(self, outcome: Outcome) -> tuple[str, list[str], str]:
        return mutants.judge(outcome, self.FILE, 300)

    def test_verdicts(self) -> None:
        self.assertEqual(self.judge(Outcome(1, tests=7, failing=["a::t1", "a::t2"])), (KILLED, ["a::t1", "a::t2"], ""))
        self.assertEqual(self.judge(Outcome(0, tests=7)), (SURVIVED, [], ""))
        result, _, reason = self.judge(Outcome(1, timed_out=True))
        self.assertEqual((result, reason[:20]), (ERROR, "timed out after 300 "))
        parse = f'SCRIPT ERROR: Parse Error: Could not parse global class "Cooldown" from "res://{self.FILE}".'
        result, failing, reason = self.judge(Outcome(1, "  FAIL  exit 105\n", tests=-1, godot=parse))
        self.assertEqual((result, failing), (ERROR, []))
        self.assertIn("the mutant does not compile: SCRIPT ERROR: Parse Error", reason)
        # A parse error of another file does not count as the mutant's own.
        self.assertEqual(self.judge(Outcome(1, godot="Parse Error in res://core/x.gd", failing=["a::t"]))[0], KILLED)
        orphans = Outcome(1, "  FAIL  exit 101: orphan nodes detected\n  FAIL  a::t: 1 orphan node(s)\n", tests=7)
        self.assertEqual(self.judge(orphans), (ERROR, [], "exit 101: orphan nodes detected; a::t: 1 orphan node(s)"))
        self.assertEqual(self.judge(Outcome(0, tests=0)), (ERROR, [], "no tests ran"))
        self.assertEqual(self.judge(Outcome(1, "boom\n")), (ERROR, [], "exit 1 without a failed test: boom"))

    def test_the_kept_log_replaces_the_scratch_trees(self) -> None:
        reason = "no results.xml written; log: tools/out/logs/test.log"
        kept = "tools/out/mutants/m-1.log"
        self.assertEqual(mutants._with_log(reason, kept), f"no results.xml written; log: {kept}")
        self.assertEqual(mutants._with_log("no tests ran", kept), f"no tests ran (log: {kept})")

    def test_failing_tests_from_results_xml(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "results.xml"
            path.write_text(
                '<testsuites><testsuite name="a_test">'
                '<testcase name="t1" classname="a_test"><failure message="x">body</failure></testcase>'
                '<testcase name="t2" classname="a_test"></testcase>'
                '<testcase name="t3" classname="a_test"><error message="y"/></testcase>'
                "</testsuite></testsuites>",
                encoding="utf-8",
            )
            self.assertEqual(mutants.read_results(path), (3, ["a_test::t1", "a_test::t3"]))
            path.write_text("<testsuites", encoding="utf-8")
            self.assertEqual(mutants.read_results(path), (-1, []))


class TableTest(unittest.TestCase):
    def test_cells_escape_pipes_and_show_newlines(self) -> None:
        mutant = mutants.Mutant(3, "core/a.gd", 9, "a || b\nc", "", ["tests/unit"], ERROR, [], "x | y", 1.25)
        (row,) = mutants.table([mutant])[2:]
        self.assertEqual(row, "| 3 | `core/a.gd:9` `a \\|\\| b\\nc` -> (nothing) | error | x \\| y | 1.2 |")
        many = mutants.Mutant(1, "core/a.gd", 1, "`x`", "y", ["tests/unit"], KILLED, ["s::a", "s::b", "s::c", "s::d"])
        self.assertIn("`` `x` `` -> `y` | killed | s::a, s::b, s::c and 1 more |", mutants.table([many])[2])


class StepTest(unittest.TestCase):
    def test_the_scratch_step_matches_the_runner_it_calls(self) -> None:
        """STEP runs HEAD's runner in the scratch tree; selftest checks it compiles and calls what exists."""
        compile(mutants.STEP, "<mutants step>", "exec")
        self.assertIn("run_import", mutants.STEP)
        self.assertTrue(callable(check.run_import))
        self.assertIn("run_import", inspect.signature(gdunit.main).parameters)
        self.assertIn("paths", inspect.signature(gdunit.main).parameters)

    def test_a_step_never_reads_the_previous_steps_results(self) -> None:
        """A child that stops before it writes results (or clears the old ones) gets no verdict from them."""
        with tempfile.TemporaryDirectory() as folder:
            tree = Path(folder)
            old = tree / "tools" / "out" / "gdunit" / "report_1" / "results.xml"
            old.parent.mkdir(parents=True)
            old.write_text(
                '<testsuites><testsuite name="a_test"><testcase name="t1" classname="a_test"/></testsuite></testsuites>',
                encoding="utf-8",
            )
            log = tree / "tools" / "out" / "logs" / "test.log"
            log.parent.mkdir(parents=True)
            log.write_text("the previous step's log\n", encoding="utf-8")
            with mock.patch.object(mutants, "_step", return_value=(1, "Traceback: early exit\n", False)):
                outcome = mutants.test_step(tree, ["tests/unit"], 300)
            self.assertEqual((outcome.rc, outcome.tests, outcome.failing, outcome.godot), (1, -1, [], ""))
            self.assertEqual(mutants.judge(outcome, "core/a.gd", 300)[0], ERROR)


class LockTest(unittest.TestCase):
    def test_one_holder_at_a_time(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            first, second = mutants.Lock(Path(folder) / "m" / "lock"), mutants.Lock(Path(folder) / "m" / "lock")
            first.acquire()
            with self.assertRaises(mutants.Failure):
                second.acquire()
            first.release()
            second.acquire()
            second.release()


class CliTest(unittest.TestCase):
    def test_the_command_and_its_help(self) -> None:
        args = cli.build_parser().parse_args(["mutants", "m.json", "--seconds", "30"])
        self.assertEqual((args.command, args.spec, args.seconds), ("mutants", "m.json", 30))
        self.assertEqual(cli.build_parser().parse_args(["mutants", "m.json"]).seconds, mutants.TEST_SECONDS)
        with mock.patch.object(mutants, "main", return_value=2) as run:
            self.assertEqual(cli.main(["mutants", "m.json"]), 2)
        run.assert_called_once_with("m.json", seconds=mutants.TEST_SECONDS)
        for key in (*mutants.KEYS, "exit codes:", "  0  the run completed", "  1  an invalid spec", "  2  the scratch"):
            self.assertIn(key, mutants.HELP)


class GuardTest(unittest.TestCase):
    """The runner's own git commands are not shell commands of the session, so only its command line is judged: it
    runs without a prompt from a task worktree and from the main checkout, in the modes that prompt too."""

    MAIN = "D:\\prime-game"
    WORKTREE = MAIN + "\\.claude\\worktrees\\184"
    PAD = "C:\\Users\\me\\AppData\\Local\\Temp\\claude\\D--prime-game\\s\\scratchpad\\a184"

    def test_the_command_passes_without_a_prompt(self) -> None:
        rules = permissions.Rules.load(ROOT / ".claude" / "settings.json")
        bash_pad = "/c/Users/me/AppData/Local/Temp/claude/D--prime-game/s/scratchpad/a184"
        calls = [
            ("Bash", self.WORKTREE, f"cd /d/prime-game/.claude/worktrees/184 && tools/run.sh mutants {bash_pad}/m1.json"),
            ("PowerShell", self.WORKTREE, f"Set-Location D:/prime-game/.claude/worktrees/184; tools\\run.cmd mutants {self.PAD}\\m1.json"),
            ("PowerShell", self.MAIN, f"tools\\run.cmd mutants {self.PAD}\\m1.json"),
            ("Bash", self.MAIN, "tools/run.sh mutants --help"),
            ("Bash", self.WORKTREE, "tools/run.sh mutants tests/scratch/m1.json"),
        ]  # fmt: skip
        for tool, cwd, command in calls:
            with self.subTest(command=command):
                verdict = permissions.verdict(rules, guard, tool, command, cwd, self.MAIN, guard.NoRepo(), False)
                self.assertEqual(verdict[0], permissions.PASS, verdict)


if __name__ == "__main__":
    unittest.main()
