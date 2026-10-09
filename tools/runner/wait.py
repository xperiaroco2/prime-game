"""`wait <log> [--max S]` (#303): wait at most S seconds for a background job's exit marker.

Workflow agents (subagents) write their prompt cache with a 5-minute lifetime, so a tool call that blocks longer
(verify, publish, mutants, CI) makes the agent's next call write its whole context again. An agent therefore starts a
long job in the background with the Bash tool, its output and then an exit marker going to a log:

    cd <worktree> && tools/run.sh verify > <log> 2>&1; echo "exit=$?" >> <log>

and polls it with `wait`, one tool call of at most S seconds each (default and maximum 180, #555). The job is finished
only when the LAST complete non-empty line of the log is `exit=<n>`: the marker is the job's final write, a half-written
line (no newline yet) is never read, and a bare `exit=0` line in the job's own output is not mistaken for the end. Then
`wait` prints the job's summary (from the last "verify summary" line, which publish prints too, or "merge-train
summary"; otherwise the last TAIL_LINES lines) and returns n. Not finished by the deadline: one "still running" line
and 124. No log, or one it cannot read: 2.

Quiet by default (#590): a passed job's summary is capped at SUCCESS_CAP bytes, a failed job's at FAILURE_CAP bytes
followed by the first lines of its log that name a failure, each line cut at LINE_CAP characters, then the log's path.
`--verbose` prints the whole summary as before.

Every line `wait` writes itself starts with "wait: ", so a job's own exit 2 or 124 is told apart by that line. It
reads only: it never writes, deletes or starts anything (a timeout leaves the job running).

A machine that sleeps during a wait (#595, suspend.Watch) ends it at the resume: the log is read once more, and a job
still running gets a "wait: the machine slept or was suspended (<n> s)" line before the still-running line and 124.

`wait --verified` answers whether `publish` would reuse this checkout's newest verify instead of running its own
(#471): 0 when that record (tools/out/logs/verify-history.jsonl) passed at HEAD, on the same tree and runner, with a
clean tree, under REUSE_MAX_AGE ago, and the tree is still clean. `reuse_refusal` is that test, which `publish` runs
after its rebase.
"""

from __future__ import annotations

import codecs
import json
import os
import re
import time
from collections.abc import Callable, Mapping
from datetime import UTC, datetime, timedelta
from pathlib import Path

from . import suspend
from .common import FAILURE_CAP, SUCCESS_CAP, cap_lines, line_bytes, say

# A poll every 3 minutes keeps a 5-minute cache warm (#555): over 212 calls that ran to their deadline (2026-10-06 to
# 10-08, `metrics`), the gap to the agent's next API call exceeded wait's own clock by 6 s median, AROUND_P95 at p95
# (the shell's and Python's start-up and the guard hook on a loaded PC, then the model's turn), so the step plus that
# stays under CACHE_TTL. A longer --max only brings that edge back: the step is the maximum too.
DEFAULT_MAX = 180
MAX_ALLOWED = DEFAULT_MAX
AROUND_P95 = 94  # measured, #555: the tests hold the step and the prompts' Bash tool timeout against it
CACHE_TTL = 300  # a workflow agent's prompt cache, in seconds
STILL_RUNNING = 124  # as coreutils' `timeout`
MISSING = 2  # no log, an unreadable one, or a bad --max (argparse's own errors are 2 too)
POLL_SECONDS = 3.0
APPEAR_GRACE = 10.0  # the background shell may not have created the log yet when the first wait starts
TAIL_LINES = 20
# A summary starts at the last of these lines: verify's (which publish prints too), or merge-train's own (#387), which
# follows the verify summaries of the publishes it ran.
SUMMARY_HEADS = ("verify summary", "merge-train summary")
EXIT_LINE = re.compile(r"^exit=(\d+)$")
# Quiet by default (#590): what a red job's log says before its summary, the first few lines that name a failure.
FAILING_LINE = re.compile(r"^\s*(FAIL|ERROR)\b|Traceback|AssertionError|\bFAILED\b")
FAILING_SHOWN = 12
# The end line of a verify summary block: what follows it in a publish log (git push's lines, "ok pushed", "publish:
# done") is the outcome the agent waits for, capped on its own so the block stays whole for `metrics` (parse_verify).
VERIFY_END_LINE = re.compile(r"^verify: (passed|FAILED)\b")
AFTER_CAP = 1500
# The last lines a summary without a verify end line always keeps (a merge-train's count, the end of a mutants run).
END_LINES = 6
# How old a passed verify may be for `publish` to push on it instead of verifying again (#471): a verify that ran two
# hours before the push tested the same bytes, but the PC (Godot, the pins, the other worktrees' load) may have moved.
REUSE_MAX_AGE = timedelta(hours=2)
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


