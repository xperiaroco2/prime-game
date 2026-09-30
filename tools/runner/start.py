"""`start <n>` (docs/AGENT_WORKFLOW.md §4.1) and `worktree-done <n>`.

`start` puts the checkout on the task branch `<area>/<n>-<slug>` from `origin/main` (or back on it, when it exists),
or from `origin/<parent>` with `--base <parent>` for a task stacked on an open PR; it records that parent and its tip
in the git config keys `branch.<task>.primeBase` and `primeBaseTip`, where `publish` finds them before the PR exists.
It assigns the issue to the caller if nobody has it, and moves it to "In progress" on the board. It never discards
work: uncommitted changes stop it unless the caller says `--include` (carry them onto the task branch) or `--stash`.
For the engineer it makes a worktree `.claude/worktrees/<n>` instead, unless `--here` (or `--stash` / `--include`)
keeps the task in this checkout; the designer never gets one
(docs/decisions/2026-09-28-worktrees-only-for-parallel-sessions.md). `worktree-done <n>`
removes such a worktree once its branch is merged, or with `--pushed` once origin has the branch (a spike that is never
merged), and finishes a removal that Windows left half done.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import time
from pathlib import Path

from . import board, publish, sessions
from .common import ROOT, Failure, Result, ok, run, say, warn

REMOTE = "origin"
BASE = "main"
# The checkout start works on (tests point it at a temp repo).
REPO = ROOT
AREAS = ("core", "server", "net", "client", "voice", "content", "level", "tooling")
AREA_LABEL_RE = re.compile(r"^area:([a-z]+)$")
SLUG_MAX = 40
TIMEOUT = 120
# Deleting a worktree's ignored .godot/ import cache can take minutes on Windows.
REMOVE_TIMEOUT = 600


def _git(*args: str, cwd: Path | None = None, timeout: float = TIMEOUT) -> Result:
    return run(["git", *args], timeout=timeout, cwd=cwd or REPO)


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
    base: str | None = None,
) -> int:
    say(f"start #{number}" + (" (dry run: only fetches)" if dry_run else ""))
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
    existing = existing_branch(number)
    if existing and base:
        warn(f"--base {base} is ignored: {existing} already exists and is resumed as it is")
        base = None
    elif base and _git("rev-parse", "--verify", "--quiet", f"refs/remotes/{REMOTE}/{base}").rc != 0:
        raise Failure(f"{REMOTE} has no branch {base} (after a fetch); check the parent's name. Nothing was changed.")
    branch = existing or f"{area_of(labels, area, number)}/{number}-{slug(issue['title'])}"
    current = _git("symbolic-ref", "--quiet", "--short", "HEAD").out.strip()

    others = sessions.active_on(REPO)
    now = time.time()
    for other in others:
        say(f"        another session is active on this checkout: {other.describe(now)}")
    if worktree and not engineer:
        raise Failure("worktrees are for the engineer only (docs/AGENT_WORKFLOW.md §4.1)")
    if worktree and current == branch:
        raise Failure(f"{branch} is checked out here, so it cannot also have a worktree; work here, or switch away first")
    # The engineer gets a worktree for every task (issue #51): the agent works freely there, and the main checkout,
    # where the Godot editor and the humans' files live, stays protected. `--here`, `--stash` and `--include`
    # (which act on this checkout's changes) keep it here, and so does a branch already checked out here.
    use_worktree = worktree or (engineer and not (here or stash or include) and current != branch)
    if others and not use_worktree and not here and current != branch:
        raise Failure(
            "another Claude session is working on this checkout (above). Switching the branch here would put that "
            "session's next commit on this task's branch. Nothing was changed. Finish or close that session first; "
            "if it is really idle, run start again with --here."
        )

    parent = base or BASE
    if use_worktree:
        path = create_worktree(number, branch, dry_run, parent)
    else:
        here_key = str(Path(REPO).resolve()).lower()
        elsewhere = [p for p, b in listed_worktrees().items() if b == branch and p != here_key]
        if elsewhere:
            raise Failure(
                f"{branch} is checked out in the worktree {elsewhere[0]}; work there (EnterWorktree with that path). "
                "Nothing was changed."
            )
        switch(branch, current, stash=stash, include=include, dry_run=dry_run, number=number, parent=parent)
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
    say(f"start: {branch}" + (f" in the worktree {path}" if use_worktree else " is checked out here"))
    return 0


def record_parent(branch: str, parent: str, dry_run: bool) -> None:
    """Remember a stacked task's parent for publish, which rebases on it until the PR exists (then the PR's base
    wins). Local git config: a clone on the other machine has no record, but by then the PR usually exists."""
    if parent == BASE:
        return
    if dry_run:
        say(f"        would record {parent} as the base for publish ({publish.base_key(branch)})")
        return
    tip = _must(_git("rev-parse", f"{REMOTE}/{parent}^{{commit}}"), "reading the parent's tip")
    _must(_git("config", publish.base_key(branch), parent), "recording the base")
    _must(_git("config", publish.tip_key(branch), tip), "recording the parent's tip")
    ok(f"recorded {parent} as the base for publish and the PR")


def switch(
    branch: str, current: str, *, stash: bool, include: bool, dry_run: bool, number: int, parent: str = BASE
) -> None:
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
        action = f"create {branch} from {REMOTE}/{parent}"
    if dry_run:
        say(f"        would {action}" + (" after stashing the changes" if dirty and stash else ""))
        if action.startswith("create"):
            record_parent(branch, parent, dry_run)
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
        res = _git("switch", "--no-track", "-c", branch, f"{REMOTE}/{parent}")
    if res.rc != 0 or res.timed_out:
        raise Failure(
            f"git could not {action}; nothing was discarded"
            + (" (the stash still holds the changes: git stash list)" if dirty and stash else "")
            + f":\n{res.out.strip()[-600:]}"
        )
    ok(action[0].upper() + action[1:] + (", carrying the uncommitted changes" if dirty and include else ""))
    if action.startswith("create"):
        record_parent(branch, parent, dry_run)


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


def create_worktree(number: int, branch: str, dry_run: bool, parent: str = BASE) -> Path:
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
        source = f"{REMOTE}/{parent}"
        args = ["worktree", "add", "--no-track", "-b", branch, str(path), source]
    new = "--no-track" in args
    if dry_run:
        say(f"        would create the worktree {path} on {branch} from {source}")
        if new:
            record_parent(branch, parent, dry_run)
        return path
    _must(_git(*args), "git worktree add")
    ok(f"created the worktree {path} on {branch} from {source}")
    if new:
        record_parent(branch, parent, dry_run)
    return path


def _is_ancestor(commit: str, of: str) -> bool:
    return _git("merge-base", "--is-ancestor", commit, of).rc == 0


def _refuse_inside(path: Path) -> None:
    """Windows cannot delete a folder that is a process's current directory: git would unregister the worktree and
    then fail to delete it, leaving a half-removed worktree. So refuse before anything changes."""
    target = path.resolve()
    here = Path.cwd().resolve()
    if here == target or target in here.parents:
        raise Failure(
            f"run worktree-done from the main checkout: cd {main_checkout()} (the current folder {here} is inside "
            "the worktree, and Windows cannot delete it). Nothing was removed."
        )
    repo = Path(str(REPO)).resolve()
    if repo == target or target in repo.parents:
        raise Failure(
            f"this is the worktree's own runner; run the main checkout's instead: cd {main_checkout()}, then "
            "tools\\run.cmd worktree-done. Nothing was removed."
        )


def _refuse_sessions_in(path: Path) -> None:
    """Any live session in the worktree, busy or idle for days: it may still work there, and on Windows it keeps the
    folder open, so git would unregister the worktree and then fail to delete it."""
    inside = sessions.alive_in(path)
    me = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if me and any(s.session_id == me for s in inside):
        raise Failure(
            "this Claude session's own folder is the worktree, and Windows cannot delete it while the session runs. "
            "Nothing was removed. Archive this session, then run worktree-done from a session in the main checkout."
        )
    if inside:
        raise Failure(
            f"a Claude session is still open in the worktree: {inside[0].describe(time.time())}"
            + (f" and {len(inside) - 1} more" if len(inside) > 1 else "")
            + ". Nothing was removed. Archive or close that session in the Claude app, then run worktree-done again."
        )


def worktree_done(number: int, *, pushed: bool = False) -> int:
    say(f"worktree-done #{number}" + (" (--pushed)" if pushed else ""))
    path = worktrees_root() / str(number)
    _refuse_inside(path)
    key = str(path.resolve()).lower()
    known = listed_worktrees()
    if key not in known:
        return finish_leftovers(number, path, known)
    branch = known[key]
    _refuse_sessions_in(path)
    dirty = _git("status", "--porcelain", "--untracked-files=all", cwd=path).out.strip()
    if dirty:
        raise Failure(f"the worktree has uncommitted changes; nothing was removed:\n{dirty}")
    _must(_git("fetch", REMOTE), f"git fetch {REMOTE}")
    # The commit checked out there, not just the branch name: a detached HEAD can hold commits no branch has.
    head = _must(_git("rev-parse", "HEAD", cwd=path), "reading the worktree's HEAD")
    merged = _is_ancestor(head, f"{REMOTE}/{BASE}") and (not branch or _is_ancestor(branch, f"{REMOTE}/{BASE}"))
    if not merged and not pushed:
        raise Failure(
            f"{branch or 'the detached HEAD'} ({head[:10]}) is not merged into {REMOTE}/{BASE} yet; nothing was "
            "removed. worktree-done runs after a human merged the PR with \"Create a merge commit\" (a squash merge "
            "leaves the branch's own commits unmerged: then ask the human). A branch that is never merged (a spike) "
            "goes with --pushed once origin has it."
        )
    if not merged:
        # --pushed: the branch on origin keeps every commit, so removing the worktree loses nothing.
        if not branch:
            raise Failure(f"the worktree is on a detached HEAD ({head[:10]}); --pushed needs a branch. Nothing was removed.")
        # Asked live, not from refs/remotes: a branch deleted on origin keeps its stale tracking ref after a fetch.
        remote = _git("ls-remote", REMOTE, f"refs/heads/{branch}")
        if remote.rc != 0 or remote.timed_out:
            raise Failure(f"could not ask {REMOTE} for {branch}; nothing was removed:\n{remote.out.strip()[-300:]}")
        tip = remote.out.split()[0] if remote.out.strip() else ""
        if not tip:
            raise Failure(f"{REMOTE} has no branch {branch}, so it is not pushed; nothing was removed.")
        if not _is_ancestor(head, tip) or not _is_ancestor(branch, tip):
            raise Failure(
                f"{branch} ({head[:10]}) has commits that {REMOTE}/{branch} does not; nothing was removed. Push them "
                "first (tools\\run.cmd publish from the worktree), or ask the human."
            )
    res = _git("worktree", "remove", str(path), timeout=REMOVE_TIMEOUT)
    if res.rc != 0 or res.timed_out:
        half = key not in listed_worktrees()
        raise Failure(
            f"git worktree remove failed: {res.out.strip()[-600:]}"
            + (
                "\ngit already unregistered the worktree, but some program still has the folder open. Close it, then "
                f"run worktree-done {number} again: it removes the folder once it is empty (files left in it stop it)."
                if half
                else ""
            )
        )
    ok(f"removed the worktree {path}")
    if branch and merged:
        _delete_merged(branch)
    elif branch:
        ok(f"kept the local branch {branch}: it is not merged into {REMOTE}/{BASE} ({REMOTE}/{branch} has it too)")
    say("worktree-done: done")
    return 0


def _delete_merged(branch: str) -> None:
    # -D, not -d: -d compares with the local HEAD, which may not have the merge yet. The caller proved the branch
    # merged into origin/main, so nothing is lost.
    res = _git("branch", "-D", branch)
    if res.rc == 0:
        ok(f"deleted the merged local branch {branch}")
    else:
        warn(f"kept the local branch {branch}: {res.out.strip()[-300:]}")


def finish_leftovers(number: int, path: Path, known: dict[str, str]) -> int:
    """The worktree is no longer registered (a removal git began but Windows could not finish, or one done by hand).
    Finish what is left: an empty folder, and the issue's merged local task branch."""
    cleaned = False
    listed = _git("branch", "--list", "--format=%(refname:short)", f"*/{number}-*").out.split()
    ours = [b for b in listed if re.fullmatch(rf"[a-z][a-z0-9]*/{number}-[a-z0-9][a-z0-9._-]*", b)]
    fetched = False
    if ours:  # before anything is removed, so a failed fetch changes nothing
        res = _git("fetch", REMOTE)
        fetched = res.rc == 0 and not res.timed_out
        if not fetched:
            warn(f"git fetch {REMOTE} failed, so the local branches stay: {res.out.strip()[-300:]}")
    if path.exists():
        files = [p for p in path.rglob("*") if not p.is_dir()]
        if files:
            raise Failure(
                f"{path} is not a registered git worktree but still holds files (such as {files[0]}); nothing was "
                "removed. Ask the human what they are."
            )
        _refuse_sessions_in(path)
        try:
            shutil.rmtree(path)
        except OSError as exc:
            raise Failure(
                f"Windows could not delete the empty leftover folder {path} ({exc.strerror}): some program still has "
                "it (or a folder in it) open, such as a terminal or an editor. Close it, then run worktree-done again."
            ) from exc
        ok(f"removed the empty leftover folder {path}")
        cleaned = True
    checked_out = set(known.values())
    for branch in ours if fetched else []:
        if branch in checked_out:
            ok(f"kept the local branch {branch}: it is checked out in another worktree or the main checkout")
        elif _is_ancestor(branch, f"{REMOTE}/{BASE}"):
            _delete_merged(branch)
            cleaned = True
        else:
            ok(f"kept the local branch {branch}: it is not merged into {REMOTE}/{BASE}")
    if not cleaned:
        left = "; the branches above are kept" if ours else ", and nothing left over from one"
        raise Failure(f"no worktree for #{number} at {path}{left}")
    say("worktree-done: done")
    return 0
