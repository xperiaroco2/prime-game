---
name: orchestrate-stage
description: Run a whole prime-game stage or list of issues as the manager session - one issue-task workflow per task, at most three at a time, merging into release/m<k> and, through a gate, into main while the engineer answers. Use for a manager kickoff that names a stage or a list of issues (one task = one issue-task workflow), "оркеструй етап", "run stage N", or "продовжуй" in a session that already manages a stage.
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
docs, reviews, publishing) runs inside workflows; your inline work is `start`, trivial rebases, opening issues and
posting answers. Talk to the human in their chat language, in plain words; GitHub and the repo are English. Commands:
`tools\run.cmd` (Git Bash: `tools/run.sh`). The method: [ADR](../../../docs/decisions/2026-09-30-orchestrator-session.md).
Git flow: every task PR targets the milestone's `release/m<k>`, you merge task PRs into it and, after the engineer's
go, the milestone into `main` ([ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md)); the tooling
track (#170) sends its PRs straight into `main`, each merged by you through the gate (§5). What you decide alone, tell
at once or ask: the tiers of the [trust ADR](../../../docs/decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md).

**Read on demand.** The core below is what every session needs; the rest is in files beside it, each keeping its §
number (a split section's second part repeats its number). After a compaction, re-read the file of the event in hand.

| § | Read it | File |
|---|---|---|
| §2 (steps 3-5, 7, 8) | a new milestone or stage, a design handoff, tasks sharing files | [stage-setup.md](stage-setup.md) |
| §3 (the args) | composing a launch's `args` | [launch-args.md](launch-args.md) |
| §4, §7 (parts) | a failed or stopped run; a crash, restart, sleep, plan limit or new session with runs | [resume.md](resume.md) |
| §5 | a merge, a rebase, a conflict, `--sync-main`, the stage's end | [merges.md](merges.md) |
| §8 | the human is needed; a merged task's worktree | [notifications.md](notifications.md) |
| §9 | a stage's first kickoff (not a handover's); a failure you have not seen | [gotchas.md](gotchas.md) |
| §1 (part), §10 | checking a stage's first kickoff; writing a handover's ready kickoff (not at your own start) | [kickoff-template.md](kickoff-template.md) |
| budget | the kickoff, each wave, each launch | [budget.md](budget.md) |
| handover | a handover; a session a scheduled task started | [handover.md](handover.md) |

## 1. The kickoff
One message the human pastes into a new session, no "ultracode" in it. Read the rules every track's manager follows,
[docs/MANAGERS.md](../../../docs/MANAGERS.md), whole now. Check a stage's or track's first kickoff against what it must
state, [kickoff-template.md](kickoff-template.md) §1, beside its template (§10); a handover's ready kickoff is that
checked kickoff with a "Continue from" line (handover.md).

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

**Your effort is high, not xhigh, in bypass** (MANAGERS.md §1, #308); `effortLevel` never goes into shared settings.

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

Steps 3 to 5, 7 and 8 (the design gate, issues from a design handoff, the release branch, ownership splits, files
shared across tracks): [stage-setup.md](stage-setup.md).

6. Write a state file in your session scratchpad, `manager/state.md`: running runs (runId, issue, worktree), the
   queue, ownership splits, merge order, open questions, the session's, the stage's and the current wave's start
   times, and the keep-alive timer and wake count (§7). Keep it current: it survives compaction. Keep no args files:
   `tools\run.cmd wave --args <n>` prints a task's args from your transcript (#277). The scratchpad is per session,
   so every wave comment also carries what a successor needs (§6).

**Never leave your shell inside a worktree** (§9): work there only through a Git Bash subshell `(cd <wt> && ...)`,
`git -C <wt> ...` or PowerShell `Push-Location <wt>; ...; Pop-Location`.

## 3. Launching a task
1. `tools\run.cmd start <n> --base release/m<k>` (plain `start <n>` on the tooling track; `--base <parent branch>`,
   a branch on origin, for a task stacked on an unmerged PR) in **your** session, from the main checkout, never in
   an agent. From its output take the `WORKTREE <path>` line and the branch from the last line, `start: <branch> in
   the worktree <path>`.
2. Launch the saved workflow `issue-task` (`.claude/workflows/issue-task.js`; the Workflow tool with
   `name: "issue-task"`, or `scriptPath` to that file in the main checkout) with `args` as a JSON object. Before
   each launch: [budget.md](budget.md)'s PC cap, its 93% stop, its args, its launch check and **the estimate** (#534) of
   [MANAGERS.md §9](../../../docs/MANAGERS.md): any other workflow too, and over about 5% a check after its first phase.

The args, the v2 args, `models`' fallbacks, staying within the approved count and the notes that worked:
[launch-args.md](launch-args.md). Always: `n`, `title`, `wt`, `branch` and `notes`; `base` (`"release/m<k>"`, a
parent's branch, or `main` on the tooling track), `plan` (default 30: set it) and `manager`; budget.md's args.

## 4. On each completion
Read the compact result (#386): `pr_url`, `published`, `ci_green`, `stopped`, `needs_engineer` and `human_steps` in
full, `not_fixed` and `merge_notes` cut to a line, `fixed` and `reviews` as counts (findings by severity); with v2 args
also `plan` (with its comment's link, `clipped` when its result was cut, and the planner's `model`), `test_review`
(mutants by result, or why skipped or missing), `skeptic` (counts), `visual` (PNGs the engineer drags into the PR) and
`publish_clean`. The whole texts are in the run's `journal.jsonl` (`full` says where; a `result` line has the `key` of
its agent's `started` line): read it only when a field you act on points there. `handoff_posted` or `board_in_review`
false: post the handoff or `board move <n> in-review` yourself. Merge it into
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

When something failed (`stopped`, `published` or `ci_green` false, `not_fixed`): [resume.md](resume.md) §4. Never
resume a run whose result has `stopped`: a resume replays the stop.

**Answers.** Post them in English on the PR and the issue ("The engineer's answers (chat with the manager session,
<date>)"). Carry an answer that belongs to a later task to that issue as a comment; open a new issue for a decision
that changes shared design. An answer with two readings that build different things is read back in one sentence
(AskUserQuestion; a session a scheduled task started has none: plain chat, §7) before it is recorded; if the human
dismisses the question and explains, read back again. An answer that changes a published PR: a trivial one inline in
its worktree, in a subshell (§9), then
`publish --base release/m<k>` in the background with `wait <log>`; otherwise `issue-task`
again for that issue with the answers in `notes` (its agents find the branch and the PR and continue).

## 6. Reporting and keeping slots busy
- After each wave, a comment on the plan issue: merged PRs (each `merge` `wave:` line), decisions recorded (with
  links), issues opened and closed, housekeeping done, in progress, order from here, batched questions (numbered,
  recommendations). Close an issue yourself once its work is on `main` and its acceptance criteria are met (a
  comment linking its PRs and merge commits; workflow agents never close one). Never edit the plan issue's body.
- In the chat, after each wave: one line per merge into `main`, then the "For you:" block (§4), with the wave's
  housekeeping the human must run batched into it once (§8), not after each PR.
- **The wave's cost** and **the budget line** of [budget.md](budget.md) ("Reading the spend"), in every wave comment.
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

## 7. Waiting, the turn end and resume
A workflow that threw, a crash, a PC restart, a plan limit, or a new session with runs to take over:
[resume.md](resume.md) §7. A result with `stopped` is never resumed (§4): relaunch fresh.
- **Keep the prompt cache warm while you wait** (#305). Your session runs on the 1-hour prompt cache: the first call
  after an idle gap over 1 hour writes the whole context again at $8 per 1M tokens (§9). The keep-alive is **one**
  timer, a background `sleep 3000` (Bash, `run_in_background`, `timeout` 3300000), armed only as the turn-end order
  says, one at a time (its task id and arm time in the state file); it fires before the cache your latest call refreshed
  expires. A sleeping machine fires no timer: before a night, `request_keep_awake` (MANAGERS.md §4,
  [resume.md](resume.md) §7).
- **A wake is a cheap turn.** Re-read only the state file's keep-alive lines (session start, timer, wake count), not
  this skill or the plan issue. Run the turn-end check and at most one status line for what can change without waking
  you (a PR the engineer merged: `gh pr list --state merged --limit 3 --json number,mergedAt`). Then follow the turn-end
  order, silent unless you hand over or that line needs the human. After 14 wakes in a row
  (about 12 hours; a human message resets the count) arm no more.
- **The turn-end check**, at each turn end, wake and launch: `tools\run.cmd wave --since <session start>
  --no-merge-check --out <scratchpad>\manager\turn-end.md` (about 10 s; never the default `--out`). Its last line:
  `handover due: <why>` or `handover not due` with clauses. Due: the context over 500k or the session over 12 hours old,
  even mid-wave (while the human is away: once your runs end, MANAGERS.md §5); or, once your runs end, a merge into
  `main` since your start that changed root `CLAUDE.md`, `docs/MANAGERS.md`, `.claude/rules/` or `.claude/agents/`
  (agents get your cached copy); until then it says "launch nothing new": obey it. "Behind origin/main": this turn's
  For-you carries `cd D:\prime-game; git pull --ff-only`; hand over once it is pulled.
- **The turn-end order**: (1) A handover due and work left: hand over (launch nothing; arm the timer only while (a)
  waits for an agent), even mid-wave, but not while your own `merge`, `merge-train` or `publish` runs; nothing left:
  the final wave comment, no timer. (2) A run of yours in flight: arm the timer (after 14 wakes none). (3) A stop for
  the human, no run in flight: hand over when the verdict says "at a stop for the human: due" (context over 250k),
  work is left and the human is present, else arm nothing. (4) Otherwise arm nothing. Earlier by judgment, and never
  so while the human is away: [handover.md](handover.md) §1.
- **A handover** (#467, #511): [handover.md](handover.md) §2: stop the runs, post the handover comment ending with
  the ready kickoff, ask the human in your For-you to paste it into a new session (bypass, high), stop. Route C
  (handover.md §3, its successor in `acceptEdits` at medium) only when he asks; a session it started reads §3 first.
- **Keep your context small**: planning reads, ADR, doc and issue-body drafts, metrics tables and audits go to a
  subagent (Agent tool, Sonnet) that returns at most about 2k characters with links and numbers, or a scratchpad file
  you pass to `gh --body-file` unread. Write no large file yourself.
- "продовжуй" after any break: re-read the live state first (`gh pr list`, the plan issue's latest comments, each
  running run), then the state file, then continue.
