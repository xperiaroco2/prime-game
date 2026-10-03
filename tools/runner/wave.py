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
Read-only: it writes only its --out file (default tools/out/wave/wave-<sid8>.md; with --args only an --out given),
runs no gh and launches nothing. Sections are separate functions returning Markdown lines (SECTIONS), so a follow-up
(#278) adds sections without touching these.
"""

from __future__ import annotations

import io
import json
import os
import re
import sys
import time
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from . import agents_check, metrics
from .common import OUT, Failure, ensure_out, say

RELAUNCH = "relaunch fresh, never resume"
RUN_ID = re.compile(r"Run ID:\s*(wf_[\w-]+)")
# "stopped" as a key of the workflow's own result; an escaped \"stopped\" sits inside an agent's string and is not one.
STOPPED = re.compile(r'(?<!\\)"stopped"\s*:\s*"((?:[^"\\]|\\.)*)')
# GitHub's limit on a comment body, in characters.
COMMENT_LIMIT = 65536
FOOTER_CALLS = 20
# A workflow's notification says so in its summary ('Dynamic workflow "…" completed'); the other notifications in a
# manager's queue (background shells, monitors, its subagents' tasks) are not runs and are passed over.
WORKFLOW_NOTE = re.compile(r"\bworkflow\b", re.I)
REVIEW_ROLES = ("code-reviewer", "netcode-security-reviewer", "netcode-second-reviewer", "godot-api-checker")


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

    @property
    def latest(self) -> Launch:
        return self.launches[-1]


@dataclass
class Wave:
    """What every section gets."""

    session: Session
    runs: list[Run]
    since: float
    now: float


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
    return runs


def latest_launch(s: Session, n: int, workflow: str | None = None) -> Launch:
    """The newest launch whose args.n is n (and whose workflow is `workflow`, when given)."""
    found = [x for x in s.launches if issue_of(x.args) == n and (workflow is None or x.name == workflow)]
    if found:
        return found[-1]
    launched = sorted({i for x in s.launches if (i := issue_of(x.args)) is not None})
    named = f" of the workflow {workflow}" if workflow else ""
    raise Failure(
        f"wave: no Workflow launch{named} of issue #{n} in session {s.sid} ({s.path}); launched: "
        + (", ".join(f"#{i}" for i in launched) or "none with args.n")
    )


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


def handover_block(r: Run, s: Session) -> list[str]:
    title = f' "{s.title}"' if s.title else ""
    head = f"<details><summary>{issue_cell(r)} {r.name} args ({r.run_id}; session {s.sid[:8]}{title})</summary>"
    if r.args is None:
        return [f"{issue_cell(r)} {r.name} ({r.run_id}): no args were passed.", ""]
    return [head, "", *fence(json.dumps(r.args, indent=1, ensure_ascii=False), "json"), "</details>", ""]


def handover_section(w: Wave) -> list[str]:
    md = ["## Handover data", ""]
    running = [r for r in w.runs if not r.finished]
    for r in running:
        md += handover_block(r, w.session)
    again = [r for r in finished_since(w) if r.stopped or r.status in ("failed", "killed")]
    if again:
        md += ["### Finished runs that need a resume or a fresh relaunch", ""]
        for r in again:
            md += handover_block(r, w.session)
    if not running and not again:
        md += ["No run is running.", ""]
    return md


def mean_usd(calls: list[dict]) -> float:
    return sum(sum(metrics.usd_of(c).values()) for c in calls) / len(calls) if calls else 0.0


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
    return [*md, ""]


SECTIONS: list[Callable[[Wave], list[str]]] = [finished_section, running_section, handover_section, footer_section]


def render(w: Wave) -> str:
    return "\n".join(line for section in SECTIONS for line in section(w)).rstrip("\n") + "\n"


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
    *,
    dirs: list[Path] | None = None,
    now: float | None = None,
) -> int:
    if (since is None) == (args_issue is None):
        raise Failure("wave: pass either --since T (the wave comment) or --args N (one issue's args)")
    if workflow is not None and args_issue is None:
        raise Failure("wave: --workflow goes with --args")
    t_since = metrics.parse_time(since) if since is not None else None
    if dirs is None:
        dirs = agents_check.project_dirs(metrics.main_checkout())
    path, sid = find_transcript(session, dirs)
    s = read_session(path, sid)
    if args_issue is not None:
        launch = latest_launch(s, args_issue, workflow)
        text = json.dumps(launch.args, indent=1, ensure_ascii=False) + "\n"
        how = "passed" if launch.passed_args else f"inherited from {launch.resume_from}"
        print(f"wave: #{args_issue} {launch.name} args ({how}) of run {launch.run_id or '(no run id)'}, launched "
              f"{metrics.iso(launch.time)} in session {sid[:8]}", file=sys.stderr)  # fmt: skip
        if out:
            write_text(Path(out), text)
            print(f"wave: wrote {out}", file=sys.stderr)
        sys.stdout.write(text)
        sys.stdout.flush()
        return 0
    assert t_since is not None
    w = Wave(session=s, runs=build_runs(s), since=t_since, now=time.time() if now is None else now)
    body = render(w)
    if out:
        target = Path(out)
    else:
        ensure_out()
        target = default_out(sid)
    write_text(target, body)
    done = finished_since(w)
    say(f"wave: {len(done)} finished since {metrics.iso(t_since)}, {sum(not r.finished for r in w.runs)} running, "
        f"{sum(r.finished for r in w.runs) - len(done)} finished before; wrote {target}")  # fmt: skip
    if len(body) > COMMENT_LIMIT:
        say(f"  warn  the body has {len(body)} characters, over GitHub's comment limit of {COMMENT_LIMIT}")
    return 0
