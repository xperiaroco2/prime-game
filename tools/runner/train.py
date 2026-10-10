"""`merge-train <pr>... --base main [--dry-run] [--recent M]` (#387): merge a list of PRs into `main` one by one.

Since the trust ADR (docs/decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md) a PR merges into `main`
only with `main` in its head or behind it with no overlap (#632), so each merge may leave the others behind and they
go strictly in series. For each PR, in the order given, with no manager turn between them:

1. Plan. Read the PR (`gh`, bounded like every gh call of the runner). Merged already: counted as merged. Skipped
   with the reason: not open, not into `main`, a head that is not a task branch `<area>/<n>-<slug>` (a milestone's
   closing PR merges with `merge <pr> --base main`), a refusal of the gate that neither a publish nor CI changes
   (merge.standing_refusals: a draft, not the engineer's PR or session, an exception, an open "Needs the engineer"),
   no worktree with the head branch checked out (`git worktree list`), or a worktree a live run holds: a verify
   slot holder there whose process lives, a Claude Code session there that is busy or was updated within `--recent`
   minutes (idle, it may wait for its human), a rebase, merge, cherry-pick, revert or bisect in progress,
   uncommitted changes, a HEAD that is not the PR's head (commits nobody published, or the PR moved), or a commit
   younger than `--recent` minutes (default RECENT_MINUTES; orchestrate-stage §2.2). The train never touches such a
   worktree.
2. The way, printed: `main` already in the head: no publish. Behind `main`, but no path it changes since its fork is
   one `main` changed since then and GitHub reports it MERGEABLE (merge.behind_reason, the gate's own rule, #632): no
   publish either; CI runs on `main` after the merge. A history with merge commits (which `publish`'s rebase
   can trip on): `git merge origin/main` in the worktree, the worktree's own `verify`, a plain fast-forward push of
   the task branch (a conflict is aborted; a red verify undoes the merge commit). Otherwise the worktree's own
   `publish` (rebase, verify, push with a lease). A red verify is retried once, logged (a timeout on a busy PC is
   the usual cause); a rebase or merge conflict, a second red or any other stop skips the PR.
3. CI: GitHub shows the pushed head (at most HEAD_WAIT s), then its checks are polled from their JSON, never the
   exit code of `gh pr checks` (non-zero both while one is pending and when one failed): any failed or cancelled
   check skips the PR at once and names it (a new required job counts like any other), all passed or skipped goes
   on, and no verdict within CI_WAIT s skips it.
4. The gate and the merge: `merge.merge(<pr>, base="main")`, the same code as `merge <pr> --base main`; it prints
   the `wave:` line of the merge. A refusal skips the PR (its reasons are printed above).

One run keeps its git answers (merge.one_run, #724): a commit-hash question is asked once, a ref until the train
fetches or a publish or merge in a worktree has pushed (merge.CACHE.moved); `held` asks git for the worktree's state in
three calls, not nine.

A final summary, from a line "merge-train summary" (which `wait` prints), lists the merged and skipped PRs; exit 0
when every PR merged, else 1. `--dry-run` prints the plan (the worktree and the way of each PR, or why it would be
skipped) and each gate's verdict now (later PRs show "behind main" until the earlier ones merge), changes nothing
and runs from any checkout; exit 0 when no PR would be skipped. A real run refuses a task's checkout, like `merge`.

It never pushes `main` (publish pushes only the current task branch; the merge way pushes only a task branch, a
fast-forward the pre-push hook allows) and never merges what the gate refuses. A long job: start it in the
background, its output to a log followed by `exit=<n>`, and poll it with `wait` (docs/AGENT_WORKFLOW.md §11).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from . import merge, sessions, slots
from .common import Failure, Result, bad, ok, run, say, warn

REMOTE = merge.REMOTE
TASK_BRANCH_RE = merge.TASK_BRANCH_RE
PUBLISH_TIMEOUT = 3600  # publish and verify under load took up to 16 minutes on 2026-10-04
HEAD_WAIT = 300.0  # for GitHub to show the pushed head on the PR
CI_WAIT = 2400.0  # CI's verify takes about 6 minutes; a queue on GitHub can add more
POLL = 30.0
RECENT_MINUTES = 10
RED_VERIFY = re.compile(r"verify is red after the rebase")
REBASE_STOPPED = re.compile(r"the rebase on \S+ stopped")
GIT_STATES = {
    "rebase-merge": "rebase", "rebase-apply": "rebase", "MERGE_HEAD": "merge", "CHERRY_PICK_HEAD": "cherry-pick",
    "REVERT_HEAD": "revert", "BISECT_LOG": "bisect",
}  # fmt: skip


def _now() -> float:
    return time.monotonic()


def _sleep(seconds: float) -> None:
    time.sleep(seconds)


@dataclass
class Plan:
    pr: merge.PullRequest
    worktree: Path
    way: str  # "up to date", "no overlap", "merge", "publish"


@dataclass
class Outcome:
    number: int
    head: str
    merged: bool
    why: str  # merged: the way it took; skipped: the reason

    def line(self) -> str:
        what = f"#{self.number}" + (f" ({self.head})" if self.head else "")
        return f"  {'merged ' if self.merged else 'skipped'}  {what}: {self.why}"


WAYS = {
    "up to date": "main is already in its head: no publish",
    "no overlap": "behind main, no file it changes is one main changed since its fork: no publish (CI runs on main)",
    "merge": "its history holds merge commits: merge origin/main into it, verify, push (no rebase, no force)",
    "publish": "publish (rebase on origin/main, verify, push with a lease)",
}
DONE = {
    "up to date": "no publish (main was in its head)", "no overlap": "no publish (behind main, no overlap)",
    "merge": "origin/main merged in", "publish": "published",
}


# --- the worktrees ----------------------------------------------------------------------------------------------------


def _wt(wt: Path, *args: str, env: dict[str, str] | None = None) -> Result:
    return run(["git", *args], timeout=merge.TIMEOUT, cwd=wt, env=env)


def worktrees() -> dict[str, Path]:
    """The checked-out branch of each worktree of the main checkout, by branch name."""
    found: dict[str, Path] = {}
    path: Path | None = None
    for line in merge._out("worktree", "list", "--porcelain").split("\n"):
        if line.startswith("worktree "):
            path = Path(line[len("worktree ") :])
        elif line.startswith("branch refs/heads/") and path is not None:
            found[line[len("branch refs/heads/") :]] = path
    return found


def slot_holders() -> list[slots.Holder]:
    """Who holds each verify slot of this PC, as the holder files say (empty when the slots are off or unreadable)."""
    try:
        count = int(slots.setting(os.environ, slots.COUNT_VAR, slots.DEFAULT_COUNT))
        return slots.Pool(slots.folder(), count, 0).holders() if count > 0 else []
    except (Failure, OSError, ValueError):
        return []


def _same(a: str | Path, b: str | Path) -> bool:
    return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))


def held(wt: Path, pr: merge.PullRequest, recent_minutes: int) -> str:
    """Why a live run may hold the worktree (orchestrate-stage §2.2), or "" when the train may work in it."""
    for holder in slot_holders():
        if holder.pid and _same(holder.worktree, wt) and sessions.process_alive(holder.pid):
            what = "a load run" if holder.kind == slots.LOAD else "a verify"  # a load takes a slot too (#388)
            return f"{what} holds slot {holder.slot} there (pid {holder.pid}, since {holder.since})"
    me = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    now = time.time()
    for session in sessions.alive_in(wt):
        recent = recent_minutes > 0 and now - session.updated < recent_minutes * 60  # idle: may wait for its human
        if (session.status == "busy" or recent) and session.session_id != me:
            return f"the Claude Code session {session.describe(now)} works there"
    asked = _wt(wt, "rev-parse", *[arg for name in GIT_STATES for arg in ("--git-path", name)])  # one call for all
    answers = [a.strip() for a in asked.out.splitlines()] if asked.rc == 0 and not asked.timed_out else []
    if len(answers) != len(GIT_STATES):  # a warning line among them would shift the answers: ask one by one
        answers = [_wt(wt, "rev-parse", "--git-path", name).out.strip() for name in GIT_STATES]
    for (name, what), where in zip(GIT_STATES.items(), answers, strict=True):
        if where and (wt / where).exists():
            return f"a {what} is in progress there"
    dirty = _wt(wt, "status", "--porcelain", "--untracked-files=no").out.strip()
    if dirty:
        return f"uncommitted changes there ({len(dirty.splitlines())} files)"
    last = _wt(wt, "log", "-1", "--format=%H %ct")  # HEAD and its commit time in one call
    head, _, stamp = last.out.strip().partition(" ") if last.rc == 0 and not last.timed_out else ("", "", "")
    if head != pr.oid:
        return (
            f"its HEAD {head[:10]} is not the PR's head {pr.oid[:10]}: commits nobody published, or the PR moved "
            "since a run worked there"
        )
    age = time.time() - int(stamp) if stamp.isdigit() else None
    if recent_minutes > 0 and age is not None and age < recent_minutes * 60:
        return (
            f"its last commit is {max(0, int(age // 60))} min old (under --recent {recent_minutes}): a run may still "
            "work there; once you know it ended, run again with --recent 0"
        )
    return ""


# --- one PR -----------------------------------------------------------------------------------------------------------


def plan(pr: merge.PullRequest, recent_minutes: int) -> Plan | str:
    """The worktree and the way for an open PR, or why the train skips it."""
    if pr.state != "OPEN":
        return f"it is {pr.state.lower()}, not open"
    if pr.base != "main":
        return f"it targets {pr.base}: merge-train merges only into main"
    if not TASK_BRANCH_RE.match(pr.head):
        return f"its head {pr.head} is not a task branch <area>/<n>-<slug>: merge it with merge {pr.number} --base main"
    standing = merge.standing_refusals(pr)  # fetches origin
    if standing:
        return "the gate would refuse it whatever a publish does: " + "; ".join(standing)
    wt = worktrees().get(pr.head)
    if wt is None:
        return f"no worktree has {pr.head} checked out (git worktree list): publish it in its own checkout first"
    if _same(wt, merge.REPO):
        return f"{pr.head} is checked out in the main checkout, where the train runs"
    why = held(wt, pr, recent_minutes)
    if why:
        return f"{wt.as_posix()} is held: {why}"
    tip = merge._sha(f"refs/remotes/{REMOTE}/main")
    if tip and merge._is_ancestor(tip, pr.oid):
        return Plan(pr, wt, "up to date")
    if tip and not merge.behind_reason(pr, "main", tip, merge.mergeable_state(pr)):  # the gate's rule (#632)
        return Plan(pr, wt, "no overlap")
    merges = _wt(wt, "rev-list", "--merges", f"{REMOTE}/main..HEAD").out.split()
    return Plan(pr, wt, "merge" if merges else "publish")


def publish_in(wt: Path, log: str) -> Result:
    """The worktree's own `publish` (its runner, its verify), as `cd <wt> && tools/run.sh publish` would run it."""
    say(f"publish in {wt.as_posix()} (log: tools/out/logs/{log}.log)")
    return run(
        [sys.executable, str(wt / "tools" / "run.py"), "publish"], cwd=wt, timeout=PUBLISH_TIMEOUT, log=log, echo=True
    )


