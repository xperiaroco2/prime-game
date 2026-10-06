# Lean reader and writer types for the workflows outside issue-task

- **Status:** Accepted
- **Date:** 2026-10-06
- **Deciders:** the engineer: yes to lean agent types and Sonnet gatherers for the night audit, the reports and the
  finders, a model choice of the same kind as N5 (the Sonnet publisher). Approved by the engineer:
  [#466 comment 6014948170](https://github.com/xperiaroco2/prime-game/issues/466#issuecomment-6014948170)
- **Tracking:** #466, #302; builds on the [lean agent types ADR](2026-10-04-lean-workflow-agent-types.md), whose
  "A third writable type needs a new ADR" this ADR answers

## Context
The [lean agent types ADR](2026-10-04-lean-workflow-agent-types.md) gave `issue-task` and `pr-rebase` typed agents
that start at about 20k tokens instead of about 57k. Every other workflow agent still ran as `workflow-subagent`:
in the 7 days from 2026-09-29 11:00 UTC, 84 of them (lens, te, scout, find, gather, audit, verify, synthesis),
whose first call less their own prompt averaged 55.4k tokens over 25.7 calls each, all but the night audit's
filing step on Opus (#466). Most of them only read: a night-audit lens, the weekly report's gatherers, a research
run's finders and scouts.

## Decision
- Two agent types in `.claude/agents/`, both with `disallowedTools` NotebookEdit, Agent and Skill, no `effort` (the
  call's or the session's applies), no `permissionMode`, no `memory`, and a short body (the shell facts, no Skill
  tool, the result once):
  - `lean-reader`: `tools: Read, Grep, Glob, Bash, PowerShell, WebFetch, WebSearch`, read-only (Edit and Write
    disallowed too), **`model: sonnet`**;
  - `lean-writer`: the reader's tools plus Edit and Write, `model: opus`. The third writable project subagent:
    `tools/runner/instructions.py` holds it to its allowlist as it does `task-implementer` and `task-publisher`.
- Who uses which, in a workflow script (`agent(prompt, {agentType, model, ...})`; the call's `model` wins over the
  file's):
  - finders, gatherers, scouts and lenses that read and report: `lean-reader` on Sonnet (the file's model);
  - skeptics and verifiers keep their model: `lean-reader` with `model: 'opus'`; the night audit's skeptic stays
    `night-skeptic`;
  - the agents that write the final issue, comment, report or synthesis keep their model: `lean-writer` (Opus), or
    with the model they had (the night audit's filing step: `model: 'sonnet'`);
  - an agent that needs a tool outside both lists (Monitor for a long job, a skill through the Skill tool) stays
    `workflow-subagent`.
- Not `issue-task` or `pr-rebase` (#458), not the UI and art repositories (their own issues).

## Model guard
Sonnet and Opus are in the shared `availableModels`
([model-guard ADR](2026-09-28-model-guard-no-fable-in-shared-config.md)). `agents-check` judges a lean reader or
writer by its file's `model:` unless the call named a model, as it does the reviewers.

## Consequences
- Expected about 1.2 points of the week per week (#466's estimate: about 1.0 from the smaller first call, 0.2 from
  Sonnet). Measured after one week on #466: first-call context (target about 21k), $ per agent, and how many agents
  failed for a missing tool (target none).
- Risk: a Sonnet finder misses something; the skeptic checks findings, not omissions. A prompt that needs a missing
  tool fails or improvises: such an agent goes back to `workflow-subagent`.

## Alternatives
- Only a reader: the synthesis and filing agents would stay at about 55k.
- Reusing `task-implementer` for ad hoc agents: Opus and Monitor/TaskStop for agents that never run a long job, and
  a name the `lean` arg of `issue-task` owns.
- Sonnet for skeptics too: the skeptic is the check on a Sonnet finder; left on Opus.
