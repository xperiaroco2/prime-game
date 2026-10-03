# Effort levels and bounded workflows

- **Status:** Accepted; launch approval and "one workflow per stage" amended by
  [2026-09-30-orchestrator-session.md](2026-09-30-orchestrator-session.md); efforts amended 2026-10-04 (#302
  decision 3, option (c); #308)
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
- **Amended 2026-09-30 (issue #91):** a stage that runs as parallel tasks with the engineer merging between them
  goes to the orchestrator session ([ADR](2026-09-30-orchestrator-session.md)): one manager session, one saved
  workflow per task. Its kickoff approves exceeding the size guideline and the stage's cost once, after the manager
  restates the waves, the agent count per workflow and the rough cost and the human says yes; the manager then does
  not ask before each task workflow. Other workflows still ask before each launch. "One workflow per stage" stays for
  a foundation stage with no mid-task human input.
- **Amended 2026-10-04 (#308; the engineer's answer to decision 3 on #302, option (c), chat with the manager
  session):**
  - `godot-api-checker` runs at effort high, set in its agent file like `code-reviewer` and
    `netcode-security-reviewer`. It set none, so inside a workflow it inherited the manager's xhigh and cost more per
    agent than the Opus code review ($1.28 against $1.08, #302's report of 2026-10-04). The workflows pass a reviewer
    no effort unless a launch's `efforts` names its role, so the agent file's applies; a runner test asserts that every
    reviewer they route sets its own.
  - Manager sessions of every track (AGENT_WORKFLOW §7.1), and the art and UI sessions, run at high instead of xhigh.
    The human sets it in each session's settings; `effortLevel` stays out of shared settings.
  - Unchanged: implementers (high; xhigh for a design task), design tasks, and the reviewers' models.
  - **A one-wave trial of a cheaper publisher.** `issue-task` takes `models.publish_clean` (a model from the shared
    list: Sonnet) and applies it only to the full publisher of a run that the reviews, the test review and the
    skeptics left with no blocker or major open: a skeptic-refuted finding is closed, one over the skeptic limit stays
    open, and minors, nits and the plan critique's findings do not count. Never to a design task or a run stopped by
    `mutants`. The manager passes it on every non-design launch of the one wave the kickoff names, and not after it
    until the engineer keeps it; a fresh relaunch of a trial run drops it (an Opus publisher, as before).
  - **How the trial is judged**, per run, from the result's `publish_clean` field (`applied`, `why`, `open`, `model`,
    `effort`): CI red rounds (failed CI runs on the PR's branch before its last green, `gh run list --branch`), the
    publisher's fix rounds and its `fixed` and `not_fixed` lists, and the publisher's $ and output tokens from
    `tools\run.cmd metrics`, against comparable earlier clean runs with Opus publishers. A trial run that needed a
    relaunch counts as a failure of the trial (its first run's numbers), not as a second trial run. The manager reports
    on #302 after the wave; the engineer keeps or drops it. No keep-or-drop threshold is set in advance.

## Alternatives
- High only for runner, guard and hooks; medium for other tooling (KICKOFF-literal for small changes).
- Workflows only on explicit request; foundation stages done interactively at high.

## Consequences
- Deviates from KICKOFF §10 twice: staged workflows instead of one run, and all tooling at high.
- `workflowSizeGuideline` is advisory and needs Claude Code 2.1.219 or later.
- Since 2026-10-04 an agent file's `effort` is part of the routing: one without it runs at its launcher's effort. The
  baseline (the pipeline v2 ADR's per-role table) shows `code-reviewer` at high under xhigh managers, so the field is
  honoured inside workflows; the next wave's `metrics` should show `godot-api-checker` at high.
- The publisher trial adds no agent and needs no allowance for a model beyond the shared list: the kickoff only names
  its wave.
