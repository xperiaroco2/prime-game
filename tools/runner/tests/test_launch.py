"""`run`: the paths it takes, the Godot command lines it builds, the error scan and the exit code.

The real-Godot test runs tools/run/probe.gd headless in a throwaway project, so it needs no import of this one.
"""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, launch
from runner.verify import starts_godot
from runner.common import ROOT, Failure, Result, godot_bin

PROBE = "tools/run/probe.gd"
SCENE = "tools/shot/probe.tscn"


def instance(rc: int = 0, out: str = "", timed_out: bool = False) -> launch.Instance:
    return launch.Instance(1, ROOT / "tools/out/logs/run/x-1.log", Result(rc, out, timed_out, 0.1), 60)


class PathsAndArgumentsTest(unittest.TestCase):
    def test_paths(self) -> None:
        for name in (PROBE, f"res://{PROBE}", PROBE.replace("/", "\\"), f"./{PROBE}"):
            with self.subTest(name=name):
                self.assertEqual(launch.target_res(name), f"res://{PROBE}")
        self.assertEqual(launch.target_res(SCENE), f"res://{SCENE}")
        for name, text in (
            ("project.godot", "a scene"),
            ("../elsewhere/x.gd", "inside the project"),
            ("tools/out/x.gd", "inside the project"),
            ("tools/run/missing.gd", "not found"),
        ):
            with self.subTest(name=name), self.assertRaises(Failure) as caught:
                launch.target_res(name)
            self.assertIn(text, str(caught.exception))

    def test_headless_script_with_user_args(self) -> None:
        cmd = launch.command(
            "godot", ROOT, "res://a.gd", headless=True, offscreen=False, audio="dummy", user_args=["--role", "host"]
        )
        self.assertEqual(cmd, ["godot", "--no-header", "--path", str(ROOT), "--headless", "-s", "res://a.gd",
                               "--", "--role", "host"])  # fmt: skip

    def test_engine_args_go_before_the_target_and_user_args_after_the_separator(self) -> None:
        cmd = launch.command(
            "godot", ROOT, "res://a.gd", headless=True, offscreen=False, audio="dummy", user_args=["--x=1"],
            engine_args=["--fixed-fps", "60"],
        )  # fmt: skip
        self.assertEqual(cmd[cmd.index("--headless") + 1 :], ["--fixed-fps", "60", "-s", "res://a.gd", "--", "--x=1"])
        scene = launch.command("godot", ROOT, "res://a.tscn", headless=True, offscreen=False, audio="dummy",
                               user_args=[], engine_args=["--fixed-fps", "60"])  # fmt: skip
        self.assertEqual(scene[-3:], ["--fixed-fps", "60", "res://a.tscn"])

    def test_headless_with_real_audio_keeps_the_audio_driver(self) -> None:
        cmd = launch.command("godot", ROOT, "res://a.tscn", headless=True, offscreen=False, audio="default", user_args=[])
        self.assertNotIn("--headless", cmd)
        self.assertEqual(cmd[cmd.index("--display-driver") + 1], "headless")
        self.assertNotIn("--audio-driver", cmd)
        self.assertEqual(cmd[-1], "res://a.tscn")
        self.assertNotIn("--", cmd)

    def test_windowed_scene(self) -> None:
        cmd = launch.command("godot", ROOT, "res://a.tscn", headless=False, offscreen=True, audio="dummy", user_args=[])
        self.assertNotIn("--headless", cmd)
        self.assertEqual(cmd[cmd.index("--position") + 1], "-30000,-30000")
        self.assertEqual(cmd[cmd.index("--audio-driver") + 1], "Dummy")
        self.assertNotIn("-s", cmd)
        visible = launch.command("godot", ROOT, "res://a.tscn", headless=False, offscreen=False, audio="default",
                                 user_args=[])  # fmt: skip
        self.assertNotIn("--position", visible)
        self.assertNotIn("--audio-driver", visible)

    def test_everything_after_the_separator_reaches_the_game(self) -> None:
        argv = ["run", "a.gd", "--headless", "--", "--seconds", "9", "--", "x"]
        self.assertEqual(cli.split_user_args(argv), (["run", "a.gd", "--headless"], ["--seconds", "9", "--", "x"]))
        self.assertEqual(cli.split_user_args(["run", "a.gd"]), (["run", "a.gd"], []))
        self.assertEqual(cli.split_user_args(["check", "--", "x"]), (["check", "--", "x"], []))
        args = cli.build_parser().parse_args(["run", "a.gd", "--headless", "--seconds", "5", "--instances", "3"])
        self.assertEqual((args.target, args.headless, args.seconds, args.instances, args.audio), ("a.gd", True, 5, 3, "dummy"))

    def test_rejects_bad_options(self) -> None:
        for kwargs in (
            {"headless": True, "offscreen": True},
            {"headless": True, "seconds": 0},
            {"headless": True, "instances": 9},
            {"headless": True, "audio": "loud"},
        ):
            with self.subTest(kwargs=kwargs), mock.patch.object(launch, "say"), self.assertRaises(Failure):
                launch.main(PROBE, **kwargs)  # type: ignore[arg-type]
        with mock.patch.object(launch.shot, "has_display", return_value=False), mock.patch.object(launch, "say"):
            with self.assertRaises(Failure) as caught:
                launch.main(PROBE)
        self.assertIn("--headless", str(caught.exception))


