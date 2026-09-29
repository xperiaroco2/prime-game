# KICKOFF — Project Bootstrap Brief for Claude Code

Read this whole file before doing anything. It is the founding brief for the project. After M0 (section 9) it is
superseded by `CLAUDE.md`, `docs/` and GitHub Issues, and should then be moved to `docs/history/KICKOFF.md`.

## 0. Who you are and the rules of this project

You are the implementer of this project. The humans are tech lead, product owner, reviewers and QA.
**Meta-constraint: the humans write zero code.** Every script, config, test, tool and document is written by an agent.
The humans steer, review diffs, playtest and report problems. The only hand-made artifacts allowed are:
spatial layout of scenes done by the designer in the Godot editor, and imported third-party assets.
Consequences:

- You must be able to verify your own work from the command line (tests, headless runs, bot matches, screenshots).
  If you cannot verify something yourself, say so explicitly and tell the human exactly what to check and how.
- Never weaken, skip or delete a test to make it pass without explicit human approval.
- Never claim something works unless you ran it. Show the command and its result.
- Prefer small, reviewable steps. One logical change per commit, Conventional Commits style.
- Do not trust your memory for fast-moving tools (Godot 4.7 APIs, Claude Code features, addons, GitHub Actions).
  Check current docs first. Godot 3 syntax is a bug.
- Stop and ask before: adding a dependency or addon, changing an architecture boundary, touching another owner's area,
  anything destructive to git history, or anything that costs money.

**Two humans, two Claude instances.** Each human works with their own Claude Code session:

- **Engineer (core owner):** game rules engine, networking, host logic, voice pipeline, tooling, CI, architecture.
- **Game designer (content owner):** mechanics design, roles/abilities/items/tasks as data, level design, balancing, GDD.

Neither Claude instance can see the other's session. **Coordination happens only through the repository and GitHub**
(issues, PRs, docs), so everything another agent needs must be written down there. Section 5 defines how.

### Communication conventions
- **Repository language is English:** code, comments, docs, commits, issues, PRs.
- **Chat language follows each human's personal config** (`~/.claude/CLAUDE.md`). The engineer chats in Ukrainian.
  Never reply in Russian.
- Humans often **dictate by voice**. Messages may contain speech-recognition errors, mixed languages or garbled
  technical terms. Infer the intended meaning. If a misreading would change what you build, confirm it in one short question.
- Humans work in the **Claude desktop app (Code tab)** on Windows and read code in **JetBrains Rider**.
  Keep the repo friendly to both: commit shared run configurations only if they are useful, and gitignore `.idea/`
  except for deliberately shared files.

## 1. Product vision

A multiplayer **social deduction game** in the spirit of Lockdown Protocol / Among Us, built in Godot.

- **First-person 3D, stylized low-poly.** Readable, cheap to produce, no texture-heavy art.
  CC0 asset packs and CSG greyboxing are fine. Record every third-party asset and its license in `CREDITS.md`.
- **Proximity voice chat is a core mechanic**, not a feature. Who hears whom is governed by game rules
  (distance, walls, death, meetings, items like radios, role abilities).
- **Player-hosted matches** (listen server): one player hosts, others join. Target 4–10 players.
- The differentiator is **a rich, varied set of mechanics**: roles, abilities, items, sabotages, task types, information tools.
  The mechanics set is designed by the humans (mainly the designer). Do not invent final game content unilaterally:
  propose options and let the humans pick.

## 2. Locked technical decisions

- **Engine:** Godot 4.7.x stable (standard build, not .NET). Pin the exact version in an ADR, in CI and in the task runner.
  The runner must fail fast with a clear message if the local Godot version does not match.
- **Language:** statically typed GDScript everywhere (typed vars, typed arrays, typed signal args, `class_name` where useful).
  Configure GDScript warnings so untyped declarations fail the `check` step.
- **Tests:** GdUnit4, runnable headless from CLI.
- **Lint/format:** gdtoolkit (`gdformat`, `gdlint`).
- **VCS/CI:** Git + GitHub, GitHub Actions running headless Godot: import, parse check, lint, unit tests, bot-match tests.
- **Networking:** Godot high-level multiplayer. Start with ENet. The transport must sit behind an abstraction,
  because we will later decide between Steam networking and WebRTC (with a signaling server) for NAT traversal.
