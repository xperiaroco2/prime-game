"""`start <n>` (docs/AGENT_WORKFLOW.md §4.1) and `worktree-done <n>`.

`start` puts the checkout on the task branch `<area>/<n>-<slug>` from `origin/main` (or back on it, when it exists),
assigns the issue to the caller if nobody has it, and moves it to "In progress" on the board. It never discards
work: uncommitted changes stop it unless the caller says `--include` (carry them onto the task branch) or `--stash`.
It makes a worktree `.claude/worktrees/<n>` instead only for the engineer, and only when another Claude session is
active on this checkout (docs/decisions/2026-09-28-worktrees-only-for-parallel-sessions.md). `worktree-done <n>`
removes such a worktree once its branch is merged.
"""

from __future__ import annotations

import json
import re
import shutil
import time
from pathlib import Path

from . import board, sessions
from .common import ROOT, Failure, Result, ok, run, say, warn

REMOTE = "origin"
BASE = "main"
# The checkout start works on (tests point it at a temp repo).
REPO = ROOT
AREAS = ("core", "server", "net", "client", "voice", "content", "level", "tooling")
AREA_LABEL_RE = re.compile(r"^area:([a-z]+)$")
SLUG_MAX = 40
TIMEOUT = 120


def _git(*args: str, cwd: Path | None = None) -> Result:
    return run(["git", *args], timeout=TIMEOUT, cwd=cwd or REPO)


def _must(res: Result, what: str) -> str:
    if res.timed_out or res.rc != 0:
        raise Failure(f"{what} failed: {res.out.strip()[-600:]}")
    return res.out.strip()


def _gh(*args: str) -> str:
    exe = shutil.which("gh")
    if not exe:
        raise Failure("GitHub CLI (gh) not found: winget install --id GitHub.cli")
    return _must(run([exe, *args], timeout=60, cwd=REPO), f"gh {' '.join(args[:2])}")


def slug(title: str) -> str:
    """'M0: Vote tally (host)' -> 'm0-vote-tally-host': lowercase ASCII words, at most SLUG_MAX characters."""
    out = ""
    for word in re.findall(r"[a-z0-9]+", title.lower()):
        candidate = f"{out}-{word}" if out else word
        if len(candidate) > SLUG_MAX:
            break
        out = candidate
    return out or "task"


def area_of(labels: list[str], override: str | None, number: int) -> str:
    if override:
        if override not in AREAS:
            raise Failure(f"--area must be one of {', '.join(AREAS)}")
        return override
    areas = sorted({m.group(1) for m in map(AREA_LABEL_RE.match, labels) if m and m.group(1) in AREAS})
    if len(areas) == 1:
        return areas[0]
    if not areas:
        raise Failure(
            f"issue #{number} has no area label, so the branch prefix is unknown. Add one, for example: "
            f"gh issue edit {number} --add-label area:tooling (or pass --area)"
        )
    raise Failure(f"issue #{number} has several area labels ({', '.join(areas)}); pass --area with the right one")


def existing_branch(number: int) -> str | None:
    """A local or remote task branch for this issue, whatever its area and slug."""
    names = set(_git("branch", "--list", "--format=%(refname:short)", f"*/{number}-*").out.split())
    remote = _git("branch", "-r", "--list", "--format=%(refname:short)", f"{REMOTE}/*/{number}-*").out.split()
    names |= {name.removeprefix(f"{REMOTE}/") for name in remote}
    names = {n for n in names if re.fullmatch(rf"[a-z][a-z0-9]*/{number}-[a-z0-9][a-z0-9._-]*", n)}
    if len(names) > 1:
        raise Failure(f"several branches exist for #{number}: {', '.join(sorted(names))}. Ask the human which one.")
    return names.pop() if names else None


def local_exists(branch: str) -> bool:
    return _git("rev-parse", "--verify", "--quiet", f"refs/heads/{branch}").rc == 0


