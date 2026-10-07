"""The shell permission rules of `.claude/settings.json` as Claude Code applies them (docs/AGENT_WORKFLOW.md §8.1),
and a replay of local transcripts through those rules and the guard (§8.2).

A model of Claude Code's matcher, close enough for selftests and replays, not the real one
(`code.claude.com/docs/en/permissions`, checked 2026-10-04):
- A command is split into subcommands at `&&`, `||`, `;`, `|`, `&` and newlines, including the commands inside
  `$(...)` (guard.split). Each subcommand's text is its words joined by single spaces, after the wrappers `timeout`,
  `time`, `nice`, `nohup`, `stdbuf`, `command` and `builtin` and, for deny and ask rules, any leading `VAR=value`.
- A `*` matches any text, spaces included. A trailing ` *` (or `:*`) that is the rule's only wildcard also matches the
  bare command. PowerShell rules match case-insensitively.
- Deny beats ask beats allow, over all subcommands: one denied subcommand denies the call, one asked subcommand asks.
  The guard's findings ask too. A call is allowed when every subcommand matches an allow rule or is read-only:
  Claude Code's documented set (`cd`, `ls`, `cat`, `grep`, `find`, `diff`, `du`, ...; `find`, `sort` and `sed` without
  their write flags) and this model's guess of git's read-only forms (`status`, `diff`, `log`, `show`, `rev-parse`,
  ...; never after `git -C` or `-c`, nor in a call that `cd`s elsewhere, where Claude Code prompts for git). The
  default-mode counts are therefore an estimate, and auto mode's classifier approves more.
- In bypass mode (the engineer's) deny rules block, ask rules and the guard prompt, and everything else runs; in the
  modes that prompt, a call that is not allowed prompts as well.
- acceptEdits (`code.claude.com/docs/en/permission-modes`, "Auto-approve file edits with acceptEdits mode" and
  "Protected paths", checked 2026-10-07; a route-C successor manager and its workflows always run in it, #484)
  allows, besides the rules and the read-only set: the file tools (Edit, Write, NotebookEdit) and the filesystem
  commands `mkdir`, `touch`, `rm`, `rmdir`, `mv`, `cp` and `sed` (after the wrappers and a `LANG=`/`LC_ALL=`/`NO_COLOR=`
  prefix), and in PowerShell `Set-Content`, `Add-Content`, `Clear-Content` and `Remove-Item` with their aliases, when
  every path they name is in scope and not protected; and output redirects (`>`, `>>`, `2>`) to such a path. In scope:
  the session's working directory (the transcript's cwd: a manager's and its workflow agents' is the main checkout;
  this model counts a session in a worktree as working in the main checkout too)
  and, this model's assumption from the session prompt's "can be used without permission prompts", the session's
  scratchpad (`<temp>/claude/<project>/<session>/scratchpad`). Protected (prompts even in scope): `.git`, `.vscode`,
  `.idea`, `.husky`, `.cargo`, `.devcontainer`, `.yarn`, `.mvn`, `.config/git`, and `.claude` but for Claude's own
  worktrees `.claude/worktrees/<n>/` (a worktree's own `.claude/` is protected in this model), and files such as
  `.gitconfig`, `.gitmodules`, `.bashrc`, `.mcp.json` (PROTECTED_FILES). A PowerShell positional argument with a quote
  in it prompts. A path the model cannot resolve (an unknown variable, `$(...)`, `~`) is out of scope.
- Default mode prompts for every file write: an Edit or Write and an output redirect to a file (not `/dev/null` or
  `$null`). In the modes that prompt, a `cd` out of the working directory is not read-only.
- Built in, whatever the mode: `rm`/`rmdir` of a critical path (`/`, a drive root, a top-level folder, home, the
  working directory or a parent of it) prompts, even in bypass; `Remove-Item` of a wildcard (`*`, `x/*`, `x\\*`) or a
  system path is denied; `Remove-Item -Recurse` of the working directory or a parent of it prompts outside bypass.

Replay: `tools/run.sh permissions --before origin/main` (`run.cmd` in PowerShell) replays every Bash, PowerShell,
Edit, Write and NotebookEdit call in this project's transcripts (`~/.claude/projects/<project>` and
`<project>--claude-worktrees-*`) in bypass mode, with the settings and the guard of that revision against the ones in
this checkout, and prints the prompts before and after and every verdict that changed. `--since YYYY-MM-DD` keeps the
calls from that day on, `--mode acceptEdits` or `--mode default` models a mode that prompts, `--list` names each cause
with examples, and `--observed` reports what the transcripts record instead: the guard's asks, deny rule denials,
Claude Code's own blocks and the human's rejections (not an ask rule's prompt that the human approved, which leaves no
trace: take those from the replay).
"""

from __future__ import annotations

import argparse
import inspect
import json
import os
import re
import subprocess
import sys
import types
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import NamedTuple

from . import guard, hooks

