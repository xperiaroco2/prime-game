# Manager rules for every track

The one place for the rules every track's manager session follows: game and meta (`D:\prime-game`, the
`orchestrate-stage` skill and `wave`), UI (`D:\prime-game-ui`) and art (`D:\prime-game-art`). The UI and art repos'
`CLAUDE.md` files point here instead of copying these rules, so a change is made once, in this file
([#511](https://github.com/xperiaroco2/prime-game/issues/511)). Approved by the engineer:
[#170 comment 6033930486](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6033930486) (the paste,
no "ultracode", 500k, one set of rules), on top of
[#170 comment 6025360550](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6025360550) (thresholds
plus judgment) and [#467](https://github.com/xperiaroco2/prime-game/issues/467#issuecomment-6014950287) (mid-wave).

**Read this file whole at your session's start**, from the main checkout (`D:\prime-game\docs\MANAGERS.md`; missing
or unreadable: the copy on GitHub, https://github.com/xperiaroco2/prime-game/blob/main/docs/MANAGERS.md), and again
after a change to it reaches `main` (§5). Where your repo's own files differ from it on the handover, its thresholds,
the "For you:" block, the kickoff, the effort or a launch's estimate (§9), this file wins. How each track carries a
rule out (its tools, its plan issue, its workflows) stays in its own repo: for game and meta, the `orchestrate-stage`
skill and its `handover.md`.

## 1. The session: mode and effort
- A manager session starts when the engineer pastes a kickoff (§2) into a new session in the track's checkout, with
  the mode and effort he picks: **bypass permissions, effort high**. High, not xhigh: the effort ADR's amendment of
  2026-10-04 ([#308](https://github.com/xperiaroco2/prime-game/issues/308)). `effortLevel` never goes into shared
  settings.
- Your first message says your permission mode and effort. Not bypass or not high: say so in your first "For you:"
  (§3); until he switches them, launch nothing that prompts in your mode.

## 2. The kickoff
- One message, as the engineer wrote it (his language kept). It names the scope, the plan issue for reports, the
  order, the budget as a percentage of the week, the approved agent count per workflow, and a `Track: <game | ui |
  art | meta>` line in English (`metrics --track` reads it). Game and meta: the `orchestrate-stage` skill's §10
  template.
- **No "ultracode"** in a manager's kickoff. The keyword is only the opt-in for workflows, and its "token cost is not a
  constraint" guidance works against the token efficiency track. The kickoff says **"one task = one issue-task
  workflow"** (UI and art: one task = one workflow of your repo), with the approved agent count: that explicit request
  is the opt-in (Claude Code's workflows docs: "Claude treats a direct request as the same opt-in"), and a saved
  workflow runs by its name.

## 3. The "For you:" block
- Every message to the engineer ends with one short "For you:" block in his language, numbered, listing only what
  needs him now (a merge the gate refused, a decision, a command, a paste), or `For you: nothing.`
  ([intervention](interventions/2026-10-04-engineer-for-you-block.md)). Everything else goes into the plan issue's
  comment.
- The label `For you:` (or `Для вас:`) on a line of its own, then numbered items at the line's start; the same block
  goes, in English, into the plan-issue comment's notes, where the secretary's `inbox` reads it (AGENT_WORKFLOW §7.2).
- Each item gives a direct link to what he must open (the PR, the issue, the comment) or the ready command itself: one
  fenced PowerShell block per command, starting with `cd` to its absolute folder, run or previewed by you first.
  Housekeeping (a pull of the main checkout, a worktree a live session holds) is batched there once per wave.

## 4. The keep-alive
- While a workflow of yours runs, one background `sleep 3000` (Bash, `run_in_background`, `timeout` 3300000) keeps
  the 1-hour prompt cache warm, re-armed at each wake, one at a time. At a stop for the engineer (no run in flight),
  arm none: over 250k, hand over instead (§5). A wake re-reads only your state lines (session start, timer, wake
  count) and is silent unless it hands over or needs him. At most 14 wakes in a row (a message from him resets the
  count); none after a handover.

## 5. When to hand over
- **The thresholds stay mandatory**, day and night: the context over **500k** tokens (to be checked with `metrics`
  after a week), the session over **12 hours** old, or **changed instructions**: a merge into `main` since your start
  that changed your repo's root `CLAUDE.md`, `.claude/rules/` or `.claude/agents/`, or this file (your agents and you
  run on the copy you read). A threshold forces a handover even mid-wave: stop your runs (one whose agent publishes,
  rebases or fixes only after that agent), post the handover (§6); the successor relaunches them fresh. Changed
  instructions with runs in flight: launch nothing new and hand over once they end.
- **At a stop for the engineer** (no run in flight, work left, he is present): hand over once the context is over
  **250k**; otherwise arm nothing. Half the threshold, as 150k was of 300k before #511.
- **Earlier, by judgment**, at a natural break (no run in flight, or a stop for him): when your cost math says a
  fresh start is cheaper: your mean $ per call, last 20 against first 20, times the calls the work left still takes,
  against one start-up (about the first 20 calls).
- **While he is away** (he said so, or his last message is over 2 hours old): no successor starts before he pastes
  its kickoff, so hand over only when a threshold forces it, never by judgment or at a stop; and with runs in flight
  do not stop them: launch nothing new, let them end, then post the handover.
- How you measure: game and meta, the last line of `wave` at each turn end (the `orchestrate-stage` skill's §7); UI,
  `node tools/manager/context.js` and the session's start; art, the app's context usage and the session's start.

## 6. The handover comment and the paste
- **The comment**, on your plan issue, titled exactly "Handover to a fresh manager session": the order from here, the
  open questions, the human steps still due, the stage's start, the runs you stopped (relaunch fresh, with their
  args), every standing instruction he gave in chat since the kickoff (a pause, a changed budget), the UTC time of his
  last chat message, your app session id, and, last in your notes, in a `text` block, **the ready kickoff** (below).
  Game and meta write it with `wave --title "Handover to a fresh manager session" --notes <file>` (wave's own sections
  follow the notes); UI and art by hand.
- **The ready kickoff** is the stage's kickoff as he wrote it (his language, its `Track:` line), with its "Start from",
  "If from a design" and "After a handover" lines replaced by:

  ```text
  Continue from the latest comment titled "Handover to a fresh manager session" on #<plan issue> and every note after
  it: its order from here wins over this kickoff's Scope and Order; the previous session stopped its runs or let them
  end (relaunch fresh the ones that comment lists as stopped) and launches nothing more; my yes to the stage's
  restatement stands: restate the order from there and go on. A standing instruction of mine (a pause, a changed
  budget) is in that comment: obey it.
  ```

  A kickoff that still says "ultracode" loses the word (§2); every other word stays his.
- **Then** your message ends with one "For you:" item: close this session, open a new one in the track's checkout
  (`D:\prime-game`, `D:\prime-game-ui`, `D:\prime-game-art`), set bypass and effort high, and paste the kickoff. The
  item carries the kickoff itself, in a fenced `text` block, and the comment's link, so he copies it from the chat.
  Send a PushNotification, arm no timer, launch nothing more, and stop.
- The successor takes the comment as its starting state, relaunches the stopped runs fresh and takes the stage's yes
  as given: it restates the order and goes on. Before any launch or merge it checks that no other manager of its
  track is live.

## 7. Route C, the optional fallback
- Only when the engineer asks for it (in the kickoff or in chat): the track's one-time Desktop scheduled task
  `<track>-manager`, whose prompt is the ready kickoff plus a line naming the manager's writes, fired a few minutes
  ahead (`fireAt`; [#484](https://github.com/xperiaroco2/prime-game/issues/484#issuecomment-6025677487)). Game and
  meta: the `orchestrate-stage` skill's `handover.md` §3; UI and art: the task created from a session in their own
  checkout, with those steps.
- **Its known limit:** the successor always starts in `acceptEdits` at medium effort, cannot raise either itself, has
  no AskUserQuestion and takes no other session's `send_message`. By day he must raise its mode and effort by hand,
  no less work than a paste; at night it is limited and has little to do without him. Hence the paste by default.

## 8. The pointer in the UI and art repos
Each repo's `CLAUDE.md` carries this block in place of its own copy of these rules (a pointer, not an `@` import: an
import outside the working directory needs a one-time approval and then loads in every session of that repo, its
workflow agents included; this repo's docs are linked, never imported, AGENT_WORKFLOW §3). `<track>` is `ui` or `art`;
the last line differs per repo:

```markdown
## Manager rules (one set for every prime-game track)
A manager session of this repo follows `D:\prime-game\docs\MANAGERS.md` (prime-game's main checkout beside this one;
missing or unreadable: https://github.com/xperiaroco2/prime-game/blob/main/docs/MANAGERS.md). Read it whole at the
session's start, before anything else, and again after a change to it reaches prime-game's `main`. It holds the mode
and effort, the kickoff (no "ultracode"), the "For you:" block, the keep-alive, when to hand over and the handover
comment with the ready kickoff the engineer pastes, and every launch's estimate with the check after a large
launch's first phase (§9); where this file differs on those, it wins.
Track: <track>. <UI: Plan issue: xperiaroco2/prime-game#150; the context: `node tools/manager/context.js`. | Art: Plan
issue: the current stage's `plan:` issue in this repo; the context: the app's context usage.>
```

## 9. Every launch: the estimate, and a check after the first phase
(#534) Approved by the engineer:
[#302 comment 6038401263](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6038401263), item 2. Art's
`wf_45e2297a` went out with no estimate and cost $693, 27% of the week, with 48 agents.
- **Before every workflow launch**, the message that launches it states the estimate: the agents, the rough list $
  and its % of the week (about list $ / 25: cache reads count at 0.75). From `metrics`' task medians (`tools\run.cmd
  metrics --since <the reset> --compact`, its "task medians" line) or the all-in cost per task of row 8 in
  [`budget.md`](../.claude/skills/orchestrate-stage/budget.md) (every track's, re-measured at each reset), times the
  tasks; else from the workflow's own numbers: agents x tool calls each x about $0.10 a call (the 2026-10-07 audit:
  $1,877 in about 17,000 calls; an agent past 200k of context costs more a call). A loop over N items is N times its
  agents. A launch over about 5% also states its first phase's share: that phase's agents x calls x about $0.10, and
  its %.
- **Over about 5% of the week** (one launch; an `issue-task` or `pr-rebase` run is under 1%), the run stops after its
  first phase. A workflow you write returns after its first phase (or takes an arg that runs only it), and the rest
  is a second launch after the check; a saved one you cannot change: stop it once its first phase's agents have
  answered, and after the check go on by relaunching it with `resumeFromRunId` and the same args
  ([`orchestrate-stage`](../.claude/skills/orchestrate-stage/SKILL.md) §7: its finished agents return their saved
  results), never a fresh launch, which pays the first phase again.
- **The check**: `tools\run.cmd metrics --run <run id>` (the Workflow tool's run id, or its start) prints a run's
  spend so far, finished or in flight: its agents started and answered, who works now, its % of the week and its list
  $ by phase. UI and art run it in prime-game's main checkout (`cd D:\prime-game`); it reads all three checkouts'
  transcripts. The first phase within 1.5 times its share of the estimate: go on, and the plan-issue comment gives
  both numbers. Over it: re-estimate the rest at the phase's real $ per agent; still within the track's budget left,
  go on and report it; else launch nothing more of it and ask in "For you:" with both numbers and what the rest buys.
