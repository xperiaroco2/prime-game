"""Machine paths for a terminal that is not a Claude Code session (#55).

The machine paths live in the `env` of each human's `~/.claude/settings.json` (docs/AGENT_WORKFLOW.md §2), which
Claude Code hands to every session, hook and subagent. A human's own PowerShell does not see them. So the runner
fills each machine-path variable the process environment lacks from the same settings files, in Claude Code's order
of precedence: the process environment, then the project's `.claude/settings.local.json`, then the user settings
(`$CLAUDE_CONFIG_DIR/settings.json` when that variable is set, else `~/.claude/settings.json`). The values go into
`os.environ` before any command runs, so Godot, gdtoolkit and every child process inherit them. `doctor` reports
where each one came from.
"""

from __future__ import annotations

import json
import os
from collections.abc import MutableMapping
from dataclasses import dataclass, field
from pathlib import Path

from .common import ROOT

MACHINE_VARS = ("GODOT_BIN", "GODOT_GUI_BIN", "PYTHON_BIN", "GDTOOLKIT_DIR", "NODE_BIN")
# Loaded like the others, but `doctor` does not warn when unset: `node` on PATH is the usual case (#368).
OPTIONAL_VARS = ("NODE_BIN",)
PROCESS = "the process environment"
LOCAL_SETTINGS = ".claude/settings.local.json"
USER_SETTINGS = "~/.claude/settings.json"


@dataclass
class Report:
    """Where each machine-path variable came from (None: nowhere) and the settings files that could not be used."""

    sources: dict[str, str | None] = field(default_factory=dict)
    problems: list[str] = field(default_factory=list)
    searched: list[str] = field(default_factory=list)


def settings_files(root: Path, home: Path, environ: MutableMapping[str, str]) -> list[tuple[str, Path]]:
    """(label, path) of the settings files that may hold the machine paths, highest precedence first."""
    config = environ.get("CLAUDE_CONFIG_DIR")
    user = (
        ("$CLAUDE_CONFIG_DIR/settings.json", Path(config) / "settings.json")
        if config
        else (USER_SETTINGS, home / ".claude" / "settings.json")
    )
    return [(LOCAL_SETTINGS, root / ".claude" / "settings.local.json"), user]


def read_env(label: str, path: Path) -> tuple[dict[str, str], list[str]]:
    """The machine-path entries of the `env` of one settings file, and what is wrong with it. A missing file is fine."""
    if not path.is_file():
        return {}, []
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        return {}, [f"{label} ({path}) is not valid JSON, so the runner ignores it: {exc}"]
    env = data.get("env") if isinstance(data, dict) else None
    if env is None:
        return {}, []
    if not isinstance(env, dict):
        return {}, [f"{label} ({path}): `env` is not an object, so the runner ignores it"]
    found: dict[str, str] = {}
    problems: list[str] = []
    for var in MACHINE_VARS:
        value = env.get(var)
        if isinstance(value, str) and value:
            found[var] = value
        elif value is not None and value != "":
            problems.append(f"{label} ({path}): env.{var} is not a string, so the runner ignores it")
    return found, problems


def load(environ: MutableMapping[str, str], root: Path, home: Path) -> Report:
    """Fill each machine-path variable environ lacks (unset or empty) from the settings files; say where each came from."""
    report = Report()
    files = settings_files(root, home, environ)
    report.searched = [PROCESS] + [label for label, _ in files]
    found: list[tuple[str, dict[str, str]]] = []
    for label, path in files:
        entries, problems = read_env(label, path)
        found.append((label, entries))
        report.problems.extend(problems)
    for var in MACHINE_VARS:
        if environ.get(var):
            report.sources[var] = PROCESS
            continue
        report.sources[var] = None
        for label, entries in found:
            if var in entries:
                environ[var] = entries[var]
                report.sources[var] = label
                break
    return report


_applied: Report | None = None


def apply() -> Report:
    """Fill os.environ once per run (tools/run.py calls it before any command); later calls return the same report."""
    global _applied
    if _applied is None:
        _applied = load(os.environ, ROOT, Path.home())
    return _applied