def verify_in(wt: Path, log: str) -> Result:
    """The worktree's own `verify` (merge.verify_in)."""
    return merge.verify_in(wt, log)


def _last_fail(result: Result) -> str:
    fails = [line.strip()[len("FAIL") :].strip() for line in result.lines if line.strip().startswith("FAIL ")]
    return fails[-1] if fails else (result.out.strip().splitlines() or ["no output"])[-1]


def _retry_note(label: str, what: str) -> None:
    warn(f"train: {label}: {what} is red on the first try: retrying once (a timeout on a busy PC is the usual cause)")


def by_publish(p: Plan) -> str:
    """Publish in the worktree, once more after a red verify; "" when pushed, else why not (the rebase undone)."""
    before = _wt(p.worktree, "rev-parse", "HEAD").out.strip()
    why = _publish(p)
    return why + _undo_rebase(p, before) if why else ""


def _publish(p: Plan) -> str:
    label = p.pr.label
    for attempt in (1, 2):
        result = publish_in(p.worktree, f"train-{p.pr.number}-publish-{attempt}")
        if result.rc == 0 and not result.timed_out:
            return ""
        if result.timed_out:
            return f"publish did not end within {PUBLISH_TIMEOUT} s"
        if REBASE_STOPPED.search(result.out):
            return "the rebase on origin/main stopped on a conflict (publish aborted it): pr-rebase"
        if not RED_VERIFY.search(result.out):
            return f"publish stopped: {_last_fail(result)}"
        if attempt == 1:
            _retry_note(label, "publish's verify")
    return "verify was red twice after the rebase: nothing was pushed"


