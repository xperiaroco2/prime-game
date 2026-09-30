"""The shell permission rules of `.claude/settings.json` as Claude Code applies them (docs/AGENT_WORKFLOW.md §8.1),
and a replay of local transcripts through those rules and the guard (§8.2).

A model of Claude Code's matcher, close enough for selftests and replays, not the real one
(`code.claude.com/docs/en/permissions`, checked 2026-09-30):
- A command is split into subcommands at `&&`, `||`, `;`, `|`, `&` and newlines, including the commands inside
  `$(...)` (guard.split). Each subcommand's text is its words joined by single spaces, after the wrappers `timeout`,
  `time`, `nice`, `nohup`, `stdbuf`, `command` and `builtin` and, for deny and ask rules, any leading `VAR=value`.
- A `*` matches any text, spaces included. A trailing ` *` (or `:*`) that is the rule's only wildcard also matches the
  bare command. PowerShell rules match case-insensitively.
- Deny beats ask beats allow, over all subcommands: one denied subcommand denies the call, one asked subcommand asks.
  The guard's findings ask too. A call is allowed when every subcommand matches an allow rule or is a read-only
  builtin (a small subset of Claude Code's: `cd`, `echo`, `ls`, `cat`, `pwd`, ...).
- In bypass mode (the engineer's) deny rules block, ask rules and the guard prompt, and everything else runs; in the
  modes that prompt, a call that is not allowed prompts as well.

Replay: `tools/run.sh permissions --before origin/main` (`run.cmd` in PowerShell) replays every Bash and
PowerShell call in `~/.claude/projects/<project>*/**/*.jsonl` in bypass mode, with the settings and the guard of that
revision against the ones in this checkout, and prints the prompts before and after and every verdict that changed.
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
from pathlib import Path

from . import guard

ROOT = Path(__file__).resolve().parents[2]
SHELLS = {"Bash": guard.BASH, "PowerShell": guard.POWERSHELL}
# Wrappers Claude Code strips before matching, and the options of theirs that take a value.
WRAPPERS = {"timeout", "time", "nice", "nohup", "stdbuf", "command", "builtin"}
WRAPPER_VALUED = {"-n", "-s", "-k", "-i", "-o", "-e"}
# Commands Claude Code runs without a rule (a subset of its read-only set: enough for the selftests).
READ_ONLY = {"cd", "echo", "ls", "cat", "pwd", "head", "tail", "grep", "wc", "set-location", "get-content"}
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

    def judge(self, tool: str, command: str) -> tuple[str, str | None]:
        """(deny, ask, allow or none; the rule that decided) for one Bash or PowerShell call, without the guard."""
        texts = subcommands(command, SHELLS[tool])
        for kind in (DENY, ASK):
            for text in texts:
                rule = self.matches(kind, tool, strip(text, assignments=True))
                if rule:
                    return kind, rule
        allowed = [self.matches(ALLOW, tool, strip(t, assignments=False)) or _read_only(t) for t in texts]
        if texts and all(allowed):
            return ALLOW, next((r for r in allowed if r != "read-only"), "read-only")
        return NONE, None


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


def _read_only(text: str) -> str | None:
    first = text.split(" ", 1)[0].lower()
    return "read-only" if first in READ_ONLY else None


def verdict(
    rules: Rules, guard_module: types.ModuleType, tool: str, command: str, cwd: str, root: str, repo: object,
    bypass: bool = True,
) -> tuple[str, str]:  # fmt: skip
    """(PASS, PROMPT or DENIED; why) for one call: the rules first, then the guard (it asks in every mode)."""
    kind, rule = rules.judge(tool, command)
    if kind == DENY:
        return DENIED, f"deny rule {rule}"
    if kind == ASK:
        return PROMPT, f"ask rule {rule}"
    findings = guard_module.check(command, SHELLS[tool], cwd, root, "", repo)
    if findings:
        return PROMPT, "guard: " + ", ".join(sorted({f.area for f in findings}))
    if kind == NONE and not bypass:
        return PROMPT, "no allow rule"
    return PASS, "allow rule" if kind == ALLOW else "no rule"


# --- replay of local transcripts -------------------------------------------------------------------------------------


def calls(folders: list[Path]) -> list[tuple[str, str, str]]:
    """(tool, command, cwd) of every Bash and PowerShell call in the transcripts under folders."""
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
                    content = (entry.get("message") or {}).get("content")
                    for item in content if isinstance(content, list) else []:
                        command = (item.get("input") or {}).get("command") if isinstance(item, dict) else None
                        if item.get("type") == "tool_use" and item.get("name") in SHELLS and isinstance(command, str):
                            found.append((item["name"], command, str(entry.get("cwd") or ROOT)))
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


def replay(before: tuple[Rules, types.ModuleType], after: tuple[Rules, types.ModuleType], folders: list[Path]) -> str:
    """The report: prompts and denials before and after, by cause, and every call whose verdict changed."""
    root = str(ROOT).replace("\\", "/")
    main = re.sub(r"/\.claude/worktrees/[^/]+$", "", root)
    repo = ReplayRepo(main)
    found = calls(folders)
    totals: dict[str, Counter[str]] = {"before": Counter(), "after": Counter()}
    changed: Counter[tuple[str, str, str]] = Counter()
    crashes = 0
    for tool, command, cwd in found:
        results = {}
        for name, (rules, module) in (("before", before), ("after", after)):
            try:
                results[name] = verdict(rules, module, tool, command, cwd, main, repo)
            except Exception as exc:  # noqa: BLE001 - a replay reports crashes instead of stopping
                crashes += 1
                results[name] = (PROMPT, f"crash {type(exc).__name__}")
            state, why = results[name]
            totals[name][state] += 1
            totals[name][why.split(":")[0].split(" rule")[0]] += 1
        if results["before"][0] != results["after"][0]:
            changed[(results["before"][0] + " -> " + results["after"][0], results["before"][1], command[:160])] += 1
    transcripts = sum(1 for folder in folders for _ in folder.rglob("*.jsonl"))
    lines = [f"{len(found)} calls in {transcripts} transcripts; {crashes} crashes"]
    for name in ("before", "after"):
        t = totals[name]
        lines.append(
            f"{name}: {t[PROMPT]} prompts ({t['ask']} ask rules, {t['guard']} guard), {t[DENIED]} denied"
        )
    newly = sum(n for (change, _, _), n in changed.items() if change == f"{PASS} -> {PROMPT}")
    lines.append(f"changed verdicts: {sum(changed.values())}; silent before, asking now: {newly}")
    for (change, why, command), count in sorted(changed.items()):
        lines.append(f"  {change} x{count} [{why}] {command!r}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="run permissions", description=__doc__.split("\n\n")[0])
    parser.add_argument("--before", default="origin/main", help="the revision to compare with (default origin/main)")
    parser.add_argument(
        "--projects", default="", help="transcript folders glob under ~/.claude/projects (default: <project>*)"
    )
    args = parser.parse_args(argv)
    base = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / "projects"
    main_root = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT))
    pattern = args.projects or re.sub(r"[^A-Za-z0-9]", "-", main_root) + "*"
    folders = sorted(p for p in base.glob(pattern) if p.is_dir())
    before = (old_settings(args.before), old_guard(args.before))
    after = (Rules.load(ROOT / ".claude" / "settings.json"), guard)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    print(f"replay of {pattern} in bypass mode: {args.before} against this checkout")
    print(replay(before, after, folders))
    return 0


if __name__ == "__main__":
    sys.exit(main())
