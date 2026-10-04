# A weekly budget across four tracks

- **Status:** Proposed (#389). The engineer chooses from "Needs the engineer" (N1 to N8) before or at the weekly
  reset, 2026-10-06 10:00 UTC; the design proceeds with each recommendation where it can be reverted.
- **Date:** 2026-10-05
- **Deciders:** the engineer (N1 to N8). The measurement and the technical choices ("What this design settles") are
  the design task's, under the engineer's delegation of technical choices (#134) and the night plan he approved on
  #302 ([comment 5984093660](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-5984093660)).
- **Tracking:** #302 (Token efficiency), #170 (AI productivity)
- **Builds on:** the [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md) (15% of the week per stage
  or track without asking), the [baseline ADR](2026-10-02-ai-productivity-baseline-and-pipeline-v2.md)'s #304 and #307
  amendments (cache reads count at w = 0.75), the [effort ADR](2026-09-28-effort-and-workflow-bounds.md)'s 2026-10-04
  amendment, the [model-guard ADR](2026-09-28-model-guard-no-fable-in-shared-config.md)'s amendment A, the
  [lean ADR](2026-10-04-lean-workflow-agent-types.md) and the [instruction diet](2026-10-04-instruction-diet.md).

## Context
The engineer, 2026-10-04 about 20:20 UTC (translated, #389): after the reset, run all our workflows again for UX/UI,
art and the main game, at a good, balanced pace with balanced token spend. Four tracks share one Max 20x weekly
limit and one PC (8 cores, 16 threads, 32 GB):
- **game**: the main game's milestones (M5, then M6), manager sessions in `D:\prime-game`, PRs into `release/m<k>`;
- **UI**: UX/UI, its own repo and checkout `D:\prime-game-ui` (its first sessions ran in `D:\prime-game`);
- **art**: characters and assets, its own repo and checkout `D:\prime-game-art` (likewise);
- **meta**: AI productivity and token efficiency (#170, #302), PRs into `main` through the gate.

The weekly counter restarted at the plan change (2026-10-02 10:28 UTC) and read 80% at 2026-10-04 20:26 UTC: four
fifths of the week in 58 hours. On 2026-10-03, the one day all four tracks ran all day, they spent 40.7% of the
week; at that pace a week lasts 2.5 days. A week that keeps the engineer's 5% has 95% to spend, **13.6% a day: a
third of 2026-10-03's pace.** The managers' own sessions were 17.8% of the week in those 2.5 days.

### Measured inputs
% of the week = (list $ without cache reads + 0.75 x cache-read $) / $23.0, the `metrics` headline (#307, #333); the
bracket at w = 0.6 and 1 moves no track's figure by more than 0.2 points. "Since the restart" is 2026-10-02 10:28 to
2026-10-04 about 22:30 UTC. `metrics` reads only this checkout's transcript folders, so the UI and art sessions in their
own checkouts (`802a8cfc` in `D--prime-game-ui`, `77aa0a64` in `D--prime-game-art`) were summed by a read-only script
with `metrics`' rules (each `message.id` once, `metrics.PRICES`); it matches `metrics`' totals for the sessions in this
checkout to within $2. The scripts (`scan.py`, `tracks.py`, `verify.py`) and their output are in the scratchpad `a389/`
of manager session 657efbf1.

| # | input | value | source |
|---|---|---|---|
| 1 | Weekly counter | 0% at 10-02 10:53 (the restart), 66% at 10-03 20:54, 77% at 10-04 05:05, 79% at 12:40, 80% at 20:26; reset 10-06 10:00 UTC | `get_usage` readings: #302 comments 5973758335, 5981003461, 5984093660; the baseline ADR's #307 amendment |
| 2 | Spend per track since the restart | game **17.6%** ($454), UI **13.0%** ($328), art **15.8%** ($409), meta **37.0%** ($949); sum 83.4%, 2 to 3 points above the counter (row 1): the conversion reads high late in the week | `tools\run.cmd metrics --since 2026-10-02T10:28:00Z --session <ids> --no-gh --compact`: game `3e834e50 dd93bf79`, meta `40774c17 5ef6e325 657efbf1`, UI `ce8374ce`, art `a62dc194`; plus `scan.py` for `802a8cfc` (UI, 8.8%) and `77aa0a64` (art, 9.1%) |
| 3 | Per UTC day | 10-03: game 9.1, UI 10.0, art 12.0, meta 9.6 = **40.7%**; 10-04: meta 12.2, the others stopped | `tracks.py` (each API call's day) |
| 4 | The 5-hour limit | does not bind: a 5-hour point is about $6.5 at w = 0.75 against $23.0 a weekly point, so one 5-hour window holds roughly a quarter to a third of the week | #307's probe: 3 points on $3.43 non-read and $21.53 of cache reads |
| 5 | Managers' own lines since the restart | game 4.5%, UI 3.8%, art 3.9%, meta 5.6%: **17.8%** (22% of list $; 25 to 29% of each product track, 15% of meta); per task or run handled: game 0.19%, meta 0.09%, art 0.28%, UI 0.35% | `tracks.py`; the `metrics` runs of row 2 ("managers and their hand-run subagents") |
| 6 | A manager's context | 657efbf1 reached about 410k in 10 hours; M5 grew from 184k to 928k, round 1 from 147k to 933k | #386's body; orchestrate-stage §9 (2026-10-03) |
| 7 | Workflow cost per task, median | game **0.50%** ($13, 75 min, n = 24, M5); meta **0.37%** ($10, 59 min, n = 61); art 0.93% per implementing run (8 runs for 14 issues); UI 0.38% per run (n = 11: research, design and build runs; UI ran no `issue-task`) | `metrics` task medians (row 2's runs); `tracks.py` |
| 8 | All-in cost per task (the track's total of row 2 over its tasks: managers and other runs included) | game **0.73%**, meta **0.61%**, art **1.13%** per issue, UI **1.18%** per run | rows 2 and 7 |
| 9 | Where a run's $ goes (calendar week, 133 finished `issue-task` runs, median 59 min, $12) | implementer 49%, publisher 21%, other 11%, code-reviewer 7%, godot-api-checker 4%, netcode reviewer 3% | `tools\run.cmd metrics --since 2026-09-29T10:00:00Z --no-gh` |
| 10 | Sonnet publisher on clean runs (#308) | median **$0.42** against $1.99 on Opus (n = 6 against 20); 0 CI red rounds in all 26 runs | #302 [comment 5984180013](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-5984180013) |
| 11 | Lean agent types (#332 A/B, 4 runs) | first call 24.4k against 58.3k (implementers) and 31.1k against 64.6k (publishers); $ per call **-42%** and **-31%**; implementer plus publisher $5.64 to $8.70 a run against a general median of $8.59; no missing tool; the per-role effort applied | #302 [comment 5985172345](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-5985172345) |
| 12 | Levers at w = 0.75, points per 34.4 hours of 10-02/03's four-track load | bounded waits 7.9 (built, #303); effort high 3.4 (decided); keep-alive 3.4 (built, #305); lean types 2.8; manager rotation at 300k 2.7; Sonnet publisher 1.2; shorter tool outputs 1.1 | #302 [comment 5977019320](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-5977019320) |
| 13 | Compact workflow results (#386) | 88,969 to 10,772 characters over 8 runs: **88% smaller**, about 1,250 a run | PR #397 |
| 14 | CI's `test` step (#341) | 133.5 s against 199 to 212 s; CI `verify` 292 s against 332 to 366 s | PR #398 |
| 15 | `verify` by runs at once on this PC (k) | median 330 s at k = 1 (n = 24), 362 s at k = 2 (20), 456 s at k = 3 (17), 422 s at k of 4 or more (7); red 14 to 24% at every k (mostly the tasks' own failures); the 3 runs that timed out (a test shard at 600 s) came at k = 2 or 3; in 3 runs Godot or git failed to start (0xC0000142, a Windows DLL initialization failure), one of them at k = 1 | `verify.py` over every worktree's `tools/out/logs/verify-history.jsonl` (68 runs from 10-03 23:08); #185's k = 1 to 4 figures in `tools/runner/slots.py` agree |
| 16 | `verify` this week; time in it | 478 agent `verify` runs, median 359 s, max 1,805 s, 11 of them without a slot (over the limit); a task holds a slot 16 to 25 of its 48 to 82 minutes (per-session medians since 10-01) | `metrics` (row 9's run: "local verify", "min in verify", "wall") |
| 17 | 10-04 13:28 to 14:16 UTC | 5 red `verify` runs in 48 minutes: 3 timed out (1,332 to 1,805 s), and in 2 every Godot process failed to start; 2 or 3 `verify` runs at once, 3 workflows and the engineer's game on the PC; the engineer paused the track at 14:25 | `verify.py`; #302 comment 5981003461 |
| 18 | Workflow runs in flight, all tracks | 10-02: up to 7, 5 or more for 319 minutes; 10-03: up to 7, 163 minutes; 10-04: up to 4 | `verify.py` (sampled each minute) |
| 19 | Other load | a Godot window took up to 9.5 s to exit under all-core load, and `playcheck` failed 8 times for other load reasons; art's batches run headless Blender and off-screen Godot outside the slots; UI's checks are Node scripts | PR #394 (#354); `D:\prime-game-art\CLAUDE.md`, `D:\prime-game-ui\CLAUDE.md` |

## Decision (proposed)

### What this design settles (technical, the trust ADR's tier (a))
- **One unit for every budget:** % of the week at w = 0.75 and $23.0 (the conversion above), counted from the reset
  over all of a track's sessions, its rotations and its other checkout included (P1).
- **The budget line in every wave comment:** `<track>: <spent>% of <budget>% this week; plan to date <budget x days
  elapsed / 7>%; weekly counter <n>% (get_usage)`. The counter is the check: when it and the tracks' sum disagree by
  more than 3 points, the wave comment says so.
- **A global stop at 93% of the weekly counter** (the engineer's rule of 2026-10-04): no track launches a new
  workflow above it, whatever its own budget; runs in flight finish.
- **Planning figures:** what a budget buys is planned at row 8's all-in cost per task and re-measured at each reset.

### Q1. Budget per track (N1)
| option | game | UI | art | meta | the engineer | buffer | buys at row 8's costs: game tasks / UI runs / art issues / meta tasks |
|---|---|---|---|---|---|---|---|
| (a) equal | 22 | 22 | 22 | 22 | 5 | 7 | 30 / 19 / 19 / 36 |
| (b) product first | 26 | 20 | 20 | 12 | 5 | 17 | 36 / 17 / 18 / 20 |
| (c) game first | 40 | 15 | 15 | 10 | 5 | 15 | 55 / 13 / 13 / 16 |

- (a) prevents one track starving the others, but gives meta as much as the game; meta spent 37% this week, the
  opposite of "balanced".
- (b) keeps the three product tracks level, cuts meta to about a third of this week's spend, and keeps a buffer for
  the conversion's error (row 2: 2 to 3 points) and for the track with the best queue mid-week.
- (c) puts the milestone first; UI and art run at three quarters of (b).
- The levers of Q4 lower the game's and meta's cost per task by an estimated 15 to 20% all-in (lean: 23 to 30% of
  the implementer and the publisher, which are 70% of a run's $, rows 9 and 11; the Sonnet publisher: about $1.5 a
  clean run on a general publisher, row 10, less on a lean one; the two not measured together). UI and art run
  their own workflows, which get none of it until P5.

**Recommended (b).** A budget over 15% needs the engineer's yes under the trust ADR; choosing it here is that yes for
the week, and within it the track's manager does not ask (tier (a)). From the next reset on, the meta track posts
the past week's spend per track against its budget with the next week's proposal; the engineer's silence keeps the
last budgets.

### Q2. When a track's budget runs out (N2)
- (a) **At 80%** the manager plans no wave larger than what is left at row 8's cost per task; merges and handovers go
  on. **At 100%** it launches nothing, lets its runs finish (a killed run's spend is lost and it must run again), says
  so in the wave comment, and asks once in "For you:" for a share of the buffer, with the amount and what it buys.
  With no answer it stops without a keep-alive: a fresh session later costs less than a warm wait of days.
- (b) As (a), but the manager takes up to 5 points of the buffer without asking and reports it.
- In both, **the last 24 hours before the reset** (from Monday 10:00 UTC) open every track's unspent budget and the
  buffer to any track with work queued, up to the 93% stop: what is left at the reset is lost.

**Recommended (a), with the last-day rule.** (a) keeps the engineer's word on every point above a budget (tier (c):
"money and budget above the set budget"); the last-day rule prevents ending the week with unused budget while a
queue waits.

### Q3. The PC as a limit (N3)
Two `verify` runs at once are what this PC sustains with nothing else heavy on it: with three at once the median run
took 38% longer than a lone one (26% longer than with two), and the timeouts came at two or three (rows 15 and 17). A
task holds a slot about a third of its wall time (row 16), so six tasks in flight, the "about six" of AGENT_WORKFLOW
§7.1, fill both slots with nothing left for merges, load runs, art's renders or the engineer's own use. Q1's budgets
average about one task in flight across the tracks (13.6% a day at about 0.65% a task is about 21 tasks of about 65
minutes), so the cap matters in bursts, not on average.
- (a) **The slots only:** #388's longer slot wait and load runs in a slot; the "about six" stays.
- (b) **The slots plus a cap across sessions:** at most four task workflows of this repo at once (by day the game 3
  and meta 1; at night either track up to 3), one art batch at a time, UI uncapped (no Godot or Blender in its
  checks). A manager launches only when `slots --status` shows no run waiting for a slot (P2). The engineer runs
  `tools\run.cmd slots --quiet 3` before playing, which leaves one slot for 3 hours (P2), instead of pausing each
  manager by chat as on 10-04.
- (c) A machine-wide workflow lock in the runner: see Alternatives.

**Recommended (b).** The slots enforce `verify`; the managers enforce the cap with one status read; no new lock.
It prevents 10-04's over-limit runs, timeout reds and the lagging PC during the engineer's game.

### Q4. Which levers are on by default (N4, N5)
| lever | measured | proposal | decides |
|---|---|---|---|
| Bounded waits | 7.9 points (row 12), built | `bounded_waits: true` on every launch (the managers' practice); the default flips in P3 | manager |
| Keep-alive | 3.4, built | stays (orchestrate-stage §7) | done |
| Effort per role | 3.4, decided 2026-10-04 | no change: managers, the art and UI sessions and reviewers high; implementers high, xhigh for a design | done |
| Compact results | 88% smaller (row 13) | on once PR #397 merges, between waves | manager |
| Lean agent types | row 11 | N4 | engineer |
| Sonnet publisher on clean runs | row 10 | N5 | engineer |
| Manager rotation | 2.7 points | N6 (Q5) | engineer |

- **N4, lean:** (a) `lean: true` on every `issue-task` and `pr-rebase` launch from the reset, except a task whose
  agents need the Skill tool, and the default flips (P3) after a week with no missing tool; (b) flip the default now
  (P3 first); (c) keep it opt-in. **Recommended (a):** the A/B passed its three criteria, and the plan agent, the test
  reviewer and `pr-rebase`'s agents, which it did not cover, get a week of real runs before the default changes.
- **N5, Sonnet publisher:** (a) keep `models.publish_clean: "sonnet"` on every non-design `issue-task` launch,
  re-judged at the next reset with `metrics`' quality scorecard; (b) drop it. **Recommended (a):** 79% less publisher
  $ with no CI red round; six runs are a small sample, hence the re-check.
- **Together:** a lean publisher under `publish_clean` runs as `task-publisher` on Sonnet (the call's model wins,
  the lean ADR). The pair is untested: the first wave checks it with `tools\run.cmd agents-check` and `metrics`.

### Q5. The managers' own cost (N6, N7)
The managers were 17.8% of the week in 2.5 days (row 5): at that rate four managers would take about half of a paced
week. Their cost follows the work they handle (0.09 to 0.35% a task), so Q1's pace cuts it by itself; what remains is
the context every call reads again (row 6) and idle re-writes (the keep-alive covers those). Compact results (row 13)
keep about 9,800 characters (about 2.8k tokens) a completion out of the context.
- **N6, rotation:** (a) at a wave boundary over 500k tokens or 12 hours (#279, today); (b) **over 300k** or 12 hours,
  still only at a wave boundary (#329); (c) (b) on one track first. **Recommended (b):** 2.7 points per 34 hours at
  the four-track load (row 12). #307 proposed a one-stage trial after #332's A/B so the two effects stay apart; the
  A/B is done, and rotation acts on the managers while lean acts on workflow agents, so `metrics`' manager rows
  measure it alone. The risk is a handover that loses a detail; the wave comment's handover data carries the runs.
- **N7, how many managers:** (a) **four**, one per track; (b) three: the meta track's issues run as fillers in the
  game manager's waves (same repo, skill and gate), and a meta session runs only for the weekly report or a design.
  **Recommended (a)** with N6 (b): (b) saves meta's manager cost (5.6% in 2.5 days, less at Q1's pace) but grows the
  game manager's context and mixes two plan issues and two merge flows in one session.

### Q6. A weekly rhythm (N8)
Q1 (b) gives a guide of game 3.7%, UI 2.9%, art 2.9% and meta 1.7% a day: a quarter to two fifths of each product
track's 10-03 pace and a sixth of meta's (row 3). The 5-hour limit allows bursts (row 4); only the weekly total
binds.
- (a) **Steady:** every track runs all day at about a third of its pace, one or two workflows at a time.
- (b) **Day and night:** by day, while the engineer answers, UI, art and the game's tasks that need his answers or
  taste; by night one long chain at a time, the game's stacked tasks or merge chain or the meta track's tooling
  merges, alternating by night. Meta's changes to shared files then land between the game's waves (AGENT_WORKFLOW
  §7.1). The daily figure is a guide; the weekly budget is the limit.
- (c) **Track days:** one track at a time at full pace. Q1 (b) at 10-03's pace is about 8 track-days in a 7-day
  week, so not every track gets its days, and a track waits days for its turn.

**Recommended (b).** It puts the taste-heavy tracks where the engineer can answer, keeps one chain a night on the PC
(Q3), and gives meta's shared-file changes the gaps between waves. The reset is Tuesday 10:00 UTC: the meta track's
report and proposal (Q1) come then, and the managers' kickoffs for the week follow the engineer's answer.

### Needs the engineer
1. **N1, budget per track:** (a) equal, 22% each; (b) game 26, UI 20, art 20, meta 12, the engineer 5, buffer 17;
   (c) game 40, UI 15, art 15, meta 10, the engineer 5, buffer 15. **Recommended (b),** and from the next reset the
   meta track proposes the budgets with the past week's report, silence keeping the last ones.
2. **N2, at a track's budget:** (a) a soft line at 80%, no launch at 100%, more only on the engineer's word; (b) as
   (a), plus up to 5 points of the buffer without asking. In both, the last 24 hours open unspent budget to any track.
   **Recommended (a)** with the last-day rule.
3. **N3, the PC:** (a) the slots only (#388); (b) the slots plus a cap of four task workflows of this repo at once,
   one art batch, launches only with no slot waiter, and `slots --quiet <hours>` for the engineer's own use.
   **Recommended (b).**
4. **N4, lean agent types:** (a) on in every launch from the reset, the default flipped after a clean week; (b) the
   default flipped now; (c) opt-in. **Recommended (a).**
5. **N5, the Sonnet publisher on clean runs:** (a) keep, re-judged at the next reset; (b) drop. **Recommended (a).**
6. **N6, manager rotation:** (a) 500k or 12 hours; (b) 300k or 12 hours; (c) (b) on one track first; always at a wave
   boundary. **Recommended (b).**
7. **N7, managers:** (a) four, one per track; (b) three, meta's issues as fillers in the game manager's waves.
   **Recommended (a).**
8. **N8, the rhythm:** (a) steady; (b) day for UI, art and the game's answer-heavy tasks, one long chain a night
   (game or meta, alternating); (c) track days. **Recommended (b).**

### Proposed issues (not opened; the build waits for the answers)
| order | issue | size | decides | depends on | files |
|---|---|---|---|---|---|
| 1 | P1. `metrics`: a track's spend this week against its budget | M | manager | none | `tools/runner/metrics.py`, its tests, orchestrate-stage §6 and §10, AGENT_WORKFLOW §7.1 |
| 1 | P2. `slots --status` and `slots --quiet <hours>` | S | N3 (b) | #388 (both change `slots.py`) | `tools/runner/slots.py`, `verify.py`, `cli.py`, tests, AGENT_WORKFLOW §11, orchestrate-stage §3 |
| 2 | P3. `issue-task` and `pr-rebase` default to `lean` and `bounded_waits` | S | N4; manager for `bounded_waits` | a week of N4 (a), or none under (b); lands between waves | `.claude/workflows/issue-task.js`, `pr-rebase.js`, snapshots, `test_workflows.py`, the lean ADR, AGENT_WORKFLOW §7.1 |
| 2 | P4. The week's rules in the skill and the ADRs | S | N1, N2, N3, N5 to N8 | the answers | orchestrate-stage §1, §3, §6, §7, §10; AGENT_WORKFLOW §7.1; dated amendments of the trust, effort and model-guard ADRs |
| 3 | P5. The art and UI workflows get bounded waits, compact results and lean types (one issue in each repo) | M each | those repos' managers | P1 (to measure before and after) | `prime-game-art` and `prime-game-ui`: `.claude/workflows/`, `.claude/agents/` |

- **P1:** `metrics --since <reset> --track <name> [--budget <%>]` groups sessions by a `Track: <name>` line in the
  session's first user message (the kickoff; the §10 template gets the line), reads the transcript folders of the
  checkouts listed in one constant (`D:\prime-game`, `D:\prime-game-ui`, `D:\prime-game-art`, each with its
  worktrees), and prints each track's % (w = 0.75, the bracket), its budget and the plan to date; a session with no
  line counts as "untracked" (the engineer's reserve). Fixture transcripts in two folders; the wave comment's budget
  line comes from it. Acceptance: on this week's transcripts it reproduces row 2 within 0.1 points.
- **P2:** `slots --status` prints the holders, the waiters and the last hour's runs without a slot; `slots --quiet
  <hours>` writes a machine-wide limit of one slot with its end time into the slots folder, which `verify` reads
  (`--quiet off` ends it); a run that starts during a quiet window says so. Tests for both and for an expired file.
- **P3:** both defaults true, `lean: false` and `bounded_waits: false` still accepted; the snapshots change on
  purpose; the lean ADR's status amended to "on by default"; lands with no `issue-task` or `pr-rebase` run in flight.
- **P4:** the kickoff template's `Track:` and budget lines and the 80%/100% rules (N2); the launch cap and the slot
  read (N3); the 300k threshold (N6); `publish_clean` from a one-wave trial to a standing rule (N5: amendments of the
  effort and model-guard ADRs); the trust ADR's "15% per stage or track" read as "the track's weekly budget under
  this ADR, else 15%"; the skill within its 500-line budget.
- **P5:** each repo's manager measures its runs with P1 first and ports what applies; no change in this repo.

## Alternatives
- **No per-track budget, spend as each track needs:** 10-03's pattern. Four tracks at full pace end the week in 2.5
  days, and the largest spender was the track that exists to cut spend.
- **Hard daily caps** (a track stops at its daily share): stops long night chains halfway and leaves the share of a
  quiet day unspent; the weekly budget with a daily guide and Q2's lines does the same with fewer stops.
- **Stopping in-flight runs at 100%:** their spend is lost and each must run again from the start or a resume.
- **A machine-wide workflow lock in the runner:** workflows start through Claude Code's Workflow tool, not the runner,
  so a lock would be held for hours by a session that may crash; one status read by the manager does the job.
- **Three or one `verify` slots:** with three at once the median run took 38% longer than a lone one (row 15); one
  slot halves the throughput to save 10% a run. P2's quiet mode gives one slot only while the engineer needs the PC.
- **Two managers, one per repo group:** UI and art are separate repos with their own runners and skills, and a
  session runs in one checkout.
- **Sonnet managers:** model policy, not measured; cache reads cost the same on Sonnet 5.5 and Opus 5.5 ($0.20 per
  1M, `metrics.PRICES`) and are 34 to 44% of each track's list $ (`tracks.py`), and a manager's merges and decisions
  are where a mistake costs most.

## Consequences
- Once accepted, P4 changes AGENT_WORKFLOW §7.1 ("about six" task workflows becomes N3's cap), the orchestrate-stage
  skill and three ADRs by dated amendments; until then they stand as written.
- The art and UI tracks' costs stay outside the Q4 levers until P5.
- The figures come from the 2.5 days after the counter restarted, under the four-track load: P1 re-measures them at
  each reset, and the budgets move with them.
- The conversion read 2 to 3 points high against the counter late in the week (row 2): the buffer covers it, and the
  93% stop reads the counter itself.
