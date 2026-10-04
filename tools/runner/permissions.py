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

Replay: `tools/run.sh permissions --before origin/main` (`run.cmd` in PowerShell) replays every Bash and
PowerShell call in this project's transcripts (`~/.claude/projects/<project>` and `<project>--claude-worktrees-*`) in
bypass mode, with the settings and the guard of that revision against the ones in this checkout, and prints the
prompts before and after and every verdict that changed. `--since YYYY-MM-DD` keeps the calls from that day on,
`--mode default` models a mode that prompts, `--list` names each cause with examples, and `--observed` reports what the
transcripts record instead: the guard's asks, deny rule denials, Claude Code's own blocks and the human's rejections.
"""

from __future__ import annotations

import argparse
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

from . import guard

ROOT = Path(__file__).resolve().parents[2]
SHELLS = {"Bash": guard.BASH, "PowerShell": guard.POWERSHELL}
# Wrappers Claude Code strips before matching, and the options of theirs that take a value.
WRAPPERS = {"timeout", "time", "nice", "nohup", "stdbuf", "command", "builtin"}
WRAPPER_VALUED = {"-n", "-s", "-k", "-i", "-o", "-e"}
# Commands Claude Code runs without a rule: its documented read-only set (code.claude.com/docs/en/permissions, "Read-only
# commands", checked 2026-10-04) and `sort` and `sed`, which it names as read-only with write-capable flags; the two
# PowerShell cmdlets are this model's own guess (the docs list no PowerShell set).
READ_ONLY = {
    "cd", "echo", "ls", "cat", "pwd", "head", "tail", "grep", "find", "wc", "which", "diff", "stat", "du", "sort", "sed",
    "set-location", "get-content",
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

    def judge(self, tool: str, command: str, cwd: str = "") -> tuple[str, str | None]:
        """(deny, ask, allow or none; the rule that decided) for one Bash or PowerShell call, without the guard. With
        cwd, a `cd` elsewhere in the same call takes git out of the read-only set."""
        texts = subcommands(command, SHELLS[tool])
        for kind in (DENY, ASK):
            for text in texts:
                rule = self.matches(kind, tool, strip(text, assignments=True))
                if rule:
                    return kind, rule
        allowed = [self._allows(tool, t, _moves(texts, cwd)) for t in texts]
        if texts and all(allowed):
            return ALLOW, next((r for r in allowed if r != "read-only"), "read-only")
        return NONE, None

    def _allows(self, tool: str, text: str, moved: bool) -> str | None:
        stripped = strip(text, assignments=False)
        return self.matches(ALLOW, tool, stripped) or read_only(stripped, git=not moved)

    def unallowed(self, tool: str, command: str, cwd: str = "") -> str:
        """The command name (`git -C`, `sed`) of the first subcommand that neither an allow rule nor the read-only set
        lets run: what prompts outside bypass."""
        texts = subcommands(command, SHELLS[tool])
        for text in texts:
            if not self._allows(tool, text, _moves(texts, cwd)):
                return head(strip(text, assignments=True))
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
    texts = []
    for segment in guard.split(command, shell):
        if segment.words:
            texts.append(" ".join(segment.words))
        for sub in segment.subs:
            texts += subcommands(sub, shell)
    return texts


def strip(text: str, assignments: bool) -> str:
    """The subcommand without the wrappers Claude Code strips and, for deny and ask rules, leading assignments."""
    words = text.split(" ")
    changed = True
    while words and changed:
        changed = False
        if assignments and re.match(r"^[A-Za-z_]\w*=", words[0]):
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
    words = text.split(" ")
    first = words[0].lower()
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
    bypass: bool = True,
) -> tuple[str, str]:  # fmt: skip
    """(PASS, PROMPT or DENIED; why) for one call: the rules first, then the guard (it asks in every mode)."""
    kind, rule = rules.judge(tool, command, cwd)
    if kind == DENY:
        return DENIED, f"deny rule {rule}"
    if kind == ASK:
        return PROMPT, f"ask rule {rule}"
    findings = guard_module.check(command, SHELLS[tool], cwd, root, "", repo)
    if findings:
        return PROMPT, "guard: " + ", ".join(sorted({f.area for f in findings}))
    if kind == NONE and not bypass:
        return PROMPT, "no allow rule: " + rules.unallowed(tool, command, cwd)
    return PASS, "allow rule" if kind == ALLOW else "no rule"


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
    """Every Bash and PowerShell call in the transcripts under folders, from the day since (YYYY-MM-DD) on."""
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
                        command = (item.get("input") or {}).get("command") if isinstance(item, dict) else None
                        if item.get("type") == "tool_use" and item.get("name") in SHELLS and isinstance(command, str):
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
    since: str = "", bypass: bool = True, listing: bool = False,
) -> str:  # fmt: skip
    """The report: prompts and denials before and after, by cause, and every call whose verdict changed; with listing,
    each cause of the after side that stops a call, with its count by role and up to three example commands."""
    root = str(ROOT).replace("\\", "/")
    main = re.sub(r"/\.claude/worktrees/[^/]+$", "", root)
    repo = ReplayRepo(main)
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
                results[name] = verdict(rules, module, call.tool, call.command, call.cwd, main, repo, bypass)
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
            changed[(results["before"][0] + " -> " + results["after"][0], results["before"][1], call.command[:160])] += 1
    transcripts = sum(1 for folder in folders for _ in folder.rglob("*.jsonl"))
    lines = [f"{len(found)} calls in {transcripts} transcripts; {crashes} crashes"]
    for name in ("before", "after"):
        t = totals[name]
        lines.append(
            f"{name}: {t[PROMPT]} prompts ({t['ask']} ask rules, {t['guard']} guard, {t['no allow']} no allow rule),"
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
    once."""
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
        " seconds from the call to its result, an upper bound of the human's answer (after a yes the run is in it)"
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
        choices=["bypass", "default"],
        default="bypass",
        help="bypass: only deny and ask rules and the guard stop a call (default); default: a call no allow rule"
        " or read-only command covers prompts as well (a model: an upper bound)",
    )
    parser.add_argument("--list", action="store_true", help="also list each cause that stops a call, with examples")
    parser.add_argument(
        "--observed",
        action="store_true",
        help="instead of a replay, what the transcripts record: guard asks, deny rule denials, Claude Code's blocks",
    )
    args = parser.parse_args(argv)
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
    print(replay(before, after, folders, args.since, args.mode == "bypass", args.list))
    return 0


if __name__ == "__main__":
    sys.exit(main())
