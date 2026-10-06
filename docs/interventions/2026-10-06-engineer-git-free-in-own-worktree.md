# 2026-10-06: Any git command in a task's own worktree on its own branch must not prompt

- **Who intervened:** the engineer.
- **Session:** the meta-optimization manager session `7a1fd9e0` (Claude Code Desktop, Opus 5.5, bypass permissions
  mode), the morning after the night run that rebased #445 (`pr-rebase`). Recurrence of
  `2026-10-01-engineer-autosquash-prompt.md` and `2026-09-30-engineer-full-freedom-in-own-worktree.md`.

**What happened.**
- At 21:56 UTC on 2026-10-05 the fix agent of #445's `pr-rebase` reworded a commit in its own worktree 425, on its
  own task branch, with a `sed` sequence editor that added an `exec git commit --amend -F <message>` line to the todo:
  `GIT_SEQUENCE_EDITOR="sed -i '/^pick 2c3e0d21/a exec git commit -q --amend ...'" git rebase -q -i origin/main`.
- The guard asked ("an interactive rebase opens an editor"): since #104 only `GIT_SEQUENCE_EDITOR=:` or `true`
  passed. Nobody was awake; the run waited until 07:19 UTC, and asked again for the next rebase at 07:25.
- The engineer, in the morning: "I allow everything; git is protected on GitHub; why does the system still ask?"

**Why it happened.**
- #104 freed only a no-op sequence editor, and judged every other editor setting as one an agent cannot use. A sequence
  editor that is a script (`sed`, Python on 2026-10-01), `-c core.editor=true` (2026-10-03, 23 minutes) and the shells'
  own `GIT_EDITOR=true` open nothing an agent waits on, and the work at risk in the own worktree on its task branch is
  the agent's own: GitHub's branch protection and the pre-push hook keep `main` and force pushes safe.
- The week's data (`tools\run.cmd permissions --observed --since 2026-09-28`): 22 git asks, of which 6 protected
  nothing (5 such rebases and a `git checkout --ours core/events/$f.gd` loop whose pathspec the guard could not
  resolve).

**Rule adopted.**
- In a task's own worktree on its own task branch every git command passes: an interactive rebase whatever editor it
  names, a rebase that names `HEAD` or `@` (git rebases a detached HEAD), a pathspec the guard cannot resolve (judged by
  the folder before its unknown part: git refuses one outside its repository), and `git worktree remove|move` of an
  absolute path inside the worktree. The guard still asks for the main checkout, other worktrees and branches, the
  protected paths, `git stash drop|clear` of entries it cannot show are the agent's, `rebase --update-refs`, `rebase
  --exec` (a push inside it gets past the deny rules; a sequence editor can add such lines too, and the pre-push hook
  and GitHub's branch protection stop a push to `main` either way) and `git -c core.hooksPath`. Push rules, deny rules
  and the pre-push hook are unchanged. Agents keep writing `GIT_SEQUENCE_EDITOR=:` (root `CLAUDE.md`, Shell), so a
  machine whose git config names an editor never opens it.

**Where the rule lives now.**
- This entry.
- `tools/runner/guard.py` (`git_rebase`, `git_discards`, `Paths.literal_place`, `git_worktree`, the module docstring)
  and its selftests.
- `docs/AGENT_WORKFLOW.md` §8.2; `docs/decisions/2026-09-28-permissions-and-thin-guard.md` (amended 2026-10-06).
