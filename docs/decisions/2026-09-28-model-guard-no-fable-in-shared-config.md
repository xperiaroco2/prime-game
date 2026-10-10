# Model guard; reviewers on Opus, not Fable

- **Status:** Accepted; amended 2026-10-02 by amendment A (the engineer's answer N1 (b), #183); amended 2026-10-04
  (#308: `godot-api-checker`'s effort, the publisher trial under amendment A); amended 2026-10-05 (the Sonnet
  publisher on clean runs a standing rule, the weekly budget ADR's N5 (a)); amended 2026-10-07 (#469: the Sonnet
  planner, a manager habit like N5, the engineer's option (a)); amended 2026-10-07 (#535: the A/B of a Sonnet code
  reviewer); amended 2026-10-08 (#560: the Sonnet implementer trial); amended 2026-10-10 (#560: the Sonnet implementer
  kept, a standing manager habit)
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
On Max, Fable may use up to 50% of the weekly limit; on Pro it bills usage credits. Workflow agents inherit the
session model. KICKOFF §6 asks for the "strongest model" for `code-reviewer`.

## Decision
- Shared `.claude/settings.json` sets `"availableModels": ["opus", "sonnet", "haiku"]`. A request for any other model
  falls back with a warning.
- Subagent models: `godot-api-checker` sonnet (effort high since #308), `test-runner` haiku, `code-reviewer` and
  `netcode-security-reviewer` **opus with effort high**. This deliberately deviates from "strongest".
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
  - **2026-10-05** (the engineer's answer N5 (a) to the
    [weekly budget ADR](2026-10-05-weekly-budget-across-four-tracks.md), [PR #403 comment
    5992271562](https://github.com/xperiaroco2/prime-game/pull/403#issuecomment-5992271562)): the Sonnet publisher on
    clean runs is a standing rule until it is judged again at the next reset: the manager passes
    `models.publish_clean: "sonnet"` on every non-design `issue-task` launch, not only in one wave.
  - **2026-10-07** (#469, the engineer's yes to a Sonnet planner in `issue-task`'s plan phase, [issue comment
    6014949187](https://github.com/xperiaroco2/prime-game/issues/469#issuecomment-6014949187)): the manager passes
    `models.plan: "sonnet"` on every `issue-task` launch with `plan_review`, as N5's publisher; the plan's critique
    stays on the review model (Opus). The habit, not a default in the script, is option (a), which the
    engineer chose ([PR #504 comment 6033798426](https://github.com/xperiaroco2/prime-game/pull/504#issuecomment-6033798426)):
    no script default names a model, and the workflow tests still assert it. It holds while `metrics`' plan phase
    table shows the critique's findings not rising against the Opus planners before it.
  - **2026-10-07** (#535, the A/B of the [code reviewer's model ADR](2026-10-07-code-reviewer-model-ab.md)). Approved
    by the engineer: https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6038401263 (item 3). `issue-task`
    gains the role `code` (the diff's code reviewer alone; it falls back to `review`) and the arg `ab_review`. The
    manager passes `models: {code: "sonnet", publish_clean: "sonnet"}` and `ab_review: true` on every non-design
    `issue-task` launch until `metrics`' A/B table gives a verdict other than "continue"; the control code reviewer
    and the judge stay on the review model (Opus). It is a trial, not a habit: a keep becomes a standing
    `models.code` only by a further amendment, after the engineer's yes on the verdict. Sonnet is in the shared list,
    so it needs no allowance under amendment A; no script, default or agent file names the model, and the workflow
    tests still assert it.
  - **2026-10-08** (#560, the [Sonnet implementer trial ADR](2026-10-08-sonnet-implementer-trial.md)). Approved by
    the engineer: https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6056243207 (item 2). The manager
    passes `models: {implement: "sonnet", publish_clean: "sonnet"}` on every qualifying `issue-task` launch (Size S,
    `area:tooling` or docs-only, nothing under `core/ server/ net/ client/ voice/`, not a design task, no
    `.claude/workflows/` edit) until `metrics`' trial table gives advice other than "continue"; the plan and the
    reviewers stay as they are. It is a trial, not a habit: a keep becomes a standing `models.implement` only by a
    further amendment, after the engineer's yes on the verdict. Sonnet is in the shared list, so it needs no allowance
    under amendment A; no script, default or agent file names the model, and the workflow tests still assert it.
  - **2026-10-10** (#560, the trial's outcome in the [trial ADR](2026-10-08-sonnet-implementer-trial.md)). Approved by
    the engineer: https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6100590082 (item 1: keep). The
    Sonnet implementer is now a standing manager habit: `models: {implement: "sonnet"}` beside `publish_clean` on
    every qualifying `issue-task` launch, same rule as the trial (Size XS or S, `area:tooling` or docs-only, nothing
    under `core/ server/ net/ client/ voice/`, not a design task, no `.claude/workflows/` edit). **Revert rule:** drop
    it if blockers and majors pass 0.3 a task over the next 10 Sonnet-implemented tasks (counted from 2026-10-10;
    `metrics` reads it). Reverting ends the `models.implement` launches and changes nothing else. Sonnet is in the
    shared list, so it needs no allowance under amendment A; no script, default or agent file names the model, and the
    workflow tests still assert it.

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
