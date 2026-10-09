"""`ctx`: the calling agent's own context now, read from its Claude Code transcript (#597, issue-task's checkpoint).

issue-task's `checkpoint` (#559) hands an implementer over to a fresh one past 150,000 tokens of context. The agent
cannot see its context, and a rule that asked it to work it out from the harness's `<total_tokens>` reminder never
fired (#559 comment 6077574716): so the implementer runs this command every ~15 tool calls and after each verify, and
hands over when it prints HANDOFF NOW.

The transcript: the newest *.jsonl (a workflow agent's agent-<id>.jsonl, a subagent's or a session's own) of the last
CTX_HOURS hours under ~/.claude/projects/<key>/ and <key>--claude-worktrees-*/ (CLAUDE_CONFIG_DIR replaces ~/.claude;
<key> as in metrics.py) whose first line, the agent's task prompt, names this checkout's folder (as C:/..., C:\\... or
/c/...). An agent works in its own worktree, and the caller is the one writing now, so the newest is its own. Its
context is the tokens of its last API call: input, cache writes, cache reads and output of the newest assistant line
with a usage (what `metrics` calls an agent's final context).
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path, PurePosixPath, PureWindowsPath

from . import agents_check
from .common import ROOT, say

AT = 150000  # issue-task's HANDOFF_AT: hand over at or past it
HARD = 200000  # past it, hand over even when only the final verify is left (#597)
CTX_HOURS = 6
MISSING = 2
TOKEN_FIELDS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")


def folder_pattern(root: Path) -> re.Pattern[str]:
    """The checkout's folder as a prompt may write it: any slashes (JSON doubles a backslash), C: or /c, any case;
    not a longer name (worktrees/59 is not worktrees/597). A drive path reads as Windows' on any OS (the tests)."""
    text = str(root)
    path = PureWindowsPath(text) if re.match(r"[A-Za-z]:", text) else PurePosixPath(text)
    parts = [p for p in path.parts[1:] if p not in ("/", "\\")]
    drive = path.drive.rstrip(":")
    head = rf"(?:{re.escape(drive)}:|/{re.escape(drive)})" if drive else ""
    sep = r"[\\/]+"
    return re.compile(head + sep + sep.join(re.escape(p) for p in parts) + r"(?![\w-]|\.\w)", re.IGNORECASE)


def project_dirs(config: Path, checkout: Path) -> list[Path]:
    """The checkout's project folder and its worktree sessions' folders (metrics.py's module docstring)."""
    from .metrics import project_key

    key = project_key(checkout)
    base = config / "projects"
    if not base.is_dir():
        return []
    return sorted(p for p in base.iterdir() if p.is_dir() and (p.name == key or p.name.startswith(key + "--claude-worktrees-")))


def first_line(path: Path) -> str:
    try:
        with path.open(encoding="utf-8", errors="replace") as f:
            return f.readline()
    except OSError:
        return ""


def find_transcript(dirs: list[Path], root: Path, now: float | None = None) -> Path | None:
    """The newest recent transcript whose first line names `root`, else None."""
    since = (time.time() if now is None else now) - CTX_HOURS * 3600
    found: list[tuple[float, Path]] = []
    for folder in dirs:
        for path in folder.rglob("*.jsonl"):
            if path.name == "journal.jsonl":
                continue
            try:
                mtime = path.stat().st_mtime
            except OSError:
                continue
            if mtime >= since:
                found.append((mtime, path))
    pattern = folder_pattern(root)
    for _, path in sorted(found, reverse=True):
        if pattern.search(first_line(path)):
            return path
    return None


def context_of(path: Path) -> int | None:
    """The tokens of the transcript's last API call, or None when it made none."""
    last: int | None = None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        if '"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message") if isinstance(d, dict) else None
        if d.get("type") != "assistant" or not isinstance(m, dict) or m.get("model") == "<synthetic>":
            continue
        usage = m.get("usage")
        if isinstance(usage, dict):
            last = sum(int(usage.get(f) or 0) for f in TOKEN_FIELDS)
    return last


def main(at: int = AT, hard: int = HARD, transcript: str | None = None) -> int:
    """Print the caller's context and HANDOFF NOW at or past `at`; 0, or 2 when no transcript or no API call is found."""
    if transcript:
        path: Path | None = Path(transcript)
    else:
        from .metrics import main_checkout

        dirs = project_dirs(agents_check.config_dir(), main_checkout())
        path = find_transcript(dirs, ROOT)
    tokens = context_of(path) if path and path.is_file() else None
    if path is None or tokens is None:
        where = path or f"{agents_check.config_dir() / 'projects'} (a prompt naming {ROOT.as_posix()})"
        say(f"ctx: no transcript with an API call found: {where}. Count your tool calls instead (the backstop).")
        return MISSING
    say(f"ctx: {tokens:,} tokens of context (hand over at {at:,}), from {path.name}")
    if tokens >= hard:
        say(f"HANDOFF NOW: past {hard:,}, even when only the final verify is left")
    elif tokens >= at:
        say("HANDOFF NOW")
    else:
        say("ctx: under the threshold, go on")
    return 0
