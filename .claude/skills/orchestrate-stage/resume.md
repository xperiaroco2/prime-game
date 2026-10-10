# Failed runs and resumes (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it when a result has `stopped`, `published` or
`ci_green` false or `not_fixed` items, when a workflow threw, and after a crash, a PC restart, a sleep, a plan limit
or in a new session with runs to take over; and before a night.

## 4. On each completion (continued from the skill's §4): when something failed
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
- A fresh relaunch is a launch like any other: it takes budget.md's args (`lean`, `models.publish_clean` and `.plan`).

## 7. Resume after a crash, a restart or a plan limit (continued from the skill's §7)
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
- **Keep the machine awake** (#595): on 2026-10-08 the laptop slept from 20:59Z to 07:21Z; every verify in flight hung,
  the keep-alive timer never fired and the night's queue never launched. Before work that must outlast the engineer's
  presence, call the desktop app's `request_keep_awake` tool (`until: "session_idle"`) and ask in your For-you for the
  lid open, mains power and sleep "never" on mains (a closed lid or a manual sleep still sleeps; his power settings
  stay his). A verify (publish's, merge's too) the machine slept through stops red at the resume: its running steps
  say "the machine slept or was suspended (<n> s)", and `wait` says so. Not the change's red: relaunch the run fresh
  with that line in `notes`. `slots --status` marks a slot holder from before the sleep STALE: launch as if it were
  free.
- **The "nobody is watching" sign** (#750): a guard ask is a card that holds your notifications all night (#731). Before
  the engineer leaves, run `tools\run.cmd unattended --until <HH:MM>` in your own session, and `unattended --off` at his
  first message (MANAGERS §4, AGENT_WORKFLOW §8.2.11). It turns the guard's asks into denials; settings `ask` rules and
  Claude Code's own checks still show a card.
- A plan limit: with `autoContinueAtUsageLimit` on, a workflow's agents wait for the reset and continue on their
  own; otherwise they fail and you resume after the reset. While you wait, the keep-alive (the skill's §7) is your
  only timer.
