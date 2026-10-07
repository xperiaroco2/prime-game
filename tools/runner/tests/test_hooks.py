"""Claude Code hooks: the fail-closed wrapper .claude/hooks/run-hook.sh, and the parts of the .gd post-edit hook."""

import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path

from runner import guard, hooks
from runner.common import ROOT, Result, git_bash

WRAPPER = str(ROOT / ".claude" / "hooks" / "run-hook.sh")
# The main checkout, also when the selftest runs in a worktree: there the session's own worktree is free (issue #51).
MAIN = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT))


class WrapperTest(unittest.TestCase):
    """Run the wrapper the way Claude Code does: Git Bash, JSON on stdin, CLAUDE_PROJECT_DIR set."""

    def run_hook(self, name: str, stdin: str, **env: str | None) -> subprocess.CompletedProcess[str]:
        bash = git_bash()
        self.assertIsNotNone(bash, "Git Bash (or bash) is needed to run the hooks")
        full = {**os.environ, "CLAUDE_PROJECT_DIR": str(ROOT)}
        # A desktop session unless a test says otherwise: in a cloud session on a task branch the main checkout is
        # the session's own (#381), and these tests judge it as a desktop session's.
        for key, value in {"CLAUDE_CODE_REMOTE": None, **env}.items():
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
    def shell_call(command: str, tool: str = "PowerShell", cwd: str = MAIN) -> str:
        return json.dumps({"tool_name": tool, "tool_input": {"command": command}, "cwd": cwd})

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

    def test_recursive_delete_asks_in_the_project_only(self) -> None:
        res = self.run_hook("guard", self.shell_call("Remove-Item -Recurse core"))
        self.assertEqual(res.returncode, 0, res.stderr)
        output = json.loads(res.stdout)["hookSpecificOutput"]
        self.assertEqual(output["permissionDecision"], "ask")
        self.assertIn("Recursive delete in the project", output["permissionDecisionReason"])
        res = self.run_hook("guard", self.shell_call('rm -rf "$TEMP/x" && git reset -q', "Bash"))
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))
        # The hook knows the real home folder: home itself asks, a folder in it passes.
        res = self.run_hook("guard", self.shell_call("rm -rf ~", "Bash"))
        self.assertEqual(json.loads(res.stdout)["hookSpecificOutput"]["permissionDecision"], "ask")
        res = self.run_hook("guard", self.shell_call("rm -rf ~/scratch-x", "Bash"))
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))
        # Inside the project, only the gitignored scratch folder is disposable.
        res = self.run_hook("guard", self.shell_call("rm -r tests/scratch/x", "Bash"))
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))
        res = self.run_hook("guard", self.shell_call("rm -r tests/integration/tmp", "Bash"))
        self.assertEqual(json.loads(res.stdout)["hookSpecificOutput"]["permissionDecision"], "ask")
        # In a worktree session its own worktree is free, and the main checkout still asks.
        worktree = str(Path(MAIN) / ".claude" / "worktrees" / "99")
        res = self.run_hook("guard", self.shell_call("rm -r tests/integration/tmp && git reset --hard", "Bash", worktree))
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))
        res = self.run_hook("guard", self.shell_call(f'git -C "{MAIN}" clean -fdx', "Bash", worktree))
        self.assertEqual(json.loads(res.stdout)["hookSpecificOutput"]["permissionDecision"], "ask")


    def test_in_accept_edits_the_guard_allows_what_it_finds_nothing_in(self) -> None:
        # Issue #312: a route-C successor manager runs in acceptEdits (#484); its routine shell work must not prompt.
        def call(command: str, mode: str, tool: str = "Bash") -> str:
            payload = {"tool_name": tool, "tool_input": {"command": command}, "cwd": MAIN, "permission_mode": mode}
            return json.dumps(payload)

        alone: dict[str, str | None] = {"CLAUDE_CODE_SESSION_ATTENDED": None}  # a scheduled-task run: no human
        command = "cd .claude/worktrees/99 && git status && awk '{print}' x"
        res = self.run_hook("guard", call(command, "acceptEdits"), **alone)
        self.assertEqual(res.returncode, 0, res.stderr)
        output = json.loads(res.stdout)["hookSpecificOutput"]
        decision = (output["permissionDecision"], output["permissionDecisionReason"])
        self.assertEqual(decision, ("allow", hooks.ALLOW_REASON))
        for mode in ("default", "bypassPermissions", "auto", "plan"):
            with self.subTest(mode=mode):
                self.assertEqual(self.run_hook("guard", call("git status", mode), **alone).stdout, "")
        # A human's own acceptEdits session (the humans' default mode) keeps its prompts.
        res = self.run_hook("guard", call(command, "acceptEdits"), CLAUDE_CODE_SESSION_ATTENDED="1")
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))
        # A guard ask stays an ask, and a write to a path Claude Code protects is left to Claude Code (its prompt).
        res = self.run_hook("guard", call("Copy-Item x .claude\\settings.json", "acceptEdits", "PowerShell"), **alone)
        self.assertEqual(json.loads(res.stdout)["hookSpecificOutput"]["permissionDecision"], "ask")
        res = self.run_hook("guard", call("cp x .claude/worktrees/99/.claude/skills/y.md", "acceptEdits"), **alone)
        self.assertEqual((res.returncode, res.stdout, res.stderr), (0, "", ""))

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

    def test_the_import_after_a_failed_check_is_recorded_for_the_next_launch(self) -> None:
        """The hook imports when a new class_name is not in the class cache yet; like every import through the runner
        it records the stamp, so the next `run` or `host` reports `import: current` instead of importing again."""
        from runner import check, common

        failing = "CHECK error res://core/x.gd:3: Identifier \"Beta\" not declared.\nCHECK summary files=1 errors=1\n"
        passing = "CHECK summary files=1 errors=0 warnings=0\n"
        replies = [Result(1, failing, False, 0.1), Result(0, "", False, 0.1), Result(0, passing, False, 0.1)]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".godot").mkdir()
            (root / check.CLASS_CACHE).write_text("list=[]\n", encoding="utf-8")
            (root / "x.gd").write_text("extends RefCounted\n", encoding="utf-8")
            started = time.time()
            with unittest.mock.patch.object(common, "ROOT", root), \
                    unittest.mock.patch.object(common, "godot", side_effect=replies) as godot:  # fmt: skip
                self.assertEqual(hooks.engine_check("res://core/x.gd"), ([], []))
            self.assertEqual(godot.call_args_list[1].args[0], ["--headless", "--import"])
            stamp = check.stamp_time(root)
            assert stamp is not None
            self.assertGreaterEqual(stamp, started)
            self.assertEqual(check.freshness(root).why, "")


