# AI productivity: the measured baseline and pipeline v2

- **Status:** Proposed: the engineer reviews it in #171's PR. The technical choices below are the manager's under the
  engineer's delegation (#134, 2026-10-01 14:02 UTC); the items marked **Needs the engineer** and the two amendment
  drafts at the end (A: the model guard, B: the release branch) are accepted or rejected one by one.
- **Date:** 2026-10-02
- **Deciders:** the engineer (the AI productivity track, #170; design task #171)

## Context
The engineer moved to Max 20x on 2026-10-02 and gave the AI productivity track (#170) about 20 to 25% of the weekly
limit: spend the extra capacity where it multiplies the speed and quality of every later task, never on tokens for
their own sake. #171 asks to measure first. Everything below is dated evidence from the transcripts of M2 to M4.

### How the baseline was computed
A read-only Python script (`measure.py`; kept in the design task's scratchpad and posted in full in the handoff on
#171; proposed issue P1 turns it into `tools\run.cmd metrics`) reads, for the manager sessions of M2 (`17021f90`,
`17094ef1`), M3 (`f4731b0a`), M4 (`dd93bf79`) and Phase A (`40c5c58a`), under
`C:/Users/xperi/.claude/projects/D--prime-game/`:
- each workflow run's `journal.jsonl` (each agent's label, phase and structured result, the reviewers' findings with
  their severity, the publishers' `fixed` and `not_fixed`) and each `agent-<id>.jsonl` (timestamps, the model, the
  effort, every tool call and its result, and the API `usage` of each message);
- the manager's own `<session>.jsonl` and the subagents it ran by hand;
- CI through `gh run list` and `gh run view --json jobs` / `--log` (`--ci 12`: the last 12 green runs).

Rules: only runs whose last transcript line is before **2026-10-02 11:00 UTC** count (the cutoff makes a rerun give
the same tables while the M4 session keeps working; its two live runs, #168 and #169, are excluded); usage is
deduplicated by message id (a message's content blocks repeat its usage); a tool call's time runs from the assistant
line that made it to the user line that carries its result; a `verify` run is counted from the "verify summary" block
printed in a tool result (deduplicated per agent), with its per-step seconds. Units:
- **final context**: the tokens of an agent's last API call, summed over agents. It is what the managers reported as
  "subagent tokens" (M4 measured 12.25M; the wave comment on #134 said about 12M).
- **fresh tokens**: input, cache writes and output, without cache reads.
- **API list $**: each agent's tokens at its model's API list price (Opus 5.5: input $4, 5-minute cache write $5,
  cache read $0.20, output $20 per million; Sonnet 5.5: $2, $2.50, $0.20, $10; Haiku 4.5: $1, $1.25, $0.10, $5;
  platform.claude.com pricing, read 2026-10-02). A weight that adds the four kinds of tokens and the models in one
  number, not money spent: the plan's own weights are not published.

**Calibration to the weekly limit.** On Max 5x about 0.44M final context took 1% of the weekly limit (#134,
2026-10-02); M4's subagents cost $25 list per 1M final context, so 1% of a **Max 20x** week is about **$44 list**.
M4 (subagents $307 plus its manager $59) is then about 8.3%, as the engineer estimated (8 to 9%); a median M4 task
($24) is about 0.55% and a median M3 task ($14) about 0.3%.

### The baseline (66 runs: 48 finished `issue-task` runs, 6 resumed ones, 1 unfinished, 4 `pr-rebase`, 7 others)

**Per finished `issue-task` run, by stage (medians; minutes)**

| stage | runs | wall | implement | review | publish | final context | fresh tokens | API list $ | tool calls | verify runs | min in verify | min on CI | majors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M2 (first session) | 3 | 53 | 29 | 6 | 18 | 0.62M | 0.81M | $12 | 188 | 3 | 10 | 2 | 2 |
| M2 (stage 2 session) | 14 | 48 | 22 | 6 | 22 | 0.74M | 0.88M | $11 | 234 | 3 | 14 | 2 | 11 |
| M3 | 17 | 53 | 25 | 6 | 22 | 0.65M | 1.23M | $14 | 236 | 3 | 17 | 4 | 18 |
| M4 | 14 | 82 | 45 | 7 | 28 | 0.94M | 1.98M | $24 | 340 | 3 | 25 | 5 | 14 |

"Verify runs" counts the summaries an implementer or publisher printed (`publish` included); "majors" is the stage's
total. M4's longest run took 99 minutes and its costliest $33. The table per run is in the handoff on #171.

**Per agent role (all 66 runs)**

| role | agents | wall min (median / max) | time in tools | tool calls (median / max) | fresh tokens (median) | API list $ | model, effort |
|---|---|---|---|---|---|---|---|
| implementer | 51 | 27 / 57 | 43% | 101 / 246 | 0.48M | $415 (44%) | Opus, high or xhigh |
| publisher | 56 | 22 / 59 | 77% | 62 / 104 | 0.27M | $189 (20%) | Opus, high |
| code-reviewer | 57 | 4 / 13 | 7% | 27 / 50 | 0.12M | $69 | Opus, high |
| godot-api-checker | 39 | 7 / 57 | 13% | 44 / 66 | 0.19M | $54 | Sonnet, xhigh (inherited) |
| netcode-security-reviewer | 37 | 3 / 8 | 6% | 22 / 39 | 0.11M | $38 | Opus, high |
| `pr-rebase` (rebase and fix) | 10 | 21 to 25 / 44 | 71 to 77% | 54 to 84 / 112 | 0.24M to 0.42M | $37 | Opus, high |
| others (Phase A research, M2 one-offs) | 45 | 10 / 61 | 17% | 47 / 144 | 0.21M | $142 | Opus, Haiku |

All subagents: 1,993M tokens, of them 95.9% cache reads; $945 list, of it cache writes 34%, cache reads 40%,
output 25%. The manager sessions added $191 list (M4: $59, 19% on top of its subagents) and 14 hand-run subagents.
Three of the 66 runs never finished, all three in M2.

**Local `verify` by step (seconds, medians of the printed summaries)**

| | runs | red | doctor | lint | check | test | enet | freeze | stall | bots | bots-enet | game | selftest | total (median / max) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M3 | 49 | 4 | 1 | 19 | 14 | 122 | 1 | 15 | 22 | 8 | 19 | | 164 | 355 / 464 |
| M4 | 48 | 10 | 1 | 23 | 17 | 144 | 1 | 15 | 22 | 10 | 47 | 4 | 199 | 489 / 632 |
| CI, last 12 green (Linux) | 12 | | 0 | 25 | 12 | 190 | 1 | 15 | 13 | 10 | 47 | 3 | 57 | 382 / 440 |

Red local summaries: 23 of 193 (12%; M4 10 of 48): lint 8, selftest 7, test 4, check 4, a dirty tree 3, bots 1. The
M4 manager's verify on each merged tree: 11 runs, 414 s median. CI: 149 runs before the cutoff, 5 reruns, no
queueing (0 s median), the job 6.6 minutes median (5.2 to 7.6). `selftest` takes 199 s on the engineer's Windows PC
and 57 s on CI's Linux runner, likely because the runner tests start many processes (git, bash), which Windows
starts slowly (P2 profiles it).

**The prompt cache after a wait.** API calls by the time since the same agent's previous call:

| gap | calls | median cache write | median cache read | calls that re-wrote most of the context |
|---|---|---|---|---|
| under 1 min | 12,506 | 2k | 0.12M | 0% |
| 1 to 5 min | 424 | 1k | 0.15M | 0% |
| 5 to 10 min | 136 | 0.13M | 18k | 91% |
| over 10 min | 16 | 0.16M | 0 | 94% |

Workflow subagents get the 5-minute cache lifetime even on a subscription (code.claude.com/docs/en/prompt-caching,
"Which TTL each request gets"). A verify run (8 minutes in M4) or a CI watch (5 to 7 minutes) is longer, so the next
call writes the whole context again: 24.0M of the 59.7M tokens written after the agents' first calls (40%), about
$115 list more than reading them, or 12% of all subagent cost.

**Reviews and rework.** Findings by reviewer in `issue-task` runs (no blocker in any run):

| reviewer | reviews | major | minor | nit | reviews with none |
|---|---|---|---|---|---|
| code-reviewer | 50 | 23 | 112 | 101 | 0 |
| godot-api-checker | 37 | 12 | 77 | 95 | 1 |
| netcode-security-reviewer | 35 | 13 | 38 | 31 | 9 |

The `pr-rebase` reviews found 5 more majors in 3 reviews. Publishers (M2 stage 2 to M4) fixed 360 findings and left
81, of which only 8 they judged wrong or already handled: false findings are rare. Rework: 4 `pr-rebase` runs (24 to
81 minutes; M4's #154 after #153, 81 minutes, and #154 merged about three hours after the conflict was found), 2 red
merges in M4 from semantic conflicts between PRs that were each green (#153 renamed a field #154 read; #156 added a
snapshot flag a #154 test lacked; #170), 6 resumed and 3 unfinished runs, second runs of #58 and #102, and the two
bugs only the engineer's playtest found (#168: spectating through the target's eyes and its HUD; #169: one Esc menu
and a Ready key). The `pr-rebase`, resumed and unfinished runs took about 11% of all subagent tokens. Fix rounds:
25 of 56 publishers ran `publish` two to four times (after a rebase conflict, a runner change, a network error or a
red CI), 12 watched CI more than once, and 2 ended with CI red.

### The five largest time sinks (M4 medians per task: 82 minutes)
1. **Implementation, 45 minutes (55%).** Implementers spend 43% of their time in tools; their 76 `verify` calls took
   5.0 hours of the 24.3 implementer hours.
2. **`verify`, about 25 minutes per task.** 489 s per local run in M4 (632 s at most), three runs per task plus the
   manager's run on the merged tree (414 s); `selftest` (199 s) and `test` (144 s) are 70% of a run. Three parallel
   runs already compete for the 8 cores (#170).
3. **Publishing, 28 minutes.** Publishers spend 77% of their time in tools: `publish` (rebase, verify, push) 5.5
   hours over 91 calls, CI watches 3.0 hours over 73 calls (about 5 minutes per task; the CI job takes 6.6).
4. **Rework.** `pr-rebase` runs of 24 to 81 minutes, relaunches after a red run, 12% red local verify runs to
   diagnose, an unfinished M2 run of 97 minutes.
5. **Serial merges and the waits behind them.** The manager merges one PR at a time with a 7-minute verify on each
   merged tree, and a task that needs a merged parent waits for it (M4: about three hours from the #153/#154 conflict
   to the merge of #154).

### The five largest token sinks (API list $, all 66 runs)
1. **Implementers' long contexts: $415 (44%).** A median of 101 tool calls, each re-reading a context that grows to
   about 0.27M tokens (the median final context); 980M cache-read tokens.
2. **Publishers: $189 (20%).** A second long context that takes in the implementer's report, every review, the
   verify output and the CI output.
3. **Cache re-writes after waits of 5 minutes or more: about $115 more than reads (12%).** 152 calls, caused by the
   8-minute verify and the CI watches.
4. **Manager sessions: $191** over the five sessions (M4: 19% on top of its subagents), plus 14 hand-run subagents.
5. **Rework: about 11% of subagent tokens** in `pr-rebase`, resumed and unfinished runs, plus second runs of #58
   and #102.

What the list in #170 misses, from this data: the cache re-writes (sink 3), which a faster `verify` removes as a side
effect; the playtest-only bugs, which no reviewer can see because none of them runs the game; and the unit the
managers budget in (final context), which understates the cost of long agents.

## Decision (proposed)
Principles for every item: each change is measured against this baseline with P1's `metrics`; no check is weakened,
skipped or removed (root `CLAUDE.md`); every new workflow argument is optional and today's behaviour is its default,
so other managers' launches and resumes stay the same; a change to a shared file lands between the other tracks'
waves. Costs are API list $ per task unless said otherwise (1% of a Max 20x week is about $44). Items 1 to 4 ask
nothing of the humans beyond reviewing and merging their PRs; items 5 to 7 change how the humans work and are
marked for the engineer.

### 1. Measurement
| option | the failure it prevents | cost | |
|---|---|---|---|
| (a) `tools\run.cmd metrics`: the script above as a runner command with selftest fixtures; `verify` appends a history record per run (`tools/out/logs/verify-history.jsonl`: worktree, branch, tree hash, each step's status and seconds) | budgets and claims of "faster" from memory or from a unit (final context) that understates long agents; numbers no one can reproduce | one task (M); seconds per report | **recommended** |
| (b) keep the scratch script and run it by hand | | none now; drifts unreviewed, lives in one scratchpad | rejected |
| (c) Claude Code's OpenTelemetry export to a collector | | a new service and dependency to run | rejected |
| (d) hooks that log every tool call | | more `.claude/` hooks on every call; the transcripts already hold the data | rejected |

The per-wave report: the manager pastes `metrics --since <wave start>` (time and API list $ per task, % of the weekly
limit) into each wave comment. It is the second thing to drop if the budget runs out (the engineer's kickoff); the
command itself stays, because every later item is judged by it.

### 2. A faster `verify`
Target: half of today's local run (489 s in M4) and under the 5-minute cache lifetime, with every step still run.

| option | the failure it prevents | cost | |
|---|---|---|---|
| (a) **two lanes**: lint then selftest (pure Python) beside check, test and the Godot runs; the steps inside the Godot lane stay serial | the 8-minute wall of every run (three per task) and the cache re-writes | one task (M); about max(23 + 199, 17 + 144 + ~100) = 261 s instead of 489 s | **recommended** (P2) |
| (b) selftest in parallel worker processes | selftest (199 s on Windows) becoming the critical path once (a) lands | in P2; about 60 s expected | **recommended** (P2) |
| (c) **an own `user://` per worktree and process**, then `test` in 2 to 3 shards | GdUnit4's `user://tmp` is one folder for every checkout of the project (`config/name="PrimeGame"`, no custom user dir), a cause of the "two verify runs collide, rerun once" gotcha; `test` is 144 s locally and 190 s on CI | one task (M to L); how Godot 4.7.2 takes a per-process user dir is verified first (environment, or a gitignored `override.cfg` with `application/config/use_custom_user_dir`); without one, no sharding | **recommended** (P5) |
| (d) a machine-wide limit of N verify runs at once | four tracks starving each other's verify runs, and timing-sensitive steps (freeze, stall) failing under load | one task (S) | **recommended** (P8) |
| (e) the ENet runs in parallel | | they measure timeouts and freezes in real time; overlap on a loaded CPU makes them flaky | rejected |
| (f) selftest locally only when `tools/` (or `.claude/`) changed; CI still runs it | 199 s of CPU per run | changes the definition of done (`verify` = what CI runs) | **Needs the engineer** (N4); recommended **no**: after (a) and (b) selftest is off the critical path |
| (g) `publish` skips its verify when the tree equals one already verified green | one run per task | publishers change the tree in nearly every task (360 fixes in 52 publishes), so it rarely applies; changes the definition of done | rejected |
| (h) cache Godot's import on CI | | `check` is 12 s on CI | rejected |
| (i) split CI into parallel jobs with a final `verify` job | the 5-minute CI watch per task | `.github/` edit; whether the runner's cores make (a) enough is measured in P2 first | later, if P2's CI timing says so |

Expected after P2, P5 and P8: local verify about 3 to 4.5 minutes (the Godot lane: check 17 s, test about 75 s, the
ENet and bot runs about 100 s), every step kept, the verify-runs share of a task from about 25 to about 12 minutes,
and most of the $115 of cache re-writes gone.

### 3. Merge safety
| option | the failure it prevents | cost | |
|---|---|---|---|
| (a) `tools\run.cmd merge-check`: every pair of open PRs into the same base, textually (`git merge-tree --write-tree`) and semantically (the symbols a PR removes or renames: `class_name`, functions, constants, fields, signals, enum values, wire rows, test fixtures, matched against identifiers the other PR's added lines use) | the M4 red merges (#153 against #154, #156 against #154) found only after a merge, and the hours of `pr-rebase` after them | one task (L, with (b)); seconds per check, no Godot | **recommended** (P4) |
| (b) `tools\run.cmd merge <pr> --base release/<x>`: the manager's merge as one command (fetch, detached checkout, `merge --no-ff`, the tree-equality shortcut against a green verify record, else `verify`, push by hash, confirm the PR shows merged); refuses `main` and task worktrees | a hand-typed recipe of six steps per merge, run up to 15 times a stage | in P4 | **recommended** (P4) |
| (c) `merge-check --trial`: base plus the named PRs merged in order in a scratch worktree, then `verify` | semantic conflicts that no symbol match sees (behaviour, test expectations) | one verify per trial; the manager runs it when (a) flags an overlap or before merging a chain | **recommended** (P4) |
| (d) only notes: the manager names shared classes and fields in both tasks' notes (the M4 lesson) | | relies on the manager seeing the overlap in advance | kept, not enough alone |
| (e) GitHub's merge queue | | merges through GitHub, which agents may not do; its availability for this repository's plan is unverified; the local merge already is a queue of one | rejected |

For tracks whose PRs go straight into `main` (this one), the engineer merges: the manager runs `merge-check` before
it asks him and names the safe order.

### 4. `issue-task` v2
Every option below is an optional argument, off by default (other managers launch the script from their own copies;
a resume replays agents only while their prompts and options are unchanged).

| option | the failure it prevents | cost per task | |
|---|---|---|---|
| (a) `plan_review`: the implementer first writes a plan (files, interfaces, tests, risks), a fresh reviewer critiques it, then the implementer builds | majors found only after 45 minutes of building (48 in 122 reviews; the M4 leak through rendering, a camera one step behind) | +2 agents, about +10 minutes, about +$5 (estimate) | **recommended** for core/, server/, net/, tests/harness/ and tasks of size M or more; the manager decides per launch |
| (b) `test_review`: after the reviews, one agent picks 3 to 5 mutants in the diff's code and runs `tools\run.cmd mutants` (P7), which plants each fault, runs the named tests and restores the file; a surviving mutant is a finding | tests that pass whatever the code does (the reviewers' "tests that actually test the change" is checked by reading only) | +1 agent, +10 to 20 minutes, about +$4 (estimate) | **recommended** for core/, server/, net/, tests/harness/; usable once P7 merges |
| (c) `skeptic`: one refuting agent per blocker or major before the publisher | wasted fixes on wrong findings | +1 agent per major | only for design tasks and audits: publishers judged just 8 of 441 findings wrong |
| (d) `second_review`: a second netcode review of a diff routed to the netcode reviewer, with another lens or model | leaks a single review misses (M3: a major found by a review run by hand, #115) | +1 agent, about +$1 on Opus (a netcode review's median) | **recommended** with item 5 |
| (e) `efforts`: per role (implement, review, godot, publish) | the godot-api-checker inheriting the session's xhigh for API look-ups (7 minutes median, 57 at most) | none | **recommended**; the manager tries `medium` for that checker and compares its majors with `metrics` |
| (f) `models`: per role, passed to `agent({model})` only when set; no default names a model | one model for every role regardless of where strength pays | none by itself | **recommended**; what a manager may pass is amendment A |
| (g) `visual`: the publisher's reviewer gets PNGs from `tools\run.cmd playcheck <scenarios>` (P9) | UI and camera bugs only a playtest found (#168, #169) | +5 to 10 minutes | **recommended** for client/ UI and camera tasks once P9 merges |

P3 builds (a) to (g) in `.claude/workflows/issue-task.js` (and the review options in `pr-rebase.js`), with
`tools/runner/tests/test_workflows.py` asserting that today's arguments produce today's prompts and options.

### 5. The model policy (**Needs the engineer**, N1; draft: amendment A)
The baseline shows where a stronger model could pay: no review found a blocker in 122 reviews, majors were found in
20 of 48 PRs (42%), some only by a review the manager ran by hand, and the costliest failures (the red merges, the
leak-test blind spot of M3, the playtest bugs) are cross-cutting judgements rather than volume. The plan reports a
separate weekly Fable window beside the all-models one (get_usage, 2026-10-02). Fable 5.1's list price is 2.5 times
Opus 5.5's (input $10, output $50 per million).

| option | where Fable runs | cost | |
|---|---|---|---|
| (a) none (today) | | | |
| (b) **per launch, for judgement**: stage designs, a second review (item 4 (d)) of PRs that touch core/, server/, net/ or tests/harness/, audits, and a task that went red twice | about 2 to 4 agents a stage; at 2.5 times the Opus price a second review is about $2.50 list and a stage design about $20 to $40 (M4's design implementer: $16 on Opus) | **recommended**; budget: at most half of the weekly Fable window across all tracks, reported per wave |
| (c) (b) plus every manager session | managers are 19% of a stage's cost and make the merge and order calls | a manager's context is long: a large share of the Fable window | not now |
| (d) everywhere | | the Fable window would last a few tasks | rejected |

How it is chosen without naming it in a shared file: the engineer adds it to `availableModels` in his own
`~/.claude/settings.json` (user scope; the lists merge across non-managed scopes, code.claude.com/docs/en/settings);
the kickoff names where it is used; the manager passes it per launch through `models` (item 4 (f)). The shared
settings, agents, workflows, skills, rules, runner, CI and CLAUDE.md files never name it; `agents-check` keeps
proving which model served each agent.

### 6. Night jobs (**Needs the engineer**, N3)
| option | the failure it prevents | cost | |
|---|---|---|---|
| (a) GitHub Actions on a schedule (`schedule:` cron on `main`, plus `workflow_dispatch`): a long chaos run with a random seed, `perf` with 10 bots, the GdUnit4 suite three times for flaky tests; artifacts and a comment on a standing "Night jobs" issue when something fails | regressions in robustness, cost per tick and flakiness found by humans or never | no tokens, no PC (a public repository on GitHub Free); scheduled runs use the latest `main` commit, may be delayed at busy hours and are disabled after 60 days without activity (docs.github.com, events that trigger workflows) | **recommended** (P12) |
| (b) one Claude audit lens per night (docs drift first; then coverage, flaky tests, dead code) as a Desktop local scheduled task with its own worktree; a skeptic re-checks each finding; confirmed ones become issues, a summary goes on the "Night jobs" issue | docs and code drifting apart; untested code; dead code | about $10 list a night (0.25% of the week); the PC on, the Desktop app open, "Keep computer awake" on (a sleeping PC skips the run; code.claude.com/docs/en/desktop-scheduled-tasks) | **recommended**, one lens; lenses beyond one are the third thing to drop |
| (c) cloud routines | runs with the PC off | `verify` runs in a cloud container after the setup script of #161 (335 s), `shot` cannot (no GPU); the cloud trial (#159) cost about $5 of cloud credits for about 140k tokens (#134) | not now (money) |
| (d) `/loop` in a manager session | | needs an open session | rejected |

**Chaos bots** (P11) test an existing invariant (ARCHITECTURE invariant 1: the host validates every intent) with
what a modified client can send: malformed frames, out-of-range values, intents in the wrong phase or for what the
peer does not own, replays, floods past the wire and peer budgets. A short seeded run joins `verify` (a new check,
nothing weakened); the long run is a night job. A bug they find becomes an issue, never part of the bot task. They
are the first thing to drop. **Performance runs** (P10): host tick time (`Time.get_ticks_usec`,
`Performance.get_monitor` with `TIME_PHYSICS_PROCESS`), snapshot bytes per peer per tick and memory
(`MEMORY_STATIC`) with 10 bots; reported against the previous night, never failing the build (a threshold is a
placeholder, not a decision).

### 7. Parallel tracks at scale (**Needs the engineer**, N2 and N5; draft: amendment B)
M5 (a local session after #167 merges), the UI track (#150), the 3D track (#165) and this track share one PC (8
cores, 16 threads, 32 GB), one weekly limit and one engineer who merges.

| option (git flow) | the failure it prevents | the humans' time | |
|---|---|---|---|
| (a) one release branch per milestone, one milestone at a time (the ADR today) | | | blocks parallel tracks |
| (b) a release branch per track; each manager merges its tasks; the engineer merges each track's closing PR | stalls at night where a task needs a merged parent | a few large PRs; cross-track conflicts appear late, in the closing PRs | possible |
| (c) every PR straight into `main`; the engineer merges each (this track's choice, 2026-10-02) | late integration | a click and a look per PR (four tracks: tens a day); a night stalls at the first merge it needs | right for day tracks |
| (d) **(b) for a track that runs unattended at night, (c) for a track the engineer follows during the day**; every release branch takes `main` in at the start of each wave (merged by its manager, `verify` on the merged tree) and closes into `main` at least every three days and at its milestone's end; `merge-check` across all open PRs before each merge | the stalls of (c) and the late surprises of (b) | (b)'s few PRs for night tracks, (c)'s clicks for day tracks | **recommended** |

Shared resources (N5): the CPU (P8's machine-wide verify slots, and at most about six task workflows across all
tracks at once); the weekly limit (each kickoff states its share as a percentage, each manager reports its own spend
from `metrics` per wave); the shared files (`tools/runner/`, `.claude/workflows/`, the orchestrate-stage skill,
`docs/AGENT_WORKFLOW.md`) belong to this track while it runs: other tracks touch them only through an issue here, and
a change to them lands between the other managers' waves.

### 8. Beyond the seven items
- **The playtest bugs** (#168, #169): item 4 (g) with P9, scripted off-screen client runs that screenshot named
  moments (spectating, the Esc menu, downed, the HUD); `Input.parse_input_event`, `Input.action_press`,
  `Viewport.get_texture`, `Texture2D.get_image` and `Image.save_png` exist in 4.7.2. Like `shot`, it needs a desktop
  session and never runs on CI. The engineer's playtest stays.
- **The prompt cache:** a 1-hour cache lifetime for subagents (`subagentPromptCacheTtl`) was costed and rejected
  (Alternatives); a `verify` under 5 minutes removes most re-writes, and agents should not wait on CI longer than
  needed.
- **Task size:** an implementer's cost grows with its tool calls times its context. Design splits aim at tasks an
  implementer finishes in about 150 tool calls (M4's took 101 to 246); the manager checks the size with `metrics`.

### Needs the engineer (one package)
1. **N1, the model policy** (amendment A): (a) none; (b) per launch for designs, second reviews of core/, server/,
   net/, tests/harness/ PRs, audits and twice-red tasks, at most half of the weekly window across tracks;
   (c) also managers; (d) everywhere. **Recommended (b).**
2. **N2, the git flow of parallel tracks** (amendment B): (a) as today; (b) a release branch per track; (c) every PR
   into `main`; (d) (b) for night tracks and (c) for day tracks, with a `main` sync each wave and a closing PR at
   least every three days. **Recommended (d).**
3. **N3, night jobs:** (a) none; (b) GitHub Actions only; (c) (b) plus one Claude audit lens a night on the PC
   (on overnight, the Desktop app open; about 0.25% of the week a night); (d) cloud routines. **Recommended (c),
   starting as (b) until P12 lands.**
4. **N4, selftest only when `tools/` changed (locally):** (a) no, `verify` stays exactly what CI runs; (b) yes.
   **Recommended (a).**
5. **N5, shared limits across tracks:** at most about six task workflows at once across tracks and each kickoff's
   budget as a percentage reported from `metrics`. **Recommended as written.**

### The proposed issues (in full in the handoff on #171)
Waves of at most two tasks while the M4 manager runs, three after; a task that needs an unmerged PR waits for the
engineer's merge unless "stacks" is said. Tasks that edit `.claude/` run only while the engineer is present (today
until about 21:00 UTC), so P3 and P6 go early.

| wave | issue | area, size | `.claude/` | depends on (waits for the merge unless "stacks") | shared files it owns in its wave |
|---|---|---|---|---|---|
| 1 | P1 `metrics`: the baseline as a runner command | tooling, M | no | none | `cli.py`; AGENT_WORKFLOW §11 command list; root CLAUDE.md commands table |
| 1 | P2 `verify` in two lanes, selftest in worker processes, a verify history record | tooling, M | no | none | `verify.py`; AGENT_WORKFLOW §11 CI paragraph |
| 2 | P3 `issue-task` v2: optional plan review, test review, second review, skeptic, visual, efforts and models | tooling, L | yes | none to build (managers enable `test_review` after P7 and `visual` after P9) | `.claude/workflows/`; `test_workflows.py`; AGENT_WORKFLOW §7.1 workflow paragraph |
| 2 | P4 `merge-check` and `merge` | tooling, L | no | P1 (`cli.py`) | `merge.py`, `cli.py`; AGENT_WORKFLOW §7.1 git-flow bullet |
| 2 or 3 | P5 an own `user://` per worktree, GdUnit4 in shards | tooling, M to L | no | P2 | `gdunit.py`, `common.py`; AGENT_WORKFLOW §11 test paragraph |
| 3 | P6 the orchestrate-stage skill and AGENT_WORKFLOW for pipeline v2 | tooling, M | yes | P1, P3; P4 (stacks on P4's branch if still open); N1, N2 answered | the skill; AGENT_WORKFLOW §7.1 |
| 3 | P7 `mutants`: plant one fault, run the named tests, restore | tooling, S to M | no | P1 (`cli.py`) | `mutants.py`, `cli.py`; AGENT_WORKFLOW §11 command list |
| 4 | P8 at most N verify runs at once on the PC | tooling, S | no | P2, P5 | `verify.py`, `common.py`; AGENT_WORKFLOW §11 CI paragraph |
| 4 | P9 `playcheck`: scripted off-screen client runs with screenshots | tooling, L | no | P1; #167 (for the #168 and #169 scenarios) | `playcheck.py`, `cli.py`, `tools/playcheck/` |
| 5 | P10 `perf`: 10 bots, tick time and snapshot sizes | tooling, M | no | P1 | `perf.py`, `cli.py`, `tests/harness/perf/` |
| 5 | P11 chaos bots against the host (dropped first) | net, L | no | P2 | `tests/harness/chaos/`, `bots.py`, one `verify` step |
| 5 | P12 night jobs: the nightly CI run and one audit lens | tooling, M | yes | N3; P10 and P11 for their jobs (it starts with the flaky-test repeats) | `.github/workflows/nightly.yml`, a `night-audit` skill |

Within a wave at most one task edits `tools/runner/cli.py` or `tools/runner/verify.py`, and each task owns a different
paragraph of `docs/AGENT_WORKFLOW.md`; waves 4 and 5 assume the M4 manager has finished (otherwise the third task
waits). The order follows leverage: what speeds up or measures every later task first (P1, P2), then the workflow
and the merge flow the other tracks will use (P3, P4), then the rest. Cost: about $15 to $30 list a task, about
$250 to $350 for the twelve (6 to 8% of a Max 20x week) plus the manager, within the track's 20 to 25%. Drop order:
P11, then the per-wave report in P6, then audit lenses beyond one in P12.

## Amendment draft A: the model guard (to `2026-09-28-model-guard-no-fable-in-shared-config.md`), Needs the engineer
Proposed text, added under its Decision if N1 is (b):
- The shared `availableModels` stays `["opus", "sonnet", "haiku"]`. The engineer may add `fable` to
  `availableModels` in his own `~/.claude/settings.json`; the designer's machine does not.
- Workflows take an optional `models` argument per role; no default names a model outside the shared list, and the
  workflow tests assert it.
- A manager passes Fable only where the kickoff allows it: stage designs, a second review of PRs that touch core/,
  server/, net/ or tests/harness/, audits, and a task that went red twice. Budget: at most half of the weekly Fable
  window across all tracks; each wave comment reports its use from get_usage.
- Fable may be named in ADRs and in issue and PR comments (kickoffs, launch arguments in the handover data, usage
  reports). It stays out of `.claude/` (settings, agents, workflows, skills, rules), `tools/`, `.github/`, every
  CLAUDE.md file and any workflow argument's default.
- Usage credits stay off or capped (unchanged); `agents-check` proves which model served each agent (unchanged).

## Amendment draft B: release branches (to `2026-10-01-release-branch-per-milestone.md`), Needs the engineer
Proposed text, replacing "There is no `staging` branch and one milestone runs at a time" if N2 is (d):
- Several tracks may run at once (a milestone stage, the UI, 3D and AI productivity tracks). A track that runs
  unattended at night gets its own `release/<track>` (`release/m<k>` for a milestone stage) under the rules above; a
  track the engineer follows during the day sends its PRs straight into `main`, where he merges each.
- Each release branch takes `main` in at the start of every wave: its manager merges `origin/main` into it in its
  release worktree, runs `verify` on the merged tree and pushes by hash, as for a task PR.
- A release branch closes into `main` through one PR at its milestone's end and at least every three days; a human
  merges it.
- Before every merge, into a release branch or (for the engineer) into `main`, the manager runs `merge-check` across
  all open PRs and names the safe order.
- Still no `staging` branch.

## Alternatives
- **A 1-hour cache lifetime for subagents** (`subagentPromptCacheTtl` or `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`,
  Claude Code 2.1.242 and later): the re-writes after long waits would become reads (about $115 saved), but every
  other subagent cache write would cost $8 instead of $5 per million on Opus (about $107 more, plus the agents' first
  writes): break-even at best. A `verify` under 5 minutes removes the cause instead.
- **Selftest locally only when `tools/` changed** (N4 (b)), **`publish` skipping a verify of an identical tree**,
  **the ENet runs in parallel**, **CI import caching**: see item 2.
- **A skeptic on every finding by default:** false findings are rare (8 of 441 judged wrong by the publishers).
- **A monitoring stack (OpenTelemetry)** and **hooks logging every tool call:** a new service or more hooks for data
  the transcripts already hold.
- **GitHub's merge queue:** merges through GitHub, which agents may not do (only humans merge into `main`).
- **Cloud routines for the night jobs:** they run with the PC off, but in cloud credits (about $5 for about 140k
  tokens in the trial, #159), and the deterministic jobs run free on GitHub Actions.
- **The strongest model everywhere, or named in shared settings:** its separate weekly window would last a few
  tasks (item 5 (d)); the model-guard ADR keeps it out of shared files.
- **A release branch per milestone with one milestone at a time** (today's rule) for four parallel tracks: it blocks
  them; see amendment B.

## Consequences
- Every later change is measured: the wave comments carry time and cost per task, and the ADR's baseline is the
  reference (M4: 82 minutes, $24 list, about 0.55% of a Max 20x week per task).
- `verify` gets faster without losing a step; with it the cache re-writes, the cross-worktree `user://` collisions
  and the CPU contention of parallel tracks go.
- `issue-task` keeps its default behaviour; managers opt into each v2 stage per launch, so other tracks are unaffected
  until they choose.
- The humans' work changes only where they say yes: the model policy (N1), the git flow of parallel tracks (N2), the
  PC on at night (N3).
