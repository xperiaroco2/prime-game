# Manager rules for every track

The one place for the rules every track's manager session follows: game and meta (`D:\prime-game`, the
`orchestrate-stage` skill and `wave`), UI (`D:\prime-game-ui`), art (`D:\prime-game-art`) and design
(`D:\prime-game-design`, the private design repo's own `design-manager` skill, AGENT_WORKFLOW §7.3, #1124). The UI,
art and design repos' `CLAUDE.md` files point here instead of copying these rules, so a change is made once, in this
file ([#511](https://github.com/xperiaroco2/prime-game/issues/511)). Approved by the engineer:
[#170 comment 6033930486](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6033930486) (the paste,
no "ultracode", 500k, one set of rules), on top of
[#170 comment 6025360550](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6025360550) (thresholds
plus judgment) and [#467](https://github.com/xperiaroco2/prime-game/issues/467#issuecomment-6014950287) (mid-wave).

**Read this file whole at your session's start**, from the main checkout (`D:\prime-game\docs\MANAGERS.md`; missing
or unreadable: the copy on GitHub, https://github.com/xperiaroco2/prime-game/blob/main/docs/MANAGERS.md); after a
change to it reaches `main`, read its diff (§5). Where your repo's own files differ from it on the handover, its
thresholds, the "For you:" block, the kickoff, the effort or a launch's estimate (§9), this file wins. How each track
carries a rule out (its tools, its plan issue, its workflows) stays in its own repo: for game and meta, the
`orchestrate-stage` skill and its `handover.md`.

**How you talk to the engineer** (dictation, plain explanations, a command for a human in the chat, memory, the
dictation glossary, launching a workflow): `D:\prime-game\docs\HUMAN_SESSIONS.md`, read at your start with this file
and again after a compaction (#836). This repo's root `CLAUDE.md` only points to it; the UI and art repos' own files
do not carry it; the design repo's skill reads it at its start.

## 1. The session: mode and effort
- A manager session starts when the engineer pastes a kickoff (§2) into a new session in the track's checkout, or
  when his director starts it on his word (AGENT_WORKFLOW §7.2), with the mode and effort he picks: **bypass
  permissions, effort high**. High, not xhigh: the effort ADR's amendment of
  2026-10-04 ([#308](https://github.com/xperiaroco2/prime-game/issues/308)). `effortLevel` never goes into shared
  settings.
- Your first message says your permission mode and effort. Not bypass or not high: say so in your first "For you:"
  (§3); until he switches them, launch nothing that prompts in your mode.

## 2. The kickoff
- One message, as the engineer wrote it (his language kept). It names the scope, the plan issue for reports, the
  order, the budget as a percentage of the week, the approved agent count per workflow, and a `Track: <game | ui |
  art | meta | design>` line in English (`metrics --track` reads it). Game and meta: the `orchestrate-stage` skill's
  §10 template (its `kickoff-template.md`); design: the design repo's `design-manager` skill's §6, which names no
  stage or agent count (its budget is in `budget.md`, its workflows each ask first).
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
- A decision there is a taste question only (art, visuals, game design, level design, a milestone's goal or
  go/no-go). A technical choice is no item: take your recommended option, merge through the gate, and list it in the
  plan-issue comment with the option taken, so he can reverse it; a technical "Needs the engineer" item in a PR gets
  the standing word's "Answered:" line of the trust ADR's last amendment (`gh pr edit --body-file`)
  ([intervention](interventions/2026-10-29-engineer-asks-only-taste.md); the trust ADR's tiers, amended 2026-10-29).
- The label `For you:` (or `Для вас:`) on a line of its own, then numbered items at the line's start; the same block
  goes, in English, into the plan-issue comment's notes, where the director's `inbox` reads it (AGENT_WORKFLOW §7.2).
- Each item gives a direct link to what he must open (the PR, the issue, the comment) or the ready command itself: one
  fenced PowerShell block per command, starting with `cd` to its absolute folder, run or previewed by you first.
  Housekeeping (a pull of the main checkout, a worktree a live session holds) is batched there once per wave.
- **The designer is optional** (#518, AGENT_WORKFLOW §9): no step, review or merge waits on him. A PR of his goes to
  the engineer, who reviews and merges it: list it in "For you:" with its link; a manager neither merges nor edits it.
  The content area (`content/ levels/ docs/GDD.md docs/design/`) changes on the engineer's word, like any task.

## 4. The keep-alive
- While a workflow of yours runs, one background `sleep 3000` (Bash, `run_in_background`, `timeout` 3300000) keeps
  the 1-hour prompt cache warm, re-armed at each wake, one at a time. At a stop for the engineer (no run in flight),
  arm none: over 250k, hand over instead (§5). A wake re-reads only your state lines (session start, timer, wake
  count) and is silent unless it hands over or needs him. At most 14 wakes in a row (a message from him resets the
  count); none after a handover.
- **Before work that must outlast his presence** (a night, #595): call the desktop app's `request_keep_awake` tool
  (`until: "session_idle"`), and your For-you asks him to leave the lid open and the machine on mains power, sleep
  "never" on mains (a closed lid or a manual sleep still sleeps). A run the machine slept through stops red at the
  resume ("the machine slept or was suspended"): relaunch it fresh.
- **A permission card stops the whole session** (#731). While a call waits on one, Claude Code holds every
  notification, from finished runs and from the timer. On 2026-10-09 one guarded cleanup command at 22:06Z kept the
  meta manager silent until 07:29Z. So at a wake (#981: a worktree removal at one held a card 90 minutes), while a run
  is in flight, or before he leaves, run no command the guard asks about (a worktree removal or branch delete outside
  a task's worktree, AGENT_WORKFLOW §8.2). Put it in "For you:" instead. At each wake, run
  `tools\run.cmd wave --stalled` (from `D:\prime-game`, read-only, about a second). It
  names another session that has taken no turn for 30 minutes after a run of its own finished or a notification
  queued, and the card it waits on. Put that line in your "For you:". Send a PushNotification only for a stalled
  session you have not reported at an earlier wake (the line names the session and its last turn), so one night-long
  stall pushes once, not at every wake.
- **The "nobody is watching" sign** (#750). Before a night, and before you leave a run alone with the engineer away,
  run `tools\run.cmd unattended --until <HH:MM>` (or `--hours <n>`, at most 16) in your own session: the guard then
  denies, with its reason and the line "unattended: put this command in the For-you block for the engineer", what it
  would ask about, for you and your workflow agents. It does not remove every card: the `ask` rules of
  `.claude/settings.json` (`gh pr review *`, `Edit(**/.claude/settings.json)`), Claude Code's own checks and, in
  acceptEdits, its prompt for a write outside the working directory still show one, so run none of those either. Put
  such a command in "For you:". Clear it with `tools\run.cmd unattended --off` at his first message, before anything
  else; it also ends at its time. Without the sign nothing changes (AGENT_WORKFLOW §8.2.11).

## 5. When to hand over
- **The thresholds stay mandatory**, day and night: the context over **500k** tokens (to be checked with `metrics`
  after a week) or the session over **12 hours** old. A threshold forces a handover even mid-wave: stop your runs (one
  whose agent publishes, rebases or fixes only after that agent), post the handover (§6); the successor relaunches
  them fresh.
- **Changed instructions are no handover** (#930): after a merge into `main` since your start that changed your repo's
  root `CLAUDE.md`, `.claude/rules/` or `.claude/agents/`, or this file, read its diff (`git fetch origin main`, then
  `git diff` of those paths from `main` at your start; game and meta: the command `wave` prints; this file lives only
  in prime-game: UI and art run it with `git -C D:\prime-game`) and go on. Claude Code reloads agent files from disk
  ([its docs](https://code.claude.com/docs/en/sub-agents)) and rules when a file they match is read, once the main
  checkout is pulled; your workflow agents keep your session's root `CLAUDE.md`, so the next launches get what they need of its change in their notes.
- **At a stop for the engineer** (no run in flight, work left, he is present): hand over once the context is over
  **250k**; otherwise arm nothing. Half the threshold, as 150k was of 300k before #511.
- **Earlier, by judgment**, at a natural break (no run in flight, or a stop for him): when your cost math says a
  fresh start is cheaper: your mean $ per call, last 20 against first 20, times the calls the work left still takes,
  against one start-up (about the first 20 calls).
- **While he is away** (he said so, or his last message is over 2 hours old): no successor starts before he pastes
  its kickoff, so hand over only when a threshold forces it, never by judgment or at a stop; and with runs in flight
  do not stop them: launch nothing new, let them end, then post the handover.
- **At the director's shift change** (AGENT_WORKFLOW §7.2, #1364): a session the director started gets its
  handover request twice a day (a safe point, WIP pushed, the handover of §6, the kickoff sent back to it with
  `send_message`); do it at once, whatever your thresholds say, stopping your runs as at a threshold. The director then clears your session
  (`clear_session`, the same id) and sends you that kickoff, so your handover comment is all your next turn knows.
- How you measure: game and meta, the last line of `wave` at each turn end (the `orchestrate-stage` skill's §7); UI,
  `node tools/manager/context.js` and the session's start; art and design, the app's context usage and the session's start.

## 6. The handover comment and the paste
- **The comment**, on your plan issue, titled exactly "Handover to a fresh manager session" (design: "Handover to a
  fresh design session", with the contents its skill's §5 lists; its ready kickoff is the skill's §6): the order from here, the
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
  (`D:\prime-game`, `D:\prime-game-ui`, `D:\prime-game-art`, `D:\prime-game-design`), set bypass and effort
  high, and paste the kickoff. The item carries the kickoff itself, in a fenced `text` block, and the comment's
  link, so he copies it from the chat. Send a PushNotification, arm no timer, launch nothing more, and stop.
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

## 8. The pointer in the UI, art and design repos
Each repo's `CLAUDE.md` carries this block in place of its own copy of these rules (a pointer, not an `@` import: an
import outside the working directory needs a one-time approval and then loads in every session of that repo, its
workflow agents included; this repo's docs are linked, never imported, AGENT_WORKFLOW §3). `<track>` is `ui`, `art` or
`design`; the last line differs per repo:

```markdown
## Manager rules (one set for every prime-game track)
A manager session of this repo follows `D:\prime-game\docs\MANAGERS.md` (prime-game's main checkout beside this one;
missing or unreadable: https://github.com/xperiaroco2/prime-game/blob/main/docs/MANAGERS.md). Read it whole at the
session's start, before anything else; after a change to it reaches prime-game's `main`, read its diff. It holds the
mode and effort, the kickoff (no "ultracode"), the "For you:" block, the keep-alive, when to hand over and the
handover comment with the ready kickoff the engineer pastes, and every launch's estimate with the check after a large
launch's first phase (§9); where this file differs on those, it wins.
Track: <track>. <UI: Plan issue: xperiaroco2/prime-game#150; the context: `node tools/manager/context.js`. | Art: Plan
issue: the current stage's `plan:` issue in this repo; the context: the app's context usage. | Design: Plan issue:
xperiaroco2/prime-game#1095; the context: the app's context usage.>
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
  ([`orchestrate-stage`](../.claude/skills/orchestrate-stage/resume.md) §7: its finished agents return their saved
  results), never a fresh launch, which pays the first phase again.
- **The check**: `tools\run.cmd metrics --run <run id>` (the Workflow tool's run id, or its start) prints a run's
  spend so far, finished or in flight: its agents started and answered, who works now, its % of the week and its list
  $ by phase, and its cache re-writes after an idle gap when it has one (#558: an agent polling a render or a `wait`
  past 5 minutes writes its whole context again each time), and each agent's average and peak context per API call
  (#584: one at 150k average or 300k peak is marked heavy). UI, art and design run it in prime-game's main checkout
  (`cd D:\prime-game`); it reads all four checkouts' transcripts. The first phase within 1.5 times its share of the
  estimate (1.5: #534's reading, until the engineer confirms it): go on, and the plan-issue comment gives both numbers.
  Over it: re-estimate the rest at the phase's real $ per agent; still within the track's budget left, go on and
  report it; else launch nothing more of it and ask in "For you:" with both numbers and what the rest buys.

## 10. An answer that changes the docs
When you record an engineer's answer that changes a documented flow, rule or number (an ADR, a file under `docs/`, a
skill, a `CLAUDE.md`), open a docs task for it in the same wave, or add it to an open one, and link that task in the
recorded answer ([#905](https://github.com/xperiaroco2/prime-game/issues/905)). An answer left only in a comment drifts
from the docs that still say the old thing: the release-branch ADR and the manager skill outlived the engineer's
"everything into `main`" ([#676 comment 6109559003](https://github.com/xperiaroco2/prime-game/issues/676#issuecomment-6109559003),
#904). The night audit's `decisions` lens finds the ones missed.
