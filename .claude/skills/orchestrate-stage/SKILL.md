---
name: orchestrate-stage
description: Run a whole prime-game stage or list of issues as the manager session - one issue-task workflow per task, at most three at a time, while the engineer merges and answers. Use for an "ultracode" kickoff that names a stage or a list of issues, "оркеструй етап", "run stage N", or "продовжуй" in a session that already manages a stage.
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(gh issue view *)
  - PowerShell(gh issue view *)
  - Bash(gh issue list *)
  - PowerShell(gh issue list *)
  - Bash(gh issue create *)
  - PowerShell(gh issue create *)
  - Bash(gh issue comment *)
  - PowerShell(gh issue comment *)
  - Bash(gh pr list *)
  - PowerShell(gh pr list *)
  - Bash(gh pr view *)
  - PowerShell(gh pr view *)
  - Bash(gh pr checks *)
  - PowerShell(gh pr checks *)
  - Bash(gh pr edit *)
  - PowerShell(gh pr edit *)
---

# Orchestrate a stage (docs/AGENT_WORKFLOW.md §7.1)

You are the **manager**: you plan, launch and watch workflows, relay questions and report. Substantive work (code,
docs, reviews, publishing) runs inside workflows; your own inline work is `start`, trivial rebases, opening issues
and posting answers. Talk to the human in their chat language, in plain words; everything on GitHub and in the repo
is English. Commands use `tools\run.cmd`; in Git Bash `tools/run.sh`. The method and its history:
[ADR](../../../docs/decisions/2026-09-30-orchestrator-session.md); the git flow: every task PR targets the
milestone's `release/m<k>`, you merge task PRs into it, a human merges it into `main`
([ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md)).

## 1. The kickoff
One message from the human with `ultracode` in it (template in §10). It must state:
- the scope (issue numbers, or the design handoff to open them from, and fillers) and the plan issue to report on.
  A new milestone gets its own plan issue (`M<k>: plan and order`, opened by you after the yes, its body written
  once and never edited); if the kickoff names none, recommend that;
- the release branch `release/m<k>` every task PR targets, and the order and dependencies: which task stacks on
  which (`start --base`), which waits for a merge into the release branch;
- the concurrency cap (default three tasks at once) and "one task = one workflow" with per-agent bounds
  (implementer about 250 tool calls, reviewers about 60, publisher about 150);
- explicit approval to exceed the size guideline (`issue-task` runs up to 5 agents; `small` means fewer than 5)
  and a budget for the whole stage (tasks × about 900k subagent tokens), so you do not ask before each workflow
  (root `CLAUDE.md`, §7 of AGENT_WORKFLOW);
- the rules: only humans merge into `main`, you merge task PRs into `release/m<k>` (§5); no agent closes issues;
  each agent only in its worktree; no `git stash`; temporary files in the scratchpad or `tests/scratch/`; Godot
  windows only through `shot`; a game rule no ADR settles becomes options under "Needs the engineer"; `content/`
  and `levels/` files are provisional;