class ErrorScanAndExitCodeTest(unittest.TestCase):
    OUTPUT = (
        "PROBE starting, no ERROR: here\n"
        "WARNING: only a warning\n"
        "\x1b[1;31mERROR: first\x1b[0m\n"
        "   at: push_error (core/variant/variant_utility.cpp:1023)\n"
        "   GDScript backtrace (most recent call first):\n"
        "       [0] _ready (res://a.gd:7)\n"
        "       [1] _enter (res://b.gd:3)\n"
        "SCRIPT ERROR: second\n"
        "   at: f (res://a.gd:9)\n"
        "USER ERROR: third\n"
        "SHADER ERROR: fourth\n"
        "USER SCRIPT ERROR: fifth\n"
        "USER SHADER ERROR: sixth\n"
    )

    def test_scan(self) -> None:
        count, shown = launch.error_lines(self.OUTPUT.splitlines())
        self.assertEqual(count, 6)
        self.assertEqual(shown, [
            "ERROR: first",
            "   at: push_error (core/variant/variant_utility.cpp:1023)",
            "       [0] _ready (res://a.gd:7)",
            "SCRIPT ERROR: second",
            "   at: f (res://a.gd:9)",
            "USER ERROR: third",
        ])  # fmt: skip
        self.assertEqual(launch.error_lines(["PROBE ok", "WARNING: x", "  ERROR: indented"]), (0, []))

    def test_problem(self) -> None:
        self.assertEqual(instance(0, "PROBE ok\n").problem, "")
        self.assertEqual(instance(3).problem, "exited 3")
        self.assertIn("timed out after 60s", instance(1, "", timed_out=True).problem)
        self.assertIn("1 engine error line", instance(0, "SCRIPT ERROR: x\n").problem)

    def test_exit_code_is_non_zero_when_any_instance_fails(self) -> None:
        with mock.patch.object(launch, "say"), mock.patch.object(launch, "ok"), mock.patch.object(launch, "bad") as bad:
            self.assertEqual(launch.report("a.gd", [instance(), instance()]), 0)
            bad.assert_not_called()
            for failing in (instance(2), instance(0, "ERROR: boom\n"), instance(1, "", timed_out=True)):
                with self.subTest(problem=failing.problem):
                    self.assertEqual(launch.report("a.gd", [instance(), failing]), 1)
            self.assertIn("ERROR: boom", "\n".join(str(call) for call in bad.call_args_list))

    def test_main_runs_every_instance_and_reports(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            results = iter([Result(0, "PROBE ok\n", False, 0.1), Result(0, "SCRIPT ERROR: x\n", False, 0.1)])
            seen: list[dict[str, str] | None] = []

            def fake_run(cmd: list[str], **kwargs: object) -> Result:
                seen.append(kwargs.get("env"))  # type: ignore[arg-type]
                return next(results)

            with mock.patch.object(launch, "run", fake_run), mock.patch.object(launch, "require_godot", return_value="g"), \
                    mock.patch.object(launch, "ensure_import"), mock.patch.object(launch, "LOGS", Path(tmp)), \
                    mock.patch.object(launch, "say"), \
                    mock.patch.object(launch, "ok"), mock.patch.object(launch, "bad"):  # fmt: skip
                self.assertEqual(launch.main(PROBE, headless=True, instances=2), 1)
            self.assertEqual(sorted((env or {})[launch.INSTANCE_ENV] for env in seen), ["1", "2"])
            self.assertEqual(sorted(p.name for p in (Path(tmp) / "run").iterdir()), ["probe-1.log", "probe-2.log"])

    def test_replaces_only_its_own_logs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp)
            for old in ("lobby-1.log", "lobby-7.log", "lobby-test-1.log", "lobby-x.log"):
                (logs / old).write_text("old", "utf-8")
            with mock.patch.object(launch, "run", return_value=Result(0, "new\n", False, 0.1)):
                launch.launch([["g"]], seconds=5, log_dir=logs, name="lobby")
            self.assertEqual(sorted(p.name for p in logs.iterdir()), ["lobby-1.log", "lobby-test-1.log", "lobby-x.log"])
            self.assertEqual((logs / "lobby-1.log").read_text("utf-8"), "new\n")

    def test_an_exe_that_cannot_start_is_one_clean_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(launch, "run", side_effect=Failure("cannot start g: missing")):
                with self.assertRaises(Failure) as caught:
                    launch.launch([["g"], ["g"]], seconds=5, log_dir=Path(tmp), name="x")
        self.assertIn("cannot start", str(caught.exception))

    def test_window_exe(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            gui = Path(tmp) / "godot-gui.exe"
            gui.write_bytes(b"")
            with mock.patch.dict("os.environ", {"GODOT_GUI_BIN": str(gui)}), \
                    mock.patch.object(launch, "check_godot_version") as check:  # fmt: skip
                self.assertEqual(launch.gui_exe(), str(gui))
            check.assert_called_once_with(str(gui), "GODOT_GUI_BIN")
            with mock.patch.dict("os.environ", {"GODOT_GUI_BIN": str(gui) + ".missing"}):
                with self.assertRaises(Failure) as caught:
                    launch.gui_exe()
            self.assertIn("missing file", str(caught.exception))
        with mock.patch.dict("os.environ", {"GODOT_GUI_BIN": ""}), mock.patch.object(launch, "warn") as warned, \
                mock.patch.object(launch, "require_godot", return_value="console"):  # fmt: skip
            self.assertEqual(launch.gui_exe(), "console")
        warned.assert_called_once()


@starts_godot
@unittest.skipUnless(godot_bin(), "needs Godot (GODOT_BIN); CI has it")
class RealRunTest(unittest.TestCase):
    """tools/run/probe.gd under a real headless Godot, in a throwaway project."""

    def test_probe_modes(self) -> None:
        # A killed engine may still hold files of the temp project for a moment on Windows.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            project = Path(tmp)
            (project / "project.godot").write_text('config_version=5\n\n[application]\nconfig/name="r"\n', "utf-8")
            (project / "probe.gd").write_bytes((ROOT / PROBE).read_bytes())
            logs = project / "logs"

            def go(*user_args: str, instances: int = 1, seconds: int = 60) -> list[launch.Instance]:
                cmd = launch.command(str(godot_bin()), project, "res://probe.gd", headless=True, offscreen=False,
                                     audio="dummy", user_args=list(user_args))  # fmt: skip
                with mock.patch("sys.stdout"):
                    return launch.launch([cmd] * instances, seconds=seconds, log_dir=logs, name="probe", cwd=project)

            passed = go("ok", "--role", "host", "two words", instances=3)
            self.assertEqual([i.problem for i in passed], ["", "", ""], passed[0].result.out)
            self.assertEqual(sorted(p.name for p in logs.iterdir()), ["probe-1.log", "probe-2.log", "probe-3.log"])
            for inst in passed:
                self.assertIn('args=["ok", "--role", "host", "two words"]', inst.result.out)
                self.assertIn(f"instance={inst.number}", inst.result.out)
            self.assertEqual(go("exit", "3")[0].problem, "exited 3")
            for mode in ("error", "script-error"):
                with self.subTest(mode=mode):
                    failed = go(mode)[0]
                    self.assertEqual(failed.result.rc, 0)
                    self.assertIn("engine error line", failed.problem, failed.result.out)
            hung = go("hang", seconds=5)[0]
            self.assertTrue(hung.result.timed_out, hung.result.out)
            self.assertLess(hung.result.seconds, 30)


if __name__ == "__main__":
    unittest.main()