ROOT = Path(__file__).resolve().parents[2]
SHELLS = {"Bash": guard.BASH, "PowerShell": guard.POWERSHELL}
# Wrappers Claude Code strips before matching, and the options of theirs that take a value.
WRAPPERS = {"timeout", "time", "nice", "nohup", "stdbuf", "command", "builtin"}
WRAPPER_VALUED = {"-n", "-s", "-k", "-i", "-o", "-e"}
# Bash control flow: Claude Code checks the commands of a loop or a condition ("a control-flow body such as a for
# loop"), not the keywords. Those before a command are stripped like wrappers; a loop header or a closing word alone
# runs nothing (a `$(...)` in it is judged on its own).
CONTROL_PREFIXES = {"do", "then", "else", "elif", "if", "while", "until", "!", "{"}
CONTROL_ALONE = {"for", "done", "fi", "esac", "}", "case", "select"}
# Commands Claude Code runs without a rule: its documented read-only set (code.claude.com/docs/en/permissions,
# "Read-only commands", checked 2026-10-04) and `sort` and `sed`, which it names as read-only with write-capable
# flags; the two PowerShell cmdlets are this model's own guess (the docs list no PowerShell set).
READ_ONLY = {
    "cd", "echo", "ls", "cat", "pwd", "head", "tail", "grep", "find", "wc", "which", "diff", "stat", "du", "sort",
    "sed", "set-location", "get-content",
}  # fmt: skip
FIND_WRITES = {"-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"}
# "read-only forms of git": the docs name none, so this is the model's guess of the plainly read-only subcommands
# (with `worktree list`, `stash list`, `remote [-v|show|get-url]` and `config --get*|--list`).
GIT_READ_ONLY = {
    "status", "diff", "log", "show", "rev-parse", "merge-base", "ls-files", "ls-tree", "grep", "blame", "describe",
    "shortlog", "cat-file", "for-each-ref", "show-ref", "rev-list", "check-ignore", "version", "help",
}  # fmt: skip
DENY, ASK, ALLOW, NONE = "deny", "ask", "allow", "none"
# Verdicts: PASS runs without a prompt, PROMPT stops for the human (a rule, the guard or no allow rule), DENIED never
# runs.
PASS, PROMPT, DENIED = "pass", "prompt", "denied"
BYPASS, ACCEPT_EDITS, DEFAULT = "bypass", "acceptEdits", "default"
MODES = (BYPASS, ACCEPT_EDITS, DEFAULT)
# The file tools: Edit rules cover all of them; acceptEdits writes with them in scope.
FILE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
# Leading assignments an allow rule matches past ("certain known-safe environment variables": the docs name LANG and
# NO_COLOR; LC_ALL is this model's guess).
SAFE_ENV = {"LANG", "LC_ALL", "NO_COLOR"}
# acceptEdits: the filesystem commands it runs on in-scope paths, in each shell (PowerShell aliases included).
EDIT_VERBS = {"mkdir", "touch", "rm", "rmdir", "mv", "cp", "sed"}
PS_EDIT_VERBS = {
    "set-content", "sc", "add-content", "ac", "clear-content", "clc",
    "remove-item", "ri", "rm", "rmdir", "del", "erase", "rd",
}  # fmt: skip
PS_REMOVE_VERBS = {"remove-item", "ri", "rm", "rmdir", "del", "erase", "rd"}
PS_PATH_OPTIONS = {"-path", "-literalpath", "-lp", "-pspath"}
PS_VALUED = {"-value", "-encoding", "-filter", "-include", "-exclude", "-stream", "-delimiter", "-credential"}
# Protected paths: writes there prompt in acceptEdits and default mode, whatever the rules say.
PROTECTED_DIRS = {".git", ".vscode", ".idea", ".husky", ".cargo", ".devcontainer", ".yarn", ".mvn", ".claude"}
PROTECTED_FILES = {
    ".gitconfig", ".gitmodules", ".bashrc", ".bash_profile", ".bash_login", ".bash_aliases", ".bash_logout", ".zshrc",
    ".zprofile", ".zshenv", ".zlogin", ".zlogout", ".profile", ".envrc", ".npmrc", ".yarnrc", ".yarnrc.yml",
    ".pnp.cjs", ".pnp.loader.mjs", ".pnpmfile.cjs", "bunfig.toml", ".bunfig.toml", ".bazelrc", ".bazelversion",
    ".bazeliskrc", ".pre-commit-config.yaml", "lefthook.yml", "lefthook.yaml", ".lefthook.yml", ".lefthook.yaml",
    "gradle-wrapper.properties", "maven-wrapper.properties", ".devcontainer.json", ".ripgreprc", "pyrightconfig.json",
    ".mcp.json", ".claude.json",
}  # fmt: skip
# Redirect targets with no file behind them.
NO_FILE = {"/dev/null", "$null", "nul", "/dev/stdout", "/dev/stderr"}
SCRATCHPAD_RE = re.compile(r"^[a-z]:/users/[^/]+/appdata/local/temp/claude/[^/]+/[^/]+/scratchpad(?=/|$)")
HOME = guard.normalize(str(Path.home()))


class Scope:
    """Where a session writes without a prompt in acceptEdits: its working directory and its scratchpad (the module
    docstring), minus the protected paths."""

    def __init__(self, cwd: str, home: str = HOME) -> None:
        # This model's simplification: a session in a worktree counts as working in the main checkout, as a manager
        # and its workflow agents do, so the project's other checkouts are in its scope (Claude Code may ask there).
        self.root = guard.project_root(guard.normalize(cwd or str(ROOT)))
        self.home = home

    def base(self, path: str) -> str | None:
        """The in-scope folder path is in (the working directory or the scratchpad), or None."""
        if path == self.root or path.startswith(self.root + "/"):
            return self.root
        match = SCRATCHPAD_RE.match(path)
        return match.group(0) if match else None

    def problem(self, path: str | None) -> str:
        """"" when acceptEdits writes path without a prompt, else why not."""
        if path is None or path == guard.OUTSIDE or guard.GLOB_RE.search(path.rsplit("/", 1)[0]):
            return "a path it cannot resolve"
        base = self.base(path)
        if base is None:
            return "outside the working directory"
        parts = [p for p in path[len(base) :].split("/") if p]
        if parts[:2] == [".claude", "worktrees"] and len(parts) > 2:
            parts = parts[3:]  # Claude's own worktrees are not protected; what is inside them may be
        for index, part in enumerate(parts):
            if part in PROTECTED_DIRS or (part == ".config" and parts[index + 1 : index + 2] == ["git"]):
                return f"protected path {part}"
        if parts and parts[-1] in PROTECTED_FILES:
            return f"protected path {parts[-1]}"
        return ""

    def critical(self, path: str | None) -> bool:
        """An `rm`/`rmdir` target Claude Code always asks for: `/`, a drive root or top-level folder, home, the
        working directory or one of its parents."""
        if path is None or path == guard.OUTSIDE:
            return False
        if re.fullmatch(r"/[^/]*|[a-z]:(/[^/]+)?", path) or path == self.home:
            return True
        return path == self.root or self.root.startswith(path + "/")

    def system(self, path: str | None) -> bool:
        """A `Remove-Item` target Claude Code denies: `/`, a drive root or top-level folder, home."""
        return path is not None and (bool(re.fullmatch(r"/[^/]*|[a-z]:(/[^/]+)?", path)) or path == self.home)


