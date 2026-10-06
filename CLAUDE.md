# prime-game

A multiplayer social deduction game (first-person 3D, proximity voice, player-hosted) in Godot 4.7.2 with
statically typed GDScript. Two humans, each with their own Claude session: the **engineer** (engine, netcode,
voice, tooling) and the **designer** (mechanics, content data, levels, GDD). The sessions cannot see each other:
everything another agent needs goes into the repo or GitHub. How agents work: `docs/AGENT_WORKFLOW.md`.
Decisions: `docs/decisions/`. Architecture and the content API: `docs/ARCHITECTURE.md`. The founding brief, which
"KICKOFF §n" refers to: `docs/history/KICKOFF.md` (superseded by these files; history only).

## Hard rules
- Humans write zero code; they hand-make only the designer's scene layout in the editor and imported third-party
  assets. You write everything else and verify it from the command line. Never claim something works unless you ran
  it; show the command and its result. If you cannot verify it, say so and tell the human exactly what to check and how.
- Never weaken, skip or delete a test to make it pass without the human's explicit approval.
<!-- see docs/interventions/2026-09-28-engineer-check-live-state.md -->
- Before stating a fact about the environment (repo, remote, branches, installed tools, versions, settings), check
  it live with a read-only command. Docs and archives describe the past: trust the live state over them and fix the doc.
- Do not trust memory for fast-moving tools (Godot 4.7, GdUnit4, Claude Code, GitHub Actions). For Godot use `check`,
  the API dump in `tools/out/godot-api/4.7.2/` and `docs.godotengine.org/en/4.7/`. Godot 3 syntax is a bug.
<!-- see docs/interventions/2026-09-28-engineer-no-privacy-scrub.md -->
- This is a hobby project: protections prevent accidents and lost work, not attackers. Add no privacy or security
  hardening (redaction, scrubbing, extra guards) unless a human asks. Never commit secrets (tokens, keys, passwords).
- Moving state (who does what, task status) lives only in GitHub Issues and the project board. Durable knowledge
  lives in `CLAUDE.md` files, `docs/` and ADRs. No status lists in Markdown, no framework planning files.
- The repo is English: code, comments, docs, commits, issues, PRs. Chat follows each human's settings; never Russian.
- Small, reviewable steps: one logical change per commit, Conventional Commits.

## Architecture invariants (details: `docs/ARCHITECTURE.md`)
1. **Host-authoritative.** Clients send intents (`Use(facing)`, `CastVote(target)`), never state. The host
   validates every intent against the rules and emits events.
2. **Per-peer filtering.** Hidden information (roles, private events, votes before reveal, ability results) reaches
   only the peers entitled to it. The host's own client gets the same filtered view and never reads `core/` state.
3. **Pure core.** `core/` is rules as `RefCounted` classes with no Nodes, scenes, networking or audio. Deterministic:
   commands in, events out. Randomness only through an injected seeded RNG.
4. **Mechanics are data.** Roles, items, modes and win conditions are `Resource`s of rules (trigger → conditions →
   effects); task types are classes with settings. The parts are the **content API**, the engineer–designer contract.
5. **Explicit match state machine, phases per game mode.** Base: Lobby → Countdown → Loading → Round → End → Lobby.
6. **Voice routing is game logic** in `core/` (who hears whom, and how). Spatialization happens on the listener.
7. **Movement:** client-side for the local player with host sanity checks; remote players are interpolated.
8. **Debug tools** (dev console, bots, forced roles) may show hidden info locally in debug builds only.
- The transport stays behind an abstraction (ENet now; Steam or WebRTC later).

## Commands
`tools\run.cmd <command>` (Git Bash and CI: `tools/run.sh <command>`); `<command> --help` says what it does and its options; read docs by section, never whole: `section <doc>` for the outline, then the § you need.
Godot, Python and gdtoolkit run only through the runner. Logs: `tools/out/logs/`; reports: `tools/out/gdunit/`.
Commands: `agents-check` `board` `bots` (the information-leak test; `--chaos`: hostile peers against the host) `check` `credits` `doctor` (first in every session) `host` `inbox` `join` `lint` `load` `merge` `merge-check` `merge-train` `metrics` `mutants` `normalize` `perf` `permissions` `pins` `playcheck` `publish` `run` `section` `selftest` `shot` `slots` `start` `test` `verify` `wait` `wave` `worktree-done`