def main(
    number: int,
    *,
    area: str | None = None,
    stash: bool = False,
    include: bool = False,
    worktree: bool = False,
    here: bool = False,
    dry_run: bool = False,
) -> int:
    say(f"start #{number}" + (" (dry run: changes nothing)" if dry_run else ""))
    if stash and include:
        raise Failure("pass --stash or --include, not both")
    if worktree and here:
        raise Failure("pass --worktree or --here, not both")

    issue = json.loads(_gh("issue", "view", str(number), "--json", "number,title,state,labels,assignees,url"))
    if "/pull/" in str(issue.get("url")):
        raise Failure(f"#{number} is a pull request, not an issue")
    if issue.get("state") != "OPEN":
        raise Failure(f"issue #{number} is {issue.get('state')}; reopen it first if the work is not done")
    labels = [label["name"] for label in issue.get("labels", [])]
    login = _gh("api", "user", "--jq", ".login")
    engineer = login == board.OWNER
    ok(f"#{number} '{issue['title']}' ({', '.join(labels) or 'no labels'}); you are {login}")

    _must(_git("fetch", REMOTE), f"git fetch {REMOTE}")
    branch = existing_branch(number) or f"{area_of(labels, area, number)}/{number}-{slug(issue['title'])}"
    current = _git("symbolic-ref", "--quiet", "--short", "HEAD").out.strip()

    others = sessions.active_on(REPO)
    now = time.time()
    for other in others:
        say(f"        another session is active on this checkout: {other.describe(now)}")
    if worktree and not engineer:
        raise Failure("worktrees are for the engineer only (docs/AGENT_WORKFLOW.md §4.1)")
    use_worktree = worktree or (engineer and bool(others) and not here and current != branch)

    if use_worktree:
        path = create_worktree(number, branch, dry_run)
    else:
        switch(branch, current, stash=stash, include=include, dry_run=dry_run, number=number)
        path = REPO

    if dry_run:
        say("start: dry run done")
        return 0
    if not issue.get("assignees"):
        _gh("issue", "edit", str(number), "--add-assignee", "@me")
        ok(f"assigned #{number} to {login}")
    elif login not in {a.get("login") for a in issue["assignees"]}:
        warn(f"#{number} is assigned to {', '.join(a.get('login', '?') for a in issue['assignees'])}, not to you")
    board.move(number, "in-progress")
    if use_worktree:
        say(f"WORKTREE {path}")
        say("        Work there: EnterWorktree with this path, or open a new session in that folder.")
        say("        Its first `tools\\run.cmd check` imports the project from scratch (slower once).")
    say(f"start: on {branch}")
    return 0


def switch(branch: str, current: str, *, stash: bool, include: bool, dry_run: bool, number: int) -> None:
    dirty = _git("status", "--porcelain", "--untracked-files=all").out.strip()
    if current == branch:
        ok(f"already on {branch}" + (" (with uncommitted changes, kept)" if dirty else ""))
        return
    if dirty and not (stash or include):
        raise Failure(
            f"uncommitted changes on '{current or 'detached HEAD'}':\n{dirty}\n"
            "Nothing was changed. Ask the human, then run start again with one of:\n"
            "  --include  carry these changes onto the task branch (they belong to this task)\n"
            "  --stash    put them away with git stash (git stash list; git stash pop brings them back)"
        )
    exists_locally = local_exists(branch)
    if exists_locally:
        action = f"switch to the existing branch {branch}"
    elif _git("rev-parse", "--verify", "--quiet", f"refs/remotes/{REMOTE}/{branch}").rc == 0:
        action = f"check out {branch} from {REMOTE}/{branch}"
    else:
        action = f"create {branch} from {REMOTE}/{BASE}"
    if dry_run:
        say(f"        would {action}" + (" after stashing the changes" if dirty and stash else ""))
        return
    if dirty and stash:
        _must(
            _git("stash", "push", "--include-untracked", "-m", f"start #{number}: left on {current or 'HEAD'}"),
            "git stash push",
        )
        ok(f"stashed the uncommitted changes of {current} (git stash list)")
    if exists_locally:
        res = _git("switch", branch)
    elif action.startswith("check out"):
        res = _git("switch", "--track", "-c", branch, f"{REMOTE}/{branch}")
    else:
        # --no-track: the upstream becomes origin/<branch> at the first publish, never origin/main.
        res = _git("switch", "--no-track", "-c", branch, f"{REMOTE}/{BASE}")
    if res.rc != 0 or res.timed_out:
        raise Failure(
            f"git could not {action}; nothing was discarded"
            + (" (the stash still holds the changes: git stash list)" if dirty and stash else "")
            + f":\n{res.out.strip()[-600:]}"
        )
    ok(action[0].upper() + action[1:] + (", carrying the uncommitted changes" if dirty and include else ""))