class Part(NamedTuple):
    """One simple command of a call, as the rules match it, with what acceptEdits and the built-in checks need."""

    text: str  # its words joined by single spaces (rules match this)
    redirects: tuple[str | None, ...]  # its output redirect targets that are files, resolved (None: unknown)
    targets: tuple[str | None, ...]  # for a filesystem command (EDIT_VERBS, PS_EDIT_VERBS): the paths it names
    raw_targets: tuple[str, ...]  # the same, as written
    cd: str | None  # for a `cd`: where it goes (None: unknown), else ""
    quoted: bool  # a PowerShell positional argument with a quote in it
    recurse: bool  # `Remove-Item -Recurse`
    cwd: str | None  # where it runs
    verb: str  # its command, wrappers and safe assignments stripped, lower case
    edit: bool  # a filesystem command acceptEdits may run (EDIT_VERBS, PS_EDIT_VERBS)


class Rules:
    """The Bash and PowerShell rules of one settings file."""

    def __init__(self, settings: dict) -> None:
        permissions = settings.get("permissions", {})
        self.lists = {kind: [_parse(r) for r in permissions.get(kind, [])] for kind in (DENY, ASK, ALLOW)}

    @classmethod
    def load(cls, path: Path) -> Rules:
        return cls(json.loads(path.read_text(encoding="utf-8")))

    def matches(self, kind: str, tool: str, text: str) -> str | None:
        """The first rule of the list kind that matches one subcommand's text, as written in the settings."""
        for rule_tool, pattern, written in self.lists[kind]:
            if rule_tool == tool and pattern is not None and pattern.fullmatch(text):
                return written
        return None

    def judge(self, tool: str, command: str, cwd: str = "", mode: str = "") -> tuple[str, str | None]:
        """(deny, ask, allow or none; the rule that decided) for one Bash or PowerShell call, without the guard. With
        cwd, a `cd` elsewhere in the same call takes git out of the read-only set. With a mode that prompts
        (ACCEPT_EDITS, DEFAULT), what that mode adds: acceptEdits' filesystem commands, and the checks of redirect
        and `cd` targets; without one, the rules and the read-only set alone."""
        return self.judge_parts(tool, parts(command, SHELLS[tool], cwd), cwd, mode)

    def judge_parts(self, tool: str, found: list[Part], cwd: str = "", mode: str = "") -> tuple[str, str | None]:
        texts = [p.text for p in found]
        for kind in (DENY, ASK):
            for text in texts:
                rule = self.matches(kind, tool, strip(text, assignments=True))
                if rule:
                    return kind, rule
        allowed = [self._allows(tool, p, _moves(texts, cwd), Scope(cwd), mode)[0] for p in found]
        if texts and all(allowed):
            return ALLOW, next((r for r in allowed if r != "read-only"), "read-only")
        return NONE, None

    def _allows(self, tool: str, part: Part, moved: bool, scope: Scope, mode: str) -> tuple[str | None, str]:
        """(what lets the subcommand run, or None; why not, when the mode's own checks stopped it)."""
        stripped = strip(part.text, assignments=False)
        allowed = self.matches(ALLOW, tool, stripped) or read_only(stripped, git=not moved)
        if mode not in (ACCEPT_EDITS, DEFAULT):
            return allowed, ""
        if allowed == "read-only" and part.cd != "" and (part.cd is None or scope.base(part.cd) != scope.root):
            return None, "outside the working directory"
        detail = ""
        if not allowed and mode == ACCEPT_EDITS and part.edit:
            problems = [scope.problem(t) for t in part.targets] + ["a quoted argument" if part.quoted else ""]
            detail = next((p for p in problems if p), "")
            allowed = None if detail else "acceptEdits"
        if allowed:
            for target in part.redirects:
                why = "a file" if mode == DEFAULT else scope.problem(target)
                if why:
                    return None, f"> {why}"
        return allowed, detail

    def unallowed(self, tool: str, command: str, cwd: str = "", mode: str = "") -> str:
        """The command name (`git -C`, `sed`) of the first subcommand that neither an allow rule nor the read-only set
        (nor, in acceptEdits, its filesystem commands) lets run, with the mode's reason when it has one (`rm (outside
        the working directory)`): what prompts outside bypass."""
        found = parts(command, SHELLS[tool], cwd)
        texts = [p.text for p in found]
        for part in found:
            allowed, detail = self._allows(tool, part, _moves(texts, cwd), Scope(cwd), mode)
            if not allowed:
                return head(strip(part.text, assignments=True)) + (f" ({detail})" if detail else "")
        return "?"


def head(text: str) -> str:
    """A subcommand's name for a report: the program, and for git and gh their subcommand (or `git -C`)."""
    words = text.split(" ")
    if words[0].lower() in ("git", "gh") and len(words) > 1:
        return f"{words[0].lower()} {words[1]}"
    return words[0] if words[0].startswith("$") else words[0].lower()


def _parse(rule: str) -> tuple[str, re.Pattern[str] | None, str]:
    match = re.fullmatch(r"(\w+)(?:\((.*)\))?", rule, re.DOTALL)
    if not match:
        return "", None, rule
    tool, body = match.group(1), match.group(2)
    if body is None:
        return tool, re.compile(r".*", re.DOTALL), rule
    if body.endswith(":*"):
        body = body[:-2] + " *"
    flags = re.DOTALL | (re.IGNORECASE if tool == "PowerShell" else 0)
    if body.endswith(" *") and body.count("*") == 1:
        return tool, re.compile(re.escape(body[:-2]) + r"(?: .*)?", flags), rule
    return tool, re.compile(".*".join(re.escape(part) for part in body.split("*")), flags), rule


