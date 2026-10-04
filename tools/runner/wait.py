"""`wait <log> [--max S]` (#303): wait at most S seconds for a background job's exit marker.

Workflow agents (subagents) write their prompt cache with a 5-minute lifetime, so a tool call that blocks longer
(verify, publish, mutants, CI) makes the agent's next call write its whole context again. An agent therefore starts a
long job in the background with the Bash tool, its output and then an exit marker going to a log:

    cd <worktree> && tools/run.sh verify > <log> 2>&1; echo "exit=$?" >> <log>

and polls it with `wait`, one tool call of at most S seconds each (default 240). The job is finished only when the
LAST complete non-empty line of the log is `exit=<n>`: the marker is the job's final write, a half-written line (no
newline yet) is never read, and a bare `exit=0` line in the job's own output is not mistaken for the end. Then `wait`
prints the job's summary (from the last "verify summary" line, which publish prints too, or "merge-train summary";
otherwise the last TAIL_LINES lines) and returns n. Not finished by the deadline: one "still running" line and 124. No log, or one it
cannot read: 2.

Every line `wait` writes itself starts with "wait: ", so a job's own exit 2 or 124 is told apart by that line. It
reads only: it never writes, deletes or starts anything (a timeout leaves the job running).

`wait --verified` answers whether a standalone verify before `publish` is needed: 0 when this checkout's newest
verify record (tools/out/logs/verify-history.jsonl) passed at HEAD with a clean tree and the tree is still clean.
"""

from __future__ import annotations

import codecs
import os
import re
import time
from collections.abc import Callable
from pathlib import Path

from .common import say

DEFAULT_MAX = 240  # a poll every 4 minutes keeps a 5-minute cache warm with a margin for the model's own call
MAX_ALLOWED = 270
STILL_RUNNING = 124  # as coreutils' `timeout`
MISSING = 2  # no log, an unreadable one, or a bad --max (argparse's own errors are 2 too)
POLL_SECONDS = 3.0
APPEAR_GRACE = 10.0  # the background shell may not have created the log yet when the first wait starts
TAIL_LINES = 20
# A summary starts at the last of these lines: verify's (which publish prints too), or merge-train's own (#387), which
# follows the verify summaries of the publishes it ran.
SUMMARY_HEADS = ("verify summary", "merge-train summary")
EXIT_LINE = re.compile(r"^exit=(\d+)$")
MSYS_DRIVE = re.compile(r"^/([A-Za-z])(?=/|$)")


def native_path(text: str, windows: bool = os.name == "nt") -> Path:
    """The log's path for this Python: on Windows the Git Bash form /c/Users/... becomes C:/Users/... (an agent may
    paste the Bash form into PowerShell); other forms, spaces included, are kept."""
    text = os.path.expanduser(text)
    if windows:
        text = MSYS_DRIVE.sub(lambda m: m.group(1).upper() + ":", text, count=1)
    return Path(text)


def read_lines(path: Path) -> list[str] | None:
    """The log's complete lines (a trailing fragment without a newline is left out), or None when it is missing.
    UTF-16 with a BOM (PowerShell 5.1's `*>`) and UTF-8 with or without a BOM are read; CR line ends are dropped."""
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        return None
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        text = data.decode("utf-16", errors="replace")
    else:
        text = data.decode("utf-8-sig", errors="replace")
    lines = text.split("\n")
    lines.pop()  # the part after the last newline: "" for a complete log, else a line still being written
    return [line.rstrip("\r") for line in lines]


def exit_code(lines: list[str]) -> int | None:
    """n when the last non-empty line is `exit=<n>`, else None (the job is still running)."""
    last = next((line for line in reversed(lines) if line.strip()), None)
    match = EXIT_LINE.match(last) if last is not None else None
    return int(match.group(1)) if match else None


