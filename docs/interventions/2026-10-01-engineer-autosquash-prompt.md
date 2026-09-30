# 2026-10-01: A no-editor autosquash in the own worktree must not prompt

- **Who intervened:** the engineer.
- **Session:** the M3 manager session (Claude Code Desktop, Opus 5.5, bypass permissions mode), the night run of
  stage 3 (#96); the workflow `issue-task` for #97 (run `wf_e9541660-55a`). Recurrence of
  `2026-09-30-engineer-night-run-blocked-by-prompts.md`.

**What happened.**
- At 01:21 local time #97's implementer folded a fix into its earlier commit, in its own worktree on its task branch:
  `cd /d/prime-game/.claude/worktrees/97 && git add -A && git commit -q --fixup=HEAD && GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash origin/release/m3`.
- The guard asked, because it asks for every interactive rebase ("it opens an editor, which an agent cannot use").
  The engineer, still awake before the night, saw the prompt, approved it and asked what it was and to fix it
  properly while present.
- With `GIT_SEQUENCE_EDITOR=:` no editor opens, and the same rebase without `-i` passes there (#51). Asleep, nobody
  would have answered: #97's workflow, and the stage behind it, would have waited until morning.

**Why it happened.**
- The guard judged the interactive rebase by its flag, not by what it does. The reason for the rule, an editor the
  agent cannot use, does not hold when the command sets the todo editor to a no-op, which is the usual way to
  autosquash without a terminal.

**Rule adopted.**
- An interactive rebase whose todo editor is a no-op (`:` or `true`, from `GIT_SEQUENCE_EDITOR`,
  `-c sequence.editor=`, `GIT_EDITOR` or `-c core.editor=`, in git's order) is judged like any other rebase: it passes
  in the own worktree on the task branch and asks everywhere else. Every interactive rebase that opens an editor
  still asks, and so do `--update-refs`, `--exec` and a rebase that names another branch.

**Where the rule lives now.**
- This entry.
- `tools/runner/guard.py` (`git_rebase`, `git_sequence_editor`, the module docstring) and its selftests.
- `docs/AGENT_WORKFLOW.md` §8.2.
