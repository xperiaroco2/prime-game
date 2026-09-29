# Worktrees only for parallel sessions

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Decision
`tools\run.cmd start` creates `.claude/worktrees/<n>` on the task branch **only when another Claude session is already
active on this checkout**, for the engineer only. `tools\run.cmd worktree-done <n>` removes it after merge. An open
Godot editor is not a trigger (see the editor-convention ADR). The designer never uses worktrees.

## Alternatives
Always a worktree (a cold `--import` each time), or never (parallel sessions collide in one folder).

## Consequences
Runner-made worktrees use `git worktree add`, so LFS content arrives normally. Archiving a session or `ExitWorktree`
does not remove worktrees entered by path; hence `worktree-done`.

## Detection (built in M0 stage 6, 2026-09-29)
Checked live on Claude Code 2.1.284 (Desktop): every running session keeps `~/.claude/sessions/<pid>.json` with
`cwd`, `sessionId`, `status` (`busy` while it works, `idle` while it waits for its human) and `updatedAt` (ms); a
session sees its own id in `CLAUDE_CODE_SESSION_ID`. Desktop sessions that were finished but never archived stay
alive and idle: on the engineer's machine three such sessions from earlier stages were running on `D:\prime-game`.

`start` counts another session as active on this checkout when its process is alive with the creation time the file
records as `procStart` (a pid can be reused; the two were equal for all four live sessions), its `cwd` is the
checkout or a folder in it but not one of its worktrees, it is not the calling session, and it is `busy` or was
updated within the last hour. The hour keeps an idle session that is mid-task (waiting for an answer) in, and old
unarchived sessions out. The engineer is the `gh` login that owns the repo. `--worktree` and `--here` override the
detection. The designer never gets a worktree: with another session active, `start` stops and changes nothing until
the human closes it or confirms it is idle (`--here`). A session that moved into a worktree with EnterWorktree may
still list the main checkout as its `cwd`; that errs towards a worktree.

The risk left: a session idle for more than an hour in the middle of a task, whose checkout `start` then switches to
another branch. Its own next `git status` shows the new branch. Committed work is safe, and uncommitted changes make
`start` stop and ask.

`worktree-done <n>` refuses while a session works in the worktree, with uncommitted changes, or when the worktree's
HEAD (a detached one included) or branch is not merged into `origin/main`. It then removes the worktree and deletes
the merged local branch. Ignored files such as `.godot/` do not block the removal (checked with git 2.49).

## Spikes and half-done removals (2026-09-29, #27)
The M1 spike branches are never merged, so `worktree-done --pushed` removes a worktree whose branch (not a detached
HEAD) is fully on `origin/<branch>`, and keeps the local branch unless it is merged; it never deletes a remote branch.
On #19 the caller's shell sat in the worktree: git unregistered it, Windows refused to delete the folder, and a rerun
said "no worktree". Now `worktree-done` refuses up front when the current folder or the runner's checkout is inside
the worktree, and when the worktree is unregistered it removes an empty leftover folder (one with files stops it) and
the issue's merged local task branch. On #27 the same happened with no shell inside: the finished spike sessions,
never archived and idle for 3 to 7 hours, were still alive with the worktree as their `cwd`, and Windows kept each
folder. So `worktree-done` refuses while **any** live session has its `cwd` in the worktree, however long idle and
the calling session included (not the one-hour window `start` uses); the human archives or closes it in the app
first. When git still fails after unregistering, the message says so, and a rerun removes the folder once it is empty
(files left in it stop it). `--pushed` asks `origin` live (`ls-remote`), so a stale tracking ref of a branch deleted
there does not count as pushed.
