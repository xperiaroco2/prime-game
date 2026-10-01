# 2026-10-01: No stash for agents, and the manager never leaves its shell in a worktree

- **Who intervened:** the engineer.
- **Session:** the M3 manager session (Claude Code Desktop, Opus 5.5, bypass permissions mode), the night run of
  stage 3 (#96); the workflow `issue-task` for #97 (run `wf_e9541660-55a`), its publisher. Recurrence of
  `2026-09-30-engineer-night-run-blocked-by-prompts.md` and `2026-10-01-engineer-autosquash-prompt.md`.

**What happened.**
- At 02:10 local time #97's publisher, in its own worktree, set a fix aside in the stash and then dropped it:
  `ref=$(git stash list ... | grep a97-jumps-core | cut -d' ' -f1) && git stash drop -q "$ref"`. The stash is
  shared by every worktree of the clone, and the guard lets a drop pass only for an entry it can show was made on
  the task branch; a computed name shows nothing, so it asked, rightly, from any working directory.
- At 02:14 the same publisher folded a fix in with an interactive autosquash in its own worktree
  (`export GIT_SEQUENCE_EDITOR=: && ... git rebase -q -i --autosquash fbe00d9~1`, which passes there since #104),
  and the guard asked "outside this session's own worktree". The manager session had left its own shell in its
  `.claude/worktrees/release-m3` worktree (a `cd` in an earlier call). A workflow agent's hooks receive the manager
  session's working directory, so the guard took `release-m3` as the session's own worktree and the publisher's
  `97` as someone else's.
- The proof is a replay with `tools\run.cmd permissions`: the 02:14 command, from the transcript recorded with the
  manager in `release-m3`, asked; with the working directory `D:\prime-game` it passed. Replayed again on 2026-10-01
  for this entry through `guard.check` of `main`: the stash drop asks from both working directories, the rebase
  only from `release-m3`.
- The engineer, not yet asleep, answered both prompts. Asleep, nobody would have: #97's publisher, and the stage
  behind it, would have waited until morning. From then on the manager entered worktrees only in subshells and every
  launch's notes said not to use `git stash`; no prompt came after that.

**Why it happened.**
- Agents used the stash to set work aside, as a human would. In a clone with many worktrees the stash is one shared
  list, so an entry's name is the only thing that says whose it is, and a computed name says nothing.
- The guard decides "the own worktree" from the session's working directory, which the manager owns and the
  workflow agents only inherit. Nothing told the manager that where its shell stands decides what its agents may do.

**Rule adopted.**
1. Agents never use `git stash`. To set work aside: a WIP commit, later `git reset --soft HEAD~1`. To fold a fix into
   an earlier commit: `git commit --fixup=<sha>`, then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash
   origin/<base>`. Both are free in the own worktree on the task branch.
2. The manager session never leaves its shell inside a worktree: it works there through Git Bash subshells
   (`(cd <wt> && ...)`), `git -C <wt>`, or PowerShell `Push-Location <wt>; ...; Pop-Location`.

**Where the rule lives now.**
- This entry.
- Root `CLAUDE.md`, "Shell" (rule 1).
- `.claude/workflows/issue-task.js` and `.claude/workflows/pr-rebase.js`, the agents' rules (rule 1).
- `.claude/skills/orchestrate-stage/SKILL.md` §9 (rules 1 and 2).
- `docs/AGENT_WORKFLOW.md` §8.2 (rule 2).
