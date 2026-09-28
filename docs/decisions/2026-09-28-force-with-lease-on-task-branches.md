# Force-with-lease only on the current task branch

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
KICKOFF §5.4 requires rebasing on `main` before a PR, which requires a force push for an already-pushed branch.
KICKOFF §0 reserves anything destructive to git history for humans.

## Decision
`tools\run.cmd publish` may push with `--force-with-lease` to the **current task branch** `<area>/<n>-*` only. The
pre-push hook allows a non-fast-forward update only there: never `main`, never deletions. The agent never force-pushes
by hand; the permission rules deny it.

## Alternatives
- Never force; push a `-r2` branch. GitHub cannot change a PR's head branch, so this means a new PR and a split review
  history.
- Merge `origin/main` instead of rebasing: no force push, but deviates from KICKOFF §5.4.

## Consequences
The exception must be re-proven in M0 (run `publish` twice after a rebase).