class CloudSessionTest(unittest.TestCase):
    """Issue #381: the hook tells the guard it runs in a cloud session, by the same test as doctor.cloud_twovoip."""

    def test_the_cloud_test_is_remote_without_ci(self) -> None:
        from runner import common

        for cloud, ci, expected in ((True, False, True), (True, True, False), (False, False, False)):
            with self.subTest(cloud=cloud, ci=ci):
                self.assertEqual(common.cloud_session(cloud, ci), expected)
                with unittest.mock.patch.multiple(common, IS_CLOUD=cloud, IS_CI=ci):
                    self.assertEqual(common.cloud_session(), expected)

    def test_the_hook_reads_the_environment_as_common_does(self) -> None:
        # hooks.cloud_session reads the environment itself (the guard skips importing common): a fresh process per
        # environment, since common reads it once at import.
        code = "from runner import common, hooks; print(common.cloud_session(), hooks.cloud_session())"
        cases = (("true", None), ("TRUE", ""), ("true", "true"), ("true", "1"), ("true", "false"), (None, None))
        for remote, ci in cases:
            env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_CODE_REMOTE", "CI")}
            env.update({k: v for k, v in (("CLAUDE_CODE_REMOTE", remote), ("CI", ci)) if v is not None})
            with self.subTest(remote=remote, ci=ci):
                command = [sys.executable, "-c", code]
                res = subprocess.run(command, cwd=ROOT / "tools", env=env, capture_output=True, text=True, timeout=60)
                self.assertEqual(res.returncode, 0, res.stderr)
                common_says, hooks_says = res.stdout.split()
                self.assertEqual(hooks_says, common_says)
                self.assertEqual(hooks_says == "True", remote is not None and ci in (None, "", "false"))

    def test_the_hook_owns_the_main_checkout_only_in_a_cloud_session_on_a_task_branch(self) -> None:
        class Repo(guard.NoRepo):
            def __init__(self, root: str, branch: str) -> None:
                self.name = branch

            def branch(self, checkout: str) -> str | None:
                return self.name

        call = {"tool_name": "Bash", "tool_input": {"command": "git reset -q --soft HEAD~2"}, "cwd": MAIN}
        for remote, ci, branch, asks in (
            ("true", "", "tooling/381-guard-cloud-checkout", False),
            ("true", "", "main", True),
            ("true", "true", "tooling/381-guard-cloud-checkout", True),
            ("", "", "tooling/381-guard-cloud-checkout", True),
        ):
            with (
                self.subTest(remote=remote, ci=ci, branch=branch),
                unittest.mock.patch.dict(os.environ, {"CLAUDE_CODE_REMOTE": remote, "CI": ci}),
                unittest.mock.patch.object(hooks, "GitFiles", lambda root, b=branch: Repo(root, b)),
                unittest.mock.patch("sys.stdout", new_callable=io.StringIO) as out,
            ):
                self.assertEqual(hooks.pre_tool_use(call), 0)
                self.assertEqual('"permissionDecision": "ask"' in out.getvalue(), asks, out.getvalue())


