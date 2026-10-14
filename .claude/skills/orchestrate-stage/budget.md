# The week's budget (orchestrate-stage)

The rules of the [weekly budget ADR](../../../docs/decisions/2026-10-05-weekly-budget-across-four-tracks.md) as the
engineer chose them on 2026-10-05: every recommendation, N1 (b) to N8 (b)
([PR #403 comment 5992271562](https://github.com/xperiaroco2/prime-game/pull/403#issuecomment-5992271562)). They apply
from the weekly reset of 2026-10-06 10:00 UTC, N5 (the Sonnet publisher) already from the answer; the reset comes
every Tuesday at 10:00 UTC, and a reset by hand (the engineer's spare reset) restarts the counter too: the week's
`--since` is then its time (AGENT_WORKFLOW §11.12, #677). Read this file at the kickoff, before you plan each wave and
before each launch. "Row n" is a row of the ADR's "Measured inputs"; "§n" is a section of the skill: `SKILL.md` beside
this file, or the file its index names for that §.

## The unit
Every budget is a % of the week: (list $ without cache reads + 0.75 x cache-read $) / $23.0, counted from the reset
over all of a track's sessions, its handovers and its other checkout included. `tools\run.cmd metrics` converts; the
weekly counter (the desktop app's `get_usage` tool) is the check.

## Budgets per track
From the reset of 2026-10-13 10:00 UTC, the engineer's answer 1A to the weekly report
([#302 comment 6145513919](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6145513919)):

| track | game | UI | art | meta | the engineer | buffer |
|---|---|---|---|---|---|---|
| % of the week | 34 | 6 | 20 | 12 | 5 | 16 |

- The tracks: **game** (the milestones; `D:\prime-game`, PRs into `main`), **UI** (`D:\prime-game-ui`), **art**
  (`D:\prime-game-art`), **meta** (AI productivity and token efficiency, #170 and #302; `D:\prime-game`, PRs into
  `main`). The engineer's 5% is his own sessions', the secretary's among them (AGENT_WORKFLOW §7.2, #485), until
  he says otherwise. The buffer lies below the 93% stop (below).
- A budget over the trust ADR's 15% is the engineer's yes for the week: within its track's budget a manager launches,
  restates the kickoff as a report and does not ask before each workflow (the trust ADR's amendment of 2026-10-05).
- What a budget buys is planned at row 8's all-in cost, re-measured at each reset (2026-10-13: game 0.60% a run, meta
  0.30% a run, art 0.77% an issue; UI not measured, 1.18% a run before). A run is not a task: relaunches make a game
  PR cost 0.89%, so plan game tasks at that. A day's share (game 4.9%, UI 0.9%, art 2.9%, meta 1.7%) is a guide; the
  weekly budget is the limit.
- From the next reset on, the meta track posts with its weekly report the past week's spend per track against its
  budget and a proposal for the next week's budgets; the engineer's silence keeps the last ones. A workflow that
  gathers it passes the lean types (AGENT_WORKFLOW §5, #466): its gatherers `{agentType: 'lean-reader'}` on Sonnet,
  its verifier (a skeptic) `{agentType: 'lean-reader', model: 'opus'}`, the agent that writes the report or comment
  `{agentType: 'lean-writer'}`.

## Reading the spend
- `tools\run.cmd metrics --since <restart> --track <track> --budget <its %> --compact` (#409; the flags, the plan to
  date and the track order: `metrics --help`). `<restart>` is the moment the counter last restarted (the Tuesday 10:00
  UTC reset, or a reset by hand after it); **never pass a fixed date or the scheduled reset after a reset by hand**: it
  read 103% against the counter's 31% (#677). After a reset by hand the plan to date runs low until the next scheduled
  reset, so hold the track's % against its budget directly.
- A session of your track listed as untracked (a kickoff without the `Track:` line of
  [kickoff-template.md](kickoff-template.md) §10, or with a translated name): count it with `--session <id>=<track>`.
- **The wave's cost**, in every wave comment: the output of `tools\run.cmd metrics --since <wave start> --session
  <your session id> --compact --verbose` (whole lines; the default cuts them at 400 characters) in a text block, written
  straight into the comment's body file, not read (at most ten lines: time and API list $ per task and in total, the %
  of the weekly limit, verify). The wave start is UTC ISO 8601 (from the state file); your id is
  `$env:CLAUDE_CODE_SESSION_ID`. A run counts in the window it started in (with what it had spent so far, if still
  running), so a task that spans waves shows up only partly: add the stage's running total, the `total API list $`
  line of the same command with `--since <stage start>`. This block is the second thing to drop when the budget
  runs out, after the kickoff's first (§6 asks for both in every wave comment). Where a launch ran a model beyond
  the shared list, add that model's line from the desktop app's `get_usage` tool (the session-management MCP
  server; its `plan` part lists the per-model weekly limits with % used and reset time): `metrics` has no price for
  it and weighs it at Opus rates.
- **The budget line**, in every wave comment beside the wave's cost (above): `<track>: <spent>% of <budget>% this week;
  plan to date <p>%; weekly counter <n>% (get_usage)`. When the counter and the line for every session differ by more
  than 3 points, the wave comment says so (the counter also counts the account's sessions outside the three
  checkouts).
- **One run so far**: `tools\run.cmd metrics --run <run id>` (#534) prints a run's agents started and answered, who
  works now, its % of the week and its list $ by phase, finished or in flight: the check after a large launch's first
  phase ([MANAGERS.md §9](../../../docs/MANAGERS.md)).

## When a track's budget runs out (N2 (a))
- **At 80%** of its budget: plan no wave larger than what is left at row 8's cost per task; merges and handovers go
  on.
- **At 100%**: launch nothing and let your runs finish (a killed run's spend is lost and it must run again). Say so in
  the wave comment and ask once in "For you:" for a share of the buffer, with the amount and what it buys. With no
  answer, stop without a keep-alive (§7): a fresh session later costs less than a warm wait of days.
- **The last 24 hours** before the reset (from Monday 10:00 UTC) open every track's unspent budget and the buffer to
  any track with work queued, up to the 93% stop, without asking: what is left at the reset is lost.
- **The 93% stop**, a standing rule: no new launch while the weekly counter reads 93% or more, whatever the track's
  own budget; runs in flight finish. Read the counter before each wave's launches.

## The PC (N3 (b))
- At most **four task workflows of this repo** at once: by day the game 3 and meta 1; at night either track up to 3,
  within the four (the night's long chain: the rhythm below). Each manager keeps to its own share. One art batch at
  a time (headless Blender and off-screen Godot, outside the verify slots); UI is uncapped (no Godot or Blender in
  its checks).
- **A launch only while no run waits for a verify slot**, and while the engineer uses the PC he runs
  `tools\run.cmd slots --quiet <hours>` (one slot for that time).

## Launch args (N4 (b), N5 (a))
Each option is described once, in [launch-args.md](launch-args.md) (the table, its `models` and `checkpoint` rows); here
only what the budget and the trials decide.
- **Always on, pass nothing**: the lean agent types (#458; [lean ADR](../../../docs/decisions/2026-10-04-lean-workflow-agent-types.md);
  also for a task that edits `.claude/workflows/`, #557) and bounded waits (#411); launch-args.md says the rest. A
  resume takes the args of its launch ([resume.md](resume.md) §7).
- **The launch check** (#557): before each `issue-task` or `pr-rebase` launch or resume, `tools\run.cmd agents-check
  --launch` in the checkout you launch from. Exit 1 names a missing or invalid lean agent file, or scripts and agent
  files that differ from origin/main: pull `main` (or have it pulled) and run it again. No arg gets around it.
- **`models.publish_clean: "sonnet"`** (N5; [effort ADR](../../../docs/decisions/2026-09-28-effort-and-workflow-bounds.md),
  [model-guard ADR](../../../docs/decisions/2026-09-28-model-guard-no-fable-in-shared-config.md)): judged again at each
  reset with `metrics`' quality scorecard, and stays until the engineer drops it; check a new pair's first wave with
  `tools\run.cmd agents-check` and `metrics`.
- **`efforts.implement: "medium"`** on a docs-only launch (#982;
  [effort ADR](../../../docs/decisions/2026-09-28-effort-and-workflow-bounds.md) "Decision": docs at medium;
  launch-args.md's `efforts` row says when): `metrics`' output $ table per role, review tier and effort compares those
  implementers with the light tier's at high.
- **`models.plan: "sonnet"`** (#469): the result's `plan.model` shows it; `metrics`' plan phase table compares the plan
  and critique $, the planner files the implementer read again and the critique's findings with the runs before (they
  must not rise).
- **`models.publish: "sonnet"`** on every `pr-rebase` launch (#835, a trial: [model-guard ADR](../../../docs/decisions/2026-09-28-model-guard-no-fable-in-shared-config.md)
  amendments of 2026-10-11 and 2026-10-13): read `tools\run.cmd metrics --since 2026-10-08T12:25:00Z`'s "Sonnet
  publisher trial (#835)" before each wave; once its "Advice (pr-rebase)" is other than "continue", post it on #302
  with the table and stop passing it.
- **Ended 2026-10-13** (#302 comment 6145513919, 3A to 5A): `ab_review` with `models.code`, `models.implement:
  "sonnet"` and `models.publish_findings`; pass none of them.
- **`checkpoint`** (#759, #920): on by default since the engineer's answer 6A (#302 comment 6145513919); pass nothing.
  launch-args.md says the rest.

## Managers (N6 (b), N7 (a))
- **Four managers, one per track**, each in its track's checkout with the `Track:` line in its kickoff
  ([kickoff-template.md](kickoff-template.md) §10). The UI and art managers run their own repos' workflows (P5 ports the
  levers there).
- **The rules every track's manager follows**, UI and art included, are in
  [docs/MANAGERS.md](../../../docs/MANAGERS.md) (#511): the mode and effort, the kickoff, the "For you:" block, the
  keep-alive, when to hand over (§5: the 500k, 12-hour and 250k thresholds, N6 (b) as changed on
  [#467](https://github.com/xperiaroco2/prime-game/issues/467#issuecomment-6014950287); the paste and the 500k:
  [#170](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6033930486)), the handover comment and the
  paste (§6), route C (§7); how game and meta carry it out: [handover.md](handover.md). While the engineer is away no
  successor starts, so a manager hands over only when a threshold forces it. A start-up costs about the successor's
  first 20 calls.
- **Long reading and drafting go to a subagent** (#467): planning reads, ADR and doc drafts and metrics tables; it
  returns a compact result, and the manager writes no large file itself.

## The rhythm (N8 (b))
- **By day**, while the engineer answers: UI, art and the game's tasks that need his answers or taste.
- **By night**, one long chain at a time: the game's stacked tasks or merge chain, or the meta track's tooling merges
  (`merge-train`), game or meta alternating by night (the track that did not run the last night's chain; the
  engineer's kickoff names it when that is unclear). Meta's changes to shared files land between the game's waves
  (AGENT_WORKFLOW §7.1, "Parallel tracks").
- The meta track's report and proposal come at the reset; the managers' kickoffs for the week follow the engineer's
  answer.
