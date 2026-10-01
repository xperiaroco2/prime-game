# A release branch per milestone: the manager merges task PRs, humans merge the milestone into main

- **Status:** Accepted
- **Date:** 2026-10-01
- **Deciders:** the engineer (chat with the M3 manager session, 2026-10-01; recorded on #96)

## Context
In stage 3 (M3) a manager session ran the stage overnight (#96, 2026-09-30 to 10-01) with the
[orchestrator session](2026-09-30-orchestrator-session.md). Under [only humans merge](2026-09-28-humans-merge-prs.md)
every task PR would have waited for the engineer's click, and the night's tasks depended on each other (3f on 3c, 3d
and 3e; 3h and 3i on 3f and 3g; #98 came in two PRs): a stage whose tasks need merged parents stalls at the first
merge nobody is awake for. The engineer authorized a different flow before the night began. A `staging` level
above the release branch was created the same night and dropped before it was used (#96, "Git flow change").

The `main` rulesets require only a pull request and the green `verify` check (`docs/AGENT_WORKFLOW.md` §8.5). So
`gh pr merge`, once allowed, would let any agent merge any green PR into `main`, for example a stacked child PR that
GitHub retargets to `main` when its parent's branch is deleted.

## Decision
- **One integration branch per milestone.** At a stage's start the manager creates `release/m<k>` from `main` and
  pushes it. Every task PR of the stage targets it: `start --base release/m<k>`, the workflows' `base:
  "release/m<k>"`, `tools\run.cmd publish --base release/m<k>` and `gh pr create --base release/m<k>`.
- **The manager merges task PRs into `release/m<k>`** without asking, once all three hold: CI is green on the PR;
  the fresh reviews have no open blocker or major finding; and `verify` is green on the merged tree before the push.
- **The merge is local.** In its own `release/m<k>` worktree the manager runs `git fetch origin`, `git merge --no-ff
  origin/<task branch>`, `tools\run.cmd verify` on the merged tree, then `git push origin release/m<k>`: a
  fast-forward that the pre-push hook allows. GitHub sees the PR's commits on its base and marks the PR merged. A
  red `verify` pushes nothing; the manager stops merging and reports (undoing the local merge is a `git reset` on a
  branch that is not a task branch, so the guard asks: a human step).
- **`gh pr merge` stays denied** for every agent, the manager included (deny rule in `.claude/settings.json`). The
  local merge needs no new permission, and no agent can merge into `main`.
- **Humans merge the milestone.** The stage ends with one PR from `release/m<k>` into `main` that links every task
  PR and carries the stage's "Needs the engineer" and "Needs the designer" items; a human reviews and merges it
  (M3: #117). Nothing reaches `main` any other way.
- **Issues stay open** until that PR merges: GitHub's `Closes #n` fires only on a merge into the default branch, and
  agents never close issues. After the merge into `main` a human closes the stage's issues (the manager lists them).
- There is no `staging` branch and one milestone runs at a time.

## Alternatives
- **Humans merge every task PR** (the 2026-09-28 rule unchanged): the stage stalls at night wherever a task needs
  a merged parent, and a task that takes three PRs waits three times.
- **`staging` plus `release/m<k>`:** a second integration level with nothing to separate while one milestone runs
  at a time; tried on the night of 2026-09-30 and dropped unused.
- **Allow `gh pr merge`:** with the `main` rulesets as they are, any agent could merge a green PR into `main`. A
  guard check on the PR's base (allow only `release/*`) would be new enforcement for a case the local merge already
  covers.

## Consequences
- The engineer reviews a stage as one PR into `main`, with every task PR, review table and answer linked from it,
  instead of one click per task. The task PRs keep their own reviews and CI runs.
- CI runs on pull requests and on pushes to `main` only, so a push to `release/m<k>` runs no CI: `verify` on the
  merged tree is the gate there, and the closing PR runs CI on the whole stage.
- Merging the closing PR deletes `release/m<k>` (auto-delete is on) and would retarget any PR still based on it to
  `main`: the manager opens it only when no task PR targets the release branch, or says which do.
- `publish` treats a `release/*` base that equals `main` as a merged parent (#113): always pass `--base
  release/m<k>`.
- Amends [only humans merge](2026-09-28-humans-merge-prs.md): humans still merge everything into `main`.
