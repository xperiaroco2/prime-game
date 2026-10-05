"""Claude Code hooks (docs/AGENT_WORKFLOW.md §8.2 and §8.4): `run hook guard` and `run hook gd-edit`.

Claude Code starts them through .claude/hooks/run-hook.sh with the hook input as JSON on stdin. Both fail closed:
any crash exits 2, which blocks a PreToolUse call, and shows the message to Claude after a PostToolUse one.
The guard runs before every shell command, so this module imports the heavy runner modules only where needed.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .common import Result

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The engine parse check of one file; an import and a second check share the same budget.
ENGINE_BUDGET = 60.0
# gdformat and gdlint take about 1 s each; with the engine budget the worst case stays under the 120 s hook timeout.
GDTOOLKIT_TIMEOUT = 20
MAX_LINES = 40
# Where the post-edit hook never formats or checks: third-party code, runner output, engine cache, other checkouts.
SKIPPED_DIRS = ("addons/", "tools/out/", ".godot/", ".claude/")
GDTOOLKIT_PARSE_RE = re.compile(r"^(Unexpected (?:token|character).*?) at line (\d+), column (\d+)")
CHECK_LINE_RE = re.compile(r"^CHECK (error|warning) (.*?)(?: \[[^\]]*\])?$")


def main(name: str) -> int:
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("the hook input is not a JSON object")
        if name == "guard":
            return pre_tool_use(payload)
        if name == "gd-edit":
            return post_edit(payload)
        raise ValueError(f"unknown hook {name!r}")
    except Exception:  # noqa: BLE001 - fail closed on anything
        import traceback

        sys.stderr.write(f"hook {name} crashed, so it fails closed:\n{traceback.format_exc()[-2500:]}")
        return 2


def _emit(event: str, **fields: str) -> None:
    sys.stdout.write(json.dumps({"hookSpecificOutput": {"hookEventName": event, **fields}}) + "\n")


# --- the thin guard (PreToolUse on Bash|PowerShell) -----------------------------------------------------------------


def pre_tool_use(payload: dict[str, object]) -> int:
    """Ask before a shell write to an ask-protected path, a recursive delete or git that discards work beyond the
    session's own worktree and task branch, or a gh command that may write to another repository (guard.py); stay
    silent otherwise."""
    tool = payload.get("tool_name")
    tool_input = payload.get("tool_input")
    if tool not in ("Bash", "PowerShell") or not isinstance(tool_input, dict):
        return 0
    command = tool_input.get("command")
    if not isinstance(command, str):
        raise ValueError(f"{tool} call without a command string")
    from . import guard

    shell = guard.BASH if tool == "Bash" else guard.POWERSHELL
    home = os.path.expanduser("~")  # so that `~/<project>` stays protected when the checkout is under home
    cwd = str(payload.get("cwd") or "")
    # A cloud session works in the main checkout on its task branch: there it is the session's own (#381).
    findings = guard.check(command, shell, cwd, ROOT, home if home != "~" else "", GitFiles(ROOT), cloud_session())
    if findings:
        _emit("PreToolUse", permissionDecision="ask", permissionDecisionReason=guard.reason(findings))
    return 0


def cloud_session() -> bool:
    """common.cloud_session() (the test doctor.cloud_twovoip uses), read here without importing common, which costs
    the guard about 40 ms on every shell call; test_hooks keeps the two equal."""
    remote = os.environ.get("CLAUDE_CODE_REMOTE", "").lower() == "true"
    return remote and os.environ.get("CI", "").lower() not in ("1", "true", "yes")


class GitFiles:
    """Branch, ref and stash names for the guard, read from the files in `.git` (no git process: the guard runs
    before every shell command). Reads what it is asked for, once; anything it cannot read is unknown."""

    STASH_LINE_RE = re.compile(r"\t(?:WIP on|On) (.+?): ")

    def __init__(self, root: str) -> None:
        # The main checkout, also when the hook runs from a worktree's copy of the runner.
        self.root = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+[\\/]?$", "", root)
        self.common = os.path.join(self.root, ".git")
        self._refs: set[str] | None = None

    def _read(self, *parts: str) -> str:
        try:
            with open(os.path.join(*parts), encoding="utf-8", errors="replace") as handle:
                return handle.read()
        except OSError:
            return ""

    def branch(self, checkout: str) -> str | None:
        """The branch of a checkout, given as the guard's normalized path (lower-case, forward slashes)."""
        from . import guard

        suffix = checkout[len(guard.normalize(self.root)) :].lstrip("/")
        git = os.path.join(self.root, *suffix.split("/"), ".git") if suffix else self.common
        admin = git
        if os.path.isfile(git):
            match = re.match(r"gitdir:\s*(.+)", self._read(git).strip())
            if not match:
                return None
            admin = match.group(1).strip()
        head = self._read(admin, "HEAD").strip()
        if head.startswith("ref: refs/heads/"):
            return head.removeprefix("ref: refs/heads/")
        # A rebase stopped on a conflict detaches HEAD, but it still rewrites its branch (#381).
        for folder in ("rebase-merge", "rebase-apply"):
            name = self._read(admin, folder, "head-name").strip()
            if name.startswith("refs/heads/"):
                return name.removeprefix("refs/heads/")
        return None

    def busy(self, checkout: str) -> bool:
        """Another live Claude session works in the worktree checkout (a normalized path): a session in the main
        checkout then does not own it (sessions.active_on)."""
        from pathlib import Path

        from . import guard, sessions

        suffix = checkout[len(guard.normalize(self.root)) :].lstrip("/")
        return bool(sessions.active_on(Path(self.root, *suffix.split("/"))))

    def refs(self) -> set[str]:
        if self._refs is None:
            names: set[str] = set()
            for line in self._read(self.common, "packed-refs").splitlines():
                parts = line.split(" ", 1)
                if len(parts) == 2 and not line.startswith(("#", "^")):
                    names |= self._names(parts[1].strip())
            base = os.path.join(self.common, "refs")
            for folder, _, files in os.walk(base):
                for name in files:
                    relative = os.path.relpath(os.path.join(folder, name), base).replace("\\", "/")
                    names |= self._names("refs/" + relative)
            self._refs = names
        return self._refs

    @staticmethod
    def _names(ref: str) -> set[str]:
        """`refs/heads/x` is x; `refs/remotes/origin/x` is origin/x and x (git checkout x creates it); tags."""
        low = ref.lower()
        for prefix in ("refs/heads/", "refs/tags/"):
            if low.startswith(prefix):
                return {low[len(prefix) :]}
        if low.startswith("refs/remotes/"):
            remote = low[len("refs/remotes/") :]
            return {remote, remote.split("/", 1)[-1]}
        return set()

    def github_repo(self) -> str | None:
        """`owner/name` of the `origin` remote in `.git/config`, when it is on github.com (lower-case)."""
        from . import guard

        section = ""
        for line in self._read(self.common, "config").splitlines():
            text = line.strip()
            if text.startswith("["):
                section = text.lower().replace(" ", "")
            elif section == '[remote"origin"]' and re.match(r"url\s*=", text, re.IGNORECASE):
                url = text.split("=", 1)[1].strip()
                ssh = re.match(r"^(?:ssh://)?git@github\.com[:/](.+)$", url, re.IGNORECASE)
                return guard.gh_repo_name(ssh.group(1) if ssh else url)
        return None

    def stash_branches(self) -> list[str] | None:
        """The branch each stash entry was made on, newest (`stash@{0}`) first, from the stash's reflog."""
        log = os.path.join(self.common, "logs", "refs", "stash")
        if not os.path.isfile(log):
            return []
        lines = [line for line in self._read(log).splitlines() if line.strip()]
        branches = []
        for line in reversed(lines):
            match = self.STASH_LINE_RE.search(line)
            branches.append(match.group(1) if match else "")
        return branches


