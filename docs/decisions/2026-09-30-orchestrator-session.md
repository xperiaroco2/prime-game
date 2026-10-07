# The orchestrator session: one manager session per stage, one workflow per task

- **Status:** Accepted
- **Date:** 2026-09-30
- **Deciders:** the engineer (chat with the M2 manager session, 2026-09-30)
- **Amended 2026-10-01:** the manager merges task PRs into the stage's `release/m<k>` branch, and humans merge that
  branch into `main` ([release branch per milestone](2026-10-01-release-branch-per-milestone.md)); "the manager
  never merges" below now means never into `main`.
- **Amended 2026-10-04 (#300):** the manager also merges into `main` through the gate of
  [trust-based autonomy](2026-10-04-trust-based-autonomy-gated-merge-into-main.md), closes issues and runs the
  housekeeping; the human answers, gives each milestone's go and merges the gate's exceptions.
- **Amended 2026-10-07 (#511):** the manager session runs from a kickoff the engineer pastes, without "ultracode",
  which is only the opt-in for workflows and whose "token cost is not a constraint" guidance works against the token
  efficiency track; the kickoff says "one task = one issue-task workflow" with the approved agent count, and the
  manager's effort stays high. "In ultracode" below is history. Approved by the engineer:
  [#170 comment 6033930486](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6033930486); the rules
  every track's manager follows: [docs/MANAGERS.md](../MANAGERS.md).

## Context
On 2026-09-30 one Claude Code session in ultracode ran M2's stage 2 as a manager: from a single kickoff message it
started each task's worktree, launched one workflow per issue (implementer, fresh reviewers, publisher), at most
three at a time, relayed "Needs the engineer" questions, rebased open PRs after each merge and reported on #30. The
engineer only merged and answered. About 20 workflows ran that day (stage 2's ten issues, fillers and follow-ups),
25 to 60 minutes and 450k to 900k subagent tokens each. The engineer asked to keep the method and to run M3 the same
way in a new session. This ADR amends the effort ADR ([2026-09-28](2026-09-28-effort-and-workflow-bounds.md)),
which prescribed one workflow per stage with human review between stages and a yes before each launch.

## Decision
- A stage (or a list of issues) is run by one **manager session** in ultracode, following the project skill
  `orchestrate-stage`, from a kickoff message that states the scope, order, concurrency cap, per-agent bounds, the
  approval to exceed the size guideline with the cost for the whole stage, the rules, the engineer's standing
  decisions and the reporting.
- Each task is one run of the saved project workflow `issue-task` (`.claude/workflows/issue-task.js`),
  parameterised by `args`; a semantic conflict after a merge is one run of `pr-rebase`. Both are ordinary project
  files, reviewed like tooling; they are the orchestration, not planning files, so the
  [no-framework ADR](2026-09-28-no-workflow-framework.md) holds: moving state stays in GitHub.
- The humans keep the gates: they merge, answer the batched questions and write the kickoff. The manager never
  merges, never closes issues and never edits the plan issue's body.
- The size guideline stays `small` in shared settings. The kickoff approves the larger task workflows and the
  stage's cost once: the manager restates the waves, the agent count per workflow and the rough cost, waits for the
  human's yes, and then does not ask before each `issue-task` or `pr-rebase` run. This amends the effort ADR's "a
  yes before each launch" for these workflows only (root `CLAUDE.md`, `docs/AGENT_WORKFLOW.md` §7).

## Alternatives
- **One big workflow per stage** (the 2026-09-28 ADR's model): no mid-run human input, so the engineer's answers
  and merges cannot shape later tasks; a failure late in the script reruns finished work; rebases after merges have
  no place in it.
- **A human running each task session by hand** (`start-task` … `finish-task`): the engineer becomes the scheduler,
  one task at a time, and loses the parallelism and the fresh reviews done without asking.

## Consequences
- Cost: the heaviest mode the project has; a stage uses a large share of a plan's limits, so the kickoff states
  the budget and what to drop first. Workflows pause at a usage limit when `autoContinueAtUsageLimit` is on, and a
  crashed run resumes with `resumeFromRunId` and the same args.
- Parallel PRs conflict: ownership of shared files is split up front, and the manager rebases after each merge
  (inline for docs and test lists, `pr-rebase` for semantic conflicts).
- The human stays the merge gate and the source of design decisions; the manager's value depends on them merging
  and answering promptly.
- Tasks that edit `.claude/` or `addons/` still prompt (`.claude/settings*.json` and `addons/` in every mode, other
  `.claude/` paths outside bypass) and run only while a human is present.
- The scratchpad is per session, so the handover to a new manager session goes through GitHub: each wave comment
  lists the running runs with their args.
