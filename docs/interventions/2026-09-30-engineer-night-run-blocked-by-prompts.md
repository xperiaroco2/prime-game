# 2026-09-30: An agent must be able to work alone overnight

- **Who intervened:** the engineer.
- **Session:** the engineer's Claude session (Desktop, Opus 5.5), the overnight workflow `overnight-wave-2`
  (run `wf_65292cf4-8b4`, M2 tracking issue #30), in bypass permissions mode. Recurrence of
  `2026-09-28-engineer-unattended-hour.md`.

**What happened.**
- The workflow's agents ran 309 shell commands (counted at the second replay on 2026-09-30). Four of them stopped on
  a permission prompt from an ask rule in `.claude/settings.json`; ask rules prompt in every mode, bypass included:
  - 23:45, the publisher of #45: `rm -rf $S`, its own temporary folder in the scratchpad (`Bash(rm -r*)`);
  - 23:59, `godot-api-checker` on #46: `rm -rf "$SP/sandbox"`, also in the scratchpad (`Bash(rm -r*)`);
  - 00:17, the publisher of #33: `git reset -q`, which only unstages (`Bash(git reset *)`);
  - 00:59, the publisher of #46: `rm -r tests/integration/tmp` in `.claude/worktrees/46` (`Bash(rm -r*)`). It had
    made that folder for a probe test (`tests/integration/tmp/probe_test.gd`, run with
    `tools/run.sh test tests/integration/tmp/probe_test.gd`), because GdUnit4 runs only tests under `res://`.
- The engineer happened to open Claude Code at midnight and approved the first three. Nobody answered the fourth:
  #46 never reached its PR that night (8 local commits and uncommitted fixes waited until morning). The engineer
  asked for unattended runs not to stop on harmless commands, and for the checks to judge a command's target rather
  than its text (issue #47).
- The thin guard alone would have asked for none of these commands. With the target check of #47 it still asks for
  the fourth, a delete inside the project; the scratch folder below removes the reason to make such a folder.

**Why it happened.**
- The 2026-09-28 rule tested each ask rule against "can the agent still work alone for an hour?". An hour with the
  engineer nearby tolerates an occasional prompt; a night does not, and the test never replayed a real unattended
  run against the rules.
- `Bash(rm -r*)` and `Bash(git reset *)` match text. They cannot tell a delete of the agent's own scratch folder from
  `rm -rf .`, or unstaging from `git reset --hard`, so they stop both.
- A probe test must live inside the project, and there was no agreed place for it: the agent picked a folder among
  the real tests, whose delete looks the same as deleting real work.

**Rule adopted.**
1. The test for a new ask or deny rule is "can an agent work alone overnight?". Replay the latest unattended run's
   transcripts against the rule; if it would have stopped routine work, judge the command by its target in the
   guard instead of by its text.
2. Recursive deletes and `git reset` are judged by the guard: a delete asks only in the project (the main checkout or
   a worktree), and `git reset` asks only when it discards work or moves the branch. Scratch deletes and unstaging
   pass.
3. Temporary files go only to the session's scratchpad or, when they must be under `res://` (a probe test, a probe
   scene), to the gitignored `tests/scratch/` of the checkout the agent works in. Deleting either never prompts, in
   the main checkout and in every worktree; full `check`, `test` and `lint` runs leave `tests/scratch/` out, and
   `tools/run.cmd test tests/scratch/<file>` runs a probe there. No other temporary folder inside the project.

**Where the rule lives now.**
- This entry.
- Root `CLAUDE.md`, "Stop and ask before" (rule 1, replacing the one-hour test of 2026-09-28) and "Shell" (rule 3).
- `.claude/rules/tests.md`, "Running" (rule 3, for probe tests).
- `docs/AGENT_WORKFLOW.md` §8.1 (rule 1), §8.2 (rules 2 and 3) and §7 (rule 3).
- `tools/runner/guard.py` and its selftests (rules 2 and 3); the text rules leave `.claude/settings.json` in the same
  PR. `.gitignore`, `tools/check/check_project.gd`, `tools/runner/gdunit.py` and `common.py` (rule 3).
- `docs/decisions/2026-09-28-permissions-and-thin-guard.md` (amended 2026-09-30).