- **Voice:** Opus-based. First candidate: the `two-voip-godot-4` GDExtension. **Risk:** its README has described the
  Windows build as incomplete. Windows is our primary platform, so the M1 spike must verify Windows binaries first,
  and compare fallbacks (e.g. `one-voip-godot-4`, Steam voice via GodotSteam, or uncompressed/lightly compressed PCM for the spike).
- **Dev environment:** native Windows is primary (the Godot editor, microphone and audio run natively). Do not assume WSL.
  Godot is a portable zip. The agent uses the `*_console.exe` build (it prints stdout/stderr); humans use the regular exe.
  All tooling must work on Windows; keep it cross-platform where cheap.
- **Git hygiene:** `.gitattributes` forces LF for text files (`*.gd`, `*.tscn`, `*.tres`, `*.godot`, `*.md`, `*.json`, `*.cfg`)
  and routes binary assets (`*.glb`, `*.png`, `*.wav`, `*.ogg`, and similar) through Git LFS.
  Ignore `.godot/`, `tools/out/`, `.idea/` (except shared files) and `.claude/settings.local.json`.
  Commit `*.uid` and `*.import` files.

## 3. Architecture principles (non-negotiable)

1. **Host-authoritative game state.** Clients send *intents* (e.g. `RequestKill(target)`, `CastVote(target)`), never state.
   The host validates every intent against the rules and emits events.
2. **Per-peer information filtering.** Hidden information (roles, private events, votes before reveal, ability results)
   is only ever sent to peers entitled to it. **The host's own local client receives the same filtered view as everyone else**
   and must never read `core` state directly. This prevents UI leaks and keeps a future dedicated-server mode trivial.
3. **Pure core.** `core/` contains game rules as plain GDScript classes (`RefCounted`), with zero dependency on Nodes,
   scenes, networking or audio. Deterministic: commands in → events out. Randomness goes through an injected seeded RNG.
   This is where most tests live.
4. **Data-driven, compositional mechanics.** Roles, abilities, items and task types are `Resource`s (`.tres`) composed from
   small reusable parts (trigger → condition → effect). Adding a mechanic should usually mean adding data plus at most one
   new effect class, not modifying the core loop. The set of available parts is the **content API** documented in
   `docs/ARCHITECTURE.md`. It is the contract between engineer and designer.
5. **Explicit match state machine:** Lobby → RoleAssign → Roam → Meeting → Vote → Resolution → (Roam | End).
6. **Voice routing is game logic.** The host decides, per speaker/listener pair, whether and how audio is delivered
   (proximity, occlusion, dead chat, meeting-global, radio). Routing rules live in `core/` and are unit-tested with
   synthetic audio frames. Spatialization happens on the receiving client via `AudioStreamPlayer3D` on the speaker's avatar.
7. **Movement:** client-side movement for the local player, with host-side sanity checks (speed, teleport);
   remote players are interpolated.
8. **Debuggability for solo testing.** A dev console and debug commands (spawn bots, force role, skip phase,
   show hidden info locally in debug builds only), so the designer can test a mechanic alone.

Suggested layout (refine it, but keep the boundaries):

```
core/        pure rules, state machine, voice routing rules, no Nodes
server/      host logic: wraps core, validates intents, filters state per peer
net/         transport abstraction, message schemas, serialization, sync
client/      scenes, player controller, UI, camera, audio playback, dev console
voice/       capture, encode/decode, jitter buffer, playback plumbing
content/     roles, abilities, items, tasks (Resources) — designer-owned
levels/      maps built from reusable room/prop/interactable sub-scenes — designer-owned
tools/       task runner, bot harness, launch scripts, screenshot capture
tests/       unit (core), integration (server+net), bot-match
docs/        GDD, architecture, roadmap, ADRs, workflow, interventions log
```

## 4. Self-verification toolkit (build this early, keep it green)

Create a single cross-platform task runner that works on Windows first (for example, one GDScript or Python entry point
with thin `.ps1` and `.sh` wrappers). Commands:

- `doctor` — checks the environment: Godot path and exact version, git, Git LFS, `gh` auth, gdtoolkit, addons present.
  Prints actionable fixes. Every new session can run it first.
- `test` — GdUnit4 headless unit and integration tests.
- `lint` — gdformat check + gdlint.
- `check` — headless import + script parse check, warnings policy enforced.
- `bots` — launch a headless host plus N headless bot clients that play a full scripted match, then assert invariants:
  the match terminates, the winner is correct, no errors are logged, and **no client ever received information it was not
  entitled to** (the information-leak test is the single most important test in the project).
- `shot` — run a non-headless instance of a given scene or state and save a PNG screenshot to `tools/out/`,
  so you can inspect UI and scenes yourself.
