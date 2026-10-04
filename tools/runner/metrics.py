"""`metrics`: time, tokens and API list $ of the task workflows, read-only from the Claude Code transcripts.

The baseline of docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md (item 1) as a runner command.

Where the transcripts are: ~/.claude/projects/<key>/ (CLAUDE_CONFIG_DIR replaces ~/.claude), where <key> is the main
checkout's path with every character other than a letter or a digit replaced by "-" (D:\\prime-game -> D--prime-game),
plus <key>--claude-worktrees-<n>/ for sessions started inside a worktree. The main checkout is the parent of
`git rev-parse --path-format=absolute --git-common-dir`, so every worktree gives the same answer (workflow agents that
work in a worktree log under their parent session's folder anyway). Per session <sid> of such a folder:
- <sid>.jsonl: the session itself (a manager session when it ran workflows);
- <sid>/subagents/agent-<id>.jsonl and .meta.json: subagents it ran by hand;
- <sid>/subagents/workflows/wf_*/: one workflow run: journal.jsonl (each agent's label, phase and structured result:
  the reviewers' findings with their severity, the publisher's PR and CI) and agent-<id>.jsonl with .meta.json.
A session is reported when it ran a workflow, or when --session names it.

Rules (the ADR's "How the baseline was computed"):
- usage is deduplicated by message id (a message's content blocks repeat its usage; each field's maximum is kept);
- a run counts when its last transcript line is before --until and its first at or after --since; a manager's own
  lines and its hand-run subagents count inside the same window;
- a tool call lasts from the assistant line that made it to the user line that carries its result;
- a `verify` run is a "verify summary" block printed in a tool result, deduplicated per agent, with each step's seconds;
- a run is finished when its journal ends with a result and every started agent has one; it is an `issue-task` run
  when it has an implementer, `pr-rebase` when it has a rebaser, a resumed `issue-task` when it has only a publisher.
Units: final context is the tokens of an agent's last API call, summed over agents (what the managers reported as
"subagent tokens"); fresh tokens are input, cache writes and output without cache reads; API list $ weighs every kind
of token and model at its API list price (PRICES): a weight, not money spent.

`tools/out/logs/verify-history.jsonl` (written by `verify` since P2, #179), in the main checkout and in every worktree
under .claude/worktrees/, adds a row to the verify table when present. Each line is one run: `start` (ISO 8601 or epoch
seconds), `worktree`, `branch`, `steps` (a list of {name, status, seconds} or a map name -> {status, seconds}), and
`seconds` (the run's wall time without its slot wait; else the sum of the steps) and `slot` (#185: `waited` seconds
for a machine-wide verify slot, `over` when none was free within the longest wait; null without slots). A printed
summary carries the same wait in its last line. Since #273 a red step carries `failure` (its first failure line), and
the `test` step `shards` (each GdUnit4 process's `rc` and `seconds`) and, when red, `failed_tests` ({`test`,
`message` or `orphans`}): the verify section counts the red runs' failing tests, first failure lines and shard exits;
an older record without them still counts as before. `--ci N` adds CI from `gh` (read-only): every run in the
window and the job and `verify` step times of the last N green runs.

Manager cache re-writes (#305): a session's own API call after an idle gap over 1 hour (REWRITE_GAP, the 1-hour prompt
cache's lifetime) that wrote most of its context to the cache again. Each is put in one bucket by what held when the
gap began: a keep-alive timer armed (a Bash or PowerShell call with `run_in_background` whose whole command is a
`sleep`, optionally followed by an `echo`; armed from its line until the task notification naming its tool-use id, or
until its seconds or its timeout ran out; one armed before --since counts while it is still armed), else a workflow
run of the session in flight, else a stop.

Quality scorecard (#314), per finished issue-task run, so a cost change is judged by quality as well as by $:
- from the journal: the blockers and majors of the diff reviewers and the test review (SERIOUS_FROM; matched as
  issue-task.js's SERIOUS, case-insensitive), how many skeptics checked and refuted, "open" (those minus the refuted)
  and "clean" (none open, not stopped by mutants and not a design task, which its implementer's prompt says
  (DESIGN_TASK): #315's publish_clean rule, derived here because a run's return value is not journaled), the
  publisher's fixed, not_fixed and needs_engineer, its PR (pr_number, else pr_url), and its fix rounds (its
  `publish` calls minus one, every attempt of a retried publisher counted); each agent's model and effort from its
  transcript;
- from `gh` (read-only, unless --no-gh): the PR's state; its CI rounds, one per head SHA of the pull_request runs of
  CI_WORKFLOW on its branch: red when a run of it ended in CI_RED (a SHA whose runs were all cancelled or skipped is no
  round; a re-run attempt shows only its last conclusion, so a re-run round counts in ci_reruns), "green on the first
  CI round" from the earliest round only (unknown when that round was re-run to green: it may have been red), and
  the red rounds that began after the run ended; Found-by follow-ups (issues whose "Found by" line names the
  task's issue or PR: a lower bound, since nothing makes an agent write one); fix-up PRs (later PRs titled `revert`
  or `fix(...)`/`fix:` that name the PR or issue, as `#N` or `owner/repo#N`, in the title or in a body sentence that
  reverts or repairs it (REGRESSION), outside their "Found by" lines and their Merge order and Verification sections,
  from another branch than the task's own `<area>/<n>-...`).
Unknown is None in the JSON and "?" in the tables, never 0: a run without a PR, an older result shape without the
key, skeptics not run while blockers or majors stand, no diff reviewer, a PR of another repository or missing from
the list, a branch without CI runs, a run list cut before the PR, `gh` skipped or failed. Medians and sums count only
the known values and say how many are known; PR-level signals count once per PR.
"""

from __future__ import annotations

import io
import json
import os
import re
import statistics
import subprocess
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

from . import agents_check
from .common import OUT, ROOT, Failure, run, say, warn

TOKEN_FIELDS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
SHORT = {
    "input_tokens": "input",
    "cache_creation_input_tokens": "cache write",
    "cache_read_input_tokens": "cache read",
    "output_tokens": "output",
}

# USD per million tokens at the API list price: input, 5-minute cache write, 1-hour cache write, cache read, output.
# Source: platform.claude.com/docs/en/about-claude/pricing, read 2026-10-02 (the ADR's table; a 1-hour cache write is
# twice the input price; Opus 5.5's cache read is 0.05 of its input price, the other models' 0.1). A model missing
# here is weighed at the first row's prices and named in the report.
PRICES = {
    "claude-opus-5-5": (4.0, 5.0, 8.0, 0.20, 20.0),
    "claude-sonnet-5-5": (2.0, 2.5, 4.0, 0.20, 10.0),
    "claude-haiku-4-5": (1.0, 1.25, 2.0, 0.10, 5.0),
}
USD_KEYS = ("usd_input", "usd_cache_write", "usd_cache_read", "usd_output")
# 1% of a Max 20x week in API list $ counting cache reads at full list $ (#304, measured in #302): Max 20x; 66% at
# 2026-10-03 20:54 UTC = $1,690 list since the counter restarted at the plan change (2026-10-02 about 10:30 UTC); cache
# reads are 40% of list $. The ADR's first $44 assumed a week 4x Max 5x's; it is 2.1 to 2.2x. Re-fitted in #307 over
# the 44 readings to 77% at 2026-10-04 05:05 UTC: $25.5 (least squares; 25.4 to 25.7 by method). Since #307 it is the
# bracket's upper end (WEEK_BRACKET), not the headline (WEEK_CENTRAL).
WEEK_PERCENT_USD = 25.5
# The limits count cache reads at a weight w of their list $, measured in #307 (the baseline ADR's amendment of
# 2026-10-04, docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md): w = 0.75, range 0.6 to 1. A % of
# the week is (list $ without cache reads + w x cache-read $) / k(w), k(w) the least-squares fit over the same 44
# readings: $21.5 at w = 0.6, $23.0 at 0.75 and full list $ at w = 1, so k(1) is WEEK_PERCENT_USD. The headline is at
# the central weight (#333), whatever the cache reads' share of list $; the bracket is the range's ends.
WEEK_CENTRAL = (0.75, 23.0)
WEEK_BRACKET = ((0.6, 21.5), (1.0, WEEK_PERCENT_USD))

ROLES = {
    "implement": "implementer",
    "publish": "publisher",
    "review:code": "code-reviewer",
    "review:netcode": "netcode-security-reviewer",
    "review:godot-api": "godot-api-checker",
    "rebase": "pr-rebase",
    "fix": "pr-rebase fix",
    # issue-task v2 (#180) and pr-rebase's optional agents
    "plan": "planner",
    "review:plan": "plan-reviewer",
    "review:netcode-second": "netcode-second-reviewer",
    "test-review": "test-reviewer",
    "skeptic": "skeptic",
}
# The reviewers of a task's diff: their findings make a task's "blockers+majors" (as in the M4 baseline).
REVIEWERS = ("code-reviewer", "netcode-security-reviewer", "godot-api-checker")
# Every agent that reports findings: the review table shows them all.
FINDERS = (*REVIEWERS, "netcode-second-reviewer", "plan-reviewer", "test-reviewer")
SEVERITIES = ("blocker", "major", "minor", "nit")

# Shell commands by what they wait on; the first match wins.
CMD_KINDS = [
    ("publish", re.compile(r"run(\.cmd|\.sh)\s+publish\b")),
    ("verify", re.compile(r"run(\.cmd|\.sh)\s+verify\b")),
    ("selftest", re.compile(r"run(\.cmd|\.sh)\s+selftest\b")),
    ("test", re.compile(r"run(\.cmd|\.sh)\s+test\b")),
    ("check", re.compile(r"run(\.cmd|\.sh)\s+check\b")),
    ("lint", re.compile(r"run(\.cmd|\.sh)\s+lint\b")),
    ("bots/run/host", re.compile(r"run(\.cmd|\.sh)\s+(bots|run|host|join|shot)\b")),
    ("ci-wait", re.compile(r"gh\s+(pr\s+checks|run\s+watch)\b")),
    ("gh", re.compile(r"\bgh\s")),
    ("git", re.compile(r"\bgit\s")),
]
STEP_LINE = re.compile(r"^\s*(passed|FAILED)\s+(\S+(?: tree)?)\s+([\d.]+)s\s*$")
VERIFY_END = re.compile(r"verify: (passed|FAILED) in ([\d.]+)s")
# The end line's slot wait (#185): "(after 45.0s waiting for a verify slot)", and "OVER THE LIMIT" when none was free.
SLOT_WAIT = re.compile(r"after ([\d.]+)s waiting for a verify slot")
OVER_LIMIT = "OVER THE LIMIT"
# The most failing tests and failure lines the verify section lists (#273); the JSON record keeps every run's.
RED_ROWS = 20
# `gh run list --limit`: enough for the project's history so far (149 runs before 2026-10-02 11:00 UTC).
CI_LIST_LIMIT = 1000
# The workflow that runs `verify` on every push and PR; other workflows (a nightly run) are left out.
CI_WORKFLOW = "ci.yml"
GAP_BUCKETS = ((0, 60, "under 1 min"), (60, 300, "1 to 5 min"), (300, 600, "5 to 10 min"), (600, None, "over 10 min"))
# A manager's cache re-write (#305): its call after an idle gap over the 1-hour prompt cache's lifetime.
REWRITE_GAP = 3600
# What held when such a gap began, in the order the first that holds wins (module docstring).
REWRITE_KINDS = ("timer", "run", "stop")
# A keep-alive timer: a background shell call that only sleeps (an `echo` after it allowed), in Bash or PowerShell.
TIMER = re.compile(r"\s*(?:sleep|start-sleep(?:\s+-s(?:econds)?)?)\s+(\d+)\s*(?:(?:;|&&)\s*echo\b.*)?",
                   re.IGNORECASE | re.DOTALL)  # fmt: skip
