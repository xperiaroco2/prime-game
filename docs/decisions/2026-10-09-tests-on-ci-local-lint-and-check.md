# Tests on CI; a local verify runs lint and check

- **Status:** Accepted (#605)
- **Date:** 2026-10-09
- **Deciders:** the engineer. Approved by the engineer: https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6082442125
  (after #302's comments 6080608901 and 6082221423)
- **Tracking:** #605, #302 (token efficiency)
- **Supersedes:** N4 (a) of the [AI productivity ADR](2026-10-02-ai-productivity-baseline-and-pipeline-v2.md)
  ("`verify` stays exactly what CI runs") for a local `verify`; CI's run is still the whole suite.

## Context
Every task ran the full local `verify`: about 14 minutes on the engineer's laptop, 30 to 40 minutes when several
worktrees ran it at once, often two or three times a task, and `merge` into `release/m<k>` ran it once more. GitHub CI
then ran the same suite on the PR (about 8 minutes, free: the repository is public). The engineer, 2026-10-09: the
laptop repeated what GitHub does anyway, for no gain, and it must stay light.

## Decision
- `verify` with no flag runs `doctor --quick`, then `lint` and `check` at once, then the clean-tree check: no
  GdUnit4 test, no network run, no bots, chaos, game or runner test, and no verify slot. Its summary says "fast verify:
  lint and check; the tests run on CI (verify --full runs them here)", and its history record has `"mode": "fast"`
  (`metrics` keeps its total out of the full runs').
- `verify --full` runs the whole suite exactly as before (lanes, `AFTER`, the count check, a verify slot,
  `--fail-fast`). CI's `verify` job runs `tools/run.sh verify --full`.
- `publish` calls the plain (fast) `verify`; `merge` runs none (#622). The definition of done: `verify` (lint and check) green
  locally, CI (the full suite) green on the PR.

## Consequences
- A task's local check takes a minute or two instead of 14; the tests run once, on CI.
- A red test is found on the PR, not before the push: a red CI round costs about 8 minutes plus a fix and a push.
- Windows-only failures (CI runs Linux, without the TwoVoIP addon) are no longer caught locally; run
  `verify --full` locally before a release, or when a change touches Windows-only code.
- A push to `release/m<k>` ran no CI, so a merge there checked only lint and check locally until `merge` waited for
  CI on an up-to-date head, as the gate into `main` does, and CI ran on pushes to `release/**` (#622, #605's remaining
  criteria): `merge --base release/m<k>` and `--sync-main` run no local verify.

## Amendment (#606, 2026-10-09): the review chain by the change's risk
- **Deciders:** the engineer, #302 comment 6080608901 item 2 ("simplify by the risk of the change"): the full chain
  only where a mistake becomes a cheat, a desync or a hidden-information leak.
- **Decision:** `issue-task` picks a review tier from the implementer's changed paths, the worst one winning.
  - `full`: a path under `core/ server/ net/ client/ voice/ tests/harness/` (the path rule of `quick-task`, #608), no
    changed paths (unknown), a design task, or the launch's `tier: "full"`. Today's chain, unchanged.
  - `light`: any other diff (docs, content data, levels, UI text and layout, tooling): `code-reviewer`
    (`godot-api-checker` too on a `.gd .tscn .tres` change; `ab_review` keeps its measurement pair) and the publisher.
    `test_review`, `second_review` and `skeptic` are dropped even when passed.
  - `plan_review` runs before any diff exists, so the branch's area (`start`'s `<area>/` prefix, from the issue's area
    label) decides it: `content`, `level` and `tooling` skip it unless the tier is forced. A diff that then turns out
    full gets the full review without the plan.
  - Only `full` can be forced: a launch cannot rate a `core/` diff light.
- **Two tiers, not the issue's three:** #606 named a `tooling` tier after #605's verify tiers, which comment
  6082442125 replaced with one fast local verify; a tooling diff is light, its tests run on CI (`selftest`), and the
  script cannot read an issue's `Size:` line to drop `plan_review` below M.
- **Consequences:** a docs, content or tooling task launched with `plan_review` and `skeptic` runs 3 agents (4 with
  `godot-api-checker`) instead of 5 and a skeptic per blocker or major;
  a light change has one fresh reviewer and CI. A mistake in tooling that guards against lost work (the guard, the
  hooks, `publish`, `merge`) is reviewed light too; the manager passes `tier: "full"` where a kickoff asks for more.
  `metrics` groups cost and wall time per tier (the publisher's prompt names it), the before and after.
