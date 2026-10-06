# Trust-based autonomy: the manager merges into main through a gate

- **Status:** Accepted: the engineer's decision on #170 and #300; its wording approved by merging its PR (#300), the
  last PR of the tooling track the engineer merges by hand under the old rule; the launch budget amended 2026-10-05
  (the weekly budget ADR's N1 (b), below)
- **Date:** 2026-10-04
- **Deciders:** the engineer (chat with the AI productivity manager session, 2026-10-03 ~20:00 UTC, recorded on #170
  in comment 5972652086 and in #300's body; the answers to the M5 manager on 2026-10-03 ~20:30 UTC, recorded on #300;
  the reporting rule of 2026-10-04 ~23:20 UTC, recorded on #300)
- **Amends:** [only humans merge](2026-09-28-humans-merge-prs.md), [a release branch per
  milestone](2026-10-01-release-branch-per-milestone.md), [the orchestrator
  session](2026-09-30-orchestrator-session.md), [pipeline v2](2026-10-02-ai-productivity-baseline-and-pipeline-v2.md)
  item 3 and [effort and workflow bounds](2026-09-28-effort-and-workflow-bounds.md) (launch approval); each has a
  dated note pointing here.

## Context
The engineer merges every PR into `main` without reading it: the agents' fresh reviews, CI and `verify` are the
checks, and the click adds none. It costs the engineer attention, and a night run stops at the first PR that waits
for it. The engineer decided to rethink the process on trust in the agent: the manager session merges into `main`
itself when a deterministic gate passes, keeps reporting what happens, and stops only for decisions that need the
engineer. The `main` rulesets ask only for a pull request and the green `verify` check (`docs/AGENT_WORKFLOW.md`
§8.5), so the gate lives in the runner, and a typed `gh pr merge` stays denied: the runner is the only way through.

## Decision
**The engineer's three answers** (#170, #300):
1. **Scope.** The manager merges everything that passes the gate, except: the designer's area (`content/ levels/
   docs/GDD.md docs/design/` and the designer's two skills: the designer's approving review, or "agreed with the
   designer, relayed by the engineer" as today); the permission and safety files (`.claude/settings*.json`,
   `.claude/githooks/`, the guard `tools/runner/guard.py`), which the engineer merges; an ADR added or changed, which
   the engineer approves (an "Approved by the engineer: <link>" line in the PR body).
2. **Release branches stay.** The manager merges task PRs into `release/m<k>` as before, and also merges the
   milestone's closing PR into `main` after the engineer's one "go" for the milestone (a playtest, once every task is
   merged and the engineer's human checks are done or postponed).
3. **The engineer's agents only.** The designer's PRs and agents keep today's flow; the designer opts in when the
   designer agrees. This ADR's PR tags @SwiftySinister for information; an objection is reverted by a follow-up PR.

**Decision tiers** (the engineer's words: the agent keeps asking about decisions, reports what happens, stops when the
engineer's attention or decision is needed; it decides alone what does not concern the engineer much, is minor, is
not large in scale, or can easily be changed later, and what the agent judges better than taste would):
- **(a) Decide and report** in the wave comment: technical choices, issues opened from an accepted design, merges
  into `release/m<k>`, closing issues and housekeeping, spending inside the set budget.
- **(b) Decide and tell at once**, one line in the chat: each merge into `main` and each revert.
- **(c) Ask and wait:** game rules and taste; money and budget above the set budget; how the humans work; model
  policy; milestone goals, the design's D items and go/no-go; new dependencies; anything irreversible or destructive;
  the gate's exceptions.

**What else changes** (the engineer's answers to the M5 manager, #300):
- **The manager closes issues and does the housekeeping.** When an issue's work is on `main` and its acceptance
  criteria are met, the manager closes it with a comment linking the PRs and merge commits, and runs `worktree-done`
  for its merged tasks when no live session sits in the worktree (after a closing PR, the release worktree too).
  Anyone can reopen an issue. Workflow agents still never close one.
- **Workflows launch without a "yes" within a budget:** up to 15% of the weekly limit per stage or track, the spend
  reported in every wave comment; above it the manager asks. The kickoff's restatement is then a report, not a
  question, unless it asks for more than that or for a tier (c) item.
  **Amended 2026-10-05** (the engineer's answer N1 (b) to the
  [weekly budget ADR](2026-10-05-weekly-budget-across-four-tracks.md), [PR #403 comment
  5992271562](https://github.com/xperiaroco2/prime-game/pull/403#issuecomment-5992271562)): "15% of the weekly limit
  per stage or track" reads as the track's weekly budget under that ADR (game 26%, UI 20%, art 20%, meta 12%), else
  15%.
- **Fewer small stops.** No "Publish now?" in the engineer's sessions (`gh api user` is the engineer's account): an
  agent publishes once `verify` is green and the fresh review is done; the designer's sessions still ask. A stage's
  issues opened from an accepted design are created and reported, without a "yes" to the list. The milestone's goal
  and the design's D items stay the engineer's.
- **One chat line per merge into `main`.** If `main` breaks after an agent's merge, the agent opens a revert PR
  (`git revert -m 1 <merge>` on a task branch), merges it through the same gate and tells the engineer.
- **A stop word.** "стоп мерджі" returns merges into `main` to the engineer until the engineer says otherwise; the
  manager records the stop on its plan issue and on #170, so a successor session sees it.
- **Reporting** (2026-10-04 ~23:20 UTC): every message from the manager to the engineer ends with one short "For
  you:" block in the engineer's language, numbered, listing only what needs the engineer now (a merge the gate
  refused, a decision, a command), or "nothing". Everything else stays in the wave comment. Housekeeping commands
  the engineer must run are batched into that block once per wave, not after every PR.

**The gate: `tools\run.cmd merge <pr> --base main [--dry-run]`** (#300). It collects every refusal, each with its
reason; `--dry-run` prints the verdict and merges nothing.
- The PR is open into `main`, not a draft, authored by the engineer's account, and gh runs as that account (the
  `*` owner in `.github/CODEOWNERS`): the designer's PRs and sessions are refused, which keeps answer 3 on any machine.
- CI is green on the PR's head (red, pending or no checks: refused); GitHub's `mergeable` is not CONFLICTING;
  `origin/<head>` is the head GitHub reports.
- **An up-to-date head:** `origin/main` is in the PR's head. Otherwise refused as behind: `publish` (or `pr-rebase`)
  brings it up to date, which runs `verify` and a new CI run.
- The exceptions of answer 1, read from `git diff --name-status` since the fork and the PR body without its HTML
  comments (the template's hint carries the relay phrase). A milestone's closing PR (head `release/*`) is refused
  without "Approved by the engineer: <link>", the engineer's go; that line also clears its designer-area paths (the
  milestone's provisional content) and its ADRs. Nothing clears the permission and safety files.
- **"Needs the engineer"**: each top-level numbered or "-" item in that section (a heading, a bold label or a line of
  its own) ends with "Answered: <link to the recorded answer>", which the manager adds with `gh pr edit --body-file`
  once the answer is on GitHub; "None", "nothing" or an empty section pass; text the gate cannot read as items, or the
  phrase with no section, is refused.
- The manager's own check stays before the command, as for a release merge: the fresh reviews left no open blocker
  or major (the PR's findings table and `not_fixed`).
- The merge itself: `origin/main` read again (`git ls-remote`; moved since the gate's fetch: refused), then `gh pr
  merge <n> --merge --match-head-commit <oid>` as the runner's own subprocess (a merge commit, as the humans made;
  the head pinned to the one the gate checked), and one `wave:` line with the merge commit. A real merge runs from
  the main checkout or a release worktree, never a task's checkout (workflow agents never merge).
- **Not in the gate, by design:** a local `verify` on the merged tree, and a refusal for a `merge-check` pair. With
  an up-to-date head the merged tree equals the head's tree, which `publish` verified on Windows and CI (`ci.yml`, on
  `refs/pull/<n>/merge`) verified on Linux. A pair that `merge-check` flags is printed as a note: after the merge the
  partner is behind `main`, so the gate refuses it until its own re-publish tests the pair; across bases the
  milestone takes `main` in (`merge --sync-main`) and rebases its PR. PRs stacked on the merged one are noted too
  (GitHub retargets them to `main`).

## Alternatives
- **Keep human merges into `main`** (the 2026-09-28 rule): a click per PR that checks nothing the gate does not,
  and a night that stops at the first PR into `main`.
- **`verify` on the merged tree for `main` too**, as for `release/m<k>`: 12 to 14 minutes in one of the PC's two
  verify slots per merge, repeating what `publish` and CI ran on the same tree. It stays for `release/m<k>`, where
  pushes run no CI and task PRs are not kept up to date with their base.
- **A `merge-check --trial` instead of an up-to-date head:** a trial verifies main plus the named PRs, but the
  second PR is behind `main` after the first merges and must be re-tested anyway; the trial adds a verify per pair.
- **Allow `gh pr merge` for agents:** the rulesets would let any agent merge any green PR, the stacked child that
  GitHub retargets included. The runner's subprocess keeps the gate the only way.
- **GitHub's merge queue or "require branches to be up to date":** a ruleset change for both humans; the runner's
  check does the same for the agents' merges and leaves the humans' Merge button as it is.

## Consequences
- The engineer merges by hand only the gate's exceptions (this ADR's own PR among them: a new ADR, changed ADRs and
  `.claude/githooks/`), answers "Needs the engineer" and gives each milestone's go.
- Each PR into `main` merged after another one needs a `publish` first (it is behind `main`): the cost of the skipped
  local verify, paid in the task's worktree. `UNKNOWN` mergeability just after a push passes when the head contains
  `main`.
- Supersedes for merges into `main`: "verify on the merged tree, always" (the release-branch ADR) and item 3 (b)'s
  "refuses `main`" (pipeline v2). The pre-push hook and the server ruleset are unchanged: nothing is pushed to
  `main`; GitHub makes the merge commit.
- Agents and the engineer use one GitHub account, so the gate cannot tell who wrote an "Approved by the engineer" or
  "Answered" link: a trust convention, as the hobby-project rule on hardening allows. The manager writes such a line
  only for the engineer's own words, recorded on GitHub.
- A head pushed without `publish` (a hand push, GitHub's "Update branch") has only CI behind it, not the Windows
  `verify`; CI's push run on `main` and the revert rule cover what CI misses.