def summary_lines(lines: list[str], tail: int = TAIL_LINES) -> list[str]:
    """What to print of a finished log: from the last "verify summary" (verify, publish) or "merge-train summary" line
    to the marker, else the last `tail` non-empty lines before it (mutants, a publish stopped before its verify)."""
    end = max(i for i, line in enumerate(lines) if line.strip())  # the marker
    body = lines[:end]
    heads = [i for i, line in enumerate(body) if line.startswith(SUMMARY_HEADS)]
    if heads:
        return body[heads[-1] :]
    return [line for line in body if line.strip()][-tail:]


def verified() -> int:
    """`wait --verified`: 0 when this checkout's newest verify record passed at HEAD with a clean tree and the tree is
    still clean (then `publish`, which runs verify itself, needs no standalone verify before it), else 1."""
    import json

    from . import verify
    from .common import git_status

    record: dict[str, object] = {}
    try:
        with verify.HISTORY.open(encoding="utf-8", errors="replace") as lines:
            for line in lines:
                try:
                    parsed = json.loads(line)
                except ValueError:
                    continue
                if isinstance(parsed, dict):
                    record = parsed
    except OSError:
        pass
    dirty = bool(git_status())
    head = verify.git_facts(clean=not dirty)["head"]
    if not record:
        why = f"no verify record in {verify.HISTORY}"
    elif record.get("status") != "passed":
        why = f"the newest verify ({record.get('start')}) is {record.get('status')}"
    elif record.get("head") != head:
        why = f"the newest verify ({record.get('start')}) ran at {str(record.get('head'))[:12]}, HEAD is {str(head)[:12]}"
    elif not record.get("tree"):
        why = f"the newest verify ({record.get('start')}) ran with uncommitted changes"
    elif dirty:
        why = "the working tree has uncommitted changes now"
    else:
        say(
            f"wait: verify passed at HEAD {str(head)[:12]} with a clean tree ({record.get('start')}); "
            "`publish` runs verify itself: no standalone verify before it"
        )
        return 0
    say(f"wait: no passed verify at HEAD with a clean tree: {why}; run verify (or publish, which runs it)")
    return 1


def main(
    log: str,
    max_seconds: int = DEFAULT_MAX,
    *,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
    now: Callable[[], float] = time.time,
    grace: float = APPEAR_GRACE,
    poll: float = POLL_SECONDS,
) -> int:
    if not 1 <= max_seconds <= MAX_ALLOWED:
        say(f"wait: --max is 1 to {MAX_ALLOWED} s (a call over about 300 s loses the 5-minute prompt cache)")
        return MISSING
    path = native_path(log)
    start = clock()
    deadline = start + max_seconds
    seen = False
    while True:
        try:
            lines = read_lines(path)
        except OSError as error:  # a folder by mistake, a locked log: wait's own 2, never a traceback's 1
            say(f"wait: cannot read {path}: {error.strerror or error}")
            return MISSING
        if lines is None:
            if seen:
                say(f"wait: {path} disappeared during the wait (deleted, or another log name?)")
                return MISSING
            if clock() - start >= min(grace, max_seconds):
                hint = (
                    "; a Git Bash path such as /tmp is not visible to Windows programs: use a scratchpad path"
                    if os.name == "nt" and log.startswith("/") and not MSYS_DRIVE.match(log)
                    else ""
                )
                say(f"wait: no log at {path} (did the background launch start?{hint})")
                return MISSING
        else:
            seen = True
            code = exit_code(lines)
            if code is not None:
                for line in summary_lines(lines):
                    say(line)
                say(f"wait: {path.name} finished: exit={code} (whole log: {path})")
                return code
        left = deadline - clock()
        if left <= 0:
            break
        sleep(min(poll, left))
    try:
        age = f"last written {max(0.0, now() - path.stat().st_mtime):.0f} s ago"
    except OSError:
        age = "not readable now"
    count = len(lines) if lines is not None else 0
    say(
        f"wait: still running after {clock() - start:.0f} s ({path}: {count} lines, {age}); "
        "call wait again, never start the job again"
    )
    return STILL_RUNNING
