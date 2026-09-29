"""`publish`: rebase the current task branch on its base, verify it, and push it with --force-with-lease.

The only way the agent updates a pushed branch after a rebase (docs/decisions/2026-09-28-force-with-lease-on-task-
branches.md). The pre-push hook lets this one non-fast-forward push through because the runner marks it with
PRIME_GAME_PUBLISH=force-with-lease; a force push typed by hand has no marker and is blocked.
"""

from __future__ import annotations

import json
import re
import shutil

from . import verify
from .common import ROOT, Failure, Result, bad, ok, run, say, warn

REMOTE = "origin"
# The checkout publish works on (tests point it at a temp repo).
REPO = ROOT
TASK_BRANCH_RE = re.compile(r"^[a-z][a-z0-9]*/[0-9]+-[a-z0-9][a-z0-9._-]*$")
MARKER = {"PRIME_GAME_PUBLISH": "force-with-lease"}
TIMEOUT = 300


def _git(*args: str, env: dict[str, str] | None = None) -> Result:
    return run(["git", *args], timeout=TIMEOUT, env=env, cwd=REPO)


def _must(res: Result, what: str) -> str:
    if res.timed_out or res.rc != 0:
        raise Failure(f"{what} failed: {res.out.strip()[-600:]}")
    return res.out.strip()


def pr_base(branch: str) -> str | None:
    """The base branch of the open pull request for branch (a stacked PR's parent), or None."""
    exe = shutil.which("gh")
    if not exe:
        return None
    res = run([exe, "pr", "view", branch, "--json", "baseRefName,state"], timeout=60)
    if res.rc != 0:
        return None
    try:
        data = json.loads(res.out)
    except ValueError:
        return None
    return data.get("baseRefName") if data.get("state") == "OPEN" else None


def base_key(branch: str) -> str:
    """The git config key where `start --base` records a stacked task's parent."""
    return f"branch.{branch}.primeBase"


def tip_key(branch: str) -> str:
    """The parent commit this branch's own commits sit on: `rebase --onto` replays exactly those, without the reflog
    `--fork-point` needs (worktrees share the remote refs, and any prune deletes a gone parent's ref and reflog)."""
    return f"branch.{branch}.primeBaseTip"


def recorded_base(branch: str) -> str | None:
    return _git("config", "--get", base_key(branch)).out.strip() or None


def _sha(ref: str) -> str:
    return _git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}").out.strip()


def _in(commit: str, ref: str) -> bool:
    return bool(commit) and _git("merge-base", "--is-ancestor", commit, ref).rc == 0


def was_local(branch: str, oid: str) -> bool:
    """oid is in the branch's history or was once its tip (reflog): the remote holds nothing the branch never had.
    A rebase or an amend keeps the old tips in the reflog, so publishing over them loses nothing."""
    if _git("merge-base", "--is-ancestor", oid, "HEAD").rc == 0:
        return True
    reflog = _git("reflog", "show", "--format=%H", f"refs/heads/{branch}").out.split()
    return oid in reflog