def _undo_rebase(p: Plan, before: str) -> str:
    """After a publish that pushed nothing: the worktree back at the PR's head (publish leaves its rebase in place),
    so that a later train run does not find it held by "commits nobody published". Only while the remote branch is
    still the PR's head: a push that went through, or someone else's, is left alone."""
    wt, branch = p.worktree, p.pr.head
    now = _wt(wt, "rev-parse", "HEAD").out.strip()
    remote = _wt(wt, "rev-parse", "--verify", "--quiet", f"refs/remotes/{REMOTE}/{branch}").out.strip()
    if not before or now == before or before != p.pr.oid or remote != p.pr.oid:
        return ""
    res = _wt(wt, "reset", "-q", "--keep", before)
    if res.rc != 0 or res.timed_out:
        return f"; its rebase could not be undone (git reset --keep {before[:10]}: {_last_fail(res)})"
    return f"; its rebase undone ({now[:10]} -> {before[:10]})"


def by_merge(p: Plan) -> str:
    """Merge origin/main into a branch whose history holds merges, verify (once more after a red), push without force;
    "" when pushed, else why not (the merge commit undone)."""
    wt, branch, label = p.worktree, p.pr.head, p.pr.label
    if not TASK_BRANCH_RE.match(branch):  # never main or a long-lived branch (plan checks it too)
        raise Failure(f"{branch} is not a task branch: merge-train pushes nothing else")
    before = _wt(wt, "rev-parse", "HEAD").out.strip()
    res = _wt(wt, "merge", "--no-edit", f"{REMOTE}/main")
    if res.rc != 0 or res.timed_out:
        _wt(wt, "merge", "--abort")
        return f"merging origin/main stopped on a conflict (aborted): pr-rebase. {res.out.strip()[-300:]}"
    after = _wt(wt, "rev-parse", "HEAD").out.strip()
    ok(f"{label}: merged origin/main into {branch}: {before[:10]} -> {after[:10]}")
    for attempt in (1, 2):
        result = verify_in(wt, f"train-{p.pr.number}-verify-{attempt}")
        if result.rc == 0 and not result.timed_out:
            break
        if attempt == 1:
            _retry_note(label, "verify")
    else:
        _wt(wt, "reset", "-q", "--keep", before)
        return (
            f"verify was red twice after merging origin/main: nothing was pushed; the merge commit undone "
            f"({before[:10]})"
        )
    res = _wt(wt, "push", REMOTE, f"refs/heads/{branch}:refs/heads/{branch}")
    for line in res.lines:
        if line.strip():
            say(f"        {line.rstrip()}")
    if res.rc != 0 or res.timed_out:
        _wt(wt, "reset", "-q", "--keep", before)
        return f"the push of {branch} was rejected (the merge commit undone): {_last_fail(res)}"
    ok(f"{label}: pushed {branch} at {after[:10]} (a fast-forward)")
    return ""


