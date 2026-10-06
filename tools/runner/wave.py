"""`wave`: a manager session's workflow runs and their handover data, read-only from its transcript and the journals.

Used by a manager session (the orchestrate-stage skill, #277) for the body of a wave comment and for a resume or a
fresh relaunch. Sources (metrics' module docstring says where the transcripts are):
- the manager's transcript <folder>/<sid>.jsonl, in one pass:
  - each Workflow tool_use (an assistant record): its input {name or scriptPath or script, args, resumeFromRunId};
  - the tool_result paired with it by tool_use_id (a user record): the run's id from the record's toolUseResult
    {runId, taskId, workflowName, transcriptDir}, else from "Run ID: wf_..." in the result's text;
  - task notifications (<task-notification> in a queue-operation enqueue record or a user record), paired by their
    <tool-use-id> (else <task-id>): the run's end (the earliest of them) and its status (completed, failed, killed);
  - the API calls (deduplicated by message id as metrics.read_agent does) and the session's title for the footer;
- each run's <sid>/subagents/workflows/<runId>/journal.jsonl through metrics.read_run: the agents, their labels,
  phases and structured results.
A notification's <result> is cut at about 8 kB, so a finished run's PR, CI, published, not_fixed, needs_engineer and
human_steps come only from the journal; the notification gives only its status and whether its result says "stopped".

Rules:
- args are kept exactly as the Workflow call passed them; a resume (resumeFromRunId) that passed none inherits the
  args of the run it resumes. `--args n` prints the args of the newest launch whose args.n is n.
- a run is finished when its latest launch has a notification, or when its journal reached the script's end:
  issue-task: a publisher result, or an implementer result with verify_green false and no publisher started (the
  script stops there); pr-rebase: a fix result, a red or unpublished rebase, or every reviewer answered with no
  blocker or major finding left to fix (each refuted by a skeptic); another workflow: every started agent answered.
  Any other run is running: its agent now is each unanswered `started` (label and phase), and the minutes since the
  newest write to its journal or agent transcripts tell a live run from a stale one (a session that died never sends
  the notification).
- a finished run is flagged "relaunch fresh, never resume" when its outcome (the publisher's result, else the
  pr-rebase fix's, else the rebase's) has published false, a publisher has stopped_by_mutants, issue-task stopped on
  a red implementer, a pr-rebase rebase is red or unpublished, or the notification's result says "stopped".
- Handover data holds the args of each running run, and of each finished run since --since that failed, was killed or
  stopped, unless a later launch took its place: a resume of it, or a later launch of the same issue and workflow under
  another run id (a fresh relaunch; shown as "relaunched as <run>").

The whole wave comment (#278): `--since` also reads, through Sources (tests replace it), each source on its own (one
that fails shows "Unavailable: <error>" in its section and a warn line; the rest of the body is still written):
- one `gh pr list --state merged --search sort:updated-desc` (the MERGED_LIMIT most recently updated, every base; at
  the limit the section names how far back it reached): the PRs merged into --base since --since (gh's merged:>=
  search is date-only, so the window is filtered by mergedAt here), and for housekeeping the PRs whose work reached
  main through a release or a parent branch (that branch's own PR into main merged at or after them);
- `gh pr list --state open`: the PRs into --base and those stacked on them, with a one-word CI cell
  (statusCheckRollup: red beats pending, else green; none when nothing reported) and mergeStateStatus;
- merge.check([], base) with its printed lines captured: the verdict always, its tables and details as printed only
  when it flagged something or failed; --no-merge-check skips it;
- metrics.collect, read_history and build in memory for this session since --since (and --stage-since): metrics' own
  compact lines (no metrics file is written; COST_EXTRAS adds lines over metrics' JSON record);
- `git worktree list --porcelain` in the main checkout, sessions.alive_in and `gh issue list --state open`: a fenced
  PowerShell block per command for each task worktree (and the manager's release-m<k> worktree) whose work is on
  main, with no running run of this session there, HEAD at the merged head and no live Claude session in it; a
  "For you:" line naming only what a live session holds (#343: the manager runs the ready blocks itself), then the
  ready blocks; waits as one-line notes; the issues still open whose PR reached main since --since;
- for the handover verdict (#467): the PRs merged into main since the session's first record (not --since) whose
  files include root CLAUDE.md or a file under .claude/rules/ or .claude/agents/ (one `gh pr list --base main --json
  files`, and `gh pr view <n> --json files` for a merge the search has not caught up with; no call when nothing merged
  into main since then), and `git diff --name-only HEAD...origin/main` on those paths in the main checkout (no fetch).
The handover verdict ends the footer and is stdout's last line (orchestrate-stage §7 runs it at each turn end):
"handover due: <why>" when the last call's context is over 300k or the session over 12 h old, even with runs in
flight (then: stop them, then post the handover; a run whose agent publishes, rebases or fixes only after that agent),
or, once no run is in flight, when such a merge changed the instructions (until then "launch nothing new"); else
"handover not due", with "at a stop for the human: due" when no run is in flight and the context is over 150k. A run
with no line for over STALE_MINUTES is named as stale, not counted in flight. A failed read says so in the line.
The body's sections, in order (SECTIONS): title and header, --notes, merged, finished runs, running, open PRs, merge
safety, cost, housekeeping, handover data, footer. Over SPLIT_LIMIT characters the handover data moves, each run's
block whole, to <out>-2.md, <out>-3.md, ..., posted as the next comments.
Read-only: it writes only its --out file(s) (default tools/out/wave/wave-<sid8>.md; with --args only an --out given)
and posts, edits and launches nothing; merge-check's `git fetch` (and the PR heads it fetches) is its only write, to
the shared git dir. `--args` reads no source beyond the transcript.
"""

from __future__ import annotations

import io
import json
import os
import re
import sys
import time
from collections import Counter
from collections.abc import Callable, Iterable
from contextlib import redirect_stdout
from dataclasses import dataclass, field
from pathlib import Path, PurePath, PureWindowsPath
from typing import Any

from . import agents_check, common, merge, metrics, sessions
from .common import OUT, Failure, ensure_out, say, warn

