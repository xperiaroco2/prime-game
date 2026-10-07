"""Machine paths from the Claude settings when the process environment lacks them (#55).

Every test builds its own home and project folders in a temporary directory: the real ~/.claude is never read.
"""

import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import common, doctor, machine_env
from runner.common import IS_WINDOWS, ROOT
from runner.machine_env import LOCAL_SETTINGS, PROCESS, USER_SETTINGS
from runner.tests.tempnames import short_temp

GODOT = r"C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
GUI = r"C:\Godot\Godot_v4.7.2-stable_win64.exe"
PYTHON = r"C:\Python314\python.exe"
TOOLKIT = r"C:\Python314\Scripts"
NODE = r"C:\Program Files\nodejs\node.exe"


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
            {
                "GODOT_BIN": GODOT,
                "GODOT_GUI_BIN": GUI,
                "PYTHON_BIN": PYTHON,
                "GDTOOLKIT_DIR": TOOLKIT,
                "NODE_BIN": NODE,
                "OTHER": "1",
            },
        )
        environ: dict[str, str] = {}
        report = self.load(environ)
        self.assertEqual(
            environ,
            {"GODOT_BIN": GODOT, "GODOT_GUI_BIN": GUI, "PYTHON_BIN": PYTHON, "GDTOOLKIT_DIR": TOOLKIT, "NODE_BIN": NODE},
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
    def output(self, report: machine_env.Report, ci: bool = False, cloud: bool = False) -> str:
        buffer = io.StringIO()
        with (
            mock.patch.object(machine_env, "apply", return_value=report),
            mock.patch.object(doctor, "IS_CI", ci),
            mock.patch.object(doctor, "IS_CLOUD", cloud),
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
        self.assertIn("skip  NODE_BIN (not set; the tool on PATH is used)", out)

    def test_names_the_claude_config_dir_settings_when_they_are_searched(self) -> None:
        report = self.report()
        report.searched[-1] = "$CLAUDE_CONFIG_DIR/settings.json"
        out = self.output(report)
        self.assertIn("PYTHON_BIN is not set", out)
        self.assertIn("add it to the env of $CLAUDE_CONFIG_DIR/settings.json", out)
        self.assertNotIn(USER_SETTINGS, out.replace(f"GODOT_BIN from {USER_SETTINGS}", ""))

    def godot_output(self, gui: str | None, cloud: bool = False) -> str:
        """machine_paths() and godot() together, as doctor runs them, with GODOT_GUI_BIN unset or set to `gui`."""
        environ = {k: v for k, v in os.environ.items() if k != "GODOT_GUI_BIN"}
        if gui is not None:
            environ["GODOT_GUI_BIN"] = gui
        report = self.report()
        report.sources["GODOT_GUI_BIN"] = PROCESS if gui is not None else None
        buffer = io.StringIO()
        with (
            mock.patch.object(machine_env, "apply", return_value=report),
            mock.patch.object(doctor, "IS_CI", False),
            mock.patch.object(doctor, "IS_CLOUD", cloud),
            mock.patch.object(doctor, "require_godot", return_value=GODOT),
            mock.patch.object(doctor, "godot_bin", return_value=GODOT),
            mock.patch.dict(os.environ, environ, clear=True),
            contextlib.redirect_stdout(buffer),
        ):
            doc = doctor.Doctor()
            doc.machine_paths()
            doc.godot()
        return buffer.getvalue()

    def test_a_missing_godot_gui_bin_is_warned_about_once(self) -> None:
        out = self.godot_output(None)
        lines = [line for line in out.splitlines() if line.strip().startswith("warn") and "GODOT_GUI_BIN" in line]
        self.assertEqual(len(lines), 1, out)
        self.assertIn("GODOT_GUI_BIN is not set", lines[0])

    def test_a_cloud_session_needs_no_godot_gui_bin(self) -> None:
        out = self.godot_output(None, cloud=True)
        self.assertIn("skip  GODOT_GUI_BIN (not needed in a cloud session)", out)
        self.assertNotIn("warn  GODOT_GUI_BIN", out)

    def test_a_godot_gui_bin_pointing_to_a_missing_file(self) -> None:
        missing = r"C:\no\Godot_v4.7.2-stable_win64.exe"
        out = self.godot_output(missing)
        self.assertIn(f"warn  GODOT_GUI_BIN points to a missing file: {missing}", out)

    def test_ci_skips_the_missing_ones(self) -> None:
        out = self.output(self.report(), ci=True)
        self.assertIn("skip  PYTHON_BIN (not set; CI finds its tools on PATH)", out)
        self.assertEqual(out.count("warn"), 1, out)

    def test_a_cloud_session_skips_the_missing_ones_like_ci(self) -> None:
        out = self.output(self.report(), cloud=True)
        self.assertIn("skip  PYTHON_BIN (not set; a cloud session finds its tools on PATH)", out)
        self.assertEqual(out.count("warn"), 1, out)


class RunPyTest(unittest.TestCase):
    """The real tools/run.py fills the machine paths before its command runs: the wiring that fixes #55."""

    def test_a_command_in_a_terminal_without_the_machine_paths(self) -> None:
        # `run` reads GODOT_BIN without calling machine_env itself (doctor does), so only run.py's call can fill it.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name) / "home"
        godot = str(Path(tmp.name) / "no" / "godot_console.exe")
        write_settings(home / ".claude" / "settings.json", {"GODOT_BIN": godot})
        env = {
            key: value
            for key, value in os.environ.items()
            if key.upper() not in (*machine_env.MACHINE_VARS, "CLAUDE_CONFIG_DIR", "HOME", "USERPROFILE")
        }
        env.update({"HOME": str(home), "USERPROFILE": str(home), "PYTHONIOENCODING": "utf-8"})
        res = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "run.py"), "run", "tools/run/probe.gd", "--headless"],
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=120,
            check=False,
        )
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertIn(f"GODOT_BIN points to a missing file: {godot}", res.stdout + res.stderr)