def subcommands(command: str, shell: str) -> list[str]:
    """The text of each simple command, the ones inside `$(...)` included."""
    return [part.text for part in parts(command, shell)]


def parts(command: str, shell: str, cwd: str = "") -> list[Part]:
    """Each simple command of a call, the ones inside `$(...)` included, with its paths resolved against cwd (the
    working directory, then each `cd`) and the variables the call assigns, as the guard resolves them."""
    paths = guard.Paths(cwd or str(ROOT), cwd or str(ROOT), HOME, shell)
    found: list[Part] = []
    _walk(command, shell, paths, found, 0)
    return found


def _walk(command: str, shell: str, paths: guard.Paths, found: list[Part], depth: int) -> None:
    scopes: list[tuple] = []
    for segment in guard.split(command, shell):
        if segment.scope == "(":
            scopes.append(paths.save())
            continue
        if segment.scope == ")":
            if scopes:
                paths.restore(scopes.pop())
            continue
        words = segment.words
        if words:
            paths.assign(list(words))
        if shell == guard.POWERSHELL and len(words) > 1 and words[0].startswith("$") and words[1] == "=":
            # `$x = <command>` runs the command; `$x = <a literal>` runs nothing: a quoted string (split drops the
            # quotes, so the command text is asked), a number, a variable, `[type]`, `@(...)`, `@{...}` or `(...)`,
            # whose `$(...)` split judges on its own. (`$x = & <command>`: split cuts at the `&`.)
            rest = words[2:]
            quoted = rest and re.search(
                re.escape(words[0]) + r"\s*=\s*(['\"])" + re.escape(rest[0]) + r"\1", command, re.IGNORECASE
            )
            words = [""] if not rest or quoted or re.match(r"^[$\d\[@]", rest[0]) else rest
        elif shell == guard.BASH and words and all(re.match(r"^[A-Za-z_]\w*=", w) for w in words):
            # A bare assignment runs nothing (a `$(...)` in it is judged on its own), unless it sets PATH or IFS.
            words = words if any(re.match(r"^(PATH|IFS)=", w) for w in words) else [""]
        if words:
            found.append(_part(" ".join(words), segment, shell, paths))
        for sub in segment.subs:
            if depth < 3:
                saved = paths.save() if shell == guard.BASH else None  # a bash `$(...)` is a subshell
                _walk(sub, shell, paths, found, depth + 1)
                if saved is not None:
                    paths.restore(saved)


def _part(text: str, segment: guard.Segment, shell: str, paths: guard.Paths) -> Part:
    """One subcommand's Part; a `cd` moves paths for the rest of the call."""
    redirects = tuple(paths.resolve(t) for t in segment.redirects if t.lower() not in NO_FILE)
    words = strip(text, assignments=False).split(" ")
    verb, args = words[0].lower(), words[1:]
    where = paths.cwd
    if verb in guard.CD_VERBS or verb in ("popd", "pop-location"):
        paths.cd(verb, args)
        return Part(text, redirects, (), (), paths.cwd, False, False, where, verb, False)
    raw: list[str] = []
    quoted = recurse = False
    edit = verb in (EDIT_VERBS if shell == guard.BASH else PS_EDIT_VERBS)
    if edit and shell == guard.BASH:
        raw = _bash_paths(verb, args)
        # sed edits files in place; a script that writes (`w`) or runs (`e`) another file is not a plain edit.
        edit = verb != "sed" or _sed_read_only([a for a in args if not re.match(r"^(-[^-]*i|--in-place)", a)])
    elif edit:
        raw, quoted, recurse = _ps_paths(args)
    items = [item for token in raw for item in paths.items(token)]
    targets = tuple(paths.resolve(item) for item in items)
    return Part(text, redirects, targets, tuple(items), "", quoted, recurse, where, verb, edit)


def _bash_paths(verb: str, args: list[str]) -> list[str]:
    """The paths a Bash filesystem command names: its positional arguments (for sed, after its script) and the value
    of `-t`/`--target-directory`; the values of `mkdir -m` and of `-S` are none."""
    found: list[str] = []
    script = verb != "sed"  # sed's first positional argument is its script, unless -e or -f gave one
    i, end = 0, False
    while i < len(args):
        arg = args[i]
        if not end and arg == "--":
            end = True
        elif not end and arg.startswith("-") and arg != "-":
            if verb == "sed" and arg in ("-e", "--expression", "-f", "--file"):
                script, i = True, i + 1
            elif arg in ("-t", "--target-directory") and verb in ("cp", "mv"):
                found += args[i + 1 : i + 2]
                i += 1
            elif arg.startswith("--target-directory="):
                found.append(arg.split("=", 1)[1])
            elif (verb == "mkdir" and arg in ("-m", "--mode")) or (verb in ("cp", "mv") and arg in ("-S", "--suffix")):
                i += 1
        elif not script:
            script = True
        else:
            found.append(arg)
        i += 1
    return found


def _ps_paths(args: list[str]) -> tuple[list[str], bool, bool]:
    """(the paths a PowerShell content or delete cmdlet names, a positional argument has a quote in it, -Recurse):
    `-Path`/`-LiteralPath` values, else its first positional argument (Set-Content's second is the value)."""
    found: list[str] = []
    positional: list[str] = []
    recurse = False
    i = 0
    while i < len(args):
        arg = args[i]
        name, _, attached = arg.lower().partition(":")
        if name.startswith("-") and len(name) > 1:
            if name in PS_PATH_OPTIONS:
                value = attached if attached else (args[i + 1] if i + 1 < len(args) else "")
                i += 0 if attached else 1
                found += [v for v in value.split(",") if v]
            elif "-recurse".startswith(name) and len(name) > 1:
                recurse = True
            elif name in PS_VALUED and not attached:
                i += 1
        else:
            positional.append(arg)
        i += 1
    if not found and positional:
        found = [v for v in positional[0].split(",") if v]
    return found, any("'" in p or '"' in p for p in positional), recurse


