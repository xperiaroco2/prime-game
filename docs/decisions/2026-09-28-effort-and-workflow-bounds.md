# Effort levels and bounded workflows

- **Status:** Accepted
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

## Alternatives
- High only for runner, guard and hooks; medium for other tooling (KICKOFF-literal for small changes).
- Workflows only on explicit request; foundation stages done interactively at high.

## Consequences
- Deviates from KICKOFF §10 twice: staged workflows instead of one run, and all tooling at high.
- `workflowSizeGuideline` is advisory and needs Claude Code 2.1.219 or later.
