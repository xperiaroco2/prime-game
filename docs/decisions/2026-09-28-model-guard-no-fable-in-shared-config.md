# Model guard; reviewers on Opus, not Fable

- **Status:** Accepted; amended 2026-10-02 by amendment A (the engineer's answer N1 (b), #183); amended 2026-10-04
  (#308: `godot-api-checker`'s effort, the publisher trial under amendment A)
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
On Max, Fable may use up to 50% of the weekly limit; on Pro it bills usage credits. Workflow agents inherit the
session model. KICKOFF §6 asks for the "strongest model" for `code-reviewer`.

## Decision
- Shared `.claude/settings.json` sets `"availableModels": ["opus", "sonnet", "haiku"]`. A request for any other model
  falls back with a warning.
- Subagent models: `godot-api-checker` sonnet (effort high since #308), `test-runner` haiku, `code-reviewer` and `netcode-security-reviewer`
  **opus with effort high**. This deliberately deviates from "strongest".
- Fable appears in no shared file, except as amendment A says. Each human keeps usage credits off or sets a spend
  cap.
- No `Agent(model:fable)` deny rule: it only blocks the per-call parameter and adds nothing on top of
  `availableModels`.
- **Amendment A** (2026-10-02, N1 (b) of the
  [pipeline v2 ADR](2026-10-02-ai-productivity-baseline-and-pipeline-v2.md), item 5; applied by #183):
  - The shared `availableModels` stays `["opus", "sonnet", "haiku"]`. The engineer may add `fable` to
    `availableModels` in his own `~/.claude/settings.json`; the designer's machine does not.
  - Workflows take an optional `models` argument per role; no default names a model outside the shared list, and the
    workflow tests assert it.
  - A manager passes Fable only where the kickoff allows it: stage designs, a second review of PRs that touch core/,
    server/, net/ or tests/harness/, audits, and a task that went red twice. Budget: at most half of the weekly Fable
    window across all tracks; each wave comment reports its use from get_usage (the desktop app's session-management tool:
    its plan limits list the per-model weekly windows with % used). Managers stay on the shared models.
  - Fable may be named in ADRs and in issue and PR comments (kickoffs, launch arguments in the handover data, usage
    reports). It stays out of `.claude/` (settings, agents, workflows, skills, rules), `.github/`, every CLAUDE.md
    file and any workflow argument's default; in `tools/` only the runner's model-family table
    (`agents_check.FAMILIES`) names it, as on main, plus the runner tests that use it as the example of a model
    outside the shared list and comments that link this ADR by its file name.
  - Usage credits stay off or capped (unchanged). `agents-check` proves which model served each agent: it reads the
    shared and the user-scope `availableModels`, accepts a model from the user list when the requested model served,
    and still fails a model in neither list that served.
  - **2026-10-04 (#308; #302 decision 3, option (c)):** the one-wave publisher trial. Its model is from the shared
    list (Sonnet), so it needs no allowance under this amendment; the kickoff only names the trial's wave. Any other
    `models` use still follows the orchestrate-stage skill's §3 (only where the kickoff allows it). `issue-task`
    applies `models.publish_clean` only to the full publisher of a run with no blocker or major open, never to a
    design task. The manager passes it on the non-design `issue-task` launches of one wave only, then reports on
    #302, and the engineer keeps or drops it
    ([effort ADR](2026-09-28-effort-and-workflow-bounds.md), amendment of 2026-10-04). No script, default or agent file
    names the model; the workflow tests still assert it.

## Alternatives
- No guard: any file or workflow naming Fable bills or silently downgrades.
- Force one subagent model (`CLAUDE_CODE_SUBAGENT_MODEL` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`): loses the
  haiku/sonnet cost routing.

## Consequences
- `availableModels` lists merge across settings files, so this is a guardrail, not enforcement; the engineer can opt
  into Fable personally.
- Since #183 `agents-check` merges the user-scope list into the shared one, as Claude Code merges lists across
  non-managed scopes (managed settings, which would replace the list, are not modelled). A model from the user list
  that served is ok; one that another family served fell back and is listed, not judged, so the verification run
  below stays green after the engineer adds Fable to his list. It reads the main checkout's transcripts from any
  worktree, and since #206 also workflow agents' (`<session>/subagents/workflows/`), so a `models` launch inside a
  workflow is checked with the same verdicts (its meta file is expected to record the request as `model`; another key
  that names a model fails until the reader learns it). `tools/runner/tests/test_agents_check.py` also asserts that
  no tracked file under `.claude/` or `.github/` and no CLAUDE.md names a model outside the shared list.
- **Verified 2026-09-28:** an Agent call with `model: fable` (its meta file records `"model":"fable"`) was served by
  `claude-opus-5-5` according to its transcript. A control run without the guard was not done, because it would
  spend Fable.