class LongTempTest(unittest.TestCase):
    """An 8.3 short TEMP (`C:\\Users\\XPERIA~1\\AppData\\Local\\Temp`, issue #542) is put in its long form once, so
    the runner and its tests compare one name of the temp folder with the long one git and Path.resolve give."""

    def same(self, a: str, b: str) -> None:
        self.assertEqual(os.path.normcase(a), os.path.normcase(b))

    def test_long_path_expands_each_short_name_and_leaves_the_rest(self) -> None:
        full, short = short_temp(self)
        self.assertNotEqual(os.path.normcase(short), os.path.normcase(full))
        self.same(common.long_path(short), full)
        missing = os.path.join(short, "missing-file.txt")
        self.assertEqual(common.long_path(missing), missing)
        self.assertEqual(common.long_path(full), full)

    def test_long_temp_changes_only_the_temp_variables_that_are_short(self) -> None:
        full, short = short_temp(self)
        environ = {"TEMP": short, "TMP": full, "TMPDIR": "", "OTHER": short}
        changed = common.long_temp(environ)
        self.assertEqual(list(changed), ["TEMP"])
        self.assertEqual(changed["TEMP"][0], short)
        self.same(environ["TEMP"], full)
        self.assertEqual((environ["TMP"], environ["TMPDIR"], environ["OTHER"]), (full, "", short))
        self.assertEqual(common.long_temp(environ), {})

    def test_the_runner_puts_a_short_temp_in_long_form_and_doctor_warns(self) -> None:
        full, short = short_temp(self)
        buffer = io.StringIO()
        with (
            mock.patch.dict(os.environ, {"TEMP": short, "TMP": short}),
            mock.patch.object(tempfile, "tempdir", short),
            mock.patch.object(machine_env, "_applied", None),
            mock.patch.object(doctor, "IS_CI", False),
            mock.patch.object(doctor, "IS_CLOUD", False),
            contextlib.redirect_stdout(buffer),
        ):
            report = machine_env.apply()
            self.same(os.environ["TEMP"], full)
            self.same(os.environ["TMP"], full)
            self.same(tempfile.gettempdir(), full)
            doctor.Doctor().machine_paths()
        self.assertEqual(sorted(report.long_temp), ["TEMP", "TMP"])
        out = buffer.getvalue()
        self.assertIn(f"warn  TEMP is the 8.3 short path {short}: the runner uses its long form ", out)
        self.assertIn(f"set TMP to the long path in the env of {USER_SETTINGS}", out)

    def test_the_tests_that_compare_temp_paths_pass_with_a_short_temp(self) -> None:
        # Tests #542 saw red with a short TEMP, run the way its report ran them: `python -m unittest` in tools/.
        _full, short = short_temp(self)
        tests = [
            "runner.tests.test_gdunit_shards.PlanTest.test_the_scan_finds_the_suites_a_one_process_run_finds",
            "runner.tests.test_train.TrainTest.test_prs_merge_in_series_each_after_main_moved",
            "runner.tests.test_hooks.GitFilesTest.test_temp_matches_list_the_temp_folder_and_find_worktrees",
        ]
        env = {**os.environ, "TEMP": short, "TMP": short, "PYTHONIOENCODING": "utf-8"}
        res = subprocess.run(
            [sys.executable, "-m", "unittest", *tests],
            cwd=ROOT / "tools",
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=180,
            check=False,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("Ran 3 tests", res.stderr)


@unittest.skipUnless(IS_WINDOWS, "tools\\run.cmd is the Windows wrapper")
class RunCmdTest(unittest.TestCase):
    """tools\\run.cmd finds Python in the Claude settings before Python runs, in a copy of it next to a stub run.py."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.root = self.project("project")
        self.user = self.home / ".claude" / "settings.json"
        self.local = self.root / ".claude" / "settings.local.json"
        self.missing = str(self.base / "no" / "python.exe")

    def project(self, name: str) -> Path:
        root = self.base / name
        (root / "tools").mkdir(parents=True)
        shutil.copyfile(ROOT / "tools" / "run.cmd", root / "tools" / "run.cmd")
        (root / "tools" / "run.py").write_text(
            "import os, sys\nprint('STUB', sys.executable, sys.argv[1:])\n", encoding="utf-8"
        )
        return root

    def run_cmd(
        self, extra: dict[str, str] | None = None, python_on_path: bool = False, root: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        system = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
        env = {
            key: value
            for key, value in os.environ.items()
            if key.upper() not in (*machine_env.MACHINE_VARS, "CLAUDE_CONFIG_DIR", "PATH", "USERPROFILE")
        }
        # Never the py launcher (it lives in its own folder or in C:\Windows): the system, and Python only when asked.
        path = [str(system), str(system / "WindowsPowerShell" / "v1.0")]
        env["PATH"] = os.pathsep.join(([str(Path(sys.executable).parent)] if python_on_path else []) + path)
        env["USERPROFILE"] = str(self.home)
        env.update(extra or {})
        return subprocess.run(
            ["cmd", "/c", str((root or self.root) / "tools" / "run.cmd"), "pins"],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def test_python_bin_from_user_settings(self) -> None:
        write_settings(self.user, {"PYTHON_BIN": sys.executable})
        res = self.run_cmd()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(f"STUB {sys.executable} ['pins']", res.stdout)

    def test_a_missing_file_is_named(self) -> None:
        write_settings(self.user, {"PYTHON_BIN": self.missing})
        res = self.run_cmd(python_on_path=True)
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertIn(f"PYTHON_BIN in the env of the Claude settings points to a missing file: {self.missing}", res.stderr)

    def test_local_settings_win(self) -> None:
        write_settings(self.user, {"PYTHON_BIN": sys.executable})
        write_settings(self.local, {"PYTHON_BIN": self.missing})
        res = self.run_cmd(python_on_path=True)
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertIn(f"points to a missing file: {self.missing}", res.stderr)

    def test_a_quote_in_the_checkout_path(self) -> None:
        # The local settings path reaches PowerShell through the environment, not inside a quoted literal.
        root = self.project("it's a project")
        write_settings(root / ".claude" / "settings.local.json", {"PYTHON_BIN": sys.executable})
        res = self.run_cmd(root=root)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(f"STUB {sys.executable} ['pins']", res.stdout)

    def test_the_process_environment_wins(self) -> None:
        write_settings(self.user, {"PYTHON_BIN": self.missing})
        res = self.run_cmd({"PYTHON_BIN": sys.executable})
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(f"STUB {sys.executable}", res.stdout)

    def test_missing_or_invalid_settings_fall_back_to_python_on_path(self) -> None:
        for text in (None, '{"env": {"PYTHON_BIN": '):
            with self.subTest(text=text):
                if text is not None:
                    write_settings(self.user, text=text)
                res = self.run_cmd(python_on_path=True)
                self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
                self.assertIn("STUB", res.stdout)
                self.assertEqual(res.stderr, "")
