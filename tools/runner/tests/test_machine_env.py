"""Machine paths from the Claude settings when the process environment lacks them (#55).

Every test builds its own home and project folders in a temporary directory: the real ~/.claude is never read.
"""

import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import doctor, machine_env
from runner.machine_env import LOCAL_SETTINGS, PROCESS, USER_SETTINGS

GODOT = r"C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
GUI = r"C:\Godot\Godot_v4.7.2-stable_win64.exe"
PYTHON = r"C:\Python314\python.exe"
TOOLKIT = r"C:\Python314\Scripts"


def write_settings(path: Path, env: object | None = None, text: str | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {"language": "English", "env": env} if env is not None else {"language": "English"}
    path.write_text(text if text is not None else json.dumps(data, indent=2), encoding="utf-8")


class LoadTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name) / "home"
        self.root = Path(tmp.name) / "project"
        self.home.mkdir()
        self.root.mkdir()
        self.user = self.home / ".claude" / "settings.json"
        self.local = self.root / ".claude" / "settings.local.json"

    def load(self, environ: dict[str, str]) -> machine_env.Report:
        return machine_env.load(environ, self.root, self.home)

    def test_missing_everywhere(self) -> None:
        environ = {"PATH": "x"}
        report = self.load(environ)
        self.assertEqual(environ, {"PATH": "x"})
        self.assertEqual(report.sources, dict.fromkeys(machine_env.MACHINE_VARS))
        self.assertEqual(report.problems, [])
        self.assertEqual(report.searched, [PROCESS, LOCAL_SETTINGS, USER_SETTINGS])

    def test_settings_without_env(self) -> None:
        write_settings(self.user)
        report = self.load({})
        self.assertEqual(report.sources["GODOT_BIN"], None)
        self.assertEqual(report.problems, [])

    def test_from_user_settings(self) -> None:
        write_settings(
            self.user,
            {"GODOT_BIN": GODOT, "GODOT_GUI_BIN": GUI, "PYTHON_BIN": PYTHON, "GDTOOLKIT_DIR": TOOLKIT, "OTHER": "1"},
        )
        environ: dict[str, str] = {}
        report = self.load(environ)
        self.assertEqual(
            environ, {"GODOT_BIN": GODOT, "GODOT_GUI_BIN": GUI, "PYTHON_BIN": PYTHON, "GDTOOLKIT_DIR": TOOLKIT}
        )
        self.assertEqual(set(report.sources.values()), {USER_SETTINGS})

    def test_the_process_environment_wins(self) -> None:
        write_settings(self.user, {"GODOT_BIN": GODOT, "PYTHON_BIN": PYTHON})
        write_settings(self.local, {"GODOT_BIN": r"D:\other\godot.exe"})
        environ = {"GODOT_BIN": r"E:\mine\godot.exe", "PYTHON_BIN": ""}
        report = self.load(environ)
        self.assertEqual(environ["GODOT_BIN"], r"E:\mine\godot.exe")
        self.assertEqual(report.sources["GODOT_BIN"], PROCESS)
        # An empty variable counts as missing, as it does for every command of the runner.
        self.assertEqual(environ["PYTHON_BIN"], PYTHON)
        self.assertEqual(report.sources["PYTHON_BIN"], USER_SETTINGS)

    def test_local_settings_win_over_user_settings(self) -> None:
        # Claude Code's own order: a session in this folder sees the local value, so a terminal gets the same one.
        write_settings(self.user, {"GODOT_BIN": GODOT, "PYTHON_BIN": PYTHON})
        write_settings(self.local, {"GODOT_BIN": r"D:\local\godot.exe"})
        environ: dict[str, str] = {}
        report = self.load(environ)
        self.assertEqual(environ["GODOT_BIN"], r"D:\local\godot.exe")
        self.assertEqual(report.sources["GODOT_BIN"], LOCAL_SETTINGS)
        self.assertEqual(report.sources["PYTHON_BIN"], USER_SETTINGS)

    def test_invalid_json_is_ignored_with_a_problem(self) -> None:
        write_settings(self.user, text='{"env": {"GODOT_BIN": "C:\\\\x.exe",}')
        write_settings(self.local, {"PYTHON_BIN": PYTHON})
        environ: dict[str, str] = {}
        report = self.load(environ)
        self.assertEqual(environ, {"PYTHON_BIN": PYTHON})
        self.assertEqual(report.sources["GODOT_BIN"], None)
        self.assertEqual(len(report.problems), 1)
        self.assertIn(f"{USER_SETTINGS} ({self.user}) is not valid JSON", report.problems[0])

    def test_wrong_shapes_are_ignored_with_a_problem(self) -> None:
        write_settings(self.user, {"GODOT_BIN": 5, "PYTHON_BIN": PYTHON, "GDTOOLKIT_DIR": ""})
        write_settings(self.local, ["not", "an", "object"])
        environ: dict[str, str] = {}
        report = self.load(environ)
        self.assertEqual(environ, {"PYTHON_BIN": PYTHON})
        self.assertEqual(len(report.problems), 2, report.problems)
        self.assertIn("`env` is not an object", report.problems[0])
        self.assertIn("env.GODOT_BIN is not a string", report.problems[1])

    def test_a_settings_file_with_a_bom(self) -> None:
        self.user.parent.mkdir(parents=True)
        self.user.write_bytes(b"\xef\xbb\xbf" + json.dumps({"env": {"GODOT_BIN": GODOT}}).encode())
        environ: dict[str, str] = {}
        self.load(environ)
        self.assertEqual(environ, {"GODOT_BIN": GODOT})

    def test_claude_config_dir_replaces_the_home_folder(self) -> None:
        config = self.home / "elsewhere"
        write_settings(self.user, {"GODOT_BIN": GODOT})
        write_settings(config / "settings.json", {"GODOT_BIN": GUI})
        environ = {"CLAUDE_CONFIG_DIR": str(config)}
        report = self.load(environ)
        self.assertEqual(environ["GODOT_BIN"], GUI)
        self.assertEqual(report.sources["GODOT_BIN"], "$CLAUDE_CONFIG_DIR/settings.json")