- `host` / `join` — launch a local host and clients for manual playtesting by the humans.
- `verify` — everything that CI runs, in the same order. The definition-of-done command.

Read the Godot binary path from the `GODOT_BIN` environment variable, falling back to `godot` on PATH.

**Test the tests.** Once the leak test exists, prove it works: temporarily inject a leak, confirm the test fails, revert.
Do the same once for CI (a deliberately failing commit on a throwaway branch must turn CI red).

## 5. Project memory, coordination and context hygiene

Context lives in the repo and on GitHub, not in any chat. The core rule that prevents the two Claudes from conflicting:
**durable knowledge lives in docs (changes rarely); moving state lives in GitHub Issues (changes constantly).**
Never keep "who is doing what right now" in a Markdown file that both people edit; that guarantees merge conflicts.

### 5.1 Source of truth for work state: GitHub Issues + a GitHub Project board
- Every unit of work is an issue. Use templates (`.github/ISSUE_TEMPLATE/`) for: `feature`, `mechanic` (designer-facing:
  intent, rules, edge cases, required engine primitives), `bug`, and `engine-request` (the designer asks the core owner for a
  new primitive or effect).
- Labels: `area:core`, `area:net`, `area:voice`, `area:content`, `area:level`, `area:tooling`, `blocked`, `needs-design`,
  `needs-engine`. Milestones mirror the roadmap (M0, M1, ...).
- Board columns: Backlog → Ready → In progress → In review → Done. Assign an issue to its human **before** starting work.
- Every session starts by reading its issue (`gh issue view <n>`) and ends by commenting a short handoff:
  what was done, what is left, decisions made, gotchas.
- Use the `gh` CLI for all of this. If `gh` is not authenticated, tell the human.

### 5.2 Durable docs (committed)
- `CLAUDE.md` (root) — short (≤150 lines): commands, hard rules, architecture boundaries, ownership map, workflow,
  definition of done. Shared by both humans' agents. Nested `CLAUDE.md` files hold area-specific rules:
  `core/`, `net/`, `voice/` (engineer-facing) and `content/`, `levels/` (designer-facing: how to author mechanics and maps
  without touching engine code).
- `docs/GDD.md` — game design, owned by the designer. Split into `docs/design/*.md` per system once it grows.
- `docs/ARCHITECTURE.md` — layers, protocol, filtering model, voice pipeline, and the **content API**: the list of engine
  primitives (triggers, conditions, effects, interactables, task stations) that designers compose. Owned by the engineer.
- `docs/AGENT_WORKFLOW.md` — how agents work here: session protocol, framework, subagents, hooks, permissions.
  Produced in Phase A, owned by the engineer, read by both agents.
- `docs/ROADMAP.md` — milestones and their goals only, with links to GitHub milestones. No task-level status here.
- `docs/decisions/YYYY-MM-DD-short-slug.md` — ADRs. Date-slug names, never sequential numbers, so two branches cannot
  collide on "ADR-0007".
- `docs/INTERVENTIONS.md` — append-only log of human interventions and the rule each one produced.
  To minimize conflicts, each entry is a single self-contained block appended at the end of the file.

### 5.3 Ownership and boundaries
- `.github/CODEOWNERS`: engineer owns `core/ server/ net/ voice/ tools/ tests/ .github/ CLAUDE.md docs/ARCHITECTURE.md`;
  designer owns `content/ levels/ docs/GDD.md docs/design/`. Placeholder GitHub handles until the humans provide them.
- The designer's agent **does not modify engine code**. If a mechanic needs a new primitive, it opens an `engine-request`
  issue with a precise spec, then continues with whatever it can do in data.
  The engineer's agent does not rebalance or redesign content without the designer's approval.
- **Scenes are single-owner.** Godot `.tscn` merges are painful. Levels are built from small sub-scenes (rooms, props,
  interactables), so two people rarely touch the same file. Never edit a scene someone else has an open PR on.

### 5.4 Branching and PRs
- Trunk-based: `main` is protected, always green. Short-lived branches `<area>/<issue>-<slug>`, one issue per branch.
- Every change lands via PR, with a PR template containing: linked issue, summary, how it was verified (commands + output),
  screenshots from `shot` for visual changes, and docs updated (yes/no).
- CI must pass. CODEOWNERS review is required when a PR touches the other person's area.
- Rebase on `main` before opening a PR; re-run tests after the rebase.
- For parallel work on one machine, prefer git worktrees over switching branches in place.