- the engineer's standing decisions to honour, with where each is recorded; known traps; what to drop first;
- reporting: a comment on the plan issue after each wave; stop with a comment when nothing more can run without
  the human (answers, a design review, the closing PR's merge); "продовжуй" resumes after a check of the live state.

Something missing: ask once, batched, with a recommendation for each item. Then, always, restate in the human's
language the waves, the ownership splits, the merge order, the agent count per workflow and the rough cost (§9
numbers), and wait for their yes. That yes covers every later `issue-task` and `pr-rebase` run of the stage; a new
kind of workflow still asks.

**Prerequisites** (check them before the restatement): the human pulled `main` in `D:\prime-game` after saving all
scenes in the editor, and `D:/prime-game/.claude/workflows/issue-task.js` exists (`Test-Path`). Missing: ask the
human to pull; a session opened before the pull needs `/reload-skills` to find the workflows by name.

## 2. Before the first launch
1. `tools\run.cmd doctor --quick`. Read the plan issue, every issue in scope with its comments, the handoffs they
   build on, and the ARCHITECTURE sections and ADRs they name.
2. **Find live runs of other sessions.** An earlier manager's workflows may still run: a handover starts while they
   finish. Treat as owned by a live run, until the human says otherwise: an issue In progress with no PR, a worktree
   with a commit in the last hour (`git -C <wt> log -1 --format=%cr`), a rebase in progress (`git -C <wt> status`),
   and every run listed as running in the plan issue's latest wave comment. List them in your batched question and
   never `start`, launch or rebase them before the answer: `start` on such an issue succeeds silently (it resumes the
   branch and worktree as they are), and a second implementer then works beside the first.
3. **The design gate.** Code tasks wait until the stage's design PR has the engineer's review. If the design task
   has no PR yet: when another session runs it, your first wave is empty (post a plan-issue comment saying you wait
   for it, and stop); otherwise the first wave is that design task alone (`design: true`). Offer fillers that do not
   depend on the design meanwhile.
4. **Opening the stage's issues** from a design handoff (its `proposed_issues`) and the engineer's review: show the
   list and the order in chat and wait for their "yes" before creating anything. Then for each, a body file under
   `<scratchpad>/manager/` with Goal, Acceptance criteria (a checklist), Out of scope, Verification, `Depends on #…`
   and `Tracking: #<plan>`, and `gh issue create --title "<area>: <what>" --label area:<x> --milestone M<k>
   --body-file <file>` (one `area:` label, which `start` needs for the branch prefix). Put the new numbers in a
   plan-issue comment.
5. **The release branch** (once per milestone, after the yes): from the main checkout, without leaving your shell
   anywhere else, `git fetch origin && git branch release/m<k> origin/main && git push -u origin release/m<k> &&
   git worktree add D:/prime-game/.claude/worktrees/release-m<k> release/m<k>`. That worktree is yours, for the
   merges (§5); say both in the first wave comment.
6. Write a state file in your session scratchpad, `manager/state.md`: running runs (runId, issue, worktree, the
   args file), the queue, ownership splits, merge order, open questions. Keep it current: it survives compaction.
   Keep each task's args in `manager/args-<n>.json`. The scratchpad is per session, so every wave comment also
   carries what a successor needs (§6).
7. Find the files that tasks running in parallel will all touch (mode `.tres` files, `docs/ARCHITECTURE.md`,
   registries, event folders) and split ownership **up front**: who owns which class, which task creates which
   shared class (same path and class name if two may create it), whose deal places what. Otherwise add/add
   conflicts and duplicate work follow.

## 3. Launching a task
1. `tools\run.cmd start <n> --base release/m<k>` (or `--base <parent branch>`, a branch on origin, for a task
   stacked on an unmerged PR) in **your** session, from the main checkout, never in an agent. From its output take
   the `WORKTREE <path>` line and the branch from the last line, `start: <branch> in the worktree <path>`.
2. Launch the saved workflow `issue-task` (`.claude/workflows/issue-task.js`; the Workflow tool with
   `name: "issue-task"`, or `scriptPath` to that file in the main checkout) with `args` as a JSON object:

| arg | what |
|---|---|
| `n`, `title`, `wt`, `branch` | the issue, its title, the worktree path, the task branch (required) |
| `base` | the PR base: `"release/m<k>"`, or the parent's branch for a stacked task (`main` only outside a stage); every non-`main` base reaches `gh pr create --base`, a release base also `publish --base` (a parent's branch does not: publish follows the PR's live base) |
| `notes` | the task's specifics, the engineer's answers that apply, ownership splits, merge order (required) |
| `coord` | what runs in parallel now and which shared files to touch minimally |
| `decisions` | the engineer's standing decisions, each with where it is recorded (every task that they touch) |
| `reading` | overrides the default reading list (the issue's links, handoffs, ADRs, area CLAUDE.md files) |
| `testing` | overrides the default test expectations, which follow the branch's area: `core` a seeded Match and `view_of`; `net`/`server` loopback-transport tests plus the ENet runs in verify; `tooling` the runner selftest; others generic |
| `design` | `true` for a docs-only design task: options for the engineer, a proposed issue split, the netcode reviewer, effort xhigh |
| `effort`, `plan`, `manager` | implementer effort (default high), the plan issue (default 30: set it), your name in prompts ("the M3 manager session") |

The workflow: implementer (commits, verify green, never publishes) → fresh reviewers in parallel, chosen from the
changed paths (`code-reviewer` always; `netcode-security-reviewer` for `core/ server/ net/ client/ tests/harness/` or a
design task; `godot-api-checker` for `.gd .tscn .tres`) → publisher (fixes blocker, major and cheap minor findings,
`publish` (`--base` for a release base), PR with a findings table, "Needs the engineer" and "Merge order", CI watch with at most
two fix rounds, handoff, board In review). It throws when any routed agent returns nothing, and stops unpublished when the implementer ends
red. Every agent writes temporary files only under the scratchpad subfolder `a<n>/`.

Notes that worked: say which PR a needed file comes from if it is unmerged ("build with fixtures, fetch and rebase
once it lands"); repeat rules that force fixture updates in every later PR (neutral class defaults with the numbers
in the data); name a task's merge order relative to the other open PRs.

## 4. On each completion
Read the result (`pub.pr_url`, `ci_green`, `needs_engineer`, `human_steps`, `not_fixed`). Merge it into the release
branch when the gate in §5 holds, and tell the human what you merged and in which order; explain each "Needs the
engineer" item in plain words: a concrete scenario of what goes wrong, the options, your recommendation, numbered so
they can answer "1A, 2B". Then fill the free slot.

When something failed:
- `stopped` (the implementer ended red) or `pub.published` false: say so on the plan issue and in chat, then launch
  `issue-task` once more as a **fresh** run (not a resume: that replays the red result) with the failure added to
  `notes`; the implementer continues from the worktree's commits. Red again: stop that task and ask the human.
- `ci_green` false after the publisher's two rounds: the same, with the failing check in `notes`.
- `not_fixed` items: list them in the wave comment; they are the engineer's to accept or turn into issues.

**Answers.** Post them in English on the PR and the issue ("The engineer's answers (chat with the manager session,
<date>)"). Carry an answer that belongs to a later task to that issue as a comment; open a new issue for a decision
that changes shared design. An answer with two readings that build different things is read back in one sentence
(AskUserQuestion) before it is recorded; if the human dismisses the question and explains, read back again. An
answer that changes a published PR: a trivial one inline in its worktree, in a subshell (§9), then
`publish --base release/m<k>`; otherwise `issue-task`
again for that issue with the answers in `notes` (its agents find the branch and the PR and continue).

## 5. Merges and rebases
You merge task PRs into `release/m<k>`; only a human merges into `main`
([ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md)). `gh pr merge` stays denied: you merge
locally.
- **The gate.** Merge a task PR only when CI is green (`gh pr checks <pr>`), the fresh reviews left no open blocker
  or major (the PR's findings table and `not_fixed`; one that waits for the engineer waits for the merge too), and
  `verify` is green on the merged tree. First check whether a human already merged it (`gh pr view <pr> --json
  state,mergedAt`; the engineer merged #107 himself on 2026-10-01): then only fetch.
- **The merge**, always in a subshell, in your `release-m<k>` worktree (§2.5); `verify` takes about six minutes, so
  run the whole command with `run_in_background`:

  ```bash
  (cd /d/prime-game/.claude/worktrees/release-m<k> && git fetch origin \
    && git checkout -q --detach origin/release/m<k> \
    && git merge --no-ff origin/<task branch> -m "Merge pull request #<pr> from <owner>/<task branch>" \
    && tools/run.sh verify && git rev-parse --short=12 HEAD)
  ```

  Then push the commit it printed: `(cd /d/prime-game/.claude/worktrees/release-m<k> && git push origin
  <commit>:release/m<k>)`. Never `git push origin HEAD:...`: the deny rule `git push *HEAD*` refuses it. Each merge
  starts on a detached HEAD at `origin/release/m<k>`, so a failed one leaves nothing to undo and never reaches the
  next push. The push is a fast-forward, which the pre-push hook allows; GitHub then marks the PR merged (check with
  `gh pr view <pr> --json state`). A red `verify` pushes nothing: tell the human and relaunch the task with the
  failure in `notes`. The guard lets these commands pass from the main checkout and from the worktree.
- **Order.** Stacked PRs: the parent first. Never merge a parent while its child's workflow has not reached Publish:
  the merge deletes the parent branch the child's reviewers diff against and its publisher targets. If it happened
  anyway, relaunch the child fresh with `base: "release/m<k>"` (update its args file) once the running one ends.
- After each merge: `gh pr list --state open --json number,headRefName,baseRefName,mergeStateStatus` (`UNKNOWN` just
  after a merge: ask again). A child still based on the merged parent: `gh pr edit <child> --base release/m<k>`.
- Never touch a worktree whose workflow is still running, yours or another session's (§2.2).
- A docs or test-list conflict: resolve inline in that task's worktree, each command in a subshell
  (`(cd <worktree> && git fetch origin && git rebase origin/release/m<k>)`, keep both sides, `verify`, then
  `(cd <worktree> && tools/run.sh publish --base release/m<k>)`), then a PR comment listing the conflicts. The
  guard lets a rebase through without a prompt when the command enters the worktree with `cd` (or `git -C`) and it
  is on its task branch (AGENT_WORKFLOW §8.2, #51); while another live session works in that worktree it asks, so
  hand such a case to `pr-rebase` when the human is away.
- A semantic conflict (two PRs creating the same classes, a changed interface): the saved workflow `pr-rebase`
  with args `{n, pr, wt, branch, base, why, steps, focus}` (`base: "release/m<k>"`): rebase agent → fresh
  reviewer(s) → a fix agent only for a blocker or major. `why` names what merged and the PRs and handoffs to read;
  `steps` says which side's files and payloads to keep. A result with `stopped` (rebase red or unpublished) gets
  one fresh relaunch with `reb.problems` in `steps`, then goes to the human.
- **The stage's end.** When every task is merged, open the PR from `release/m<k>` into `main` (`gh pr create --base
  main --head release/m<k>`; M3: #117): a table of the task PRs with their merge commits, every open "Needs the
  engineer" and "Needs the designer" item, and the issues a human closes after the merge (`Closes` does not fire
  from the release branch). Open it only when no task PR still targets `release/m<k>`: merging it deletes the branch
  (auto-delete) and GitHub retargets such a PR to `main`. A human reviews and merges it.

## 6. Reporting and keeping slots busy
- After each wave, a comment on the plan issue: merged PRs, decisions recorded (with links), in progress, order from
  here, batched questions (numbered, recommendations), housekeeping for a human: `worktree-done` lines (§8) and the
  issues to close once `release/m<k>` is merged into `main` (auto-close does not fire from the release branch and
  agents never close issues). Never edit the plan issue's body.
- **Handover data** in every wave comment: for each running run the issue, the worktree, the owning session's name,
  the runId and the args as a JSON block. A successor session (§7) relaunches from that, not from your scratchpad.
- Keep every slot busy: when the next task waits for a merge, start what does not depend on it (a task's
  independent part with a "fetch and check whether X is on origin/release/m<k>" step, fillers, the next milestone's
  design task). When nothing more can run without merges or a design review, say so in a plan-issue comment and stop.
- Tasks that edit `.claude/` (any path) or `addons/` prompt unless the session runs in bypass: run them only while
  the human is present.

## 7. Resume after a crash, a restart or a plan limit
- A workflow throws when an agent returns nothing. Relaunch it the same way (name or `scriptPath`) with
  `resumeFromRunId` and the **same args** (from the args file): finished agents return their saved results. A
  resume replays agents only while their prompts are unchanged, so it needs the same script too: if `main` changed
  `issue-task.js` since the launch, expect the changed agents to run again.
- A stacked task whose parent has merged since the launch: do not resume; relaunch fresh with
  `base: "release/m<k>"`.
- After a PC restart or a crashed session: reopen the same session (`claude --resume`, or the app) and resume each
  run as above. In a **new** session there is no run to resume ("nothing to resume") and no old scratchpad: take
  each run's args from the latest wave comment on the plan issue (§6), confirm with the human that the old session
  is closed, and launch `issue-task` afresh with those args; the implementer finds earlier commits and uncommitted
  files through `git status`, the publisher an existing PR through `gh pr list`.
- A plan limit: with `autoContinueAtUsageLimit` on, a workflow's agents wait for the reset and continue on their
  own; otherwise they fail and you resume after the reset. While you wait (a limit, a long run, a merge), set a
  timer with a background `sleep <seconds>` (Bash, `run_in_background`); it wakes you when it exits. A finished
  workflow wakes you anyway.
- "продовжуй" after any break: re-read the live state first (`gh pr list`, the plan issue's latest comments, each
  running run), then the state file, then continue.

## 8. Notifications and housekeeping
- When the human is needed (a PR to merge, questions, a stop), end your turn with a short summary and send a
  PushNotification. It is suppressed while the human is active in the session, and the desktop app only flashes its
  icon while its window is in use; a PowerShell toast tests whether Windows notifications work at all.
- Merged tasks' worktrees: list `tools\run.cmd worktree-done <n>` (from `D:\prime-game`) for the human in the
  wave comment, to run once `release/m<k>` is merged into `main`; a worktree whose branch never reached main but
  whose work did (merged into a parent) says so. Your `release-m<k>` worktree goes too, but `worktree-done` takes
  only an issue number: give the human `cd D:\prime-game; git worktree remove .claude/worktrees/release-m<k>; git
  branch -d release/m<k>`, to run after the closing PR has merged into `main`.

## 9. Gotchas

### 2026-09-30 (M2)
- The scratchpad is shared by all agents of all workflows: one overwrote another's `pr_body.md`. Hence `a<n>/`.
- `publish` can fail right after a rebase that changed `tools/runner` (verify ran the old modules): run it again.
  "Could not resolve hostname github.com" is transient: `git ls-remote origin`, then again.
- Intermediate commits after a rebase may not compile (the fix lands at the tip): bisect by PR; merge commits keep
  PRs as units.
- Two verify runs at once in different worktrees can collide (GdUnit4 files under `user://`, a busy port): the
  agents rerun once before debugging.
- Agents see the human's mid-turn messages relayed; they ignore requests outside their task. Tell the human that a
  message meant for you should go to your session, not to a running workflow.
- Numbers: about 20 workflows in one day; 25 to 60 minutes and 450k to 900k subagent tokens per task workflow.

### 2026-10-01 (the M3 night run, #96)
- **Never leave your shell inside a worktree.** Workflow agents' hooks receive your session's working directory, so
  the guard takes the worktree your shell stands in as every agent's own and asks when they rebase or reset in
  theirs: a publisher's autosquash stopped at 02:14 that way (proved by a `tools\run.cmd permissions` replay). Work
  in a worktree only through a Git Bash subshell `(cd <wt> && ...)`, `git -C <wt> ...`, or PowerShell
  `Push-Location <wt>; ...; Pop-Location`; a bare `cd` in the Bash tool persists into your next call.
- **No `git stash`, in every launch's rules.** The stash is one list for all worktrees, so the guard asks before a
  drop of an entry it cannot show is the agent's own (`git stash drop "$ref"` at 02:10). The workflows' rules say
  so; repeat it in `notes` for any other agent you start: a WIP commit and later `git reset --soft HEAD~1`, or
  `git commit --fixup=<sha>` then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>`.
- **`publish` with a release base (#113, fixed).** On the M3 night `publish` took `release/m<k>` equal to `main` for
  a merged parent, and after a hand rebase replayed upstream commits from a stale `branch.<branch>.primeBaseTip`.
  It now keeps a base outside `<area>/<n>-<slug>` and replays only the commits after the merge-base. Still pass
  `publish --base release/m<k>` and `gh pr create --base release/m<k>` (the workflows pass `base`): a checkout
  without `start`'s record needs it. The workflows' `primeBaseTip` reset after a hand rebase is now redundant.
- **The information-leak test gets a netcode review.** A PR that touches only `tests/` and `tools/` once had no
  `netcode-security-reviewer` (#115); a pass run by hand found a major blind spot. The workflows now route it for
  `tests/harness/`; for a leak-test change elsewhere (a new runner in `tools/`), run one by hand before the merge.
- **No `staging`.** A second integration branch was tried and dropped the same night: one `release/m<k>` per
  milestone.

### 2026-10-01 (M4)
- **The netcode review covers `client/`** (#158). What the client renders can leak (a sound through walls, a camera
  that sees too far). Before this, the review ran by hand on PR #154 twice, and both runs found real problems.
- **Name a rename in both tasks' notes**, not only who owns which file. #153 renamed
  `PlayerRules.ghost_speed_factor` while #154 started reading it: each PR was green alone, the merged tree was red,
  and `pr-rebase` fixed it.
- **A `pr-rebase` fix after the review gets a fresh netcode review.** When its fix agent changes netcode-relevant
  code after the reviewers ran, run `netcode-security-reviewer` again before the merge (done by hand for #154).
- **Never `cd <wt> && ...` in your Bash shell**: it stayed inside a worktree twice in M4. Only a subshell
  `(cd <wt> && ...)` or `git -C <wt>`.
- **`§` in args on Windows.** A Python `print` of the args mangled it: pass the args inline in the Workflow call,
  or set `PYTHONIOENCODING=utf-8`.

## 10. Kickoff template
The human copies it, fills the placeholders and sends it, in English or in their own language. Moving state (which
issues, which PRs) goes only in the message, never in this file.

```text
ultracode: orchestrate stage <k> (<milestone>, <theme>) with the skill orchestrate-stage. You are the manager: one
task = one issue-task workflow, at most three at once.

Start from: <my review of the design PR #<pr> and its handoff on #<design issue> | the issues below>.
<If from a design: open the stage's issues from that handoff with my review's changes, show me the list and the
order, and wait for my "yes".>

Scope: <issues, or "the issues from the handoff">; fillers: <issues>.
Plan and reports: a comment on #<plan issue> after each wave; never edit its body.
Release branch: release/m<k> from main; every task PR targets it (start --base release/m<k>); you merge task PRs
into it after green CI, fresh reviews with no open blocker or major and verify on the merged tree; I merge it into
main through one PR at the end.
Order: <order, or "as in the handoff">; stack with start --base <parent> only where a task depends on an unmerged
PR.
Bounds: implementer ≤ 250 tool calls, reviewers ≤ 60, publisher ≤ 150. I approve exceeding the size guideline
(up to 5 agents per workflow) and a budget of about <N> tasks × 900k subagent tokens for the stage; do not ask
before each workflow once I have said yes to your restatement.
Rules: only I merge into main; no issue is closed by an agent; each agent only in its worktree; no git stash;
you never leave your shell inside a worktree; temporary files in scratchpad/a<n>/ or tests/scratch/; Godot
windows only through shot; a game rule no ADR settles becomes options with a recommendation under "Needs the
engineer"; content/ and levels/ files are provisional, I approve them in the PR.
My decisions: the ADRs and my answers in the comments of <issues> (newer ones win).
Traps: <known traps>; tasks that edit .claude/ run only while I am around; <decisions reserved for me>.
Drop first if the budget runs out: <fillers>, then <lowest-priority task>.
When nothing more can run without me: a comment on #<plan issue> and stop. "продовжуй": check the live
state and continue.
```