def failing_lines(lines: list[str]) -> list[str]:
    """The first FAILING_SHOWN lines before the summary block that name a failure (a red step's FAIL line, a test's
    assertion, a traceback), for a red job; none when the log has no summary block (summary_lines then already
    printed the last lines)."""
    end = max(i for i, line in enumerate(lines) if line.strip())  # the marker
    body = lines[:end]
    heads = [i for i, line in enumerate(body) if line.startswith(SUMMARY_HEADS)]
    if not heads:
        return []
    return [line for line in body[: heads[-1]] if FAILING_LINE.search(line)][:FAILING_SHOWN]


def quiet_report(lines: list[str], code: int, whole: str) -> list[str]:
    """What a finished job prints by default (#590): its summary, at most SUCCESS_CAP bytes when it passed; when it
    failed at most FAILURE_CAP, the summary and then the first failing lines of its log. Lines over the cap are cut
    from the middle (a line says how many, with `whole`, the log's path): the verify end line and the last lines
    always print, and the lines after a verify block (publish's push) have their own AFTER_CAP."""
    cap = SUCCESS_CAP if code == 0 else FAILURE_CAP
    more = f"whole log: {whole}"
    summary = summary_lines(lines)
    ends = [i for i, line in enumerate(summary) if VERIFY_END_LINE.match(line)]
    if ends:
        block, after = summary[: ends[-1] + 1], summary[ends[-1] + 1 :]
        report = cap_lines(block, cap, more, keep_end=1) + cap_lines(after, AFTER_CAP, more, keep_end=3)
    else:
        report = cap_lines(summary, cap, more, keep_end=END_LINES)
    if code != 0:
        used = line_bytes(report)
        failing = failing_lines(lines)
        if failing and cap - used > 200:
            report += ["first failing lines of the log (search it for the rest):"]
            report += cap_lines(failing, cap - used - 60, more)
    return report


def utc_now() -> datetime:
    return datetime.now(UTC)


def newest_record(history: Path) -> dict[str, object]:
    """The last JSON object in a verify history (one record a line), or {} when there is none or no file."""
    record: dict[str, object] = {}
    try:
        with history.open(encoding="utf-8", errors="replace") as lines:
            for line in lines:
                try:
                    parsed = json.loads(line)
                except ValueError:
                    continue
                if isinstance(parsed, dict):
                    record = parsed
    except OSError:
        pass
    return record


def record_age(record: Mapping[str, object], now: datetime) -> timedelta | None:
    """How long ago the record's verify started, or None when its start is missing or unreadable."""
    try:
        start = datetime.fromisoformat(str(record.get("start")).replace("Z", "+00:00"))
    except ValueError:
        return None
    if start.tzinfo is None:
        return None
    return now - start


