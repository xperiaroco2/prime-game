# prime-game

A multiplayer social deduction game (first-person 3D, proximity voice, player-hosted) in Godot 4.7.2 with
statically typed GDScript. Two humans, each with their own Claude session: the **engineer** (engine, netcode,
voice, tooling) and the **designer** (mechanics, content data, levels, GDD). The sessions cannot see each other:
everything another agent needs goes into the repo or GitHub. How agents work: `docs/AGENT_WORKFLOW.md`.
Decisions: `docs/decisions/`. Architecture and the content API: `docs/ARCHITECTURE.md`.

## Hard rules
- Humans write zero code. You write everything and verify it from the command line. Never claim something works
  unless you ran it; show the command and its result. If you cannot verify it, say so and tell the human exactly
  what to check and how.
- Never weaken, skip or delete a test to make it pass without the human's explicit approval.
<!-- see docs/interventions/2026-09-28-engineer-check-live-state.md -->
- Before stating a fact about the environment (repo, remote, branches, installed tools, versions, settings), check
  it live with a read-only command. Docs and archives describe the past: when they disagree with the live state,
  trust the live state and fix the doc.
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
1. **Host-authoritative.** Clients send intents (`RequestKill(target)`, `CastVote(target)`), never state. The host
   validates every intent against the rules and emits events.
2. **Per-peer filtering.** Hidden information (roles, private events, votes before reveal, ability results) reaches
   only the peers entitled to it. The host's own client gets the same filtered view and never reads `core/` state.
3. **Pure core.** `core/` is rules as `RefCounted` classes with no Nodes, scenes, networking or audio. Deterministic:
   commands in, events out. Randomness only through an injected seeded RNG.
4. **Mechanics are data.** Roles, abilities, items and task types are `Resource`s composed from trigger → condition
   → effect. The available parts are the **content API**, the contract between engineer and designer.
5. **Explicit match state machine:** Lobby → RoleAssign → Roam → Meeting → Vote → Resolution → (Roam | End).
6. **Voice routing is game logic** in `core/` (who hears whom, and how). Spatialization happens on the listener.
7. **Movement:** client-side for the local player with host sanity checks; remote players are interpolated.
8. **Debug tools** (dev console, bots, forced roles) may show hidden info locally in debug builds only.
- The transport stays behind an abstraction (ENet now; Steam or WebRTC later).

## Commands
Windows: `tools\run.cmd <command>`. Git Bash and CI: `tools/run.sh <command>`.

| Command | What it does |
|---|---|
| `doctor [--quick]` | Checks the environment and prints fixes. Run it first in every session |
| `lint [--fix] [files]` | gdformat and gdlint; with no files also CLAUDE.md budgets and rule/agent frontmatter |
| `check [res://paths]` | Headless import, warnings policy, UID lint, parse and load of every script and scene |
| `test [paths]` | GdUnit4 headless; judged by exit code and `results.xml`; orphan nodes fail |
| `verify` | Everything CI runs, in the same order: the definition-of-done gate |
| `start <n> [--include\|--stash] [--dry-run]` | Task branch `<area>/<n>-<slug>`, assign, board In progress (skill `start-task`) |
| `publish [--base B]` | Rebases the task branch on its PR base (else main), runs `verify`, pushes with a lease |
| `board move <issue> in-progress` or `in-review` | Puts an open issue on the project board in that column |
| `normalize <files>` / `shot <scene>` | Re-save `.tscn`/`.tres` as the editor would / an off-screen PNG of a scene |
| `credits` | Writes `CREDITS.md` from `docs/credits/`; `check` fails on an LFS asset without an entry |
| `agents-check` / `worktree-done <n>` | Subagents ran on their models / remove a merged task's worktree |
| `selftest` / `pins [--get X]` | The runner's own tests / pinned tool versions |

Godot, Python and gdtoolkit run only through the runner. Logs: `tools/out/logs/`; reports: `tools/out/gdunit/`.

## Shell
PowerShell 5.1 is the primary shell; the Bash tool is Git Bash.
- No `&&` or `||` in PowerShell: `A; if ($LASTEXITCODE -eq 0) { B }`.
- PowerShell 5.1 breaks quoted arguments containing spaces for native exes (`gh --jq '.a + " " + .b'`): use Bash.
- Multi-line commit messages and PR bodies go in a scratchpad file: `git commit -F <file>`,
  `gh pr create --body-file <file>`. Structured arguments go in files, not inline JSON.