# A background task's notification names the tool call that started it.
NOTIFIED = re.compile(r"<tool-use-id>([^<\s]+)</tool-use-id>")
# issue-task.js tells a design task's implementer so in its prompt; #315's publish_clean is false for such a run.
DESIGN_TASK = "This is a DESIGN task: documents only"
# Claude Code stops a background command after its `timeout`, 30 minutes when none is given.
BACKGROUND_TIMEOUT = 1800
# The quality scorecard (#314, the module docstring): what issue-task.js counts as a blocker or major (its SERIOUS),
# and the agents whose findings it counts (#315's open blockers and majors).
SERIOUS = re.compile(r"blocker|major", re.IGNORECASE)
SERIOUS_FROM = (*REVIEWERS, "netcode-second-reviewer", "test-reviewer")
# A CI round is red when one of its runs ended so; cancelled, skipped and the like make no round.
CI_RED = frozenset({"failure", "timed_out", "startup_failure"})
PR_URL = re.compile(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)")
FOUND_BY = re.compile(r"found by[^\n]*", re.IGNORECASE)
FIXUP_TITLE = re.compile(r"^\s*(revert\b|fix(\(|:|!))", re.IGNORECASE)
# A fix-up's body names the task only in a sentence that says it reverts or repairs it: PR bodies list their sibling
# PRs (Merge order, merge-check results) and cite others as context ("PR #41's test"), which is no fix-up.
REGRESSION = re.compile(r"revert|regress|introduc|\bbroke|\bbreaks?\b|caused by", re.IGNORECASE)
# The PR template's sections that list other PRs as a matter of course: left out of the search.
LISTING_SECTION = re.compile(r"^#{1,6}[ \t]*(merge order|verification)\b.*?(?=^#{1,6}[ \t]|\Z)",
                             re.IGNORECASE | re.MULTILINE | re.DOTALL)  # fmt: skip
SENTENCE_END = re.compile(r"(?<=[.;!?])\s+|\n")
# `gh pr list` and `gh issue list --limit`: the project had about 330 of each by 2026-10-05.
GH_LIST_LIMIT = 1000
# The signals of a run, and those of its PR (counted once per PR when several runs end on it).
RUN_SIGNALS = ("serious", "refuted", "open", "not_fixed", "needs_engineer", "fix_rounds")
PR_SIGNALS = ("ci_red_rounds", "ci_red_after_run")
GITHUB_SIGNALS = ("pr_state", "merged", "ci_runs", "ci_red_rounds", "ci_red_after_run", "ci_last", "ci_reruns",
                  "green_first", "followups", "fixups")  # fmt: skip


# --- time and formatting ------------------------------------------------------------------------------------------


def parse_time(text: str) -> float:
    """ISO 8601 ('2026-10-02T11:00:00Z', '2026-10-02') as epoch seconds; a time without a zone is UTC."""
    try:
        moment = datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
    except ValueError as exc:
        raise Failure(f"not an ISO 8601 time: {text!r} (for example 2026-10-02T11:00:00Z)") from exc
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.timestamp()


def stamp(value: object) -> float | None:
    """A transcript or history timestamp (ISO 8601, or epoch seconds or milliseconds) as epoch seconds."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value / 1000 if value > 1e11 else float(value)
    if isinstance(value, str) and value:
        try:
            return parse_time(value)
        except Failure:
            return None
    return None


def iso(seconds: float | None) -> str:
    if seconds is None:
        return ""
    return datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fmt_usd(v: float) -> str:
    return f"${v:,.0f}" if v >= 10 else f"${v:.2f}"


def fmt_tok(n: float) -> str:
    return f"{n / 1e6:.2f}M" if n >= 1e5 else f"{n / 1e3:.0f}k"


def mins(s: float) -> str:
    return f"{s / 60:.0f}"


def med(values: list[float]) -> float:
    return statistics.median(values) if values else 0.0


def table(head: list[str], rows: list[list[object]]) -> str:
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


# --- prices -------------------------------------------------------------------------------------------------------


def price_of(model: str | None) -> tuple[tuple[float, ...], bool]:
    """(prices, known). Model IDs may carry a date suffix (claude-haiku-4-5-20251001)."""
    for name, price in PRICES.items():
        if (model or "").startswith(name):
            return price, True
    return next(iter(PRICES.values())), False


def usd_of(usage: dict) -> dict[str, float]:
    """One API call's tokens at its model's list price, by kind (see PRICES)."""
    price, _known = price_of(usage.get("model"))
    one_hour = min(usage.get("cache_write_1h", 0), usage["cache_creation_input_tokens"])
    return {
        "usd_input": usage["input_tokens"] * price[0] / 1e6,
        "usd_cache_write": ((usage["cache_creation_input_tokens"] - one_hour) * price[1] + one_hour * price[2]) / 1e6,
        "usd_cache_read": usage["cache_read_input_tokens"] * price[3] / 1e6,
        "usd_output": usage["output_tokens"] * price[4] / 1e6,
    }


def write_premium(usage: dict) -> float:
    """What one API call's cache writes cost above reading the same tokens from the cache, at its model's prices."""
    price, _known = price_of(usage.get("model"))
    return usd_of(usage)["usd_cache_write"] - usage["cache_creation_input_tokens"] * price[3] / 1e6


def total(t: dict) -> float:
    return sum(t.get(f, 0) for f in TOKEN_FIELDS)


def fresh(t: dict) -> float:
    """Tokens that are not cache reads: input, cache writes and output."""
    return t.get("input_tokens", 0) + t.get("cache_creation_input_tokens", 0) + t.get("output_tokens", 0)


def usd(t: dict) -> float:
    return sum(t.get(k, 0) for k in USD_KEYS)


def week_percent(spent: float, read: float) -> dict:
    """% of a Max 20x week for `spent` API list $ of which `read` is cache reads: at the central weight (WEEK_CENTRAL),
    and the bracket's two ends (WEEK_BRACKET: the limit counting cache reads at 60% and at 100%)."""
    def at(w: float, k: float) -> float:
        return (spent - read + w * read) / k

    return {"percent": at(*WEEK_CENTRAL), "bracket": [at(w, k) for w, k in WEEK_BRACKET]}


def week_rate() -> str:
    """The conversion, for a report's note on its % of the week."""
    w, k = WEEK_CENTRAL
    (w0, k0), (w1, k1) = WEEK_BRACKET
    return (f"(list $ without cache reads + {w:g} x cache-read $) / ${k} per 1%, the limit counting cache reads at "
            f"{w:.0%} of their list $ (#307's central weight); in brackets, at {w0 * 100:g} to {w1:.0%} ((list $ "
            f"without cache reads + {w0:g} or {w1:g} x cache-read $) / ${k0} or ${k1})")


def fmt_week(week: dict) -> str:
    """'6.0% (5.8 to 6.1%)': the % at the central weight, then the bracket."""
    lo, hi = week["bracket"]
    return f"{week['percent']:.1f}% ({lo:.1f} to {hi:.1f}%)"


# --- transcripts --------------------------------------------------------------------------------------------------