def main(base: str | None = None) -> int:
    say("publish")
    branch = _git("symbolic-ref", "--quiet", "--short", "HEAD").out.strip()
    if not TASK_BRANCH_RE.match(branch):
        raise Failure(
            f"the current branch '{branch or '(detached HEAD)'}' is not a task branch <area>/<n>-<slug>; "
            "publish pushes only the current task branch"
        )
    dirty = _git("status", "--porcelain", "--untracked-files=no").out.strip()
    if dirty:
        raise Failure(f"uncommitted changes; commit them first:\n{dirty}")

    asked = base
    parent = recorded_base(branch)
    tip = _git("config", "--get", tip_key(branch)).out.strip() if parent else ""
    if not _in(tip, "HEAD"):
        tip = ""  # the branch was rewritten by hand: --fork-point below, as for an unrecorded branch
    # Read before the prune below deletes it: the parent's tip as this checkout last saw it.
    stale = _sha(f"refs/remotes/{REMOTE}/{parent}") if parent else ""
    # --prune drops remote-tracking refs of deleted branches, so the lease below never expects a branch that is gone.
    _must(_git("fetch", "--prune", REMOTE), f"git fetch {REMOTE}")
    # An open PR's base wins over the recorded parent: GitHub retargets it to main once the parent is merged.
    base = base or pr_base(branch)
    source, unstack = "", False
    if parent:
        live = _sha(f"refs/remotes/{REMOTE}/{parent}")
        merged = _in(live, f"{REMOTE}/main")
        # Without a usable recorded tip, a parent tip already in this branch still marks where its own commits begin.
        tip = tip or next((c for c in (live, stale) if _in(c, "HEAD")), "")
        if not base and live and not merged:
            base, source = parent, " (recorded by start --base)"
        elif (base or "main") == "main":
            # The parent is done: merged (its branch deleted or not) or, with --base main, the human says so.
            latest = live or stale or tip
            if not asked and not _in(latest, f"{REMOTE}/main"):
                raise Failure(
                    f"publish cannot confirm that the parent {parent} (recorded by start --base) was merged: its last "
                    f"known tip {latest[:10] or '(unknown)'} is not in {REMOTE}/main. Rebasing on main now could carry "
                    "its commits into this PR. Nothing was changed. Ask the human to check the parent's PR; if it was "
                    "merged, run publish --base main (it replays only this branch's own commits onto main)."
                )
            if tip and not _in(latest, f"{REMOTE}/main"):
                dropped = _git("log", "--oneline", f"{REMOTE}/main..{tip}").out.strip()
                warn(
                    f"--base main leaves out these commits of the parent {parent}, which {REMOTE}/main lacks (to keep "
                    f"them instead: git config --unset {base_key(branch)}, and the same for {tip_key(branch)}):\n"
                    + dropped
                )
            base, unstack = "main", True
        elif base == parent and merged:
            warn(f"the parent {parent} is merged but its branch remains: gh pr edit {branch} --base main")
    base = base or "main"
    upstream = f"{REMOTE}/{base}"
    _must(_git("rev-parse", "--verify", "--quiet", f"refs/remotes/{upstream}"), f"finding {upstream}")
    ok(f"fetched {REMOTE}; base {upstream}{source}")
    onto = bool(tip) and (unstack or base == parent)

    before = _must(_git("rev-parse", "HEAD"), "reading HEAD")
    remote_oid = _git("rev-parse", "--verify", "--quiet", f"refs/remotes/{REMOTE}/{branch}").out.strip()
    if remote_oid and not was_local(branch, remote_oid):
        raise Failure(
            f"{REMOTE}/{branch} has commits this branch never had (a suggestion committed on GitHub, \"Update "
            "branch\", or a push from the other machine). The lease push would delete them, so publish stopped "
            f"before changing anything. Ask the human; usually: git merge {REMOTE}/{branch}, then publish again."
        )

    # After a stacked parent was rebased or amended, replay only this branch's own commits onto it: the ones after the
    # recorded parent commit (--onto), else after the fork point that the upstream's reflog shows (--fork-point).
    res = _git("rebase", "--onto", upstream, tip) if onto else _git("rebase", "--fork-point", upstream)
    if res.rc != 0 or res.timed_out:
        _git("rebase", "--abort")
        raise Failure(
            f"the rebase on {upstream} stopped, usually on a conflict. Publish aborted it: {branch} is unchanged "
            f"at {before[:10]}. Ask the human how to resolve it.\n{res.out.strip()[-600:]}"
        )
    after = _must(_git("rev-parse", "HEAD"), "reading HEAD")
    ok(f"rebased on {upstream}" + (" (already up to date)" if after == before else f": {before[:10]} -> {after[:10]}"))
    if unstack:
        _git("config", "--unset", tip_key(branch))
        _must(_git("config", "--unset", base_key(branch)), "forgetting the recorded parent")
        ok(f"the parent {parent} is merged: the base is main from now on")
    elif parent and base == parent:
        _must(_git("config", tip_key(branch), _sha(upstream)), "recording the parent's tip")

    say()
    if verify.main() != 0:
        raise Failure("verify is red after the rebase; nothing was pushed")
    say()

    # An empty expected value means the branch must not exist on the remote yet.
    lease = f"--force-with-lease=refs/heads/{branch}:{remote_oid}"
    res = _git("push", lease, "-u", REMOTE, f"{branch}:{branch}", env=MARKER)
    for line in res.lines:
        if line.strip():
            say(f"        {line.rstrip()}")
    if res.rc != 0 or res.timed_out:
        bad(f"push of {branch} failed")
        raise Failure(
            "the push was rejected. 'stale info' means the remote branch moved since the fetch: "
            "run publish again, and ask the human if it repeats."
        )
    ok(f"pushed {branch} at {after[:10]}" + (f" (was {remote_oid[:10]} on {REMOTE})" if remote_oid else " (new)"))
    say("publish: done")
    return 0