## Shell
PowerShell 5.1 is the primary shell (no `&&` or `||`: `A; if ($LASTEXITCODE -eq 0) { B }`); the Bash tool is Git Bash.
- PowerShell 5.1 breaks quoted arguments containing spaces for native exes (`gh --jq '.a + " " + .b'`): use Bash.
- Multi-line commit messages, PR bodies and structured arguments go in scratchpad files (`-F`, `--body-file`).
- Keep file writes and `Remove-Item` in separate commands (the delete guard misreads combined ones).
<!-- see docs/interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md -->
- Temporary files go only to your scratchpad or, if they must be under `res://` (a probe test), to the gitignored
  `tests/scratch/`; deleting those never prompts. No other temporary folder in the project.
- `bash` on PATH is the WSL launcher, not Git Bash. In Git Bash `python` is a Store stub: use `$PYTHON_BIN`.
- In the Bash tool `\\` arrives as `\`, even in single quotes and heredocs: write such code to a file with Write.
- `.cmd` files are CRLF and never read `%ERRORLEVEL%` inside a `( )` block.
- A long-lived waiting session keeps its cache warm: background `sleep 3000`, `timeout` 3300000 (orchestrate-stage §7).
- Push an explicit task branch only (`git push -u origin <branch>`, or `publish`; a stage's manager also fast-forwards
  `release/m<k>`, DoD 5). Never `main`, no force push by hand (the pre-push hook blocks both): rebased, only `publish`.
- No `git stash` (one stash for all worktrees): set work aside with a WIP commit, later `git reset --soft HEAD~1`;
  fold a fix with `git commit --fixup=<sha>`, then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>`.
<!-- see docs/interventions/2026-10-01-engineer-night-run-prompts.md -->
- Every agent runs verify, publish and mutants in the background (a slot wait can reach 600 s): `<cmd> > <log> 2>&1;
  echo "exit=$?" >> <log>`, poll `wait <log>`, never rerun a running one. Workflow agents and subagents block no call over 240 s (5-minute cache; AGENT_WORKFLOW §11).

## Ownership (`docs/AGENT_WORKFLOW.md` §9)
- **Engineer:** `core/ server/ net/ client/ voice/ tools/ tests/ addons/ .github/ .claude/ project.godot CLAUDE.md`,
  `docs/ARCHITECTURE.md`, `docs/AGENT_WORKFLOW.md`, `docs/ROADMAP.md`.
- **Designer:** `content/ levels/ docs/GDD.md docs/design/` and the skills `new-mechanic` and `new-level-piece`.
- **Shared:** `docs/interventions/ docs/decisions/ docs/credits/ docs/history/ CREDITS.md .claude/rules/`.
- The designer's agent never edits engine code: a missing primitive becomes an `engine-request` issue with a precise
  spec. The engineer's agent never rebalances or redesigns content (`content/ levels/ docs/GDD.md docs/design/`)
  without the designer's approval in the PR or the engineer's word that the designer agreed: the PR then says "agreed
  with the designer, relayed by the engineer" and tags @SwiftySinister; a follow-up PR reverts an objection. Never edit
  a scene in someone else's open PR.
<!-- see docs/interventions/2026-10-01-engineer-relayed-design-agreement.md -->
- The Godot editor may be open. Remind the human: Save All Scenes (Ctrl+Shift+Alt+S) before asking the agent, no hand
  edits while it works; on "files changed on disk" Reload («Джерело отримання»), never «Ігнорувати зовнішні зміни».