def text_of(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(str(b.get("text", "")) for b in content if isinstance(b, dict))
    return ""


def cmd_kind(cmd: str) -> str:
    for kind, rx in CMD_KINDS:
        if rx.search(cmd):
            return kind
    return "other shell"


def union_seconds(intervals: list[tuple[float, float]]) -> float:
    covered, end = 0.0, None
    for a, b in sorted(intervals):
        if end is None or a > end:
            covered += b - a
            end = b
        elif b > end:
            covered += b - end
            end = b
    return covered


def parse_verify(text: str) -> dict | None:
    """The last "verify summary" block in text: {steps: {name: (status, seconds)}, total, status, wait, over}; wait is
    the seconds it waited for a verify slot (None: a run without slots), over whether it ran without one."""
    i = text.rfind("verify summary")
    if i < 0:
        return None
    steps: dict[str, tuple[str, float]] = {}
    total_s, status, wait, over = None, None, None, False
    for line in text[i:].splitlines()[1:]:
        m = STEP_LINE.match(line)
        if m:
            steps[m.group(2)] = (m.group(1), float(m.group(3)))
            continue
        m = VERIFY_END.search(line)
        if m:
            status, total_s = m.group(1), float(m.group(2))
            waited = SLOT_WAIT.search(line)
            wait = float(waited.group(1)) if waited else None
            over = OVER_LIMIT in line
            break
    if not steps:
        return None
    return {"steps": steps, "total": total_s, "status": status, "wait": wait, "over": over}


def timer_seconds(block: object) -> float | None:
    """A tool_use block's keep-alive seconds (TIMER, run in the background), capped by its timeout; else None."""
    if not isinstance(block, dict) or block.get("type") != "tool_use" or not block.get("id"):
        return None
    inp = block.get("input") if isinstance(block.get("input"), dict) else {}
    if block.get("name") not in ("Bash", "PowerShell") or inp.get("run_in_background") is not True:
        return None
    timer = TIMER.fullmatch(str(inp.get("command", "")))
    if not timer:
        return None
    limit = inp.get("timeout")
    limit_s = limit / 1000 if isinstance(limit, (int, float)) and limit > 0 else None
    return min(float(timer.group(1)), limit_s or BACKGROUND_TIMEOUT)


def read_agent(path: Path, since: float | None = None, until: float | None = None) -> dict:
    """One transcript: usage deduplicated by message id, tool calls with their wall time, verify summaries.

    Lines outside [since, until] are left out (used for a manager session that spans several windows)."""
    usage: dict[str, dict] = {}
    first_seen: dict[str, float] = {}
    uses: dict[str, dict] = {}
    stamps: list[float] = []
    model, effort, title = None, None, None
    prompt: str | None = None  # the first user message: the agent's prompt
    last_ctx = 0
    verifies: list[dict] = []
    timers: dict[str, tuple[float, float]] = {}  # a keep-alive timer's tool-use id: (armed at, its seconds)
    woken: dict[str, float] = {}  # a background task's tool-use id: when its notification came
    with io.open(path, encoding="utf-8", errors="replace") as lines:
        for line in lines:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            if d.get("type") == "custom-title" and d.get("customTitle"):
                title = str(d["customTitle"])
            t = stamp(d.get("timestamp"))
            if t is None or (until is not None and t >= until):
                continue
            if "<task-notification>" in line:  # a queue-operation line or a user message, whichever comes first
                for tid in NOTIFIED.findall(line):
                    woken.setdefault(tid, t)
            m = d.get("message")
            if since is not None and t < since:
                # Before the window only its keep-alive timers count: one may still be armed when a gap in it begins.
                if d.get("type") == "assistant" and isinstance(m, dict) and m.get("model") != "<synthetic>":
                    for b in m.get("content") or []:
                        secs = timer_seconds(b)
                        if secs is not None and b["id"] not in timers:
                            timers[b["id"]] = (t, secs)
                continue
            stamps.append(t)
            if not isinstance(m, dict):
                continue
            if prompt is None and d.get("type") == "user":
                content = m.get("content")
                if isinstance(content, str) or (
                    isinstance(content, list) and any(isinstance(b, dict) and b.get("type") == "text" for b in content)
                ):
                    prompt = text_of(content)
            if d.get("type") == "assistant":
                msg_model = m.get("model")
                if msg_model == "<synthetic>":
                    continue  # written by Claude Code itself (an interruption, an API error): no API call
                model = msg_model or model
                effort = d.get("effort") or effort
                u = m.get("usage") if isinstance(m.get("usage"), dict) else {}
                mid = m.get("id") or d.get("requestId") or d.get("uuid")
                cur = usage.get(mid)
                if cur is None:
                    cur = usage[mid] = {**{f: 0 for f in TOKEN_FIELDS}, "cache_write_1h": 0, "model": model}
                    first_seen[mid] = t
                for f in TOKEN_FIELDS:
                    cur[f] = max(cur[f], int(u.get(f) or 0))
                cache = u.get("cache_creation")
                if isinstance(cache, dict):
                    cur["cache_write_1h"] = max(cur["cache_write_1h"], int(cache.get("ephemeral_1h_input_tokens") or 0))
                last_ctx = sum(cur[f] for f in TOKEN_FIELDS)
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id"):
                        inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                        cmd = str(inp.get("command", "")) if b.get("name") in ("Bash", "PowerShell") else ""
                        secs = timer_seconds(b)
                        if secs is not None and b["id"] not in timers:
                            timers[b["id"]] = (t, secs)
                        uses[b["id"]] = {
                            "name": b.get("name"),
                            "t0": t,
                            "t1": None,
                            "kind": cmd_kind(cmd) if cmd else b.get("name"),
                        }
            elif d.get("type") == "user" and isinstance(m.get("content"), list):
                for b in m["content"]:
                    if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in uses:
                        call = uses[b["tool_use_id"]]
                        call["t1"] = t
                        text = text_of(b.get("content"))
                        if call["kind"] in ("verify", "publish") or "verify summary" in text:
                            v = parse_verify(text)
                            if v:
                                v["via"] = call["kind"]
                                v["t"] = call["t0"]
                                verifies.append(v)
    tokens: dict[str, float] = Counter()
    unpriced: set[str] = set()
    for u in usage.values():
        tokens.update({f: u[f] for f in TOKEN_FIELDS})
        tokens.update(usd_of(u))
        if not price_of(u["model"])[1] and total(u):
            unpriced.add(str(u["model"]))
    order = sorted(first_seen, key=lambda k: first_seen[k])
    # Per call after the first: (seconds since the previous call, cache write, cache read, the write's premium over a
    # read, the write's API list $, the previous call's time).
    gaps = [
        (first_seen[b] - first_seen[a], usage[b]["cache_creation_input_tokens"], usage[b]["cache_read_input_tokens"],
         write_premium(usage[b]), usd_of(usage[b])["usd_cache_write"], first_seen[a])
        for a, b in zip(order, order[1:])
    ]
    armed = sorted((t0, woken.get(tid, t0 + secs)) for tid, (t0, secs) in timers.items())
    calls = list(uses.values())
    seen, unique = set(), []
    for v in verifies:
        sig = (v["total"], tuple(sorted((k, x[1]) for k, x in v["steps"].items())))
        if sig not in seen:
            seen.add(sig)
            unique.append(v)
    kinds: dict[str, float] = defaultdict(float)
    for c in calls:
        kinds[c["kind"]] += (c["t1"] or c["t0"]) - c["t0"]
    return {
        "start": min(stamps) if stamps else None,
        "end": max(stamps) if stamps else None,
        "model": model,
        "effort": effort,
        "title": title,
        "design": DESIGN_TASK in (prompt or ""),
        "api_calls": len(usage),
        "tokens": dict(tokens),
        "unpriced": unpriced,
        "last_ctx": last_ctx,
        "gaps": gaps,
        # Keep-alive timers as (armed, ended): ended at the notification, else when its seconds ran out. One armed
        # before the window is kept while it is still armed in it; "timers_armed" counts those armed in the window.
        "timers": [(a, b) for a, b in armed if since is None or b > since],
        "timers_armed": sum(1 for t0, _secs in timers.values() if since is None or t0 >= since),
        "tool_calls": len(calls),
        "kinds": dict(kinds),
        "kind_counts": Counter(c["kind"] for c in calls),
        "tool_seconds": union_seconds([(c["t0"], c["t1"]) for c in calls if c["t1"]]),
        "verifies": unique,
    }


def role_of(label: str) -> str:
    base = re.sub(r"[:#]?#?\d[\d,#]*$", "", label).rstrip(":#")
    return ROLES.get(base, "other")


def as_dict(result: object) -> dict:
    if isinstance(result, dict):
        return result
    if isinstance(result, str):
        try:
            value = json.loads(result)
        except ValueError:
            return {}
        return value if isinstance(value, dict) else {}
    return {}


def read_json_lines(path: Path) -> list[dict]:
    found = []
    if not path.is_file():
        return found
    with io.open(path, encoding="utf-8", errors="replace") as lines:
        for line in lines:
            try:
                value = json.loads(line)
            except ValueError:
                continue
            if isinstance(value, dict):
                found.append(value)
    return found


def read_meta(agent_file: Path) -> dict:
    meta = agent_file.with_name(agent_file.name.removesuffix(".jsonl") + ".meta.json")
    try:
        value = json.loads(meta.read_text(encoding="utf-8")) if meta.is_file() else {}
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


# --- collecting ---------------------------------------------------------------------------------------------------


def main_checkout(root: Path = ROOT) -> Path:
    """The main checkout: the parent of git's common dir, the same from every worktree; else this checkout."""
    res = run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], timeout=30, cwd=root)
    lines = [line for line in res.lines if line.strip()]
    if res.rc == 0 and lines:
        return Path(lines[-1].strip()).parent
    return root


def project_key(checkout: Path) -> str:
    """Claude Code's folder name for a working directory: D:\\prime-game -> D--prime-game."""
    return re.sub(r"[^A-Za-z0-9]", "-", str(checkout))


def session_filter(values: list[str]) -> dict[str, str | None]:
    """--session ID[=LABEL] values as {id or id prefix: label}."""
    found: dict[str, str | None] = {}
    for value in values:
        sid, _, label = value.partition("=")
        if sid.strip():
            found[sid.strip()] = label.strip() or None
    return found


def collect(dirs: list[Path], sessions: dict[str, str | None], since: float | None, until: float) -> dict:
    """Every session, run and agent of the given project folders, as the module docstring describes."""
    out: dict = {"sessions": [], "runs": [], "found_runs": 0, "other_sessions": 0}
    for folder in dirs:
        names = {p.stem for p in folder.glob("*.jsonl")} | {
            p.name for p in folder.iterdir() if p.is_dir() and (p / "subagents").is_dir()
        }
        for sid in sorted(names):
            named = next((k for k in sessions if sid == k or sid.startswith(k)), None)
            if sessions and named is None:
                continue
            base = folder / sid
            run_dirs = sorted(p for p in (base / "subagents" / "workflows").glob("wf_*") if p.is_dir())
            if not run_dirs and named is None:
                out["other_sessions"] += 1
                continue
            label = (sessions.get(named) if named else None) or sid[:8]
            out["found_runs"] += len(run_dirs)
            files = {p.name[6:-6]: p for p in (base / "subagents").rglob("agent-*.jsonl")} if base.is_dir() else {}
            transcript = folder / f"{sid}.jsonl"
            manager = read_agent(transcript, since, until) if transcript.is_file() else None
            hand = []
            for p in sorted((base / "subagents").glob("agent-*.jsonl")) if base.is_dir() else []:
                data = read_agent(p, since, until)  # cut to the window, like the session's own lines
                if data["api_calls"]:
                    hand.append({"id": p.name[6:-6], "type": str(read_meta(p).get("agentType", "?")), "data": data})
            cache: dict[str, dict] = {}
            runs = [read_run(w, files, cache, label) for w in run_dirs]
            for r in runs:
                r["sid"] = sid
                r["counted"] = bool(r["end"]) and r["end"] < until and (since is None or (r["start"] or 0) >= since)
            if named is None and not hand and not (manager and manager["api_calls"]) and not any(
                r["counted"] for r in runs
            ):
                out["other_sessions"] += 1  # nothing of it in the window
                continue
            out["runs"] += runs
            out["sessions"].append(
                {"id": sid, "label": label, "folder": folder.name, "manager": manager, "hand": hand,
                 "title": manager["title"] if manager else None}
            )
    return out


def read_run(folder: Path, files: dict[str, Path], cache: dict[str, dict], label: str) -> dict:
    entries = read_json_lines(folder / "journal.jsonl")
    started = [e for e in entries if e.get("type") == "started" and "key" in e]
    results = {e["key"]: e for e in entries if e.get("type") == "result" and "key" in e}
    # A key started twice is an agent retried after its first attempt died: both attempts spent time and tokens, the
    # result belongs to the last one.
    last_attempt = {e["key"]: str(e.get("agentId", "")) for e in started}
    agents = []
    listed = set()
    for e in started:
        aid = str(e.get("agentId", ""))
        result = results.get(e["key"]) if last_attempt[e["key"]] == aid else None
        agents.append((aid, str(e.get("label", "")), e.get("phase"), result))
        listed.add(aid)
    # An agent the journal does not list (a journal cut short): its .meta.json names it.
    for p in sorted(folder.glob("agent-*.jsonl")):
        aid = p.name[6:-6]
        if aid not in listed:
            meta = read_meta(p)
            agents.append((aid, str(meta.get("description", "")), meta.get("workflowPhase"), None))
            files.setdefault(aid, p)
    run_agents = []
    for aid, agent_label, phase, result in agents:
        if aid not in cache and aid in files:
            cache[aid] = read_agent(files[aid])
        run_agents.append(
            {
                "id": aid,
                "label": agent_label,
                "role": role_of(agent_label),
                "phase": phase,
                "result": as_dict(result["result"]) if result else None,
                "data": cache.get(aid),
            }
        )
    with_data = [x["data"] for x in run_agents if x["data"] and x["data"]["end"]]
    finished = bool(entries) and entries[-1].get("type") == "result" and set(last_attempt) <= set(results)
    nums = re.findall(r"#(\d+)", " ".join(x["label"] for x in run_agents))
    roles = {x["role"] for x in run_agents}
    kind = (
        "issue-task" if "implementer" in roles
        else "pr-rebase" if "pr-rebase" in roles
        else "issue-task (resumed)" if "publisher" in roles
        else "other"
    )
    return {
        "session": label,
        "wf": folder.name,
        "kind": kind,
        "issue": int(Counter(nums).most_common(1)[0][0]) if nums else None,
        "finished": finished,
        "start": min(d["start"] for d in with_data) if with_data else None,
        "end": max(d["end"] for d in with_data) if with_data else None,
        "agents": run_agents,
    }


def history_paths(main: Path) -> list[Path]:
    """verify-history.jsonl of the main checkout, of each of its worktrees and of this checkout."""
    rel = Path("tools") / "out" / "logs" / "verify-history.jsonl"
    found = [main / rel, *sorted((main / ".claude" / "worktrees").glob(f"*/{rel.as_posix()}")), ROOT / rel]
    unique: list[Path] = []
    for p in found:
        if p.is_file() and all(os.path.normcase(p.resolve()) != os.path.normcase(q.resolve()) for q in unique):
            unique.append(p)
    return unique


def read_history(paths: list[Path], since: float | None, until: float) -> list[dict]:
    """The verify runs recorded by `verify` itself, in the window, as parse_verify's shape."""
    found, seen = [], set()
    for path in paths:
        for rec in read_json_lines(path):
            start = stamp(rec.get("start") or rec.get("started") or rec.get("time"))
            if start is None or start >= until or (since is not None and start < since):
                continue
            raw = rec.get("steps")
            if isinstance(raw, dict):
                items = list(raw.items())
            else:
                items = [(s.get("name"), s) for s in raw or [] if isinstance(s, dict)]
            steps = {}
            red: dict[str, list] = {"failed_tests": [], "step_failures": [], "shard_exits": []}
            for name, step in items:
                if name and isinstance(step, dict):
                    passed = str(step.get("status", "")).lower() in ("passed", "ok", "pass", "true")
                    steps[str(name)] = ("passed" if passed else "FAILED", float(step.get("seconds") or 0))
                    if not passed:
                        add_red_detail(red, str(name), step)
            if not steps:
                continue
            seconds = rec.get("seconds")
            total_s = float(seconds) if isinstance(seconds, (int, float)) else sum(s for _, s in steps.values())
            status = "FAILED" if any(st == "FAILED" for st, _ in steps.values()) else "passed"
            slot = rec.get("slot")
            waited = slot.get("waited") if isinstance(slot, dict) else None
            wait = float(waited) if isinstance(waited, (int, float)) else None
            over = bool(slot.get("over")) if isinstance(slot, dict) else False
            key = (start, str(rec.get("worktree", "")), total_s)
            if key not in seen:
                seen.add(key)
                found.append({"steps": steps, "total": total_s, "status": status, "via": "history", "t": start,
                              "wait": wait, "over": over, **red})  # fmt: skip
    return found


