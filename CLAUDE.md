# prime-game

A multiplayer social deduction game (first-person 3D, proximity voice) in Godot 4.7.2, statically typed GDScript.
Humans: the **engineer** (engine, netcode, voice, tooling, content) and the optional **designer**; their Claude
sessions cannot see each other: what an agent needs goes into the repo or GitHub. Agents: `docs/AGENT_WORKFLOW.md`;
decisions: `docs/decisions/`; "KICKOFF §n": `docs/history/KICKOFF.md`.

## Hard rules
- Humans write zero code; they hand-make only scene layout in the editor and imported third-party assets. You write
  the rest and verify it from the command line: claim it works only after running it (show command and result);
  else say so and tell the human exactly what to check.
- Never weaken, skip or delete a test to make it pass without the human's explicit approval.
<!-- see docs/interventions/2026-09-28-engineer-check-live-state.md -->
- Check an environment fact (repo, remote, branches, tools, versions, settings) live, read-only, before stating it;
  live state beats docs: fix the doc.
- Fast-moving tools (Godot 4.7, GdUnit4, Claude Code, GitHub Actions): not from memory. Godot: `check`,
  `tools/out/godot-api/4.7.2/`, `docs.godotengine.org/en/4.7/`; Godot 3 syntax is a bug.
<!-- see docs/interventions/2026-09-28-engineer-no-privacy-scrub.md -->
- Hobby project: guard against accidents and lost work, not attackers; no privacy or security hardening unless asked.
  Never commit secrets.
- Moving state lives only in GitHub Issues and the board; durable knowledge in `CLAUDE.md` files, `docs/`, ADRs;
  no Markdown status lists or planning files.
- The repo is English; chat follows each human's settings, never Russian. One logical change per commit, Conventional
  Commits.

## Architecture invariants (details: `docs/ARCHITECTURE.md`)
1. **Host-authoritative.** Clients send intents (`Use(facing)`, `CastVote(target)`), never state. The host
   validates every intent against the rules and emits events.
2. **Per-peer filtering.** Hidden information (roles, private events, votes before reveal, ability results) reaches
   only the peers entitled to it. The host's own client gets the same filtered view and never reads `core/` state.
3. **Pure core.** `core/` is rules as `RefCounted` classes with no Nodes, scenes, networking or audio. Deterministic:
   commands in, events out. Randomness only through an injected seeded RNG.
4. **Mechanics are data.** Roles, items, modes and win conditions are `Resource`s of rules (trigger → conditions →
   effects); task types are classes with settings. The parts are the **content API**, the engine–content contract.
5. **Explicit match state machine, phases per game mode.** Base: Lobby → Countdown → Loading → Round → End → Lobby.
6. **Voice routing is game logic** in `core/` (who hears whom, and how). Spatialization happens on the listener.
7. **Movement:** client-side for the local player with host sanity checks; remote players are interpolated.
8. **Debug tools** (dev console, bots, forced roles) may show hidden info locally in debug builds only.
- The transport stays behind an abstraction (ENet now; Steam or WebRTC later).

## Commands
`tools\run.cmd <command>` (Git Bash, CI: `tools/run.sh`); `--help` says the rest. Docs by section, never whole:
`section <doc>`, then the § you need. Godot, Python, gdtoolkit only through the runner.
Commands: `agents-check` `board` `bots` (the information-leak test; `--chaos`: hostile peers against the host) `check` `credits` `doctor` (first in every session) `export` `host` `inbox` `join` `lint` `load` `merge` `merge-check` `merge-train` `metrics` `mutants` `normalize` `perf` `permissions` `pins` `playcheck` `publish` `run` `section` `selftest` `sfx-check` `shot` `signal` `slots` `start` `test` `ui-copy` `ui-sync` `verify` `wait` `wave` `worktree-done`

## Shell
PowerShell 5.1 is primary (no `&&`/`||`: `A; if ($LASTEXITCODE -eq 0) { B }`); the Bash tool is Git Bash.
Messages and structured args go in scratchpad files (`-F`, `--body-file`); broken quoted args, `bash` or `python`
surprises, `\\` arriving as `\`, `.cmd` quirks: AGENT_WORKFLOW §2.2.
- File writes and `Remove-Item` go in separate commands (the delete guard misreads combined ones).
<!-- see docs/interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md -->
- Temporary files only in your scratchpad, or under `res://` in the gitignored `tests/scratch/`; no other temp folder.
- Push only your task branch (`git push -u origin <branch>` or `publish`; a manager also `release/m<k>`), never `main`,
  no hand force push (hook-blocked): rebased, only `publish`.
