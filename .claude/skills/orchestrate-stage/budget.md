# The week's budget (orchestrate-stage)

The rules of the [weekly budget ADR](../../../docs/decisions/2026-10-05-weekly-budget-across-four-tracks.md) as the
engineer chose them on 2026-10-05: every recommendation, N1 (b) to N8 (b)
([PR #403 comment 5992271562](https://github.com/xperiaroco2/prime-game/pull/403#issuecomment-5992271562)). They apply
from the weekly reset of 2026-10-06 10:00 UTC, N5 (the Sonnet publisher) already from the answer; the reset comes
every Tuesday at 10:00 UTC. Read this file at the kickoff, before you plan each wave and before each launch. "Row n"
is a row of the ADR's "Measured inputs"; "§n" is a section of the skill: `SKILL.md` beside this file, or the file
its index names for that §.

## The unit
Every budget is a % of the week: (list $ without cache reads + 0.75 x cache-read $) / $23.0, counted from the reset
over all of a track's sessions, its handovers and its other checkout included. `tools\run.cmd metrics` converts; the
weekly counter (the desktop app's `get_usage` tool) is the check.

## Budgets per track (N1 (b))
| track | game | UI | art | meta | the engineer | buffer |
|---|---|---|---|---|---|---|
| % of the week | 26 | 20 | 20 | 12 | 5 | 10 |

- The tracks: **game** (the milestones; `D:\prime-game`, PRs into `release/m<k>`), **UI** (`D:\prime-game-ui`), **art**
  (`D:\prime-game-art`), **meta** (AI productivity and token efficiency, #170 and #302; `D:\prime-game`, PRs into
  `main`). The engineer's 5% is his own sessions', the secretary's among them (AGENT_WORKFLOW §7.2, #485), until
  he says otherwise. The buffer lies below the 93% stop (below).
- A budget over the trust ADR's 15% is the engineer's yes for the week: within its track's budget a manager launches,
  restates the kickoff as a report and does not ask before each workflow (the trust ADR's amendment of 2026-10-05).
- What a budget buys is planned at row 8's all-in cost per task, re-measured at each reset: game 0.73% a task, meta
  0.61% a task, art 1.13% an issue, UI 1.18% a run. A day's share (game 3.7%, UI 2.9%, art 2.9%, meta 1.7%) is a
  guide; the weekly budget is the limit.
- From the next reset on, the meta track posts with its weekly report the past week's spend per track against its
  budget and a proposal for the next week's budgets; the engineer's silence keeps the last ones. A workflow that
  gathers it passes the lean types (AGENT_WORKFLOW §5, #466): its gatherers `{agentType: 'lean-reader'}` on Sonnet,
  its verifier (a skeptic) `{agentType: 'lean-reader', model: 'opus'}`, the agent that writes the report or comment
  `{agentType: 'lean-writer'}`.

## Reading the spend
- `tools\run.cmd metrics --since <the reset, 2026-10-06T10:00:00Z> --track <track> --budget <its %> --compact` (#409)
  prints the window, one line per track named (`<track>: <%> (<bracket>) of <budget>% this week; plan to date <%>;
  list $<n> in <k> sessions`; the plan to date is the budget x the days since the reset / 7), and the total of every
  session of the three checkouts with its untracked share and that share's largest sessions. Several tracks take one
  budget each, in their order (`--track game meta --budget 26 12`); `--track all` lists every track found and takes no
  `--budget`. Without `--compact` it adds a table of every session with its track and where the track came from.
- A session's track: its `--session <id>=<track>` label, else the `Track:` line of its kickoff (§10's template in
  [kickoff-template.md](kickoff-template.md), and the handover kickoff of §7, so a successor keeps its track), else its
  checkout's (`-ui`: ui, `-art`: art), else untracked (the engineer's reserve). A session of your track listed as
  untracked (a kickoff without the line, or with a translated name): count it with `--session <id>=<track>`.
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
  `tools\run.cmd slots --quiet <hours>` (one slot for that time). If `tools\run.cmd slots --help` lists no `--quiet`
  (`slots --status` and `--quiet` are #416, P2), the cap above is the rule and the engineer's word in the chat pauses
  launches.

## Launch args (N4 (b), N5 (a))
- **`lean`** is the default of `issue-task` and `pr-rebase` since #458 (the engineer's N4 (b), 2026-10-06): pass
  nothing, also for a task that edits `.claude/workflows/` (#557: its agents read `docs/workflow-scripts.md`).
  `lean: false` needs `lean_reason` ([launch-args.md](launch-args.md) §3's row;
  [lean ADR](../../../docs/decisions/2026-10-04-lean-workflow-agent-types.md)).
- **The launch check** (#557): before each `issue-task` or `pr-rebase` launch or resume, `tools\run.cmd agents-check
  --launch` in the checkout you launch from. Exit 1 names a missing or invalid lean agent file, or scripts and agent
  files that differ from origin/main: pull `main` (or have it pulled) and run it again. Never pass `lean: false` to
  get around it.
- **`models: {publish_clean: "sonnet"}`** on every non-design `issue-task` launch, from the answer on (never
  `pr-rebase`: it has no publisher and rejects the role). With `lean`, a clean run's publisher runs as
  `task-publisher` on Sonnet (the call's model wins); the pair is new, so check the first wave's runs with
  `tools\run.cmd agents-check` and `metrics`.
  It is judged again at the next reset with `metrics`' quality scorecard and stays until the engineer drops it
  ([effort ADR](../../../docs/decisions/2026-09-28-effort-and-workflow-bounds.md),
  [model-guard ADR](../../../docs/decisions/2026-09-28-model-guard-no-fable-in-shared-config.md)).
- **`models: {plan: "sonnet"}`** on every `issue-task` launch with `plan_review` (#469, the engineer's yes on the
  issue): the planner on Sonnet, the critique on the review model (Opus), with `publish_clean` beside it on a
  non-design task. The result's `plan.model` shows it; `metrics`' plan phase table compares the plan and critique $,
  the planner files the implementer read again and the critique's findings with the runs before (they must not rise).
- **`models: {implement: "sonnet"}`** beside `publish_clean` on every qualifying `issue-task` launch during #560's
  trial ([trial ADR](../../../docs/decisions/2026-10-08-sonnet-implementer-trial.md); the engineer's yes on #302):
  Size S or XS by its `Size:` line, `area:tooling` or docs-only, nothing under `core/ server/ net/ client/ voice/`, not a
  design task, no `.claude/workflows/` edit. Red once: the fresh relaunch stays on Sonnet; red twice: relaunch once
  more without `models.implement` (Opus). Check the first trial run with `tools\run.cmd agents-check`; read `tools\run.cmd metrics
  --since 2026-09-30T00:00:00Z`'s "Sonnet implementer trial" table before each wave, and once its advice is other
  than "continue", post it on #302 with the table and stop passing `implement` (a keep needs the engineer's yes and
  an amendment of the model-guard ADR).
- `bounded_waits` is the default since #411: pass nothing. A resume takes the args of its launch
  ([resume.md](resume.md) §7); for a run launched before #458 without `lean`, add `lean: false` and `lean_reason: "a
  resume of <run id>, launched before #458"` (launch-args.md §3's row), or the lean agent types change its agents and
  the resume replays nothing past the reviews.

## Managers (N6 (b), N7 (a))
- **Four managers, one per track**, each in its track's checkout with the `Track:` line in its kickoff
  ([kickoff-template.md](kickoff-template.md) §10). The UI and art managers run their own repos' workflows (P5 ports the
  levers there).
- **The rules every track's manager follows**, UI and art included, are
  [docs/MANAGERS.md](../../../docs/MANAGERS.md) (#511): the mode and effort, the kickoff, the "For you:" block, the
  keep-alive and the handover; the UI and art repos' `CLAUDE.md` files point there.
- **A handover** (§7) is due once the context is over 500k tokens or the session over 12 hours old, even mid-wave:
  N6 (b) as changed by the engineer on
  [#467](https://github.com/xperiaroco2/prime-game/issues/467#issuecomment-6014950287), replacing "still only at a wave
  boundary" (#329), with 500k for 300k on
  [#170 comment 6033930486](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6033930486) (#511; to be
  checked with `metrics` after a week). Also due once the runs in flight end after a merge into `main` changed root
  `CLAUDE.md`, `docs/MANAGERS.md`, `.claude/rules/` or `.claude/agents/`, and at a stop for the human with the context
  over 250k (half the threshold, as 150k was of 300k) and no run in flight (instead of a keep-alive). `wave`'s last
  line says which (§7's turn-end check). A manager may also hand over earlier, at a natural break, when its cost math
  says a fresh start is cheaper (#484).
- **The engineer pastes the successor's kickoff** (#511; approved by the engineer:
  [#170 comment 6033930486](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6033930486)), on every
  track: the handover comment's notes end with the ready kickoff (handover.md §4), the last For-you carries it, so no
  handover needs a prompt written by hand, and he pastes it into a new session in the track's checkout with bypass and
  effort high. While he is away no successor starts, so a manager hands over only when a threshold forces it, and lets
  its runs end first. Route C (#484, a one-time `fireAt` scheduled task, handover.md §3) is a fallback he asks for: its
  successor always starts in `acceptEdits` at medium effort. A start-up costs about the successor's first 20 calls.
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
