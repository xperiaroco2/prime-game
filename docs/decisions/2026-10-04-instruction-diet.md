# Instruction diet: agents load only the instructions and docs a task needs

- **Status:** Proposed (design task #313). The engineer chooses N1 to N3 below; the build waits for his choice.
- **Date:** 2026-10-04
- **Deciders:** the engineer (N1 to N3). The measurement, the cost model and the technical framing are the design
  task's, under the engineer's delegation of technical choices (#134).
- **Tracking:** Token efficiency, #302 (its verified report and the engineer's answers: lean agent types wait for the
  cache-read probe, #307).

## Context
Every agent pays for its instructions three ways. At launch it gets the main checkout's root `CLAUDE.md`, the user
memory, the skill listing and the MCP servers' instructions. Some files load **by path**: a nested `CLAUDE.md` loads
when the Read tool opens a file in its folder, and a `.claude/rules/` file when Read, Write or Edit touches a file its
`paths:` match (code.claude.com/docs/en/memory; a shell `cat` or `sed` loads neither). The rest it **reads** with
tools: `docs/ARCHITECTURE.md` (3,593 lines, 386k characters, about 164k tokens), `docs/AGENT_WORKFLOW.md` (1,230
lines, 124k characters) and the ADRs. Whatever enters the context is carried by every later call of that agent.
#302 found that reads of large docs cost about $127 a week, ARCHITECTURE alone about $63, and that root `CLAUDE.md`
sits at its 150-line budget ([instruction budgets ADR](2026-09-29-instruction-files-and-budgets.md)). #303's implementer found that a workflow
agent gets only the main checkout's root `CLAUDE.md` and the user memory at launch. This design measures what each
role loads and uses, then gives the engineer options to cut it without losing a rule.

### How it was measured
A read-only script over the transcripts under `~/.claude/projects/D--prime-game*/` (not the art and UI
repositories). The window is this limit week, 2026-09-29 10:00 to 2026-10-04 03:00 UTC (4.71 days: M2's end, M3, M4,
M5 and the tooling tracks). It covers 683 agent transcripts: 619 workflow agents in 117 `issue-task` runs and other
workflows, 41 hand-run subagents, 9 manager sessions and 14 other main sessions. #313's own run is left out.
- **What enters a context:** each transcript's `instructions` attachment (the files loaded at launch), its
  `nested_memory` attachments (files loaded by path), the `skill_listing` and `mcp_instructions_delta` attachments,
  and the result of every tool call that reads a doc: Read, Grep, and Bash or PowerShell commands that name a doc
  path. Runner output and `git diff/show/log` never count.
- **Cost of an item:** it is written to the cache once, at the agent's 5-minute or 1-hour mix. Every later call reads
  it, until a compaction or the agent's end. A later call that re-wrote at least half of its context (a lapsed cache)
  writes the item again. Tokens are characters / 2.35, the median of 4,397 context-growth pairs after a lone tool
  result of 4,000 characters or more (#302 found 2.33 to 2.55). Prices are `metrics`' `PRICES`.
- **Points** are % of a Max 20x week, (non-read $ + w x cache-read $) / k(w), with k(0) = 15.3 and k(0.5) = 20.3
  (#302; w is the weight the limit gives cache reads, which #307 measures). "Per 7 days" scales the window by 1.49 at
  this week's volume (about 174 `issue-task` runs a week).
- **Sections** are matched to today's files by line text. 5% of ARCHITECTURE's returned text and 11% of
  AGENT_WORKFLOW's has changed since and is left out of the section tables. A grep hit marks its section as
  "touched", not read.
- **Caveats:**
  - Launch items count as written once per agent, but general workflow agents read 32% of their first call from the
    cache (another agent's prefix), so the launch items' non-read $ is high by up to a third.
  - Bounded waits (#303, on `main` since #310) remove most re-writes, so most figures are also given without them.

### What each role loads and reads
Medians per agent: launch-loaded, path-loaded and read tokens. The window total covers instruction and doc items only.

| role | agents | calls | first call | launch-loaded | path-loaded | docs read | $ per agent | $ in window | of the role's $ |
|---|---|---|---|---|---|---|---|---|---|
| implementer | 120 | 82 | 56.9k | 14.2k | 5.4k | 18.7k | $0.98 | $162 | 17% |
| publisher | 124 | 49 | 63.3k | 14.2k | 2.6k | 3.7k | $0.45 | $68 | 16% |
| code-reviewer | 119 | 20 | 19.2k | 6.3k | 4.9k | 3.3k | $0.13 | $18 | 14% |
| godot-api-checker | 71 | 31 | 19.4k | 6.3k | 7.7k | 5.6k | $0.13 | $10 | 11% |
| netcode-security-reviewer | 62 | 17 | 19.5k | 6.3k | 6.9k | 2.9k | $0.13 | $10 | 19% |
| planner, plan-reviewer, test-reviewer | 23 | 14 to 34 | 28k to 62k | 7.0k to 15.3k | 0 to 2.1k | 0 to 21.5k | $0.11 to $0.36 | $6 | 15 to 19% |
| `pr-rebase` agents | 11 | 52 to 76 | 51k to 54k | 12k to 13k | 6.5k to 7.8k | 7.2k to 9.8k | $0.33 to $1.01 | $7 | 15 to 18% |
| other workflow agents (research, designs) | 88 | 21 | 56.5k | 14.2k | 0 | 0.6k | $0.16 | $21 | 10% |
| hand-run subagents | 41 | 15 | 14.9k | 5.9k | 0 | 0 | $0.07 | $4 | 12% |
| manager sessions | 9 | 315 | 72.5k | 15.1k | 0 | 33.9k | $4.15 | $42 | 8% |
| other main sessions | 14 | 86 | 61.4k | 12.7k | 0 | 2.6k | $0.51 | $7 | 7% |

A general workflow agent's launch-loaded items are root `CLAUDE.md` (5.5k tokens), the skill listing (7.5k) and the
MCP instructions (1.2k). The three reviewer types start with no skill listing: their `tools:` lists have no Skill tool.
Per `issue-task` run, instructions and docs cost a median $1.91 of a median $12.55 run (16%).

### By file

| what | how it gets in | loads or reads | tokens in | list $ | of it non-read | main roles |
|---|---|---|---|---|---|---|
| the skill listing | launch, general agents | 440 | 2.91M | $67 | $32 | implementer 39%, publisher 32% |
| `docs/ARCHITECTURE.md` | read | 1,590 | 3.20M | $66 | $30 | implementer 66%, publisher 11%, manager 7% |
| root `CLAUDE.md` (the main checkout's) | launch | 681 | 3.67M | $63 | $31 | implementer 30%, publisher 24% |
| ADRs | read | 923 | 1.89M | $45 | $19 | implementer 49%, manager 25% |
| root `CLAUDE.md`, **the worktree's copy** | by path | 231 | 1.19M | $19 | $9 | implementer, publisher, code-reviewer |
| `.claude/rules/*.md` (main's and the worktree's copies) | by path | 1,022 | 1.30M | $19 | $10 | implementer 39%, publisher 27% |
| area `CLAUDE.md` | read by a tool | 724 | 0.69M | $17 | $7 | implementer 72% |
| `docs/AGENT_WORKFLOW.md` | read | 601 | 0.69M | $15 | $8 | implementer 54%, manager 21% |
| MCP server instructions | launch | 654 | 0.68M | $13 | $6 | implementer 34%, publisher 26% |
| area `CLAUDE.md` | by path | 315 | 0.73M | $10 | $5 | implementer 43% |
| workflow scripts, skills | read | 139 | 0.60M | $12 | $6 | implementer, manager |
| GDD, ROADMAP, interventions, other docs | read | 267 | 0.27M | $6 | $2 | manager, implementer |
| root `CLAUDE.md` again | read by a tool | 288 | 0.23M | $4 | $2 | implementer 48% |

**In total: $355 of the agents' $2,610 list (13.6%).** Of the $355, first writes are $89, re-writes after a lapsed
cache $78, and cache reads $188. Per 7 days at this week's volume that is 16.2 points (w = 0) to 19.1 (w = 0.5).
With bounded waits (#303) it is about 8.6 to 13.5.

### Which sections are used
**ARCHITECTURE by section group** (today's file: 164k tokens):

| group (§) | size (tokens) | list $ | share of each task area's ARCHITECTURE $ |
|---|---|---|---|
| client (4.7) | 28.3k | $5.4 | client 32% |
| content API (9.1 to 9.4, 9.8) | 24.2k | $8.4 | core 24% |
| bots and leak test (4.6, 9.7) | 22.9k | $7.8 | tooling 39%, net 17%, voice 17%, server 15% |
| protocol (4 to 4.4) | 22.9k | $11.3 | net 38%, voice 18%, client 17%, core 16% |
| movement (7, 7.1) | 15.4k | $6.7 | client 14%, net 14%, core 12% |
| MVP content (9.5, 9.6) | 11.9k | $4.5 | core 13% |
| voice (6) | 11.6k | $2.7 | voice 24%, server 12% |
| host session (4.5) | 11.3k | $4.5 | server 56%, tooling 24%, net 12% |
| match (1 to 3.5) | 10.6k | $5.2 | core 12% |
| filtering (5) | 2.9k | $2.5 | (read by 135 agents) |

A task reads across groups. A core task's ARCHITECTURE reads spread over six groups, from 24% down to 11% each; a
client task's over client, protocol and movement; a net task's over protocol, bots and movement. Only server tasks
stay mostly in one group (56%). Implementers touch a median 58% of the file's sections by size, grep hits included;
publishers 17% and reviewers 22 to 28%.

**How the docs are read.**
- Whole reads are rare: 7 of ARCHITECTURE in 4.7 days, 56 of ADRs ($15.1).
- Most reads are ranges, but a range misses the section's end. A Read with offset and limit covers 3.1 sections on
  average, and 46% of its text lies outside the section it mostly returned ($16.5 of the $35.6 of such reads).
- Shell reads (`sed -n`) overshoot less (23%).
- Searches for headings and terms cost $9.9 on ARCHITECTURE.
- Re-reading the same section in one agent is negligible ($0.2).
- Reading a section another agent of the same run already read: 2,130 times, $14. That is the price of fresh-context
  reviews and stays.

**AGENT_WORKFLOW:** §11 (Godot specifics, 43.9k characters) is $4.1 of its $15, three quarters of that in tooling
tasks. §7.1 (the orchestrator) costs $1.6, §8.2 (the guard) $0.8, the rest $0.4 or less each.

**Root `CLAUDE.md`** as it loads (16k characters):
- The commands table is 26% of it. 15% (routing, talking to the humans, memory, the dictation glossary) serves only
  sessions with a human; workflow agents run unattended.
- Most workflow roles run only a few of the runner's about 30 commands:
  - implementers: `verify` 97%, `lint` 79%, `test` 62%, `check` 47%, `merge-check` 24%, `normalize` 22%, `bots` 18%,
    the rest 14% or less;
  - publishers: `board` 92%, `publish` 91%, `lint` 73%, `test` 56%, `verify` 56%;
  - reviewers: `test` and `check` (the godot-api-checker 75% and 44%, the others 11% or less).
- Agents still grep or `sed` the file they were given at launch: 288 times, $4. The plan-review prompt asks for it
  explicitly.

### Duplicate loads
The workflow agents' working directory is the main checkout, and they Read files under `.claude/worktrees/<n>/`.
Reading such a file loads three things by path:
- the worktree's root `CLAUDE.md`, as a nested file: a second copy of root `CLAUDE.md`, 5.5k tokens (231 loads);
- the worktree's copy of each matching rule, beside the main checkout's copy, which matches worktree files too (352
  agent and rule pairs got both);
- the worktree's area `CLAUDE.md`. This one is wanted: it is the branch's version, and it loads only once.

The two duplicates cost $25 in the window, 1.2 to 1.4 points per 7 days (0.7 to 1.0 with bounded waits). Claude Code
already skips a worktree's root `CLAUDE.md` and rules for subagents it isolates itself (`isolation: worktree`,
code.claude.com/docs/en/worktrees). Our worktrees come from `start`, so that rule does not apply to them.

Only the root duplicate can go. A session started inside a worktree (the engineer's task session, AGENT_WORKFLOW
§4.1) loads only the worktree's copy of each rule, never the main checkout's: in the transcripts under
`D--prime-game--claude-worktrees-*`, every rule loaded by path is the worktree's copy, and none is main's. Excluding
the worktree's rules would leave such a session with no `gdscript.md`, `tests.md` or `godot-resources.md`. The root
duplicate is $19 of the $25: 0.90 / 1.04 points per 7 days, 0.55 / 0.78 with bounded waits. The rule pairs ($6, 0.19
/ 0.25 with bounded waits) stay.

## Decision (proposed)

### What this design decides (technical framing)
- **The method and the unit.** Cost per role from the transcripts, as above, with every saving given at w = 0 and
  w = 0.5 and after bounded waits. Proposed issue E makes the method a `metrics` section, so the build is measured
  against this baseline (the pipeline v2 ADR's rule: every change is measured).
- **§ numbers stay stable in every option.** 654 lines of tracked files name ARCHITECTURE, 513 of them with a § number
  (code comments in `core/events`, `core/content` and `core/match` included), and at least 100 issues and PRs name
  it. A § number must stay an address that resolves.
  - *Failure prevented:* a renumbered or moved section silently breaks every "§4.5" in code comments and issues.
- **Duplicates go through `claudeMdExcludes`, not through the workflow scripts.**
  - What it is: a setting that skips instruction files by absolute-path glob, at any settings layer; the arrays merge
    (code.claude.com/docs/en/memory). Installed Claude Code: 2.1.284.
  - The pattern: `**/.claude/worktrees/*/CLAUDE.md`. One `*` does not cross a folder, so area files such as
    `.claude/worktrees/<n>/core/CLAUDE.md` still load. No pattern for the worktree's `.claude/rules/`: a session
    started in a worktree has only that copy (Duplicate loads, above).
  - *Failure prevented:* every agent that reads a worktree file carries root `CLAUDE.md` twice.
  - It is checked by two probes before the setting lands, a workflow agent and a session started in a worktree
    (issue A).
- **Sections come from a runner command, not a generated index file.**
  - `tools\run.cmd section <doc>` prints the outline: §, title, line range and tokens.
  - `tools\run.cmd section <doc> <§>...` prints exactly those sections, up to the next heading of the same or a
    higher level.
  - *Failure prevented:* a committed index drifts on each of ARCHITECTURE's commits (283 in six days). A Read range
    that guesses where a section ends returns 46% of other sections.
- **Large sections get numbered subsections from their existing bold labels.** These are the sections over about 7k
  tokens: §4.7, §4.6, §7.1, §6, §4.5, §9.5, §9.4 and §4.3, and AGENT_WORKFLOW §11 and §8.2; §4.7 alone is 28k. The
  labels become `#### 4.7.1 ...` and no other text changes.
  - *Failure prevented:* a "section read" of §4.7 still costs 28k tokens.

### The options

| | option | saving, points per 7 days (w = 0 / w = 0.5, after bounded waits) | migration cost | risk of an agent missing a rule | how lint and docs drift keep working |
|---|---|---|---|---|---|
| O1 | **Load root `CLAUDE.md` once** (`claudeMdExcludes` for the worktree's root `CLAUDE.md`) | 0.55 / 0.78 (before #303: 0.90 / 1.04); certain | S: one settings entry, two probes, a runner test, a §3 row | low (see O1) | budgets unchanged; a runner test asserts the pattern; issue E's duplicate count shows no root `CLAUDE.md` twice |
| O2 | **Read by section**: `section` command, numbered subsections, a lint check for § references, prompts that name sections | about 0.6 to 0.9 / 1.0 to 1.4 (50 to 75% of 1.14 / 1.92 addressable) | M (B) plus S (C); no file moves | low to medium (see O2) | docs have no budget; a new lint check fails a § reference that does not resolve or a duplicate § (a deterministic docs-drift check); the night audit's lens is unchanged |
| O3 | **Per-area architecture files with an index**: `docs/architecture/<§>-<slug>.md` per group, ARCHITECTURE.md an index keeping every § | about the same as O2 (the file boundary does what `section` does) | L: 654 referring lines, CODEOWNERS, the night-audit lens; a move between waves while no open PR touches ARCHITECTURE | medium (see O3) | O2's § check over the new files; a size budget per file in lint; the night-audit lens and CODEOWNERS paths change |
| O4 | **Reference tables out of always-loaded files**: root's commands table becomes one line of names plus `tools\run.cmd <command> --help` | 0.38 / 0.55; plus about 18 of root's 150 budget lines freed | S to M | medium (see O4) | lint's root count drops; a runner test checks the names line against `cli.py` both ways and that each command's `--help` says what the row said |
| O5 | **Lean workflow agent types with role packs** (extends #302's lever 5) | skill listing and MCP instructions 1.60 / 2.49; the tool schemas per #302 (0.8 / 2.3 over its 34.4 hours); role packs about 0.6 / 0.9 more | M to L, and it reverses AGENT_WORKFLOW §5's "every project subagent is read-only" (#302 decision 4) | high for packs, low for lean types alone (see O5) | `instructions.py` learns the `omitClaudeMd` and `skills` agent fields; a pack generator, and lint fails a stale pack |

**O1. Load root `CLAUDE.md` once.** Two probes run before the setting lands:
- A workflow agent (working directory: the main checkout) Reads a worktree `.gd` file and a `tests/` file. Its
  transcript's `nested_memory` lines show `gdscript.md` and `tests.md` (from either copy) and the worktree's
  `core/CLAUDE.md`, and no worktree root `CLAUDE.md`.
- A session started in `.claude/worktrees/<n>` loads a root `CLAUDE.md` at launch, then Reads a `.gd` file, a
  `tests/` file and a `.tscn`. Its `nested_memory` lines show `gdscript.md`, `tests.md` and `godot-resources.md`.
  The 8 measured worktree sessions loaded `D:\prime-game\CLAUDE.md` at launch, never the worktree's, so the
  exclude should not touch them; the probe checks it.
- *Fallback:* if either probe loses a file it should show, the setting does not land, and A reports what loaded.
- *Risk:* a branch that changes root `CLAUDE.md` or a rule is followed under `main`'s version until it merges. That
  is already true at launch today, and the agent that edits the file reads it anyway.
- *Who decides:* the change is technical and reversible, so it is decided here. It edits `.claude/settings.json`, so
  the engineer merges it (#300's proposed gate refuses `.claude/settings*.json`).

**O2. Read by section.**
- Rule: one sentence in root `CLAUDE.md`, changed in place with no net growth: "read docs by section:
  `tools\run.cmd section <doc>` for the outline, then the § you need; never a whole doc".
- Prompts: `issue-task.js` and `pr-rebase.js` give the plan reviewer and the reviewers "the ARCHITECTURE sections the
  change touches", not `docs/ARCHITECTURE.md`. The plan-review prompt stops asking to read root `CLAUDE.md`, which is
  already loaded.
- What it saves: the over-fetch of range reads, the heading searches (one outline call replaces them) and part of the
  whole ADR reads. The ADRs have headings too, so `section` serves them.
- *Risk:* an agent reads §4.5 and misses a constraint stated in §5. Agents already read ranges (7 whole reads in 4.7
  days), so this changes where a read ends, not whether a constraint is in view. The outline shows every section's
  title, the invariants stay in root `CLAUDE.md`, and the cross-references already name the § to follow.

**O3. Per-area architecture files.**
- It saves no more than O2. Tasks read across 3 to 6 groups, so a split does not localize the reading.
- An agent that Reads a whole area file over-fetches more: the client file alone would be 28k tokens.
- It has one benefit beyond tokens: fewer textual conflicts between parallel PRs. ARCHITECTURE had 283 commits in
  six days, so parallel PRs often touch it; how often that conflicts is not measured here.
- *Risk:* higher than O2. An agent must know which file holds a rule. A grep over `docs/architecture/` works, but the
  habit of one file is gone.

**O4. Reference tables out of always-loaded files.**
- Root's commands section becomes three or four lines: the command names, `tools\run.cmd <command> --help`, and the
  logs and reports line.
- Root's human-only sections (15%) cannot move without O5's packs: every session loads root, and the human sessions
  need them.
- Area `CLAUDE.md` files cost $10 by path in the window (0.3 / 0.4 points per 7 days): not worth trimming now.
- *Risk:* an agent forgets that a command exists. The failure: it runs Godot by hand, against the hard rule, or skips
  `normalize` after a `.tscn` edit. Three things limit it:
  - the names line keeps every command visible;
  - `godot-resources.md` already names `normalize` when a `.tscn` is touched;
  - the prompts name the commands each role runs.

**O5. Lean agent types with role packs.**
- Lean types alone: the implementer and the publisher get agent types with a `tools:` allowlist and no Skill or MCP
  tools. Their first call drops the skill listing (7.5k), the MCP instructions (1.2k) and most tool schemas (#302:
  56k down to about 21k for the implementer). This is #302's proposed issue E, which waits for #307.
- Role packs on top: `omitClaudeMd: true` launches the agent without the project and user `CLAUDE.md` (Claude Code
  2.1.271 and later), and `skills:` preloads a role pack instead (code.claude.com/docs/en/sub-agents).
  - What goes in a pack: a runner command generates it from tagged root `CLAUDE.md` sections (hard rules, invariants,
    shell, the role's commands, definition of done). It leaves out routing, talking to the humans, memory and the
    glossary, which no unattended agent uses.
  - *It amends the [instruction budgets ADR](2026-09-29-instruction-files-and-budgets.md):* that ADR keeps the hard
    rules and invariants in root `CLAUDE.md` because root survives compaction (AGENT_WORKFLOW §3: "re-injected after
    compaction"). Implementers average 82 calls and can compact. Whether a preloaded skill is re-attached after
    compaction is not documented or measured, so packs need a probe first: an agent with a pack that compacts must
    still show the pack in its context afterwards. If it does not, packs are off the table.
  - *Risk:* a pack that misses a hard rule is the one way this design can lose a rule. A generator plus a stale-pack
    lint keeps the packs from drifting, but not from a wrong tag.

### How the options combine
- **O1 to O4 against O5.** O1 to O4 remove tokens that enter mid-context (docs read, files loaded by path) or sit in
  root `CLAUDE.md`. O5 removes the launch prefix. The sets do not overlap, so the savings add. The one exception is O4
  with O5's packs: with packs, O4's saving applies only to main sessions and reviewers.
- **The probe.** #307's probe decides w. O1, O2 and O4 are worth something at any w, so they need no probe. O5's
  value at w = 0 is mostly the skill listing and the schemas' first writes; #302 recommends it only if w is at least
  0.25.
- **#302's lever 7** ("shorter, shared tool outputs: section reads"; the manager's call) is O2's prompt part. The
  measurement here replaces its assumed cut.
- **Bounded waits (#303)** halve the non-read value of everything here, because 47% of the instructions' non-read $
  was re-writes after long waits. The figures above are given after that.
- **Recommended now (O1, O2, O4): about 1.5 to 1.8 points per 7 days at w = 0 and 2.3 to 2.7 at w = 0.5** at this
  week's volume. This week's whole load at that volume is 148 to 152 points per 7 days, so the saving is about 1 to
  2% of it. Nothing a task reads goes away.

### Needs the engineer
1. **N1, how agents read ARCHITECTURE and AGENT_WORKFLOW:**
   - (a) section reads (O2: issues B and C);
   - (b) per-area files with an index (B's lint check, then G);
   - (c) (a) now, and (b) later only if ARCHITECTURE keeps showing up as a conflict in `merge-check`;
   - (d) neither.

   **Recommended (a).** It saves what (b) saves, because tasks read across groups. It needs a fraction of the
   migration and no file move between waves.
2. **N2, root `CLAUDE.md`'s commands table:**
   - (a) a names line plus `--help` (O4, issue D);
   - (b) keep the table.

   **Recommended (a).** It frees about 18 of the 150 budget lines that every PR adding a command competes for.
3. **N3, after #307, how lean the workflow agents get:**
   - (a) lean agent types only (no skill listing, MCP instructions or unused tool schemas; root `CLAUDE.md` still
     loads);
   - (b) also `omitClaudeMd` with generated role packs (it amends the instruction budgets ADR, and only if the
     compaction probe in F passes);
   - (c) not now.

   **Recommended (a) first, and (b) only as an A/B trial on 3 to 4 tasks after (a)'s data.** This keeps the
   engineer's answer on #302: lean types wait for the probe.

O1 (issue A) is technical and recommended here. The engineer merges it because it changes `.claude/settings.json`.

### Proposed issues (milestone Token efficiency, area:tooling; the build waits for N1 to N3)

| order | issue | size | decides | depends on | files |
|---|---|---|---|---|---|
| 1 | A. Workflow agents load root `CLAUDE.md` once (`claudeMdExcludes`) | S | manager; the engineer merges | none | `.claude/settings.json`, a runner test, AGENT_WORKFLOW §3 |
| 1 | E. `metrics`: instruction and doc cost per role | M | manager | none; after #314 (both touch `metrics.py`) | `tools/runner/metrics.py`, its tests and fixtures |
| 2 | B. `section`: a doc's outline and exact sections; numbered subsections; lint checks § references | M | N1 (a) or (c) | none | `tools/runner/section.py` (new), `cli.py`, the lint check, tests, ARCHITECTURE and AGENT_WORKFLOW headings only, one root `CLAUDE.md` row in place |
| 3 | C. Prompts and the rule read docs by section | S | N1 (a) or (c) | B | `.claude/workflows/issue-task.js`, `pr-rebase.js`, the workflow snapshots, root `CLAUDE.md` one sentence in place |
| 3 | D. Root `CLAUDE.md`'s commands table becomes a names line plus `--help` | S to M | N2 (a) | none; after C when both are open (both edit root `CLAUDE.md`); lands between waves | `CLAUDE.md`, `cli.py` help texts, a runner test, AGENT_WORKFLOW §3 |
| after #307 | F. Lean workflow agent types, and role packs if N3 (b) (extends #302's E) | M to L | N3, #302 decision 4 | #307 | `.claude/agents/`, `issue-task.js`, `instructions.py`, a pack generator, AGENT_WORKFLOW §5 |
| only if N1 (b) or (c) | G. ARCHITECTURE.md into per-area files with an index | L | N1 | B | `docs/architecture/`, `docs/ARCHITECTURE.md`, CODEOWNERS, the night-audit skill's lens |

Acceptance criteria. Each issue gives its before and after numbers from E, or from this ADR's method until E lands.
C and F change `.claude/workflows/`, which changes only through the tooling track (pipeline v2 ADR, N5 (c)).
- **A:**
  - a probe workflow agent shows the O1 result in its transcript;
  - a session started inside a worktree still loads root `CLAUDE.md` at launch, and its Reads of a `.gd` file, a
    `tests/` file and a `.tscn` still load `gdscript.md`, `tests.md` and `godot-resources.md`; if either probe loses
    a file, the setting does not land;
  - `.claude/settings.json` carries the pattern (no pattern for the worktree's rules), and a runner test asserts it;
  - the AGENT_WORKFLOW §3 table says which copy loads.
- **E:** `metrics` prints per role:
  - agents, and launch-loaded, path-loaded and read tokens;
  - list $ split into first writes, re-writes and reads;
  - points at w = 0 and 0.5;
  - files loaded twice in one agent;
  - ARCHITECTURE and AGENT_WORKFLOW $ by §.

  Selftest fixtures cover each part.
- **B:**
  - `section <doc>` prints the outline, and `section <doc> <§>...` prints exactly those sections, for ARCHITECTURE,
    AGENT_WORKFLOW and any ADR;
  - the large sections get numbered subsections, with no other text change (the engineer approves the doc diff);
  - lint fails a duplicate § in a doc, and a § reference to ARCHITECTURE or AGENT_WORKFLOW in tracked files
    (`docs/history/` excluded) that does not resolve; the same PR fixes the references that already dangle;
  - runner tests cover all of it;
  - the root `CLAUDE.md` row is changed in place, with no net growth.
- **C:**
  - the plan-review and review prompts name sections, not the whole doc, and no prompt asks to read root `CLAUDE.md`
    again;
  - the snapshots change on purpose;
  - one wave later E shows ARCHITECTURE $ per run down, and no review finding traced to a section not read.
- **D:**
  - root's commands section is at most five lines, and lint's root count drops by at least 18;
  - a runner test checks the names line against `cli.py` both ways, and that each command's `--help` covers its old
    row;
  - the night audit's docs-drift lens needs no change (it already checks commands against `--help`).
- **F:** #302's E, plus:
  - the lean agents' first call carries no skill listing or MCP instructions;
  - if N3 (b): a generated role pack, `omitClaudeMd`, a stale-pack lint, and `instructions.py` accepting the new
    agent fields;
  - if N3 (b), before any trial: a probe agent with a pack runs until it compacts, and its transcript shows the pack
    re-attached afterwards (hard rules and invariants in context). If it does not, (b) is dropped. The PR amends the
    instruction budgets ADR.
- **G:**
  - every § resolves through the index;
  - one file per group, under a lint size budget;
  - CODEOWNERS and the night-audit lens are updated;
  - it lands when no open PR touches ARCHITECTURE.

## Alternatives
- **Only a prompt rule** ("read sections, not whole docs") with no tool. Agents already read ranges; the over-fetch
  comes from not knowing where a section ends, which a rule cannot fix. It is kept as C, on top of B.
- **A committed index or digest of ARCHITECTURE.** An index drifts on every edit (283 commits in six days). A
  hand-written digest drifts in meaning, and an agent would trust it over the source.
- **`@import`ing ARCHITECTURE sections into area `CLAUDE.md` files.** Imports load with the file every time, so they
  add tokens to every path-load.
- **Search over the docs through an MCP server (embeddings).** A new dependency, plus tool schemas and MCP
  instructions in every agent's launch prefix: the kind of cost O5 removes.
- **Workflow agents with their working directory in the task's worktree** (so only one root `CLAUDE.md` is found).
  The workflow scripts pass `label`, `phase`, `schema`, `model`, `effort` and `agentType`, and no working-directory
  option is used or documented in this repository. `isolation: worktree` makes a new temporary worktree, not the
  task's. The excludes reach the same result without touching the scripts.
- **Trimming the area `CLAUDE.md` files or AGENT_WORKFLOW §11.** $10 and $4 in the window: below the cost of the
  edits and the risk of losing a rule now.
- **A 1-hour cache lifetime for subagents.** Rejected in the pipeline v2 ADR. Bounded waits removed the re-writes it
  would have caught.

## Consequences
- With N1 (a) and N2 (a), the docs keep their files and § numbers. Agents read them in sections they can name, and a
  dangling § reference fails `verify` instead of waiting for the night audit.
- Root `CLAUDE.md` gets room under its budget again, and every runner command keeps a single source of truth in its
  own `--help`.
- Workflow agents carry one copy of root `CLAUDE.md`. A rule can still load twice (main's and the worktree's copy),
  the price of keeping the rules in a session started in a worktree.
- The launch prefix waits for #307. This design adds what it measured to #302's lever 5: the skill listing is 7.5k
  tokens in every general workflow agent, while implementers invoked a skill twice in 120 runs.
- `metrics` reports the instruction and doc cost per role. A later rise, such as a doc that grows back into a
  monolith or a new duplicate load, then shows up in the wave comments.