def strip(text: str, assignments: bool) -> str:
    """The subcommand without the wrappers Claude Code strips and leading assignments: for deny and ask rules any,
    for allow rules those of SAFE_ENV."""
    words = text.split(" ")
    changed = True
    while words and changed:
        changed = False
        if re.match(r"^[A-Za-z_]\w*=", words[0]) and (assignments or words[0].split("=", 1)[0] in SAFE_ENV):
            words, changed = words[1:], True
        elif words[0] in CONTROL_PREFIXES and len(words) > 1:
            words, changed = words[1:], True
        elif words[0] in WRAPPERS and len(words) > 1 and words[1] != "-v":
            prefix, words, changed = words[0], words[1:], True
            while words and words[0].startswith("-"):
                words = words[2:] if words[0] in WRAPPER_VALUED else words[1:]
            if prefix == "timeout" and words and re.match(r"^\d", words[0]):
                words = words[1:]
    return " ".join(words)


def read_only(text: str, git: bool = True) -> str | None:
    """"read-only" when Claude Code would run this subcommand (wrappers stripped) without a rule, as far as its docs
    say: the commands of READ_ONLY without their write flags, and git's read-only forms (GIT_READ_ONLY) unless git is
    False."""
    if text == "":
        return "read-only"  # a bare assignment (subcommands)
    words = text.split(" ")
    first = words[0].lower()
    if words[0] in CONTROL_ALONE or (words[0] in CONTROL_PREFIXES and len(words) == 1):
        return "read-only"
    if first == "git":
        return "read-only" if git and _git_read_only(words[1:]) else None
    if first not in READ_ONLY:
        return None
    args = words[1:]
    if first == "find" and any(w in FIND_WRITES for w in args):
        return None
    if first == "sort" and any(w.startswith("--output") or re.match(r"^-[^-]*o", w) for w in args):
        return None
    if first == "sed" and not _sed_read_only(args):
        return None
    return "read-only"


def _git_read_only(args: list[str]) -> bool:
    """A git subcommand that only reads, with no global option before it (`git -C x` and `git -c k=v` change where git
    runs or what it runs) and no `--output`."""
    if not args or args[0].startswith("-") or any(a.startswith("--output") for a in args):
        return False
    sub, rest = args[0], args[1:]
    if sub in GIT_READ_ONLY:
        return True
    if sub in ("worktree", "stash") and rest[:1] == ["list"]:
        return True
    if sub == "remote":
        return not rest or rest[0] in ("-v", "--verbose", "show", "get-url")
    if sub == "config":
        return bool(rest) and rest[0] in ("--get", "--get-all", "--get-regexp", "--list", "-l", "--show-origin")
    return False


def _sed_read_only(args: list[str]) -> bool:
    """sed without `-i`/`--in-place` (also inside a cluster: `-ni`, `-i.bak`) and without a `w`, `W` or `e` command in
    a script (`1,5w out`, `s/a/b/w out`): when unsure, not read-only."""
    for arg in args:
        if arg.startswith("--in-place") or re.match(r"^-[^-]*i", arg):
            return False
    scripts = [a for a in args if not a.startswith("-")][:1] + [
        args[i + 1] for i, a in enumerate(args[:-1]) if a in ("-e", "--expression")
    ]
    return not any(re.search(r"(?:^|[;{}\d$/])\s*[wWe](?:\s|$)|^s(.).*\1.*\1[a-zA-Z0-9]*[we]", s) for s in scripts)


def _moves(texts: list[str], cwd: str) -> bool:
    """A `cd`, `Set-Location` or `Push-Location` in the call into a folder other than cwd: Claude Code then prompts for
    git even in its read-only forms, since git runs that folder's hooks."""
    if not cwd:
        return False
    for text in texts:
        words = text.split(" ")
        if words[0].lower() in ("cd", "set-location", "push-location", "sl", "pushd") and len(words) > 1:
            if _folder(words[-1].strip("'\"")) != _folder(cwd):
                return True
    return False


def _folder(path: str) -> str:
    path = re.sub(r"^/([a-zA-Z])/", r"\1:/", path.replace("\\", "/") + "/")
    return path.rstrip("/").lower()


def verdict(
    rules: Rules, guard_module: types.ModuleType, tool: str, command: str, cwd: str, root: str, repo: object,
    mode: str = BYPASS, cloud: bool = False,
) -> tuple[str, str]:  # fmt: skip
    """(PASS, PROMPT or DENIED; why) for one call in mode (MODES): deny rules, Claude Code's built-in denials, ask
    rules, its built-in prompts, the guard (it asks in every mode), then what the mode lets run. A file tool's
    command is its path."""
    if tool in FILE_TOOLS:
        return file_verdict(rules, command, cwd, mode)
    found = parts(command, SHELLS[tool], cwd)
    kind, rule = rules.judge_parts(tool, found, cwd, mode)
    if kind == DENY:
        return DENIED, f"deny rule {rule}"
    built_in = builtin(tool, found, Scope(cwd), mode)
    if built_in and built_in[0] == DENIED:
        return built_in
    if kind == ASK:
        return PROMPT, f"ask rule {rule}"
    if built_in:
        return built_in
    # A cloud session's main checkout on its task branch is its own (#381); a guard from before that takes no cloud.
    extra = {"cloud": cloud} if "cloud" in inspect.signature(guard_module.check).parameters else {}
    findings = guard_module.check(command, SHELLS[tool], cwd, root, "", repo, **extra)
    if findings:
        return PROMPT, "guard: " + ", ".join(sorted({f.area for f in findings}))
    if kind == NONE and mode != BYPASS:
        return PROMPT, "no allow rule: " + rules.unallowed(tool, command, cwd, mode)
    return PASS, ("acceptEdits" if rule == "acceptEdits" else "allow rule") if kind == ALLOW else "no rule"