class DoctorTest(unittest.TestCase):
    def output(self, report: machine_env.Report, ci: bool = False) -> str:
        buffer = io.StringIO()
        with (
            mock.patch.object(machine_env, "apply", return_value=report),
            mock.patch.object(doctor, "IS_CI", ci),
            mock.patch.dict(os.environ, {"GODOT_BIN": GODOT}),
            contextlib.redirect_stdout(buffer),
        ):
            doctor.Doctor().machine_paths()
        return buffer.getvalue()

    def report(self) -> machine_env.Report:
        sources: dict[str, str | None] = dict.fromkeys(machine_env.MACHINE_VARS)
        sources["GODOT_BIN"] = USER_SETTINGS
        return machine_env.Report(sources, ["x is not valid JSON"], [PROCESS, LOCAL_SETTINGS, USER_SETTINGS])

    def test_says_where_each_path_came_from_and_warns_when_missing(self) -> None:
        out = self.output(self.report())
        self.assertIn(f"ok    GODOT_BIN from {USER_SETTINGS}: {GODOT}", out)
        self.assertIn("warn  x is not valid JSON", out)
        self.assertIn(
            f"warn  PYTHON_BIN is not set: neither {PROCESS}, {LOCAL_SETTINGS} nor {USER_SETTINGS} has it", out
        )
        self.assertEqual(out.count("warn"), 4, out)

    def test_ci_skips_the_missing_ones(self) -> None:
        out = self.output(self.report(), ci=True)
        self.assertIn("skip  PYTHON_BIN (not set; CI finds its tools on PATH)", out)
        self.assertEqual(out.count("warn"), 1, out)