# --- the .gd post-edit hook (PostToolUse on Edit|Write) -------------------------------------------------------------


def project_gd(file_path: str, root: str = ROOT) -> str | None:
    """The repo-relative path of an edited project .gd file, or None when the hook should leave it alone."""
    if not file_path.lower().endswith(".gd"):
        return None
    path = os.path.abspath(file_path)
    base = os.path.abspath(root).rstrip("\\/") + os.sep
    if not os.path.normcase(path).startswith(os.path.normcase(base)):
        return None
    relative = path[len(base) :].replace("\\", "/")
    if relative.lower().startswith(SKIPPED_DIRS):
        return None
    return relative


def gdtoolkit_problems(relative: str, res: Result, tool: str) -> list[str]:
    """gdformat/gdlint output as `file:line: message` lines."""
    problems = []
    for line in res.lines:
        text = line.strip()
        parse = GDTOOLKIT_PARSE_RE.match(text)
        if parse:
            problems.append(f"{relative}:{parse.group(2)}: {tool}: {parse.group(1)} (column {parse.group(3)})")
        elif re.match(r"^.+\.gd:\d+: ", text):
            head, _, tail = text.partition(": ")
            problems.append(f"{head.replace(chr(92), '/')}: {tool}: {tail}")
    if res.rc != 0 and not problems:
        problems.append(f"{relative}: {tool} failed (exit {res.rc}): {res.out.strip()[-300:]}")
    return problems


