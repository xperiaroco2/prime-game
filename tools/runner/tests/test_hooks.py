"""Claude Code hooks: the fail-closed wrapper .claude/hooks/run-hook.sh, and the parts of the .gd post-edit hook."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from runner import hooks
from runner.common import ROOT, Result, git_bash

WRAPPER = str(ROOT / ".claude" / "hooks" / "run-hook.sh")


class WrapperTest(unittest.TestCase):
    """Run the wrapper the way Claude Code does: Git Bash, JSON on stdin, CLAUDE_PROJECT_DIR set."""

    def run_hook(self, name: str, stdin: str, **env: str | None) -> subprocess.CompletedProcess[str]:
        bash = git_bash()
        self.assertIsNotNone(bash, "Git Bash (or bash) is needed to run the hooks")
        full = {**os.environ, "CLAUDE_PROJECT_DIR": str(ROOT)}
        for key, value in env.items():
            if value is None:
                full.pop(key, None)
            else:
                full[key] = value
        return subprocess.run(
            [str(bash), WRAPPER, name],
            input=stdin,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=full,
            timeout=120,
        )

    @staticmethod
    def shell_call(command: str, tool: str = "PowerShell") -> str:
        return json.dumps({"tool_name": tool, "tool_input": {"command": command}, "cwd": str(ROOT)})

    def test_normal_command_passes_silently(self) -> None:
        res = self.run_hook("guard", self.shell_call("git status; tools\\run.cmd lint"))
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))

    def test_protected_write_asks(self) -> None:
        res = self.run_hook("guard", self.shell_call("Copy-Item $env:TEMP\\s.json .claude\\settings.json"))
        self.assertEqual(res.returncode, 0, res.stderr)
        output = json.loads(res.stdout)["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertEqual(output["permissionDecision"], "ask")
        self.assertIn(".claude\\settings.json", output["permissionDecisionReason"])

    def test_crash_fails_closed(self) -> None:
        res = self.run_hook("guard", "this is not JSON")
        self.assertEqual(res.returncode, 2)
        self.assertIn("fails closed", res.stderr)

    def test_missing_python_bin_fails_closed(self) -> None:
        res = self.run_hook("guard", self.shell_call("git status"), PYTHON_BIN=str(ROOT / "no-such-python.exe"))
        self.assertEqual(res.returncode, 2)
        self.assertIn("PYTHON_BIN points to a missing file", res.stderr)

    def test_no_python_at_all_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as empty:
            res = self.run_hook("guard", self.shell_call("git status"), PYTHON_BIN=None, PATH=empty)
        self.assertEqual(res.returncode, 2)
        self.assertIn("no Python found", res.stderr)

    def test_python_that_exits_1_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "fakepython"
            fake.write_text("#!/bin/sh\necho broken >&2\nexit 1\n", encoding="ascii", newline="\n")
            fake.chmod(0o755)
            res = self.run_hook("guard", self.shell_call("git status"), PYTHON_BIN=str(fake))
        self.assertEqual(res.returncode, 2)
        self.assertIn("Python exited with code 1", res.stderr)

    def test_post_edit_ignores_other_files(self) -> None:
        payload = {"tool_name": "Write", "tool_input": {"file_path": str(ROOT / "docs" / "GDD.md")}}
        res = self.run_hook("gd-edit", json.dumps(payload))
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))


class PostEditTest(unittest.TestCase):
    def test_only_project_gd_files_outside_third_party_code(self) -> None:
        root = os.path.join(tempfile.gettempdir(), "proj")
        cases = {
            os.path.join(root, "core", "match", "vote.gd"): "core/match/vote.gd",
            os.path.join(root, "tests", "unit", "smoke_test.gd"): "tests/unit/smoke_test.gd",
            os.path.join(root, "addons", "gdUnit4", "x.gd"): None,
            os.path.join(root, "tools", "out", "x.gd"): None,
            os.path.join(root, ".claude", "worktrees", "5", "core", "x.gd"): None,
            os.path.join(root, "core", "notes.md"): None,
            os.path.join(root + "2", "core", "x.gd"): None,
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(hooks.project_gd(path, root), expected)

    def test_gdtoolkit_parse_error_becomes_file_line(self) -> None:
        out = (
            "tools/out/hookprobe/broken.gd:\n\n\tvar x: int = \n                     ^\n\n"
            "Unexpected token Token('_NL', '\\n\\t') at line 4, column 15.\nExpected one of: \n\t* DOLLAR\n"
        )
        problems = hooks.gdtoolkit_problems("core/x.gd", Result(1, out, False, 0.0), "gdformat")
        self.assertEqual(problems, ["core/x.gd:4: gdformat: Unexpected token Token('_NL', '\\n\\t') (column 15)"])

    def test_gdlint_findings_keep_their_lines(self) -> None:
        out = "core\\x.gd:7: Error: Function name \"Bad\" is not valid (function-name)\nFailure: 1 problem found\n"
        problems = hooks.gdtoolkit_problems("core/x.gd", Result(1, out, False, 0.0), "gdlint")
        self.assertEqual(problems, ['core/x.gd:7: gdlint: Error: Function name "Bad" is not valid (function-name)'])

    def test_engine_errors_keep_project_lines(self) -> None:
        out = "\n".join(
            [
                "SCRIPT ERROR: Parse Error: Expected expression.",
                'CHECK error res://core/x.gd:4: Parse Error: Expected expression after "=". [GDScript::reload]',
                "CHECK error modules/gdscript/gdscript_resource_format.cpp:46: Failed to load script [load]",
                "CHECK warning res://core/y.gd:9: The local variable is unused (UNUSED_VARIABLE)",
                "CHECK summary files=1 errors=2 warnings=1",
            ]
        )
        errors, warnings = hooks.engine_lines(Result(1, out, False, 0.0))
        self.assertEqual(errors, ['core/x.gd:4: Parse Error: Expected expression after "=".'])
        self.assertEqual(warnings, ["core/y.gd:9: The local variable is unused (UNUSED_VARIABLE)"])


if __name__ == "__main__":
    unittest.main(argv=sys.argv)