**Definition of done** for any task: lint clean, all tests green, bot match green (once it exists), docs updated if
durable knowledge changed, issue handoff comment written, PR opened.

## 6. Agent environment: subagents, skills, hooks, permissions

This is a starting proposal. Phase A (section 8) may change it after research and discussion.

In `.claude/agents/`:

- `godot-api-checker` — read-only; verifies code against Godot 4.x APIs and flags Godot 3 idioms. Cheaper model is fine.
- `test-runner` — runs test/lint/bots and returns only failures with minimal context. Cheaper model is fine.
- `code-reviewer` — read-only review of the current diff against CLAUDE.md and ARCHITECTURE.md. Strongest model.
- `netcode-security-reviewer` — read-only; hunts for information leaks, unvalidated client intents, and host-trust assumptions.

Set `model:` and a minimal `tools:` list in each frontmatter. Afterwards, verify that model routing actually takes effect.

In `.claude/settings.json` (shared, committed):
- A PostToolUse hook that runs `gdformat` and `gdlint` on edited `.gd` files.
- A permissions allowlist for routine, safe commands (the task runner, the Godot console exe, `git status/diff/log/add/commit`,
  read-only `gh` commands, gdtoolkit), so sessions are not interrupted by approval prompts for every run.
  Deny or require confirmation for: force-push, pushing to `main`, deleting branches, `rm -rf`-style deletes outside
  `tools/out/`, and editing `.github/workflows/` without mention in the plan.

In `.claude/settings.local.json` (personal, gitignored): machine-specific `env` such as `GODOT_BIN`. Claude Code applies
this `env` to its own tool calls, so the agent can configure its own environment without the human editing system
variables. The `doctor` command reads the same variables.

