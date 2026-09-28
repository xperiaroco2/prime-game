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