def engine_lines(res: Result) -> tuple[list[str], list[str]]:
    """(errors, warnings) from check_project.gd, as `file:line: message` with res:// removed. Engine-internal lines
    (`modules/...cpp`) are dropped when a project file already explains the error."""
    errors, project, warnings = [], [], []
    for line in res.lines:
        match = CHECK_LINE_RE.match(line.strip())
        if not match:
            continue
        text = match.group(2)
        if match.group(1) == "warning":
            warnings.append(text.removeprefix("res://"))
            continue
        errors.append(text.removeprefix("res://"))
        if text.startswith("res://"):
            project.append(text.removeprefix("res://"))
    return (project or errors), warnings


def engine_check(res_path: str, budget: float = ENGINE_BUDGET) -> tuple[list[str], list[str]]:
    """Load one script in the engine. If that fails, import (the class cache may miss a new class_name) and retry,
    all within budget seconds."""
    import time

    from .common import godot

    deadline = time.monotonic() + budget
    args = ["--headless", "-d", "--ignore-error-breaks", "-s", "res://tools/check/check_project.gd", "--", res_path]

    def attempt() -> tuple[list[str], list[str]] | None:
        res = godot(args, timeout=max(1.0, deadline - time.monotonic()), log="hook-gd-check")
        if res.timed_out:
            return None
        if not any(line.startswith("CHECK summary") for line in res.lines):
            tail = " | ".join(res.lines[-5:])
            return [f"{res_path.removeprefix('res://')}: the engine check crashed (exit {res.rc}): {tail}"], []
        return engine_lines(res)

    timed_out = f"{res_path.removeprefix('res://')}: the engine check timed out after {budget:.0f}s"
    first = attempt()
    if first is None:
        return [timed_out], []
    if not first[0]:
        return first
    started = time.time()
    res = godot(["--headless", "--import"], timeout=max(1.0, deadline - time.monotonic()), log="hook-gd-import")
    if res.timed_out:
        return first
    if res.rc == 0:
        from .check import record_import

        record_import(started)  # the next launch need not import again (#174)
    second = attempt()
    return second if second is not None else ([timed_out], [])


def check_file(relative: str) -> tuple[list[str], list[str]]:
    """Format, restore LF, lint and engine-check one project .gd file: (problems, notes for Claude)."""
    from . import lint
    from .common import ROOT as root
    from .common import run

    path = root / relative
    before = path.read_bytes()
    problems: list[str] = []
    res = run([lint.exe("gdformat"), relative], timeout=GDTOOLKIT_TIMEOUT)
    lint.strip_cr(path)  # gdformat writes CRLF on Windows; the repo is LF
    problems += gdtoolkit_problems(relative, res, "gdformat") if res.rc != 0 else []
    res = run([lint.exe("gdlint"), relative], timeout=GDTOOLKIT_TIMEOUT)
    problems += gdtoolkit_problems(relative, res, "gdlint") if res.rc != 0 else []
    errors, warnings = engine_check("res://" + relative)
    notes = [f"gdformat reformatted {relative}: Read it again before the next Edit."] if path.read_bytes() != before else []
    notes += [f"engine warning: {w}" for w in warnings[:MAX_LINES]]
    return list(dict.fromkeys(errors + problems)), notes


def post_edit(payload: dict[str, object]) -> int:
    tool_input = payload.get("tool_input")
    raw = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    relative = project_gd(raw) if isinstance(raw, str) else None
    if relative is None or not os.path.isfile(os.path.join(ROOT, relative)):
        return 0
    from .common import Failure

    try:
        problems, notes = check_file(relative)
    except Failure as exc:
        sys.stderr.write(f"The .gd post-edit hook could not check {relative}: {exc}\n")
        return 2
    if problems:
        more = [f"... and {len(problems) - MAX_LINES} more"] if len(problems) > MAX_LINES else []
        lines = [f"GDScript problems in {relative}:", *problems[:MAX_LINES], *more, *notes]
        sys.stderr.write("\n".join(lines) + "\n")
        return 2
    if notes:
        _emit("PostToolUse", additionalContext="\n".join(notes))
    return 0

