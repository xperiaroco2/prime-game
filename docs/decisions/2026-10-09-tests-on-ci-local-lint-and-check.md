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
- `publish` and `merge` call the plain (fast) `verify`. The definition of done: `verify` (lint and check) green
  locally, CI (the full suite) green on the PR.

## Consequences
- A task's local check takes a minute or two instead of 14; the tests run once, on CI.
- A red test is found on the PR, not before the push: a red CI round costs about 8 minutes plus a fix and a push.
- Windows-only failures (CI runs Linux, without the TwoVoIP addon) are no longer caught locally; run
  `verify --full` locally before a release, or when a change touches Windows-only code.
- A push to `release/m<k>` runs no CI, so a merge there now checks only lint and check locally until `merge` and
  `merge-train` wait for CI on an up-to-date head (#605's remaining criteria).