RELAUNCH = "relaunch fresh, never resume"
RUN_ID = re.compile(r"Run ID:\s*(wf_[\w-]+)")
# "stopped" as a key of the workflow's own result; an escaped \"stopped\" sits inside an agent's string and is not one.
STOPPED = re.compile(r'(?<!\\)"stopped"\s*:\s*"((?:[^"\\]|\\.)*)')
# GitHub's limit on a comment body, in characters; over SPLIT_LIMIT the handover data moves to the next comments.
COMMENT_LIMIT = 65536
SPLIT_LIMIT = 60000
FOOTER_CALLS = 20
# A workflow's notification says so in its summary ('Dynamic workflow "…" completed'); the other notifications in a
# manager's queue (background shells, monitors, its subagents' tasks) are not runs and are passed over.
WORKFLOW_NOTE = re.compile(r"\bworkflow\b", re.I)
REVIEW_ROLES = ("code-reviewer", "netcode-security-reviewer", "netcode-second-reviewer", "godot-api-checker")
# The branch every task's work finally lands in: worktree-done checks against origin/main.
MAIN = "main"
# One `gh pr list --state merged` serves the merged section (filtered by base and mergedAt here: gh's merged:>= search
# is date-only) and housekeeping (every base, for PRs that reached main through a release or a parent branch).
# gh lists PRs by creation date unless a search sorts them: by update, a PR merged lately comes first however old it is.
MERGED_LIMIT = 500
MERGED_SEARCH = "sort:updated-desc"
MERGED_FIELDS = (
    "number,title,headRefName,baseRefName,mergedAt,mergeCommit,closingIssuesReferences,headRefOid,updatedAt"
)
OPEN_FIELDS = "number,title,headRefName,baseRefName,isDraft,statusCheckRollup,mergeStateStatus,closingIssuesReferences"
# The issue of a task branch <area>/<n>-<slug> (merge.TASK_BRANCH_RE's shape).
TASK_BRANCH = re.compile(r"^[a-z][a-z0-9]*/(\d+)-")
# The stage window's lines of metrics' compact summary (--stage-since), by their start; when none matches (metrics
# reworded them), the stage window's whole summary is shown.
STAGE_LINES = ("total API list $", "% of a Max 20x week")
# More cost lines, each a function of metrics' JSON record for --since (build's second value); #314's quality line
# may go here when it is not one of metrics' compact lines already (those flow through unchanged).
COST_EXTRAS: list[Callable[[dict], list[str]]] = []
RELEASE_WORKTREE = re.compile(r"^release-m(\d+)$")
CI_PASS = {"SUCCESS", "NEUTRAL", "SKIPPED"}
CI_PENDING = {"PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}
# The handover verdict (#467; orchestrate-stage §7): due when strictly over a threshold.
HANDOVER_CONTEXT = 300_000
HANDOVER_HOURS = 12.0
STOP_CONTEXT = 150_000
# The agents' instructions a manager hands its workflow agents from its own cache: root CLAUDE.md only (core/CLAUDE.md
# and the like load from disk in the agent's own folder), the rules and the agent types.
INSTRUCTION_FILES = ("CLAUDE.md",)
INSTRUCTION_DIRS = (".claude/rules/", ".claude/agents/")
FILES_FIELDS = "number,baseRefName,mergedAt,files"
FILES_LIMIT = 200
# Agents that push or rebase a branch: a run is stopped for a handover only between them.
PUSHING_ROLES = ("publisher", "pr-rebase", "pr-rebase fix")
# A running run with no line for longer is stale for the verdict (its agents block no call over 240 s, #303).
STALE_MINUTES = 60


@dataclass
class Notice:
    time: float
    status: str
    summary: str
    result_text: str
    output_file: str
    task_id: str
    tool_use_id: str


@dataclass
class Launch:
    tool_use_id: str
    time: float
    name: str
    script_path: str | None
    args: dict | None
    passed_args: bool
    resume_from: str | None
    run_id: str | None = None
    task_id: str | None = None
    run_dir: Path | None = None
    notice: Notice | None = None
    paired: bool = False


@dataclass
class Session:
    sid: str
    path: Path
    folder: Path
    title: str | None = None
    first: float | None = None
    last: float | None = None
    calls: list[dict] = field(default_factory=list)
    last_ctx: int = 0
    launches: list[Launch] = field(default_factory=list)
    skipped: Counter = field(default_factory=Counter)


@dataclass
class Run:
    run_id: str
    launches: list[Launch]
    name: str
    issue: int | None
    args: dict | None
    status: str
    finished: bool
    finished_at: float | None
    last_write: float | None
    working: list[tuple[str, str | None]]
    outcome: dict
    agents: list[dict]
    kind: str
    stopped: str | None = None
    resumed_as: str | None = None
    relaunched_as: str | None = None

    @property
    def latest(self) -> Launch:
        return self.launches[-1]


@dataclass
class MergedPR:
    number: int
    title: str
    head: str
    base: str
    merged_at: float
    merge_commit: str
    issues: list[int]
    head_oid: str


@dataclass
class OpenPR:
    number: int
    title: str
    head: str
    base: str
    draft: bool
    ci: str
    merge_state: str
    issues: list[int]


@dataclass
class InstructionChange:
    """A PR merged into main since the session start that changed the agents' instructions."""

    number: int
    merged_at: float
    paths: list[str]


@dataclass
class MergeCheck:
    """merge-check's exit code, its verdict line and, when it flagged something or failed, its output as printed."""

    rc: int
    verdict: str
    detail: list[str]
    error: str | None = None
    skipped: bool = False


@dataclass
class Cost:
    """metrics' compact lines for this session since --since (None: nothing of it in the window), the stage window's
    total lines (--stage-since) and COST_EXTRAS' lines."""

    window: list[str] | None
    stage: list[str] | None = None
    stage_since: float | None = None
    extra: list[str] = field(default_factory=list)


@dataclass
class Worktree:
    path: Path
    branch: str  # "" when detached
    head: str

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def n(self) -> int | None:
        """The issue of a task worktree .claude/worktrees/<n>."""
        inside = self.path.parent.name == "worktrees" and self.path.parent.parent.name == ".claude"
        return int(self.name) if inside and self.name.isdigit() else None

    @property
    def release(self) -> str | None:
        """The k of a manager's .claude/worktrees/release-m<k> on release/m<k>."""
        m = RELEASE_WORKTREE.match(self.name)
        inside = self.path.parent.name == "worktrees" and self.path.parent.parent.name == ".claude"
        return m.group(1) if inside and m and self.branch == f"release/m{m.group(1)}" else None


@dataclass
class Housekeeping:
    """What the worktrees and the merged PRs give: blocks to run now, blocks a live session holds, waits and the
    issues still open whose work reached main since --since."""

    ready: list[tuple[str, list[str]]] = field(default_factory=list)  # (worktree label, commands)
    held: list[tuple[str, str, list[str]]] = field(default_factory=list)  # (label, the sessions, commands)
    waiting: list[str] = field(default_factory=list)
    issues: list[str] = field(default_factory=list)


@dataclass
class Wave:
    """What every section gets. A source's field is None when it was not read and a str (its error) when reading it
    failed; Wave(session, runs, since, now) alone renders every section."""

    session: Session
    runs: list[Run]
    since: float
    now: float
    base: str = MAIN
    plan: int | None = None
    title: str | None = None
    notes: str | None = None
    merged: list[MergedPR] | str | None = None  # every base, oldest first
    merged_cut: float | None = None  # read_merged's cut: gh's limit reached, a PR merged before it may be missing
    open_prs: list[OpenPR] | str | None = None  # into base and stacked on those
    merge_check: MergeCheck | None = None
    cost: Cost | str | None = None
    housekeeping: Housekeeping | str | None = None
    instructions: list[InstructionChange] | str | None = None  # merges into main since the session start
    behind: list[str] | str | None = None  # the main checkout's instruction files behind origin/main


class Sources:
    """Everything `wave --since` reads beyond the transcripts and the journals (tests replace it). Each is a read:
    gh's JSON, merge-check (its git fetch is its only write, to the shared git dir), `git worktree list`, the live
    Claude sessions, the verify history files and the main checkout."""

    def gh_json(self, *args: str) -> Any:
        return merge.gh_json(*args)

    def check(self, numbers: list[int], base: str) -> int:
        return merge.check(numbers, base=base)

    def worktree_list(self, main: Path) -> str:
        res = common.run(["git", "worktree", "list", "--porcelain"], timeout=60, cwd=main)
        if res.rc != 0 or res.timed_out:
            raise Failure(f"git worktree list failed: {res.out.strip()[-300:]}")
        return res.out

    def alive_in(self, path: Path) -> list:
        return sessions.alive_in(path)

    def history(self, main: Path) -> list[Path]:
        return metrics.history_paths(main)

    def main_checkout(self) -> Path:
        return metrics.main_checkout()

    def instructions_behind(self, main: Path) -> list[str]:
        """The instruction files origin/main changed since the main checkout's HEAD (no fetch: as fresh as the shared
        git dir's last fetch)."""
        res = common.run(["git", "diff", "--name-only", "HEAD...origin/main", "--", *INSTRUCTION_FILES,
                          *(d.rstrip("/") for d in INSTRUCTION_DIRS)], timeout=60, cwd=main)  # fmt: skip
        if res.rc != 0 or res.timed_out:
            raise Failure(f"git diff failed: {res.out.strip()[-300:]}")
        return instruction_paths(res.out.split())


# --- reading the transcript ---------------------------------------------------------------------------------------


def tag(body: str, name: str) -> str:
    """The text of <name>…</name> in a notification; a cut notification may lack the closing tag."""
    m = re.search(rf"<{name}>(.*?)(?:</{name}>|\Z)", body, re.S)
    return m.group(1).strip() if m else ""


def notices_in(text: str, t: float) -> list[Notice]:
    found = []
    for piece in text.split("<task-notification>")[1:]:
        body = piece.split("</task-notification>")[0]
        found.append(Notice(t, tag(body, "status"), tag(body, "summary"), tag(body, "result"),
                            tag(body, "output-file"), tag(body, "task-id"), tag(body, "tool-use-id")))  # fmt: skip
    return found


def as_args(value: object) -> dict | None:
    """The args as passed: a dict, or a JSON string of one (parsed); anything else is not args."""
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            return None
    return value if isinstance(value, dict) else None


def launch_of(block: dict, t: float) -> Launch:
    inp = block.get("input") if isinstance(block.get("input"), dict) else {}
    script = inp.get("scriptPath")
    name = inp.get("name") or (Path(str(script).replace("\\", "/")).stem if script else "")
    resume = inp.get("resumeFromRunId")
    return Launch(
        tool_use_id=str(block["id"]), time=t, name=str(name), script_path=str(script) if script else None,
        args=as_args(inp.get("args")), passed_args="args" in inp, resume_from=str(resume) if resume else None,
    )  # fmt: skip


def pair(launch: Launch, record: dict, block: dict, single: bool, folder: Path, sid: str) -> None:
    """The run id (and task id and run folder) from the tool_result of a Workflow call."""
    launch.paired = True
    tur = record.get("toolUseResult") if single and isinstance(record.get("toolUseResult"), dict) else {}
    run_id = tur.get("runId")
    if not run_id:
        m = RUN_ID.search(metrics.text_of(block.get("content")))
        run_id = m.group(1) if m else None
    if not run_id:
        return
    launch.run_id = str(run_id)
    launch.task_id = str(tur["taskId"]) if tur.get("taskId") else None
    if not launch.name:
        launch.name = str(tur.get("workflowName") or "inline script")
    given = Path(str(tur["transcriptDir"])) if tur.get("transcriptDir") else None
    launch.run_dir = given if given and given.is_dir() else folder / sid / "subagents" / "workflows" / launch.run_id


def read_session(path: Path, sid: str) -> Session:
    """One pass over a manager's transcript: its Workflow launches with their results and notifications, its API calls
    and title. Unknown records are passed over; broken ones are counted in Session.skipped."""
    s = Session(sid=sid, path=path, folder=path.parent)
    usage: dict[str, dict] = {}
    uses: dict[str, Launch] = {}
    all_ids: set[str] = set()
    notes: list[Notice] = []
    model = None
    with io.open(path, encoding="utf-8", errors="replace") as lines:
        for line in lines:
            if not line.strip():
                continue
            try:
                d = json.loads(line)
            except ValueError:
                s.skipped["not JSON"] += 1
                continue
            if not isinstance(d, dict):
                s.skipped["not JSON"] += 1
                continue
            kind = d.get("type")
            if kind == "custom-title" and d.get("customTitle"):
                s.title = str(d["customTitle"])
            t = metrics.stamp(d.get("timestamp"))
            if t is None:
                continue
            s.first = t if s.first is None else min(s.first, t)
            s.last = t if s.last is None else max(s.last, t)
            m = d.get("message") if isinstance(d.get("message"), dict) else {}
            if kind == "assistant":
                if m.get("model") != "<synthetic>":
                    model = m.get("model") or model
                    count_usage(usage, m, d, model)
                    cur = usage.get(m.get("id") or d.get("requestId") or d.get("uuid"))
                    s.last_ctx = sum(cur[f] for f in metrics.TOKEN_FIELDS) if cur else s.last_ctx
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id"):
                        all_ids.add(str(b["id"]))
                        if b.get("name") == "Workflow":
                            uses[str(b["id"])] = launch_of(b, t)
            elif kind == "user":
                content = m.get("content")
                if isinstance(content, list):
                    results = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"]
                    for b in results:
                        launch = uses.get(str(b.get("tool_use_id")))
                        if launch is not None and not launch.paired:
                            pair(launch, d, b, len(results) == 1, s.folder, sid)
                notes += notices_in(metrics.text_of(content), t)
            elif kind == "queue-operation" and d.get("operation") == "enqueue":
                notes += notices_in(str(d.get("content") or ""), t)
    s.calls = list(usage.values())
    s.launches = sorted(uses.values(), key=lambda x: x.time)
    for launch in s.launches:
        if not launch.paired:
            s.skipped["Workflow call without a result"] += 1
        elif launch.run_id is None:
            s.skipped["Workflow result without a runId"] += 1
    by_task = {x.task_id: x for x in s.launches if x.task_id}
    for note in notes:
        launch = uses.get(note.tool_use_id) or (by_task.get(note.task_id) if note.task_id else None)
        if launch is None:
            if note.tool_use_id not in all_ids and WORKFLOW_NOTE.search(note.summary):
                s.skipped["workflow notification for no known launch"] += 1
            continue
        if launch.notice is None or note.time < launch.notice.time:
            launch.notice = note  # the enqueue comes first; the user record repeats it later
    resolve_args(s.launches)
    return s


def count_usage(usage: dict[str, dict], m: dict, d: dict, model: str | None) -> None:
    """One assistant line's usage, deduplicated by message id with each field's maximum (metrics.read_agent's rule)."""
    u = m.get("usage") if isinstance(m.get("usage"), dict) else {}
    mid = m.get("id") or d.get("requestId") or d.get("uuid")
    cur = usage.get(mid)
    if cur is None:
        cur = usage[mid] = {**{f: 0 for f in metrics.TOKEN_FIELDS}, "cache_write_1h": 0, "model": model}
    for f in metrics.TOKEN_FIELDS:
        cur[f] = max(cur[f], int(u.get(f) or 0))
    cache = u.get("cache_creation")
    if isinstance(cache, dict):
        cur["cache_write_1h"] = max(cur["cache_write_1h"], int(cache.get("ephemeral_1h_input_tokens") or 0))


def resolve_args(launches: list[Launch]) -> None:
    """A resume that passed no args runs with the args of the run it resumes (following a chain of resumes)."""
    by_run: dict[str, Launch] = {}
    for launch in launches:  # oldest first
        if launch.args is None and launch.resume_from and launch.resume_from in by_run:
            launch.args = by_run[launch.resume_from].args
            launch.passed_args = False
        if launch.run_id:
            by_run[launch.run_id] = launch


# --- runs ---------------------------------------------------------------------------------------------------------


def issue_of(args: dict | None) -> int | None:
    n = (args or {}).get("n")
    if isinstance(n, bool):
        return None
    if isinstance(n, int):
        return n
    if isinstance(n, str) and n.strip().isdigit():
        return int(n.strip())
    return None


def answered(agents: list[dict], role: str) -> list[dict]:
    return [a["result"] for a in agents if a["role"] == role and a["result"] is not None]


def outcome_of(agents: list[dict]) -> dict:
    """The result that ends a run: the publisher's, else the pr-rebase fix's, else the rebase's."""
    for role in ("publisher", "pr-rebase fix", "pr-rebase"):
        found = answered(agents, role)
        if found:
            return found[-1]
    return {}


def serious(result: dict) -> int:
    findings = result.get("findings") or []
    return sum(1 for f in findings if isinstance(f, dict) and re.search(r"blocker|major", str(f.get("severity")), re.I))


def journal_done(info: dict) -> bool:
    """Whether the journal reached the script's end (the module docstring's rule per workflow)."""
    agents = info["agents"]
    started = {a["role"] for a in agents}
    if info["kind"].startswith("issue-task"):
        if answered(agents, "publisher"):
            return True
        impl = answered(agents, "implementer")
        return bool(impl) and impl[-1].get("verify_green") is False and "publisher" not in started
    if info["kind"] == "pr-rebase":
        if answered(agents, "pr-rebase fix"):
            return True
        reb = answered(agents, "pr-rebase")
        if not reb:
            return False
        if reb[-1].get("verify_green") is False or reb[-1].get("published") is False:
            return True
        if not info["finished"] or "pr-rebase fix" in started:
            return False
        reviews = [r for role in REVIEW_ROLES for r in answered(agents, role)]
        refuted = sum(1 for r in answered(agents, "skeptic") if r.get("refuted") is True)
        return bool(reviews) and sum(serious(r) for r in reviews) <= refuted
    return bool(info["finished"])


def stopped_reason(info: dict, outcome: dict, notice: Notice | None) -> str | None:
    """Why a finished run must be relaunched fresh (never resumed), or None. info: metrics.read_run's result."""
    agents = info["agents"]
    if any(r.get("stopped_by_mutants") is True for r in answered(agents, "publisher")):
        return "mutants exited 2: nothing published"
    impl = answered(agents, "implementer")
    if (info["kind"].startswith("issue-task") and impl and impl[-1].get("verify_green") is False
            and "publisher" not in {a["role"] for a in agents}):  # fmt: skip
        return "verify red after the implementer: nothing reviewed or published"
    reb = answered(agents, "pr-rebase")
    if (reb and (reb[-1].get("verify_green") is False or reb[-1].get("published") is False)
            and not answered(agents, "pr-rebase fix")):  # fmt: skip
        return "rebase red or unpublished: nothing reviewed"
    if outcome.get("published") is False:
        return "published false"
    m = STOPPED.search(notice.result_text) if notice else None
    if m:
        return "stopped: " + m.group(1).replace('\\"', '"')[:200]
    return None


def unanswered(journal: list[dict]) -> list[tuple[str, str | None]]:
    """The agents working now: the last attempt of every started key that has no result."""
    results = {e["key"] for e in journal if e.get("type") == "result" and "key" in e}
    last: dict[str, dict] = {}
    for e in journal:
        if e.get("type") == "started" and "key" in e:
            last[e["key"]] = e
    return [(str(e.get("label", "")), e.get("phase")) for k, e in last.items() if k not in results]


def last_write(run_dir: Path | None) -> float | None:
    if not run_dir or not run_dir.is_dir():
        return None
    times = [p.stat().st_mtime for p in [run_dir / "journal.jsonl", *run_dir.glob("agent-*.jsonl")] if p.is_file()]
    return max(times) if times else None


def build_runs(s: Session) -> list[Run]:
    """The session's runs, one per run id, oldest launch first."""
    groups: dict[str, list[Launch]] = {}
    for launch in s.launches:
        if launch.run_id:
            groups.setdefault(launch.run_id, []).append(launch)
    resumed_as = {
        x.resume_from: x.run_id for x in s.launches if x.resume_from and x.run_id and x.resume_from != x.run_id
    }
    runs = []
    for run_id, launches in groups.items():
        latest = launches[-1]
        folder = latest.run_dir
        if folder and folder.is_dir():
            info = metrics.read_run(folder, {}, {}, s.sid[:8])
            journal = metrics.read_json_lines(folder / "journal.jsonl")
        else:
            info, journal = {"agents": [], "kind": "other", "issue": None, "finished": False}, []
        outcome = outcome_of(info["agents"])
        written = last_write(folder)
        if latest.notice:
            status, finished, finished_at = latest.notice.status or "finished", True, latest.notice.time
        elif journal_done(info):
            status, finished, finished_at = "finished (no notification)", True, written
        else:
            status, finished, finished_at = "running", False, None
        issue = issue_of(latest.args)
        if issue is None and info["kind"] != "other":
            issue = info["issue"]
        run = Run(
            run_id=run_id, launches=launches, name=latest.name or "inline script", issue=issue, args=latest.args,
            status=status, finished=finished, finished_at=finished_at, last_write=written,
            working=unanswered(journal), outcome=outcome, agents=info["agents"], kind=info["kind"],
            resumed_as=resumed_as.get(run_id),
        )  # fmt: skip
        if finished:
            run.stopped = stopped_reason(info, outcome, latest.notice)
        runs.append(run)
    for run in runs:
        if not run.resumed_as:
            run.relaunched_as = relaunched_as(s.launches, run)
    return runs


def relaunched_as(launches: list[Launch], run: Run) -> str | None:
    """The run id of the newest later launch of the same issue and workflow under another run id (a fresh relaunch,
    or a resume of another run of it): that launch took this run's place."""
    if run.issue is None:
        return None
    last = max(i for i, x in enumerate(launches) if any(x is y for y in run.launches))
    later = [
        x.run_id
        for x in launches[last + 1 :]
        if x.run_id and x.run_id != run.run_id and x.name == run.name and issue_of(x.args) == run.issue
    ]
    return later[-1] if later else None


def latest_launch(s: Session, n: int, workflow: str | None = None) -> Launch:
    """The newest launch whose args.n is n (and whose workflow is `workflow`, when given) that started a run; a launch
    with no run id (the tool rejected its input) only when no launch of n ran."""
    of_n = [x for x in s.launches if issue_of(x.args) == n and (workflow is None or x.name == workflow)]
    found = [x for x in of_n if x.run_id] or of_n
    if found:
        return found[-1]
    launched = sorted({i for x in s.launches if (i := issue_of(x.args)) is not None})
    named = f" of the workflow {workflow}" if workflow else ""
    raise Failure(
        f"wave: no Workflow launch{named} of issue #{n} in session {s.sid} ({s.path}); launched: "
        + (", ".join(f"#{i}" for i in launched) or "none with args.n")
    )


# --- GitHub -------------------------------------------------------------------------------------------------------


def issue_from_branch(branch: str) -> int | None:
    m = TASK_BRANCH.match(branch)
    return int(m.group(1)) if m else None


def issues_of(d: dict) -> list[int]:
    """A PR's closing issues, else the issue of its task branch (a PR into a release branch links none)."""
    refs = d.get("closingIssuesReferences") if isinstance(d.get("closingIssuesReferences"), list) else []
    found = [int(r["number"]) for r in refs if isinstance(r, dict) and isinstance(r.get("number"), int)]
    if found:
        return found
    n = issue_from_branch(str(d.get("headRefName") or ""))
    return [n] if n is not None else []


def rows_of(data: Any, what: str) -> list[dict]:
    if not isinstance(data, list):
        raise Failure(f"gh pr list {what}: not a list but {type(data).__name__}")
    return [d for d in data if isinstance(d, dict) and isinstance(d.get("number"), int)]


def read_merged(gh: Callable[..., Any]) -> tuple[list[MergedPR], float | None]:
    """The MERGED_LIMIT most recently updated merged PRs into any base, oldest merge first, and the cut: the oldest
    update among them when gh returned its whole limit (a PR merged before it may be missing; merging updates a PR, so
    every PR merged after it is listed), else None."""
    data = gh("pr", "list", "--state", "merged", "--search", MERGED_SEARCH, "--limit", str(MERGED_LIMIT), "--json",
              MERGED_FIELDS)  # fmt: skip
    rows = rows_of(data, "--state merged")
    cut = None
    if len(data) >= MERGED_LIMIT:
        updates = [t for t in (metrics.stamp(d.get("updatedAt")) for d in rows) if t is not None]
        cut = min(updates) if updates else None
    found = []
    for d in rows:
        t = metrics.stamp(d.get("mergedAt"))
        if t is None:
            continue
        commit = d.get("mergeCommit") if isinstance(d.get("mergeCommit"), dict) else {}
        found.append(MergedPR(d["number"], str(d.get("title") or ""), str(d.get("headRefName") or ""),
                              str(d.get("baseRefName") or ""), t, str(commit.get("oid") or ""), issues_of(d),
                              str(d.get("headRefOid") or "")))  # fmt: skip
    return sorted(found, key=lambda p: (p.merged_at, p.number)), cut


def ci_cell(rollup: object) -> str:
    """A PR's statusCheckRollup in one word and the checks behind it: red (any failed) beats pending, else green;
    none when no check reported."""
    checks = [c for c in rollup if isinstance(c, dict)] if isinstance(rollup, list) else []
    if not checks:
        return "none"
    red: list[str] = []
    pending: list[str] = []
    for c in checks:
        name = str(c.get("name") or c.get("context") or "?")
        if c.get("__typename") == "StatusContext" or ("state" in c and "status" not in c):
            state = str(c.get("state") or "").upper()
        elif str(c.get("status") or "").upper() != "COMPLETED":
            state = "PENDING"
        else:
            state = str(c.get("conclusion") or "").upper()
        if state in CI_PENDING:
            pending.append(name)
        elif state not in CI_PASS:
            red.append(name)
    if red:
        return "red: " + ", ".join(dict.fromkeys(red))
    if pending:
        return "pending: " + ", ".join(dict.fromkeys(pending))
    return "green"


def read_open(gh: Callable[..., Any], base: str) -> list[OpenPR]:
    """The open PRs into base, and those stacked on one of them (they land in base too), by number."""
    prs = [
        OpenPR(d["number"], str(d.get("title") or ""), str(d.get("headRefName") or ""), str(d.get("baseRefName") or ""),
               bool(d.get("isDraft")), ci_cell(d.get("statusCheckRollup")), str(d.get("mergeStateStatus") or ""),
               issues_of(d))
        for d in rows_of(gh("pr", "list", "--state", "open", "--limit", "200", "--json", OPEN_FIELDS), "--state open")
    ]  # fmt: skip
    lands, grew = {base}, True
    while grew:
        grew = False
        for p in prs:
            if p.base in lands and p.head not in lands:
                lands.add(p.head)
                grew = True
    return sorted((p for p in prs if p.base in lands), key=lambda p: p.number)


def instruction_paths(paths: Iterable[str]) -> list[str]:
    """The paths among these that are the agents' instructions (INSTRUCTION_FILES at the root, files under
    INSTRUCTION_DIRS), in their order."""
    return [p for p in paths
            if p in INSTRUCTION_FILES or (p.startswith(INSTRUCTION_DIRS) and p not in INSTRUCTION_DIRS)]  # fmt: skip


def files_of(d: object) -> list[str]:
    files = d.get("files") if isinstance(d, dict) else None
    return [str(f["path"]) for f in files or [] if isinstance(f, dict) and f.get("path")]


def read_instruction_changes(gh: Callable[..., Any], merged: list[MergedPR] | str | None,
                             start: float | None) -> list[InstructionChange]:  # fmt: skip
    """The PRs merged into main at or after start whose files include an instruction file, oldest first. The
    candidates are read_merged's PRs into main since start (none: no gh call); one `gh pr list --json files` reads
    their files (merged:>= is date-only, so a day early, and filtered here), and `gh pr view <n> --json files` each one
    the search has not caught up with yet. gh lists at most 100 files of a PR."""
    if merged is None or start is None:
        return []
    if isinstance(merged, str):
        raise Failure(f"merged PRs: {merged}")
    candidates = [p for p in merged if p.base == MAIN and p.merged_at >= start]
    if not candidates:
        return []
    day = time.strftime("%Y-%m-%d", time.gmtime(start - 86400))
    data = gh("pr", "list", "--state", "merged", "--base", MAIN, "--search", f"merged:>={day} {MERGED_SEARCH}",
              "--limit", str(FILES_LIMIT), "--json", FILES_FIELDS)  # fmt: skip
    files = {d["number"]: files_of(d) for d in rows_of(data, "--json files")}
    found = []
    for p in candidates:
        paths = files[p.number] if p.number in files else files_of(gh("pr", "view", str(p.number), "--json", "files"))
        chosen = instruction_paths(paths)
        if chosen:
            found.append(InstructionChange(p.number, p.merged_at, chosen))
    return found


# --- merge-check --------------------------------------------------------------------------------------------------

STATUS_PREFIX = re.compile(r"^  (?:ok|warn|FAIL|skip) +")


def capture_merge_check(check: Callable[[list[int], str], int], base: str) -> MergeCheck:
    """merge-check --base B with its printed lines captured (merge.check prints through `say`; its git and gh calls
    capture their own output). The verdict: its last 'merge-check:' line, else its last line without the status
    prefix. The detail: everything but its title and its 'ok' progress lines, kept only when it flagged or failed."""
    buf = io.StringIO()
    error = None
    try:
        with redirect_stdout(buf):
            rc = int(check([], base))
    except Exception as exc:  # a Failure (gh missing, a PR head not on origin) or a bug: the body is still written
        rc, error = 1, str(exc).strip() or type(exc).__name__
        warn(f"wave: merge-check failed: {error}")
    lines = buf.getvalue().rstrip().splitlines()
    if lines and lines[0].strip() == "merge-check":
        lines = lines[1:]
    verdict = next((line.strip() for line in reversed(lines) if line.startswith("merge-check:")), "")
    if not verdict:
        last = next((line for line in reversed(lines) if line.strip()), "")
        verdict = STATUS_PREFIX.sub("", last).strip() or "(merge-check printed nothing)"
    if error is not None:
        verdict = f"merge-check failed: {error}"
    detail = [line for line in lines if not line.startswith("  ok    ")]
    while detail and not detail[0].strip():
        detail.pop(0)
    return MergeCheck(rc, verdict, detail if rc != 0 or error is not None else [], error)


# --- cost ---------------------------------------------------------------------------------------------------------


def metrics_window(dirs: list[Path], sid: str, since: float, now: float, history: list[Path]) -> tuple[dict, dict,
                                                                                                         list[str]]:  # fmt: skip
    """What `metrics --since <since> --session <sid> --compact` computes, in memory (no metrics file is written):
    (collect's data, build's JSON record, build's compact lines)."""
    data = metrics.collect(dirs, {sid: None}, since, now)
    _, record, compact = metrics.build(data, metrics.read_history(history, since, now), None, since, now)
    return data, record, compact


def nothing_in(data: dict) -> bool:
    """No API call of the session's own, no hand-run subagent and no counted run in the window (collect lists a named
    session even then, with zero lines)."""
    own = any(s["manager"] and s["manager"]["api_calls"] for s in data["sessions"])
    return not own and not any(s["hand"] for s in data["sessions"]) and not any(r["counted"] for r in data["runs"])


def cost_of(dirs: list[Path], sid: str, since: float, stage_since: float | None, now: float,
            history: list[Path]) -> Cost:  # fmt: skip
    data, record, compact = metrics_window(dirs, sid, since, now, history)
    cost = Cost(None if nothing_in(data) else compact)
    if cost.window is not None:
        cost.extra = [line for extra in COST_EXTRAS for line in extra(record)]
    if stage_since is not None:
        stage = metrics_window(dirs, sid, stage_since, now, history)[2]
        cost.stage = [line for line in stage if line.startswith(STAGE_LINES)] or stage
        cost.stage_since = stage_since
    return cost


# --- housekeeping -------------------------------------------------------------------------------------------------


def parse_worktrees(text: str) -> list[Worktree]:
    """`git worktree list --porcelain`: blocks of 'worktree <path>', 'HEAD <sha>', 'branch refs/heads/<b>' or
    'detached', separated by blank lines."""
    found = []
    for chunk in re.split(r"\n\s*\n", text.replace("\r\n", "\n")):
        fields = dict(line.split(" ", 1) if " " in line else (line, "") for line in chunk.strip().splitlines())
        if fields.get("worktree"):
            branch = fields.get("branch", "").removeprefix("refs/heads/")
            found.append(Worktree(Path(fields["worktree"]), branch, fields.get("HEAD", "")))
    return found


def landing(pr: MergedPR, by_head: dict[str, list[MergedPR]], seen: tuple[int, ...] = ()) -> tuple[MergedPR | None,
                                                                                                   str]:  # fmt: skip
    """The PR that took pr's work into main (pr itself when its base is main) and MAIN, else None and the branch the
    work waits in: a release branch or a parent task branch whose own PR into main has not merged since."""
    if pr.base == MAIN:
        return pr, MAIN
    later = [q for q in by_head.get(pr.base, []) if q.merged_at >= pr.merged_at and q.number not in seen]
    if not later:
        return None, pr.base
    return landing(min(later, key=lambda q: q.merged_at), by_head, (*seen, pr.number))


def same_path(a: object, b: Path) -> bool:
    return str(a).replace("\\", "/").rstrip("/").lower() == b.as_posix().rstrip("/").lower()


def running_in(wt: Worktree, runs: list[Run]) -> Run | None:
    """A running run of this session in the worktree: its args.wt is that folder, or args.n its issue."""
    for r in runs:
        if not r.finished and ((wt.n is not None and issue_of(r.args) == wt.n) or same_path((r.args or {}).get("wt"),
                                                                                             wt.path)):  # fmt: skip
            return r
    return None


def cd_main(main: PurePath) -> str:
    """The PowerShell prefix that enters the main checkout. Built from the path's text: Python 3.11 builds a
    PureWindowsPath from another path's parts, so a POSIX-flavoured "D:/prime-game" (the Linux CI) became the
    drive-relative "D:prime-game"; 3.12 and later read the text."""
    return f"cd {PureWindowsPath(str(main))}; "


def housekeeping_of(worktrees: list[Worktree], merged: list[MergedPR], runs: list[Run], alive_in: Callable[[Path],
                    list], main: Path, open_issues: set[int], since: float, now: float) -> Housekeeping:  # fmt: skip
    """Per task worktree (.claude/worktrees/<n>) and manager release worktree (release-m<k>) whose branch has a
    merged PR: a block when its work is on main, no run of this session works there, its HEAD is the merged head and
    no live Claude session sits there; held when one does; else a wait. Worktrees with no merged PR are left out."""
    cd = cd_main(main)
    by_head: dict[str, list[MergedPR]] = {}
    for p in merged:
        by_head.setdefault(p.head, []).append(p)
    h = Housekeeping()
    for wt in worktrees:
        if (wt.n is None and wt.release is None) or not wt.branch or wt.branch not in by_head:
            continue
        pr = by_head[wt.branch][-1]  # the newest merged PR of the branch
        label = f"worktree {wt.name}"
        top, waits = landing(pr, by_head)
        run_there = running_in(wt, runs)
        if top is None:
            h.waiting.append(f"{label}: PR #{pr.number} merged into {pr.base}; after {waits} reaches main.")
        elif run_there is not None:
            h.waiting.append(f"{label}: run {run_there.run_id} still running there.")
        elif wt.head != pr.head_oid:
            # Ahead (a commit after the merge) or behind (the remote branch got a commit): either way, look first.
            h.waiting.append(f"{label}: HEAD {wt.head[:10]} is not PR #{pr.number}'s merged head {pr.head_oid[:10]}: "
                             "check before removing.")  # fmt: skip
        else:
            if wt.n is not None:
                commands = [f"{cd}tools\\run.cmd worktree-done {wt.n}"]
            else:
                # -D, not -d (as start.py's own branch delete): -d compares with the main checkout's local HEAD,
                # often behind origin/main, and refuses; landing() and the HEAD check above proved the work is on main.
                commands = [f"{cd}git worktree remove .claude/worktrees/{wt.name}", f"{cd}git branch -D {wt.branch}"]
            live = alive_in(wt.path)
            if live:
                who = ", ".join(s.describe(now) if hasattr(s, "describe") else str(s) for s in live)
                h.held.append((label, who, commands))
            else:
                h.ready.append((label, commands))
    issues: dict[int, str] = {}
    for p in merged:
        top, _ = landing(p, by_head)
        if top is not None and top.merged_at >= since:
            for n in p.issues:
                if n in open_issues and n not in issues:
                    issues[n] = f"#{n} (PR #{p.number}" + (f" via {p.base})" if p.base != MAIN else ")")
    h.issues = [issues[n] for n in sorted(issues)]
    return h


def read_open_issues(gh: Callable[..., Any]) -> set[int]:
    data = gh("issue", "list", "--state", "open", "--limit", "1000", "--json", "number")
    if not isinstance(data, list):
        raise Failure(f"gh issue list: not a list but {type(data).__name__}")
    return {d["number"] for d in data if isinstance(d, dict) and isinstance(d.get("number"), int)}


# --- sections -----------------------------------------------------------------------------------------------------


def cell(value: object) -> str:
    """A table cell: a '|' or a line break in free text would break the row."""
    return re.sub(r"\s*[\r\n]+\s*", " ", str(value)).replace("|", "\\|")


def table(head: list[str], rows: list[list[object]]) -> str:
    return metrics.table(head, [[cell(c) for c in r] for r in rows])


def fence(text: str, lang: str = "") -> list[str]:
    """A code fence longer than the longest run of backticks inside it."""
    longest = max((len(m) for m in re.findall(r"`+", text)), default=0)
    marks = "`" * max(3, longest + 1)
    return [marks + lang, text, marks]


def issue_cell(r: Run) -> str:
    return f"#{r.issue}" if r.issue is not None else "—"


def pr_cell(r: Run) -> str:
    o = r.outcome
    if o.get("pr_url"):
        return str(o["pr_url"])
    if o.get("pr_number"):
        return f"#{o['pr_number']}"
    pr = (r.args or {}).get("pr")
    return f"#{pr}" if pr not in (None, "") else ""


def yes_no(value: object, yes: str = "yes", no: str = "no") -> str:
    return {True: yes, False: no}.get(value, "") if isinstance(value, bool) else ""


def count(value: object) -> str:
    return str(len(value)) if isinstance(value, list) else ""


def status_cell(r: Run) -> str:
    text = r.status
    notice = r.latest.notice
    if notice and r.status not in ("completed", "finished") and notice.summary:
        text += f": {notice.summary[:150]}"
    if r.resumed_as:
        text += f" (resumed as {r.resumed_as})"
    if r.relaunched_as:
        text += f" (relaunched as {r.relaunched_as})"
    return text


def human_steps(r: Run) -> list[object]:
    """Every agent's human_steps in journal order (a rebase's and a fix's both count), each once."""
    seen, steps = set(), []
    for a in r.agents:
        for step in (a["result"] or {}).get("human_steps") or []:
            key = json.dumps(step, sort_keys=True, ensure_ascii=False)
            if key not in seen:
                seen.add(key)
                steps.append(step)
    return steps


def step_lines(step: object) -> list[str]:
    if isinstance(step, dict) and ("why" in step or "command" in step):
        lines = [f"- {step.get('why') or '(no why given)'}"]
        command = str(step.get("command") or "").rstrip("\r\n")
        return [*lines, "", *fence(command, "powershell"), ""] if command.strip() else [*lines, ""]
    if isinstance(step, str):
        return [f"- {step}", ""]
    return ["", *fence(json.dumps(step, indent=1, ensure_ascii=False), "json"), ""]


def header_section(w: Wave) -> list[str]:
    title = w.title or f"Wave report since {metrics.iso(w.since)}"
    plan = f"Plan #{w.plan}; " if w.plan is not None else ""
    return [f"# {cell(title)}", "",
            f"{plan}base {w.base}; since {metrics.iso(w.since)}; written {metrics.iso(w.now)} from session "
            f"{w.session.sid[:8]}.", ""]  # fmt: skip


def notes_section(w: Wave) -> list[str]:
    """The manager's own judgement (--notes), as written: decisions, batched questions, the order from here."""
    return [w.notes.strip("\n"), ""] if w.notes and w.notes.strip() else []


def source_state(value: object) -> list[str] | None:
    """The body of a section whose source was not read or failed, else None."""
    if value is None:
        return ["Not read.", ""]
    if isinstance(value, str):
        return [f"Unavailable: {cell(value)}", ""]
    return None


def issues_cell(issues: list[int]) -> str:
    return ", ".join(f"#{n}" for n in issues) or "—"


def merged_section(w: Wave) -> list[str]:
    md = [f"## Merged into {w.base} since {metrics.iso(w.since)}", ""]
    state = source_state(w.merged)
    if state is not None or not isinstance(w.merged, list):
        return md + (state or [])
    rows = [[f"#{p.number}", p.title, p.head, metrics.iso(p.merged_at), p.merge_commit[:10], issues_cell(p.issues)]
            for p in w.merged if p.base == w.base and p.merged_at >= w.since]  # fmt: skip
    md += [table(["PR", "title", "branch", "merged", "merge commit", "issues"], rows), ""] if rows else ["None.", ""]
    if w.merged_cut is not None and w.merged_cut > w.since:
        md += [f"gh returned its limit of {MERGED_LIMIT} merged PRs, the most recently updated, back to an update at "
               f"{metrics.iso(w.merged_cut)}: a PR merged before then may be missing here and in housekeeping.",
               ""]  # fmt: skip
    return md


def open_prs_section(w: Wave) -> list[str]:
    md = ["## Open PRs", ""]
    state = source_state(w.open_prs)
    if state is not None or not isinstance(w.open_prs, list):
        return md + (state or [])
    if not w.open_prs:
        return [*md, "None.", ""]
    rows = [[f"#{p.number}", p.title, issues_cell(p.issues), p.base, yes_no(p.draft), p.ci, p.merge_state]
            for p in w.open_prs]  # fmt: skip
    return [*md, table(["PR", "title", "issues", "base", "draft", "CI", "merge state"], rows), "",
            f"Into {w.base}, and stacked on one of those.", ""]  # fmt: skip


def merge_section(w: Wave) -> list[str]:
    md = ["## Merge safety", ""]
    m = w.merge_check
    if m is None:
        return [*md, "Not read.", ""]
    if m.skipped:
        return [*md, "Skipped (--no-merge-check).", ""]
    md += [f"`merge-check --base {w.base}`: exit {m.rc}.", ""]
    if m.error is not None:
        return [*md, m.verdict, "", *([*m.detail, ""] if m.detail else [])]
    return [*md, *(m.detail or [m.verdict]), ""]


def cost_section(w: Wave) -> list[str]:
    md = ["## Cost", ""]
    state = source_state(w.cost)
    if state is not None or not isinstance(w.cost, Cost):
        return md + (state or [])
    c, sid8 = w.cost, w.session.sid[:8]
    block: list[str] = []
    if c.window is None:
        md += [f"None. Session {sid8} made no API call and counted no run since {metrics.iso(w.since)}.", ""]
    else:
        md += [f"`metrics --since {metrics.iso(w.since)} --session {sid8} --compact`:", ""]
        block += [*c.window, *c.extra]
    if c.stage is not None:
        block += [*([""] if block else []), f"stage since {metrics.iso(c.stage_since)}:", *c.stage]
    return md + (["```text", *block, "```", ""] if block else [])


def powershell(commands: list[str]) -> list[str]:
    """One fenced PowerShell block per command (root CLAUDE.md: commands for a human)."""
    return [line for c in commands for line in [*fence(c, "powershell"), ""]]


def names_of(labels: list[str]) -> str:
    """'worktree 305' or 'worktrees 305, 251 and release-m4'."""
    names = [label.removeprefix("worktree ") for label in labels]
    if len(names) == 1:
        return f"worktree {names[0]}"
    return f"worktrees {', '.join(names[:-1])} and {names[-1]}"


def for_you(h: Housekeeping) -> str:
    """The section's first line, for the manager to lift into chat: only what needs the engineer, the worktrees a live
    session holds, else nothing. The ready blocks are the manager's own steps (the trust ADR: it runs worktree-done
    itself when no live session sits there), so they stay out of this line."""
    if not h.held:
        return "For you: nothing."
    who = "; ".join(sessions_ for _, sessions_, _ in h.held)
    plural = len(h.held) > 1
    return (f"For you: close the Claude session{'s' if plural else ''} in {names_of([lb for lb, _, _ in h.held])} "
            f"({who}), then run {'their blocks' if plural else 'its block'} below.")  # fmt: skip


def housekeeping_section(w: Wave) -> list[str]:
    md = ["## Housekeeping", ""]
    state = source_state(w.housekeeping)
    if state is not None or not isinstance(w.housekeeping, Housekeeping):
        return md + (state or [])
    h = w.housekeeping
    md += [for_you(h), ""]
    if not (h.ready or h.held or h.waiting or h.issues):
        return [*md, "None.", ""]
    if h.ready:
        md += [f"Ready to remove: {', '.join(label for label, _ in h.ready)} (the work is on main; no run of this "
               "session and no live Claude session there; HEAD at the merged head). The manager runs each block itself "
               "(orchestrate-stage §8):", ""]  # fmt: skip
        md += [line for _, commands in h.ready for line in powershell(commands)]
    if h.held:
        md += ["Held by a live Claude session (worktree-done refuses while one sits there):", ""]
        for label, who, commands in h.held:
            md += [f"- {label}: {who}; close it, then:", "", *powershell(commands)]
    if h.waiting:
        md += ["Not yet:", "", *(f"- {line}" for line in h.waiting), ""]
    issues = ", ".join(h.issues) if h.issues else "none"
    md += [f"Issues still open whose PR reached main since {metrics.iso(w.since)} (close each once its acceptance "
           f"criteria are met): {issues}.", ""]  # fmt: skip
    return md


def finished_since(w: Wave) -> list[Run]:
    return [r for r in w.runs if r.finished and (r.finished_at is None or r.finished_at >= w.since)]


def finished_section(w: Wave) -> list[str]:
    done = finished_since(w)
    shown = {r.run_id for r in done}
    before = sum(1 for r in w.runs if r.finished and r.run_id not in shown)
    md = [f"## Finished runs since {metrics.iso(w.since)}", ""]
    if done:
        rows = [
            [issue_cell(r), r.name, r.run_id, status_cell(r), pr_cell(r),
             yes_no(r.outcome.get("ci_green"), "green", "red"), yes_no(r.outcome.get("published")),
             count(r.outcome.get("not_fixed")), count(r.outcome.get("needs_engineer")),
             f"{RELAUNCH}: {r.stopped}" if r.stopped else ""]
            for r in done
        ]  # fmt: skip
        head = ["issue", "workflow", "run", "status", "PR", "CI", "published", "not fixed", "needs engineer", "flag"]
        md += [table(head, rows), ""]
    else:
        md += ["None.", ""]
    for r in done:
        steps = human_steps(r)
        if steps:
            md += [f"**{issue_cell(r)} human steps** ({r.run_id})", ""]
            for step in steps:
                md += step_lines(step)
    if before:
        md += [f"{before} run{'s' if before != 1 else ''} finished before {metrics.iso(w.since)}, left out.", ""]
    return md


def minutes(seconds: float | None) -> str:
    return "" if seconds is None else f"{max(0.0, seconds) / 60:.0f}"


def running_section(w: Wave) -> list[str]:
    running = [r for r in w.runs if not r.finished]
    md = ["## Running", ""]
    if not running:
        return [*md, "None.", ""]
    rows = []
    for r in running:
        a = r.args or {}
        now = "; ".join(f"{label} ({phase})" if phase else label for label, phase in r.working) or "between agents"
        rows.append([issue_cell(r), r.name, a.get("title") or "", a.get("wt") or "", a.get("branch") or "",
                     a.get("base") or ("main" if r.args else ""), r.run_id, now, minutes(w.now - r.latest.time),
                     minutes(w.now - r.last_write) if r.last_write else ""])  # fmt: skip
    head = ["issue", "workflow", "title", "worktree", "branch", "base", "run", "agent now", "min since launch",
            "min since last line"]  # fmt: skip
    return [*md, table(head, rows), "",
            "\"min since last line\": since the newest write to the run's journal or agent transcripts; a run whose "
            "session died never finishes here, so a large value means stale.", ""]  # fmt: skip


def launching_session(r: Run, s: Session) -> str | None:
    """The session whose folder holds the run (<folder>/<sid>/subagents/workflows/<runId>), when it is not this one."""
    d = r.latest.run_dir
    if d and d.parent.name == "workflows" and d.parent.parent.name == "subagents" and d.parents[2].name != s.sid:
        return d.parents[2].name
    return None


def handover_block(r: Run, s: Session) -> list[str]:
    title = f' "{s.title}"' if s.title else ""
    head = f"<details><summary>{issue_cell(r)} {r.name} args ({r.run_id}; session {s.sid}{title})</summary>"
    if r.args is None:
        resumed = r.latest.resume_from
        if resumed and not any(x.run_id == resumed and not x.resume_from for x in s.launches):
            old = launching_session(r, s) or "<the session that launched it>"
            n = r.issue if r.issue is not None else "<n>"
            return [
                f"{issue_cell(r)} {r.name} ({r.run_id}): a resume of {resumed} with no args of its own, which "
                f"another session launched; its args: `tools\\run.cmd wave --args {n} --session {old}`.",
                "",
            ]
        return [f"{issue_cell(r)} {r.name} ({r.run_id}): no args were passed.", ""]
    return [head, "", *fence(json.dumps(r.args, indent=1, ensure_ascii=False), "json"), "</details>", ""]


def handover_chunks(w: Wave) -> list[list[str]]:
    """One block per running run, then one per finished run that needs a resume or a fresh relaunch (the first of
    those under its heading); the unit a split moves as a whole."""
    chunks = [handover_block(r, w.session) for r in w.runs if not r.finished]
    again = [
        r
        for r in finished_since(w)
        if (r.stopped or r.status in ("failed", "killed")) and not r.resumed_as and not r.relaunched_as
    ]
    for i, r in enumerate(again):
        head = ["### Finished runs that need a resume or a fresh relaunch", ""] if i == 0 else []
        chunks.append([*head, *handover_block(r, w.session)])
    return chunks


def handover_section(w: Wave) -> list[str]:
    chunks = handover_chunks(w)
    return ["## Handover data", "", *(line for chunk in chunks for line in chunk), *([] if chunks else
                                                                                       ["No run is running.", ""])]  # fmt: skip


def mean_usd(calls: list[dict]) -> float:
    return sum(sum(metrics.usd_of(c).values()) for c in calls) / len(calls) if calls else 0.0


def plural(n: int, one: str, many: str) -> str:
    return one if n == 1 else many


def changes_text(changes: list[InstructionChange]) -> str:
    return ", ".join(f"#{c.number} ({', '.join(c.paths)})" for c in changes)


def run_name(r: Run) -> str:
    return issue_cell(r) if r.issue is not None else r.run_id


def runs_text(runs: list[Run], now: float) -> str:
    """'#466 implement:#466, 3 min since its last line; ...'."""
    shown = []
    for r in runs:
        agent = ", ".join(label for label, _ in r.working) or "between agents"
        line = f"{minutes(now - r.last_write)} min since its last line" if r.last_write else "no line yet"
        shown.append(f"{run_name(r)} {agent}, {line}")
    return "; ".join(shown)


def is_stale(r: Run, now: float) -> bool:
    """A running run with no line for over STALE_MINUTES: its session may have died (no notification ever comes)."""
    return r.last_write is not None and now - r.last_write > STALE_MINUTES * 60


def in_flight_text(runs: list[Run], now: float) -> str:
    """'2 runs in flight (#466 implement:#466, 3 min since its last line; ...): stop each (...), then post the
    handover; the new session relaunches them fresh'."""
    pushing = [r for r in runs if any(metrics.role_of(label) in PUSHING_ROLES for label, _ in r.working)]
    wait = ""
    if pushing:
        wait = f" ({', '.join(run_name(r) for r in pushing)} only once its publish, rebase or fix agent ends)"
    n = len(runs)
    return (f"{n} {plural(n, 'run', 'runs')} in flight ({runs_text(runs, now)}): stop {plural(n, 'it', 'each')}{wait}, "
            f"then post the handover; the new session relaunches {plural(n, 'it', 'them')} fresh")  # fmt: skip


def handover_verdict(w: Wave) -> str:
    """One line: 'handover due: <why>' or 'handover not due' with its clauses (orchestrate-stage §7, #467).
    Due, even with runs in flight: the last call's context over HANDOVER_CONTEXT or the session over HANDOVER_HOURS
    old. Due once no run of this session is in flight: a merge into main since the session start changed the agents'
    instructions (until then: launch nothing new). Not due, no run in flight and the context over STOP_CONTEXT: a
    stop for the human hands over instead of arming a keep-alive. A stale run (is_stale) is named but not in flight."""
    s = w.session
    ctx = s.last_ctx
    age = (w.now - s.first) / 3600 if s.first is not None else 0.0
    running = [r for r in w.runs if not r.finished and not is_stale(r, w.now)]
    stale = [r for r in w.runs if not r.finished and is_stale(r, w.now)]
    changes = w.instructions if isinstance(w.instructions, list) else []
    reasons = []
    if ctx > HANDOVER_CONTEXT:
        reasons.append(f"the context {metrics.fmt_tok(ctx)} is over {HANDOVER_CONTEXT // 1000}k")
    if age > HANDOVER_HOURS:
        reasons.append(f"the session is {age:.1f} h old, over {HANDOVER_HOURS:g} h")
    if changes and (reasons or not running):
        reasons.append(f"merges into main since the session start changed the agents' instructions: "
                       f"{changes_text(changes)}")  # fmt: skip
    if reasons:
        line = "handover due: " + "; ".join(reasons)
        if running:
            line += "; " + in_flight_text(running, w.now)
        if changes:
            line += "; pull the main checkout before the new session starts"
    else:
        line = "handover not due"
        if changes:
            n = len(running)
            line += (f"; instruction change pending: launch nothing new; due once the {n} "
                     f"{plural(n, 'run in flight ends', 'runs in flight end')}: {changes_text(changes)}")  # fmt: skip
        if not running and ctx > STOP_CONTEXT:
            line += (f"; at a stop for the human: due (the context {metrics.fmt_tok(ctx)} is over "
                     f"{STOP_CONTEXT // 1000}k and no run is in flight)")  # fmt: skip
    if stale:
        n = len(stale)
        line += (f"; {n} stale {plural(n, 'run', 'runs')}, no line for over {STALE_MINUTES} min, not counted in flight "
                 f"({runs_text(stale, w.now)}): check {plural(n, 'it', 'each')}, stop {plural(n, 'it', 'them')} "
                 "before a handover")  # fmt: skip
    if isinstance(w.instructions, str):
        line += f"; instruction changes unavailable: {cell(w.instructions)}"
    elif w.merged_cut is not None and s.first is not None and w.merged_cut > s.first:
        line += (f"; instruction changes may be incomplete (gh's merged list is cut at {metrics.iso(w.merged_cut)}, "
                 "after the session start)")  # fmt: skip
    if isinstance(w.behind, str):
        line += f"; the main checkout's instruction files unavailable: {cell(w.behind)}"
    elif w.behind:
        line += (f"; the main checkout's instruction files are behind origin/main ({', '.join(w.behind)}): the human "
                 "pulls it before a new session starts")  # fmt: skip
    return line.rstrip(".") + "."


def footer_section(w: Wave) -> list[str]:
    s = w.session
    age = (w.now - s.first) / 3600 if s.first is not None else 0.0
    title = f' "{s.title}"' if s.title else ""
    first, last = s.calls[:FOOTER_CALLS], s.calls[-FOOTER_CALLS:]
    md = ["---", "",
          f"Session {s.sid}{title}: {age:.1f} h old; the last call's context {metrics.fmt_tok(s.last_ctx)}; mean API "
          f"list $ per call: first {len(first)} {metrics.fmt_usd(mean_usd(first))}, last {len(last)} "
          f"{metrics.fmt_usd(mean_usd(last))} ({len(s.calls)} calls)."]  # fmt: skip
    if s.skipped:
        md += ["", "Skipped: " + ", ".join(f"{k} {v}" for k, v in s.skipped.items()) + "."]
    return [*md, "", handover_verdict(w), ""]


SECTIONS: list[Callable[[Wave], list[str]]] = [
    header_section, notes_section, merged_section, finished_section, running_section, open_prs_section,
    merge_section, cost_section, housekeeping_section, handover_section, footer_section,
]  # fmt: skip


def render(w: Wave, sections: list[Callable[[Wave], list[str]]] | None = None) -> str:
    return "\n".join(line for section in sections or SECTIONS for line in section(w)).rstrip("\n") + "\n"


def part_path(out: Path, k: int) -> Path:
    """The k-th comment's file next to out: w.md -> w-2.md."""
    return out.with_name(f"{out.stem}-{k}{out.suffix}")


def render_parts(w: Wave, out: Path) -> list[tuple[Path, str]]:
    """The body as one file, or, over SPLIT_LIMIT characters, the body with its handover data moved to <out>-2.md,
    <out>-3.md, ... (each run's block whole, each file at most SPLIT_LIMIT unless one block alone is longer), each
    posted as the next comment."""
    body = render(w)
    chunks = handover_chunks(w)
    if len(body) <= SPLIT_LIMIT or not chunks:
        return [(out, body)]
    groups: list[list[list[str]]] = []
    size = 0
    for chunk in chunks:
        n = sum(len(line) + 1 for line in chunk)
        if not groups or size + n > SPLIT_LIMIT - 1000:  # room for the part's heading
            groups.append([])
            size = 0
        groups[-1].append(chunk)
        size += n
    paths = [part_path(out, k) for k in range(2, len(groups) + 2)]
    many = len(groups) > 1

    def pointer(_: Wave) -> list[str]:
        return ["## Handover data", "",
                f"Moved to the next {len(groups)} comment{'s' if many else ''} ({', '.join(p.name for p in paths)}): the "
                f"args of {len(chunks)} run{'s' if len(chunks) != 1 else ''}, posted right after this one as "
                f"{'they are' if many else 'it is'} (this body with them would have {len(body)} characters, over "
                f"{SPLIT_LIMIT}).", ""]  # fmt: skip

    s = w.session
    title = f' "{s.title}"' if s.title else ""
    parts = [(out, render(w, [pointer if f is handover_section else f for f in SECTIONS]))]
    for k, (path, group) in enumerate(zip(paths, groups), start=2):
        lines = [f"## Handover data, part {k} of {len(groups) + 1} (session {s.sid}{title})", "",
                 *(line for chunk in group for line in chunk)]  # fmt: skip
        parts.append((path, "\n".join(lines).rstrip("\n") + "\n"))
    return parts


# --- the command --------------------------------------------------------------------------------------------------


def find_transcript(session: str | None, dirs: list[Path]) -> tuple[Path, str]:
    """The transcript of a session id or its prefix (default: this Claude Code session) in the project folders."""
    sid = session or os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not sid:
        raise Failure("wave: no session: pass --session <id or prefix> (CLAUDE_CODE_SESSION_ID is not set)")
    found = [p for d in dirs for p in sorted(d.glob("*.jsonl")) if p.stem == sid or p.stem.startswith(sid)]
    exact = [p for p in found if p.stem == sid]
    found = exact or found
    if not found:
        where = ", ".join(str(d) for d in dirs) or "(no transcript folder of this checkout)"
        raise Failure(f"wave: no transcript of session {sid} in {where}")
    if len(found) > 1:
        raise Failure(f"wave: session {sid} is ambiguous: " + ", ".join(p.stem for p in found))
    return found[0], found[0].stem


def attempt(what: str, read: Callable[[], Any]) -> Any:
    """A source's value, or its error as a str (the section says it is unavailable; the rest of the body is still
    written). Exception, not BaseException: Ctrl+C still stops the command."""
    try:
        return read()
    except Exception as exc:
        text = str(exc).strip() or type(exc).__name__
        warn(f"wave: {what} unavailable: {text}")
        return text


def gather(w: Wave, src: Sources, merge_check: bool, dirs: list[Path], stage_since: float | None) -> None:
    """Every source beyond the transcripts, each on its own: one that fails leaves the others."""
    main = attempt("the main checkout", src.main_checkout)
    merged = attempt("merged PRs", lambda: read_merged(src.gh_json))
    w.merged, w.merged_cut = merged if isinstance(merged, tuple) else (merged, None)
    w.open_prs = attempt("open PRs", lambda: read_open(src.gh_json, w.base))
    if merge_check:
        w.merge_check = capture_merge_check(src.check, w.base)
    else:
        w.merge_check = MergeCheck(0, "", [], skipped=True)

    def cost() -> Cost:
        history = src.history(main) if isinstance(main, Path) else []
        return cost_of(dirs, w.session.sid, w.since, stage_since, w.now, history)

    w.cost = attempt("cost", cost)

    def housekeeping() -> Housekeeping:
        if isinstance(main, str):
            raise Failure(f"the main checkout: {main}")
        if not isinstance(w.merged, list):
            raise Failure(f"merged PRs: {w.merged}")
        worktrees = parse_worktrees(src.worktree_list(main))
        issues = read_open_issues(src.gh_json)
        return housekeeping_of(worktrees, w.merged, w.runs, src.alive_in, main, issues, w.since, w.now)

    w.housekeeping = attempt("housekeeping", housekeeping)
    # From the session's start, not --since: a merge after the session began but before this wave still counts.
    start = w.session.first if w.session.first is not None else w.since
    w.instructions = attempt("instruction changes", lambda: read_instruction_changes(src.gh_json, w.merged, start))
    if isinstance(main, Path):
        w.behind = attempt("the main checkout's instruction files", lambda: src.instructions_behind(main))
    else:
        w.behind = f"the main checkout: {main}"


def read_notes(path: Path) -> str:
    """--notes as UTF-8 text with LF line ends (a file PowerShell 5.1 wrote may start with a BOM and use CRLF)."""
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise Failure(f"wave: --notes {path}: cannot read it ({exc.strerror or exc})") from None
    return raw.decode("utf-8-sig", errors="replace").replace("\r\n", "\n")


def default_out(sid: str) -> Path:
    return OUT / "wave" / f"wave-{sid[:8]}.md"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(
    session: str | None = None,
    since: str | None = None,
    args_issue: int | None = None,
    out: str | None = None,
    workflow: str | None = None,
    base: str | None = None,
    plan: int | None = None,
    title: str | None = None,
    notes: str | None = None,
    stage_since: str | None = None,
    merge_check: bool = True,
    *,
    dirs: list[Path] | None = None,
    now: float | None = None,
    sources: Sources | None = None,
) -> int:
    started = time.monotonic()
    if (since is None) == (args_issue is None):
        raise Failure("wave: pass either --since T (the wave comment) or --args N (one issue's args)")
    if workflow is not None and args_issue is None:
        raise Failure("wave: --workflow goes with --args")
    if args_issue is not None:
        given = {"--base": base, "--plan": plan, "--title": title, "--notes": notes, "--stage-since": stage_since,
                 "--no-merge-check": None if merge_check else True}  # fmt: skip
        extra = [flag for flag, value in given.items() if value is not None]
        if extra:
            raise Failure(f"wave: {', '.join(extra)} goes with --since, not with --args")
    t_since = metrics.parse_time(since) if since is not None else None
    t_stage = metrics.parse_time(stage_since) if stage_since is not None else None
    notes_text = read_notes(Path(notes)) if notes is not None else None
    if dirs is None:
        dirs = agents_check.project_dirs(metrics.main_checkout())
    path, sid = find_transcript(session, dirs)
    s = read_session(path, sid)
    if args_issue is not None:
        launch = latest_launch(s, args_issue, workflow)
        text = json.dumps(launch.args, indent=1, ensure_ascii=False) + "\n"
        how = "passed" if launch.passed_args else f"inherited from {launch.resume_from}"
        print(f"wave: #{args_issue} {launch.name} args ({how}) of run {launch.run_id or '(no run id)'}, launched "
              f"{metrics.iso(launch.time)} in session {sid}", file=sys.stderr)  # fmt: skip
        if out:
            write_text(Path(out), text)
            print(f"wave: wrote {out}", file=sys.stderr)
        sys.stdout.write(text)
        sys.stdout.flush()
        return 0
    assert t_since is not None
    w = Wave(session=s, runs=build_runs(s), since=t_since, now=time.time() if now is None else now,
             base=base or MAIN, plan=plan, title=title, notes=notes_text)  # fmt: skip
    gather(w, sources or Sources(), merge_check, dirs, t_stage)
    if out:
        target = Path(out)
    else:
        ensure_out()
        target = default_out(sid)
    parts = render_parts(w, target)
    for path, text in parts:
        write_text(path, text)
    done = finished_since(w)
    say(f"wave: {len(done)} finished since {metrics.iso(t_since)}, {sum(not r.finished for r in w.runs)} running, "
        f"{sum(r.finished for r in w.runs) - len(done)} finished before; wrote {', '.join(str(p) for p, _ in parts)} "
        f"in {time.monotonic() - started:.1f} s")  # fmt: skip
    for path, text in parts:
        if len(text) > COMMENT_LIMIT:
            warn(f"{path.name} has {len(text)} characters, over GitHub's comment limit of {COMMENT_LIMIT}: it cannot be "
                 "posted as one comment")  # fmt: skip
    k = len(parts) + 1
    while part_path(target, k).exists():
        warn(f"{part_path(target, k)} is from an earlier run of wave, not part of this body")
        k += 1
    say(handover_verdict(w))  # the last line: the turn-end check reads it (orchestrate-stage §7)
    return 0