def wait_head(number: int, oid: str) -> bool:
    """Whether GitHub shows oid as the PR's head within HEAD_WAIT s."""
    deadline = _now() + HEAD_WAIT
    while True:
        try:
            if merge.pr_view(number).oid == oid:
                return True
        except Failure:
            pass  # a gh call that failed or timed out: ask again
        if _now() >= deadline:
            return False
        _sleep(min(10.0, POLL))


def wait_ci(number: int) -> str:
    """"" once every check on the PR's head passed (or was skipped), else why not: a failed or cancelled check at
    once, or no verdict within CI_WAIT s."""
    deadline = _now() + CI_WAIT
    while True:
        found, answer = merge.checks(number)
        failed = [f"{c.get('name')}: {c.get('state')}" for c in found if c.get("bucket") in ("fail", "cancel")]
        if failed:
            return "CI is red: " + "; ".join(failed)
        if found and all(c.get("bucket") in ("pass", "skipping") for c in found):
            return ""
        if _now() >= deadline:
            pending = [str(c.get("name")) for c in found if c.get("bucket") == "pending"]
            left = ", ".join(pending) or answer or "no checks reported"
            return f"CI gave no verdict within {CI_WAIT / 60:.0f} min ({left})"
        _sleep(POLL)


def ride(number: int, recent_minutes: int) -> Outcome:
    """One PR through the train: plan, publish (or merge main in), CI, the gate and the merge."""
    pr = merge.pr_view(number)
    if pr.state == "MERGED":
        return Outcome(number, pr.head, True, "already merged")
    planned = plan(pr, recent_minutes)
    if isinstance(planned, str):
        return Outcome(number, pr.head, False, planned)
    say(f"train: {pr.label}: in {planned.worktree.as_posix()}; way: {WAYS[planned.way]}")
    if planned.way not in ("up to date", "no overlap"):
        why = by_publish(planned) if planned.way == "publish" else by_merge(planned)
        merge.CACHE.moved()  # the worktree's publish or push moved the remote-tracking refs
        if why:
            return Outcome(number, pr.head, False, why)
        oid = _wt(planned.worktree, "rev-parse", "HEAD").out.strip()
        if not wait_head(number, oid):
            why = f"GitHub did not show the pushed head {oid[:10]} within {HEAD_WAIT:.0f} s"
            return Outcome(number, pr.head, False, why)
    say(f"train: {pr.label}: waiting for CI (at most {CI_WAIT / 60:.0f} min)")
    why = wait_ci(number)
    if why:
        return Outcome(number, pr.head, False, why)
    ok(f"{pr.label}: CI green")
    if merge.merge(number, base="main") != 0:
        return Outcome(number, pr.head, False, "the gate refused it (its gate: refused lines above)")
    return Outcome(number, pr.head, True, f"{DONE[planned.way]}, CI green, the gate passed")