def add_red_detail(red: dict[str, list], name: str, step: dict) -> None:
    """A red step's fields of the history record (#273; an older record has none): the failing tests of `test`
    ("<suite>::<test>"), the step's first failure line, and each GdUnit4 process that did not end with exit 0."""
    tests = step.get("failed_tests")
    for test in tests if isinstance(tests, list) else []:
        if isinstance(test, dict) and test.get("test"):
            red["failed_tests"].append(str(test["test"]))
    if isinstance(step.get("failure"), str) and step["failure"]:
        red["step_failures"].append((name, step["failure"]))
    shards = step.get("shards")
    for shard in shards if isinstance(shards, list) else []:
        if not isinstance(shard, dict) or (shard.get("rc") == 0 and not shard.get("timed_out")):
            continue
        rc = shard.get("rc")
        label = "did not start" if rc is None else "timed out" if shard.get("timed_out") else f"exit {rc}"
        red["shard_exits"].append(label + (" without results.xml" if shard.get("results") is False else ""))


def numbers_as_n(text: str) -> str:
    """A failure line with its numbers as N (ports, instances, epochs, positions), so one cause counts as one. Digits
    after a letter or an underscore are part of a name and stay whole ("GdUnit4", "test-shard12.log",
    "probe_273_fail_test")."""
    return re.sub(r"(?<![A-Za-z_\d])\d+(?:\.\d+)?", "N", text)


def red_detail_section(history: list[dict]) -> list[str]:
    """What the red runs of the history file failed on: tests (runs per test), the first failure line of each red
    step (runs per step and line), and the GdUnit4 processes that did not end with exit 0."""
    tests = Counter(t for v in history for t in set(v.get("failed_tests", [])))
    lines = Counter((s, numbers_as_n(m)) for v in history for s, m in set(v.get("step_failures", [])))
    exits = Counter(e for v in history for e in v.get("shard_exits", []))
    md: list[str] = []
    if tests:
        rows = [[f"`{t}`", n] for t, n in tests.most_common(RED_ROWS)]
        md += ["Failing tests of red runs (history file):", "", table(["test", "red runs"], rows), ""]
    if lines:
        rows = [[s, m.replace("|", "\\|"), n] for (s, m), n in lines.most_common(RED_ROWS)]
        md += ["First failure line of each red step (history file; numbers as N):", "",
               table(["step", "first failure line", "runs"], rows), ""]  # fmt: skip
    if exits:
        md += ["GdUnit4 processes of `test` that did not end with exit 0 (history file): "
               + ", ".join(f"{k} {v}" for k, v in exits.most_common()) + ".", ""]  # fmt: skip
    return md