- Keep file writes and `Remove-Item` in separate commands (the delete guard misreads combined ones).
- `bash` on PATH is the WSL launcher, not Git Bash. In Git Bash `python` is a Store stub: use `$PYTHON_BIN`.
- In the Bash tool `\\` arrives as `\`, even inside single quotes and quoted heredocs (`"\\r"` became a CR).
  Write code that contains backslashes to a file with the Write tool, then run the file.
- `.cmd` files are CRLF and never read `%ERRORLEVEL%` inside a `( )` block.
- Push an explicit task branch only: `git push -u origin <branch>`, or `publish`. Never `main`, never a force push
  by hand: the pre-push hook blocks both, and a rebased branch goes up only through `publish`.

## Ownership (`docs/AGENT_WORKFLOW.md` §9)
- **Engineer:** `core/ server/ net/ client/ voice/ tools/ tests/ addons/ .github/ .claude/ project.godot CLAUDE.md`,
  `docs/ARCHITECTURE.md`, `docs/AGENT_WORKFLOW.md`, `docs/ROADMAP.md`.
- **Designer:** `content/ levels/ docs/GDD.md docs/design/` and the skills `new-mechanic` and `new-level-piece`.
- **Shared:** `docs/interventions/ docs/decisions/ docs/credits/ docs/history/ CREDITS.md .claude/rules/`.
- The designer's agent never edits engine code: a missing primitive becomes an `engine-request` issue with a precise
  spec. The engineer's agent never rebalances or redesigns content without the designer's approval in the PR.
- Scenes are single-owner: never edit a scene someone else has an open PR on.
- The Godot editor may be open on this checkout. Remind the human: Save All Scenes (Ctrl+Shift+Alt+S) before asking
  the agent, no hand edits while it works, and on "files changed on disk" choose Reload («Джерело отримання»), never
  «Ігнорувати зовнішні зміни».

## Routing
| When | Use |
|---|---|
| "start task 42" | skill `start-task` |
| "finish", "заверши задачу" | skill `finish-task` |
| "нова механіка: …" | skill `new-mechanic` |
| a room, prop or interactable sub-scene | skill `new-level-piece` |
| "запам'ятай", "remember", a human correction | the question in Memory below; project → skill `log-intervention` |
| "налаштуй мене" | skill `onboard` |
| review of a code diff | agent `code-reviewer`; plus `netcode-security-reviewer` if `core/ server/ net/` changed |
| `.gd`, `.tscn` or `.tres` changed | agent `godot-api-checker` |
| run tests and get back only failures | agent `test-runner` |

## Definition of done
1. `verify` is green; paste its tail. Red → stop and report.
2. Fresh-context review as routed above. Fix the findings or list them in the PR.
3. Docs updated if durable knowledge changed; intervention and credit entries added if any.
4. Ask once: "Publish now?". Then `publish` (rebase, verify, push), open the PR from the template (linked issue,
   summary, verification commands and output, screenshots for visual changes, docs updated yes/no) and write the
   handoff comment on the issue: done, left, decisions, gotchas.
5. Only humans merge. Stacked PRs: after a parent PR merges, retarget each child with
   `gh pr edit <n> --base main` before its merge; GitHub does that itself only when the parent branch is deleted.

## Stop and ask before
- Adding a dependency or addon; changing an architecture boundary; touching the other owner's area.
- Anything destructive to git history or that discards work; anything that costs money.
- Deciding anything KICKOFF §0 reserves for humans: batch such questions into one, with options and a recommendation.
<!-- see docs/interventions/2026-09-28-engineer-phase-a-workflow-unbounded.md -->
- Launching a workflow: state the agent count (fewer than 5) and a rough cost, then wait for a yes. Every workflow
  prompt states its bounds: max agents, max turns or tool calls per agent, a time or token budget, and what to drop
  first. "ultracode" alone never approves exceeding the size guideline.
<!-- see docs/interventions/2026-09-28-engineer-unattended-hour.md -->
- Adding a permission ask or deny rule: first check "can the agent still work alone for an hour?". Routine work
  (status reads, branches, commits, task-branch pushes, issues, PRs, tooling edits) must not prompt.

## Talking to the humans
- Humans often dictate by voice. Infer the meaning; read the file name back before editing; ask one short question
  only if a misreading would change what gets built.
<!-- see docs/interventions/2026-09-28-engineer-plain-explanations.md -->
- Explain a decision from a concrete scenario of what goes wrong, in plain words, naming which person, which agent
  and which machine. Options come next, jargon last. Before designing enforcement against a human behaviour, ask
  how the humans actually work.

## Memory
Auto memory is personal and machine-local: never put shared rules or task state there. On "запам'ятай" ask
"для проєкту (PR) чи тільки для вас?". Project → a `docs/interventions/` entry whose rule is promoted into these
files in the same PR. Personal → `~/.claude/CLAUDE.md`, after the human approves the edit.

## Dictation glossary
Add a row for each real misrecognition you had to resolve; never guess entries.

| Heard | Meant |
|---|---|