## Routing
| When | Use |
|---|---|
| "start task 42" / "finish", "заверши задачу" | skill `start-task` / `finish-task` |
| "нова механіка: …" | skill `new-mechanic` |
| a room, prop or interactable sub-scene | skill `new-level-piece` |
| "запам'ятай", "remember", a human correction | the question in Memory below; project → skill `log-intervention` |
| "налаштуй мене" | skill `onboard` |
| "оркеструй етап", an "ultracode" kickoff for a stage or a list of issues | skill `orchestrate-stage` |
| "що нового?", the engineer's inbox (a secretary session) | skill `secretary` |
| review of a code diff | agent `code-reviewer`; plus `netcode-security-reviewer` if `core/ server/ net/ client/ tests/harness/` changed |
| `.gd`, `.tscn` or `.tres` changed | agent `godot-api-checker` |
| run tests and get back only failures | agent `test-runner` |

## Definition of done
1. `verify` is green; paste its tail. Red → stop and report.
2. Fresh-context review as routed above. Fix the findings or list them in the PR.
3. Docs updated if durable knowledge changed; intervention and credit entries added if any.
4. In the engineer's sessions (`gh api user` is xperiaroco2) publish once 1-3 hold; otherwise ask once: "Publish now?".
   Then `publish` (rebase; verify, unless an identical tree was just verified green; push), the PR from the template
   (linked issue, summary, verification output, screenshots for visual changes, docs updated yes/no) and the handoff
   comment: done, left, decisions, gotchas.
5. Merges: `merge <pr> --base main` (its gate: the trust ADR) by the engineer's manager, task PRs into `release/m<k>`;
   gate exceptions, the designer's PRs and solo sessions without the engineer's word go to a human. Merging a parent
   deletes its branch and GitHub retargets each child; a child still on it gets `gh pr edit <n> --base <its base>`.

## Stop and ask before
- Adding a dependency or addon; changing an architecture boundary; touching the other owner's area (see Ownership).
- Anything destructive to git history or that discards work outside your own worktree and task branch (inside them
  git and deletes are free: the guard asks only beyond them); anything that costs money.
<!-- see docs/interventions/2026-09-30-engineer-full-freedom-in-own-worktree.md -->
- Deciding anything reserved for the humans (the trust ADR's "ask and wait": game rules and taste, a milestone's
  goal, a go/no-go, the items above): batch such questions into one, with options and a recommendation.
<!-- see docs/interventions/2026-09-28-engineer-phase-a-workflow-unbounded.md -->
- Launching a workflow: state the agent count (fewer than 5) and a rough cost, then wait for a yes; a manager runs
  a stage's or track's workflows without one up to 15% of the weekly limit (the trust ADR), reporting the spend.
  Every workflow prompt states its bounds: max agents, max turns or tool calls per agent, a time or token budget,
  and what to drop first. "ultracode" alone never approves exceeding the size guideline.
<!-- see docs/interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md -->
- Adding a permission ask or deny rule: first check "can an agent work alone overnight?". Routine work (status reads,
  branches, commits, task-branch pushes, issues, PRs, tooling edits, scratch cleanup) must not prompt.

## Talking to the humans
- Humans often dictate by voice. Infer the meaning; read the file name back before editing; ask one short question
  only if a misreading would change what gets built. A design answer with two readings that build different things
  (the look or the mechanics) is read back in one sentence before an issue, an ADR or a design doc records it.
<!-- see docs/interventions/2026-09-30-engineer-ghosts-look-not-flight.md -->
- Explain a decision from a concrete scenario of what goes wrong (which person, agent and machine) in plain words;
  options next, jargon last. Before designing enforcement against a human behaviour, ask how the humans work.
<!-- see docs/interventions/2026-09-28-engineer-plain-explanations.md -->
- A command for a human goes in the chat itself, one fenced PowerShell block each (a PR or issue may add it, never
  instead), starting with `cd` to its absolute folder (your worktree, not the main checkout). Run or preview it first.
<!-- see docs/interventions/2026-09-29-engineer-commands-say-where.md -->
<!-- see docs/interventions/2026-10-03-engineer-commands-in-the-chat.md -->

## Memory
Auto memory is personal and machine-local: never put shared rules or task state there. On "запам'ятай" ask
"для проєкту (PR) чи тільки для вас?". Project → a `docs/interventions/` entry whose rule is promoted into these
files in the same PR. Personal → `~/.claude/CLAUDE.md`, after the human approves the edit.

## Dictation glossary
Add a row for each real misrecognition you had to resolve; never guess entries.

| Heard | Meant |
|---|---|