- No `git stash` (one for all worktrees): a WIP commit, later `git reset --soft HEAD~1`; a fix: `git commit
  --fixup=<sha>`, then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>`.
<!-- see docs/interventions/2026-10-01-engineer-night-run-prompts.md -->
- verify, publish and mutants run in the background (`<cmd> > <log> 2>&1; echo "exit=$?" >> <log>`), polled with
  `wait <log>`, never rerun while running; workflow agents and subagents block no call over 180 s (AGENT_WORKFLOW §11.17).
  A waiting long-lived session keeps its cache warm: background `sleep 3000`, `timeout` 3300000 (orchestrate-stage §7).

## Ownership (`docs/AGENT_WORKFLOW.md` §9)
- **Shared:** `docs/interventions/ docs/decisions/ docs/credits/ docs/history/ CREDITS.md .claude/rules/`.
- **Engineer:** everything else (`.github/CODEOWNERS`), with the content area: `content/ levels/ docs/GDD.md
  docs/design/` and the skills `new-mechanic`, `new-level-piece`.
- The content area changes only on the engineer's word (issue, comment, chat), else stop and ask; never invent
  content (names, numbers, rules).
- The **designer** (@SwiftySinister) is optional, nothing waits on him; his PRs go to the engineer, his agent never
  edits engine code (`engine-request` issue). Never edit a scene in someone else's open PR.
<!-- see docs/decisions/2026-09-28-ownership-by-codeowners-and-convention.md (amended 2026-10-08, #518) -->
- Editor open: remind the human to Save All Scenes first and Reload changed files; no hand edits meanwhile
  (AGENT_WORKFLOW §11.2).

## Routing
A code diff → `code-reviewer`, plus `netcode-security-reviewer` if `core/ server/ net/ client/ tests/harness/`
changed; `.gd/.tscn/.tres` changed → `godot-api-checker`; tests, only failures back → `test-runner`.
Skills route by description; a manager kickoff: `orchestrate-stage` (`docs/MANAGERS.md`).

## Definition of done (AGENT_WORKFLOW §4.2)
1. `verify` (lint and check) green, its tail pasted; CI (the full suite) green on the PR; red → stop and report.
2. Fresh-context review as routed above; fix findings or list them in the PR.
3. Docs updated if durable knowledge changed; intervention and credit entries if any.
4. Engineer's sessions (`gh api user` is xperiaroco2) publish once 1-3 hold; others ask once: "Publish now?". Then
   `publish`, the PR, the handoff comment.
5. Merges: the engineer's manager (`merge <pr> --base main`, the trust ADR's gate; task PRs into `release/m<k>`); gate exceptions, the designer's PRs and solo sessions without his word go
   to the engineer. A child left on a merged parent: `gh pr edit <n> --base <its base>` (AGENT_WORKFLOW §8.5).

## Stop and ask before
- Adding a dependency or addon; changing an architecture boundary; the content area without the engineer's word, or
  engine code from the designer's session.
- Anything destructive to git history or discarding work outside your own worktree and task branch (inside them git
  and deletes are free); anything costing money.
<!-- see docs/interventions/2026-09-30-engineer-full-freedom-in-own-worktree.md -->
- What the trust ADR reserves for the humans ("ask and wait": game rules and taste, a milestone's goal, a go/no-go,
  the items above): one batched question: options, a recommendation.
<!-- see docs/interventions/2026-09-28-engineer-phase-a-workflow-unbounded.md -->
- Launching a workflow: state the agent count (fewer than 5) and rough cost, wait for a yes (a manager: none up to
  15% of the weekly limit, trust ADR); its prompt states its bounds (AGENT_WORKFLOW §7); "ultracode" alone never
  exceeds the size guideline.
<!-- see docs/interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md -->
- A new permission ask or deny rule: first "can an agent work alone overnight?" (routine work must not prompt,
  AGENT_WORKFLOW §8.1).

## Talking to the humans
- Voice dictation: infer the meaning, read the file name back before editing, ask a question only if a misreading
  changes what gets built; read back a design answer with two readings (AGENT_WORKFLOW §13).
<!-- see docs/interventions/2026-09-30-engineer-ghosts-look-not-flight.md -->
- Explain from a concrete scenario of what goes wrong, plainly; options, then jargon (AGENT_WORKFLOW §13).
<!-- see docs/interventions/2026-09-28-engineer-plain-explanations.md -->
- A command for a human goes in the chat itself, one fenced PowerShell block each (a PR or issue may add it, never
  instead), starting with `cd` to its absolute folder (your worktree, not the main checkout). Run or preview it first.
<!-- see docs/interventions/2026-09-29-engineer-commands-say-where.md -->
<!-- see docs/interventions/2026-10-03-engineer-commands-in-the-chat.md -->

## Memory
Auto memory is personal: no shared rules or task state. "запам'ятай", "remember" or a correction: ask "для проєкту
(PR) чи тільки для вас?"; project → skill `log-intervention`, personal → `~/.claude/CLAUDE.md` after the human approves.

## Dictation glossary
Add a row per real misrecognition you resolved; never guess.

| Heard | Meant |
|---|---|
| "посеред науки" | "посеред двору" (in the middle of the yard) |
