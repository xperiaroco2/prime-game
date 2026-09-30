# 2026-09-30: Agents have full freedom in their own worktree and consult only on design

- **Who intervened:** the engineer.
- **Session:** the engineer's manager session (Desktop, Opus 5.5), in chat on 2026-09-30, after the overnight run
  `wf_65292cf4-8b4` and the path-aware guard of #47 (PR #53); tracked as issue #51 (M2, tracking issue #30).

**What happened.**
- #47 moved recursive deletes and `git reset` from text ask rules to the guard, but every other command that
  discards work or rewrites history (`git checkout`, `restore`, `clean`, `rebase`, `stash drop`, `branch -d`,
  `worktree`, `git -c`) still had an ask rule, and a delete inside a worktree still asked. An agent in its own
  worktree could still stop, unattended, on a `git rebase origin/main` or a `git checkout -- file` of its own work.
- The engineer said that agents should have full freedom inside their own worktree and task branch: every git
  operation and every delete there runs without a prompt, and agents stop only for design questions and for what
  reaches beyond their own worktree and branch. Every engineer task should get its own worktree, so the freedom
  always applies and the main checkout (the Godot editor and the humans' files) stays protected. He approved the
  design in chat on 2026-09-30.

**Why it happened.**
- The rules asked "is this command destructive?", not "whose work can it destroy?". Inside the agent's own worktree
  on its task branch the only work at risk is the agent's own, which is committed or reproducible; the risk is in
  the main checkout, in another session's worktree and on other branches. The text rules could not see that
  difference, so they stopped both.
- Worktrees were made only when another session was active, so an agent often worked in the main checkout, where
  freedom would have been unsafe.

**Rule adopted.**
1. Inside your own worktree and on your task branch, git and deletes are free: reset, checkout, restore, clean,
   rebase (not interactive), stash drop of your own entries, deleting your task branch's helper branches, and
   recursive deletes run without asking. Stop and ask only for design and other human-reserved decisions,
   dependencies, the other owner's area, anything that costs money, and what reaches beyond your own worktree and
   branch.
2. The guard enforces rule 1 by target: those commands ask in the main checkout, in another worktree, on another
   branch, and for stash entries made on another branch; the ask rules for them leave `.claude/settings.json`. The
   deny rules (pushes to `main`, remote deletes, `--mirror`/`--all`/`--prune`, `gh pr merge`, `hooksPath`) and the
   asks on `.claude/settings*.json` and `addons/` stay.
3. Every engineer task gets its own worktree: `start` makes `.claude/worktrees/<n>` by default, and `--here` is the
   exception. A task session whose shell starts in the main checkout moves into its worktree with `cd` (Git Bash)
   or `Set-Location` (PowerShell) at the start of every command.

**Where the rule lives now.**
- This entry.
- Root `CLAUDE.md`, "Stop and ask before" (rule 1) and the `start` row of "Commands" (rule 3).
- `docs/AGENT_WORKFLOW.md` §4.1 (rule 3), §8.1 and §8.2 (rules 1 and 2).
- `tools/runner/guard.py`, `tools/runner/hooks.py` and their selftests (rule 2); `.claude/settings.json` (rule 2);
  `tools/runner/start.py` and its tests (rule 3).
- `docs/decisions/2026-09-28-permissions-and-thin-guard.md`, `2026-09-28-unattended-work-permissions.md` and
  `2026-09-28-worktrees-only-for-parallel-sessions.md` (amended 2026-09-30).
