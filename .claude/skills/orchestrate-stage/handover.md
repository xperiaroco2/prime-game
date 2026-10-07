# Handover to a fresh manager session

How a game or meta manager hands its track over to a fresh session (#467, #484, #511). The rules every track's
manager follows, UI and art included, are [docs/MANAGERS.md](../../../docs/MANAGERS.md): when (its §5), the handover
comment and the paste (§6), route C (§7). This file is how you carry them out here, with `wave` and the
scheduled-task tools. When a handover is due is the skill's §7 (the turn-end verdict and order). Read it at a
handover, and first thing in a session a scheduled task started (§3).

Approved by the engineer:
[#170 comment 6033930486](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6033930486): the handover
goes back to a pasted kickoff by default, and route C, which
[#170 comment 6025360550](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6025360550) and the probe
in [#484 comment 6025677487](https://github.com/xperiaroco2/prime-game/issues/484#issuecomment-6025677487) brought,
becomes a fallback: its successor always runs in `acceptEdits` at medium effort.

## 1. When, beyond the verdict
- **The thresholds stay mandatory**, day and night: the context over 500k, the session over 12 hours, changed
  instructions (§7's verdict; MANAGERS.md §5).
- **Earlier, by judgment**: at a natural break (no run in flight, or a stop for the human) you may hand over before a
  threshold when your cost math says a fresh start is cheaper: the footer's mean $ per call, last 20 against first 20,
  times the calls the work left still takes, against one start-up (about the first 20 calls).
- **While the human is away** (he said so, or his last message is over 2 hours old; a scheduled task's prompt is not
  a message from him: a successor counts from the time of his last chat message that the handover comment gives, or
  from his own later messages): no successor starts before his paste, so hand over only when a threshold forces it,
  never by judgment or at §7's "at a stop for the human: due"; with runs in flight, launch nothing new and post the
  handover once they end instead of stopping them (the verdict's "the human away" clause).

## 2. The steps
- **(a)** TaskStop each run the verdict names (a publish, rebase or fix agent at work: after it, the timer armed),
  until the check shows none in flight. While the human is away: none; wait for them to end (§1).
- **(b)** One plan-issue comment, `wave --since <session start> --title "Handover to a fresh manager session" --notes
  <file>`: the order from here, open questions, `human_steps` still due, the stage's start, the runs you stopped
  (relaunch fresh), every standing instruction the human gave in chat since the kickoff (a pause, a changed budget:
  the stored kickoff does not hold it), the UTC time of his last chat message (§1), your app session id
  (`get_session("self")`, where the tool exists) and the handover data; the notes end with **the ready kickoff** (§4)
  in a `text` block.
- **(c) The paste** (the default): your last message's "For you:" has one item: close this session, open a new one in
  `D:\prime-game` (the track's checkout), set bypass and effort high, and paste the kickoff, which the item carries
  itself in a fenced `text` block, with the handover comment's link. A verdict that says to pull the main checkout puts
  the pull before it, in the same block. Send a PushNotification, arm no timer, launch nothing more, and stop.
- **(d) Route C**, only when the human asked for it in the kickoff or in chat: §3's steps in place of (c).
- The successor takes the handover comment as the skill's §2.2 answer, relaunches the stopped runs fresh and takes the
  stage's yes as given: it restates the order and goes on (the skill's §1 wait does not apply).

## 3. Route C, the fallback
Its known limit (MANAGERS.md §7): the successor starts in `acceptEdits` at medium effort, whatever its predecessor's
mode, and cannot raise either itself.

**Starting it.** Load `mcp__scheduled-tasks__*` and `mcp__ccd_session_mgmt__*` with ToolSearch. Never
`run_scheduled_task`: a session a scheduled task started is refused it, so it does not chain.
1. The track keeps one task, `<track>-manager`, whose prompt is the ready kickoff (§4) plus §4's route C line.
2. A verdict that says to pull the main checkout: the For-you carries the pull; start the successor once it is pulled.
3. Arm the task: `fireAt` 3 minutes ahead (ISO 8601 with its offset, in the future), `notifyOnCompletion: false`
   (true is refused in a session a scheduled task started), never a `cronExpression`. It exists
   (`list_scheduled_tasks`): `update_scheduled_task` (a new `fireAt` re-arms a one-time task that fired and disabled
   itself), with a new `prompt` only when the stage, the plan issue or the human's kickoff changed, or the stored
   prompt lacks §4's lines (a task created before #484, such as the probe's `meta-manager`); read the stored one first
   from the `path` the list gives; never per handover. None: `create_scheduled_task` with that `taskId`, a
   `description`, that prompt and those fields. The tool takes no folder: the probe's tasks, created from a session in
   `D:\prime-game`, ran there, so create it from your track's checkout and check the successor's folder
   (`get_session`) after its first run. A one-time task fires by itself at its `fireAt`, while the desktop app is open.
4. Once the `fireAt` is past, `list_task_runs` of the task, again after a background `sleep 120`, at most three
   checks (no foreground sleep): a new run is your successor. Send the PushNotification of step 5 first; then, only
   while the human is present, `set_session_effort` on its session (your kickoff's effort, else `high`; from its
   second turn on): it may show an approval card, which at night would block your turn before the archive. Refused,
   or the human away: the successor runs at medium until the human raises it (its For-you asks). No new run after the
   third check: `create_scheduled_task` once more as `<track>-manager-<UTC yyyymmddhhmm>` with the same prompt and
   fields, name it in the handover comment, and check again. Still none: fall back to (c), the paste.
5. One chat line naming the successor ([its title](#<session id>)), its mode and effort, the For-you ("nothing", or
   the pull), the PushNotification (sent before step 4's `set_session_effort`), then `archive_session("self")` as your
   last call; refused (likely in a session a scheduled task started), you just stop: no timer, launch nothing more.

**A successor route C started:**
- **The frame.** The app wraps its prompt in a frame ("an automated run", "the user is not present", write actions
  "only if the task file asks"); the route C line names your writes, so you post, merge, launch and hand over as the
  skill says.
- **A second manager of your track** (the skill's §2.2): `list_task_runs` of `<track>-manager` (and of any
  `<track>-manager-<time>` the handover comment names) and `list_sessions`. A live, unarchived run or session of your
  track's manager other than you is another manager, except the predecessor whose app session id the handover
  comment names: a session a scheduled task started may be refused `archive_session`, so it stays listed after it
  stopped; go on, and your first For-you asks the human to archive it. Any other: stop before any launch or merge and
  ask.
- **No AskUserQuestion**: a read-back (the skill's §4) is one numbered question in plain chat, and the answer waits for
  the human's reply there. The app counts the session as unattended: another session's `send_message` to it is
  refused, so relays reach it through GitHub; the human types into it as into any session.
- **Mode and effort.** Your first message says your mode and effort, and its For-you asks the human to switch them to
  bypass and high (he can, by hand; `set_session_permission_mode` is unavailable there). Until he does, launch only
  what does not prompt in `acceptEdits` (the skill's §6: no task that edits `.claude/` or `addons/`).
- **Your own handover** is the paste again (§2 (c)), unless the human asks for route C once more.

## 4. The ready kickoff
What the handover comment's notes end with and the last For-you carries, so no handover needs a prompt written by
hand: the human's kickoff of the stage (the skill's §10) as he wrote it (his language kept, its `Track:` line included,
"ultracode" dropped if an older one has it: MANAGERS.md §2), with its "Start from", "If from a design" and "After a
handover" lines replaced by the "Continue from" line of MANAGERS.md §6:

```text
Continue from the latest comment titled "Handover to a fresh manager session" on #<plan issue> and every note after
it: its order from here wins over this kickoff's Scope and Order; the previous session stopped its runs or let them
end (relaunch fresh the ones that comment lists as stopped) and launches nothing more; my yes to the stage's
restatement stands: restate the order from there and go on. A standing instruction of mine (a pause, a changed
budget) is in that comment: obey it.
```

For route C (§3), the task's prompt adds this line after it:

```text
You were started by the previous manager through the Desktop scheduled task <track>-manager (orchestrate-stage's
handover.md §3). This is a manager session, not a one-off report: as that skill says, you post issue and PR comments,
open issues, run start, launch and stop workflows, merge with tools\run.cmd merge and merge-train, and at a handover
post the handover comment with the ready kickoff for the paste. Your first message says your permission mode and
effort and which of these tools you lack: AskUserQuestion, PushNotification, the session tools, the scheduled-task
tools.
```

The UI and art managers work in their own repos (`D:\prime-game-ui`, `D:\prime-game-art`), without this skill or
`wave`. Their `CLAUDE.md` files point to [docs/MANAGERS.md](../../../docs/MANAGERS.md) instead of copying these rules
(#511; the block each adds is on its issue there).
