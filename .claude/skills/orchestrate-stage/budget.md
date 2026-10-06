# The week's budget (orchestrate-stage)

The rules of the [weekly budget ADR](../../../docs/decisions/2026-10-05-weekly-budget-across-four-tracks.md) as the
engineer chose them on 2026-10-05: every recommendation, N1 (b) to N8 (b)
([PR #403 comment 5992271562](https://github.com/xperiaroco2/prime-game/pull/403#issuecomment-5992271562)). They apply
from the weekly reset of 2026-10-06 10:00 UTC, N5 (the Sonnet publisher) already from the answer; the reset comes
every Tuesday at 10:00 UTC. Read this file at the kickoff, before you plan each wave and before each launch. "Row n"
is a row of the ADR's "Measured inputs"; "§n" is a section of `SKILL.md` beside this file.

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
  `main`). The engineer's 5% is his own sessions'. The buffer lies below the 93% stop (below).
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
- A session's track: its `--session <id>=<track>` label, else the `Track:` line of its kickoff (§10's template, and
  the handover kickoff of §7, so a successor keeps its track), else its checkout's (`-ui`: ui, `-art`: art), else
  untracked (the engineer's reserve). A session of your track listed as untracked (a kickoff without the line, or
  with a translated name): count it with `--session <id>=<track>`.
- **The budget line**, in every wave comment beside the wave's cost (§6): `<track>: <spent>% of <budget>% this week;
  plan to date <p>%; weekly counter <n>% (get_usage)`. When the counter and the line for every session differ by more
  than 3 points, the wave comment says so (the counter also counts the account's sessions outside the three
  checkouts).

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
  nothing. `lean: false` is the exception, for a task whose agents need a skill through the Skill tool (§3's row)
  ([lean ADR](../../../docs/decisions/2026-10-04-lean-workflow-agent-types.md)).
- **`models: {publish_clean: "sonnet"}`** on every non-design `issue-task` launch, from the answer on (never
  `pr-rebase`: it has no publisher and rejects the role). With `lean`, a clean run's publisher runs as
  `task-publisher` on Sonnet (the call's model wins); the pair is new, so check the first wave's runs with
  `tools\run.cmd agents-check` and `metrics`.
  It is judged again at the next reset with `metrics`' quality scorecard and stays until the engineer drops it
  ([effort ADR](../../../docs/decisions/2026-09-28-effort-and-workflow-bounds.md),
  [model-guard ADR](../../../docs/decisions/2026-09-28-model-guard-no-fable-in-shared-config.md)).
- `bounded_waits` is the default since #411: pass nothing. A resume takes the args of its launch (§7); for a run
  launched before #458 without `lean`, add `lean: false` (§3's row), or the lean agent types change its agents and the
  resume replays nothing past the reviews.

## Managers (N6 (b), N7 (a))
- **Four managers, one per track**, each in its track's checkout with the `Track:` line in its kickoff (§10). The UI
  and art managers run their own repos' workflows (P5 ports the levers there).
- **A handover** (§7) is due once the context is over 300k tokens or the session over 12 hours old, even mid-wave:
  N6 (b) as changed by the engineer on
  [#467](https://github.com/xperiaroco2/prime-game/issues/467#issuecomment-6014950287), replacing "still only at a wave
  boundary" (#329). Also due once the runs in flight end after a merge into `main` changed root `CLAUDE.md`,
  `.claude/rules/` or `.claude/agents/`, and at a stop for the human with the context over 150k and no run in flight
  (instead of a keep-alive). `wave`'s last line says which (§7's turn-end check). A manager may also hand over
  earlier, at a natural break, when its cost math says a fresh start is cheaper (#484).
- **The manager starts its successor itself** (#484, route C; approved by the engineer:
  [#170 comment 6025360550](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6025360550), with route
  C for its route B after [the probe](https://github.com/xperiaroco2/prime-game/issues/484#issuecomment-6025677487)),
  on every track: the track's standing kickoff is stored once per stage as the prompt of its ad-hoc Desktop scheduled
  task `<track>-manager` (handover.md §4), so no handover needs a prompt written by hand. At a handover the manager
  points that task's `fireAt` 3 minutes ahead, checks that the successor's run started and stops (handover.md §2); the
  human's paste is left only for a missing or refused tool. The successor starts in `acceptEdits` at medium effort, so
  while the human is away a manager hands over only when a threshold forces it. A start-up costs about the successor's
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
