# Handover to a fresh manager session

How a manager hands its track over to a fresh session and starts that session itself (#467, #484). When a handover is
due is the skill's §7 (the turn-end verdict and order); this file adds the judgment rule, the steps and what the
successor needs. Read it at a handover, and first thing in a session a scheduled task started.

The engineer's rule for every track's manager, game, UI, art and meta (approved by the engineer:
[#170 comment 6025360550](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6025360550)), with route C
in place of its route B after the probe in
[#484 comment 6025677487](https://github.com/xperiaroco2/prime-game/issues/484#issuecomment-6025677487). Earlier
probe data: [6025319228](https://github.com/xperiaroco2/prime-game/issues/484#issuecomment-6025319228),
[6025434392](https://github.com/xperiaroco2/prime-game/issues/484#issuecomment-6025434392). The approved comment names
route B and says nothing about nights: route C and §1's night rule are the meta manager's reading of that probe,
which the engineer confirms in the PR that brought this file (its "Needs the engineer").

## 1. When, beyond the verdict
- **The thresholds stay mandatory**, day and night: the context over 300k, the session over 12 hours, changed
  instructions (§7's verdict).
- **Earlier, by judgment**: at a natural break (no run in flight, or a stop for the human) you may hand over before a
  threshold when your cost math says a fresh start is cheaper: the footer's mean $ per call, last 20 against first 20,
  times the calls the work left still takes, against one start-up (about the first 20 calls).
- **While the human is away** (he said so, or his last message is over 2 hours old; a scheduled task's prompt is not
  a message from him: a successor counts from the time of his last chat message that the handover comment gives, or
  from his own later messages), hand over only when a threshold forces it, never by judgment or at §7's "at a stop for the human: due": the successor starts in `acceptEdits` at
  medium effort, and whatever prompts there waits for him.

## 2. The steps
- **(a)** TaskStop each run the verdict names (a publish, rebase or fix agent at work: after it, the timer armed),
  until the check shows none in flight.
- **(b)** One plan-issue comment, `wave --since <session start> --title "Handover to a fresh manager session" --notes
  <file>`: the order from here, open questions, `human_steps` still due, the stage's start, the runs you stopped
  (relaunch fresh), every standing instruction the human gave in chat since the kickoff (a pause, a changed budget:
  the stored kickoff does not hold it), the UTC time of his last chat message (§1), your app session id (`get_session("self")`), the successor's start (route C at
  its `fireAt`, in `acceptEdits` at medium effort: what prompts there waits for the engineer) and the handover data.
- **(c) Start your successor yourself** (route C); nothing is pasted. Load `mcp__scheduled-tasks__*` and
  `mcp__ccd_session_mgmt__*` with ToolSearch. Never `run_scheduled_task`: a session a scheduled task started is
  refused it, so it does not chain.
  1. The track keeps one task, `<track>-manager`, whose prompt is its standing kickoff (§4 below).
  2. A verdict that says to pull the main checkout: the For-you carries the pull; start the successor once it is
     pulled.
  3. Arm the task: `fireAt` 3 minutes ahead (ISO 8601 with its offset, in the future), `notifyOnCompletion: false`
     (true is refused in a session a scheduled task started), never a `cronExpression`. It exists
     (`list_scheduled_tasks`): `update_scheduled_task` (a new `fireAt` re-arms a one-time task that fired and disabled
     itself), with a new `prompt` only when the stage, the plan issue or the human's kickoff changed (read the stored
     one first from the `path` the list gives), never per handover. None: `create_scheduled_task` with that `taskId`, a
     `description`, the standing kickoff (§4 below) as `prompt` and those fields. The tool takes no folder: the probe's
     tasks, created from a session in `D:\prime-game`, ran there, so create it from your track's checkout and check the
     successor's folder (`get_session`) after its first run. A one-time task fires by itself at its `fireAt`, while the
     desktop app is open.
  4. Once the `fireAt` is past, `list_task_runs` of the task, again after a background `sleep 120`, at most three
     checks (no foreground sleep): a new run is your successor. Then `set_session_effort` on its session (your
     kickoff's effort, else `high`; from its second turn on); a session a scheduled task started may be refused it:
     the successor then runs at medium until the human raises it. No new run after the third check (whether a task
     fires while an earlier run of it still counts as running is not probed): `create_scheduled_task` once more as
     `<track>-manager-<UTC yyyymmddhhmm>` with the same prompt and fields, name it in the handover comment, and check
     again.
  5. One chat line naming the successor ([its title](#<session id>)), its mode and effort, the For-you ("nothing", or
     the pull), a PushNotification, then `archive_session("self")` as your last call; refused (likely in a session a
     scheduled task started), you just stop: no timer, launch nothing more either way.
- **The paste**, only when route C fails (no such tools, a create or update refused, still no run): "For you:" close
  this session and paste the stored task's prompt (else the skill's §10 kickoff with "Continue from" and `Track:`) into
  a new session in the track's checkout.
- The successor takes the handover comment as the skill's §2.2 answer, relaunches the stopped runs fresh and takes the
  stage's yes as given: it restates the order and goes on (the skill's §1 wait does not apply).

## 3. A successor started by a scheduled task
- **The frame.** The app wraps its prompt in a frame ("an automated run", "the user is not present", write actions
  "only if the task file asks"); the standing kickoff's own line names your writes, so you post, merge, launch and
  hand over as the skill says.
- **A second manager of your track** (the skill's §2.2): `list_task_runs` of `<track>-manager` (and of any
  `<track>-manager-<time>` the handover comment names) and `list_sessions`. A live, unarchived run or session of your
  track's manager other than you is another manager, except the predecessor whose app session id the handover
  comment names: a session a scheduled task started may be refused `archive_session`, so it stays listed after it
  stopped; go on, and your first For-you asks the human to archive it. Any other: stop before any launch or merge and
  ask.
- **No AskUserQuestion**: a read-back (the skill's §4) is one numbered question in plain chat, and the answer waits for
  the human's reply there. The app counts the session as unattended: another session's `send_message` to it is refused,
  so relays reach it through GitHub; the human types into it as into any session.
- **Mode and effort.** It starts in `acceptEdits` at medium effort whatever its predecessor's mode, and cannot raise
  either itself (`set_session_permission_mode` is unavailable there): your first message says your mode and effort,
  and its For-you asks the human to switch them to your track's (he can, by hand) when they differ. Until he does,
  launch only what does not prompt in `acceptEdits` (the skill's §6: no task that edits `.claude/` or `addons/`).

## 4. The standing kickoff
What the track's scheduled task `<track>-manager` holds, stored once per stage, so no handover needs a prompt written
by hand. It is the human's kickoff of the stage (the skill's §10) as he wrote it (his language kept, nothing
reworded, its `Track:` line included), with its "Start from", "If from a design" and "After a handover" lines
replaced by these two:

```text
Continue from the latest comment titled "Handover to a fresh manager session" on #<plan issue> and every note after
it: its order from here wins over this kickoff's Scope and Order; the previous session stopped its runs (relaunch
them fresh) and launches nothing more; my yes to the stage's restatement stands: restate the order from there and go
on. A standing instruction of mine (a pause, a changed budget) is in that comment: obey it.
You were started by the previous manager through the Desktop scheduled task <track>-manager (orchestrate-stage's
handover.md). This is a manager session, not a one-off report: as that skill says, you post issue and PR comments,
open issues, run start, launch and stop workflows, merge with tools\run.cmd merge and merge-train, and at a handover
create and update the track's scheduled task (a fireAt 3 minutes ahead starts your successor), set its effort and
archive yourself where the app allows. Your first message says your permission mode and effort and which of these
tools you lack: AskUserQuestion, PushNotification, the session tools, the scheduled-task tools.
```

The UI and art managers work in their own repos (`D:\prime-game-ui`, `D:\prime-game-art`), without this skill or
`wave`: they need their task created from a session in their checkout, holding their kickoff with these two lines,
and the steps above in their `CLAUDE.md` (AGENT_WORKFLOW §7.1).