def reuse_refusal(
    record: Mapping[str, object],
    facts: Mapping[str, object],
    dirty: bool,
    now: datetime,
    max_age: timedelta = REUSE_MAX_AGE,
) -> str:
    """Why the newest verify record does not stand for a verify of this checkout now, or "" when it does (#471): it
    passed at the same head, tree and runner (facts: verify.git_facts' keys), with a clean tree then and now, and it
    started under max_age before now. `publish` skips its own verify only on ""."""
    when = record.get("start")

    def ran(key: str) -> str:  # the record's value and this checkout's, side by side
        return f"{str(record.get(key))[:12]}, HEAD's is {str(facts.get(key))[:12]}"

    if not record:
        return "there is no verify record"
    if record.get("status") != "passed":
        return f"the newest verify ({when}) is {record.get('status')}"
    if record.get("head") != facts.get("head"):
        head = str(facts.get("head"))[:12]
        return f"the newest verify ({when}) ran at {str(record.get('head'))[:12]}, HEAD is {head}"
    if not record.get("tree"):
        return f"the newest verify ({when}) ran with uncommitted changes"
    if dirty:
        return "the working tree has uncommitted changes now"
    if record.get("tree") != facts.get("tree"):
        return f"the newest verify ({when}) ran on tree {ran('tree')}"
    if not record.get("runner") or record.get("runner") != facts.get("runner"):
        return f"the newest verify ({when}) ran with runner {ran('runner')}"
    age = record_age(record, now)
    if age is None:
        return f"the newest verify has no readable start time ({when})"
    if age < timedelta(0):
        return f"the newest verify starts in the future ({when}): this PC's clock moved"
    if age >= max_age:
        return f"the newest verify ({when}) started {minutes(age)} ago, over the {minutes(max_age)} limit"
    return ""


def minutes(span: timedelta) -> str:
    """A span as "1 h 05 min" or "42 min"."""
    total = int(span.total_seconds() // 60)
    return f"{total // 60} h {total % 60:02d} min" if total >= 60 else f"{total} min"


def verified() -> int:
    """`wait --verified`: 0 when `publish` would reuse this checkout's newest verify record instead of running verify
    (reuse_refusal is ""), so no standalone verify is needed before it; else 1."""
    from . import verify
    from .common import git_status

    record = newest_record(verify.HISTORY)
    dirty = bool(git_status())
    facts = verify.git_facts(clean=not dirty)
    why = reuse_refusal(record, facts, dirty, utc_now())
    if not why:
        say(
            f"wait: verify passed at HEAD {str(facts['head'])[:12]} with a clean tree ({record.get('start')}); "
            "`publish` reuses it instead of verifying again"
        )
        return 0
    if not record:
        why = f"no verify record in {verify.HISTORY}"
    say(f"wait: no passed verify at HEAD with a clean tree that publish would reuse: {why}; publish runs verify itself")
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
    verbose: bool = False,
) -> int:
    if not 1 <= max_seconds <= MAX_ALLOWED:
        say(f"wait: --max is 1 to {MAX_ALLOWED} s (a call over about 300 s loses the 5-minute prompt cache)")
        return MISSING
    path = native_path(log)
    start = clock()
    deadline = start + max_seconds
    seen = False
    watch = suspend.Watch(now, clock)  # #595: a machine that sleeps during the wait ends it at the resume
    slept: float | None = None
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
                for line in summary_lines(lines) if verbose else quiet_report(lines, code, str(path)):
                    say(line)
                say(f"wait: {path.name} finished: exit={code} (whole log: {path})")
                return code
        left = deadline - clock()
        if left <= 0 or slept is not None:
            break
        sleep(min(poll, left))
        slept = watch.tick()  # then the log is read once more
    try:
        age = f"last written {max(0.0, now() - path.stat().st_mtime):.0f} s ago"
    except OSError:
        age = "not readable now"
    count = len(lines) if lines is not None else 0
    if slept is not None:
        say(f"wait: {suspend.message(slept)} during this wait; a verify stops red on it by itself")
    say(
        f"wait: still running after {clock() - start:.0f} s ({path}: {count} lines, {age}); "
        "call wait again, never start the job again"
    )
    return STILL_RUNNING
