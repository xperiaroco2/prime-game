---
name: orchestrate-stage
description: Run a whole prime-game stage or list of issues as the manager session - one issue-task workflow per task, at most three at a time, merging into release/m<k> and, through a gate, into main while the engineer answers. Use for an "ultracode" kickoff that names a stage or a list of issues, "оркеструй етап", "run stage N", or "продовжуй" in a session that already manages a stage.
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
milestone's `release/m<k>`, you merge task PRs into it and, after the engineer's go, the milestone into `main`
([ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md)). The tooling track (the AI productivity
track, #170) sends its PRs straight into `main`, and you merge each through the gate (§5). What you decide alone,
what you tell at once and what you ask: the tiers of the
[trust ADR](../../../docs/decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md).

## 1. The kickoff
One message from the human with `ultracode` in it (template in §10). It must state:
- the scope (issue numbers, or the design handoff to open them from, and fillers) and the plan issue to report on.
  A new milestone gets its own plan issue (`M<k>: plan and order`, opened by you after the yes, its body written
  once and never edited); if the kickoff names none, recommend that;
- the git flow: the release branch `release/m<k>` every task PR targets (or, on the tooling track, PRs into `main`),
  and the order and dependencies: which task stacks on which (`start --base`), which waits for a merge;
- the concurrency cap (default three tasks at once, fewer where budget.md's PC share is lower: meta by day 1)
  and "one task = one workflow" with per-agent bounds (implementer about 250 tool calls, reviewers about 60,
  publisher about 150; with the v2 args of §3 the plan agent about 80, its critique about 40, the test reviewer
  about 60, each skeptic about 30, a publisher that only reports a stop about 30);
- explicit approval to exceed the size guideline, with the agent count it approves per workflow (`issue-task` runs
  3 to 5 agents plus those of the v2 args the kickoff names, §3; `small` means fewer than 5), and the `Track:` line,
  whose weekly budget (budget.md) covers the stage: you do not ask before each workflow (root `CLAUDE.md`);
- where a model beyond the shared list may run, if anywhere (the model-guard ADR's amendment A: stage designs,
  second reviews of PRs that touch `core/ server/ net/ tests/harness/`, audits, a task red twice), and its share of
  that model's own weekly window (at most half across all tracks). You stay on the shared models;
- the rules: you merge into `release/m<k>` and, through the gate, into `main` (§5); you close issues, workflow
  agents never; each agent only in its worktree; no `git stash`; temporary files in the scratchpad or `tests/scratch/`; Godot
  windows only through `shot`; a game rule no ADR settles becomes options under "Needs the engineer"; `content/`
  and `levels/` files are provisional;
- the engineer's standing decisions to honour, with where each is recorded; known traps; what to drop first;
- reporting: a comment on the plan issue after each wave; stop with a comment when nothing more can run without
  the human (answers, a design review, the milestone's go); "продовжуй" resumes after a check of the live state.

Something missing: ask once, batched, with a recommendation for each item. Then, always, restate in the human's
language the waves, the ownership splits, the merge order, the agent count per workflow and the rough cost as a
percentage of the weekly limit (budget.md's cost per task). Within the track's weekly budget (else 15% of the
week) and with no "ask and wait" item (the trust ADR's tiers), the restatement is a report and you go on; above it,
wait for their yes. That covers every later `issue-task` and `pr-rebase` run of the stage; a new kind still asks.

**The week's budget** (the engineer's answers of 2026-10-05): read [budget.md](budget.md) now and before each wave.

**Prerequisites** (check them before the restatement): the human pulled `main` in `D:\prime-game` after saving all
scenes in the editor, and `D:/prime-game/.claude/workflows/issue-task.js` exists (`Test-Path`) and knows the v2 args
(`Select-String -Path D:/prime-game/.claude/workflows/issue-task.js -Pattern plan_review -Quiet`: an older copy logs
and ignores them, so the reviews they add would silently not run). The merges of §5 need `merge-check` and `merge`
in the main checkout's runner (`tools\run.cmd merge-check --help`, #181; merges into `main` need `--dry-run` in
`tools\run.cmd merge --help`, #300: without it, the engineer merges those). Missing: ask the human to pull; a session
opened before the pull needs `/reload-skills` to find the workflows by name.

**Your effort is high, not xhigh** (the effort ADR's amendment of 2026-10-04, #308), as for the art and UI sessions:
the human sets it in the session settings; `effortLevel` never goes into shared settings.

## 2. Before the first launch
1. `tools\run.cmd doctor --quick`. Read the plan issue, every issue in scope with its comments, the handoffs they
   build on, and the ARCHITECTURE sections and ADRs they name.
2. **Find live runs of other sessions.** An earlier manager's workflows may still run (a crash, or a handover that did
   not stop them). Treat as owned by a live run, until the human says otherwise: an issue In progress with no PR, a
   worktree with a commit in the last hour (`git -C <wt> log -1 --format=%cr`), a rebase in progress (`git -C <wt>
   status`), and every run listed as running in the plan issue's latest wave comment. List them in your batched question
   and never `start`, launch or rebase them before the answer: `start` on such an issue succeeds silently (it resumes
   the branch and worktree as they are), and a second implementer then works beside the first. A second live
   manager of your track (#484; [handover.md](handover.md) §3): stop before any launch or merge and ask.
3. **The design gate.** Code tasks wait until the stage's design PR has the engineer's review. If the design task
   has no PR yet: when another session runs it, your first wave is empty (post a plan-issue comment saying you wait
   for it, and stop); otherwise the first wave is that design task alone (`design: true`). Offer fillers that do not
   depend on the design meanwhile.
4. **Opening the stage's issues** from a design handoff (its `proposed_issues`) and the engineer's review: create
   them without waiting for a "yes" and report the list and the order (an accepted design; the trust ADR). For
   each, a body file under `<scratchpad>/manager/` with Goal, Acceptance criteria (a checklist), Out of scope, Verification, `Depends on #…`
   and `Tracking: #<plan>`, and `gh issue create --title "<area>: <what>" --label area:<x> --milestone M<k>
   --body-file <file>` (one `area:` label, which `start` needs for the branch prefix). Put the new numbers in a
   plan-issue comment.
5. **The release branch** (a milestone only, once, after the yes): from the main checkout, without leaving your
   shell anywhere else, `git fetch origin && git branch release/m<k> origin/main && git push -u origin release/m<k>
   && git worktree add D:/prime-game/.claude/worktrees/release-m<k> release/m<k>`. That worktree is yours (§5); say
   both in the first wave comment.
6. Write a state file in your session scratchpad, `manager/state.md`: running runs (runId, issue, worktree), the
   queue, ownership splits, merge order, open questions, the session's, the stage's and the current wave's start
   times, and the keep-alive timer and wake count (§7). Keep it current: it survives compaction. Keep no args files:
   `tools\run.cmd wave --args <n>` prints a task's args from your transcript (#277). The scratchpad is per session,
   so every wave comment also carries what a successor needs (§6).
7. Find the files that tasks running in parallel will all touch (mode `.tres` files, `docs/ARCHITECTURE.md`,
   registries, event folders) and split ownership **up front**: who owns which class, which task creates which
   shared class (same path and class name if two may create it), whose deal places what. Otherwise add/add
   conflicts and duplicate work follow.
8. **Files shared across tracks** (the engineer's answer N5 (c); AGENT_WORKFLOW §7.1 "Parallel tracks"):
   `.claude/workflows/` and this skill change only through the tooling track (#170): an issue there, landing between
   the other managers' waves, since a change in the middle of a wave breaks their resumes (§7). A task of yours may
   change `tools/runner/` or `docs/AGENT_WORKFLOW.md`, merged between waves after `merge-check`. `merge-check` also
   pairs your PRs with every open PR into another base when both change a shared file (`tools/`, `.claude/`,
   `.github/`, `docs/AGENT_WORKFLOW.md`; its table "across bases", #207). A flagged pair: name it on that track's
   plan issue; the PR into `main` merges first (through the gate, §5), the milestone takes `main` in
   (`merge --sync-main`, §5) and its PR is rebased on that before it merges (what you do meanwhile: §5).

## 3. Launching a task
1. `tools\run.cmd start <n> --base release/m<k>` (plain `start <n>` on the tooling track; `--base <parent branch>`,
   a branch on origin, for a task stacked on an unmerged PR) in **your** session, from the main checkout, never in
   an agent. From its output take the `WORKTREE <path>` line and the branch from the last line, `start: <branch> in
   the worktree <path>`.
2. Launch the saved workflow `issue-task` (`.claude/workflows/issue-task.js`; the Workflow tool with
   `name: "issue-task"`, or `scriptPath` to that file in the main checkout) with `args` as a JSON object. Before
   each launch: [budget.md](budget.md)'s PC cap, its 93% stop and its args on every launch.

| arg | what |
|---|---|
| `n`, `title`, `wt`, `branch` | the issue, its title, the worktree path, the task branch (required) |
| `base` | the PR base: `"release/m<k>"`, or the parent's branch for a stacked task (`main` outside a stage and on the tooling track); every non-`main` base reaches `gh pr create --base`, a release base also `publish --base` (a parent's branch does not: publish follows the PR's live base) |
| `notes` | the task's specifics, the engineer's answers that apply, ownership splits, merge order (required) |
| `coord` | what runs in parallel now and which shared files to touch minimally |
| `decisions` | the engineer's standing decisions, each with where it is recorded (every task that they touch) |
| `reading` | overrides the default reading list (the issue's links, handoffs and ADRs, the ARCHITECTURE sections it names by section, the code; area CLAUDE.md files and rules load by path, #339) |
| `testing` | overrides the default test expectations, which follow the branch's area: `core` a seeded Match and `view_of`; `net`/`server` loopback-transport tests plus the ENet runs in verify; `tooling` the runner selftest; others generic |
| `design` | `true` for a docs-only design task: options for the engineer, a proposed issue split, the netcode reviewer, effort xhigh |
| `effort`, `plan`, `manager` | implementer effort (default high), the plan issue (default 30: set it), your name in prompts ("the M3 manager session") |

**Pipeline v2 args** (AGENT_WORKFLOW §7.1), off by default but `bounded_waits` and `lean`; the agents each adds count
toward the number per workflow the kickoff approved:

| arg | when | adds (tool calls each) |
|---|---|---|
| `plan_review: true` | the issue's Files line touches `core/ server/ net/ tests/harness/`, or its Size is M or more | 2: a plan agent (80) and a fresh critique (40) |
| `test_review: true` | the same paths, once `mutants` (#184) is on the task's base (`git show origin/<base>:tools/runner/mutants.py`) | 1 (60); none for a design task or a diff without `core/ server/ net/ client/ voice/` code |
| `second_review: true` | PRs that touch `core/ server/ net/ tests/harness/`, where the kickoff asks for it; with `models.second_review` where it allows a model beyond the shared list there | 1 (60) where the netcode review is routed |
| `skeptic: <n>` or `true` | design tasks and audits (publishers judged only 8 of 441 findings wrong) | 1 per blocker or major checked (30) |
| `visual: true`, a scenario or a list | `client/` UI and camera tasks, once `playcheck` (#186) is on the base; the notes name the scenarios | 0 |
| `bounded_waits` | the default since #411 (no tool call of `issue-task` or `pr-rebase` blocks over 240 s, so their 5-minute cache stays warm; on a base without `wait`, #303, the agents wait in the foreground): pass nothing; `false` only to resume a run launched before #411 without the arg | 0 |
| `efforts: {role: level}` | try `{godot: "medium"}` and compare its majors with `metrics` | 0 |
| `models: {role: model}` | only where the kickoff allows a model beyond the shared list: `implement` of a stage design or of a task red twice (§4), `second_review`; and `publish_clean: "sonnet"` on every non-design `issue-task` launch (budget.md, N5; not `pr-rebase`: it has no publisher and rejects the role) | 0 |
| `lean` | the default since #458 (the engineer's N4 (b), 2026-10-06; the implementing and publishing agents run as `task-implementer` and `task-publisher`, whose files must be in your checkout: a run's `agent-*.meta.json` shows the `agentType`): pass nothing; `lean: false` is the exception, for a task whose agents need a skill through the Skill tool (editing `.claude/workflows/` used `workflow-authoring`) or to resume a run launched before #458 without the arg | 0 |

- **`models`** follows the script's fallbacks: set only `implement`, `second_review` or `publish_clean`,
  never `review` or `netcode` (`review` also covers `plan_review`, `netcode`, `skeptic` and `second_review`; `netcode`
  covers `second_review`). `plan` follows `implement`, so a red-twice launch with `plan_review` plans on that model
  too unless you also set `models.plan: "opus"`. `publish_clean` falls back to `publish` and applies only to the full
  publisher of a run with no blocker or major left open (a skeptic-refuted one is closed), never to a design task;
  leave `efforts.publish_clean` unset, so only the model varies. Other models never as a habit or for yourself.
- **Staying within the approved count A.** An `issue-task` launch runs at most 5 agents (the implementer, up to three
  reviewers, the publisher) plus what each option you pass adds. For a design task or an audit pass `skeptic: A −
  that sum` when it is at least 1, else leave `skeptic` out; `true` (a skeptic on every blocker or major) only when
  the kickoff set no cap (the manager's decision on PR #193). `pr-rebase` the same way, from at most 4 (§5).

The workflow: (with `plan_review` a plan agent and a fresh critique of its plan first) implementer (commits, verify
green, never publishes) → fresh reviewers in parallel, chosen from the changed paths (`code-reviewer` always;
`netcode-security-reviewer` for `core/ server/ net/ client/ tests/harness/` or a design task; `godot-api-checker`
for `.gd .tscn .tres`; then, when passed, the second netcode review, the test review with `mutants` and a skeptic per
blocker or major) → publisher (fixes blocker, major and cheap minor findings, `publish` (`--base` for a release
base), PR with a findings table, "Needs the engineer" and "Merge order", CI watch with at most two fix rounds,
handoff, board In review). It throws when any routed agent returns nothing, and stops unpublished when the
implementer ends red. Every agent writes temporary files only under the scratchpad subfolder `a<n>/`.

Notes that worked: say which PR a needed file comes from if it is unmerged ("build with fixtures, fetch and rebase
once it lands"); repeat rules that force fixture updates in every later PR (neutral class defaults with the numbers
in the data); name a task's merge order relative to the other open PRs; name every rename in both tasks' notes (§9).

## 4. On each completion
Read the compact result (#386): `pr_url`, `published`, `ci_green`, `stopped`, `needs_engineer` and `human_steps` in
full, `not_fixed` and `merge_notes` cut to a line, `fixed` and `reviews` as counts (findings by severity); with v2
args also `plan`, `test_review` (mutants by result, or why skipped or missing), `skeptic` (counts), `visual` (PNGs the
engineer drags into the PR) and `publish_clean`. The whole texts are in the run's `journal.jsonl` (`full` says where;
a `result` line has the `key` of its agent's `started` line): read it only when a field you act on points there.
`handoff_posted` or `board_in_review` false: post the handoff or `board move <n> in-review` yourself. Merge it into
its base when the gate in §5 holds (on the tooling track into `main`), and tell the human what you merged and in which
order, one line per merge into `main`; explain each "Needs the engineer" item in plain words: a concrete scenario of
what goes wrong, the options, your recommendation, numbered so they can answer "1A, 2B". End every message to the
human with one short "For you:" block in their language, numbered, listing only what needs them now (a merge the gate
refused, a decision, a command), or "nothing"; the rest goes into the wave comment. Copy every `human_steps` command
into the chat itself, never only a pointer ("it is in PR #235's body"; fetch what a step only points to): one fenced
PowerShell block each, run or previewed by you first (root `CLAUDE.md`, "Talking to the humans"); the PR and the wave
comment may carry it too. Each item is `{why, command}`: `command` is one PowerShell line, which you check starts with
`cd <absolute folder>;` and copy as is under its `why`; an empty `command` is a click or a decision you tell in plain
words; a plain string (a run before #266) likewise. Then fill the free slot.
<!-- see docs/interventions/2026-10-03-engineer-commands-in-the-chat.md -->

When something failed (never resume a run whose result has `stopped`: a resume replays the stop):
- `stopped` (the implementer ended red) or `published` false: say so on the plan issue and in chat, then launch
  `issue-task` once more as a **fresh** run with the failure added to `notes` (its issue comment or the journal); the
  implementer continues from the worktree's commits. Red again: stop that task and ask the human; where the kickoff
  allows a model beyond the shared list for a task red twice, offer a third launch with `models.implement` (§3).
- `stopped` after `tools\run.cmd mutants` exited 2 (a scratch worktree could not be removed, or the task's
  `git status` changed during the run): nothing was published. Read the stop comment on the issue. Only when it
  names a leftover worktree under the task worktree's `tools/out/mutants/`, ask the engineer to remove it (a delete
  outside your worktree prompts; #184's next `mutants` run also removes it first). Then relaunch fresh with the stop
  in `notes`: a resume would replay the cached exit 2.
- `ci_green` false after the publisher's two rounds: the same, with the failing check in `notes`.
- `not_fixed` items: list them in the wave comment; they are the engineer's to accept or turn into issues.
- A fresh relaunch is a launch like any other: it takes budget.md's args (`lean`, `models.publish_clean`).

**Answers.** Post them in English on the PR and the issue ("The engineer's answers (chat with the manager session,
<date>)"). Carry an answer that belongs to a later task to that issue as a comment; open a new issue for a decision
that changes shared design. An answer with two readings that build different things is read back in one sentence
(AskUserQuestion; a session a scheduled task started has none: plain chat, §7) before it is recorded; if the human
dismisses the question and explains, read back again. An answer that changes a published PR: a trivial one inline in
its worktree, in a subshell (§9), then
`publish --base release/m<k>` in the background with `wait <log>`; otherwise `issue-task`
again for that issue with the answers in `notes` (its agents find the branch and the PR and continue).

## 5. Merges and rebases
You merge task PRs into `release/m<k>`, and PRs into `main` through the gate of `merge <pr> --base main`
([release-branch ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md),
[trust ADR](../../../docs/decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)). A typed `gh pr
merge` stays denied: you merge only with `tools\run.cmd merge` (#181, #300; AGENT_WORKFLOW §7.1 Git flow). Run
`merge` and `merge-check` from the main checkout: your `release-m<k>` worktree has them only once `release/m<k>` has
taken in a `main` that has them.
- **The gate.** Merge a PR only when CI is green, the fresh reviews left no open blocker or major (the PR's
  findings table and `not_fixed`; one that waits for the engineer waits for the merge too: write its answer as
  "Answered: <link>" at the end of the item, `gh pr edit --body-file`), and, into `release/m<k>`, `verify` is green
  on the merged tree (`merge` checks CI and runs that `verify`; into `main` it checks the rest of the gate instead).
- **Before every merge: `tools\run.cmd merge-check --base release/m<k>`** (seconds, no Godot): each open PR onto
  its base tip and each pair into it, textually and by symbols (what one side removes or changes and the other's
  added lines use; a signature that only appends parameters with defaults is a note), plus the pairs across bases
  that change a shared file (§2.8); Markdown tables for the wave comment; exit 1 on a conflict, an overlap or a PR
  it could not check. An overlap is a lead, not a proof. When it flags the PR you are about to merge, either merge
  the side that changes the symbol first and send the other to `pr-rebase` (inline for a docs or test-list
  conflict, below), or first run `tools\run.cmd merge-check --trial <pr> <pr>... --base release/m<k>` with
  `run_in_background` (the base plus the PRs merged in that order in a scratch worktree, then `verify`): green,
  merge in that order; red, merge the first and send the later PR to `pr-rebase` with the trial's log in `why`. A
  chain you merge in one go gets a trial too.
- **Flagged across bases** (your PR and an open PR into `main`, §2.8): `--trial` takes one base, so hold that one PR
  and merge the rest of the wave. Name the pair on your plan issue and the other track's; the `main` side merges
  first (its manager's gate notes the pair). Once it is on `main`: `merge --sync-main`, then the held PR to
  `pr-rebase` (inline for a docs conflict), then merge it. If the `main` PR is still open when everything else of
  the stage is merged, it goes into your "For you:" block: the engineer chooses the order.
- **The merge:** `tools\run.cmd merge <pr> --base release/m<k>` with `run_in_background` (12 to 14 minutes on this
  PC: a fresh import plus the whole suite). It refuses any base but `release/*` and `main`, and a task's checkout;
  a PR a human already merged is only fetched (the engineer merged #107 himself); otherwise it checks CI, merges
  `--no-ff` in a scratch detached worktree at `origin/release/m<k>`, runs `verify` on the merged tree, pushes the
  merge commit by hash, confirms the PR merged on GitHub and prints one `wave:` line: paste it into the wave comment.
  A red `verify` or a conflict pushes nothing and leaves nothing to undo (logs and GdUnit reports in
  `tools/out/merge-logs/`): tell the human and relaunch the task with the failure in `notes`. Never type its git
  steps by hand: the guard asks for them, and the deny rule `git push *HEAD*` refuses `HEAD:`.
- **Taking `main` in** (the engineer's answer N2): when the tooling track's manager says on your plan issue that
  `main` has a change the stage should take in, run `tools\run.cmd merge --sync-main --base release/m<k>` at the
  next wave boundary (no merge in flight), with `run_in_background`: `origin/main` merged into the release branch the
  same way, `verify` on the merged tree, the push by hash. Then `merge-check --base release/m<k>` again (the open
  task PRs onto the new tip); both go into the wave comment.
- **Order.** Stacked PRs: the parent first. Never merge a parent while its child's workflow has not reached Publish:
  the merge deletes the parent branch the child's reviewers diff against and its publisher targets. If it happened
  anyway, relaunch the child fresh with `base: "release/m<k>"` (its `wave --args <n>` with the new base) once the
  running one ends.
- After each merge: `gh pr list --state open --json number,headRefName,baseRefName,mergeStateStatus` (`UNKNOWN` just
  after a merge: ask again). A child still based on the merged parent: `gh pr edit <child> --base release/m<k>`.
- Never touch a worktree whose workflow is still running, yours or another session's (§2.2).
- A docs or test-list conflict: resolve inline in that task's worktree, each command in a subshell
  (`(cd <worktree> && git fetch origin && git rebase origin/release/m<k>)`, keep both sides, `verify`, then
  `(cd <worktree> && tools/run.sh publish --base release/m<k>)`, both in the background with `wait <log>`), then a
  PR comment listing the conflicts. The guard lets a rebase through without a prompt when the command enters the
  worktree with `cd` (or `git -C`) and it is on its task branch (AGENT_WORKFLOW §8.2, #51); while another live
  session works in that worktree it asks, so hand such a case to `pr-rebase` when the human is away.
- A semantic conflict (two PRs creating the same classes, a changed interface): the saved workflow `pr-rebase`
  with args `{n, pr, wt, branch, base, why, steps, focus}` (`base: "release/m<k>"`) and its v2 args
  `second_review`, `skeptic`, `bounded_waits`, `efforts`, `models` and `lean` (roles rebase, review, netcode, second_review,
  skeptic, fix; the rules of §3): rebase agent → fresh reviewer(s) → a fix agent only for a blocker or major; 2 to 4
  agents, plus 1 for `second_review` and 1 per skeptic. `why` names what merged and the PRs and handoffs to read;
  `steps` says which side's files and payloads to keep. A result with `stopped` (rebase red or unpublished) gets one
  fresh relaunch with its `problems` in `steps`, then goes to the human. A result with `note` (skeptics refuted every
  blocker and major, so no fix agent ran): add its `refuted`, each with its reason, to the PR body (`gh pr view <pr>
  --json body -q .body` into a file under `<scratchpad>/manager/`, append, `gh pr edit <pr> --body-file <file>`). A fix
  agent that changed netcode-relevant code gets a fresh `netcode-security-reviewer` before the merge (§9).
- **Into `main`** (the tooling track, #170, and a milestone's closing PR): `tools\run.cmd merge-check --base main`,
  then `tools\run.cmd merge <pr> --base main --dry-run` (seconds), then without it. The gate (AGENT_WORKFLOW §7.1)
  refuses with every reason: a red, pending or missing CI, a draft, not the engineer's PR or session, a head behind
  `main` (a background `publish` with `wait <log>` in its worktree, or `pr-rebase` when its `gate: note:` lines name an
  overlap, then CI), the exceptions (the designer's area without the relay phrase or approval; `.claude/settings*.json`,
  `.claude/githooks/`, the guard; an ADR without "Approved by the engineer: <link>"), an open "Needs the engineer" item.
  An exception goes into your "For you:" block; the rest you fix and run again. Each merge leaves the other PRs behind
  `main`: two or more go through `tools\run.cmd merge-train <pr>... --base main` (#387; `--dry-run` first, then in the
  background, `wait` on its log): per PR in order, publish in its worktree (a red verify retried once), CI, the gate; a
  PR that fails is skipped with the reason and the train goes on. After each merge: one chat line ("merged #N into main
  as <sha>"), the `wave:` line in the wave comment, a note on a running milestone's plan issue that needs it (`merge
  --sync-main`). `main` broken by your merge: a revert PR (`git revert -m 1 <merge>`) through the same gate; tell the
  engineer. "стоп мерджі": no merges into `main` until the engineer lifts it; record it on your plan issue and #170.
- **The stage's end.** When every task is merged, open the PR from `release/m<k>` into `main` (`gh pr create --base
  main --head release/m<k>`; M3: #117): a table of the task PRs with their merge commits, every open "Needs the
  engineer" and "Needs the designer" item, and the issues to close after the merge (`Closes` does not fire from the
  release branch). Open it only when no task PR still targets `release/m<k>`: merging it deletes the branch
  (auto-delete) and GitHub retargets such a PR to `main`. Run `merge-check --base main` and put its table in the PR.
  Ask the engineer for the milestone's go (a playtest, their human checks done or postponed); record it as a PR
  comment, add "Approved by the engineer: <its link>" to the body and merge it with `merge <pr> --base main`. Then
  close the stage's issues (a comment linking the PRs and merge commits) and remove your release worktree.

## 6. Reporting and keeping slots busy
- After each wave, a comment on the plan issue: merged PRs (each `merge` `wave:` line), decisions recorded (with
  links), issues opened and closed, housekeeping done, in progress, order from here, batched questions (numbered,
  recommendations). Close an issue yourself once its work is on `main` and its acceptance criteria are met (a
  comment linking its PRs and merge commits; workflow agents never close one). Never edit the plan issue's body.
- In the chat, after each wave: one line per merge into `main`, then the "For you:" block (§4), with the wave's
  housekeeping the human must run batched into it once (§8), not after each PR.
- **The wave's cost**, in every wave comment: the output of `tools\run.cmd metrics --since <wave start> --session
  <your session id> --compact` in a text block (at most ten lines: time and API list $ per task and in total, the %
  of the weekly limit, verify). The wave start is UTC ISO 8601 (from the state file); your id is
  `$env:CLAUDE_CODE_SESSION_ID`. A run counts in the window it started in (with what it had spent so far, if still
  running), so a task that spans waves shows up only partly: add the stage's running total, the `total API list $`
  line of the same command with `--since <stage start>`. This block is the second thing to drop when the budget
  runs out, after the kickoff's first. Where a launch ran a model beyond
  the shared list, add that model's line from the desktop app's `get_usage` tool (the session-management MCP
  server; its `plan` part lists the per-model weekly limits with % used and reset time): `metrics` has no price for
  it and weighs it at Opus rates.
- **The budget line** of [budget.md](budget.md) ("Reading the spend", `metrics --track`), in every wave comment.
- **Merge safety**: the latest `merge-check` result, or its table when it flagged something.
- **Handover data** in every wave comment, which `tools\run.cmd wave --since <wave start>` writes from your
  transcript (#277; no args files): each running run's args as launched (worktree included), its runId and your
  session, and each failed, killed or stopped run since then not yet relaunched. A successor (§7) relaunches from it.
- Keep every slot busy: when the next task waits for a merge, start what does not depend on it (a task's
  independent part with a "fetch and check whether X is on origin/release/m<k>" step, fillers, the next milestone's
  design task). When nothing more can run without merges or a design review, say so in a plan-issue comment and stop
  (§7: a keep-alive timer or a handover).
- Tasks that edit `.claude/` (any path) or `addons/` prompt unless the session runs in bypass: run them only while
  the human is present.

## 7. Resume after a crash, a restart or a plan limit
- A workflow throws when an agent returns nothing. Relaunch it the same way (name or `scriptPath`) with
  `resumeFromRunId` and the **same args** (`wave --args <n>`, v2 args included): finished agents return their saved
  results. A resume replays agents only while their prompts are unchanged, so it needs the same script too: if `main`
  changed `issue-task.js` since the launch, expect the changed agents to run again.
- A result with `stopped` is never resumed (§4): relaunch fresh.
- A stacked task whose parent has merged since the launch: do not resume; relaunch fresh with
  `base: "release/m<k>"`.
- After a PC restart or a crashed session: reopen the same session (`claude --resume`, or the app) and resume each
  run as above. In a **new** session there is no run to resume ("nothing to resume") and no old scratchpad: take
  each run's args from the latest wave comment on the plan issue (§6), confirm with the human that the old session
  is closed, and launch `issue-task` afresh with those args; the implementer finds earlier commits and uncommitted
  files through `git status`, the publisher an existing PR through `gh pr list`.
- A plan limit: with `autoContinueAtUsageLimit` on, a workflow's agents wait for the reset and continue on their
  own; otherwise they fail and you resume after the reset. While you wait, the keep-alive below is your only timer.
- **Keep the prompt cache warm while you wait** (#305). Your session runs on the 1-hour prompt cache: the first call
  after an idle gap over 1 hour writes the whole context again at $8 per 1M tokens (§9). The keep-alive is **one**
  timer, a background `sleep 3000` (Bash, `run_in_background`, `timeout` 3300000), armed only as the turn-end order says, one at a time (its task id and arm time in the
  state file); it fires before the cache your latest call refreshed expires.
- **A wake is a cheap turn.** Re-read only the state file's keep-alive lines (session start, timer, wake count), not
  this skill or the plan issue. Run the turn-end check and at most one status line for what can change without waking
  you (a PR the engineer merged: `gh pr list --state merged --limit 3 --json number,mergedAt`). Then follow the turn-end
  order, silent unless you hand over or that line needs the human. After 14 wakes in a row
  (about 12 hours; a human message resets the count) arm no more.
- **The turn-end check**, at each turn end, wake and launch: `tools\run.cmd wave --since <session start>
  --no-merge-check --out <scratchpad>\manager\turn-end.md` (about 10 s; never the default `--out`). Its last line:
  `handover due: <why>` or `handover not due` with clauses. Due: the context over 300k or the session over 12 hours old,
  even mid-wave; or, once your runs end, a merge into `main` since your start that changed root
  `CLAUDE.md`, `.claude/rules/` or `.claude/agents/` (agents get your cached copy); until then it says "launch
  nothing new": obey it. "Behind origin/main": this turn's For-you carries `cd D:\prime-game; git pull --ff-only`; hand
  over once it is pulled.
- **The turn-end order**: (1) A handover due and work left: hand over (launch nothing; arm the timer only while (a)
  waits for an agent), even mid-wave, but not while your own `merge`, `merge-train` or `publish` runs; nothing left:
  the final wave comment, no timer. (2) A run of yours in flight: arm the timer (after 14 wakes none). (3) A stop for
  the human, no run in flight: hand over when the verdict says "at a stop for the human: due" (context over 150k),
  work is left and the human is present, else arm nothing. (4) Otherwise arm nothing. Earlier by judgment, and never
  so while the human is away: [handover.md](handover.md) §1.
- **A handover** (#467, #484): follow [handover.md](handover.md) §2: (a) stop the runs, (b) post the handover
  comment, (c) start your successor yourself through the track's scheduled task (route C); nothing is pasted. A
  session a scheduled task started reads its §3 first (no AskUserQuestion, `acceptEdits` at medium effort).
- **Keep your context small**: planning reads, ADR, doc and issue-body drafts, metrics tables and audits go to a
  subagent (Agent tool, Sonnet) that returns at most about 2k characters with links and numbers, or a scratchpad file
  you pass to `gh --body-file` unread. Write no large file yourself.
- "продовжуй" after any break: re-read the live state first (`gh pr list`, the plan issue's latest comments, each
  running run), then the state file, then continue.

## 8. Notifications and housekeeping
- When the human is needed (a refused merge, questions, a stop), end your turn with a short summary, the "For you:"
  block, and send a PushNotification. It is suppressed while the human is active in the session, and the desktop app
  only flashes its icon while its window is in use; a PowerShell toast tests whether Windows notifications work at all.
- Merged tasks' worktrees: once the task's work is on `main` (`release/m<k>` merged into `main`, or the task's PR
  on the tooling track), run `tools\run.cmd worktree-done <n>` (from `D:\prime-game`) yourself when no live session
  sits in that worktree (no workflow of yours running there; a solo session's worktree is its owner's); a worktree
  whose branch never reached main but whose work did (merged into a parent) takes `--pushed` or says so. After the
  closing PR has merged, remove your `release-m<k>` worktree too (`git worktree remove .claude/worktrees/release-m<k>`
  and `git branch -D release/m<k>` from `D:\prime-game`). What you cannot run (it prompts, or a live session holds
  the folder, or the human must pull `D:\prime-game` with the editor saved) goes into the wave's "For you:" block.
- Every housekeeping command the human runs, like every command of `human_steps` (§4), goes into the chat when it is
  due, one fenced PowerShell block per command, starting with `cd D:\prime-game` (or the folder it runs in), for example:
  ```powershell
  cd D:\prime-game; tools\run.cmd worktree-done 42
  ```
  Where running it yourself would do the human's step or prompt, preview it instead (`git worktree list` shows the
  worktree is there; `--dry-run` where the command has one). The wave comment may list it too, never instead.
<!-- see docs/interventions/2026-10-03-engineer-commands-in-the-chat.md -->

## 9. Gotchas

### 2026-09-30 (M2)
- The scratchpad is shared by all agents of all workflows: one overwrote another's `pr_body.md`. Hence `a<n>/`.
- `publish` can fail right after a rebase that changed `tools/runner` (verify ran the old modules): run it again.
  "Could not resolve hostname github.com" is transient: `git ls-remote origin`, then again.
- Intermediate commits after a rebase may not compile (the fix lands at the tip): bisect by PR; merge commits keep
  PRs as units.
- Two verify runs at once in different worktrees can collide (a busy ENet port, a timeout under CPU load; GdUnit4's
  `user://` files too, until #182 gave each worktree and shard its own): the agents rerun once before debugging.
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
  and `pr-rebase` fixed it. `merge-check` now flags such a rename across open PRs (§5), but only once both PRs
  exist: the notes still name it before the second task starts.
- **A `pr-rebase` fix after the review gets a fresh netcode review.** When its fix agent changes netcode-relevant
  code after the reviewers ran, run `netcode-security-reviewer` again before the merge (done by hand for #154).
  `pr-rebase`'s `second_review` runs before the fix agent, so it does not cover the fix.
- **Never `cd <wt> && ...` in your Bash shell**: it stayed inside a worktree twice in M4. Only a subshell
  `(cd <wt> && ...)` or `git -C <wt>`.
- **`§` in args on Windows.** A Python `print` of the args mangled it: pass the args inline in the Workflow call,
  or set `PYTHONIOENCODING=utf-8`.

### 2026-10-02 (the AI productivity track, #170)
- **`publish` after a rebase that changed `tools/runner`** needed a second run twice more (#176, #199): the M2
  gotcha holds; the second run passes.
- **A bare `cd` into a worktree** happened once more in a manager's shell: the M3 rule holds for every manager.
- **A Git Bash path given to `tools\run.cmd`** (`/c/Users/...`) made a stray `D:\c\` folder: Python on Windows reads
  it as a folder on the current drive. Give `tools\run.cmd` Windows paths (`C:/Users/...`); Git Bash paths only to
  `tools/run.sh`.
- **An older `issue-task.js` logs and ignores the v2 args**: a launch from a main checkout that was not pulled runs
  without the reviews they add. Check the prerequisite in §1 first.
- **Numbers** (M4, the pipeline v2 ADR's baseline): about 82 minutes, $24 API list and 0.94% of a Max 20x week per
  task ($25.5 per 1%, #304); a stage's budget in % starts from them.

### 2026-10-03 (round 2's scouting, #170)
- **A manager's context only grows** (round 2's wave 0 on #170, `wf_e55a9be5-eac`): neither manager compacted
  (round 1's 147k to 933k tokens, M5's 184k to 928k); a call on day 2 cost 2.7 and 3.3 times one of the first hours;
  the re-writes after idle hours cost $8.12 (14% of round 1's manager) and $14.06 (19% of M5's). Hence §7's handover.

### 2026-10-04 (the Token efficiency track, #302)
- **Idle re-writes** (#302's report of 2026-10-04, the managers since the plan change): 24 calls after a gap over 1
  hour wrote 0.15 to 0.93M tokens each again, $89.8 list: 11 while their own workflow ran ($38.8), 13 at human
  breaks of 1.0 to 13.5 hours ($51.0). A wake reads the context once ($0.20 per 1M on Opus 5.5: $0.10 at 500k) and
  writes a few hundred tokens; a re-write costs $8 per 1M ($4 at 500k), so 14 wakes (12 hours) cost less than one.
  The keep-alive of §7 saves a net 5.7 limit points at cache-read weight 0 (2.9 at full weight). `metrics` reports
  each manager session's re-writes by what held when the gap began: with a timer armed it should be 0.

## 10. Kickoff template
The human copies it, fills the placeholders and sends it, in English or in their own language; the `Track:` line stays
English (`metrics --track` reads it). Moving state (which issues, which PRs) goes only in the message, never here.

```text
ultracode: orchestrate stage <k> (<milestone>, <theme>) with the skill orchestrate-stage. You are the manager: one
task = one issue-task workflow, at most <n> at once (your track's PC share in budget.md).

Start from: <my review of the design PR #<pr> and its handoff on #<design issue> | the issues below>.
<If from a design: open the stage's issues from that handoff with my review's changes and report the list and the
order.>

<After a handover by the paste (handover.md): Continue from the handover comment <link>; the previous session stopped
its runs (relaunch them fresh) and launches nothing more, and my yes to the stage's restatement stands: restate the
order from there and go on.>
Track: <game | ui | art | meta>. Scope: <issues, or "the issues from the handoff">; fillers: <issues>.
Plan and reports: a comment on #<plan issue> after each wave; never edit its body.
Git flow: <release/m<k> from main; every task PR targets it (start --base release/m<k>); you merge task PRs into it
with tools\run.cmd merge after green CI, fresh reviews with no open blocker or major, merge-check and verify on the
merged tree; you merge it into main through one PR at the end, through the gate, after my go | every PR straight
into main (the tooling track); you merge each with merge <pr> --base main after merge-check>.
Order: <order, or "as in the handoff">; stack with start --base <parent> only where a task depends on an unmerged
PR.
Pipeline v2: <plan_review for core/server/net/tests-harness and size M or more; test_review once mutants is on the
base; skeptic for design tasks; ...>; approved agents per workflow: issue-task up to <A>, pr-rebase up to <B>.
Bounds: implementer ≤ 250 tool calls, reviewers ≤ 60, publisher ≤ 150; plan ≤ 80, its critique ≤ 40, test review
≤ 60, each skeptic ≤ 30. I approve exceeding the size guideline (up to <A> agents per workflow); do not ask before
each workflow. Hand over at §7's turn-end verdict, even mid-wave, and start your successor yourself (handover.md).
Budget: this track's <T>% of the week from the reset <date> 10:00 UTC (budget.md; metrics --track reads it); within
it your restatement is a report; budget.md's rules at 80% and 100%, the 93% stop, the PC cap and the args apply.
Models beyond the shared list: <none | <model> for <stage designs, second reviews of core/server/net/tests-harness
PRs, tasks red twice>, at most <Q>% of its own weekly window>; you stay on the shared models.
Rules: into main only through the gate; you close issues, workflow agents never; each agent only in its worktree;
no git stash; you never leave your shell inside a worktree; temporary files in scratchpad/a<n>/ or tests/scratch/; Godot
windows only through shot; a game rule no ADR settles becomes options with a recommendation under "Needs the
engineer"; content/ and levels/ files are provisional, I approve them in the PR.
My decisions: the ADRs and my answers in the comments of <issues> (newer ones win).
Traps: <known traps>; tasks that edit .claude/ run only while I am around; <decisions reserved for me>.
Drop first if the budget runs out: <fillers>, then the per-wave metrics report, then <lowest-priority task>.
When nothing more can run without me: a comment on #<plan issue> and stop. "продовжуй": check the live
state and continue.
```
