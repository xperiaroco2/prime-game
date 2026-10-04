# A release branch per milestone: the manager merges task PRs, humans merge the milestone into main

- **Status:** Accepted; one Decision bullet added 2026-10-02 (a tooling track beside a milestone, the engineer's
  answer N2, #183)
- **Amended 2026-10-04 (#300):** the manager also merges the milestone's closing PR into `main` once the engineer
  gave the milestone's go (an "Approved by the engineer: <link>" line in its body), and the tooling track's PRs go
  into `main` through the same gate, merged by its manager
  ([trust-based autonomy](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)). "Humans merge the milestone",
  "each merged by the engineer, never by an agent" and "humans still merge everything into `main`" below now hold only
  for the gate's exceptions, and "agents never close issues ... a human closes the stage's issues" no longer holds:
  the manager closes them after the merge into `main`. `verify` on the merged tree stays the gate into `release/m<k>`; into `main` the gate
  requires an up-to-date head instead.
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
- **The merge is local.** In its own `release/m<k>` worktree the manager runs `git fetch origin`, `git checkout
  --detach origin/release/m<k>`, `git merge --no-ff origin/<task branch>`, `tools\run.cmd verify` on the merged
  tree, then pushes that merge commit by its hash, `git push origin <commit>:release/m<k>` (the deny rule
  `git push *HEAD*` refuses `HEAD:`): a fast-forward that the pre-push hook allows. GitHub sees the PR's
  commits on its base and marks the PR merged. A red `verify` pushes nothing and leaves nothing to undo: the next
  merge starts again from `origin/release/m<k>` (no `git reset`, which the guard would ask for on a branch that is
  not a task branch); the manager reports and relaunches the task.
- **`gh pr merge` stays denied** for every agent, the manager included (deny rule in `.claude/settings.json`). The
  local merge needs no new permission, and no agent can merge into `main`.
- **Humans merge the milestone.** The stage ends with one PR from `release/m<k>` into `main` that links every task
  PR and carries the stage's "Needs the engineer" and "Needs the designer" items; a human reviews and merges it
  (M3: #117). Nothing reaches `main` any other way.
- **Issues stay open** until that PR merges: GitHub's `Closes #n` fires only on a merge into the default branch, and
  agents never close issues. After the merge into `main` a human closes the stage's issues (the manager lists them).
- There is no `staging` branch and one milestone runs at a time.
- **A tooling track beside the milestone** (the engineer's answer N2, 2026-10-02, to the
  [pipeline v2 ADR](2026-10-02-ai-productivity-baseline-and-pipeline-v2.md); the one exception to "Nothing reaches
  `main` any other way"): the AI productivity track (#170) may run beside a milestone with its PRs straight into
  `main`, each merged by the engineer, never by an agent. When `main` gets a change the milestone should take in,
  that track's manager says so on the milestone's plan issue; at a wave boundary the milestone's manager merges
  `origin/main` into `release/m<k>`, runs `verify` on the merged tree and pushes the merge commit by hash, as for a
  task PR (`tools\run.cmd merge --sync-main --base release/m<k>`, #181).

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
- On the M3 night `publish` treated a `release/*` base that equalled `main` as a merged parent. Since #113 it keeps
  any recorded base outside `<area>/<n>-<slug>` while origin has it, and follows a hand rebase on a newer
  `origin/release/m<k>`. The workflows still pass `--base release/m<k>`, which also covers a checkout without the
  record `start --base` leaves.
- Since #181 `tools\run.cmd merge <pr> --base release/m<k>` runs the local merge above as one command, in a
  scratch detached worktree under `tools/out/merge/` (removed afterwards) instead of on the release worktree's own
  HEAD, with the same gate: green CI, `verify` on the merged tree every time, the push by hash. It refuses `main`.
  `tools\run.cmd merge-check` checks the open PRs against each other and their base before each merge
  (`docs/AGENT_WORKFLOW.md` §7.1).
- Amends [only humans merge](2026-09-28-humans-merge-prs.md): humans still merge everything into `main`.
