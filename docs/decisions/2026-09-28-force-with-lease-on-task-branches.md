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

**Built and proven in M0 stage 4 (2026-09-29).** A hook cannot see `--force-with-lease` on the command line, so
`publish` marks its push with `PRIME_GAME_PUBLISH=force-with-lease` and the hook lets a non-fast-forward update
through only with that marker, for the checked-out task branch. `publish` rebases on the open PR's base, so a
stacked PR is rebased on its parent, not on `main`. Real pushes to GitHub with throwaway branches
`tooling/4-probe-publish` and `tooling/4-probe-base` (a base that moved twice, like a parent PR):
- `publish --base tooling/4-probe-base` twice, each after the base moved: rebased (`d255eaf` → `0caf005` →
  `d7370fd`), `verify` green, forced update with the lease accepted. A third run changed nothing.
- Blocked by the hook, remote unchanged: `--force` by hand, `--force-with-lease` by hand (no marker), `--delete`,
  a push to `main` (`--dry-run`: the ruleset lets admins bypass it, so a real push would land if the hook failed),
  and the marker on a branch that is not checked out.
- Found on the way: a checkout without `.claude/githooks/pre-push` (a branch from before this stage) runs no
  pre-push hook at all, and the marker test from such a branch went through. `docs/AGENT_WORKFLOW.md` §8.3 records
  it; repeated from a checkout that has the hook, it is blocked.
