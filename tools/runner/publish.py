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
from .common import ROOT, Failure, Result, bad, ok, run, say

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

    # --prune drops remote-tracking refs of deleted branches, so the lease below never expects a branch that is gone.
    _must(_git("fetch", "--prune", REMOTE), f"git fetch {REMOTE}")
    base = base or pr_base(branch) or "main"
    upstream = f"{REMOTE}/{base}"
    _must(_git("rev-parse", "--verify", "--quiet", f"refs/remotes/{upstream}"), f"finding {upstream}")
    ok(f"fetched {REMOTE}; base {upstream}")

    before = _must(_git("rev-parse", "HEAD"), "reading HEAD")
    remote_oid = _git("rev-parse", "--verify", "--quiet", f"refs/remotes/{REMOTE}/{branch}").out.strip()
    if remote_oid and not was_local(branch, remote_oid):
        raise Failure(
            f"{REMOTE}/{branch} has commits this branch never had (a suggestion committed on GitHub, \"Update "
            "branch\", or a push from the other machine). The lease push would delete them, so publish stopped "
            f"before changing anything. Ask the human; usually: git merge {REMOTE}/{branch}, then publish again."
        )

    # --fork-point: after a stacked parent was rebased, replay only this branch's own commits onto it.
    res = _git("rebase", "--fork-point", upstream)
    if res.rc != 0 or res.timed_out:
        _git("rebase", "--abort")
        raise Failure(
            f"the rebase on {upstream} stopped, usually on a conflict. Publish aborted it: {branch} is unchanged "
            f"at {before[:10]}. Ask the human how to resolve it.\n{res.out.strip()[-600:]}"
        )
    after = _must(_git("rev-parse", "HEAD"), "reading HEAD")
    ok(f"rebased on {upstream}" + (" (already up to date)" if after == before else f": {before[:10]} -> {after[:10]}"))

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