def file_verdict(rules: Rules, path: str, cwd: str, mode: str) -> tuple[str, str]:
    """(PASS, PROMPT or DENIED; why) for an Edit, Write or NotebookEdit of path: Edit deny and ask rules in every
    mode; bypass writes anything else, acceptEdits what is in scope and not protected, default mode nothing."""
    target = guard.normalize(path) if re.match(r"^([A-Za-z]:)?[\\/]", path) else guard.normalize(f"{cwd}/{path}")
    for kind, verdict_ in ((DENY, DENIED), (ASK, PROMPT)):
        if rule := rules.matches(kind, "Edit", target):
            return verdict_, f"{kind} rule {rule}"
    if mode == BYPASS:
        return PASS, "no rule"
    problem = "a file" if mode == DEFAULT else Scope(cwd).problem(target)
    return (PROMPT, f"no allow rule: edit ({problem})") if problem else (PASS, "acceptEdits")


def builtin(tool: str, found: list[Part], scope: Scope, mode: str) -> tuple[str, str] | None:
    """Claude Code's own checks of deletes (the module docstring), whatever the rules say: (DENIED or PROMPT; why),
    or None."""
    for part in found:
        if tool == "PowerShell" and part.edit and part.verb in PS_REMOVE_VERBS:
            for raw, target in zip(part.raw_targets, part.targets):
                if raw == "*" or raw.endswith(("/*", "\\*")):
                    return DENIED, "Claude Code: Remove-Item of a wildcard"
                if scope.system(target):
                    return DENIED, "Claude Code: Remove-Item of a system path"
            if part.recurse and mode != BYPASS and any(scope.critical(t) for t in part.targets):
                return PROMPT, "Claude Code: Remove-Item -Recurse of the working directory"
        elif tool == "Bash" and part.verb in ("rm", "rmdir"):
            for raw, target in zip(part.raw_targets, part.targets):
                if scope.critical(target) or (target is None and re.match(r"^\$\{?\w+\}?/+\*?$", raw)):
                    return PROMPT, "Claude Code: rm of a critical path"
    return None


# --- replay of local transcripts -------------------------------------------------------------------------------------


class Call(NamedTuple):
    """One Bash or PowerShell call of a transcript."""

    tool: str
    command: str
    cwd: str
    when: str  # the entry's ISO timestamp, "" when it has none
    role: str  # "session", "subagent" (a hand-made one) or "workflow" (a workflow script's agent)
    transcript: str


def role(path: Path) -> str:
    """Who wrote a transcript, from where Claude Code keeps it: `<session>/subagents/workflows/<run>/agent-*.jsonl` is a
    workflow agent's, `<session>/subagents/agent-*.jsonl` a hand subagent's, anything else a session's."""
    text = path.as_posix()
    return "workflow" if "/subagents/workflows/" in text else "subagent" if "/subagents/" in text else "session"