def survey(number: int, recent_minutes: int) -> bool:
    """--dry-run for one PR: its plan and the gate's verdict now; True when the train would not skip it."""
    pr = merge.pr_view(number)
    if pr.state == "MERGED":
        say(f"plan: {pr.label} ({pr.head}): already merged")
        return True
    planned = plan(pr, recent_minutes)
    if isinstance(planned, str):
        say(f"plan: {pr.label} ({pr.head}): would skip: {planned}")
        return False
    say(f"plan: {pr.label} ({pr.head}) in {planned.worktree.as_posix()}: {WAYS[planned.way]}")
    say(f"plan: {pr.label}: the gate now (behind main and CI change once the earlier PRs merge):")
    merge.merge(number, base="main", dry_run=True)
    return True


@merge.in_one_run
def main(numbers: list[int], base: str, dry_run: bool = False, recent_minutes: int = RECENT_MINUTES) -> int:
    order = list(dict.fromkeys(numbers))
    say(f"merge-train {' '.join(map(str, order))} --base {base}" + (" --dry-run" if dry_run else ""))
    if base != "main":
        raise Failure(f"merge-train merges only into main, not {base}; into a release branch: merge <pr> --base {base}")
    if not order:
        raise Failure("name the PRs to merge, in order: merge-train 350 321 --base main")
    if recent_minutes < 0:
        raise Failure("--recent is 0 (off) or more minutes")
    if dry_run:
        fine = True
        for number in order:
            try:
                fine = survey(number, recent_minutes) and fine
            except Failure as exc:
                bad(f"#{number}: {exc}")
                fine = False
        say(f"merge-train --dry-run: {'every PR would go' if fine else 'some PRs would be skipped'}; nothing changed")
        return 0 if fine else 1
    merge.refuse_task_checkout()
    outcomes: list[Outcome] = []
    try:
        for number in order:
            say()
            say(f"== merge-train: #{number} ({datetime.now(UTC).strftime('%H:%MZ')})")
            try:
                outcome = ride(number, recent_minutes)
            except (Failure, subprocess.TimeoutExpired, OSError) as exc:  # a hung git call ends one PR, not the train
                outcome = Outcome(number, "", False, str(exc) or type(exc).__name__)
            if not outcome.merged:
                bad(f"train: #{number} skipped: {outcome.why}")
            outcomes.append(outcome)
    finally:  # an unexpected error still leaves the summary of the PRs taken so far for `wait`
        summarize(outcomes, len(order))
    return 0 if sum(o.merged for o in outcomes) == len(order) else 1


def summarize(outcomes: list[Outcome], wanted: int) -> None:
    merged = sum(o.merged for o in outcomes)
    say()
    say("merge-train summary")
    for outcome in outcomes:
        say(outcome.line())
    left = f", {wanted - len(outcomes)} not tried (the train stopped)" if len(outcomes) < wanted else ""
    say(f"merge-train: {merged} merged, {len(outcomes) - merged} skipped of {len(outcomes)} PRs{left}")