class GitFilesTest(unittest.TestCase):
    """The guard's view of the repository: branches, refs and stash entries, read from `.git` without git."""

    def test_branches_refs_and_stash_of_a_real_repository(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gitfiles") as tmp:
            main = Path(tmp) / "game"

            def git(*args: str, where: Path = main) -> None:
                subprocess.run(["git", *args], cwd=where, check=True, capture_output=True)

            main.mkdir()
            git("init", "-q", "-b", "main")
            for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
                git("config", key, value)
            (main / "f.txt").write_text("one\n", encoding="utf-8")
            git("add", "f.txt")
            git("commit", "-q", "-m", "c1")
            worktree = main / ".claude" / "worktrees" / "7"
            git("worktree", "add", "-q", "-b", "core/7-x", str(worktree))
            (main / "f.txt").write_text("human\n", encoding="utf-8")
            git("stash", "push", "-q", "-m", "start #8: left on main")
            (worktree / "f.txt").write_text("agent\n", encoding="utf-8")
            git("stash", "push", "-q", where=worktree)
            files = hooks.GitFiles(str(worktree))

            self.assertEqual(files.branch(guard.normalize(str(main))), "main")
            self.assertEqual(files.branch(guard.normalize(str(worktree))), "core/7-x")
            self.assertEqual(files.stash_branches(), ["core/7-x", "main"])
            self.assertTrue({"main", "core/7-x"} <= files.refs())
            self.assertIsNone(files.branch(guard.normalize(str(main / ".claude" / "worktrees" / "9"))))
            # A rebase stopped on a conflict detaches HEAD; the branch it rebases is still the checkout's (#381).
            git("checkout", "-q", "--detach", where=worktree)
            self.assertIsNone(files.branch(guard.normalize(str(worktree))))
            rev_parse = ["git", "rev-parse", "--absolute-git-dir"]
            found = subprocess.run(rev_parse, cwd=worktree, check=True, capture_output=True, text=True)
            admin = Path(found.stdout.strip())
            for folder in ("rebase-apply", "rebase-merge"):
                with self.subTest(folder=folder):
                    (admin / folder).mkdir()
                    (admin / folder / "head-name").write_text("refs/heads/core/7-x\n", encoding="utf-8")
                    self.assertEqual(files.branch(guard.normalize(str(worktree))), "core/7-x")
                    shutil.rmtree(admin / folder)

    def test_the_github_repository_comes_from_the_origin_remote(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gitfiles") as tmp:
            main = Path(tmp) / "game"
            main.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main"], cwd=main, check=True, capture_output=True)
            worktree = main / ".claude" / "worktrees" / "7"
            self.assertIsNone(hooks.GitFiles(str(worktree)).github_repo())
            for url, expected in (
                ("git@github.com:Owner/Game.git", "owner/game"),
                ("https://github.com/owner/game.git", "owner/game"),
                ("ssh://git@github.com/owner/game", "owner/game"),
                ("https://gitlab.com/owner/game.git", None),
            ):
                with self.subTest(url=url):
                    subprocess.run(["git", "remote", "remove", "origin"], cwd=main, capture_output=True)
                    upstream = ["git", "remote", "add", "upstream", "https://github.com/u/x"]
                    subprocess.run(upstream, cwd=main, capture_output=True)
                    subprocess.run(["git", "remote", "add", "origin", url], cwd=main, check=True, capture_output=True)
                    self.assertEqual(hooks.GitFiles(str(worktree)).github_repo(), expected)

    def test_the_gh_account_comes_from_gh_hosts_file(self) -> None:
        # Issue #464: the account `gh api user` returns, read from gh's config folder without a network call.
        with tempfile.TemporaryDirectory(prefix="gitfiles") as tmp:
            files = hooks.GitFiles(str(Path(tmp) / "game"))
            clean = {"GH_CONFIG_DIR": tmp, "GH_TOKEN": "", "GITHUB_TOKEN": ""}
            hosts = Path(tmp) / "hosts.yml"
            for text, expected in (
                (
                    "github.com:\n    git_protocol: https\n    users:\n        Other:\n    user: XperiaRoco2\n",
                    "xperiaroco2",
                ),
                ("github.com:\n    oauth_token: x\n    user: owner-1\n    git_protocol: ssh\n", "owner-1"),
                ("ghe.example.com:\n    user: corp\ngithub.com:\n    users:\n        a:\n            user: no\n", None),
                ("", None),
            ):
                with self.subTest(text=text):
                    hosts.write_text(text, encoding="utf-8")
                    with unittest.mock.patch.dict(os.environ, clean):
                        self.assertEqual(files.gh_user(), expected)
            hosts.write_text("github.com:\n    user: owner-1\n", encoding="utf-8")
            with unittest.mock.patch.dict(os.environ, {**clean, "GH_TOKEN": "t"}):
                self.assertIsNone(files.gh_user())
            with unittest.mock.patch.dict(os.environ, {**clean, "GH_CONFIG_DIR": str(Path(tmp) / "none")}):
                self.assertIsNone(files.gh_user())

    def test_temp_matches_list_the_temp_folder_and_find_worktrees(self) -> None:
        # Issue #464: a filtered delete in the temp folder is judged by what it matches now.
        with tempfile.TemporaryDirectory(prefix="gitfiles") as tmp:
            main, temp = Path(tmp) / "game", Path(tmp) / "temp"
            main.mkdir()
            temp.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main"], cwd=main, check=True, capture_output=True)
            for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
                subprocess.run(["git", "config", key, value], cwd=main, check=True, capture_output=True)
            commit = ["git", "commit", "-q", "--allow-empty", "-m", "c"]
            subprocess.run(commit, cwd=main, check=True, capture_output=True)
            for folder in ("rmtree-a", "rmtree-b/x", ".rmtree-hidden", "other", "linked/inner"):
                (temp / folder).mkdir(parents=True)
            (temp / "linked" / "inner" / ".git").write_text("gitdir: elsewhere\n", encoding="utf-8")
            add = ["git", "worktree", "add", "-q", "--detach", str(temp / "held" / "wt")]
            subprocess.run(add, cwd=main, check=True, capture_output=True)
            files = hooks.GitFiles(str(main))
            files.temp = str(temp)
            self.assertEqual(sorted(files.temp_matches("rmtree-*") or []), [("rmtree-a", False), ("rmtree-b", False)])
            self.assertEqual(files.temp_matches(".rmtree-*"), [(".rmtree-hidden", False)])
            self.assertEqual(files.temp_matches("h*"), [("held", True)])
            self.assertEqual(files.temp_matches("held/w?"), [("held/wt", True)])
            self.assertEqual(files.temp_matches("linked/*"), [("linked/inner", True)])
            self.assertEqual(files.temp_matches("linked"), [("linked", False)])  # only a worktree of this repository
            self.assertEqual(files.temp_matches("none-*"), [])
            # A link or junction may lead a recursive delete out of the temp folder: it counts as a worktree.
            link = temp / "link-x"
            try:
                os.symlink(temp / "other", link, target_is_directory=True)
            except OSError:
                if os.name != "nt":
                    raise
                import _winapi

                _winapi.CreateJunction(str(temp / "other"), str(link))
            (temp / "other" / "inner").mkdir()
            self.assertEqual(files.temp_matches("link-*"), [("link-x", True)])
            self.assertEqual(files.temp_matches("link-x/*"), [("link-x/inner", True)])
            self.assertEqual(files.temp_matches("othe?"), [("other", False)])
            files.temp = str(Path(tmp) / "missing")
            self.assertIsNone(files.temp_matches("rmtree-*"))

    def test_a_worktree_is_busy_while_another_live_session_works_there(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gitfiles") as tmp:
            worktree = Path(tmp) / "game" / ".claude" / "worktrees" / "7"
            worktree.mkdir(parents=True)
            sessions = Path(tmp) / "config" / "sessions"
            sessions.mkdir(parents=True)
            files = hooks.GitFiles(str(worktree))
            env = {"CLAUDE_CONFIG_DIR": str(sessions.parent), "CLAUDE_CODE_SESSION_ID": "me"}
            with unittest.mock.patch.dict(os.environ, env):
                self.assertFalse(files.busy(guard.normalize(str(worktree))))
                record = {"pid": os.getpid(), "sessionId": "other", "cwd": str(worktree), "status": "busy"}
                (sessions / "1.json").write_text(json.dumps(record), encoding="utf-8")
                self.assertTrue(files.busy(guard.normalize(str(worktree))))
                self.assertFalse(files.busy(guard.normalize(str(worktree.parent / "8"))))


if __name__ == "__main__":
    unittest.main(argv=sys.argv)