def calls(folders: list[Path], since: str = "") -> list[Call]:
    """Every Bash, PowerShell and file tool call in the transcripts under folders, from the day since (YYYY-MM-DD)
    on; a file tool's command is the path it writes."""
    found = []
    for folder in folders:
        for path in sorted(folder.rglob("*.jsonl")):
            with path.open(encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    if '"tool_use"' not in line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    when = str(entry.get("timestamp") or "")
                    if since and when < since:
                        continue
                    content = (entry.get("message") or {}).get("content")
                    for item in content if isinstance(content, list) else []:
                        given = (item.get("input") or {}) if isinstance(item, dict) else {}
                        name = item.get("name") if isinstance(item, dict) else None
                        key = "command" if name in SHELLS else "file_path"
                        key = "notebook_path" if name == "NotebookEdit" else key
                        command = given.get(key) if isinstance(given, dict) else None
                        tool = item.get("type") == "tool_use" and name in (*SHELLS, *FILE_TOOLS)
                        if tool and isinstance(command, str):
                            cwd = str(entry.get("cwd") or ROOT)
                            found.append(Call(item["name"], command, cwd, when, role(path), str(path)))
    return found


def old_guard(revision: str) -> types.ModuleType:
    """guard.py as it was at revision, loaded from git as a module of its own (it imports only the standard library)."""
    source = subprocess.run(
        ["git", "show", f"{revision}:tools/runner/guard.py"], cwd=ROOT, capture_output=True, check=True
    ).stdout.decode("utf-8")
    module = types.ModuleType("guard_" + re.sub(r"\W", "_", revision))
    sys.modules[module.__name__] = module  # dataclass-free, but `from __future__` annotations look the module up
    exec(compile(source, f"{revision}:tools/runner/guard.py", "exec"), module.__dict__)  # noqa: S102
    return module


def old_settings(revision: str) -> Rules:
    text = subprocess.run(
        ["git", "show", f"{revision}:.claude/settings.json"], cwd=ROOT, capture_output=True, check=True
    ).stdout.decode("utf-8")
    return Rules(json.loads(text))


class ReplayRepo:
    """The live repository reader, without the live sessions: a replay judges old calls, not who works now."""

    def __init__(self, root: str) -> None:
        from .hooks import GitFiles

        self.files = GitFiles(root)

    def __getattr__(self, name: str) -> object:
        return getattr(self.files, name)

    def busy(self, checkout: str) -> bool:
        return False


def replay(
    before: tuple[Rules, types.ModuleType], after: tuple[Rules, types.ModuleType], folders: list[Path],
    since: str = "", mode: str = BYPASS, listing: bool = False,
) -> str:  # fmt: skip
    """The report: prompts and denials before and after, by cause, and every call whose verdict changed; with listing,
    each cause of the after side that stops a call, with its count by role and up to three example commands."""
    root = str(ROOT).replace("\\", "/")
    main = re.sub(r"/\.claude/worktrees/[^/]+$", "", root)
    repo = ReplayRepo(main)
    cloud = hooks.cloud_session()  # judged as this machine's sessions: a cloud container replays cloud transcripts
    found = calls(folders, since)
    totals: dict[str, Counter[str]] = {"before": Counter(), "after": Counter()}
    changed: Counter[tuple[str, str, str]] = Counter()
    causes: dict[tuple[str, str], Counter[str]] = {}
    examples: dict[tuple[str, str], list[str]] = {}
    crashes = 0
    for call in found:
        results = {}
        for name, (rules, module) in (("before", before), ("after", after)):
            try:
                results[name] = verdict(rules, module, call.tool, call.command, call.cwd, main, repo, mode, cloud)
            except Exception as exc:  # noqa: BLE001 - a replay reports crashes instead of stopping
                crashes += 1
                results[name] = (PROMPT, f"crash {type(exc).__name__}")
            state, why = results[name]
            totals[name][state] += 1
            totals[name][why.split(":")[0].split(" rule")[0]] += 1
        state, why = results["after"]
        if listing and state != PASS:
            causes.setdefault((state, why), Counter())[call.role] += 1
            seen = examples.setdefault((state, why), [])
            if len(seen) < 3 and call.command[:160] not in seen:
                seen.append(call.command[:160])
        if results["before"][0] != results["after"][0]:
            change = results["before"][0] + " -> " + results["after"][0]
            changed[(change, results["before"][1], call.command[:160])] += 1
    transcripts = sum(1 for folder in folders for _ in folder.rglob("*.jsonl"))
    lines = [f"{len(found)} calls in {transcripts} transcripts; {crashes} crashes"]
    for name in ("before", "after"):
        t = totals[name]
        lines.append(
            f"{name}: {t[PROMPT]} prompts ({t['ask']} ask rules, {t['guard']} guard, {t['no allow']} no allow rule,"
            f" {t['Claude Code']} built-in),"
            f" {t[DENIED]} denied"
        )
    newly = sum(n for (change, _, _), n in changed.items() if change == f"{PASS} -> {PROMPT}")
    lines.append(f"changed verdicts: {sum(changed.values())}; silent before, asking now: {newly}")
    for (change, why, command), count in sorted(changed.items()):
        lines.append(f"  {change} x{count} [{why}] {command!r}")
    if listing:
        lines.append("after, by cause (count; by role; examples):")
        for (state, why), roles in sorted(causes.items(), key=lambda kv: (-sum(kv[1].values()), kv[0])):
            by_role = ", ".join(f"{r} {n}" for r, n in sorted(roles.items()))
            lines.append(f"  {state} [{why}] x{sum(roles.values())} ({by_role})")
            lines += [f"      {command!r}" for command in examples[(state, why)]]
    return "\n".join(lines)


# --- what the transcripts record: the real prompts, denials and blocks -----------------------------------------------

DENIED_TEXT = re.compile(r"Permission to use (\w+) with command (.*) has been denied\.", re.DOTALL)
REJECTED_TEXT = "The user doesn't want to proceed with this tool use"
PROTECTED_TEXT = re.compile(r"(\S+) on system path .* is blocked\. This path is protected from removal\.")


class Event(NamedTuple):
    """One call that something stopped, as its transcript records it."""

    kind: str  # "guard ask", "deny rule", "blocked" (Claude Code's own check) or "rejected" (the human said no)
    cause: str
    command: str
    when: str
    wait: float  # seconds from the call to its result: the human's answer plus, after a yes, the run (an upper bound)
    ran: bool  # the call ran after all (an ask answered yes)
    role: str


def _text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(str(i.get("text") or "") for i in content if isinstance(i, dict))
    return ""


def _seconds(start: str, end: str) -> float:
    try:
        return max(0.0, (datetime.fromisoformat(end) - datetime.fromisoformat(start)).total_seconds())
    except ValueError:
        return 0.0


def observed_events(folders: list[Path], rules: Rules, since: str = "") -> tuple[list[Event], int]:
    """(the events, the malformed entries skipped) of every transcript under folders, from the day since on: a guard
    ask or deny (the PreToolUse hook's permissionDecision), a deny rule's denial, Claude Code's own block (`Blocked:`
    and protected removal paths) and a human's rejection. A call seen in two transcripts (a resumed session) counts
    once. Blind spot: an ask rule's prompt (settings.json `ask`) that the human approved leaves no trace in the
    transcript, only a rejected one does; the replay's "ask rules" count holds those."""
    events: dict[str, Event] = {}
    skipped = 0
    for folder in folders:
        for path in sorted(folder.rglob("*.jsonl")):
            uses: dict[str, tuple[str, str]] = {}  # tool_use id: (command, timestamp)
            hooks: dict[str, tuple[str, str]] = {}  # tool_use id: (decision, reason)
            with path.open(encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    if not any(k in line for k in ('"tool_use"', '"tool_result"', "permissionDecision")):
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        skipped += 1
                        continue
                    when = str(entry.get("timestamp") or "")
                    attachment = entry.get("attachment")
                    if isinstance(attachment, dict) and attachment.get("hookEvent") == "PreToolUse":
                        try:
                            output = json.loads(attachment.get("stdout") or "{}").get("hookSpecificOutput") or {}
                        except (json.JSONDecodeError, AttributeError):
                            skipped += 1
                            continue
                        if output.get("permissionDecision") in ("ask", "deny"):
                            reason = str(output.get("permissionDecisionReason") or "")
                            hooks[str(attachment.get("toolUseID"))] = (output["permissionDecision"], reason)
                        continue
                    content = (entry.get("message") or {}).get("content")
                    for item in content if isinstance(content, list) else []:
                        if not isinstance(item, dict):
                            continue
                        if item.get("type") == "tool_use":
                            command = (item.get("input") or {}).get("command")
                            uses[str(item.get("id"))] = (command if isinstance(command, str) else "", when)
                            continue
                        if item.get("type") != "tool_result":
                            continue
                        key = str(item.get("tool_use_id"))
                        command, start = uses.get(key, ("", when))
                        if since and start < since:
                            continue
                        text = _text(item.get("content")).strip()
                        wait = _seconds(start, when)
                        found = None
                        if key in hooks:
                            decision, reason = hooks[key]
                            cause = reason.split(":", 1)[0]
                            ran = not text.startswith(REJECTED_TEXT)  # a failing command ran too
                            found = Event("guard " + decision, cause, command, start, wait, ran, role(path))
                        elif match := DENIED_TEXT.match(text):
                            tool, denied = match.group(1), match.group(2)
                            command = command or denied
                            judged = rules.judge(tool, command) if tool in SHELLS else (NONE, None)
                            cause = judged[1] if judged[0] == DENY else "a deny rule no longer in the settings"
                            found = Event("deny rule", str(cause), command, start, wait, False, role(path))
                        elif text.startswith("<tool_use_error>Blocked: "):
                            cause = re.sub(r"\d+", "N", text[len("<tool_use_error>") :].split(" followed by")[0])
                            found = Event("blocked", cause[:80], command, start, wait, False, role(path))
                        elif match := PROTECTED_TEXT.match(text):
                            cause = f"{match.group(1)} on a protected system path"
                            found = Event("blocked", cause, command, start, wait, False, role(path))
                        elif text.startswith(REJECTED_TEXT):
                            found = Event("rejected", "the human said no", command, start, wait, False, role(path))
                        if found:
                            events.setdefault(key, found)
    return list(events.values()), skipped


def observed(folders: list[Path], rules: Rules, since: str = "") -> str:
    """The report of observed_events, by kind and cause: count, roles, days, the wait and whether the call ran."""
    events, skipped = observed_events(folders, rules, since)
    transcripts = sum(1 for folder in folders for _ in folder.rglob("*.jsonl"))
    lines = [
        f"{len(events)} stopped calls in {transcripts} transcripts ({skipped} malformed entries skipped); wait ="
        " seconds from the call to its result, an upper bound of the human's answer (after a yes the run is in it)",
        "not here: an ask rule's prompt the human approved (no trace in the transcript; see the replay's ask rules)",
    ]
    groups: dict[tuple[str, str], list[Event]] = {}
    for event in events:
        groups.setdefault((event.kind, event.cause), []).append(event)
    for (kind, cause), group in sorted(groups.items(), key=lambda kv: (kv[0][0], -len(kv[1]), kv[0][1])):
        roles = Counter(e.role for e in group)
        days = sorted(e.when[:10] for e in group if e.when)
        span = f"{days[0]}..{days[-1]}" if days else "?"
        waits = [e.wait for e in group]
        lines.append(
            f"{kind} [{cause}] x{len(group)} ({', '.join(f'{r} {n}' for r, n in sorted(roles.items()))}) {span};"
            f" wait {sum(waits):.0f} s, longest {max(waits):.0f} s; ran {sum(e.ran for e in group)}"
        )
        shown: list[str] = []
        for event in group:
            if len(shown) < 3 and event.command[:160] not in shown:
                shown.append(event.command[:160])
        lines += [f"      {command!r}" for command in shown]
    return "\n".join(lines)


def project_folders(base: Path, main_root: str, pattern: str = "") -> list[Path]:
    """The transcript folders of this project: the main checkout's and its worktrees' (`<slug>--claude-worktrees-*`),
    never a sibling repository's whose name only starts the same (`D--prime-game-art`); or those matching pattern."""
    if pattern:
        return sorted(p for p in base.glob(pattern) if p.is_dir())
    slug = re.sub(r"[^A-Za-z0-9]", "-", main_root)
    return sorted(p for p in [base / slug, *base.glob(slug + "--claude-worktrees-*")] if p.is_dir())


def _day(text: str) -> str:
    """text as a zero-padded YYYY-MM-DD day, or "" when it is not one (strptime alone accepts `2026-9-29`)."""
    try:
        return datetime.strptime(text, "%Y-%m-%d").strftime("%Y-%m-%d")
    except ValueError:
        return ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="run permissions", description=__doc__.split("\n\n")[0])
    parser.add_argument("--before", default="origin/main", help="the revision to compare with (default origin/main)")
    parser.add_argument(
        "--projects",
        default="",
        help="transcript folders glob under ~/.claude/projects (default: this project's and its worktrees')",
    )
    parser.add_argument("--since", default="", help="only calls from this day on (YYYY-MM-DD, UTC)")
    parser.add_argument(
        "--mode",
        choices=list(MODES),
        default=BYPASS,
        help="bypass: only deny and ask rules, the guard and Claude Code's built-in delete checks stop a call"
        " (default); acceptEdits: also what neither an allow rule, the read-only set nor its in-scope file writes"
        " cover; default: also every file write (a model: an upper bound)",
    )
    parser.add_argument("--list", action="store_true", help="also list each cause that stops a call, with examples")
    parser.add_argument(
        "--observed",
        action="store_true",
        help="instead of a replay, what the transcripts record: guard asks, deny rule denials, Claude Code's blocks"
        " (not an approved ask rule prompt, which leaves no trace: the replay counts those)",
    )
    args = parser.parse_args(argv)
    if args.since and _day(args.since) != args.since:  # compared as text with the transcripts' ISO timestamps
        parser.error(f"--since {args.since}: not a YYYY-MM-DD day")
    base = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / "projects"
    main_root = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT))
    pattern = args.projects or re.sub(r"[^A-Za-z0-9]", "-", main_root) + "{,--claude-worktrees-*}"
    folders = project_folders(base, main_root, args.projects)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    if args.observed:
        print(f"observed in {pattern}" + (f" since {args.since}" if args.since else ""))
        print(observed(folders, Rules.load(ROOT / ".claude" / "settings.json"), args.since))
        return 0
    before = (old_settings(args.before), old_guard(args.before))
    after = (Rules.load(ROOT / ".claude" / "settings.json"), guard)
    since = f" since {args.since}" if args.since else ""
    print(f"replay of {pattern}{since} in {args.mode} mode: {args.before} against this checkout")
    print(replay(before, after, folders, args.since, args.mode, args.list))
    return 0


if __name__ == "__main__":
    sys.exit(main())