def _gh(args: list[str]) -> str:
    try:
        res = subprocess.run(
            ["gh", *args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180, cwd=ROOT
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Failure(f"gh {' '.join(args)}: {exc}") from exc
    if res.returncode != 0:
        raise Failure(f"gh {' '.join(args)} failed: {res.stderr.strip()[:300]}")
    return res.stdout


def ci_data(since: float | None, until: float, last: int, gh=_gh) -> dict:
    """CI from GitHub, read-only: every run of CI_WORKFLOW in the window, and the jobs and verify steps of the last
    `last` green."""
    listed = json.loads(
        gh(["run", "list", "--workflow", CI_WORKFLOW, "--limit", str(CI_LIST_LIMIT), "--json",
            "databaseId,event,conclusion,createdAt,startedAt,attempt"])
    )
    runs = []
    for r in listed:
        created = stamp(r.get("createdAt"))
        if created is not None and created < until and (since is None or created >= since):
            runs.append(r)
    green = sorted((r for r in runs if r.get("conclusion") == "success"), key=lambda r: r["createdAt"])[-last:]
    jobs, steps = [], defaultdict(list)
    for r in green:
        # The run's jobs from the first start to the last end: every lane if verify is split into several jobs.
        listed_jobs = json.loads(gh(["run", "view", str(r["databaseId"]), "--json", "jobs"])).get("jobs") or []
        starts = [t for j in listed_jobs if (t := stamp(j.get("startedAt"))) is not None]
        ends = [t for j in listed_jobs if (t := stamp(j.get("completedAt"))) is not None]
        if starts and ends:
            jobs.append(max(ends) - min(starts))
        log = gh(["run", "view", str(r["databaseId"]), "--log"])
        v = parse_verify("\n".join(re.sub(r"^.*?\dZ ", "", line) for line in log.splitlines()))
        for name, (_, sec) in (v or {}).get("steps", {}).items():
            steps[name].append(sec)
        if v and v["total"]:
            steps["verify total"].append(v["total"])
    waits = [(stamp(r.get("createdAt")), stamp(r.get("startedAt"))) for r in runs]
    queue = [b - a for a, b in waits if a is not None and b is not None]
    oldest = min((t for r in listed if (t := stamp(r.get("createdAt"))) is not None), default=None)
    return {
        "runs": len(runs),
        "cut": len(listed) >= CI_LIST_LIMIT and oldest is not None and (since is None or oldest > since),
        "by_outcome": dict(Counter(f"{r.get('event')} {r.get('conclusion')}" for r in runs).most_common()),
        "reruns": sum((r.get("attempt") or 1) > 1 for r in runs),
        "queue_s": med(queue),
        "green": len(green),
        "job_s": jobs,
        "steps": dict(steps),
    }


def gh_list(gh, args: list[str]) -> list[dict]:
    """A `gh ... --json` listing as a list of objects; Failure when its output is not one."""
    text = gh(args)
    try:
        value = json.loads(text)
    except ValueError as exc:
        raise Failure(f"gh {' '.join(args[:2])}: its output is not JSON ({exc})") from exc
    if not isinstance(value, list):
        raise Failure(f"gh {' '.join(args[:2])}: its output is not a JSON list")
    return [v for v in value if isinstance(v, dict)]


def read_github(gh=_gh) -> dict:
    """What the quality scorecard reads from GitHub (read-only): every PR, the runs of CI_WORKFLOW, every issue."""
    prs = gh_list(gh, ["pr", "list", "--state", "all", "--limit", str(GH_LIST_LIMIT), "--json",
                       "number,url,title,body,headRefName,state,createdAt,mergedAt"])  # fmt: skip
    runs = gh_list(gh, ["run", "list", "--workflow", CI_WORKFLOW, "--limit", str(CI_LIST_LIMIT), "--json",
                        "databaseId,event,headBranch,headSha,conclusion,createdAt,attempt"])  # fmt: skip
    issues = gh_list(gh, ["issue", "list", "--state", "all", "--limit", str(GH_LIST_LIMIT), "--json",
                          "number,title,body,createdAt"])  # fmt: skip
    # A run list at its limit misses older runs: a PR opened before its oldest run has unknown CI rounds.
    oldest = min((t for r in runs if (t := stamp(r.get("createdAt"))) is not None), default=None)
    cut = [name for name, lst, limit in (("PRs", prs, GH_LIST_LIMIT), ("CI runs", runs, CI_LIST_LIMIT),
                                         ("issues", issues, GH_LIST_LIMIT)) if len(lst) >= limit]  # fmt: skip
    return {"read_at": iso(time.time()), "prs": prs, "runs": runs, "issues": issues, "cut": cut,
            "runs_from": oldest if "CI runs" in cut else None}  # fmt: skip


# --- the report ---------------------------------------------------------------------------------------------------


def per_task(r: dict) -> dict:
    ph: dict[str, list[tuple[float, float]]] = defaultdict(list)
    tok: Counter = Counter()
    ctx = calls = nver = 0
    vt = ci = 0.0
    vsum: list[dict] = []
    for x in r["agents"]:
        d = x["data"]
        if not d or d["start"] is None:
            continue
        ph[str(x["phase"])].append((d["start"], d["end"]))
        tok.update(d["tokens"])
        ctx += d["last_ctx"]
        calls += d["tool_calls"]
        vsum += d["verifies"]
        nver += d["kind_counts"].get("verify", 0) + d["kind_counts"].get("publish", 0)
        vt += d["kinds"].get("verify", 0) + d["kinds"].get("publish", 0)
        ci += d["kinds"].get("ci-wait", 0)
    span = {p: max(e for _, e in v) - min(s for s, _ in v) for p, v in ph.items()}
    sev = Counter(
        f.get("severity")
        for x in r["agents"]
        if x["role"] in REVIEWERS
        for f in ((x["result"] or {}).get("findings") or [])
        if isinstance(f, dict)
    )
    pub = next((x["result"] for x in r["agents"] if x["role"] == "publisher" and x["result"]), None) or {}
    return {
        "session": r["session"],
        "issue": r["issue"],
        "wf": r["wf"],
        "start": r["start"],
        "wall": r["end"] - r["start"],
        "span": span,
        "tokens": total(tok),
        "fresh": fresh(tok),
        "usd": usd(tok),
        "ctx": ctx,
        "calls": calls,
        "summaries": len(vsum),
        "summaries_failed": sum(v["status"] == "FAILED" for v in vsum),
        "summary_s": sum(v["total"] or 0 for v in vsum),
        "verify_calls": nver,
        "verify_call_s": vt,
        "ci_s": ci,
        "sev": dict(sev),
        "pr": pub.get("pr_number"),
        "ci_green": pub.get("ci_green"),
    }


def run_usd(r: dict) -> float:
    return sum(usd(x["data"]["tokens"]) for x in r["agents"] if x["data"])


def total_week(counted: list[dict], managers: list[dict]) -> dict:
    """Every counted run and every manager's own lines and hand-run subagents: API list $, its cache reads and the %
    of a Max 20x week (week_percent)."""
    spent = sum(run_usd(r) for r in counted) + sum(m["manager_usd"] + m["hand_usd"] for m in managers)
    read = sum(x["data"]["tokens"].get("usd_cache_read", 0) for r in counted for x in r["agents"] if x["data"])
    read += sum(m["manager_read_usd"] + m["hand_read_usd"] for m in managers)
    return {"usd": spent, "read_usd": read, **week_percent(spent, read)}


def build(
    data: dict, history: list[dict], ci: dict | None, since: float | None, until: float, *, github: dict | None = None
) -> tuple[list[str], dict, list[str]]:
    """(the Markdown report, the JSON record, the compact summary). github: read_github's lists for the quality
    scorecard, {"error": ...} or {"skipped": ...}; None leaves its GitHub signals unknown."""
    counted = [r for r in data["runs"] if r["counted"]]
    finished = [r for r in counted if r["kind"] == "issue-task" and r["finished"]]
    tasks = [per_task(r) for r in finished]
    labels = list(dict.fromkeys(s["label"] for s in data["sessions"]))  # a label may name several sessions
    window = f"{iso(since) or 'the first transcript'} to {iso(until)}"
    md = [
        f"# Task workflow metrics ({window})",
        "",
        f"Runs: {data['found_runs']} found in {len(labels)} sessions, {len(counted)} in the window "
        f"({sum(not r['finished'] for r in counted)} of them unfinished: died, stopped, threw or still running).",
        "",
    ]
    md += task_section(tasks)
    stages = stage_rows(tasks, labels)
    md += stage_section(stages)
    md += role_section(counted)
    by_row = verify_rows(counted, data["sessions"], history)
    md += verify_section(by_row)
    md += review_section(counted)
    quality = quality_record(finished, labels, github)
    md += quality_section(quality)
    md += time_section(counted)
    md += cache_section(counted)
    managers = manager_rows(counted, data["sessions"])
    md += manager_section(managers, data["other_sessions"])
    rewrites = rewrite_rows(data["sessions"], data["runs"])
    md += rewrite_section(rewrites)
    md += other_section(counted)
    if ci is not None:
        md += ci_section(ci)
    week = total_week(counted, managers)
    compact = compact_lines(tasks, counted, by_row, history, ci, managers, week, window, quality=quality)
    record = {
        "since": iso(since) or None,
        "until": iso(until),
        "sessions": managers,
        "week": week,
        "stages": stages,
        "tasks": tasks,
        "runs": [{k: v for k, v in r.items() if k != "agents"} | {"usd": run_usd(r)} for r in counted],
        "verifies": {
            k: [{**v, "steps": {s: list(x) for s, x in v["steps"].items()}} for v in lst] for k, lst in by_row.items()
        },
        "ci": ci,
        "manager_rewrites": rewrites,
        "quality": quality,
        "compact": compact,
    }
    return md, record, compact


def task_section(tasks: list[dict]) -> list[str]:
    rows = []
    for p in tasks:
        sev = p["sev"]
        rows.append([
            p["session"], f"#{p['issue']}", mins(p["wall"]), mins(p["span"].get("Implement", 0)),
            mins(p["span"].get("Review", 0)), mins(p["span"].get("Publish", 0)), fmt_tok(p["ctx"]),
            fmt_tok(p["fresh"]), fmt_usd(p["usd"]), p["calls"], f"{p['summaries']}/{p['summaries_failed']}",
            mins(p["summary_s"]), p["verify_calls"], mins(p["verify_call_s"]), mins(p["ci_s"]),
            *(sev.get(s, 0) for s in SEVERITIES), p["pr"] or "", {True: "green", False: "red"}.get(p["ci_green"], ""),
        ])
    head = ["session", "issue", "wall", "implement", "review", "publish", "final context", "fresh tokens",
            "API list $", "tool calls", "verify runs/red", "min in verify", "verify+publish calls",
            "min in those calls", "min on CI", *SEVERITIES, "PR", "CI"]
    return ["## Per finished issue-task run (minutes)", "", table(head, rows), ""]


def stage_rows(tasks: list[dict], labels: list[str]) -> list[dict]:
    """Per session (a stage): medians of its finished issue-task runs."""
    stages = []
    for label in labels:
        t = [p for p in tasks if p["session"] == label]
        if not t:
            continue
        stages.append({
            "session": label, "runs": len(t), "wall": med([p["wall"] for p in t]),
            "wall_max": max(p["wall"] for p in t),
            "implement": med([p["span"].get("Implement", 0) for p in t]),
            "review": med([p["span"].get("Review", 0) for p in t]),
            "publish": med([p["span"].get("Publish", 0) for p in t]),
            "ctx": med([p["ctx"] for p in t]), "fresh": med([p["fresh"] for p in t]),
            "usd": med([p["usd"] for p in t]), "usd_max": max(p["usd"] for p in t),
            "calls": med([p["calls"] for p in t]), "verify_runs": med([p["summaries"] for p in t]),
            "verify_s": med([p["summary_s"] for p in t]), "ci_s": med([p["ci_s"] for p in t]),
            "majors": sum(p["sev"].get("blocker", 0) + p["sev"].get("major", 0) for p in t),
        })
    return stages


def stage_section(stages: list[dict]) -> list[str]:
    head = ["session", "runs", "wall", "implement", "review", "publish", "final context", "fresh tokens",
            "API list $", "tool calls", "verify runs", "min in verify", "min on CI", "blockers+majors", "wall max",
            "API list $ max"]
    rows = [
        [s["session"], s["runs"], mins(s["wall"]), mins(s["implement"]), mins(s["review"]), mins(s["publish"]),
         fmt_tok(s["ctx"]), fmt_tok(s["fresh"]), fmt_usd(s["usd"]), f"{s['calls']:.0f}", f"{s['verify_runs']:.0f}",
         mins(s["verify_s"]), mins(s["ci_s"]), s["majors"], mins(s["wall_max"]), fmt_usd(s["usd_max"])]
        for s in stages
    ]
    return [
        "## Per session (a stage): finished issue-task runs, medians in minutes", "", table(head, rows), "",
        "\"verify runs\" counts the summaries an implementer or publisher printed (`publish` included).", "",
    ]


def role_section(counted: list[dict]) -> list[str]:
    """Per agent role, over every counted run, finished or not: the tokens were spent."""
    roles: dict[str, dict] = defaultdict(lambda: {"n": 0, "wall": [], "calls": [], "tok": Counter(), "fresh": [],
                                                  "tool_s": [], "models": Counter(), "efforts": Counter()})
    grand: Counter = Counter()
    unpriced: set[str] = set()
    for r in counted:
        for x in r["agents"]:
            d = x["data"]
            if not d or d["start"] is None:
                continue
            g = roles[x["role"]]
            g["n"] += 1
            g["wall"].append(d["end"] - d["start"])
            g["calls"].append(d["tool_calls"])
            g["tool_s"].append(d["tool_seconds"])
            g["tok"].update(d["tokens"])
            g["fresh"].append(fresh(d["tokens"]))
            g["models"][str(d["model"])] += 1
            g["efforts"][str(d["effort"])] += 1
            grand.update(d["tokens"])
            unpriced |= d["unpriced"]
    rows = []
    for role, g in sorted(roles.items(), key=lambda kv: -usd(kv[1]["tok"])):
        rows.append([
            role, g["n"], f"{mins(med(g['wall']))} / {mins(max(g['wall']))}",
            f"{med(g['tool_s']) / max(1.0, med(g['wall'])):.0%}", f"{med(g['calls']):.0f} / {max(g['calls'])}",
            fmt_tok(med(g["fresh"])), f"{fmt_usd(usd(g['tok']))} ({usd(g['tok']) / max(1e-9, usd(grand)):.0%})",
            ", ".join(g["models"]), ", ".join(g["efforts"]),
        ])
    head = ["role", "agents", "wall min (median / max)", "time in tools", "tool calls (median / max)",
            "fresh tokens (median)", "API list $", "models", "efforts"]
    md = ["## Per agent role (every run in the window)", "", table(head, rows), ""]
    if total(grand):
        kinds = ", ".join(f"{SHORT[f]} {fmt_tok(grand[f])} ({grand[f] / total(grand):.1%})" for f in TOKEN_FIELDS)
        shares = ", ".join(f"{k[4:].replace('_', ' ')} {grand[k] / max(1e-9, usd(grand)):.0%}" for k in USD_KEYS)
        md += [f"All workflow subagents: {fmt_tok(total(grand))} tokens, {kinds}; "
               f"{fmt_usd(usd(grand))} list: {shares}.", ""]
    if unpriced:
        md += [f"Models without a price in PRICES (weighed at {next(iter(PRICES))}'s): "
               f"{', '.join(sorted(unpriced))}.", ""]
    return md


def verify_rows(counted: list[dict], sessions: list[dict], history: list[dict]) -> dict[str, list[dict]]:
    """Verify runs by where they come from: each session's agents, the managers' own runs, the history file."""
    by_row: dict[str, list[dict]] = defaultdict(list)
    for r in counted:
        for x in r["agents"]:
            if x["data"]:
                by_row[r["session"]] += x["data"]["verifies"]
    for s in sessions:
        if s["manager"]:
            by_row["managers"] += s["manager"]["verifies"]
    if history:
        by_row["history file"] = history
    return by_row


def agent_verifies(by_row: dict[str, list[dict]]) -> list[dict]:
    return [v for k, lst in by_row.items() if k not in ("managers", "history file") for v in lst]


def slot_waits(lst: list[dict]) -> tuple[list[float], int]:
    """The seconds each run waited for a verify slot (#185; runs without slots left out), and how many ran over the
    limit (no slot free within the longest wait)."""
    return [float(v["wait"]) for v in lst if v.get("wait") is not None], sum(bool(v.get("over")) for v in lst)


def verify_section(by_row: dict[str, list[dict]]) -> list[str]:
    step_names: list[str] = []
    for lst in by_row.values():
        for v in lst:
            step_names += [s for s in v["steps"] if s not in step_names]
    with_slots = any(slot_waits(lst)[0] for lst in by_row.values())
    rows = []
    for name, lst in [*by_row.items(), ("all agents", agent_verifies(by_row))]:
        if not lst:
            continue
        row: list[object] = [name, len(lst), sum(v["status"] == "FAILED" for v in lst)]
        for s in step_names:
            vals = [v["steps"][s][1] for v in lst if s in v["steps"]]
            row.append(f"{med(vals):.0f}" if vals else "")
        tots = [v["total"] for v in lst if v["total"]]
        row.append(f"{med(tots):.0f} / {max(tots):.0f}" if tots else "")
        if with_slots:
            waits, over = slot_waits(lst)
            row += [f"{med(waits):.0f} / {max(waits):.0f}" if waits else "", over]
        rows.append(row)
    fails = Counter(s for lst in by_row.values() for v in lst for s, (st, _) in v["steps"].items() if st == "FAILED")
    slot_head = ["slot wait (median / max)", "over the limit"] if with_slots else []
    md = ["## Local verify by step (seconds, medians of the printed summaries)", "",
          table(["", "runs", "red", *step_names, "total (median / max)", *slot_head], rows), ""]
    if with_slots:
        md += ["\"slot wait\" is the time a run waited for one of the machine-wide verify slots before its lanes "
               "(left out of its total); \"over the limit\" counts runs that found no slot within the longest wait "
               "and ran anyway.", ""]  # fmt: skip
    if fails:
        md += ["Red steps: " + ", ".join(f"{k} {v}" for k, v in fails.most_common()) + ".", ""]
    md += red_detail_section(by_row.get("history file", []))
    return md


def review_section(counted: list[dict]) -> list[str]:
    rv: dict[tuple[str, str], dict] = defaultdict(lambda: {"n": 0, "sev": Counter(), "zero": 0})
    for r in counted:
        for x in r["agents"]:
            if x["role"] in FINDERS and x["result"]:
                f = [i for i in (x["result"].get("findings") or []) if isinstance(i, dict)]
                g = rv[(r["kind"], x["role"])]
                g["n"] += 1
                g["sev"].update(i.get("severity") for i in f)
                g["zero"] += not f
    rows = [[k[0], k[1], g["n"], *(g["sev"].get(s, 0) for s in SEVERITIES), g["zero"]] for k, g in sorted(rv.items())]
    return ["## Review findings by reviewer", "",
            table(["run kind", "reviewer", "reviews", *SEVERITIES, "reviews with none"], rows), ""]


def time_section(counted: list[dict]) -> list[str]:
    """Where the agents' time went: tool time by kind, per role."""
    rows = []
    for role in (*dict.fromkeys(ROLES.values()), "other"):
        k: Counter = Counter()
        n: Counter = Counter()
        wall = 0.0
        for r in counted:
            for x in r["agents"]:
                if x["role"] == role and x["data"] and x["data"]["start"] is not None:
                    k.update(x["data"]["kinds"])
                    n.update(x["data"]["kind_counts"])
                    wall += x["data"]["end"] - x["data"]["start"]
        if wall:
            top = ", ".join(f"{kind} {v / 3600:.1f}h/{n[kind]}" for kind, v in k.most_common(6))
            rows.append([role, f"{wall / 3600:.1f}", top])
    return ["## Where the agents' time went (tool time by kind: hours / calls)", "",
            table(["role", "agent hours", "top tool kinds"], rows), ""]


def cache_section(counted: list[dict]) -> list[str]:
    """API calls by the time since the same agent's previous call: after 5 minutes the cache is gone."""
    gaps = [g for r in counted for x in r["agents"] if x["data"] for g in x["data"]["gaps"]]
    rows = []
    for lo, hi, name in GAP_BUCKETS:
        sel = [g for g in gaps if lo <= g[0] and (hi is None or g[0] < hi)]
        if sel:
            rewrote = sum(g[1] > 0.5 * (g[1] + g[2]) for g in sel) / len(sel)
            rows.append([name, len(sel), fmt_tok(med([g[1] for g in sel])), fmt_tok(med([g[2] for g in sel])),
                         fmt_tok(sum(g[1] for g in sel)), f"{rewrote:.0%}"])
    head = ["gap", "API calls", "median cache write", "median cache read", "cache write (total)",
            "calls that re-wrote most of the context"]
    md = ["## The prompt cache after a wait (API calls by the time since the same agent's previous call)", "",
          table(head, rows), ""]
    long_w = sum(g[1] for g in gaps if g[0] >= 300)
    long_usd = sum(g[3] for g in gaps if g[0] >= 300)
    all_w = sum(g[1] for g in gaps)
    if all_w:
        md += [f"Cache writes after a wait of 5 minutes or more: {fmt_tok(long_w)} of {fmt_tok(all_w)} "
               f"({long_w / all_w:.0%}), about {fmt_usd(long_usd)} list more than reading them "
               "(each call at its own model's prices).", ""]
    return md


def manager_rows(counted: list[dict], sessions: list[dict]) -> list[dict]:
    """Per session: its own lines, its hand-run subagents and its counted workflow runs, in API list $."""
    managers = []
    for s in sessions:
        man = s["manager"] or {}
        mtok = man.get("tokens") or {}
        hand_usd = sum(usd(h["data"]["tokens"]) for h in s["hand"])
        hand_read = sum(h["data"]["tokens"].get("usd_cache_read", 0) for h in s["hand"])
        sub = [x["data"] for r in counted if r["sid"] == s["id"] for x in r["agents"] if x["data"]]
        sub_tok: Counter = Counter()
        for d in sub:
            sub_tok.update(d["tokens"])
        # Summed in total_week's order (its runs, then the manager's own and hand-run $), so a one-session week is
        # the total to the last bit on any Python: 3.11's sum() rounds at each step, 3.12's compensates.
        own = [r for r in counted if r["sid"] == s["id"]]
        spent = sum(run_usd(r) for r in own) + (usd(mtok) + hand_usd)
        read = sum(x["data"]["tokens"].get("usd_cache_read", 0) for r in own for x in r["agents"] if x["data"])
        read += mtok.get("usd_cache_read", 0) + hand_read
        week = week_percent(spent, read)
        managers.append({
            "session": s["id"], "label": s["label"], "title": s["title"], "model": man.get("model"),
            "manager_usd": usd(mtok), "manager_read_usd": mtok.get("usd_cache_read", 0), "manager_fresh": fresh(mtok),
            "hand": len(s["hand"]), "hand_usd": hand_usd, "hand_read_usd": hand_read,
            "runs": sum(1 for r in counted if r["sid"] == s["id"]), "subagent_usd": usd(sub_tok),
            "subagent_ctx": sum(d["last_ctx"] for d in sub), "read_usd": read,
            "week_percent": week["percent"], "week_bracket": week["bracket"],
        })
    return managers


def manager_section(managers: list[dict], other_sessions: int) -> list[str]:
    head = ["session", "title", "manager API list $", "manager fresh", "model", "hand-run subagents",
            "their API list $", "workflow runs", "subagent API list $", "subagent final context", "% of a Max 20x week"]
    rows = [
        [m["label"], m["title"] or "", fmt_usd(m["manager_usd"]), fmt_tok(m["manager_fresh"]), m["model"] or "",
         m["hand"], fmt_usd(m["hand_usd"]), m["runs"], fmt_usd(m["subagent_usd"]), fmt_tok(m["subagent_ctx"]),
         fmt_week({"percent": m["week_percent"], "bracket": m["week_bracket"]})]
        for m in managers
    ]
    md = ["## Manager sessions (their own lines and hand-run subagents in the window)", "", table(head, rows), "",
          f"% of a Max 20x week: manager, hand-run and workflow subagents together, {week_rate()}.", ""]
    if other_sessions:
        md += [f"{other_sessions} other sessions of this checkout ran no workflow or have nothing in the window "
               "(name one with --session to see it).", ""]
    return md


def rewrite_kind(began: float, timers: list[tuple[float, float]], runs: list[dict]) -> str:
    """What held when a manager's idle gap began (REWRITE_KINDS): a keep-alive timer, a run of its own, neither."""
    if any(armed <= began < ended for armed, ended in timers):
        return "timer"
    if any(r["start"] <= began < r["end"] for r in runs):
        return "run"
    return "stop"


def rewrite_rows(sessions: list[dict], runs: list[dict]) -> list[dict]:
    """Per session with own API calls in the window: its cache re-writes after an idle gap over REWRITE_GAP (#305),
    by what held when the gap began, its keep-alive timers and its last call's context."""
    rows = []
    for s in sessions:
        man = s["manager"]
        if not man or not man["api_calls"]:
            continue
        own = [r for r in runs if r["sid"] == s["id"] and r["start"] is not None and r["end"] is not None]
        found = [
            {"at": iso(g[5] + g[0]), "idle_hours": g[0] / 3600, "tokens": g[1], "usd": g[4],
             "while": rewrite_kind(g[5], man["timers"], own)}
            for g in man["gaps"]
            if g[0] > REWRITE_GAP and g[1] > 0.5 * (g[1] + g[2])
        ]
        row = {"session": s["id"], "label": s["label"], "rewrites": len(found),
               "tokens": sum(f["tokens"] for f in found), "usd": sum(f["usd"] for f in found)}
        for kind in REWRITE_KINDS:
            sel = [f for f in found if f["while"] == kind]
            row[kind] = {"rewrites": len(sel), "usd": sum(f["usd"] for f in sel)}
        rows.append(row | {"timers": man["timers_armed"], "last_ctx": man["last_ctx"], "found": found})
    return rows


def rewrite_section(rows: list[dict]) -> list[str]:
    if not rows:
        return []
    head = ["session", "re-writes", "tokens re-written", "API list $", "a keep-alive timer armed",
            "a run of its own in flight", "neither (a stop)", "keep-alive timers", "context of its last call"]
    body = [
        [r["label"], r["rewrites"], fmt_tok(r["tokens"]), fmt_usd(r["usd"]),
         *(f"{r[k]['rewrites']} ({fmt_usd(r[k]['usd'])})" for k in REWRITE_KINDS), r["timers"], fmt_tok(r["last_ctx"])]
        for r in rows
    ]
    return ["## Manager cache re-writes after an idle gap over 1 hour (#305)", "", table(head, body), "",
            "A re-write is a session's own API call after over 1 hour without one that wrote most of its context to "
            "the cache again (at the 1-hour cache write price: $8 per 1M tokens on Opus 5.5). Each counts once, in "
            "the first column that held when the gap began: a keep-alive timer armed (a background `sleep`; the "
            "orchestrate-stage skill, §7), which should stay 0; a workflow run of the session in flight; else a stop "
            "for the human.", ""]  # fmt: skip


def other_section(counted: list[dict]) -> list[str]:
    rows = [
        [r["session"], r["wf"], r["kind"], f"#{r['issue']}" if r["issue"] else "", "yes" if r["finished"] else "no",
         mins(r["end"] - r["start"]) if r["start"] else "",
         fmt_tok(sum(total(x["data"]["tokens"]) for x in r["agents"] if x["data"])), fmt_usd(run_usd(r))]
        for r in counted
        if r["kind"] != "issue-task" or not r["finished"]
    ]
    return ["## Other runs (pr-rebase, resumed, unfinished, others)", "",
            table(["session", "run", "kind", "issue", "finished", "wall min", "tokens", "API list $"], rows), ""]


def ci_section(ci: dict) -> list[str]:
    md = ["## CI (GitHub Actions)", "",
          f"Runs in the window: {ci['runs']} ({', '.join(f'{k} {v}' for k, v in ci['by_outcome'].items())}); "
          f"reruns (attempt > 1): {ci['reruns']}; queue (created to started) median {ci['queue_s']:.0f} s.", ""]
    if ci.get("cut"):
        md += [f"`gh run list` returned its limit of {CI_LIST_LIMIT} runs: older runs of the window are missing.", ""]
    if ci["job_s"]:
        md += [f"The last {ci['green']} green runs: the job {med(ci['job_s']) / 60:.1f} min median "
               f"({min(ci['job_s']) / 60:.1f} to {max(ci['job_s']) / 60:.1f}).", ""]
    if ci["steps"]:
        md += [table(["verify step", "seconds (median)", "max"],
                     [[k, f"{med(v):.0f}", f"{max(v):.0f}"] for k, v in ci["steps"].items()]), ""]
    return md


# --- the quality scorecard (#314) ---------------------------------------------------------------------------------


def pr_of(pub: dict) -> tuple[int | None, str | None]:
    """A publisher result's PR: (its number, from pr_number, else from pr_url; its URL)."""
    url = pub.get("pr_url") if isinstance(pub.get("pr_url"), str) and pub.get("pr_url") else None
    num = pub.get("pr_number")
    if isinstance(num, bool) or not isinstance(num, (int, float)) or num != int(num) or num <= 0:
        num = None
    found = PR_URL.search(url) if url else None
    if num is None and found:
        num = int(found.group(2))
    return (int(num) if num is not None else None), url


def count_of(value: object) -> int | None:
    """The length of a result's list; None when the key is missing (an older result shape), never 0."""
    return len(value) if isinstance(value, list) else None


def quality_of(r: dict) -> dict:
    """A finished issue-task run's journal signals (the module docstring); None wherever the journal does not say."""
    findings: Counter = Counter()
    serious, reviewed = 0, False
    for x in r["agents"]:
        if x["role"] in SERIOUS_FROM and x["result"] is not None:
            reviewed = reviewed or x["role"] in REVIEWERS
            listed = x["result"].get("findings")
            for f in listed if isinstance(listed, list) else []:
                if isinstance(f, dict):
                    sev = str(f.get("severity", "")).lower()
                    findings[sev] += 1
                    serious += bool(SERIOUS.search(sev))
    skeptics = [x["result"] for x in r["agents"] if x["role"] == "skeptic" and x["result"] is not None]
    checked: int | None = None
    refuted: int | None = None
    opened: int | None = None
    if reviewed:
        if skeptics or not serious:
            checked, refuted = len(skeptics), sum(s.get("refuted") is True for s in skeptics)
        opened = serious - (refuted or 0)
    pubs = [x for x in r["agents"] if x["role"] == "publisher"]
    pub = next((x["result"] for x in reversed(pubs) if x["result"] is not None), None) or {}
    pr, url = pr_of(pub)
    stopped = pub.get("stopped_by_mutants") is True
    implementers = [x["data"] for x in r["agents"] if x["role"] == "implementer" and x["data"]]
    design = any(d.get("design") for d in implementers) if implementers else None
    data = [x["data"] for x in pubs if x["data"]]
    runs = sum(d["kind_counts"].get("publish", 0) for d in data) if data else None
    settings = {
        x["role"]: {"model": x["data"]["model"], "effort": x["data"]["effort"]}
        for x in r["agents"]
        if x["data"] and x["data"]["start"] is not None
    }
    return {
        "session": r["session"], "issue": r["issue"], "wf": r["wf"], "start": r["start"], "end": r["end"],
        "usd": run_usd(r), "published": pub["published"] if isinstance(pub.get("published"), bool) else None,
        "pr": pr, "pr_url": url, "findings": dict(findings) if reviewed else None,
        "serious": serious if reviewed else None, "checked": checked, "refuted": refuted, "open": opened,
        "clean": None if opened is None or design is None else opened == 0 and not stopped and not design,
        "design": design, "stopped_by_mutants": stopped,
        "fixed": count_of(pub.get("fixed")), "not_fixed": count_of(pub.get("not_fixed")),
        "needs_engineer": count_of(pub.get("needs_engineer")), "publish_runs": runs,
        "fix_rounds": None if runs is None else max(0, runs - 1), "settings": settings,
    }  # fmt: skip


def mentions(text: str, numbers: list[int], repo: str) -> bool:
    """Whether text names one of the numbers as a whole `#N`, or as `owner/repo#N` of the PR's own repository."""
    qualified = f"|(?<![\\w.-]){re.escape(repo)}" if repo else ""
    return any(re.search(rf"(?:(?<![\w/#.-]){qualified})#{n}(?!\d)", text) for n in numbers)


def fixes_in_body(body: str, numbers: list[int], repo: str) -> bool:
    """Whether a fix PR's body names the task in a sentence that reverts or repairs it (REGRESSION), outside its
    "Found by" lines and its Merge order and Verification sections."""
    text = LISTING_SECTION.sub("", FOUND_BY.sub("", body))
    return any(REGRESSION.search(s) and mentions(s, numbers, repo) for s in SENTENCE_END.split(text))


def ci_rounds(runs: list[dict], branch: object, opened: float | None, end: float | None) -> dict:
    """A PR's CI rounds: one per head SHA of the pull_request runs on its branch since it opened (module docstring)."""
    mine = [r for r in runs if r.get("event") == "pull_request" and r.get("headBranch") == branch
            and (opened is None or (stamp(r.get("createdAt")) or 0) >= opened - 60)]  # fmt: skip
    found: dict = {"ci_runs": len(mine)}
    rounds: dict[object, dict] = {}
    for r in sorted(mine, key=lambda r: stamp(r.get("createdAt")) or 0):
        g = rounds.setdefault(r.get("headSha"), {"first": stamp(r.get("createdAt")), "conclusions": [],
                                                 "rerun": False})  # fmt: skip
        g["conclusions"].append(str(r.get("conclusion") or ""))
        attempt = r.get("attempt")
        g["rerun"] = g["rerun"] or (isinstance(attempt, int) and attempt > 1)
    outcomes = []
    for g in rounds.values():
        cs = g["conclusions"]
        outcome = ("red" if any(c in CI_RED for c in cs) else "success" if "success" in cs
                   else "pending" if "" in cs else None)  # fmt: skip
        if outcome:  # all cancelled or skipped: no round
            outcomes.append((g["first"], outcome, g["rerun"]))
    if not outcomes:
        return found
    red = [t for t, o, _rerun in outcomes if o == "red"]
    _t, first, rerun = outcomes[0]
    return found | {
        "ci_red_rounds": len(red),
        "ci_red_after_run": None if end is None else sum(t is not None and t >= end for t in red),
        "ci_last": outcomes[-1][1],
        "ci_reruns": sum(o[2] for o in outcomes),
        # A re-run shows only its last attempt: a first round re-run to green may have been red (a flaky run).
        "green_first": None if rerun and first == "success" else {"success": True, "red": False}.get(first),
    }


def quality_github(q: dict, github: dict | None) -> dict:
    """A run's GitHub signals (GITHUB_SIGNALS) from read_github's lists; all None when they cannot be known."""
    out: dict = dict.fromkeys(GITHUB_SIGNALS)
    if not github or "prs" not in github or q["pr"] is None:
        return out
    pr = next((p for p in github["prs"] if p.get("number") == q["pr"]), None)
    if pr is None or (q["pr_url"] and str(pr.get("url", "")).rstrip("/") != q["pr_url"].rstrip("/")):
        return out  # not in the list, or a PR of another repository
    found = PR_URL.search(str(pr.get("url", "")))
    repo = found.group(1) if found else ""
    opened = stamp(pr.get("createdAt"))
    out["pr_state"] = pr.get("state")
    out["merged"] = pr.get("state") == "MERGED" or bool(pr.get("mergedAt"))
    runs_from = github.get("runs_from")
    if runs_from is None or (opened is not None and opened >= runs_from):
        out.update(ci_rounds(github.get("runs") or [], pr.get("headRefName"), opened, q["end"]))
    numbers = [n for n in (q["issue"], q["pr"]) if n is not None]
    out["followups"] = sorted(
        i["number"] for i in github.get("issues") or []
        if i.get("number") not in numbers
        and (q["start"] is None or (stamp(i.get("createdAt")) or 0) >= q["start"])
        and any(mentions(m.group(0), numbers, repo) for m in FOUND_BY.finditer(str(i.get("body") or "")))
    )  # fmt: skip
    own = re.compile(rf"^[A-Za-z]+/{q['issue']}-") if q["issue"] is not None else None
    fixups = []
    for p in github["prs"]:
        title = str(p.get("title") or "")
        created = stamp(p.get("createdAt"))
        if p.get("number") == q["pr"] or not FIXUP_TITLE.search(title):
            continue
        if opened is not None and (created is None or created <= opened):
            continue
        if own and own.match(str(p.get("headRefName") or "")):
            continue
        if mentions(title, numbers, repo) or fixes_in_body(str(p.get("body") or ""), numbers, repo):
            fixups.append(p["number"])
    out["fixups"] = sorted(fixups)
    return out


def stat(values: list) -> dict:
    """The median of the known values (None: unknown), how many are known, and of how many."""
    known = [v for v in values if v is not None]
    return {"median": statistics.median(known) if known else None, "known": len(known), "of": len(values)}


def pr_key(q: dict, i: int) -> object:
    """One key per PR (a run without one is its own), so PR-level signals count once when two runs end on a PR."""
    return i if q["pr"] is None else (q["repo"], q["pr"])


def url_repo(url: str | None) -> str | None:
    found = PR_URL.search(url or "")
    return found.group(1) if found else None


def quality_summary(label: str, rows: list[dict]) -> dict:
    """A session's (or a wave's) runs: medians and sums of the known signals, and API list $ per green-first PR."""
    units = list({pr_key(q, i): q for i, q in enumerate(rows)}.values())
    prs = [q for q in units if q["pr"] is not None]
    green = [q["green_first"] for q in units if q["green_first"] is not None]
    spent = sum(q["usd"] for q in rows)
    lists = {k: [q[k] for q in units if q[k] is not None] for k in ("followups", "fixups")}
    return {
        "session": label, "tasks": len(rows), "usd": spent,
        **{k: stat([q[k] for q in rows]) for k in RUN_SIGNALS},
        **{k: stat([q[k] for q in prs]) for k in PR_SIGNALS},
        "sums": {k: sum(q[k] for q in rows if q[k] is not None) for k in RUN_SIGNALS}
        | {k: sum(q[k] for q in prs if q[k] is not None) for k in PR_SIGNALS},
        "prs": len(prs), "merged": sum(q["merged"] is True for q in prs),
        "merged_known": sum(q["merged"] is not None for q in prs),
        "green_first": sum(green), "green_known": len(green),
        "usd_per_green_first": spent / sum(green) if sum(green) else None,
        **{k: sorted({n for lst in v for n in lst}) if v else None for k, v in lists.items()},
    }  # fmt: skip


def quality_settings(runs: list[dict], rows: list[dict]) -> list[dict]:
    """Per role setting (role, model, effort) of every agent of the scored runs: agents, their median API list $, and
    the medians of the runs they took part in. A clean run's publisher also counts as "publisher (clean run)"."""
    groups: dict[tuple[str, str, str], dict] = {}
    for i, (r, q) in enumerate(zip(runs, rows)):
        for x in r["agents"]:
            d = x["data"]
            if not d or d["start"] is None:
                continue
            roles = [x["role"], *(["publisher (clean run)"] if x["role"] == "publisher" and q["clean"] else [])]
            for role in roles:
                g = groups.setdefault((role, str(d["model"]), str(d["effort"])), {"usd": [], "rows": {}})
                g["usd"].append(usd(d["tokens"]))
                g["rows"][i] = q
    found = []
    for (role, model, effort), g in sorted(groups.items()):
        part = quality_summary(role, list(g["rows"].values()))
        found.append({"role": role, "model": model, "effort": effort, "agents": len(g["usd"]),
                      "runs": len(g["rows"]), "usd": med(g["usd"]),
                      **{k: part[k] for k in (*RUN_SIGNALS, *PR_SIGNALS, "green_first", "green_known")}})  # fmt: skip
    return found


def github_status(github: dict | None) -> dict:
    """Where the GitHub signals came from, for the record and the notes."""
    if github is None:
        return {"skipped": "not read"}
    if "prs" in github:
        return {"read_at": github.get("read_at"), "cut": github.get("cut") or []}
    return {k: v for k, v in github.items() if k in ("error", "skipped")}


def quality_record(runs: list[dict], labels: list[str], github: dict | None) -> dict:
    """The scorecard of the finished issue-task runs: per run, per session, over all, per role setting."""
    rows = [q | quality_github(q, github) for q in map(quality_of, runs)]
    # A PR's repository: its URL's, else (a result with pr_number only) the one most PR URLs name, so both result
    # shapes of one PR are one PR.
    repos = Counter(r for q in rows if (r := url_repo(q["pr_url"])))
    home = repos.most_common(1)[0][0] if repos else ""
    for q in rows:
        q["repo"] = None if q["pr"] is None else url_repo(q["pr_url"]) or home
    quality = {
        "tasks": rows,
        "sessions": [quality_summary(label, sel) for label in labels if (sel := [q for q in rows
                                                                                 if q["session"] == label])],
        "all": quality_summary("all", rows),
        "settings": quality_settings(runs, rows),
        "github": github_status(github),
    }  # fmt: skip
    quality["compact"] = quality_compact(quality)
    return quality


def fmt_v(value: object) -> str:
    """A signal in a table: "?" when unknown."""
    if value is None:
        return "?"
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, float):
        return f"{value:g}"
    return str(value)


def fmt_q(s: dict) -> str:
    """A stat(): its median, with "(k/n)" when only k of n are known; "?" when none is."""
    if not s["known"]:
        return "?"
    return fmt_v(s["median"]) + (f" ({s['known']}/{s['of']})" if s["known"] < s["of"] else "")


def fmt_nums(numbers: list[int] | None) -> str:
    return "?" if numbers is None else ", ".join(f"#{n}" for n in numbers) or "none"


def fmt_green(s: dict) -> str:
    return f"{s['green_first']} of {s['green_known']}" if s["green_known"] else "?"


def quality_section(quality: dict) -> list[str]:
    rows = []
    for q in quality["tasks"]:
        pub = q["settings"].get("publisher")
        rows.append([
            q["session"], f"#{q['issue']}", q["pr"] or ("none" if q["published"] is False else "?"), fmt_v(q["merged"]),
            fmt_v(q["serious"]), "?" if q["checked"] is None else f"{q['refuted']}/{q['checked']}", fmt_v(q["open"]),
            fmt_v(q["clean"]), fmt_v(q["fixed"]), fmt_v(q["not_fixed"]), fmt_v(q["needs_engineer"]),
            fmt_v(q["fix_rounds"]),
            "?" if q["ci_red_rounds"] is None else f"{q['ci_red_rounds']} ({fmt_v(q['ci_red_after_run'])})",
            fmt_v(q["green_first"]), fmt_nums(q["followups"]), fmt_nums(q["fixups"]),
            f"{pub['model']} {pub['effort']}" if pub else "?", fmt_usd(q["usd"]),
        ])  # fmt: skip
    head = ["session", "issue", "PR", "merged", "blockers+majors", "refuted/checked", "open", "clean", "fixed",
            "not fixed", "needs engineer", "publisher fix rounds", "CI red rounds (after the run)",
            "green on the first CI round", "Found-by follow-ups", "fix-up PRs", "publisher", "API list $"]  # fmt: skip
    md = ["## Quality per finished issue-task run (#314)", "", table(head, rows), ""]
    sessions = [
        [s["session"], s["tasks"], f"{s['prs']} ({s['merged'] if s['merged_known'] else '?'} merged)",
         *(fmt_q(s[k]) for k in ("serious", "refuted", "open", "not_fixed", "fix_rounds", "ci_red_rounds")),
         fmt_green(s), fmt_nums(s["followups"]), fmt_nums(s["fixups"]), fmt_usd(s["usd"]),
         fmt_usd(s["usd_per_green_first"]) if s["usd_per_green_first"] is not None else "?"]
        for s in [*quality["sessions"], *([quality["all"]] if len(quality["sessions"]) > 1 else [])]
    ]  # fmt: skip
    head = ["session", "tasks", "PRs", "blockers+majors", "refuted", "open", "not fixed", "publisher fix rounds",
            "CI red rounds", "green on the first CI round", "Found-by follow-ups", "fix-up PRs", "API list $",
            "$ per PR green on its first CI round"]  # fmt: skip
    md += ["Per session (a wave when run with --since <wave start>; medians, PR signals once per PR):", "",
           table(head, sessions), ""]  # fmt: skip
    settings = [
        [s["role"], s["model"], s["effort"], s["agents"], s["runs"], fmt_usd(s["usd"]),
         *(fmt_q(s[k]) for k in ("serious", "open", "not_fixed", "fix_rounds", "ci_red_rounds")), fmt_green(s)]
        for s in quality["settings"]
    ]  # fmt: skip
    head = ["role", "model", "effort", "agents", "runs", "API list $ per agent (median)", "blockers+majors", "open",
            "not fixed", "publisher fix rounds", "CI red rounds", "green on the first CI round"]  # fmt: skip
    md += ["By role setting (the medians of the runs each took part in):", "", table(head, settings), ""]
    status = quality["github"]
    if "read_at" in status:
        source = f"GitHub read at {status['read_at']}" + (
            f" ({', '.join(status['cut'])} at the list limit: older ones are missing)" if status["cut"] else "")
    else:
        source = "GitHub was not read (" + (status.get("skipped") or f"gh failed: {status.get('error')}") + ")"
    md += [f"\"?\" is unknown, never 0: no PR, an older result shape, skeptics not run, a PR of another repository, "
           f"a branch without CI runs, or GitHub not read. {source}. \"clean\": no blocker or major left after the "
           "skeptics, not stopped by mutants, not a design task (#315's rule, from the journal). CI red rounds: "
           "head SHAs with a red run (failure, timed_out, startup_failure), in brackets those that began after the "
           "run ended. Found-by follow-ups are a lower bound (only issues whose \"Found by\" line names the task); "
           "fix-up PRs are later `revert` or `fix` PRs naming it in a sentence that reverts or repairs it: check "
           "both lists before trusting a count.", ""]  # fmt: skip
    return md


def quality_compact(quality: dict) -> str:
    """One line for the compact summary (a wave comment): the quality of all scored runs and its cost."""
    a = quality["all"]

    def summed(key: str, of: str = "runs") -> str:
        """The sum of the known values, with "in k of n" when only k of n are known; "?" when none is."""
        s = a[key]
        if not s["known"]:
            return "?"
        return f"{a['sums'][key]}" + (f" in {s['known']} of {s['of']} {of}" if s["known"] < s["of"] else "")

    def counted(key: str) -> str:
        """How many numbers a list holds; "?" when no run's list is known (unknown is never 0)."""
        return "?" if a[key] is None else str(len(a[key]))

    serious = summed("serious")
    if a["serious"]["known"]:
        serious += f" ({a['sums']['refuted']} refuted, {a['sums']['open']} open)"
    line = (f"quality: {a['tasks']} tasks, {a['prs']} PRs ({a['merged'] if a['merged_known'] else '?'} merged); "
            f"blockers+majors {serious}; not fixed {summed('not_fixed')}; "
            f"publisher fix rounds {summed('fix_rounds')}")  # fmt: skip
    status = quality["github"]
    if "read_at" not in status:
        why = status.get("skipped") if "skipped" in status else "gh failed"
        return line + ("; GitHub: not read" + (f" ({why})" if why != "not read" else ""))
    if a["green_first"]:
        cost = (f"{fmt_usd(a['usd_per_green_first'])} per PR green on its first CI round "
                f"({a['green_first']} of {a['green_known']} known)")  # fmt: skip
    elif a["green_known"]:
        cost = f"none of {a['green_known']} PRs green on their first CI round"
    else:
        cost = "no PR with a known first CI round"
    after = f" ({a['sums']['ci_red_after_run']} after the run)" if a["ci_red_after_run"]["known"] else ""
    return (line + f"; CI red rounds {summed('ci_red_rounds', 'PRs')}{after}; "
            f"Found-by follow-ups {counted('followups')}, fix-up PRs {counted('fixups')}; {cost}")


def compact_lines(
    tasks: list[dict], counted: list[dict], by_row: dict[str, list[dict]], history: list[dict], ci: dict | None,
    managers: list[dict], week: dict, window: str, *, quality: dict | None = None,
) -> list[str]:
    """At most ten lines for a wave comment: time and API list $ per task and in total, the quality scorecard's line
    (#314), the % of the week, verify."""
    other = [r for r in counted if r["kind"] != "issue-task" or not r["finished"]]
    lines = [f"metrics, {window}: {len(tasks)} finished issue-task runs, {len(other)} other runs "
             f"({sum(not r['finished'] for r in counted)} unfinished)"]
    if tasks:
        lines.append("per task (wall min, API list $): " + ", ".join(
            f"#{p['issue']} {mins(p['wall'])} min {fmt_usd(p['usd'])}" for p in tasks))
        wall, cost = med([p["wall"] for p in tasks]), med([p["usd"] for p in tasks])
        ctx, calls = med([p["ctx"] for p in tasks]), med([p["calls"] for p in tasks])
        lines.append(f"task medians: {mins(wall)} min, {fmt_usd(cost)}, {fmt_tok(ctx)} final context, "
                     f"{calls:.0f} tool calls")
        if quality:
            lines.append(quality["compact"])
    task_usd = sum(p["usd"] for p in tasks)
    other_usd = sum(run_usd(r) for r in other)
    man_usd = sum(m["manager_usd"] + m["hand_usd"] for m in managers)
    spent = task_usd + other_usd + man_usd
    lines.append(f"total API list $: tasks {fmt_usd(task_usd)} + other runs {fmt_usd(other_usd)} + managers and their "
                 f"hand-run subagents {fmt_usd(man_usd)} = {fmt_usd(spent)}")
    w, k = WEEK_CENTRAL
    (w0, _k0), (w1, _k1) = WEEK_BRACKET
    lo, hi = week["bracket"]
    lines.append(f"% of a Max 20x week: {week['percent']:.1f}% with cache reads at {w:.0%} of their list $ (${k} per "
                 f"1%); {lo:.1f} to {hi:.1f}% if the limit counts them at {w0 * 100:g} to {w1:.0%}")
    for name, lst in (("local verify (agents)", agent_verifies(by_row)), ("local verify (history file)", history),
                      ("local verify (managers)", by_row.get("managers", []))):
        if lst:
            tots = [v["total"] for v in lst if v["total"]]
            names: list[str] = []
            for v in lst:
                names += [s for s in v["steps"] if s not in names]
            steps = ", ".join(f"{s} {med([v['steps'][s][1] for v in lst if s in v['steps']]):.0f}" for s in names)
            waits, over = slot_waits(lst)
            slot = (f"; slot wait median {med(waits):.0f} s (max {max(waits):.0f}), {over} over the limit"
                    if waits else "")  # fmt: skip
            lines.append(f"{name}: {len(lst)} runs, {sum(v['status'] == 'FAILED' for v in lst)} red, median "
                         f"{med(tots):.0f} s (max {max(tots, default=0):.0f}){slot}; steps: {steps}")
    if ci is not None:
        job = f"job {med(ci['job_s']) / 60:.1f} min median" if ci["job_s"] else "no green run"
        vt = ci["steps"].get("verify total")
        lines.append(f"CI: {ci['runs']} runs in the window; last {ci['green']} green: {job}"
                     + (f", verify {med(vt):.0f} s" if vt else ""))
    return lines[:10]


def main(
    sessions: list[str] | None = None,
    since: str | None = None,
    until: str | None = None,
    ci: int = 0,
    out: str | None = None,
    compact: bool = False,
    *,
    dirs: list[Path] | None = None,
    history: list[Path] | None = None,
    gh=_gh,
    no_gh: bool = False,
) -> int:
    t_since = parse_time(since) if since else None
    t_until = parse_time(until) if until else time.time()
    if ci < 0:
        raise Failure(f"--ci {ci}: the number of green CI runs to read is 0 or more")
    if t_since is not None and t_since >= t_until:
        raise Failure(f"--since {since} is not before --until {until or 'now'}")
    checkout = None
    if dirs is None:
        checkout = main_checkout()
        dirs = agents_check.project_dirs(checkout)
    if history is None:
        history = history_paths(checkout or main_checkout())
    data = collect(dirs, session_filter(sessions or []), t_since, t_until) if dirs else None
    folder = Path(out) if out else OUT / "metrics"
    if data and not data["sessions"] and data["other_sessions"]:
        # Transcripts exist but none falls in the window: an empty report replaces an older one, which would look
        # current.
        window = f"{iso(t_since) or 'the first transcript'} to {iso(t_until)}"
        message = f"metrics: nothing in the window {window} ({data['other_sessions']} sessions read)."
        folder.mkdir(parents=True, exist_ok=True)
        with io.open(folder / "metrics.md", "w", encoding="utf-8", newline="\n") as f:
            f.write(f"{message}\n")
        with io.open(folder / "metrics.json", "w", encoding="utf-8", newline="\n") as f:
            json.dump({"since": iso(t_since), "until": iso(t_until), "sessions": [], "runs": [], "tasks": []}, f)
            f.write("\n")
        say(message)
        return 0
    if not data or not data["sessions"]:
        where = ", ".join(str(d) for d in dirs) or str(
            agents_check.config_dir() / "projects" / project_key(checkout or ROOT)
        )
        named = " for the named sessions" if sessions else ""
        say(f"metrics: no Claude Code transcripts of this checkout in {where}{named}; nothing to measure.")
        return 0
    verify_runs = read_history(history, t_since, t_until)
    ci_info = ci_data(t_since, t_until, ci, gh) if ci else None
    github: dict = {"skipped": "--no-gh"}
    if not no_gh:
        try:
            github = read_github(gh)
        except (Failure, ValueError) as exc:  # the quality scorecard's GitHub signals stay unknown
            github = {"error": str(exc)}
            if not compact:  # the compact summary's quality line says it
                warn(f"metrics: GitHub not read, its quality signals are unknown: {exc}")
    md, record, summary = build(data, verify_runs, ci_info, t_since, t_until, github=github)
    folder.mkdir(parents=True, exist_ok=True)
    text = "\n".join(["## Summary", "", "```", *summary, "```", "", *md])
    with io.open(folder / "metrics.md", "w", encoding="utf-8", newline="\n") as f:
        f.write(text.rstrip("\n") + "\n")
    with io.open(folder / "metrics.json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(record, f, indent=1, default=_json_default)
        f.write("\n")
    if compact:
        say("\n".join(summary))  # only the summary: the manager pastes it into a wave comment as it is
    else:
        say("\n".join([*md, "## Summary", "", *summary]))
        say(f"\nmetrics: wrote {folder / 'metrics.md'} and metrics.json")
    return 0


def _json_default(value: object) -> object:
    if isinstance(value, (set, frozenset)):
        return sorted(value)
    if isinstance(value, Path):
        return str(value)
    return str(value)
