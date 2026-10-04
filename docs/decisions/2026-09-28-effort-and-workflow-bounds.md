# Effort levels and bounded workflows

- **Status:** Accepted; launch approval and "one workflow per stage" amended by
  [2026-09-30-orchestrator-session.md](2026-09-30-orchestrator-session.md)
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
The Phase A research workflow ran 27 agents for 66 minutes and used about 70% of the engineer's 5-hour plan limit
(`docs/interventions/2026-09-28-engineer-phase-a-workflow-unbounded.md`). KICKOFF §10 describes one uninterrupted
ultracode run for foundation work and puts small tooling changes at medium.

## Decision
- Foundation stages (M0 execution, core architecture and content-API design before M2, project-wide audits): effort
  xhigh plus `ultracode` in that one prompt, **one workflow per stage**, human review between stages.
- Everyday `core/ server/ net/ voice/` work and **all tooling**: high. Docs, content data, routine fixes: medium.
- `workflowSizeGuideline: "small"` (fewer than 5 agents) in shared settings. Every workflow prompt states max agents,
  max turns or tool calls per agent, a time or token budget, and what to drop first. Before launch, the agent states
  the agent count and a rough cost and waits for a yes; exceeding the guideline needs explicit approval.
  (Amended 2026-10-04, #300: the manager of a stage or track launches without waiting for a yes up to 15% of
  the weekly limit, its restatement then a report; see
  [trust-based autonomy](2026-10-04-trust-based-autonomy-gated-merge-into-main.md).)
- **Amended 2026-09-30 (issue #91):** a stage that runs as parallel tasks with the engineer merging between them
  goes to the orchestrator session ([ADR](2026-09-30-orchestrator-session.md)): one manager session, one saved
  workflow per task. Its kickoff approves exceeding the size guideline and the stage's cost once, after the manager
  restates the waves, the agent count per workflow and the rough cost and the human says yes; the manager then does
  not ask before each task workflow. Other workflows still ask before each launch. "One workflow per stage" stays for
  a foundation stage with no mid-task human input.

## Alternatives
- High only for runner, guard and hooks; medium for other tooling (KICKOFF-literal for small changes).
- Workflows only on explicit request; foundation stages done interactively at high.

## Consequences
- Deviates from KICKOFF §10 twice: staged workflows instead of one run, and all tooling at high.
- `workflowSizeGuideline` is advisory and needs Claude Code 2.1.219 or later.
