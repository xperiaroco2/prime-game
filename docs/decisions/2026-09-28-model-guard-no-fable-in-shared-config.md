# Model guard; reviewers on Opus, not Fable

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
On Max, Fable may use up to 50% of the weekly limit; on Pro it bills usage credits. Workflow agents inherit the
session model. KICKOFF §6 asks for the "strongest model" for `code-reviewer`.

## Decision
- Shared `.claude/settings.json` sets `"availableModels": ["opus", "sonnet", "haiku"]`. A request for any other model
  falls back with a warning.
- Subagent models: `godot-api-checker` sonnet, `test-runner` haiku, `code-reviewer` and `netcode-security-reviewer`
  **opus with effort high**. This deliberately deviates from "strongest".
- Fable appears in no shared file. Each human keeps usage credits off or sets a spend cap.
- No `Agent(model:fable)` deny rule: it only blocks the per-call parameter and adds nothing on top of
  `availableModels`.

## Alternatives
- No guard: any file or workflow naming Fable bills or silently downgrades.
- Force one subagent model (`CLAUDE_CODE_SUBAGENT_MODEL` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`): loses the
  haiku/sonnet cost routing.

## Consequences
- `availableModels` lists merge across settings files, so this is a guardrail, not enforcement; the engineer can opt
  into Fable personally.
- **Verified 2026-09-28:** an Agent call with `model: fable` (its meta file records `"model":"fable"`) was served by
  `claude-opus-5-5` according to its transcript. A control run without the guard was not done, because it would
  spend Fable.