Shared project skills in `.claude/skills/` (committed, so both humans' agents get them):

- `new-mechanic` (designer-facing) — turns a mechanic idea into: a `mechanic` issue, a GDD section, content Resources built
  from existing primitives, a bot scenario that exercises it, and an `engine-request` issue for any missing primitive.
- `new-level-piece` (designer-facing) — how to build a room or interactable as a reusable sub-scene that follows the
  level conventions.
- `start-task` — read the issue, check the relevant docs, confirm the branch, restate the plan.
- `finish-task` — run the definition of done, write the handoff comment, open the PR with the template filled in.

Personal preferences (language of chat replies, verbosity, personal shortcuts) belong in each human's user-level
`~/.claude/CLAUDE.md` and `.claude/settings.local.json` (gitignored), never in the shared files.

Whatever framework Phase A selects (Superpowers, GSD or none), GitHub Issues, the durable docs and the ADRs remain the
source of truth for project state. A framework's own planning files must not become a second, competing source of truth.

## 7. Roadmap (draft — refine it in ROADMAP.md)

- **M0 — Agent setup + foundation.** Phase A (section 8), then repo structure, `.gitattributes`/LFS/`.gitignore`, CLAUDE.md files, docs skeletons, ADRs for the
  decisions above, tooling runner, GdUnit4, gdtoolkit, CI, CODEOWNERS, issue and PR templates, labels, subagents, skills,
  hooks. A trivial passing test in CI, plus an initial set of M1 issues on the board.
- **M1 — Risk spike (throwaway branch).** Host + 2 clients over ENet on one machine, first-person capsules walking in a
  greybox room, proximity voice via the Opus addon with 3D falloff. Measure latency and CPU cost; confirm the addon builds
  or ships for Windows first, then other target platforms. Output: an ADR with a go/no-go on the voice approach, plus lessons learned.
  This code is not merged as-is.
- **M2 — Core rules, headless.** Roles, tasks, meetings, voting, win conditions, voice-routing rules. Fully unit-tested, no visuals.
- **M3 — Networked match loop.** Lobby, role assignment, intent/event protocol, per-peer filtering, bot harness,
  information-leak tests.
- **M4 — First-person greybox.** Map, movement, interactions, tasks in 3D, host-side movement checks, interpolation.
- **M5 — Voice integrated with rules.** Proximity, occlusion, dead chat, meeting mode, push-to-talk / voice activity.
- **M6 — Playable vertical slice** with friends over the internet. NAT traversal ADR (Steam vs WebRTC) and implementation.
- **M7+ — Mechanics.** Co-designed roles, abilities, items and sabotages, one at a time, each with tests and a bot scenario.
  Then the low-poly art pass, audio, and polish.

## 8. Phase A — set yourself up (do this first, in this session)

Goal: before any project code, **build the working environment you yourself will be most productive in**, then agree
on it with the engineer. You are the one who will live in this repo, so design it for yourself: fast feedback,
small context footprint, clear rules, low friction. Treat it as a design review of your own workflow.

1. **Audit the machine.** Detect OS and shell, Godot binaries and exact version, git, Git LFS, `gh` and its auth status,
   Python and gdtoolkit availability, disk layout. Report what is missing. Install what you safely can
   (for example `pip install gdtoolkit`, GdUnit4 into `addons/`) and give exact commands for anything that needs the human
   (GUI installers, `gh auth login`, admin rights).
2. **Inject your environment.** Write machine-specific variables (e.g. `GODOT_BIN` pointing to the console exe) into
   `.claude/settings.local.json`. Verify that a fresh command actually sees them.
3. **Research current best practice.** Read the current Claude Code docs on memory/CLAUDE.md, subagents (including
   model routing), skills, hooks, permissions and settings. Also skim the current Superpowers and GSD docs and the available
   Godot MCP servers. Do not rely on memory: these tools change monthly.
4. **Propose your working model in `docs/AGENT_WORKFLOW.md`** and discuss it with the engineer. Cover at least:
   - Framework: Superpowers vs GSD vs plain plan mode with our own skills. Recommend one with trade-offs
     (discipline vs token cost). Do not install more than one.
   - The `CLAUDE.md` hierarchy: what goes in root vs nested files vs docs, how to stay under a lean line budget, and how
     rules get added (from `INTERVENTIONS.md` lessons).
   - The session protocol: how a session starts (`doctor`, read the issue, read the relevant docs), how it ends
     (`verify`, handoff comment, PR), and when to `/clear` or start a new session.
   - Subagents: final list, model per subagent, tool allowlists, and how you verified routing.
   - Hooks and permissions: exact allow/deny lists.
   - Whether a Godot MCP server adds enough over the CLI to justify it.
   - An effort policy: which kinds of tasks get the `ultracode` workflow mode, which get high, and which get medium
     (see section 10). Include how to keep workflow output reviewable.
   - How the designer's agent will work: which docs, skills and boundaries make it productive without engine code.
   - How the humans should phrase requests to you (for example issue templates, acceptance criteria, dictation tips).
5. **Wait for approval**, apply agreed changes, and record the key choices as ADRs.

## 9. Phase B — execute M0

1. Ask any remaining blocking questions (at most 5, batched): GitHub repo URL, both GitHub handles, and anything else.
2. Execute M0 as described in section 7. The GDD skeleton gets sections and open questions only, no invented content.
   Write the designer-facing CLAUDE.md files and skills so that someone who never touches engine code can be productive.
3. Prove it: run `doctor` and `verify` locally and show the output. Make sure CI config is valid; test the tests (section 4).
4. Create labels, milestones and the first M1 issues via `gh`. Open M0 as a PR (or commit directly to `main` if the repo is
   empty and branch protection is not set up yet; say which you did).
5. Move this file to `docs/history/KICKOFF.md` and make sure nothing important lives only here.
6. Finish with a short report: what was done, what the humans must set up manually on GitHub (branch protection,
   required reviews, LFS quota), open risks, and questions for the M1 spike.

## 10. Effort and orchestration policy (starting point)

The foundation matters most, so the foundation gets the most compute. Everything after it runs at normal effort.

- **`ultracode` workflows** (multi-agent, xhigh): for foundation work with no mid-task human input:
  Phase A research and the `AGENT_WORKFLOW.md` proposal, M0 execution after approval, the core architecture and
  content-API design before M2, and later project-wide audits (information leaks, netcode security, large refactors).
- **high**: everyday work in `core/`, `server/`, `net/`, `voice/`.
- **medium**: docs updates, content data, routine fixes, small tooling changes.

Rules for workflow runs:
- A workflow must **not** make decisions that section 0 reserves for humans. When it hits one, it records the options and
  its recommendation in the output and continues with the rest; it does not guess.
- Design before code: for architecture work, the first output is documents (options considered, an adversarial critique of
  the favored option, the decision proposal, ADR drafts), not implementation.
- Output must stay reviewable: split the result into focused commits or PRs with a summary of what each contains and how it
  was verified. A huge unreviewable diff counts as a failed run.
- Verification is a separate step done by a fresh agent (e.g. run `verify`, re-check claims against the docs),
  not self-grading by the agent that wrote the code.
