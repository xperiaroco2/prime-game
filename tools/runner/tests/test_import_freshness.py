"""The import before a launch (#174): `host`, `join`, `run`, `playcheck`, `perf`, `bots` and `shot` import the project
first when a file Godot sees changed after the last import through the runner.

The engineer's playtest: after `git switch` brought new class_name scripts, `host` printed `Identifier "MousePointer"
not declared` in every window, since only an import rebuilds Godot's global class cache. RealStaleCacheTest
reproduces that in a throwaway project with the pinned Godot; the other tests need none.
"""

import io
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from runner import check, common, hostjoin, launch, playcheck, shot
from runner.common import Failure, Result, godot_bin
from runner.verify import starts_godot

PROJECT = 'config_version=5\n\n[application]\n\nconfig/name="PrimeGame"\n'
ALPHA = 'class_name Alpha\nextends RefCounted\n\n\nstatic func word() -> String:\n\treturn "alpha"\n'
BETA = 'class_name Beta\nextends RefCounted\n\n\nstatic func word() -> String:\n\treturn "beta"\n'
MAIN = 'extends SceneTree\n\n\nfunc _initialize() -> void:\n\tprint("PROBE word=", {cls}.word())\n\tquit(0)\n'


def project(parent: Path, *, linked: bool = False) -> Path:
    """A project folder with one class_name script; a linked worktree has a .git file (common.is_linked_worktree)."""
    root = parent / "project"
    root.mkdir()
    if linked:
        (root / ".git").write_text(f"gitdir: {parent.as_posix()}/.git/worktrees/project\n", encoding="utf-8")
    (root / "project.godot").write_text(PROJECT, encoding="utf-8")
    (root / "alpha.gd").write_text(ALPHA, encoding="utf-8")
    return root


def imported(root: Path, *, at: float) -> None:
    """What an import through the runner leaves: the class cache and the stamp of when it started."""
    (root / ".godot").mkdir(exist_ok=True)
    (root / check.CLASS_CACHE).write_text("list=[]\n", encoding="utf-8")
    check.write_stamp(root, at)


def age(path: Path, seconds: float) -> None:
    """Set a file's modification time `seconds` before now."""
    when = time.time() - seconds
    os.utime(path, (when, when))


class FreshnessTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = project(Path(tmp.name))
        for path in (self.root / "project.godot", self.root / "alpha.gd"):
            age(path, 60)

    def test_no_import_yet(self) -> None:
        self.assertIn("no .godot/ yet", check.freshness(self.root).why)
        (self.root / ".godot").mkdir()
        self.assertIn(check.CLASS_CACHE, check.freshness(self.root).why)

    def test_an_import_the_runner_did_not_record_counts_as_stale(self) -> None:
        # The editor's import, or a runner from before #174: one import through the runner records it.
        imported(self.root, at=time.time())
        (self.root / check.STAMP).unlink()
        self.assertIn(check.STAMP, check.freshness(self.root).why)

    def test_current_after_an_import(self) -> None:
        imported(self.root, at=time.time())
        state = check.freshness(self.root)
        self.assertEqual(state.why, "")
        self.assertEqual(state.files, 2)  # project.godot and alpha.gd; .godot/ is hidden

    def test_a_new_class_name_script_after_the_import_makes_it_stale(self) -> None:
        imported(self.root, at=time.time() - 30)
        (self.root / "client").mkdir()
        (self.root / "client" / "beta.gd").write_text(BETA, encoding="utf-8")
        state = check.freshness(self.root)
        self.assertEqual(state.why, "res://client/beta.gd changed after the last import")
        self.assertEqual(state.newest_path, "client/beta.gd")

    def test_a_changed_asset_or_project_setting_makes_it_stale(self) -> None:
        for name in ("icon.png", "project.godot", "override.cfg", "level.tscn", "alpha.gd.uid"):
            with self.subTest(name=name):
                imported(self.root, at=time.time() - 30)
                (self.root / name).write_bytes(b"x")
                self.assertIn(f"res://{name} changed", check.freshness(self.root).why)
                age(self.root / name, 60)

    def test_files_godot_never_imports_or_never_sees_do_not_count(self) -> None:
        imported(self.root, at=time.time() - 30)
        for name in ("docs/GDD.md", "tools/runner/x.py", ".claude/worktrees/9/a.gd", "tools/out/logs/run.log"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("x", encoding="utf-8")
        (self.root / "tools/out/.gdignore").write_text("", encoding="ascii")
        (self.root / "tools/out/shot.png").write_bytes(b"x")  # under a .gdignore: Godot skips the folder
        self.assertEqual(check.freshness(self.root).why, "")

    def test_the_import_records_when_it_started(self) -> None:
        (self.root / ".godot").mkdir()
        before = time.time()
        with mock.patch.object(common, "ROOT", self.root), \
                mock.patch.object(check, "godot", return_value=Result(0, "", False, 0.1)):  # fmt: skip
            check.run_import("x")
        stamp = check.stamp_time(self.root)
        assert stamp is not None
        self.assertGreaterEqual(stamp, before)
        self.assertLessEqual(stamp, time.time())

    def test_a_file_dated_in_the_future_never_moves_the_stamp_past_the_import(self) -> None:
        """Review of #174: a stamp an hour ahead reported every real change of that hour (a `git switch`, a new
        class_name script) as `current`. The stamp stays at the import's end; the file makes each launch import."""
        (self.root / ".godot").mkdir()
        (self.root / "alpha.gd.uid").write_text("uid://b1\n", encoding="ascii")
        age(self.root / "alpha.gd.uid", -3600)  # copied with its original time, from a machine whose clock is ahead
        with mock.patch.object(common, "ROOT", self.root), \
                mock.patch.object(check, "godot", return_value=Result(0, "", False, 0.1)):  # fmt: skip
            check.run_import("x")
        stamp = check.stamp_time(self.root)
        assert stamp is not None
        self.assertLessEqual(stamp, time.time())
        (self.root / check.CLASS_CACHE).write_text("list=[]\n", encoding="utf-8")
        state = check.freshness(self.root)
        self.assertRegex(state.why, r"^res://alpha\.gd\.uid is dated \d+s in the future, so every launch imports")
        self.assertIn("(touch alpha.gd.uid)", state.why)
        age(self.root / "alpha.gd.uid", 60)  # touched (here: dated before the import)
        self.assertEqual(check.freshness(self.root).why, "")

    def test_what_the_import_writes_itself_does_not_make_the_next_launch_import_again(self) -> None:
        def fake_godot(*_args: object, **_kwargs: object) -> Result:
            time.sleep(0.05)
            imported(self.root, at=0)
            (self.root / "alpha.gd.uid").write_text("uid://b1\n", encoding="ascii")
            (self.root / "icon.png.import").write_text("[remap]\n", encoding="ascii")
            return Result(0, "", False, 0.1)

        (self.root / "icon.png").write_bytes(b"x")
        age(self.root / "icon.png", 60)
        with mock.patch.object(common, "ROOT", self.root), mock.patch.object(check, "godot", fake_godot):
            check.run_import("x")
        self.assertEqual(check.freshness(self.root).why, "")
        (self.root / "beta.gd").write_text(BETA, encoding="utf-8")  # a change after the import still counts
        # NTFS keeps a coarse clock: no tie with the stamp, and not in the future either (that is a warning)
        stamp = check.stamp_time(self.root)
        assert stamp is not None
        os.utime(self.root / "beta.gd", (stamp + 0.001, stamp + 0.001))
        time.sleep(0.02)
        self.assertIn("res://beta.gd changed", check.freshness(self.root).why)

    def test_the_stamp_keeps_the_exact_time(self) -> None:
        # Rounded to microseconds, it fell below a .uid file the import had just written: a flaky extra import.
        (self.root / ".godot").mkdir()
        for when in (1759400000.1234564, 1759400000.9999996, 0.5):
            check.write_stamp(self.root, when)
            self.assertEqual(check.stamp_time(self.root), when)

    def test_a_broken_import_records_nothing(self) -> None:
        (self.root / ".godot").mkdir()
        with mock.patch.object(common, "ROOT", self.root), mock.patch.object(check, "warn"), \
                mock.patch.object(check, "godot", return_value=Result(3, "", False, 0.1)):  # fmt: skip
            with self.assertRaises(Failure):
                check.run_import("x")
        self.assertIsNone(check.stamp_time(self.root))


class EnsureImportTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.parent = Path(tmp.name)

    def ensure(self, root: Path, run_import: mock.MagicMock) -> str:
        with mock.patch.object(common, "ROOT", root), mock.patch.object(check, "run_import", run_import), \
                mock.patch("sys.stdout", new_callable=io.StringIO) as out:  # fmt: skip
            check.ensure_import()
        return out.getvalue()

    def test_current_says_so_in_one_line_and_starts_no_godot(self) -> None:
        root = project(self.parent)
        imported(root, at=time.time() + 1)
        run_import = mock.MagicMock()
        said = self.ensure(root, run_import).splitlines()
        run_import.assert_not_called()
        self.assertEqual(len(said), 1, said)
        self.assertRegex(said[0], r"^        import: current \(2 project files unchanged since the last import, ")

    def test_stale_names_the_file_and_imports_first(self) -> None:
        root = project(self.parent)
        imported(root, at=time.time() - 30)
        for path in (root / "project.godot", root / "alpha.gd"):
            age(path, 60)  # older than the stamp: only beta.gd is stale, whatever the walk order
        (root / "beta.gd").write_text(BETA, encoding="utf-8")
        run_import = mock.MagicMock()
        said = self.ensure(root, run_import)
        self.assertIn("import: res://beta.gd changed after the last import; importing the project first", said)
        self.assertIn("import: done in ", said)
        run_import.assert_called_once_with("run-import")

    def test_a_file_dated_in_the_future_is_a_warning_and_still_imports(self) -> None:
        root = project(self.parent)
        imported(root, at=time.time())
        age(root / "alpha.gd", -3600)
        run_import = mock.MagicMock()
        said = self.ensure(root, run_import)
        self.assertRegex(said, r"  warn  import: res://alpha\.gd is dated \d+s in the future")
        self.assertIn("(touch alpha.gd); importing the project first", said)
        run_import.assert_called_once_with("run-import")

    def test_in_a_linked_worktree_the_import_sees_the_override(self) -> None:
        """#182 gives a linked worktree its own user:// through override.cfg: it is written before the walk and the
        import, so the import runs with it, and its own creation does not make the next launch import again."""
        root = project(self.parent, linked=True)
        starts: list[list[str]] = []

        def fake_run(cmd: list[str], **_kwargs: object) -> Result:
            self.assertTrue((root / common.OVERRIDE).is_file(), "override.cfg must exist when the import starts")
            starts.append(cmd)
            imported(root, at=time.time())  # what Godot writes; run_import then rewrites the stamp
            return Result(0, "", False, 0.1)

        with (
            mock.patch.object(common, "ROOT", root),
            mock.patch.object(common, "godot_bin", return_value="godot"),
            mock.patch.object(common, "check_godot_version"),
            mock.patch.object(common, "run", fake_run),
            mock.patch("sys.stdout", new_callable=io.StringIO) as out,
        ):
            check.ensure_import()
            check.ensure_import()
        self.assertEqual(len(starts), 1, out.getvalue())
        self.assertEqual(starts[0][1:], ["--no-header", "--path", str(root), "--headless", "--import"])
        self.assertIn("import: no .godot/ yet", out.getvalue())
        self.assertIn("import: current (3 project files", out.getvalue())  # override.cfg among them


class EveryLaunchImportsFirstTest(unittest.TestCase):
    """Each command that starts the game finds Godot (which writes a worktree's override.cfg), then imports if
    needed, then starts it. `perf` and `bots` start through `run` (launch.main; test_perf, test_bots)."""

    def setUp(self) -> None:
        self.order: list[str] = []
        out = mock.patch("sys.stdout", new_callable=io.StringIO)
        out.start()
        self.addCleanup(out.stop)

    def step(self, name: str, value: object = None) -> mock.MagicMock:
        def record(*_args: object, **_kwargs: object) -> object:
            self.order.append(name)
            return value

        return mock.MagicMock(side_effect=record)

    def test_run(self) -> None:
        with (
            mock.patch.object(launch, "require_godot", self.step("godot", "godot")),
            mock.patch.object(launch, "ensure_import", self.step("import")),
            mock.patch.object(launch, "launch", self.step("start", [])),
            mock.patch.object(launch, "report", return_value=0),
        ):
            self.assertEqual(launch.main("tools/run/probe.gd", headless=True), 0)
        self.assertEqual(self.order, ["godot", "import", "start"])

    def test_host_join_and_verifys_game_step(self) -> None:
        for name, call in (
            ("host", lambda: hostjoin.host(port=None, clients=1, local=True, seconds=1, headless=True)),
            ("join", lambda: hostjoin.join("127.0.0.1", port=None, seconds=1, headless=True)),
            ("game", lambda: hostjoin.game_check(24998, seconds=1)),
        ):
            with self.subTest(command=name):
                self.order.clear()
                with (
                    mock.patch.object(hostjoin, "require_godot", self.step("godot", "godot")),
                    mock.patch.object(hostjoin.launch, "ensure_import", self.step("import")),
                    mock.patch.object(hostjoin, "supervise", self.step("start")),
                    mock.patch.object(hostjoin, "write_logs"),
                    mock.patch.object(hostjoin, "report", return_value=0),
                ):
                    self.assertEqual(call(), 0)
                self.assertEqual(self.order, ["godot", "import", "start"])

    def test_playcheck(self) -> None:
        with (
            mock.patch.object(playcheck, "IS_CI", False),
            mock.patch.object(shot, "has_display", return_value=True),
            mock.patch.object(playcheck, "require_godot", self.step("godot", "godot")),
            mock.patch.object(playcheck.launch, "ensure_import", self.step("import")),
            mock.patch.object(playcheck, "run_one", self.step("start", 0)),
        ):
            self.assertEqual(playcheck.main(["esc_menu"]), 0)
        self.assertEqual(self.order, ["godot", "import", "start"])

    def test_shot(self) -> None:
        # shot starts Godot through common.godot (require_godot inside); ensure_import writes the override itself.
        with (
            mock.patch.object(shot, "has_display", return_value=True),
            mock.patch.object(shot, "ensure_import", self.step("import")),
            mock.patch.object(shot, "godot", self.step("start", Result(1, "SHOT error x\n", False, 0.1))),
        ):
            with self.assertRaises(Failure):
                shot.main("tools/shot/probe.tscn", out=str(Path(tempfile.gettempdir()) / "a174-never.png"))
        self.assertEqual(self.order, ["import", "start"])


@starts_godot
@unittest.skipUnless(godot_bin(), "needs Godot (GODOT_BIN); CI has it")
class RealStaleCacheTest(unittest.TestCase):
    """The playtest's failure with the pinned Godot, in a throwaway project: a class_name script that arrived after
    the last import is unknown to a game started without an import, and `run` imports first and passes."""

    def test_a_new_class_name_script_after_the_import(self) -> None:
        # A killed engine may still hold files of the temp project for a moment on Windows.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            root = project(Path(tmp))
            (root / "main.gd").write_text(MAIN.format(cls="Alpha"), encoding="utf-8")
            logs = Path(tmp) / "logs"
            logs.mkdir()

            def run_main() -> tuple[int, str]:
                with (
                    mock.patch.object(common, "ROOT", root),
                    mock.patch.object(common, "LOGS", logs),
                    mock.patch.object(launch, "ROOT", root),
                    mock.patch.object(launch, "LOGS", logs),
                    mock.patch("sys.stdout", new_callable=io.StringIO) as out,
                ):
                    code = launch.main("main.gd", headless=True, seconds=60)
                return code, out.getvalue()

            code, said = run_main()
            self.assertEqual(code, 0, said)
            self.assertIn("import: no .godot/ yet", said)
            self.assertIn("PROBE word=alpha", said)

            # What `git switch` did in the playtest: a new class_name script and a script that uses it.
            (root / "beta.gd").write_text(BETA, encoding="utf-8")
            (root / "main.gd").write_text(MAIN.format(cls="Beta"), encoding="utf-8")
            cmd = launch.command(str(godot_bin()), root, "res://main.gd", headless=True, offscreen=False,
                                 audio="dummy", user_args=[])  # fmt: skip
            stale = common.run(cmd, timeout=60, cwd=root)
            self.assertNotIn("PROBE word=beta", stale.out)
            self.assertIn('Identifier "Beta" not declared', stale.out)

            code, said = run_main()
            self.assertEqual(code, 0, said)
            self.assertIn("changed after the last import; importing the project first", said)
            self.assertIn("PROBE word=beta", said)

            code, said = run_main()
            self.assertEqual(code, 0, said)
            self.assertIn("import: current", said)


if __name__ == "__main__":
    unittest.main()