def worktrees_root() -> Path:
    return main_checkout() / ".claude" / "worktrees"


def main_checkout() -> Path:
    """The main checkout, also when the runner runs from inside a worktree."""
    common = Path(_must(_git("rev-parse", "--path-format=absolute", "--git-common-dir"), "finding the git dir"))
    return common.parent


def listed_worktrees() -> dict[str, str]:
    """{normalized path: branch} from `git worktree list --porcelain`."""
    found: dict[str, str] = {}
    path = ""
    for line in _git("worktree", "list", "--porcelain").out.splitlines():
        if line.startswith("worktree "):
            path = str(Path(line.removeprefix("worktree ")).resolve()).lower()
            found[path] = ""
        elif line.startswith("branch ") and path:
            found[path] = line.removeprefix("branch refs/heads/")
    return found


def create_worktree(number: int, branch: str, dry_run: bool) -> Path:
    path = worktrees_root() / str(number)
    known = listed_worktrees()
    if str(path.resolve()).lower() in known:
        ok(f"worktree {path} already exists (on {known[str(path.resolve()).lower()] or 'a detached HEAD'})")
        return path
    if path.exists():
        raise Failure(f"{path} exists but is not a git worktree; ask the human what it is before anything else")
    if local_exists(branch):
        args, source = ["worktree", "add", str(path), branch], f"the existing branch {branch}"
    elif _git("rev-parse", "--verify", "--quiet", f"refs/remotes/{REMOTE}/{branch}").rc == 0:
        args, source = ["worktree", "add", "--track", "-b", branch, str(path), f"{REMOTE}/{branch}"], f"{REMOTE}/{branch}"
    else:
        args, source = ["worktree", "add", "--no-track", "-b", branch, str(path), f"{REMOTE}/{BASE}"], f"{REMOTE}/{BASE}"
    if dry_run:
        say(f"        would create the worktree {path} on {branch} from {source}")
        return path
    _must(_git(*args), "git worktree add")
    ok(f"created the worktree {path} on {branch} from {source}")
    return path


def worktree_done(number: int) -> int:
    say(f"worktree-done #{number}")
    path = worktrees_root() / str(number)
    key = str(path.resolve()).lower()
    known = listed_worktrees()
    if key not in known:
        raise Failure(f"no worktree for #{number} at {path}")
    if Path(str(REPO)).resolve() == path.resolve():
        raise Failure("run worktree-done from the main checkout, not from inside the worktree")
    branch = known[key]
    dirty = _git("status", "--porcelain", "--untracked-files=all", cwd=path).out.strip()
    if dirty:
        raise Failure(f"the worktree has uncommitted changes; nothing was removed:\n{dirty}")
    _must(_git("fetch", REMOTE), f"git fetch {REMOTE}")
    if branch and _git("merge-base", "--is-ancestor", branch, f"{REMOTE}/{BASE}").rc != 0:
        raise Failure(
            f"{branch} is not merged into {REMOTE}/{BASE} yet; nothing was removed. "
            "worktree-done runs after a human merged the PR."
        )
    _must(_git("worktree", "remove", str(path)), "git worktree remove")
    ok(f"removed the worktree {path}")
    if branch:
        # -D, not -d: -d compares with the local HEAD, which may not have the merge yet. The branch is proven merged
        # into origin/main above, so nothing is lost.
        res = _git("branch", "-D", branch)
        if res.rc == 0:
            ok(f"deleted the merged local branch {branch}")
        else:
            warn(f"kept the local branch {branch}: {res.out.strip()[-300:]}")
    say("worktree-done: done")
    return 0
