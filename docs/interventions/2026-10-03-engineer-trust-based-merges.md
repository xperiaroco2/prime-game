# 2026-10-03: The manager merges into main itself, through a gate

- **Who intervened:** the engineer.
- **Session:** the AI productivity manager session (the engineer's Claude session, Desktop, Opus 5.5), 2026-10-03
  ~20:00 UTC, day 3 of the AI productivity track (#170); the same message to the M5 manager session at ~20:30 UTC.
  Recorded on #170 (comment 5972652086) and #300.

**What happened.**
- The managers stopped at every PR into `main` and asked the engineer to merge it: the tooling track's PRs one by
  one, each milestone's closing PR, and the questions batched with them. A night's work waited for the morning's
  clicks.
- The engineer said he merges every PR without reading it, so the click is load, not a check, and asked to rethink
  the process on trust in the agent: the manager merges into `main` itself through a deterministic gate, keeps
  reporting what happens, and stops only for decisions that need him. He answered three questions (scope with its
  exceptions, release branches stay, the engineer's agents only) and four more of the M5 manager (the manager closes
  issues and does the housekeeping; workflows launch without a "yes" within 15% of the week; no "Publish now?"; one
  chat line per merge and a revert through the same gate; the stop word "стоп мерджі").

**Why it happened.**
- "Only humans merge into `main`" (2026-09-28) was written when nothing else checked a PR. Since then the fresh
  reviews, CI, `verify` in `publish` and `merge-check` check every PR, and the human click checked nothing they had
  not. The rule outlived its reason, and the agents followed it to the letter.
- The instruction files listed what to ask about, not what the agent may decide, so the managers asked about minor,
  reversible steps too.

**Rule adopted.**
- [Trust-based autonomy: the manager merges into main through a
  gate](../decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md): `tools\run.cmd merge <pr> --base main`
  merges through GitHub when its gate passes; the exceptions (the designer's area, the permission and safety files,
  ADRs) and the designer's PRs stay a human's; the decision tiers (decide and report; decide and tell at once; ask and
  wait) say what the agent decides alone.

**Where the rule lives now.**
- The ADR above, and dated amendments to `2026-09-28-humans-merge-prs.md`, `2026-10-01-release-branch-per-milestone.md`,
  `2026-09-30-orchestrator-session.md` and `2026-10-02-ai-productivity-baseline-and-pipeline-v2.md`.
- `tools/runner/merge.py` (`merge <pr> --base main [--dry-run]`) and its tests in `tools/runner/tests/test_merge.py`.
- Root `CLAUDE.md`: the `merge` row of the commands table, definition of done 4 and 5, and "Stop and ask before",
  reworded in place within the 150-line launch budget.
- `docs/AGENT_WORKFLOW.md` §4.2 (item 4), §7.1 (Git flow, Parallel tracks, The human), §8.3, §9 and §10 (Merging).
- `.claude/skills/orchestrate-stage/SKILL.md` §1, §2, §4, §5, §6, §8 and the kickoff template;
  `.claude/skills/finish-task/SKILL.md` steps 4 and 8; `.claude/skills/onboard/SKILL.md`.
- The pre-push hook's message (`.claude/githooks/pre-push`): pushes to `main` stay blocked.
