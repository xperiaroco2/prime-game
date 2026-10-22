# Agent Workflow

| | |
|---|---|
| **Status** | Decided 2026-09-28 (KICKOFF Phase A, step 5). Owned by the engineer, read by both agents. |
| Reasons | One ADR per significant decision in `docs/decisions/` |
| History | The founding brief: [`docs/history/KICKOFF.md`](history/KICKOFF.md) ("KICKOFF §n" in these docs). The Phase A proposal, research, reviews and metrics: `docs/history/2026-09-28-phase-a/` |

This file states **what we do**, not why. Markers: **[applied]** is in effect now; **[M0]** is built during M0;
**👤** is a step only a human can do.

---

## 1. Ground rules

- **Moving state lives in GitHub Issues** (and the board). Durable knowledge lives in `CLAUDE.md` files, `docs/` and
  ADRs. Nothing else holds task state: no framework planning files, no Markdown status lists.
- **No workflow framework.** Plain plan mode plus our own project skills (§6). No Superpowers, no GSD
  ([ADR](decisions/2026-09-28-no-workflow-framework.md)).
- **Proportionate protection.** This is a hobby project for the humans and their friends. Protections exist to stop
  accidents and lost work, not attackers. Do not add privacy or security hardening (redaction, scrubbing, extra
  guards) that nobody asked for. Secrets (tokens, keys, passwords) are still never committed.
- **The repo is English**: code, comments, docs, commits, issues, PRs. Chat follows each human's settings.
- **Humans write zero code** (KICKOFF §0). The agent verifies its own work from the command line and never claims
  something works without running it.

## 2. Environment

| Item | Decision | State |
|---|---|---|
| Surface | The Claude desktop app (Code tab), ≥ 2.1.281 on both machines. The `claude` on PATH is updated or removed 👤 so Rider cannot start an old build. `doctor` fails below 2.1.281 | 👤 / [M0] |
| Shell | PowerShell 5.1 is the agent's primary shell. No `&&`/`||`: chain with `; if ($LASTEXITCODE -eq 0) { … }`. Structured arguments go in files, not inline JSON | [M0] root `CLAUDE.md` |
| Machine paths | `GODOT_BIN`, `GODOT_GUI_BIN`, `PYTHON_BIN`, `GDTOOLKIT_DIR` in the `env` of each human's `~/.claude/settings.json`, so every session, worktree, hook and subagent sees them ([ADR](decisions/2026-09-28-machine-env-in-user-settings.md)). A human's own terminal needs no Windows variables for them: before any command the runner fills each one the process environment lacks from the `env` of the project's `.claude/settings.local.json`, then of `~/.claude/settings.json` (`$CLAUDE_CONFIG_DIR/settings.json` when that is set), and `tools\run.cmd` finds `PYTHON_BIN` there before Python starts. The process environment wins; `doctor` says where each came from and warns when none has it. The runner also puts `TEMP` and `TMP` in their long form when they hold an 8.3 short path (`C:\Users\XPERIA~1\...`, which the desktop app may give a shell while git and `Path.resolve` give `C:\Users\xperiaroco\...`), and so does the runner tests' package for a bare `python -m unittest`; `doctor` warns about the short one, whose fix is the long path in that `env` (#542) | [applied] engineer |
| Personal settings | Each human's `~/.claude/settings.json` holds `"language"` and `"permissions": {"defaultMode": "acceptEdits"}`. Personal rules go in `~/.claude/CLAUDE.md`. Nothing personal in shared files | [applied] engineer |
| `.claude/settings.local.json` | Personal permission approvals, plus in the main checkout on Windows the `claudeMdExcludes` patterns that the full `doctor` adds (§3 "Which copy loads", #385, #406); gitignored and untracked | [applied] |
| Godot import scope | `docs/.gdignore` keeps the editor from importing anything under `docs/` | [applied] |
| Auto mode | Not yet. Revisit after the M0 guard tests pass (§14) | — |

### 2.1 Cloud sessions
A Claude Code cloud session (claude.ai/code, a Linux container with a fresh clone) runs `tools/run.sh verify` as CI
does (#159, #345). **First command of every cloud session:** `tools/cloud/setup.sh`, then `tools/run.sh doctor`.
- **`tools/cloud/setup.sh`** (from any folder; idempotent): installs
  the pinned Godot Linux build in `~/godot/godot` (SHA-512 checked) and links it as `godot` on PATH, installs the pinned
  gdtoolkit with pip, the pinned Node.js in `~/node` (SHA-256 checked; the runner takes it there in a cloud session,
  since the image's own Node 22 comes first on PATH and Claude Code runs on it; #368), and raises
  `net.core.rmem_default` to 416 KB when lower (some container kernels hold only 256
  small datagrams in the 208 KB default; verify's stall step queues 320). **In a cloud session only**
  (`CLAUDE_CODE_REMOTE=true`) it also leaves the Windows-only TwoVoIP extension (`addons/twovoip/twovoip.gdextension`
  and its `.uid`, the M5 voice ADR §2) out of the clone with a non-cone sparse checkout, as CI deletes them: on Linux
  Godot prints an `ERROR:` line for the extension and every Godot step of `verify` fails. git still tracks both files,
  so `git status` stays clean and no commit can take their deletion; the sparse patterns hold through a switch,
  `reset --hard` and a new worktree (`git update-index --skip-worktree` alone did not). Undo with
  `git sparse-checkout disable`. If Godot imported the project before, a
  `run` still loads the extension until the next `check` (ARCHITECTURE §6.5.2 The addon in the repo); `verify` runs
  `check` first. `doctor` (also `--quick`, so `verify` stops at once) fails in a cloud session while the `.gdextension`
  is in the working tree or was deleted by hand, and names the fix; it skips the machine paths and `gh` there, as on CI.
  The webrtc-native extension (`addons/webrtc_native/`, the M6 ADR's E57, #367) is not left out: it ships a Linux
  x86_64 library, which loads headless, so a cloud session runs `check` and the WebRTC tests with it, as CI does.
- **Why first, and again:** an environment's cached setup may not carry the sparse checkout or the sysctl into a new
  session, and the sysctl can fall back to 212992 within one (#346: `verify`'s `freeze` and `stall` failed until
  `setup.sh` ran again): rerun it whenever `doctor` warns.
- **Python:** the image's `python3` is 3.11, the runner's minimum (`pins.PYTHON_MIN`; 3.10, 3.12 and 3.13 are
  installed too), while CI's `verify` runs 3.12; #345 fixed three 3.12-only spots that broke `verify` and `selftest` on
  3.11, and since #349 CI's job `python-min` keeps the minimum true.
- **Network access:** `github.com` with `release-assets.githubusercontent.com`
  for the Godot zip, `pypi.org` with `files.pythonhosted.org` for gdtoolkit; `nodejs.org` for Node (#368). The
  session's proxy refuses API calls and feeds of other GitHub repositories ("sessions are bound to their configured repositories"); the WebFetch tool still
  reads public pages (docs, release pages) for research.
- **GitHub:** `gh auth status` calls the token invalid, yet `gh api` REST calls on this repository go through the
  session's GitHub proxy (`gh api user`, `gh api repos/{owner}/{repo}/issues/<n>`). GraphQL is refused (HTTP 403), so
  `gh issue view`, `gh pr create|view|checks` and `gh project` fail, and with them the runner's `start`, `board` and
  `merge`. Read issues and open PRs with the session's GitHub tools, leave the board column to the manager, and push
  with `publish --base <base>` (it needs no `gh` when given the base) or a plain `git push -u origin <branch>` after
  a green `verify`.
- **Task branches**: the container starts on its own branch; switch to the task branch from its base
  (`git fetch origin <base>; git switch -c <area>/<n>-<slug> origin/<base>`, then `git branch --unset-upstream`, so
  nothing tracks the base). On its task branch the clone is the session's own worktree for the guard (#381, §8.2.1):
  `reset`, `rebase`, `checkout -- <path>` and `clean` there pass without a prompt, which nobody would answer. Before
  #381 the M6-3 session waited 30 minutes on `git reset --soft HEAD~2`. On `main` or `release/*` they still ask.
- **Agents:** the subagents in `.claude/agents/` run there (`agents-check` works on their transcripts). The Workflow
  tool is offered, under the `small` size guideline.
- **Cannot**: open Godot windows (`run` without `--headless`, the editor), take a `shot` or run `playcheck` (they
  stop with "needs a desktop session with a GPU"), or do the Windows-only steps (`tools\run.cmd`, PowerShell, the
  humans' settings files, the TwoVoIP round trip).

### 2.2 Shell notes for agents
Known shell failures on this machine, moved out of root `CLAUDE.md` (#561), whose Shell section keeps the rules that
prevent prompts and lost work and names these symptoms with a pointer here:
- PowerShell 5.1 breaks quoted arguments containing spaces for native exes (`gh --jq '.a + " " + .b'`): use Bash.
- `bash` on PATH is the WSL launcher, not Git Bash (§11.15). In Git Bash `python` is a Store stub: use `$PYTHON_BIN`.
- In the Bash tool `\\` arrives as `\`, even in single quotes and heredocs: write such code to a file with Write.
- `.cmd` files are CRLF and never read `%ERRORLEVEL%` inside a `( )` block.

## 3. Instruction files and memory

| File | Loaded | Content | Budget |
|---|---|---|---|
| Root `CLAUDE.md` (engineer-owned) | Always; re-injected after compaction (which copy: "Which copy loads" below) | Hard rules, **architecture invariants**, the runner command names (each command's `--help` says the rest), the shell rules that prevent prompts and lost work (the quirks: §2.2), ownership, review routing (skills route by their descriptions), definition of done, stop-and-ask list, a pointer to `docs/HUMAN_SESSIONS.md` (talking to the humans, memory, the dictation glossary: a chat with a human reads it, no workflow agent needs it, #836); each rule in short with a pointer to the section that has the detail (#561) | ≤ 150 lines and 9,216 bytes loaded, counting unscoped rule files |
| `core/ server/ net/ client/ voice/` `CLAUDE.md` | When a file there is read | Engineer area rules | ≤ 100 lines and 10,240 bytes each (`NESTED_BYTES`, #1242) |
| `content/ levels/` `CLAUDE.md` (engineer-owned, the content area) | Same | How to author mechanics and maps without engine code | ≤ 100 lines and 10,240 bytes each |
| `.claude/rules/*.md` with `paths:` | When a matching file is touched | `gdscript.md`, `tests.md`, `godot-resources.md`, `workflow-scripts.md` | ≤ 60 lines each |
| `docs/HUMAN_SESSIONS.md` | Read by a chat with a human (task session, manager, secretary, meta) before its first reply and again after a compaction, by root's pointer; no workflow agent reads it (#836) | Talking to the humans, launching a workflow, memory, the dictation glossary | none (not loaded at launch) |
| `docs/*.md` | Only when read | Architecture (with the **content API**), GDD, roadmap, ADRs. Linked, never `@imported` | none |

- Invariants live in root because nested files drop out after compaction
  ([ADR](decisions/2026-09-29-instruction-files-and-budgets.md)).
- **Which copy loads** (Claude Code 2.1.284, probed in #336). A session started in the main checkout (the manager,
  its workflow agents, and a task session that works in a worktree through `cd`/`Set-Location`, §4.1) loads main's
  root `CLAUDE.md` at launch. A Read of a file under `.claude/worktrees/<n>/` then also loads that worktree's root
  `CLAUDE.md` (a second copy), its area `CLAUDE.md`, and both main's and the worktree's copy of each matching rule. A
  session started inside a worktree loads only the worktree's copies: its root `CLAUDE.md` at launch, never main's,
  and its area files and rules by path. So `claudeMdExcludes` with `**/.claude/worktrees/*/CLAUDE.md` in the tracked
  `.claude/settings.json` is wrong: the tracked file is also each worktree's own settings, and in a session started
  inside a worktree the pattern matches the only root `CLAUDE.md` it has.
- **[applied] The exclude lives in the main checkout's `.claude/settings.local.json`** (#385, the engineer's option
  (a) on PR #360). On Windows Claude Code reads the local settings file of the folder a session starts in
  (code.claude.com/docs/en/settings, "Where Claude Code keeps the local file"; elsewhere a worktree session uses the
  main checkout's file instead), so the exclude there keeps a worktree root `CLAUDE.md` out of a main-started session
  and leaves a worktree session its own (#385's probes).
  `tools\run.cmd doctor` (the full one; `onboard` runs it) adds the pattern to that file, merged into what is there
  (never to a file under `.claude/worktrees/`, should git fail to name the main checkout); `doctor --quick` (and so `verify`) only warns when it is missing. Neither touches it in CI or off Windows, where
  it would take a worktree session's only root `CLAUDE.md`. So a workflow agent reads a worktree's root `CLAUDE.md`
  only by Read.
- **[applied] The rules too (#406).** The same file also gets `**/.claude/worktrees/*/.claude/rules/**`, through the
  same `doctor` code; without it a main-started agent that Reads worktree files loads main's and the worktree's copy
  of each matching rule (#406's probes). With it, such an agent loads main's copy of each rule once (main's
  `tests/**` rule matches a worktree's `tests/` file) and no worktree copy. So a main-started agent follows main's
  rules: a task branch's own edit of a rule, or a rule it adds, reaches that agent only by Read (a task that changes a
  rule says so in its prompt). `godot-resources.md` names `**/project.godot` rather than `project.godot` on purpose,
  so that main's copy also matches a worktree's (not probed, #406's review).
- **[applied]** All files in this table exist (M0 stage 3). `tools\run.cmd lint` (part of `verify`) fails over
  budget. It counts the lines Claude Code loads: frontmatter and block-level HTML comments are left out, so the
  `<!-- see docs/interventions/… -->` notes are free. Since #561 it counts their bytes too (`ROOT_BYTES` and
  `SKILL_BYTES` in `tools/runner/instructions.py`): the launch-time files at most 9,216 (every agent carries them on
  every call; root `CLAUDE.md` has little room left, so a rule added there trims another rule into its
  doc in the same PR), and each `SKILL.md` body at most 16,000 (an invocation injects it whole and a compaction re-attaches
  only its first 5,000 tokens, code.claude.com/docs/en/skills); a skill's detail goes into supporting files in its
  folder, read on demand (`orchestrate-stage`'s core names the file for each event, §6). It also fails on rule
  frontmatter that would not parse (Claude Code would then load the rule at every launch). The same PR then scopes a
  rule to paths, moves it into a skill, or retires it, and the intervention entry says which.
- **[applied]** Root's commands section is the runner line and one line of command names, no table (#340; N2 (a) of
  the instruction-diet ADR, PR #325): each command's `--help` (its `description` in `tools/runner/cli.py`) carries what
  its table row said. A new command adds its name in alphabetical order and a description; a note on the names line
  only where nothing else always loaded says it (`bots` is the information-leak test). The runner test
  `tools/runner/tests/test_cli_help.py` fails a name missing on either side, a command without a description, or a
  fact of an old row gone from its `--help`.
- **Docs by section [applied]** (the instruction-diet ADR's N1 (a), #325; #338): `tools\run.cmd section <doc>` prints a
  doc's outline (§, title, line range, tokens), `section <doc> <§>...` exactly those sections. § numbers stay stable: a
  section is never renumbered or moved, since code comments and issues name them. `lint` fails a duplicate § in a doc, a
  heading without a § under a numbered one in ARCHITECTURE or AGENT_WORKFLOW (a new heading takes the next free number
  under its parent), and a § reference to those two that resolves to no heading; the doc a § belongs to is the one named
  with it (scope rules: `tools/runner/refs.py`), and a § with no doc in scope is only counted (`section --refs` lists
  those). Root's runner line says to read docs by section, never whole (#339), and the workflow prompts (§7.1) name
  sections: the reviewers and the plan's critique read the ARCHITECTURE sections the change touches (a design's: the
  outline, then every section it could contradict), the netcode reviewers (the `second_review` pass too, which audits
  the leak test) always read ARCHITECTURE §5, §4.2 and §4.6 (a change to its §4.7 alone can still add a snapshot field
  the leak test does not compare), and no prompt asks for root `CLAUDE.md`, which every agent has from its launch. The
  agent files of `code-reviewer` and `netcode-security-reviewer` say the same for a review launched by hand, and allow
  `section` as their one read-only runner command besides the netcode reviewer's `bots` (#433; `test_agent_files.py`).
  The implementer's default reading list names no area `CLAUDE.md` file and no rule: those load by path when it Reads a
  file there, as it does before every Edit (a `cat` loads none). Code too since #468: `section <file>` outlines a .py,
  .gd or .js file and `section <file> <symbol>` prints one symbol; the workflows' reading line and `metrics`' code-read
  table go with it. The task's ADR since #815: every agent of `issue-task.js` and `pr-rebase.js` (the publisher and the
  read-only ones too) has one line of the shared rules: read each section of the ADR once per context, and again only
  after the file changed or a compaction (PR #794's `metrics --adr-reads` table: about 960 of 976 section reads of ADRs in
  three days were repeats of the same task ADRs). Since #816 the same line says to read it by section, never whole
  (`section <adr>`, then `section <adr> <§>`): the table's 39 whole-file reads of the 2026-10-10 task ADRs cost $9.32
  of $33. Since #834 the line covers ARCHITECTURE too, named through its `section` call (about $20 over 1471 tool
  reads since 2026-10-08T12:25Z, 51% the implementer's, had been left out); `metrics --adr-reads` counts its repeats.
- **Auto memory stays on.** It is personal and machine-local, and never holds shared rules or task state. "Запам'ятай / remember" gets one question
  back: *для проєкту (PR) чи тільки для вас?* Project → `/log-intervention`; personal → `~/.claude/CLAUDE.md` after
  the human approves the edit.

## 4. Session protocol

### 4.1 Start: "start task 42" / `/start-task 42`
1. `tools\run.cmd doctor --quick`. Red blocks the task, with a plain-language fix. (No SessionStart hook.)
2. `gh issue view 42`; read the linked docs and the area's `CLAUDE.md`.
3. If the task touches the other owner's area, stop and ask (§9). If another human has an open PR on a scene the task
   edits, stop (KICKOFF §5.3).
4. `tools\run.cmd start 42` **[applied]**: creates `<area>/<issue>-<slug>` from `origin/main` with no upstream (the area
   from the issue's single `area:*` label, else `--area`), or resumes the issue's existing branch; assigns the issue if
   unassigned; moves the board item to **In progress**. Uncommitted changes stop it with the list: `--include` carries
   them onto the task branch, `--stash` stashes them; it never discards. `--dry-run` only fetches. A task stacked on an
   open PR starts with `--base <parent>`: the branch comes from `origin/<parent>` (refused when origin lacks it), and
   `start` records the parent in the machine-local git config key `branch.<task>.primeBase` (its tip in `primeBaseTip`),
   where `publish` and `finish-task` find it before the PR exists (§8.3); resuming an existing branch ignores `--base`
   and says so. **For the engineer it creates a worktree `.claude/worktrees/<n>` for every task** (issue #51): there
   the agent works freely (§8.2.1), and the main checkout, where the Godot editor and the humans' files live, stays
   protected. `--here` is the exception that keeps the task in this checkout, and so do `--stash` and `--include`
   (they act on this checkout's changes) and a branch already checked out here. The designer never gets a worktree:
   with another Claude session active on this checkout, `start` stops rather than switch the branch under that
   session (`--here` when the human says it is idle). Work in the worktree: a session opened in that folder, or,
   for a task session whose shell starts in the main checkout, `cd <worktree> && ...` (Git Bash) or
   `Set-Location <worktree>; ...` (PowerShell) at the start of every command. `tools\run.cmd worktree-done <n>`
   removes the worktree, and its own `user://` folder (§11.18), once its branch is merged
   ([ADR](decisions/2026-09-28-worktrees-only-for-parallel-sessions.md)); `--pushed` also removes one whose branch is
   never merged (a spike) once `origin/<branch>` holds all its commits, and keeps that local branch. Run it from the
   main checkout: Windows cannot delete a folder a process sits in, so it refuses when the current folder is inside the
   worktree or any live Claude session (even one idle for days, or the calling one) has it as its folder; archive that
   session in the app first. A rerun finishes a half-done removal (an empty leftover folder, the issue's merged local
   branch).
5. Restate goal, acceptance criteria, plan, verification commands and risks. Non-trivial work: plan mode, wait for "go".

### 4.2 Finish: "finish" / `/finish-task` (definition of done)
1. `tools\run.cmd verify --changed` (an agent's run: its lint checks only the changed GDScript, §11.16); paste
   the tail. Red → stop and report. Never weaken a test. A plain `verify` runs only
   `doctor --quick`, `lint` and `check` (no test, no verify slot); every test, the bot matches included, runs on CI's
   `verify --full`, so CI green on the PR is the test gate (#605,
   [ADR](decisions/2026-10-09-tests-on-ci-local-lint-and-check.md)); `verify --full` runs the whole suite here when
   needed (§11.16). Every agent runs it in the background and polls it with `wait <log>`
   (since #388 a slot wait alone can reach 600 s, where a foreground call is killed; `finish-task` step 1, #406); a
   workflow agent or subagent (a 5-minute prompt cache) in calls of at most 180 s (§11.17, "Bounded waits").
   **A design-only diff** (#1123: every changed path on `.github/design-only-paths.txt`, the Markdown design docs
   `docs/GDD.md`, `COMPASS.md`, `m8-match.md`, `docs/design/ideas/`, `docs/design/research/`; never `house-map.md`,
   which the level tests read): its `verify` runs `doctor` and `lint` (the § references) without `check`, and CI
   skips the Godot parts of `verify --full` (the required `verify` passes on their `skipped`, `runner on the minimum
   Python` lints it); `runner on the minimum Python` took 38 s in the last PR run, the `changes` job is not yet
   timed. Any other path in the diff runs everything.
2. Fresh-context review (none for a design-only diff, step 1, #1123): `code-reviewer` for code diffs (bundled `/code-review` at medium, or none, for docs-only and
   content-data diffs); plus `netcode-security-reviewer` if `core/`, `server/`, `net/`, `voice/`, `client/` (what it
   renders can leak) or `tests/harness/` (the information-leak test) changed (the workflows leave out a diff whose only
   such paths are under `client/ui/`, the screens: §7.1, #606); plus
   `godot-api-checker` if `.gd`, `.tscn` or `.tres` changed. Fix findings or list them in the PR.
3. Update docs if durable knowledge changed; add intervention and credit entries if any.
4. In the engineer's sessions (`gh api user` is the engineer's account, the `*` owner in `.github/CODEOWNERS`) no
   question: publish once 1 to 3 hold ([trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)).
   In the designer's sessions, or when unsure, one question: **"Publish now? (push + PR + handoff comment)"**.
5. `tools\run.cmd publish`, in the background with `wait <log>` like `verify`: rebase on the open PR's base (else the
   `start --base` parent, else `origin/main`); verify, unless an identical tree was just verified green (the newest
   verify record passed at the same head, tree and runner, with a clean tree then and now, under 2 hours ago: it says
   so and pushes on that record, #471); push the task branch with a lease (§8.3). A red verify pushes nothing, so after
   review fixes the tests they touch and `check` come before `publish`, with no standalone `verify`: the publishing
   agents of `issue-task` and `pr-rebase` (§7.1) and `finish-task` step 2 work this way. A rebase that moves the
   branch changes its head, so `publish` verifies it as always; CI runs the full verify before any merge.
6. Open the PR from the template: `Closes #42`, summary, verification commands and output, `shot` screenshots for
   visual changes, docs updated yes/no, `--reviewer <other human>` if the other owner's paths are touched.
7. Handoff comment on the issue (done / left / decisions / gotchas); board item → **In review** via the runner.

### 4.3 Context hygiene
- One issue per session; a new issue starts a new session.
- `/clear` between unrelated tasks, after two failed corrections on the same point, and after a plan is approved
  when the plan is enough to implement from.
- After compaction, re-read the area `CLAUDE.md` before editing.

## 5. Subagents and models

Files in `.claude/agents/` **[applied]**. Six are read-only: no Edit, Write or NotebookEdit, `disallowedTools`
includes `Agent`, no `memory:` field. The three lean writers are the exception: `task-implementer` and
`task-publisher` ([ADR](decisions/2026-10-04-lean-workflow-agent-types.md), #332), which only `issue-task`,
`pr-rebase` (always since #458) and `quick-task` (only `task-publisher`) use (§7.1), and `lean-writer`
([ADR](decisions/2026-10-06-lean-reader-and-writer-types.md), #466) for the other workflows. Each lean type (the
writers and `lean-reader`) keeps to its `tools:` allowlist, disallows Skill, NotebookEdit and Agent, sets no
`effort:` and no `skills:` preload, and names in its body only `docs/` and `.claude/` paths that exist (#557). No agent
file sets `permissionMode`, so every subagent runs in the session's mode;
`tools/runner/instructions.py` (`lint`) enforces all of it. Their shell use is limited by the shared permission
rules.

| Agent | Job | Model |
|---|---|---|
| `godot-api-checker` | Check changes against the pinned Godot 4.7.2 API; flag Godot 3 idioms. Sources: `check`, the engine API dump, `docs.godotengine.org/en/4.7/` only | `sonnet`, effort high |
| `test-runner` | Run test / lint / check / bots via the runner; return only failures | `haiku` |
| `code-reviewer` | Review the branch diff against `CLAUDE.md`, the ARCHITECTURE sections it touches (`section`) and the content API | `opus`, effort high |
| `netcode-security-reviewer` | Information leaks, unvalidated intents, host-trust assumptions; always reads ARCHITECTURE §5, §4.2 and §4.6 | `opus`, effort high |
| `night-skeptic` | Re-check the night audit's candidates against the repo and GitHub runs: CONFIRMED, REFUTED or UNSURE each (§15) | `opus`, effort high |
| `task-implementer` | Always (#458): the implementer, the plan agent and the test reviewer of `issue-task`, in the task worktree, with a lean tool set (no Skill tool: it reads a skill's `SKILL.md`, and for a workflow script `docs/workflow-scripts.md`, #557) | `opus`, effort from the workflow's role |
| `task-publisher` | Always (#458): the publisher of `issue-task`, the rebase and fix agents of `pr-rebase`, and `quick-task`'s builder and fixer; the implementer's tools plus SendUserFile | `opus`, effort from the workflow's role |
| `lean-reader` | Workflows other than `issue-task` and `pr-rebase`: finders, gatherers, scouts, lenses, skeptics and verifiers that read and report (below); Read, Grep, Glob, Bash, PowerShell, WebFetch, WebSearch | `sonnet` (a skeptic's call passes `opus`), effort from the call or the session |
| `lean-writer` | Workflows other than `issue-task` and `pr-rebase`: the agents that write files (a synthesis, issue or comment bodies); the reader's tools plus Edit and Write | `opus` (or the call's model), effort from the call or the session |

- **Agent types in other workflows [applied]** (the night audit run as a workflow, the meta track's weekly report,
  ad hoc research, audits and scouting; [ADR](decisions/2026-10-06-lean-reader-and-writer-types.md), #466). Every
  `agent()` call of such a script passes `agentType`, so it starts at about 21k tokens instead of about 57k:
  - finders, gatherers, scouts and lenses that read and report: `{agentType: 'lean-reader'}`, on Sonnet by the
    file;
  - skeptics and verifiers keep their model: `{agentType: 'lean-reader', model: 'opus'}`; the night audit's skeptic
    stays `night-skeptic`;
  - the agents that write the final issue, comment, report or synthesis keep their model: `{agentType:
    'lean-writer'}` (Opus), or with the model they had (`model: 'sonnet'` for the night audit's filing step);
  - an agent that needs a tool outside both lists (Monitor for a long job, the Skill tool) stays
    `workflow-subagent`, and its prompt says why. Lean agents have no Skill tool: a prompt that names a skill tells
    the agent to read its `SKILL.md`;
  - `agents-check` judges these agents by the call's `model`, else the type's `model:`.

- **Model guard [applied]:** `"availableModels": ["opus", "sonnet", "haiku"]` in the shared settings. A request for
  another model falls back with a warning. Fable appears in no shared file
  ([ADR](decisions/2026-09-28-model-guard-no-fable-in-shared-config.md)). Its amendment A (the engineer's answer N1
  (b), 2026-10-02): the engineer may add Fable to `availableModels` in his own `~/.claude/settings.json` (the lists
  merge across non-managed scopes), and a manager passes it per launch through a workflow's `models` argument, only
  where the kickoff allows it (stage designs, second reviews of PRs that touch `core/ server/ net/ tests/harness/`,
  audits, a task red twice), within at most half of its weekly window across tracks, reported per wave. It stays out
  of `.claude/`, `.github/`, every CLAUDE.md and every workflow default (`test_agents_check.py` and
  `test_workflows.py` assert it). 👤 Both humans keep **usage credits off** or set a spend cap: the only hard stop on
  money.
- **Routing check [applied]:** each subagent transcript under
  `~/.claude/projects/D--prime-game/<session>/subagents/agent-*.jsonl` records the model that actually served it,
  and `agent-*.meta.json` next to it the `agentType` and any requested `model`. `tools\run.cmd agents-check`
  (this session; `--all` for every session of the main checkout and its worktrees, from any of them) asserts the model
  **family**, not exact IDs: the requested model, else the agent file's `model:`. `availableModels` is the shared list
  merged with the user-scope one (#183). A request from the user list is ok when it served and listed as "fell back"
  when another family served it; a request in neither list must be served by another family (the model guard).
  Workflow agents (`<session>/subagents/workflows/wf_*/agent-*.jsonl` and `.meta.json`, #206) get the same verdicts,
  printed with their label and run: a default launch's meta file has no `model` (a reviewer, a lean implementer
  or publisher, or a `lean-reader` or `lean-writer`, is judged by its agent file; an implementer or publisher of
  `agentType` `workflow-subagent` inherits the session's model and is only listed, unless a model in neither list
  served it: a failure); a `models` launch is
  read from `model`, as the Agent tool records it, and any other meta key that names a model, at any depth
  (`request.model`), fails until the reader learns it. After a launch that passes `models`, `agents-check` in the
  manager's session checks it. `finish-task` runs it after the reviews.
- **Launch check [applied] (#557; the lean ADR amendment of 2026-10-08):**
  `tools\run.cmd agents-check --launch` judges no transcript: in the manager's
  checkout, where the Workflow tool reads the scripts and resolves their agent types, it fails on a missing or invalid
  `task-implementer.md` or `task-publisher.md`, a missing `issue-task.js` or `pr-rebase.js`, or a file under
  `.claude/workflows/` or `.claude/agents/` that differs from origin/main after `git fetch origin main` (a failed
  fetch warns and compares with the last fetch). A script cannot read files, so it cannot check this itself; the
  manager runs it before each launch (orchestrate-stage §3).
- A new `.claude/agents/` directory is only seen by sessions started after it exists.

## 6. Skills [applied]

Committed in `.claude/skills/<name>/SKILL.md` (M0 stage 6); no plugins. The two content skills are the engineer's
since #518 (§9); they serve whoever brings the idea, the engineer or the optional designer.

| Skill | For | Does |
|---|---|---|
| `start-task`, `finish-task` | both | §4.1, §4.2 |
| `new-mechanic` | both | Front door for an idea: interview → `mechanic` issue + `engine-request` issues (stop for OK) → `start-task` → GDD section with open questions and **no invented content**; content data only once the content API exists (M2+) |
| `new-level-piece` | both | A room or interactable sub-scene per the level conventions; `normalize`; `shot` screenshot |
| `log-intervention` | both | Writes a `docs/interventions/` entry and promotes the rule in the same PR (§10) |
| `onboard` | both | "налаштуй мене": runs `doctor`, writes user settings after approval, prints the human-only checklist (§12) |
| `orchestrate-stage` | engineer | A manager kickoff for a stage (no "ultracode", `docs/MANAGERS.md` §2): the manager session runs one `issue-task` workflow per issue (§7.1). Since #561 `SKILL.md` is a core (the kickoff, the launch steps, the completion loop, reporting, the turn end) with an index naming, for each event, the file beside it that holds the rest, each keeping its § numbers: `stage-setup.md`, `launch-args.md`, `resume.md`, `merges.md`, `notifications.md`, `gotchas.md`, `kickoff-template.md`, besides `budget.md` and `handover.md` |
| `night-audit` | engineer | Started each night by the Desktop scheduled task `night-audit` (a manager runs it as a workflow only by hand, for a missed night): one read-only audit lens, every finding re-checked by one skeptic, issues and a summary on the "Night jobs" issue (§15) |
| `design-manager` | engineer | A pointer: the design track's manager runs in the private design repo `D:\prime-game-design` on that repo's own skill (§7.3, #1124); a design kickoff in `D:\prime-game` is sent there |
| `secretary` | engineer | The engineer's inbox: gathers what needs him from every session and the four repos into the pinned "Engineer's inbox" issue every 30 to 60 minutes and relays his answers; runs and decides nothing (§7.2) |

- No skill is named `doctor`, `verify` or `run` (they would replace bundled commands).
- All skills are model-invocable, so a dictated "заверши задачу" works; publishing still asks once.
- `start-task` and `finish-task` never use `context: fork`. `allowed-tools` carry Bash and PowerShell forms.
- The Python runner lints agent and skill frontmatter in `verify` [applied], so CI needs no Claude Code install.
  For skills: strict YAML subset, `name` = folder, no unknown field (Claude Code ignores one silently), the rules
  above, `description` + `when_to_use` within the 1,536-character listing cap, and a PowerShell twin for every Bash
  rule. `claude plugin validate .claude/skills` is no substitute: it passed a description YAML cannot parse.
- Of the bundled skills, the listing keeps only `workflow-authoring` (a manager loads it to write a workflow script)
  and `code-review` (step 2 of §4.2 routes docs-only diffs to it) (#562,
  [ADR](decisions/2026-10-08-skill-listing-and-account-connectors.md)): `skillOverrides` in `.claude/settings.json`
  sets each other bundled skill to `"user-invocable-only"` (out of the model's listing, still `/name` for a human).
  A Claude Code update that brings a new bundled skill needs a new entry. The lint fails an entry that hides ours or
  those two, and `disableBundledSkills`. The desktop app's `anthropic-skills` plugin stays listed and the account's
  connectors stay loaded: both are beyond project settings (the ADR).
- `allowed-tools` only pre-approves tools for the turn that invokes the skill; ask and deny rules still win, so a
  skill never bypasses the guard or the settings prompts.
- A running session sees edits to existing skills at once, but a `.claude/skills/` folder created after it started
  only after `/reload-skills`, and it is not watched afterwards: each later edit needs `/reload-skills` again
  (code.claude.com/docs/en/skills; seen live on 2026-09-29, when `finish-task` loaded its text from the reload).

## 7. Effort and orchestration

([ADR](decisions/2026-09-28-effort-and-workflow-bounds.md))

| Work | Effort |
|---|---|
| Foundation stages with no mid-task human input: M0 execution, core architecture and content-API design before M2, project-wide audits | xhigh + `ultracode` in that one prompt; one workflow per stage; human review between stages |
| Everyday `core/ server/ net/ voice/` work, and **all tooling** (`tools/`, runner, hooks, CI) | high |
| Docs, content data, routine fixes; the designer's default | medium |
| Manager sessions (§7.1) of every track, and the art and UI sessions | high, not xhigh (the ADR's amendment of 2026-10-04; the human sets it, with bypass, when he pastes the kickoff: `docs/MANAGERS.md` §1) |
| The secretary session (§7.2) | medium, on Opus (the engineer's answer on #170, #485) |
| The design manager (§7.3) | high, on Opus, like every manager |

Rules for every workflow run:
- **Size guideline `small` (fewer than 5 agents)** [applied: `workflowSizeGuideline` in shared settings].
- Every workflow prompt states its bounds: max agents, max turns or tool calls per agent, a wall-clock or token
  budget, and what to drop first when the budget runs out.
- Before launching, the agent states the planned agent count and a rough cost, and waits for a yes. Exceeding the
  size guideline needs the human's explicit approval in that same message, or in a §7.1 stage kickoff, which
  approves the stage's task workflows once; "ultracode" alone does not count.
- A run never decides a human-reserved item; it records options and a recommendation and continues.
- Temporary files go only to the session's scratchpad or, when they must be under `res://` (a probe test), to the
  gitignored `tests/scratch/` of the checkout the agent works in; deleting either never prompts (§8.2). Inside its
  own worktree an agent's deletes and git are free too (#51), but a temporary folder in the main checkout or another
  worktree asks on delete and stops the run until morning. An unattended run's prompt says so, gives each task its
  worktree (`cd <worktree> && ...` in Git Bash, `Set-Location <worktree>; ...` in PowerShell, at the start of
  every command), and tells its agents not to run commands they
  expect to prompt (deletes, resets, rebases or branch deletes beyond their own worktree and task branch) but to list
  them in the handoff for the human instead: a prompt blocks the call, so an agent cannot note it and move on
  ([intervention](interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md)).
- Design runs produce documents first. Output lands as focused PRs, each with its verification, checked by a
  **fresh** agent.
- Changes to `.claude/settings*.json` and `addons/` wait for the human (ask rules prompt in every mode). Other
  `.claude/` paths are protected by Claude Code itself and prompt in every mode except bypass, so unattended runs
  that edit them need bypass.
- `effortLevel` is never put in shared settings.

### 7.1 The orchestrator session
([ADR](decisions/2026-09-30-orchestrator-session.md); skill `orchestrate-stage`)
- **When:** a whole stage or a list of issues that can run in parallel, with the engineer around to answer. One
  issue alone stays a normal task session (§4).
- **How:** one session, the **manager**, started from a kickoff the engineer pastes (no "ultracode": the
  [manager rules](MANAGERS.md) every track follows, #511), runs the skill. For each task it runs `start` itself, then the
  saved workflow `issue-task` (`.claude/workflows/issue-task.js`: implementer → fresh reviewers chosen from the
  changed paths → publisher; `design: true` for a docs-only design task) with `args` (issue, worktree, branch, base,
  notes, coordination, the engineer's decisions). A semantic conflict after a merge goes to `pr-rebase`
  (`.claude/workflows/pr-rebase.js`); a docs or test-list conflict the manager resolves inline. A small task (the
  issue's `Size:` XS or S, one logical change, no design) goes to `quick-task` instead (`.claude/workflows/quick-task.js`,
  #608): one agent takes it through lint, check, a PR and CI, fresh reviewers only for a diff under `core/ server/ net/
  client/ voice/ tests/harness/` (`code-reviewer` alone when those paths are all under `client/ui/`, #606), and the
  manager merges it at once when its result says `ready_to_merge` (the definition of done's review step, §4.2, is then
  CI alone for any other diff). `issue-task`'s review chain follows the change's risk (#606, [ADR
  amendment](decisions/2026-10-09-tests-on-ci-local-lint-and-check.md)): the full chain for a path under `core/ server/
  net/ client/ voice/ tests/harness/` (but `client/ui/`), no changed paths, a design task or `tier: "full"`; the light
  one (`code-reviewer`, `godot-api-checker` on a `.gd .tscn .tres` change, the publisher) for any other diff. A
  relaunch of a published PR passes `update: true` (#856) and reviews only the delta. Details: orchestrate-stage
  `launch-args.md` ("Review tier") and `docs/workflow-scripts.md`.
  A session runs a saved workflow as `/issue-task`, or with the Workflow tool by `name` or `scriptPath`; after editing one, a running
  session needs `/reload-skills` (code.claude.com/docs/en/workflows). Both route `netcode-security-reviewer` by the
  same paths as §4.2, `client/` included: a leak through rendering is an information leak (#158); a diff whose only
  such paths are under `client/ui/` gets none in either script (#606), and the result says so.
  `tools/runner/tests/test_workflows.py` runs the scripts under Node with stub agents and checks their routing and
  rules (skipped where Node is missing, except on GitHub Actions, where a missing Node fails it). Workflow agents
  read their prompt, not this file, so each rule they need is a line of it (the read-only agents' as `REVIEW_RULES`),
  identical across the scripts and pinned by the test: the hooks path (§8.1), the bounded wait (§11.17), no write
  outside the worktree and the scratchpad (#413), the one way to change an earlier commit (#456, §8.2.6).
  Both return a compact result (#386): the harness prints a run's return value into the manager's context, so it
  holds what orchestrate-stage §4 acts on and `full`, the path of the run's journal with every agent's whole result;
  a stop keeps in full what its relaunch needs. Agents get digests of each other's results (#470, #696), and the
  publisher's prompt carries `finish-task`'s docs, intervention and credits steps itself.
- **Pipeline v2 options** ([ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md), item 4; #180):
  optional `issue-task` args (`plan_review`, `test_review`, `second_review`, `skeptic`, `visual`, `efforts`,
  `models`, `ab_review` (ended 2026-10-13: refused since #1147), `checkpoint`; `pr-rebase` takes `second_review`, `skeptic`, `efforts` and `models`), all off
  by default but `checkpoint` (on since #920, the engineer's answer 6A on #302: `checkpoint: false` turns it off); bounded waits (#411) and the lean agent types (#458) are always on (#883 removed their switches). What each does, when to pass it and the agents it adds: orchestrate-stage `launch-args.md` (a row per
  arg) and each script's header comment, `whenToUse` and args comment (the counts, the roles and their fallbacks);
  `tools/runner/tests/workflow_snapshots/` pins the prompts and options they produce (`docs/workflow-scripts.md`).
  The kickoff's approved agent count must cover the options the manager will pass.
- **Lean agent types** ([ADR](decisions/2026-10-04-lean-workflow-agent-types.md), #332, #458, #557): always on since #458
  (#883 removed the `lean` switch); the implementing agents run as `task-implementer` and the publishing ones as
  `task-publisher` (§5), with
  no desktop, MCP or Skill tools; the manager's checkout must have both agent files, which `agents-check --launch`
  checks (§5). A task that edits `.claude/workflows/` reads `docs/workflow-scripts.md` instead of the bundled
  `workflow-authoring` skill.
- **Bounds:** the concurrency cap, the agents' tool-call bounds and the `a<n>/` scratchpad subfolder are in the
  kickoff (orchestrate-stage `kickoff-template.md`, `launch-args.md`); the approval of the agent count and the budget,
  the design gate and the runs another session may still own, in orchestrate-stage `SKILL.md`, `stage-setup.md` and
  `budget.md` (the [trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tiers).
- **Git flow** ([ADR](decisions/2026-10-01-release-branch-per-milestone.md), amended 2026-10-13: from M7 on no
  release branch): every task PR of a stage targets `main`; the manager merges it through the gate below, never by
  git steps or a typed `gh pr merge`, which stays denied (the `main` rulesets ask only for a PR and green checks, so
  it would let any agent merge into `main`). Before each merge the manager runs `tools\run.cmd merge-check` (#181,
  #207: each open PR onto its base tip and each pair into it, textually and by symbols; `--trial` merges them in a
  scratch worktree and runs its fast `verify`; the `merge.py` docstring has the rules). **No local `verify`** (#622,
  #605): CI tests. The milestone ends with its playtest and the closing of its issues. A kickoff may still name a
  release branch `release/m<k>` for a stage (`merge --base release/m<k>`, `--sync-main`; CI runs on pushes to
  `release/**`): the steps are in orchestrate-stage `merges.md`.
  - **Into `main`** (#300, the [trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)): the
    engineer's manager runs `tools\run.cmd merge <pr> --base main` from the main checkout once the fresh reviews left no
    open blocker or major (`--dry-run` first, from any checkout). Its gate collects every refusal (the `merge.py`
    docstring; orchestrate-stage `merges.md`): CI not green, a draft, not the engineer's PR or session, a head behind
    `main` that overlaps it, the exceptions (the content area, §9, or an ADR changed without "Approved by the engineer:
    <GitHub link>", #563; `.claude/settings*.json`, `.claude/githooks/`, `tools/runner/guard.py`, always), a closing PR
    without the engineer's go, and an open "Needs the engineer" item without "Answered: <GitHub link>". No local
    `verify`: `publish` and CI tested the head. Each merge is one chat line to the engineer; when `main` breaks after
    one, the manager opens a revert PR (`git revert -m 1 <merge>` on a task branch), merges it through the same gate
    and says so. "стоп мерджі" from the engineer returns merges into `main` to the engineer until the engineer says
    otherwise (recorded on the plan issue and #170). A solo session merges only where the engineer said so, from the
    main checkout.
  - **A list into `main`: `merge-train`** (#387): each merge leaves the others behind `main`, so they go in series.
    `tools\run.cmd merge-train <pr>... --base main` (from the main checkout, in the background, polled with `wait`)
    takes them in order with no manager turn between: per PR its way (no publish, a merge of `origin/main`, or the
    worktree's `publish`), CI, then the gate; a PR it cannot take is skipped with the reason (the skip conditions: the
    `train.py` docstring). Before the train the manager checks each PR's findings (no open blocker or major), which the
    gate does not read. It never pushes `main` and never merges a gate exception.
- **Parallel tracks** ([pipeline v2 ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md) item 7, the
  engineer's answers N2 and N5, 2026-10-02): one milestone at a time; beside it the AI productivity track (#170) sends
  its PRs into `main` like every track, each merged by its manager through the gate (Git flow above, "Into `main`"). How many task workflows run at once, each track's budget and its spend
  reports: N3 (b) of the [weekly budget ADR](decisions/2026-10-05-weekly-budget-across-four-tracks.md), whose rules
  the orchestrate-stage skill's `budget.md` holds. Shared files (N5 (c)): `.claude/workflows/` and the
  orchestrate-stage skill change only through the tooling track, between the other managers' waves; `tools/runner/`
  and this file may be changed by any track between waves, after `merge-check`, which pairs PRs across bases when both
  change a shared file (`tools/`, `.claude/`, `.github/`, this file); a flagged pair: the PR that merges first
  goes through the gate, the other rebases on its base (`main`; a release branch a kickoff names: after `merge --sync-main`; orchestrate-stage `stage-setup.md` item 8, `merges.md`). After a
  change to a shared file reaches `main`, the tooling track's manager says so on each running manager's plan issue.
- **The human:** writes the kickoff once per stage (template in the skill, with the budget as a percentage of the
  weekly limit), answers the numbered "Needs the engineer" questions, gives each milestone's go (a playtest) and merges
  the gate's exceptions. The manager closes issues whose work is on `main` and runs `worktree-done` for its merged
  tasks when no live session sits there. Every message from the manager ends with one short "For you:" block, each
  command the human must run goes into the chat itself as one runnable PowerShell block, and the manager keeps its
  prompt cache warm while a run is in flight: [`docs/MANAGERS.md`](MANAGERS.md) ("The \"For you:\" block", "The
  keep-alive"; interventions: [For you](interventions/2026-10-04-engineer-for-you-block.md),
  [commands in the chat](interventions/2026-10-03-engineer-commands-in-the-chat.md)) and orchestrate-stage
  `notifications.md`.
- **Recovery:** a crashed run resumes with `resumeFromRunId` and the same args; the prompts tell each agent to check
  what an earlier attempt already did, so a fresh run with the same args also continues. Each wave comment on the
  plan issue lists the running runs with their args, so a new manager session can take over from GitHub alone. The
  handover is mechanical (#279, #467, #511): at each turn end the manager runs `wave`, whose last line is the verdict;
  when to hand over, the handover comment with the ready kickoff the human pastes, and Route C as the fallback:
  [`docs/MANAGERS.md`](MANAGERS.md), the one place for the rules every track's manager follows (the UI and art
  managers, in their own repos without this skill or `wave`, point there), and orchestrate-stage `handover.md`.

### 7.2 The secretary session

(#485; the engineer's answers on [#170](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6025360550),
recorded in the [weekly budget ADR](decisions/2026-10-05-weekly-budget-across-four-tracks.md), Q5, amended
2026-10-07.) With four tracks' managers and his own sessions, the engineer went from session to session to find
what waited for him. One more session, the **secretary**, does that and is no manager: it runs nothing.

- **Who:** one session of the engineer's, Opus at medium effort, in `D:\prime-game` (it only reads the checkout), on
  the skill `secretary` (`.claude/skills/secretary/SKILL.md`). Its cost counts in the engineer's own 5% of the week
  (the skill's `budget.md`) until he says otherwise.
- **Powers:** it reads every session and the four repos, digests, and relays the engineer's answers to the session
  that asked, which records them on GitHub as usual. It never merges, launches, closes, creates or decides; it never
  answers a permission card (they are the human's by design). Its only writes: the inbox issue's body, relay
  comments and `send_message`.
- **Where and when:** the pinned issue "Engineer's inbox", whose body it rewrites every 30 to 60 minutes while the
  engineer is at the PC (a background `sleep 3000` timer, re-armed while he wrote in its chat in the last 3 hours):
  what to approve or decide and what to look at, numbered, each item with a link or a ready command. In its chat,
  one short line on what changed. "що нового?" digests at once.
- **Sources:** `tools\run.cmd inbox` gathers the GitHub half in one call (§11.23); `list_sessions`, `list_events` and
  `search_session_transcripts` give the sessions' half: each session's last "For you:" block and the day's news.
- **Relays:** `send_message` to the session that asked; a session a scheduled task started is unattended and refuses
  it ("messages can't be delivered there", probed on
  [#484](https://github.com/xperiaroco2/prime-game/issues/484#issuecomment-6025367088)), so the answer goes as a
  comment on the plan issue that session watches, or on the PR the item came from, quoting the engineer's words.
- **Every manager's "For you:" block stays parseable** (orchestrate-stage §8, `notifications.md`): the label
  `For you:` (or `Для вас:`) on a line of its own, then numbered items at the line's start, each item's command block
  indented or fenced under it, or `For you: nothing.`; the same block goes into the wave comment's notes in English,
  where `inbox` reads it.

**Approval cards (probed 2026-10-06 ~21:12 UTC, from a workflow agent of the meta manager).** `get_session` has no
pending-approval field, only `isRunning` and `lastActivityAt`. `list_events` renders a call still waiting for its
result as `[assistant] (called Bash)`, with no arguments and no result line (the running "META" session's last event
then). So a session that waits on a card looks like one inside a long call. Since agents block no call over 180 s
(§11.17), the secretary reads a running session whose last event is such a call and whose `lastActivityAt` is over 5
minutes old as "probably waits on a permission card", and names the session and the tool. A session known to
sit on a card was seen on the night of 2026-10-09/10 (#731); whether `lastActivityAt` stayed frozen meanwhile was not
checked. The transcript shows the card: its call has a PreToolUse
`hook_success` record whose `permissionDecision` is `ask`, then no result. The session's notifications pile up as
queue `enqueue` records with nothing delivered. `tools\run.cmd wave --stalled` (§11.11) reads those records and names
the session, the card and the guard's reason.

**Set up** (the engineer, once): the issue and its pin.
```powershell
cd D:\prime-game; gh issue create --title "Engineer's inbox" --body "The secretary session rewrites this body (docs/AGENT_WORKFLOW.md §7.2)."
```
```powershell
cd D:\prime-game; gh issue pin <the new issue's number>
```
**Start** (the engineer, when he sits down): a plain new Desktop session (not a scheduled task) in `D:\prime-game`,
no worktree, model Opus, effort medium, the permission mode he uses for his own sessions, with the kickoff below
pasted. A plain session, because the secretary lives on his chat and its relays, and a scheduled-task run is the
wrong shape for both (#484's probes): the app wraps its prompt in a frame that says the user is not present and
allows only the writes the task file names; no other session can `send_message` to it; it starts in `acceptEdits`
at medium whatever its creator ran in; and an unattended session cannot `run_scheduled_task`, so a scheduled-task
manager could not start it anyway. Whether the engineer can type into a scheduled-task run is still unprobed.
A scheduled task `secretary` stays an option only once those are probed; its kickoff would then have to name the
writes (the inbox body, relay comments, `send_message`) and say the engineer is present.

The kickoff:
```text
/secretary
Digest now, then every 30 to 60 minutes while I am at the PC. I am here and answer in this chat.
```
No `Track:` line: `metrics --track` counts a main-checkout session without one as the engineer's own (untracked)
share, where the secretary's cost belongs. Its first digest also checks that `list_sessions`, `list_events` and
`send_message` load (ToolSearch) and names any that does not in its chat line.

**The timer stops** after 3 hours without a word from the engineer in its chat (his answer (a) on
[#502](https://github.com/xperiaroco2/prime-game/pull/502#issuecomment-6026981361), not a fixed day window or
"пауза" alone): it costs nothing while he is away, one word restarts it, and "пауза" still stops it at once.

### 7.3 The design manager session

(#1120; the engineer's yes on [#1095](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6199371817);
its own repo since #1124.) Game design is a track of its own, `design`, beside game, UI, art and meta: the engineer,
the project lead and the game designer, works through one manager session at a time, which keeps the design context
across sessions and hands over like any manager (`docs/MANAGERS.md`).

- **Where:** the private repo **xperiaroco2/prime-game-design**, checkout `D:\prime-game-design` (the engineer's
  decisions, [#1095 comment 6200062331](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6200062331):
  the design "lives its own life", and [comment 6200108169](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6200108169):
  a separate repo). Its research, references, idea batches and brainstorms are committed straight to its `main`, with no
  checks; its root `CLAUDE.md` holds its rules, its `design-research` workflow and `design-reader` and `design-writer`
  agents its research. Its manager follows `docs/MANAGERS.md` like the UI and art managers (§8's pointer, design
  variant). What stays here: the decided rules (`docs/GDD.md`, `docs/design/`, with `docs/design/COMPASS.md`, which
  the design repo reads by path), each landing through a docs PR on the design-only fast path (§4.2, #1123), and the
  archive of 2026-10-15 (`docs/design/research/`, `docs/design/ideas/`).
- **Who:** one session of the engineer's in `D:\prime-game-design`, Opus, bypass, effort high, on that repo's skill
  `design-manager`, started by its kickoff (`Track: design`, plan issue #1095). This repo's
  `.claude/skills/design-manager/SKILL.md` is only a pointer there.
- **Its lens:** `docs/design/COMPASS.md` (`D:\prime-game\docs\design\COMPASS.md` from the design repo), read
  whole at each start: the tone (described without other works' names: the repo is public; the names are in the
  engineer's personal memory), the tone test, the pillars' checklist and how an idea moves.
- **Powers:** it researches (workflows of up to 12 agents a launch after his yes, #1095 comment 6200108169), proposes
  and records; it never decides content; its docs PRs here merge only on his word for that PR, through the gate.
- **Budget:** the `design` line of `.claude/skills/orchestrate-stage/budget.md`. `tools\run.cmd metrics --track
  design` (run in `D:\prime-game`) counts the design repo's sessions with the main checkout's (its sessions' default
  track is `design`), and `metrics --run`, `wave --stalled` and the secretary's `inbox` read that repo too (#1124).

## 8. Permissions, guards and hooks

([ADR](decisions/2026-09-28-permissions-and-thin-guard.md))

### 8.1 Permission rules [applied]
`.claude/settings.json`, strict JSON. Every `Bash(...)` rule has a `PowerShell(...)` twin. Deny beats ask beats allow.
**Goal: an agent can work alone overnight** (read status, branch, commit, push its task branch, open PRs and issues,
edit tooling, clean up its scratchpad and `tests/scratch/`) and stops only for the rare items below
([ADR](decisions/2026-09-28-unattended-work-permissions.md)). **Test for a new ask or deny rule:** "can an agent work
alone overnight?" Replay the latest unattended run's transcripts against the new rule
(`tools\run.cmd permissions --before origin/main` replays this project's transcripts, the main checkout's and its
worktrees', through the rules and the guard of `origin/main` and of the checkout, in bypass mode; `--since
YYYY-MM-DD` keeps the calls from that day on, `--mode acceptEdits` or `--mode default` models a mode that prompts
(§8.2.10), `--list` names each cause with examples, and `--observed` reports what the transcripts record instead:
the guard's asks, deny rule denials, Claude Code's own blocks and the human's rejections, with roles and waits, but
not an ask rule's prompt that the human approved, which leaves no trace: the replay's "ask rules" count holds those;
the replay reads the file tools' calls too, and every mode applies Claude Code's built-in delete checks); a rule that
would have stopped routine work is judged by its target in the guard (§8.2) instead of by its text
([intervention](interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md)). `runner.permissions` models
Claude Code's matcher (subcommands, wrappers, `*`, deny before ask before allow, its documented read-only commands and
a guess at git's read-only forms, which a `cd` elsewhere in the same call takes away; `acceptEdits`' file writes and
protected paths, §8.2.10), and its selftests (`tools/runner/tests/test_permissions.py`) check the lists with the
guard: reads of other repositories pass in every mode, writes there ask, and every `Bash(...)` rule has its
`PowerShell(...)` twin. **Inside its own worktree and task branch an agent has full freedom**: every git operation
and every delete there runs without a prompt, and it stops only for design and other human-reserved decisions and
for what reaches beyond them ([intervention](interventions/2026-09-30-engineer-full-freedom-in-own-worktree.md)).
- Deny and ask rules apply in **every** permission mode, including bypass; allow rules matter only in the modes that
  prompt (`acceptEdits`, both humans' default mode and a route-C successor's only one: there the guard allows routine
  shell work in an unattended session, §8.2.10).
- **Allow:** the runner; `git fetch origin`, `add`, `commit`, `log`, `switch`, `branch`, `stash` (push/list/pop),
  `git push [-u] origin <branch>`; `gh` issue and PR create/view/list/comment/edit/close/ready, run
  list/view/watch/rerun, workflow list/view, `label`, `project`, `ruleset`, `release view|list`, `search`, `repo view`,
  `api` (GET and POST); WebFetch to Godot, Claude Code, GitHub and git docs. These rules also cover **reads of other
  repositories** (`gh issue view 1 -R godotengine/godot`, `gh release list --repo x/y`, `gh search issues --repo x/y`,
  `gh api repos/x/y/...` GET): no text rule asks for `-R|--repo` since #68.
- **Ask (the agent's stop points):** edits to `.claude/settings*.json` (its own permissions) and `addons/`
  (dependencies); `gh api` PUT/PATCH/DELETE; deleting issues, labels, projects or the last comment; `gh pr review`;
  `gh workflow run|enable|disable`; `gh release create|edit|delete|upload|download`, `secret`, `variable`;
  `gh repo edit|rename|archive|deploy-key`. A `gh` command that may write to **another repository** (comment, create,
  edit, close, `api` with a write method or fields) has no text rule since #68: ask beats allow, so a rule on `-R` also
  stopped every read. The guard asks for it (§8.2). Work-discarding or history-rewriting git (`reset`, `checkout`,
  `switch -f|--discard-changes`, `restore`, `clean`, `rebase`, `stash drop|clear`, `branch -d|-D`, `worktree`, `git -c`)
  and recursive deletes have no text rule since #51 (and #47 for `rm -r` and `git reset`): the guard asks by where they
  act (§8.2), so they are free in the agent's own worktree and on its task branch, and ask in the main checkout (but
  a cloud session's on its task branch, #381), in another worktree and on another branch.
- **Deny:** force pushes; pushes to `main` in any spelling, including a bare `git push`, `git push [-u] origin` with
  no branch and any push naming `HEAD` (always push an explicit branch name); `--no-verify`, remote deletes,
  `--prune`, `--mirror`, `--all`, `git config` on `hooksPath` or `--unset`, `--upload-pack`,
  `--output`, **`gh pr merge` and `mcp__ccd_pr__set_auto_merge`**, `gh repo delete`, `gh auth token`,
  token-printing `gh auth status`. A deny rule matches reads too and denies the whole call: read the hooks path with
  `git rev-parse --git-path hooks` (it prints `.claude/githooks`) or `doctor`, never `git config --get core.hooksPath`
  (10 denied calls in the week to 2026-10-04, #312), and the merge help with `gh help pr merge`, never
  `gh pr merge --help`. Each `git push ...` deny rule has the twins `git -C * push ...` and
  `git -c * push ...` (#342; other git options before `push`, such as `--git-dir`, are left to the pre-push hook and
  the server ruleset), and because `*` spans words they also deny a `git -C` or `git -c` command whose `-m` message
  contains the word `push` (at its end, or before `HEAD`, `main` or a forbidden flag), so such a message goes in a
  file (`-F`).
- Godot, Python and gdtoolkit run without a prompt **only through the runner**; their raw forms prompt in modes that
  prompt.
- `GH_PROMPT_DISABLED=1` is set in the shared `env`.

### 8.2 Thin guard [applied]
Hooks live in `.claude/settings.json` and run in Git Bash through `.claude/hooks/run-hook.sh`, which finds Python as
`PYTHON_BIN`, else `py -3`, else a `python3` that really runs; the logic is in the runner (`run hook <name>`), so
`selftest` covers it in CI ([ADR](decisions/2026-09-29-claude-code-hooks-in-git-bash.md)). **Fail-closed:** no Python,
a crash, or any exit code other than 0 and 2 becomes exit 2, which blocks the call. A hook that cannot start, or
that times out, fails open: `doctor` is red when Git Bash is missing.

**Start-up (#568).** The guard runs before every shell call, so its start-up is kept small: `run-hook.sh` starts
Python with `-S` for the guard (no `site` module: it needs only the standard library), `tools/run.py` imports `hooks`
and `guard` from checked-hash pycs in `tools/out/pycache` (PEP 552: checked against the source's hash on every import,
so an edit is never missed; the standard library keeps its own bytecode, the runner's other modules compile as
before), and neither module imports `typing` or `common` (`test_hooks.py`'s `HookStartUpTest`). Measured on the
laptop (16 threads) on 2026-10-08, the hook as Claude Code starts it (`bash -c 'bash run-hook.sh guard'`), median /
p95 of 20 calls: 249 / 267 ms idle before; beside one other worktree's `verify`, 418 / 884 ms before and 333 / 675 ms
after, Python's part 243 / 425 ms before and 145 / 357 ms after. The rest is two Git Bash starts (Claude Code's shell
for the hook's command, then the `bash` the command names; about 70 ms each idle, 100 to 140 ms under load) and
Python's own start. `metrics` reports the start-up of real calls (§11.12, the tool-call start-up per class of call).

The guard is a PreToolUse hook on `Bash|PowerShell`, with no network calls. It asks before three kinds of shell
command: those that lose work outside the session's own worktree and task branch, `gh` commands that may write to
another repository (both below), and **shell commands that write to the ask-protected paths** of this project
(top-level `.claude/settings*.json` and `addons/`, of the main checkout or a worktree): `Copy-Item`, `Move-Item`,
`Set-Content`, `Out-File`, `>`, `tee`, `cp`, `mv`, `rm`, `sed -i`, archive extraction, downloads, `git checkout|restore|rm|mv|clean|stash` naming those paths, paths fed by a
pipeline (`Get-ChildItem addons | Remove-Item`, `| xargs rm`), `for` loops over them, `bash -c`, `powershell -Command`
and `$(...)` bodies, and the inline code of interpreters and .NET calls (`python -c`, a heredoc fed to Python,
`node -e`, `[IO.File]::WriteAllText`). Text rules cannot see these writes: Claude Code checks a redirect or `tee`
target against Edit allow and deny rules, not ask rules. The file tools need no guard, because `Edit(...)` rules
cover Edit, Write and NotebookEdit. So a test of what happens without an addon runs in a scratch clone outside the
project (`git clone` into the scratchpad, then remove the addon there), never by moving `addons/` in the worktree,
which asks at every step (5 asks in one task on 2026-10-03, #312).

It also judges two kinds of command by what they act on, where a text rule would stop an unattended agent: commands
that lose work, by where they act (its own scratch folder, issue #47, or its own worktree, issue #51), and `gh`
commands, by the repository they name (issue #68, a read of another repository must not stop it).

#### 8.2.1 The session's own worktree and task branch are free
(issue #51,
[intervention](interventions/2026-09-30-engineer-full-freedom-in-own-worktree.md)). The own worktree is the
`.claude/worktrees/<n>` that the session's working directory is in; a session whose shell starts in the main
checkout (a manager's task session) owns the first worktree its command enters with `cd`, `Set-Location` or
`git -C` (`cd D:/prime-game/.claude/worktrees/51 && git rebase origin/main` passes; a second worktree in the same
command asks), unless another live Claude session works in that worktree (`sessions.active_on`): then it owns
none. On a desktop the main checkout is never owned: the designer's sessions and the engineer's `start --here`
sessions keep every prompt. **A cloud session** (§2.1; `CLAUDE_CODE_REMOTE` true and not CI, the test `doctor`
uses: `common.cloud_session`, which `hooks.cloud_session` mirrors without importing `common`) whose working
directory is in no worktree owns the main checkout while a task branch (`<area>/<n>-<slug>`, `guard.TASK_BRANCH_RE`)
is checked out there (issue #381): the same rules as a worktree on its task branch, with `<n>` taken from that
branch. No worktree folder pins `<n>` there, so any task branch checked out counts, a parent's after a switch too.
`.git`, `.claude`, `.claude/worktrees` and any glob that may name them (`.[^.]*`, `*`, `{s..t}`, an extglob) stay
outside it, and so do `git clean -x|-X|-e|-ff` (ignored files: `.claude/settings.local.json`, the other worktrees as
nested repositories), `git stash -a` and magic pathspecs (`:(top)x`); git work in another worktree still asks.
`git clean -en` is `-e n`, no dry run (in every checkout since #381). On `main`, `release/*`, any other branch or a
detached HEAD it asks as on a desktop; a rebase stopped on a conflict keeps its branch (`hooks.GitFiles` reads
`rebase-merge|rebase-apply/head-name`). The pre-push hook and the push rules (no `main`, no force push by hand) are
unchanged. `tools/run.sh permissions` judges the replayed calls as this machine's sessions: a cloud container's
replay sees the cloud rule. The task branch is known by the worktree's identity: the branch checked out in
`.claude/worktrees/<n>` when its name is `<area>/<n>-<slug>`, as `start` makes it. Another branch checked out
there (a parent, a spike) is not the task's, so work that discards on it asks, whatever an earlier call did; a
detached HEAD moves no branch and stays free. Its helpers are branches named `<task branch>-x`,
`<task branch>/x`, `<task branch>.x` or `<task branch>_x`. The hook reads branch, ref and stash names from the
files in `.git` (`hooks.GitFiles`, no git call).

#### 8.2.2 Workflow agents' hooks take the manager session's working directory (the `cwd` of the hook input), not their own
A manager whose shell stands in a worktree (a `cd` in the Bash tool persists between its calls) makes that
worktree every agent's own, and each agent's own worktree someone else's: on the M3 night run a publisher's
autosquash in its own worktree asked that way, and a replay with `tools\run.cmd permissions` showed the same
command passing from `D:\prime-game`. So the manager enters worktrees only through subshells `(cd <wt> && ...)`,
`git -C <wt>` or PowerShell `Push-Location`/`Pop-Location`, and its shell stays in the main checkout
([intervention](interventions/2026-10-01-engineer-night-run-prompts.md)).

#### 8.2.3 Recursive deletes
(`rm -r|-R|-rf|--recursive` or `--rec` in bash, `Remove-Item -Recurse` or `-r`, `rmdir /s`,
`rd /s/q` (`//s` from Git Bash), `del /s`, a plain delete fed by a recursive listing, an unfiltered `find -delete` or `find -exec rm -rf`,
`shutil.rmtree('x')` and `[IO.Directory]::Delete('x', $true)`; also inside `bash -c`, pipelines, `xargs`,
`timeout` and `for` loops) ask when a target is the project (the main checkout or a worktree), inside it (but not
inside the own worktree; its folder itself, `rm -rf .` there, still asks), above it, a drive root, `/`, or the home or temp folder itself (`~`, `$HOME`, `$env:TEMP`). A target it cannot resolve
asks when it names the project: its folder name (read from the checkout, so a clone named otherwise is covered),
`git rev-parse --show-toplevel`, `$PWD` inside it, a command's output that names a path in it (`$(realpath core)`,
`(Resolve-Path core)`; `$(mktemp -d)` names none), a variable or loop built from such text, or a relative path
after an unresolvable `cd` made from inside the project. The targets of a pipeline (`$_`, `{}`, none) are the
paths its first command names, or the working directory. A PowerShell array (`Remove-Item -Recurse a,b`,
`'a','b'`, `@('a','b')`) and a bash brace expansion (`x/{a,b}`) are judged item by item. Regenerated output
(`tools/out/`, `.godot/`, any `__pycache__/`) and the gitignored scratch folder `tests/scratch/` pass, in the main
checkout and in every worktree; so do the scratchpad, `$TEMP/x`, `/tmp/x` and `~/x` (the hook passes the real
home folder, so a checkout under home stays protected). `$(git rev-parse --show-toplevel)` is the checkout that
holds the working directory, so `rm -rf "$(git rev-parse --show-toplevel)/tests/scratch"` passes too.
- Neither the Bash tool nor the PowerShell tool keeps variables between calls. In bash a variable the command never
  assigns is therefore also judged as empty: `rm -rf "$X"/*` is `rm -rf /*` and asks, and `cd "$X" && rm -rf y`
  stays in the project and asks. A bash subshell (`( ... )`, `$(...)`) keeps its `cd` and variables to itself, and
  `cd -` and `popd` go back to where the command was (or stay, when it never moved). What still passes: a variable
  from the environment or a PowerShell variable the command never assigns, when its text does not name the project;
  filtered deletes, even project-wide ones (`find . -name '*.orig' -delete`, `find . -name '*.gd' -delete`,
  `Get-ChildItem -Recurse -Filter *.tmp | Remove-Item`; a filter of `*`, or one before `-prune -o`, is none).
- **A filtered recursive delete in the temp folder is judged by what it matches** (#464): a glob after `$TEMP`,
  `$TMP`, `$TMPDIR`, `$env:TEMP`, `%TEMP%` or `/tmp` (`rm -rf "$TEMP"/rmtree-*`, `Remove-Item -Recurse
  $env:TEMP\x*`), and a PowerShell `Get-ChildItem $env:TEMP -Filter 'rmtree-*' -Directory | Remove-Item -Recurse
  -Force` that does not recurse (its targets are `$env:TEMP\rmtree-*`, not the folder). A filter matches the Win32
  way, so the guard reads it as a glob that matches at least as much (`x.*` and `x.` also match `x`, so `*.*` matches
  every name; a `?` also matches nothing; `[` is a literal), and a filter without a glob (`-Filter claude`) is judged
  the same way. It passes unless the pattern reaches outside the folder (`..`) or has a part the guard cannot read
  (`"$TEMP"/$X*`, `-Filter $f`, a `~` that may match an 8.3 short name), may match a Claude scratchpad root or a
  folder that holds one (`claude/<project>/<session>/scratchpad`: `"$TEMP"/cl*`, `"$TEMP"/claude/*/*`; any
  session's, the guard does not know which is the caller's) or reach into scratchpads through a wildcard project or
  session (`"$TEMP"/claude/*/*/scratchpad/*`), or a match is or holds a worktree (a `.git` file in it, a worktree of
  this repository at or below it, or a symbolic link or junction at or above it; `hooks.GitFiles.temp_matches` lists
  the folder when the hook runs, comparing final paths: a TEMP named by its 8.3 short path holds the worktrees git
  records by their long names, #542). A delete inside one named session's scratchpad
  (`"$TEMP"/claude/<project>/<session>/scratchpad/a1*`) passes. A recursive listing (`Get-ChildItem $env:TEMP
  -Recurse -Filter x`), `-Filter *` and an unfiltered one still delete the temp folder itself and ask; a literal
  path there (`$TEMP/x`) is judged as before. One such delete of `rmtree-*` leftovers waited 8.8 hours on
  2026-10-05.

#### 8.2.4 `tests/scratch/`
Is for temporary files that must be under `res://` (a probe test). It is gitignored but not
gdignored, so `tools\run.cmd test tests/scratch/<file>` and `check res://tests/scratch/<file>` run what is there;
full `check` (its UID lint too, #264), `test` and `lint` runs leave it out, so a half-written probe or a leftover
`.gd.uid` never turns `verify` red. Godot still imports it: no `class_name` and no uid copied from a project file
there (a `.tscn`/`.tres` header, or a suite's `.gd.uid` copied with it): Godot gives the uid to whichever file it
scans last, so the import and the UID lint both fail on a copy. Never create a link or junction there: the guard
judges a delete by its text path, and PowerShell 5.1 `Remove-Item -Recurse` on a junction deletes what it points to.

#### 8.2.5 `git reset`
Asks with `--hard`, `--merge` or `--keep`, or when it moves the branch to another commit
(`git reset HEAD~1`, `git reset --soft origin/main`, `git reset v0.1.0`), in a repository anywhere in the project
but the own worktree, `tools/out/` included; `-C`, `--git-dir` and `--work-tree` name that repository. Unstaging passes: `git reset`, `git reset -q`, `git reset -- <paths>`,
`git reset HEAD -- <paths>`, `git reset core`. A lone argument without `--` is a commit when it looks like one (a
SHA, `~`, `^`, `origin/x`, `refs/x`, `v1.2`, a task branch `net/40-x`, `main`) and a path otherwise, so
`git reset feature-x` passes.

#### 8.2.6 Other git that discards work or rewrites history
Passes in the own worktree on the task branch, and in a
repository outside the project (a clone in the scratchpad); it asks in the main checkout (but a cloud session's on
its task branch, above) and in another worktree
(`-C`, `cd`, `--git-dir`, `--work-tree`, `GIT_DIR`, `GIT_WORK_TREE`; the repository and the working tree are
judged apart and the worse wins), when a pathspec reaches another checkout (`git checkout -- ../47/core`), and
after the same command switched away from the task branch (`git checkout main && git reset --hard`, also inside
`bash -c`):
`checkout` of paths or `-f`, `switch -f|--discard-changes`, `restore` (not `--staged` alone), `clean` (not `-n`),
`rebase` (`--continue` and `--abort` too), `worktree remove|move` of anything but the own worktree's folder, an
absolute path inside it (a nested worktree, also `.../51/tools/out/measure/w$i` in a loop, #457) or an
absolute path outside the project (git also takes a worktree's last path parts: `git worktree remove 47`, so a
relative `tools/out/measure/w1` asks), `update-ref HEAD`. A pathspec the guard cannot resolve (`core/$f.gd` in a
loop, `$(git diff --name-only)`) is judged by the folder before its unknown part, because git refuses a pathspec
outside its repository (#457); a `..` after the unknown part, a folder or unknown part in or naming `.claude`,
`.git` or `addons` (`.claude/$f`, `$(ls .claude)`: it may be a protected path), and a cloud session's main
checkout keep the ask.
A plain `git switch x` or
`git checkout x` discards nothing and passes anywhere. Branches and the stash are shared by every checkout, so
they are judged by name: `branch -d|-D`, `branch -f`, `branch -M|-C`, `checkout -B`, `switch -C`, a rebase that
names its branch (not `HEAD` or `@`: git then rebases a detached HEAD and moves no branch),
`update-ref refs/heads/<x>` and a forced switch pass only for the task branch and its helpers;
`stash drop|clear` only for entries made on them (a human's `start --stash` entry is made on `main` and asks),
and never after the same command changed the stash (the indices shift); agents use no stash at all, a WIP commit
instead (root `CLAUDE.md`, Shell). An interactive rebase (`-i`, `--edit-todo`) is judged like any other rebase,
whatever editor it names (#457, [intervention](interventions/2026-10-06-engineer-git-free-in-own-worktree.md):
the engineer, 2026-10-06, "git is protected on GitHub"; it reverses #104's editor ask, after which a publisher's
`-c core.editor=true` waited 23 minutes on 2026-10-03 and #445's fix agent's `sed` sequence editor a night).
Claude Code's Bash and PowerShell tools set `GIT_EDITOR=true`, and this machine sets no `sequence.editor`, so no
editor opens; agents still write `git commit --fixup=<sha>` then
`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>` (root `CLAUDE.md`, Shell), because a machine
whose git config names a `sequence.editor` (`code --wait`) would open it and the call would run to its timeout:
`git rebase --abort` in the own worktree then ends it. A reword stays editor-free too, through an `amend!` commit
made with `git commit --allow-empty -F <file>` (its first line `amend! <subject>`), which autosquash applies as
`fixup -C`; `--fixup=reword:` and `--fixup=amend:` open the message editor (under `GIT_EDITOR=true` the reword
keeps the old message without a word; #456, the workflows' rules). Always asks: `rebase --update-refs` (moves
other branches), `rebase -x|--exec` (runs commands, a push among them, that the deny rules cannot see; a sequence
editor is such a command too, and passes since #457: the pre-push hook and GitHub's branch protection still stop a
push to `main` and a force push; a deliberate exception to #457's "every form", kept because the task forbade
weakening a push rule and left to the engineer on its PR), `update-ref --stdin` and `git -c core.hooksPath=...` (the deny rule on
`git config *hooksPath*` cannot see it).
Rebase options are read as git reads them (#105): a cluster letter by letter (`-qi`, `-qx cmd`), an attached
value (`-x'cmd'`), a unique prefix of a long option (`--interac`, `--exe=cmd`, `--up`), and `rebase.updateRefs`
from `git -c` or `--config-env` (any true value, unless `--no-update-refs` follows) like `--update-refs`. A nested
shell inherits its command's `VAR=value` prefixes (`GIT_SEQUENCE_EDITOR=: bash -c 'git rebase -i ...'` passes).

#### 8.2.7 `gh` aimed at another repository (issue #68)
Asks unless it only reads. The repository is the value of `-R|--repo`
(`-Rx/y`, `--repo=x/y`), `GH_REPO` (a prefix, `export` or `$env:`), a github.com URL argument
(`gh issue comment https://github.com/x/y/issues/1`), `gh repo <sub> x/y`, the destination of `gh issue transfer`, or
a `gh api repos/x/y/...` endpoint; `{owner}/{repo}` and this project's own `origin` (read from `.git/config` by
`hooks.GitFiles`, any spelling) are not another repository. Reads: `issue view|list|status`,
`pr view|list|diff|checks|status`, `release view|list|verify|verify-asset`, `repo view|list|clone`,
`run view|list|watch`, `workflow view|list`, `label list`, `cache list`, `ruleset view|list|check`, every `gh search`,
and `gh api` GET or HEAD (`-X GET|HEAD`, or no `-X` and no `-f`, `-F` or `--input` field: fields without `-X`
make it a POST). Everything else there asks, `gh issue create --repo godotengine/godot` included. The values of text options (`--body`, `--title`, `-f`,
`--jq`) never name the repository, and an option is never taken as the value of another one
(`gh pr create -d -R x/y`). A value it cannot compute (`$env:GH_REPO = (Get-Content f)`, `-R "$R"`) counts as another
repository. Out of scope: GraphQL mutations (a node ID does not say its repository) and a `gh` command run in a clone
of another repository without naming it.

**A repository of gh's own account passes like this project's** (#464, wanted by the engineer on 2026-10-06): when
the owner of the named repository is the account `gh api user` returns (`hooks.GitFiles.gh_user` reads its login from
gh's `hosts.yml`, in `GH_CONFIG_DIR`, `%AppData%\GitHub CLI` or `~/.config/gh`, without a network call; unknown when
`GH_TOKEN` or `GITHUB_TOKEN` is set), the guard leaves the command to the rules, as for this repository: on the
engineer's machine `gh issue create|comment|edit`, `gh pr create|comment|edit`, `gh label`, `gh repo create` and
`gh api` POSTs to `xperiaroco2/prime-game-art`, `xperiaroco2/prime-game-ui` or any `xperiaroco2/*` pass (30 asks on
2026-10-02 and 10-03 before, about 12.6 hours of waiting, one `gh pr create` over a whole night, #312). It also
fills in a variable the same command assigns (`R=xperiaroco2/prime-game-art; gh issue create -R "$R"`) and takes
an owner it can read alone (`-R "xperiaroco2/$1"`). On the designer's machine the account is the designer's, so the
engineer's repositories still ask there. What keeps the guard's ask in those repositories, because a spelling like
`gh pr -R x merge 5` slips past the rules' text: every `gh` command a deny or ask rule names (`pr merge|review`,
`repo delete|archive|unarchive|rename|edit|deploy-key`, `issue delete`, `label delete`, `project delete`, release
changes, `workflow run|enable|disable`, `auth`, `secret`, `variable`, `--delete-last`; `guard.GH_OWNER_KEPT`, a test
checks it against `.claude/settings.json`), `gh issue transfer`, and a `gh api` write that is not a POST or reaches a
`merges`, `merge`, `secrets`, `variables`, `keys`, `dispatches`, `releases` or `transfer` endpoint. Such a kept
command that names this project's repository asks too (`R=xperiaroco2/prime-game; gh pr -R $R merge 5`); a `gh api`
write here stays with the rules. The deny and ask rules themselves are unchanged: `gh pr merge 5 -R
xperiaroco2/prime-game-art` is still denied, `gh secret set` still asks. Any other owner (`godotengine/godot`, an
organization the account belongs to) asks as before.

#### 8.2.8 Targets and the prompt
- In a worktree session the rest of the project stays protected: `rm -rf D:/prime-game/core` and
  `git -C D:/prime-game clean -fdx` ask there.
- It resolves each target against the session's working directory, `cd`, and the variables the same command assigns;
  `$TEMP`, `$env:TEMP` and `~` are outside the project, so scratch copies never ask. A target it cannot resolve (an
  unknown variable, `$(...)`, a PowerShell `(...)` argument) asks when its text names a protected path. Content is
  not a target: `Add-Content .gitignore "addons/"` stays silent. Out of scope: scripts it would have to run, globs
  that match only by expansion (`a*ons`), `git apply`, `awk -i`, `ed`. It does not check ownership or the editor.
- The prompt appears in every mode, bypass included. 👤 Answer it with a one-time "Yes" or "No": "don't ask again"
  silences the guard for the rest of the session (verified live 2026-09-29).

#### 8.2.9 Replays
Each guard or permission change is replayed before it lands: `tools\run.cmd permissions --since <date>` (bypass mode
unless `--mode` says otherwise, `origin/main` against the branch) judges every Bash and PowerShell call of this
machine's transcripts both ways and counts prompts, denials and crashes; `--observed` lists what actually stopped
agents. The replay reads today's branches, temp folder and gh account, so it may undercount past asks (a deleted
worktree's call reads as a detached HEAD, which is free). The numbers are in the issues (#47, #51, #68, #312, #457, #464).
What they settled:
- The guard adds about 0.2 s to each shell command and has never crashed on a replay; no change made a call that was
  silent before ask.
- Its one known false ask: a heredoc whose text holds a delete (`shutil.rmtree('core')` in test data).
- Target-judged deletes and resets (#47): a scratch delete in `tests/scratch/` passes, one elsewhere in the project
  asks; the own worktree (#51) and git there on its task branch (#457) pass, including rebases with an editor setting.
- `gh` reads of other repositories (#68) and writes to the account's own repositories (#464) pass; a write to another
  owner's repository (an upstream bug report) asks.
- What still asks is right or a wrong command pattern: a manager's shell standing in another worktree, `git stash
  drop` (the stash is shared), deleting a release or another task's branch, writes to `addons/` and `.claude/`.
  Claude Code's own blocks were foreground `sleep`s (§11.17, "Bounded waits") and a `Remove-Item` beside a cmd.exe
  `/c` argument, read as its target: put such code in a `.ps1` file in the scratchpad and run it with
  `powershell -File`.
- Outside bypass, allow rules alone leave thousands of prompts (a `cd` into the scratchpad, `git -C`, `sed` on a
  variable's path, `GIT_SEQUENCE_EDITOR=: git rebase`, `bash -c`), so unattended work stays in bypass mode, and an
  `acceptEdits` session gets the guard's allow instead (#312, §8.2.10); there writes to a worktree's own `.claude/`
  still prompt.

#### 8.2.10 Unattended `acceptEdits` sessions (#312)
A route-C successor manager and its workflow agents always run in `acceptEdits` and cannot leave it (#484). There
Claude Code runs, besides the allow rules and its read-only commands, the file tools and `mkdir`, `touch`, `rm`,
`rmdir`, `mv`, `cp`, `sed` (and `Set-Content`, `Add-Content`, `Clear-Content`, `Remove-Item`) on paths in the working
directory, and prompts for everything else (`code.claude.com/docs/en/permission-modes`, checked 2026-10-07). So in an
**unattended** session in `acceptEdits` the guard's hook answers `allow` for a Bash or PowerShell call it finds
nothing to ask for (`hooks.pre_tool_use`, `guard.allows`): the call runs as it would in bypass.

Unattended needs a positive sign (`hooks.unattended`, fails closed): `CLAUDE_CODE_SESSION_ATTENDED` set to `0` or
`false`, or a session the desktop app started (`CLAUDE_CODE_ENTRYPOINT=claude-desktop`) without the variable. The app
sets it to `1` in a session a human opened (seen on 2026-10-07). A human's own `acceptEdits` session, both humans'
default mode (§2), keeps its prompts: a desktop session the app marks attended, and a CLI or IDE session (a terminal,
Rider), which never counts as unattended.

What still holds over the hook's `allow`: every deny rule, every ask rule, the guard's own asks, and Claude Code's
built-in checks (`rm` of a critical path such as a drive's top-level folder asks even in bypass; `Remove-Item` of a
wildcard or a system path is denied in every mode). The hook allows no shell write or delete
- to a path Claude Code protects (`.claude` but its worktrees `.claude/worktrees/<n>/`, `.git`, `.vscode`,
  `.gitmodules` and the others in `guard.CLAUDE_PROTECTED_DIRS` and `_FILES`, by the guard's targets and by inline
  code that writes and names one: `Analysis.protected`);
- beyond the session's own worktree, the temp folder (the scratchpad) and the disposable folders (`tests/scratch/`,
  `tools/out/`, `.godot/`), or to a path it cannot resolve (`Paths.free`, `Analysis.beyond`): the main checkout from
  a worktree, another worktree, a sibling repository, home. A `rm D:/prime-game/core/x.gd` from a worktree keeps
  Claude Code's own prompt, as deletes outside the agent's worktree must. A loop variable after a known folder
  (`$S/p$n.md`) counts as a file in it; one that starts the path (`rm $f`) does not.

Those keep Claude Code's own verdict. No hook can allow an Edit or Write under `.claude/`: so a task that edits
`.claude/` (a skill, an agent, a workflow, a hook) stops at its first such edit in an unattended `acceptEdits`
session, and a manager in that mode launches none (orchestrate-stage `handover.md` §3, "Mode and effort").
`tools\run.cmd permissions --mode acceptEdits` models the mode (the scratchpad counts as in scope, the model's
assumption; a session in a worktree, or in a folder inside one, as working in the main checkout) and judges every
session as unattended. Unverified until a route-C run shows it: that the hook's `allow` reaches a scheduled
session's workflow agents, and that a scheduled session carries one of the two signs above (if it sets
`CLAUDE_CODE_SESSION_ATTENDED=1` or runs outside the desktop app, the hook allows nothing and the run prompts as
before #312).

#### 8.2.11 The "nobody is watching" sign (#750)
A guard `ask` is a permission card, and a card has no timeout: while a call waits on one, Claude Code holds every
notification of that session (finished workflows, the keep-alive timer) until a human clicks it. On 2026-10-09 one ask
at 22:06Z kept the meta manager silent for 9 h 23 min (#731). The card shows in every mode, bypass included, so a manager
that runs while the engineer is away needs the guard to refuse instead of ask. That is the sign:

- **Set** by the manager before a night, from its own session: `tools\run.cmd unattended --until 07:30` (the next such
  local time; or an ISO time such as `2026-10-11T05:30Z`) or `--hours 9`. At most 16 h ahead; a longer one is refused.
  It writes `tools/out/unattended/<session id>.json` in the main checkout (any worktree writes there), with the
  session id from `CLAUDE_CODE_SESSION_ID`, so the shell must be the manager's own.
- **Cleared** by the manager when the engineer is back (his first message), before anything else: `unattended --off`
  (`--off --all` clears every session's; `--status` lists the signs). It also ends by itself at its time.
- **Effect.** In a call with the sign in force, every guard `ask` is a `deny` with the same reason plus one line:
  "unattended: put this command in the For-you block for the engineer". The agent gets an error and goes on; the
  command goes into the For-you block (MANAGERS §3). Nothing is allowed that was not before: the deny and ask rules,
  the guard's findings and Claude Code's own checks are unchanged, and a call the guard finds nothing in is left
  alone (the `acceptEdits` allow of §8.2.10 is a separate sign).
- **Fail-closed, per session.** The hook (`hooks.manager_sign`, read only when the guard would ask) counts the sign
  for a call whose `session_id`, or an id in its `transcript_path`, is the sign's session. A workflow agent's
  transcript sits under the manager's session id (`<session id>/subagents/workflows/<run>/`, seen 2026-10-10), so the
  manager's sign covers its agents. A human's own session has another id and no file, so it keeps its prompts, also
  when the manager forgot to clear the sign. No file, another session's, one that has ended, one that ends more than 16 h
  ahead, an unreadable or malformed one, or an id that is not a UUID: the ask, as before. Unverified until a night shows
  it: that the hook payload's `session_id` equals `CLAUDE_CODE_SESSION_ID` and that a workflow agent's call carries the
  manager's id in its `transcript_path`; if not, the sign changes nothing and the ask stays (`unattended --status` shows
  the sign; the first night's For-you says whether a guard ask still came).
- Out of scope (the engineer's answers on #741): a `Notification` hook, a Claude Code feature request.

### 8.3 Pre-push hook and publishing [applied]
Committed at `.claude/githooks/pre-push`; `doctor` sets `core.hooksPath` to `.claude/githooks` (the agent's own
`git config *hooksPath*` is denied). It blocks pushes to `main`, all deletions and force pushes (any non-fast-forward
update), with one exception: the **current task branch** `<area>/<n>-*` pushed by `tools\run.cmd publish`, which
marks its `--force-with-lease` push with `PRIME_GAME_PUBLISH=force-with-lease`. A force push typed by hand has no
marker and is blocked; `--dry-run` pushes run the hook too. A merge into `main` is GitHub's merge commit
(`tools\run.cmd merge <pr> --base main`, §7.1), never a push. The agent never force-pushes by hand
([ADR](decisions/2026-09-28-force-with-lease-on-task-branches.md)).
- The hook lives in the working tree. A checkout of a commit from before M0 stage 4 has no
  `.claude/githooks/pre-push`, and git then runs no pre-push hook at all (not even LFS's): only the deny rules and
  the server ruleset stand. Task branches start from `main`, which has the hook.
- `publish`: `git fetch --prune origin`, rebase on `--base`, else the open PR's base (a stacked PR's parent), else the
  parent `start --base` recorded, else `main`; then `verify` (unless an identical tree was just verified green, §4.2
  step 5) and the lease push. It stops before touching anything when the remote branch has a commit this branch never
  had (a suggestion committed on GitHub, "Update branch", a push from the other machine): the lease alone would not
  protect it, because the fetch just updated the expected value. A conflict aborts the rebase and leaves the branch as
  it was; a red `verify` pushes nothing. When HEAD already holds the base's tip (a branch that took `main` or the base
  in by a merge, #694) there is no rebase: it would drop the merges and replay what they brought in as the branch's own. After its parent was rebased or amended, a stacked child replays only its own
  commits: those after the parent commit `start` recorded (`branch.<task>.primeBaseTip`, renewed by each publish on the
  parent; `rebase --onto`), else those after the fork point (`--fork-point`, which needs the reflog of the parent's
  remote ref).
  After a hand rebase on a newer base (`git rebase origin/<base>` in the worktree), the merge-base of the branch and
  its base replaces a recorded tip it descends from, so the base's own commits are not replayed again (#113).
- A recorded base outside `<area>/<n>-<slug>` (a stage's `release/m<k>`, any long-lived branch) is never a done
  parent while origin has it, even when its tip is in `origin/main` (just created from `main` or fast-forwarded):
  `publish` keeps rebasing on it and keeps the record (#113). Once it is deleted (the milestone PR merged), the rule
  below applies.
- A recorded parent is done when the PR's base is `main` (GitHub retargets the child once the parent merges), its branch
  is gone from origin, or it is in `origin/main`. `publish` then rebases the child's own commits on `main` and drops the
  record, but only if the parent's latest known tip is in `origin/main`; otherwise (deleted unmerged, retargeted by
  hand, or rewritten after this checkout last saw it) it stops and asks for the human. `publish --base main` is the
  human's word that the parent is merged; it warns and lists the parent commits it leaves out (to keep an abandoned
  parent's commits in the child instead, unset both keys and publish). The record is local to the machine that ran
  `start`: on the other machine, before the PR exists, use `publish --base <parent>`.
- `core.hooksPath` switches off the hooks Git LFS installs in `.git/hooks`, so the hook runs `git lfs pre-push`
  itself. The other three LFS hooks only serve file locking, which the project does not use. With `core.hooksPath`
  set, `git lfs install` and `git lfs update` stop with "Hook already exists" and change nothing; use
  `git lfs install --skip-repo`, and never `git lfs update --force` (it would overwrite the pre-push hook).

### 8.4 `.gd` post-edit hook [applied]
PostToolUse on `Edit|Write`, for a project `*.gd` outside `addons/`, `tools/out/`, `.godot/` and `.claude/`:
gdformat and gdlint (20 s each at most), restore LF, then an engine load of that one file
(`tools/check/check_project.gd`) within 60 s, so the whole hook fits its 120 s timeout. When
the engine reports errors, it imports once (a new `class_name` may be missing from the class cache) and loads again
in the same budget. Problems → exit 2 with `file:line: message`; a reformat or engine warnings reach Claude as
context ("Read it again before the next Edit"). About 2 s per edit, 8 s when the file has errors. A shell write to a
`.gd` does not trigger it; `lint` in `verify` and CI covers that. Autoloads must be side-effect-free under
`--check-mode`.

### 8.5 Server side 👤
A ruleset on `main` of the public repo: block force pushes, restrict deletions, require a PR. The required status
check `verify` is added **after the CI PR has merged**. Code-owner review stays off. No bypass for admins.
- **Live state (read 2026-10-04 with `gh api .../rules/branches/main`):** `main-1` blocks deletions and
  non-fast-forward pushes; `main-2` requires a PR (0 approvals) and the checks `verify` and `runner on the minimum
  Python` (the job `python-min`, added by the engineer on 2026-10-04 after #358), both from GitHub Actions. Neither
  has a bypass: the engineer removed `main-2`'s admin bypass on 2026-09-29, so the admin account the agents push as
  cannot skip them either. A cloud session cannot change a ruleset: its GitHub proxy refuses writes to that API path
  (HTTP 403), so a ruleset change is the engineer's step in the repository's settings.
- **Classic branch protection** on `main` too (read 2026-10-15 with `gh api .../branches/main/protection`, #1123):
  a PR with 0 approvals, no required checks of its own (the ruleset's apply), force pushes and deletions refused,
  admins not enforced. The rulesets above are the gate; it adds nothing they lack.
- A design-only pull request (#1123, §4.2 step 1) skips CI's Godot parts but still reports both required checks: the
  trigger has no path filter, and `verify` and `python-min` always run.
- "Automatically delete head branches" is on: a merged PR's branch is deleted, and GitHub retargets its stacked
  children to `main` itself.

## 9. Ownership

([ADR](decisions/2026-09-28-ownership-by-codeowners-and-convention.md))

| Owner | Paths |
|---|---|
| Engineer | `core/ server/ net/ client/ voice/ tools/ tests/ addons/ assets/ .github/ .claude/ project.godot export_presets.cfg CLAUDE.md README.md docs/{ARCHITECTURE,AGENT_WORKFLOW,ROADMAP,PLAYING,MANAGERS}.md`, and the **content area**: `content/ levels/ docs/GDD.md docs/design/ .claude/skills/{new-mechanic,new-level-piece}/` |
| Designer (optional) | none of his own: he may contribute anywhere, mostly in the content area, through PRs the engineer merges |
| Shared | `docs/interventions/ docs/decisions/ docs/credits/ docs/history/ CREDITS.md .claude/rules/` |

- Enforced by **`.github/CODEOWNERS` and the rules in `CLAUDE.md` files**, not by a hook.
- **The designer is optional** (the engineer's decision of 2026-10-07,
  [#170 comment 6037210189](https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6037210189) point 3;
  #518). The engineer owns the content area and its two skills. It replaces the designer's area and the **relayed
  agreement** of 2026-10-01 ([intervention](interventions/2026-10-01-engineer-relayed-design-agreement.md), kept as
  history): no "agreed with the designer" line and no tag are needed any more.
  - Agents change the content area (rebalance or redesign content, edit `docs/GDD.md`, `docs/design/` or `levels/`)
    on the engineer's word: the issue, his comment or his chat. Without it they stop and ask. They never invent
    content (names, numbers, rules) nobody decided: options with a recommendation go to the engineer.
  - Nothing waits on the designer: no step, review or merge needs his approval.
  - The designer may still contribute: his PRs go to the engineer, who reviews and merges them (§10). His agent never
    edits engine code: a missing primitive becomes an `engine-request` issue with a precise spec, and the agent
    continues with data (`content/CLAUDE.md`, `levels/CLAUDE.md`).
  - A scene with someone else's open PR is still never edited (`gh pr list --state open --json number,author,files`).
- **The engineer is the project lead and the game designer** (his word of 2026-10-15, #1073): game design, narrative,
  taste and the pillars are his decisions alone, never "agreed with the designer"; the designer may still help now and
  then, as above.
- The gate of `merge <pr> --base main` (§7.1) refuses a PR not authored by the engineer's account, or run outside the
  engineer's sessions, so the designer's PRs reach the engineer. A PR into `main` that changes the content area merges
  through it once its body has "Approved by the engineer: <GitHub link>", as an ADR does (the engineer's answer (b) on
  [#563](https://github.com/xperiaroco2/prime-game/issues/563#issuecomment-6057446276)): the publisher lists the
  `content/` and `levels/` files as provisional, and the manager adds the line, linking the engineer's approval
  recorded on GitHub; the designer's review and the old relay phrase clear nothing. A milestone's closing PR clears it
  with the engineer's go, the same line. `.claude/settings*.json`, `.claude/githooks/` and the guard are always the
  engineer's to merge ([trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)).
- MVP content: the engineer's agent builds the MVP's `content/` data and `levels/` scenes, each PR with the
  engineer's explicit approval and marked provisional
  ([ADR](decisions/2026-09-29-mvp-content-built-by-the-engineer.md)).

## 10. GitHub coordination

- **Repo:** public, GitHub Free ([ADR](decisions/2026-09-28-public-repo-on-github-free.md)). The Phase A archive
  is published as is.
- **Merging:** the engineer's manager merges into `main` through the gate of `tools\run.cmd merge <pr> --base main`
  (§7.1, [trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)); the gate's exceptions and
  the designer's PRs are merged by the engineer, with the Merge button on GitHub or in the Desktop PR pane, after CI
  is green: he reviews the designer's PRs, and no PR waits for the designer (§9). Content and levels are judged
  through `shot` screenshots and a playtest, never the diff ([ADR](decisions/2026-09-28-humans-merge-prs.md)). In a
  stage the manager merges task PRs into `main` through the gate (§7.1,
  [ADR](decisions/2026-10-01-release-branch-per-milestone.md)).
- **Board:** a Project owned by the engineer, linked to the repo; the designer is invited to the project and the
  repo. Built-in workflows: keep closed → Done and PR merged → Done; item added → Backlog; disable
  "PR linked → In progress". Agents set only In progress and In review, via `tools\run.cmd board move`.
  👤 Both humans run `gh auth refresh -s project` and upgrade gh to ≥ 2.97.
  **[applied]** [Project 1](https://github.com/users/xperiaroco2/projects/1) "prime-game", linked to the repo, with
  a Status field Backlog → Ready → In progress → In review → Done and a "Board" view.
  `tools\run.cmd board move <issue> in-progress|in-review` adds the issue if needed and sets the column; it refuses
  pull requests and closed issues. The built-in workflows can only be set in the web UI; **verified live
  2026-09-29:** "Item added to project" and "Item closed" and "Pull request merged" on, "Pull request linked to
  issue" off, plus GitHub's default "Auto-add sub-issues to project" on. `gh issue create --project prime-game`
  lands in Backlog within about 2 s. A `board move <n> in-progress` right after the add is **not** overwritten:
  #12, moved within 3 s of its creation, still read In progress 79 s later (then set back to Backlog by hand).
- **Issue templates [applied]:** `feature`, `mechanic`, `bug`, `engine-request`, `intervention` in
  `.github/ISSUE_TEMPLATE/`, as Markdown with front matter, plus `.github/pull_request_template.md`. Agents build
  bodies from them and pass `--label` explicitly.
- **Labels and milestones [applied]:** one area label per folder, `area:core`, `area:server`, `area:net`,
  `area:client`, `area:voice`, `area:content`, `area:level`, `area:tooling` (KICKOFF §5.1 plus `server` and
  `client`, the engineer's choice on 2026-09-29), and `blocked`, `needs-design`, `needs-engine`; milestones `M0` to
  `M7` with the
  roadmap goals.
- **CODEOWNERS [applied]:** `.github/CODEOWNERS` mirrors §9. The designer is `@SwiftySinister` (since 2026-09-30,
  #85); since #518 he appears only on the shared paths, and the content area falls to the engineer's `*` line. GitHub
  accepts an owner only once they have write access, so the entries count from the accepted invitation.
- **ADRs:** `docs/decisions/YYYY-MM-DD-<slug>.md`, never sequential numbers, so two branches cannot collide on
  the same number. Short: status, date, deciders, context, decision, alternatives, consequences.
- **Append-style logs are one file per entry** ([ADR](decisions/2026-09-28-one-file-per-entry-logs.md)):
  interventions in `docs/interventions/YYYY-MM-DD-<who>-<slug>.md`, asset credits in `docs/credits/<asset>.md`.
  `/log-intervention` writes the entry and promotes the rule in the same PR; each promoted rule carries a
  `<!-- see docs/interventions/… -->` comment.
- **Credits [applied]:** one file per asset or pack, `docs/credits/<asset-slug>.md`: a `# <name>` title, then
  `- **Files:**` (repo-relative globs in backticks; `*` stays in one folder, `**` crosses folders), `- **Author:**`,
  `- **Source:**` and `- **License:**` lines; more fields and free text are copied as they are
  ([example](credits/gdunit4.md)). An entry that covers an LFS asset also has `- **AI generated:**` and
  `- **Public repo OK:**`, each `true` or `false` first (the art manifest's `ai_generated` and `public_repo_ok`,
  #519; the art handoff: `docs/ARCHITECTURE.md` §11), and `check` refuses `Public repo OK: false`. A file the engineer
  adds by hand later gets its entry first with `- **Pending:** <what lands, and how>`: its globs may match no file
  yet (#520, the Comfortaa font); `check` warns about it, and fails once every glob matches a file until the line
  goes.
  `tools\run.cmd credits` writes `CREDITS.md` from them; nobody edits it by hand.
  `check` fails when a file that `.gitattributes` routes through LFS, outside `addons/`, matches no entry (untracked
  files count, so it fails before the commit), when an entry's glob matches no file, and when `CREDITS.md` is out of
  date. `addons/` is exempt from the check (its code keeps its own LICENSE and its images stay out of LFS), but each
  addon still gets an entry.
- **LFS in CI [applied]:** CI checks out without LFS content, so each LFS file is a pointer file there. `check`
  imports a stand-in of its type in its place (an image, a WAV, a glTF, GLB or OBJ; other types are kept out of the
  import) and drops the project check's lines about the rest, in one `skip` line; the credits check still covers
  them; locally nothing changes. A build runs `check --lfs-content`, which fails on any pointer file
  ([ADR amendment](decisions/2026-09-29-git-lfs-for-binary-assets.md), #515).

## 11. Godot specifics

### 11.1 Stack ([ADR](decisions/2026-09-29-technical-stack-from-the-brief.md))
Godot 4.7.2 standard build (not .NET),
typed GDScript, GdUnit4, gdtoolkit, ENet behind a transport abstraction, Opus voice (M1 spike decides the addon).
Native Windows first, never WSL: the agent runs the Godot `*_console.exe`, humans the regular exe. Binary assets go
through Git LFS, `addons/` stays outside it ([ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md)).

### 11.2 Editor convention ([ADR](decisions/2026-09-28-godot-editor-save-first-convention.md))
Nobody edits by hand
while an agent works. Before asking the agent for anything, Scene → **Save All Scenes** (Ctrl+Shift+Alt+S;
Ukrainian UI «Зберегти всі сцени»). If Godot asks about files changed on disk, always choose **Reload from disk**
(Ukrainian UI: **«Джерело отримання»**; never «Ігнорувати зовнішні зміни»). The agent reminds the human; nothing blocks. Headless runs next to an open editor were verified in M0.

### 11.3 `.tscn` / `.tres` ([ADR](decisions/2026-09-29-hand-written-scenes-then-normalize.md))
The agent hand-writes
readable text and never copies a uid or a `.uid` sidecar; `tools\run.cmd normalize <files>` **[applied]**
re-saves them in headless editor context (`--headless -e -s`, after the first file-system scan), which adds the
header uid and node `unique_id`s the editor would. A second run leaves the file byte-identical. Godot drops a property it does not know (a typo), one at its default, and any line
after a parse error, without an error: `normalize` compares property keys before and after, and on a loss restores
the file and fails. `check` reads each `content/**/*.tres` as text and fails on a key no stored property of its
section's class has, with file and line (`tools/check/content_keys.gd`, #1238), so a misspelled key that skipped
`normalize` still fails CI. `check` also fails on UID problems, on files left modified by `--import`, and on an `ext_resource`
uid that resolves to a different file than its `path=`. Godot 4.7.2 sometimes dies of an access violation (exit
3221225477, 0xC0000005) while it shuts down after `check_project.gd` printed a clean summary (#442: 2 of 326 check
steps, the summary their last line, none of the shutdown lines every run prints after it): `check` passes such a run
with a `GODOT CRASHED AT EXIT` warning and keeps its output in `tools/out/logs/check-exit-crash.log`. A crash before
the summary, after an error or with another exit code stays red, and nothing is retried. In `verify` such a pass also
reaches the summary row (`passed  check  28.3s  (Godot crashed at exit, #442)`, so publish's verify tail and the PR
body carry it), the step's history record (`exit_crash: true`) and `metrics`' crash rate over the window (#449).

### 11.4 `shot <scene>` [applied]
A real window off every screen, never headless or minimized (Godot then never draws). `--position -30000,-30000`
alone does not do it: Godot 4.7.2 on Windows clamps a new window into the primary screen, so each shot window stood
at the top-left corner at full size (1282x752) for 1.5 to 3.9 s (#1141). The runner (`tools/runner/offscreen.py`)
starts it as one pixel at `--position 30000,-30000 --resolution 1x1` with the size it wants in `PRIME_WINDOW`; the
window script calls `tools/offscreen/offscreen.gd` `place()` first, which moves it to -30000,-30000 with
`DisplayServer.window_set_position` (no clamp), grows it and prints an `OFFSCREEN window <x>,<y> <w>x<h> screens ...`
line. The runner fails a run whose line is missing or whose window meets a screen. What a window watcher still saw:
the frame's 1 px left border, 2 px tall at the top-right corner, until `place()` (0.5 to 0.8 s for a shot, 3.7 and
4.9 s for playcheck's two windows); the game keeps its title bar and focus (no command-line flag makes a window
borderless or unfocused). The pictures are unchanged: pixel-identical for `probe.tscn` and the attic; the End
screen of `client/dev/end_preview.tscn` fades in over 0.4 s of real time, so its background differs by 1 to 2 levels
between two runs of the same code too. A 60 s watchdog, a PNG in `tools/out/shots/`. A scene with no camera (a level
piece) gets one that frames all its geometry, plus a light if it has none. It prints the driver it drew with
(`renderer: vulkan forward_plus`; the runner's `--no-header` hides Godot's own line). Desktop only: CI never runs it, and the human
gets the PNG to drag into the PR (`gh` cannot upload images). `tools/shot/probe.tscn` is its smoke test.

### 11.5 `run <scene.tscn | script.gd>` [applied]
Runs a scene, or a `-s` script that extends `SceneTree`, with the
pinned Godot; arguments after `--` reach `OS.get_cmdline_user_args()`. `--headless` uses `GODOT_BIN`; a window
uses `GODOT_GUI_BIN` (else `GODOT_BIN`), and `--offscreen` keeps it off-screen as `shot` does (§11.4): a scene runs under
`tools/offscreen/offscreen_scene.gd`, which places the window first; a `.gd` target calls `Offscreen.place()` itself or
the run fails with "no OFFSCREEN line". `--seconds N`
(default 60) kills the process tree; `--instances N` (up to 8) starts N copies at once, each with
`PRIME_INSTANCE=<i>` in its environment and its own log `tools/out/logs/run/<name>-<i>.log` (the next run of the
same name replaces them). `--audio dummy` (default) or `default`; `--headless --audio default` keeps the real
audio driver (`--display-driver headless`). Fails when an instance exits non-zero, times out or prints an
`ERROR:` / `SCRIPT ERROR:` line (Godot exits 0 after both), and names the instance and its first error lines. A
scene that never calls `quit()` therefore fails at `--seconds`: read its log. The agent's own checks run
`--headless` (never a window while a human uses the machine). It imports the project first when the import is not
current (the next item). `tools/run/probe.gd` is its smoke test.

### 11.6 The import before a launch [applied] (#174)
`host`, `join`, `run` (and through it `perf` and `bots`),
`playcheck`, `shot` and `verify`'s `game` step import the project before they start Godot when a file Godot sees
changed after the last import through the runner, since only an import rebuilds the global class cache (a game
started after a `git switch` that brought a new `class_name` printed `Identifier "MousePointer" not declared` in
the engineer's playtest). No `check` is needed after a `git switch`, a pull or new scripts or assets. One line
says which: `import: current (1489 project files unchanged since the last import, 0.03s)`, or
`import: res://client/app/game.gd changed after the last import; importing the project first`, then
`import: done in 11.3s`. Every import through the runner (`check`, `test`, `mutants`, these and the `.gd` post-edit
hook's) records when it started in `.godot/runner_import.stamp`, or the time of the newest `.uid` or `.import` file
it wrote itself, never a time after the import ended; the
test compares the modification times of the files Godot sees (no hidden folders, none with a `.gdignore`, no
Markdown, Python or shell scripts) with it: git gives every file a switch, pull or rebase writes the time it
arrived. Measured on the engineer's PC: 0.03 to 0.04 s for the test, against 9.9 s for a quick import that
finds nothing to do (11.3 s after one changed script, 17.7 s after a `git switch`), so the import is not always
on. A file dated in the future (clock skew, or copied with its original time) makes every launch import, with a
`warn` line that names it: `touch` it. An import by the editor is not recorded: the next
launch through the runner imports once. A linked worktree's `override.cfg` (#182) is written before the test and
the import, so the import uses the worktree's own `user://`.

### 11.7 `mutants <spec.json> [--seconds N]` [applied]
(#184; item 4 (b) of the
[AI productivity ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md), the tool of `issue-task`'s
`test_review`): shows that a change's tests fail when its code is wrong. Each mutant of the spec names a tracked
`file` under `core/ server/ net/ client/ voice/`, the 1-based `line` on which `original` (exact text, which must
start there once) begins, its `replacement`, and the `tests` (files or folders under `tests/`) that should catch it;
`mutants --help` prints the format. A mutant on a `class_name` or `extends` line is refused: the scratch tree is
imported once, so its global class cache would be stale. It refuses a dirty worktree (the mutants run HEAD) and runs nothing on an
invalid spec. A run never writes the task's tree, so a run killed half-way (a 600 s Bash limit, a stopped
workflow) cannot leave a planted fault for the publisher to commit: it makes the scratch worktree
`tools/out/mutants/tree-<checkout folder>` (`git worktree add --detach` of HEAD; a start first removes one a killed
run left), copies the checkout's `.godot` import cache and its files' modification times in (Godot then rechecks
nothing: the import takes about 7.5 s, 10 to 11 s afresh), imports it once, runs every named test once without a
mutant (a red baseline makes every mutant an `error`), then plants each mutant there, runs its tests (`test` without
the import) and restores the file: `killed` (a named test failed; they are listed), `survived` (a finding, not a
failure) or `error` (the mutant does not compile, `--seconds` (default 300) ran out, or the tests could not judge;
the reason and the log). At the end it removes the scratch worktree (and its `user://` folder, §11.18), also after an
exception, and confirms the task's `git status` unchanged. A `tree-*` folder that `git worktree remove` leaves is
deleted with `common.force_rmtree` (#453; the runner tests clean up with it too): git's read-only files are made
writable, a path a git process removes meanwhile counts as deleted, and every other error is reported. A lock in
`tools/out/mutants/` allows one run per checkout (the OS releases it when a run is killed). The table is printed
and written to `tools/out/mutants/<spec name>.md` after every mutant, with each test run's output and Godot's log in
`<spec name>-<step>.log` beside it. Exit 0: the run completed, whatever the results; 1: an invalid spec, or a run
that could not start or finish (a dirty tree, another run, a failed import), nothing left behind; 2: the scratch
worktree could not be removed or the task's tree changed: run no more mutants and tell the human (`git worktree
list` shows it; the next run removes it first). One mutant takes about 17 to 19 s with small suites (setup about
9 s, baseline and mutant about 4 s each), several or tests that name all of `tests/` far longer (two full runs:
596 s while other worktrees verified), so every agent runs `mutants` in the background and polls `wait <log>` (the
"Bounded waits" of §11.17; `mutants --help` prints both lines, #435); the report file shows the progress meanwhile.
The runner's own git commands are not the session's shell commands, so the guard judges only `tools\run.cmd mutants
<spec>`, which passes from a task worktree and the main checkout; a hand-typed `git worktree remove` of the scratch
tree asks (§8.2.6).

### 11.8 `host` and `join` [applied]
(3i, #103; windows since #149; `docs/ARCHITECTURE.md` §4.6 and §4.7, the M4 ADR's
E20): the game over ENet. `host [--port P] [--clients N] [--local] [--seconds S]` hosts on every interface, or on
127.0.0.1 only with `--local` (no firewall prompt), and with `--clients N` (up to 7) starts N clients that join it
on 127.0.0.1 once it hosts. `join <address> [--port P] [--seconds S]` joins a host. The default port, 24600, is a
placeholder ("not a decision"). Each process gets `PRIME_INSTANCE` (1 the host, 2 and on the clients in tile order),
so each window keeps its own settings file (`user://settings.cfg`, `settings_2.cfg`, ...; the M5 ADR §1.7).

The runner echoes every process's lines live as `[host]`, `[client 2]` or `[join]` (a label is a process, not a
player: client 2 may become Player3) and keeps each in `tools/out/logs/session/<label>.log`. They run until
Ctrl+C, `--seconds S` or every process ending (every window closed); the stop is clean (a stop file each process
polls: the host closes, so the clients see `host_lost` at once), and a process still running 10 s later is
killed (the report names its last line and when it came; one that stopped says how long it took). Each process
also stops by itself once the runner's alive file (touched every second) is gone or 10 s old, so a killed runner
leaves no session holding the port. Fails like `run`: a non-zero exit or an engine error line. The agent's own
checks pass `--local --seconds S` (never without `--seconds` in the foreground). On Windows, Ctrl+C in
`tools\run.cmd` ends with cmd's `Terminate batch job (Y/N)?`: the session has already stopped, so either answer
is fine. Its selftest runs a headless host and two local clients to the full lobby
roster and builds the windowed command lines without starting Godot; `verify`'s `game` step runs the game
scene headless through its command line (§11.16 CI).

#### 11.8.1 Windows (the default for a human)
Each process is the game, `client/app/game.tscn`, started with the
command line `LaunchOptions` reads (`--host [--local]` or `--join=<address>`, `--port=`, the stop and alive files
above), so it skips the menu and goes straight to the lobby. A host and its `--clients` are tiled over the primary
screen (`--position`, `--resolution`); a windowed host on every interface prints what to type on another PC. A
host that cannot listen stays at its menu with the reason, and its clients do not start. A window never welcomed
into a lobby (it could not host, or its join ended) fails the run with the reason, though the game exits 0.

#### 11.8.2 `--headless`
M3's `tools/run/headless_session.gd` (a `HostSession` and its own `ClientSession` of the base
mode). Each process prints `session:` lines: the roster (`Player1 [1] ready, Player2 [<peer>]`), the phase, and
the counters (the transport's rejects and LATEST merges, the client's undecodable messages; on the host the
budgets' `over_budget`, `bad_payloads`, `malformed_disconnects` and `voice_dropped`) when they change, at most
once a second; a refused join says why in words (`wrong_version`, `wrong_content`, `joins_closed`, `full`, no
answer). Exit 1 is a refused or unanswered join, a client stopped before `Welcome` or ended by anything but its
host, or a host that cannot start or ends for an error.

#### 11.8.3 An agent's shell (`CLAUDECODE` is set)
Gets `--headless` by default, so an unattended run never opens a window
on a human's screen; `--windows` opens them there, and agents never pass it. A human who asks an agent for
windows ("запусти хост і двох клієнтів") gets the command to run in their own PowerShell, starting with `cd`.

### 11.9 `bots [scenario ...]` [applied] (#102; `docs/ARCHITECTURE.md` §4.6, §9.7)
Plays every bot scenario in
`content/scenarios/` (or those named) through `HostSession` and one `ClientSession` per bot, in one headless process
over the loopback on a simulated clock (60 steps per simulated second), and asserts the information-leak test (§5
there) for every bot, a lurker and a refused bot. `--instances N` (N > 1) plays one
scenario of N bots over ENet on 127.0.0.1 on a free port, one process per bot, on the real clock; `--seconds`
overrides the timeout (300, over ENet 180). It runs `tests/harness/bots/bots_main.gd` through `run`, so `run`'s
failure rules apply. A failed scenario prints its seed and each failure (the bot, its step, its last events) and
writes the command log that replays it (`ReplayFiles.read`, then `Match.replay`) to `tools/out/bots/<scenario>/`,
next to each bot's view file `bot-<i>.bin`; every run starts with that folder empty. Over ENet a scenario step that
needs two events in one poll (an `Expect` with `within_s` 0 after a `WaitFor`) is timing-dependent
(`dropped_at_the_loading_deadline` failed once in four runs); a failure there is not a leak by itself
(ARCHITECTURE §4.6).
`bots --chaos [--seed N] [--runs K] [--long] [--enet]` (#188; `docs/ARCHITECTURE.md` §4.6.5 "Chaos bots") runs the
chaos bots instead: `tests/harness/chaos/chaos_main.gd`, a hostile player and a malformed peer against the host
beside honest bots, for K seeds from N (without `--seed` a random one, printed first, so a failed night run names
the seed that replays it); per seed a baseline with the chaos peers idle, the chaos run and one with hidden roles
swapped, in one process over the loopback; `--long` is the match in which the hostile also dies, `--enet` one run
over ENet on 127.0.0.1 on a free port (the invariants only). A failure prints `CHAOS seed <n>: FAILED` and each
broken rule (the input, the phase and life state, what was expected and what came).

### 11.10 `perf [--bots N] [--seconds S] [--enet] [--baseline FILE]` [applied]
(#187; item 6 of the [AI productivity
ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md)): the host's cost with 10 bots, measured
from the harness (`tests/harness/perf/`, ARCHITECTURE §9.7); nothing in `server/` or `net/` changes. One seeded
match (every bot readies, walks a spoke across the greybox, the round ends by time up after S seconds, default 60)
in one headless process: over the loopback on the simulated clock at `--fixed-fps 60` (about 10 s for a 20 s
round), or with `--enet` over real sockets on 127.0.0.1 on the real clock (the round's length and more). It writes
`tools/out/perf/<date>.json` (UTC; `-enet` over ENet, `-<N>b<S>s` for a run other than 10 bots and 60 s) and
`summary.md`: p50/p95/max of the host step (`Time.get_ticks_usec` around `HostSession.step`, steps that ran a tick;
inside it the harness's meter only appends to a buffer, folded after), `TIME_PHYSICS_PROCESS` (read about once a
second, host and bots together; how the engine refreshes it between reads is not documented), events per tick, each
`Snapshot`'s payload bytes per remote peer per tick, frame bytes per remote peer per second down (all, snapshots,
the bots' synthetic voice) and up (not voice, and voice frames), and `MEMORY_STATIC`; next to them the wire budgets
and their headroom (the 1024-byte unreliable cap, E7's per-peer budgets, E11's tick on `VoiceBatch`). It compares
with `--baseline`, else `tools/out/perf/baseline.json`, else the newest earlier report of the same transport, bots
and round, and lists every metric that moved by more than 20% (a placeholder, not a decision); only a failed match
fails it. Not a `verify` step: the nightly job `perf` runs it (§15). Copy a report you trust to `baseline.json` to
pin the comparison. The pinned Godot is a debug build (unoptimised GDScript): compare runs with each other, not
with a release host's cost.

### 11.11 `wave --since T [--base B] [--plan N] [--title T] [--notes FILE] [--stage-since T] [--no-merge-check] | --args <n> [--workflow NAME] [--session ID] [--out FILE] | --stalled [--minutes M]` [applied]
(#277, #278; round 2 of the AI productivity track, a
cheaper manager): a manager session's workflow runs and their handover data, read-only from its transcript and the
journals, and with `--since` the whole wave comment, so status gathering and wave reports cost the manager one
command. Sources: the manager's `<session>.jsonl` in one pass (each Workflow call's input `{name or scriptPath or
script, args, resumeFromRunId}`, paired by `tool_use_id` with its result's `toolUseResult` `{runId, taskId,
workflowName}` or the "Run ID: wf_..." in its text; each task notification, from its queue `enqueue` record or its
user record, paired by `<tool-use-id>`; the API calls and the title) and each run's `journal.jsonl` through
`metrics.read_run`. A notification's `<result>` is cut at about 8 kB, so PR, CI, published, not fixed, needs engineer
and human steps come only from the journal (the publisher's result, else the pr-rebase fix's, else the rebase's; human
steps from every agent, each once); the notification gives the status (completed, failed, killed) and whether its
result says `"stopped"`. `--since T` writes a wave comment's body (default `tools/out/wave/wave-<session8>.md`, UTF-8;
it prints the path and its own run time) with eleven sections in this order, each a function in `wave.py`'s
`SECTIONS`: a title (`--title`, default "Wave report since T") with a header line (the plan issue `--plan`, the base,
the window); the manager's own judgement from `--notes FILE` as written (decisions, batched questions, the order from
here; a BOM and CRLF are dropped); the PRs merged into the base (`--base`, default main) since T (number, title,
branch, merge time and commit, closing issues or the branch's issue); the runs finished since T (a "relaunch fresh,
never resume" flag when the outcome has published false, a publisher stopped on `mutants` exit 2, issue-task stopped
on a red implementer (the last one: one that handed over under `checkpoint` is followed by a continuation, #559), a
pr-rebase rebase is red or unpublished, or the result says stopped; other workflows, such as a
read-only scouting run, are listed by their name with no issue), the running runs (title, worktree, branch, base, the
agent working now: each `started` with no `result`, and the minutes since the launch and since the newest write to the
run's journal or agent transcripts, which tell a live run from one whose session died); the open PRs into the base and
those stacked on them (issues, base, draft, a CI cell from `statusCheckRollup`: red beats pending, else green, "none"
when nothing reported; `mergeStateStatus`); merge safety (`merge-check --base B` with its printed lines captured: its
exit code and verdict line, and only when it flagged something or failed its tables and details exactly as printed;
`--no-merge-check` skips it and its `git fetch`); the cost (what `metrics --since T --session <this session>
--compact` prints, computed in memory with no metrics file written, from metrics' transcript cache (§11.12), plus
with `--stage-since S` the stage's `total API list $` and `% of a Max 20x week` lines; `COST_EXTRAS` in `wave.py`
takes more lines over metrics' JSON record, the hook for #314); housekeeping (below); the handover args of each
running run and of each failed, killed or stopped one that no later launch of its issue and workflow has replaced
(the args exactly as passed, `indent=1`, `ensure_ascii=False`; a resume without args inherits its run's); and a
footer (the session's age, its last call's context, the mean API list $ per call of its first and last 20 calls, and
any records it skipped), whose last line, also stdout's last, is the handover verdict: `handover due: <why>` or `handover not due` with its clauses (#467; the
orchestrate-stage skill's §7 turn-end check; thresholds 500k and, at a stop for the human, 250k, #511). A due verdict
ends with the successor (#511, `docs/MANAGERS.md` §6): the handover comment's notes end with the ready kickoff the human
pastes; route C (`update_scheduled_task <track>-manager` with a `fireAt` 3 minutes ahead) only if he asked for it, the
track read from the `Track:` line of the session's kickoff (as `metrics --track` reads it, inside a scheduled task's
frame too). With runs in flight it adds the rule while the human is away: launch nothing new and post the handover
once they end. Above the verdict, an `Instructions:` line (#930; never a handover) names the PRs merged into main
since the session's first record that changed root `CLAUDE.md`, `docs/MANAGERS.md`, `.claude/rules/` or
`.claude/agents/` (one `gh pr list --base main --json files`; `gh pr view <n> --json files` for one the search lags
on) with the `git diff` from origin/main at that start, and the main checkout behind origin/main on those paths (`git
diff --name-only HEAD...origin/main` there); the rule is in `wave.py`'s docstring. A section says
"None." when it has nothing, and "Unavailable: <error>" (with a warn line) when its source failed: the rest of the
body is still written and `wave` exits 0. Housekeeping, from `git worktree list --porcelain` in the main checkout: one
fenced PowerShell block per command (`cd D:\prime-game; tools\run.cmd worktree-done <n>`; for the manager's
`release-m<k>` worktree its `git worktree remove` and `git branch -D`) for each worktree whose branch's PR merged and
whose work is on main (directly, or through a release or parent branch whose own PR into main merged later), with no
running run of this session there, its HEAD at the merged head and no live Claude session in it; the manager runs
those itself (orchestrate-stage §8 in `notifications.md`, the trust ADR). The section's first line, which the manager
lifts into its chat message, names only what needs the engineer, a worktree a live session holds: `For you: close the
Claude session in worktree <n> (...), then run its block below.` (`For you: nothing.` when none; the ready blocks stay
out of it, #343). The other cases are one-line waits (after `release/m<k>` reaches main, a run still running there, HEAD
not the merged head). It also names the issues still open whose PR reached main since T. One `gh pr list --state merged
--search sort:updated-desc` (the 500 most recently updated, every base; gh's default order is by creation) serves the
merged section and housekeeping (gh's `merged:>=` search is date-only, so mergedAt is filtered here); when gh returns
all 500, the merged section names the oldest update among them, before which a merged PR (and its worktree) may be
missing. A body over 60,000 characters (GitHub's limit is 65,536) moves its handover data, each run's block whole, to
`<out>-2.md` (and `-3.md`, ...), posted as the next comments; the first body says so, every path is printed, a part one
run's args alone push over 65,536 gets a warn, and a part left from an earlier run is named, never deleted.
A run is finished when its latest launch has a notification or its journal reached the script's end (issue-task: a
publisher result, or a red implementer with no publisher; pr-rebase: a fix result, a red or unpublished rebase, or
every reviewer answered with no blocker or major left to fix). `--args <n>` prints only the JSON of issue n's newest
launch on stdout (the run, workflow and time on stderr; `--workflow issue-task` or `pr-rebase` picks one; `--out` also
saves it, best for Cyrillic from PowerShell 5.1) and exits 1 when n has none; the `--since` flags are refused with it,
and it reads nothing beyond the transcript. The session defaults to `CLAUDE_CODE_SESSION_ID`; an id prefix works. It
writes only its `--out` file(s) and posts, edits and launches nothing: `gh` is only read, and merge-check's `git
fetch` (with any PR head it fetches) is its only write, to the shared git dir. The live run on the AI productivity
manager (#278's PR) took about 9 s with merge-check. The orchestrate-stage skill moves onto it, replacing its
`args-<n>.json` files, in #279.
`--stalled [--minutes M]` (#731, `wave_stall.py`) looks at the other sessions instead of this one. On 2026-10-09 a
manager's guarded cleanup command (a branch delete outside a task branch) became a permission card at 22:06Z. Claude
Code held every task notification of that session behind it, four finished runs and the keep-alive timer, until the
engineer allowed the call at 07:29Z. It reads every transcript of the track checkouts (main, -ui, -art, -design) and their worktrees
written in the last 24 hours, except the caller's own. It flags a session whose process is alive when it has had no
turn since either (a session no file in `~/.claude/sessions` names is closed, Claude Code removes the file at exit;
with no file at all, the process is unknown and the session is flagged):
- a run of its own finished more than M minutes ago (default 30; a stopped or killed run starts no turn and does not
  count); or
- a notification has waited undelivered in its queue that long, after the session's last turn (before it, only when a
  permission card waits): an `enqueue` record that no `remove`, `dequeue` or delivering user record took out. A
  notification that needs no turn does not count: an artifact watch that dropped or ended (`<task-type>`
  `artifact-watch-lifecycle`) or auto-replies paused by an interrupt (`artifact-auto-react`). On 2026-10-14 a dropped
  watch alone had the art manager flagged for six hours (#1044).

A session that handed over to a fresh one in its last turn (since the human's last prompt) takes no more turns. Its
handover is the comment titled "Handover to a fresh manager session" posted by hand (`## ` heading) or by
`wave --title`, or a For-you asking to close this session and paste the kickoff (English or Ukrainian). Of such a
session's queued notifications only an unstopped result of its own workflow counts; a timer or a background command
left behind does not. Its line adds when it handed over.

One line per session gives its title, its id, how long it has had no turn, the runs and queued notifications, and the
call it waits on. When a PreToolUse hook answered `ask` for that call, the line calls it a permission card and quotes
the guard's reason; the line ends with what the engineer does. The command is read-only. It exits 3 when it flags a
session and 0 otherwise, and its last line counts the transcripts it read. Its flags other than `--minutes` are
refused.

### 11.12 `metrics [--session ID[=LABEL] ...] [--since T] [--until T] [--ci N] [--out DIR] [--compact] [--no-gh] [--adr-reads] [--track NAME ... [--budget PCT ...]] | --run ID ...` [applied]
(#178; item 1 of the [AI productivity ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md), whose
baseline it reproduces): time, tokens and API list $ of the task workflows, read-only from Claude Code transcripts
(`~/.claude/projects/<key>/` and `<key>--claude-worktrees-<n>/`, `<key>` the main checkout's path with every character
but letters and digits replaced by `-`; `CLAUDE_CONFIG_DIR` replaces `~/.claude`). Per session: the manager's own
lines, its hand-run subagents and each workflow run under `subagents/workflows/wf_*/`. Usage counts each message id
once; a run counts when its first line is at or after `--since` and its last before `--until` (default now), so a
past `--until` gives the same tables later. `--session dd93bf79=M4` labels sessions (one label: one stage). It prints
and writes `tools/out/metrics/metrics.md` and `.json`; the `metrics.py` docstrings (the module's and each table function's) have each table's fields. The tables,
one line each (the key in `metrics.json` in brackets):
- per finished `quick-task` run (#1012, `quick_tasks`; its own kind, by the run's saved script name, else the `script` of its saved
  run record, else its Quick phase, never a resumed `issue-task`): wall, $, the reviewers' blockers and majors, fix agent, PR, CI and CI rounds,
  their medians, and the quality scorecard's `quick-task` row; on the compact summary as clauses of its lines;
- per finished `issue-task` run, per session (a stage) and per agent role, from the agent's label (§7.1); the role
  table's tool calls per API call (#979, `tool_calls_per_api_call`; the implementer's and publisher's on the compact
  "task medians" line) and its output $ with their share of the role's $ (#982);
- output $ per agent role, review tier (an issue-task run's, another run's kind) and effort (#982, `output_by_role`;
  medium against high in one tier: the effort ADR gives docs work medium);
- per review tier (#606, `tiers`) and per path of an update run (#875, "Update runs (#856)", `update_runs`);
- local `verify` by step, with its slot wait, runs over the limit, the red runs' failing tests and the `check` steps
  that passed although Godot crashed at exit (#179, #185, #273, #449; from `tools/out/logs/verify-history.jsonl`);
- review findings by reviewer (a task's blockers and majors count only its diff reviewers', as in the baseline);
- the plan phase per run with a planner (#469, `plans`);
- the code reviewer's A/B (#535, `ab_review`; [A/B ADR](decisions/2026-10-07-code-reviewer-model-ab.md), whose stop
  rule it advises on; ended 2026-10-13);
- implementer context and checkpoint handoffs (#559, `handoffs`);
- the tool output per implementer (#572, `impl_outputs`) and the launch prompt size per role (#470, `prompt_sizes`);
- the Sonnet implementer trial (#560, `sonnet_trial`; [trial ADR](decisions/2026-10-08-sonnet-implementer-trial.md),
  with its revert rule's advice; ended 2026-10-13);
- the Sonnet publisher trial and `pr-rebase` by model (#835, `publisher_trial`; the
  [model-guard ADR](decisions/2026-09-28-model-guard-no-fable-in-shared-config.md)'s amendments of 2026-10-11,
  2026-10-13 and 2026-10-20: the publisher's half ended, `pr-rebase`'s became a standing habit);
- agents by role and agent type, and how many ran general (#557, `agent_types`);
- cache re-writes after a `wait` or a CI wait (#555, §11.17, `bounded_waits`) and the tool-call start-up per class of
  call (#568, §8.2, `tool_latency`);
- CI waits per run kind and CI role (#1019, `ci_waits`: issue-task's publisher, quick-task's quick agent and fixer,
  pr-rebase's rebase and fix agents): the API calls that only poll CI, `wait` or sleep (or end a turn right after
  one), their list $ by input, cache write, cache read and output, share of the role's $ and % of the week, and a poll
  agent's estimate (each call at 16k context, one launch per wait; `metrics --help` has the model) with its saving and
  a free poll agent's, per 7 days at the window's rate against the engineer's 1% bar (#302's answer 4A); on the compact
  summary at the end of its % of the week line (else on the total line, or in a short form);
- manager sessions with their % of the week and their cache re-writes after an idle gap over 1 hour (#305), by what
  held when it began (a foreground call such as a permission card, a timer until its notification or TaskStop, a run
  not stopped, else a stop; #981), and the subagents' re-writes after a gap of 5 minutes or more, by what preceded
  it (#558, `idle`);
- the context per API call of every agent, with the heavy ones (#584, `context_per_call`);
- the quality scorecard (#314, `quality`): per run, per session and per role setting, blockers and majors, skeptics'
  refutations, "clean" (#315's rule), the publisher's fixes and rounds, and from `gh` (read-only, by default; `--no-gh`
  skips it) the PR, its CI rounds, Found-by issues and later reverts or fixes; unknown is `?`, never 0;
- "Instructions and docs per agent role" (#337, the instruction-diet ADR's method, `instructions`): loaded and read
  tokens, the points at three cache-read weights, files loaded twice, cost by file, ARCHITECTURE's and
  AGENT_WORKFLOW's list $ by § of today's file, and the open-PR pairs whose `merge-check` names an ARCHITECTURE
  conflict;
- `--adr-reads` (#793, `instructions.adr_reads`): ADR reads by file, whole, by section or small; with it the
  ARCHITECTURE reads by agent type and their repeats (#834, `instructions.arch_reads`);
- "Issues launched 2 or more times" (#833, `relaunches`): the runs per issue and their $ after the first; the cause of
  a relaunch is in the run's notes and the issue's comments, not the transcripts.

`--ci N` adds CI from `gh`. `--compact` prints only a summary of at most 11 lines, each cut at 400 characters unless
`--verbose` (#572): the manager writes `metrics --since <wave start> --compact --verbose` straight into the wave
comment's `--body-file`, without reading it. The % of the week counts cache reads at the central weight #307 measured
(`WEEK_CENTRAL`, #333: (list $ without cache reads + 0.75 x the cache-read $) / $23.0 per 1%), with the measured
range in a bracket (`WEEK_BRACKET`). API list $ is a weight (one price table in `metrics.py`), not money spent; no
transcripts or an empty window is a message and exit 0 (and an empty report). It covers only this checkout's sessions
that ran a workflow or that `--session` names.
**Transcript cache** (#1014): each transcript's parsed summary (`metrics.read_agent`'s, which every table and `wave`
are built from; never a report) is kept in `tools/out/cache/transcripts/` of the checkout that runs it, one pickle per
transcript keyed by its path, size and mtime, a format version and a hash of `metrics.py`, with up to 8 windows each
(`transcript_cache.py`'s docstring has the rules). A changed size or mtime (the live session's transcript), a corrupt
entry or another parser parses the file again, so the output is the same with and without it; deleting the folder
only makes the next run slow. Measured on 1.7 GB (#1014): a day's transcripts in 2.4 s instead of 60 s; the GitHub
lists are read at once, the CI run list as its REST pages through `gh api` (`gh run list` reads them one after
another, 36 s), so a warm `metrics --compact` over a day takes about 10 s instead of 85 s. `wave` over an hour spends
its 11 s in its `gh` calls, which the cache does not touch. Library calls and the tests parse without it.

**`--track NAME ...`** (#409) with `--since <the weekly reset>`: a track's spend this week against its budget, over
every session of the main checkout and its `-ui` and `-art` checkouts (`TRACK_CHECKOUTS`, #586), each API call counted
by its time in the window. A session's track: `--session <id>=<track>`, else a `Track: <name>` line in its kickoff
(orchestrate-stage `kickoff-template.md`), else its checkout's, else `untracked`. One line per track (% of the week
with the bracket, list $, sessions; with `--budget PCT ...` the budget and the plan to date), then every session's
total, which the manager holds against the weekly counter; a checkout with no folder here is `not on this machine`,
its spend unknown, never 0%. **`--since` is the moment the counter last restarted, not always the scheduled reset**
(#677): after a reset by hand, pass its time; the plan to date then runs low until the next scheduled reset, so hold
a track's % against its budget directly. It writes `tracks.json`, never `metrics.md`.
**`--run ID ...`** (#534), alone: one workflow run's spend so far, finished or in flight, for the manager's check
after a large launch's first phase ([`docs/MANAGERS.md`](MANAGERS.md) §9): its agents, who works now, the minutes
since its last write, its % of the week and list $ by phase, its idle re-writes and context per call. It writes no
file; an ID that names no run fails.

### 11.13 `playcheck [scenario ...]` [applied] (#186, P9 of the AI productivity ADR, item 8)
The real game in off-screen
windows running scripted steps, with screenshots at named steps, for the UI and camera bugs only a playtest saw before
(#168, #169). A scenario, `tools/playcheck/scenarios/<name>.txt` (grammar: `tools/runner/playcheck.py`), names its
players: window 1 hosts (`client/app/game.tscn` with `--host --local` on a free port; with the `tutorial` header it
is the only window and starts the solo tutorial, `--tutorial`, #601), up to two more windows join it,
and the players after them are bots, one headless process (`tests/harness/playcheck/`) playing a `BotScenario`'s
scripts over ENet (`bots <file.tres>`); its `role`, `setting` and `clock` lines are the setup window 1 sends as the
host's own client. Each window (`tools/playcheck/playcheck_window.gd`) runs its own steps: `wait
phase|screen|life|ready|players|event|esc|pointer ...`, read from its own `ClientSession`, `ClientModel`, Esc menu and
pointer, never `HostSession`, the match or `core/` (invariant 2); `wait text <field> is|has|lacks <text>` and `wait
shown <field> on|off` (#275), what its own Ui and current camera draw (the fields: `FIELDS` in
`tools/runner/playcheck.py`, the same keys as the window's `GameView`; whitespace runs count as one space, a hidden
field reads as ""); `press <action>` (its key through `Input.parse_input_event`), `hold`/`release`
(`Input.action_press`), `button <text>` (the one visible, enabled Button with that text takes the focus and gets
`ui_accept`'s key; none or several fail the step), `aim item <kind>` until `aim off` (#276: each frame the window
turns its own player, `PlayerController.look`, to face the nearest resting item of that kind in its own `ClientModel`;
paired like `hold`), `frames N` and `shot <name>`. A `press` reaches what reads input events and what polls
`Input.is_action_just_pressed` in `_process` alike (`interact`, `swap`, `put_down`). A text wait asserts a short,
stable part with `has`/`lacks`, never a whole greybox sentence (#150): a wording change stays a one-line scenario
edit, and a timeout prints what the window drew (`hud.aim 'Package'`). `lacks` holds at once on a hidden field
(it reads as ""): put a `has` or `wait shown <field> on` on the same field before it. The windows stay off-screen as
`shot`'s does (§11.4: `playcheck_window.gd` calls `Offscreen.place()` first) with the dummy audio driver, never
headless. The game gets a pointer that only remembers, and
playcheck presses keys only, so the real mouse is never captured. The item keys read that pointer, so `hold use` (the
left button has no key for `press`) uses the hand item and shoots from the viewfinder (#1114); spectate cycling,
which reads Input's mouse mode, is out of its reach, and `aim` is the only way to turn. PNGs:
`tools/out/playcheck/<scenario>/<shot>.png` (`gh` cannot upload them: the PR lists their paths and says what each shows); logs:
`tools/out/logs/playcheck/<scenario>/`. A run fails on a wait past its timeout (the window prints the step's line and
what it saw, and saves `failed-window-<n>.png`), an engine error line or a non-zero exit of any process, a window not
done within `--seconds` (default 300; it names the last step) or a missing PNG, and stops every process it started
through the stop file (else a kill: a window after 30 s, since its renderer's exit can wait seconds on the GPU
driver when every core is busy, #354; the bots after 10 s). Under a full-PC load it can also fail for reasons that
are not bugs (ARCHITECTURE §4.7 `playcheck`, "Known load limits", #406): run it again once the load ends before
debugging it. Desktop only: CI and `verify` never run it; an agent
may (off-screen windows, like `shot`). Scenarios: `esc_menu` (#169), `spectate` (#168), `items` (a knife picked
up, swapped to the belt and back and put down, #276) and `end` (a match ended by the clock, the end screen's countdown
and the return to the lobby with no button, #212, and a second round, #276).

### 11.14 Warnings [applied]
`untyped_declaration`, `unsafe_method_access`, `unsafe_property_access`,
`unsafe_call_argument` = Error; the rest stay Warn and are reported by `check`; `inferred_declaration` stays off.

### 11.15 Runner [applied] ([ADR](decisions/2026-09-29-python-task-runner.md))
Python core `tools/run.py` with
`tools\run.cmd` (immune to the execution policy) and `tools/run.sh`. `tools/run.sh --help` lists the commands and each one's
`--help` says what it does (root `CLAUDE.md` lists only the names, §3). Pins and pass/fail
rules: [ADR](decisions/2026-09-28-toolchain-pins.md). On this machine `bash` on PATH is the WSL launcher, not Git
Bash; `doctor` finds Git Bash through git's install folder. Logs go to `tools/out/logs/`, GdUnit reports to
`tools/out/gdunit/`. The commands agents run in loops are quiet by default (#590, #572; `--verbose` prints the whole
output): a summary when green, a capped excerpt (about 4 KB) with the exit code and the log's path when red. `lint`,
`check`, `merge-check` and `merge` keep their whole output in `tools/out/logs/<command>-output.log`, written as it
runs; a green `check` counts the script warnings after the first 3, but those of the `.gd` files the branch changes
always print; `merge-check` lists only the rows that flag something and counts the clean ones; `merge` leaves out its
`ok` progress lines (its verdict, `wave:` line and exit code are unchanged; the log's path follows them). `merge` and
`merge-check` write `merge-<pr>-output.log` and `merge-check-<PRs>-output.log`, one per run, so managers merging at
once keep their own. `verify` (and `publish`, which runs it) writes its whole output to
`tools/out/logs/verify-output.log` (the run before it stays as `verify-output.prev.log`: a retry in the same worktree
keeps the red run) and prints each red step's failure lines and the summary
block, whole, with that path in it; CI's `verify --full` stays verbose (its job log is the only log there). `wait`
points to the job's own log; `metrics --compact` cuts each summary line at 400 characters (`metrics.md` has them
whole). Read a log by search (grep the failing test or `FAIL`), never whole: a log read whole is carried on every
later call. Outside a Claude Code session (a human's PowerShell) the runner
takes the machine paths from the Claude settings (§2).

### 11.16 CI [applied]
A plain `verify` runs only `doctor --quick`, `lint` and `check` (one lane each, at once) and the clean-tree check,
takes no verify slot, prints "fast verify: lint and check; the tests run on CI" and records `"mode": "fast"`; every
test runs on CI (#605, [ADR](decisions/2026-10-09-tests-on-ci-local-lint-and-check.md)). Every agent runs `verify` in
the background into a log and polls it with `wait <log>` (§11.17). The rest of this section is
`verify --full`, CI's run, which an agent runs locally only when it needs to (a Windows-only failure, a release). How
its steps, lanes, `AFTER` order, output and record work: the docstrings of `tools/runner/verify.py`, `slots.py`,
`load.py`, `suspend.py`, `common.py` and `verify --help`; the measurements behind them: git history.
**CI:** `.github/workflows/ci.yml` runs `tools/run.sh verify --full` on ubuntu-24.04 in parts at once (#857), a job
per part of `verify.PARTS` (`verify --full --part <name>`), each with its own reports artifact. Since #980 `test`
runs there as its two halves, the parts `test-1` and `test-2` (`verify.HALVES`): every script of a run without paths
is in one half (`gdunit.half_of`: `FIXED_FPS_SUITES` and the folders of `gdunit.HALF_ONE` the first, the rest the
second; a runner test checks the halves against that run), so each suite runs once on CI; a local `verify --full`
keeps the one `test` step. Since #1013 the network runs are two parts too: `network-1` the ENet and loopback runs,
`network-2` the WebRTC ones, each run in one of them (a runner test checks it); `verify --full --part network` (the
group of `verify.GROUPS`) runs both as one, every network run, locally. The job named
`verify` needs every part (`if: always()`) and is green only when every part's job was. A second job, `python-min`
(#349), runs `selftest --group python` on the pinned minimum Python (`pins --get python_min`), since 3.12-only code
once broke `verify` on 3.11 (#345). Both are required checks of `main` (§8.5), so neither `merge` nor a human's merge
button takes a PR while one is red. Since #1123 a job `changes` first diffs a PR against its merge base (plain git)
and matches every path against `.github/design-only-paths.txt`, the list `tools/runner/design_only.py` reads too:
when all match (a design-only PR, §4.2 step 1), the parts are skipped, `verify` passes on their `skipped` and
`python-min` also runs `lint` (the § references); a push, a dispatch or a red `changes` runs every part. CI runs on every PR (whatever its base) and on pushes to `main` and `release/**`
(#622), so the tree a `merge` or `merge --sync-main` leaves there is tested (§7.1), with the checksum-checked Godot
build from the pins. It removes the Windows-only TwoVoIP extension first (the M5 voice ADR's E35 (a)) and loads
webrtc-native (the M6 ADR's E57, #367; smoke test `tests/unit/net/transport/webrtc_native_addon_test.gd`); if its
Linux library ever fails to load there, CI removes it like TwoVoIP and the WebRTC steps print SKIP, which then also
needs a skip in that smoke suite when the `.gdextension` is absent. The game targets Windows for now; CI stays on
GitHub's free Linux runner as an extra check, and a problem seen only on Linux is low priority (the engineer,
2026-10-01). Tested once (KICKOFF §4): a deliberately failing commit on the throwaway branch `tooling/2-ci-red-probe`
turned CI red on 2026-09-28; repeat it after a structural change to `ci.yml`.
**`verify --full`:** `doctor --quick` first (red: nothing else runs), then three lanes at once: Python (`lint`,
`signal`, `selftest`), Godot (`check`, `test`, then the network runs: `enet`, `freeze`, `stall`, their WebRTC twins,
`bots`, `bots-enet`, `bots-webrtc`, `chaos`, `chaos-webrtc` and `game`) and selftest-godot (the runner tests marked
`@starts_godot`), so no other Godot run overlaps a network run. Every step runs and any red step fails it; then the
clean-tree check and the runner tests counted against a serial discovery. If `test` turns flaky under the extra load
(see its red rate in `metrics`), `AFTER["selftest-godot"] = ("check", "test")` puts that lane after `test` again
(#556). Each step's output goes whole to `tools/out/logs/verify-output.log`, a red step's failure lines to the
terminal too (quiet by default, §11.15; `--verbose` and CI print every step whole). The `game` step (#149) starts
`client/app/game.tscn` headless through its command line, a host and one client that must both be welcomed into the
lobby and stop with exit 0 and no engine error line. The network runs take a random free port in 20000–31999; if
two worktrees ever share one, the host fails with `host on 127.0.0.1:<p> failed`: run `verify` again. Test suites are
named `<name>_test.gd` (GdUnit4's snake_case convention).
**`verify --changed` and `lint --changed` (#859, the engineer's approval of 2026-10-11):** the agents' local lint.
gdformat and gdlint run only on the project `.gd` files changed against `origin/<base>` (the parent `start --base`
recorded, else `main`); the budget, frontmatter and § checks still run whole, and every file is linted (the output
says why) when the merge base is unknown, a lint config or `pins.py`/`lint.py` changed, and on CI. Agents pass the
flag (the workflow prompts, finish-task); `publish` adds it in a Claude Code shell (`CLAUDECODE`). A human's plain
`verify` and `lint` stay whole, and `verify --full` refuses `--changed`, so CI always lints every file: a lint problem
in a file the change did not touch shows up red on CI, not in the local run.
**`verify --fail-fast` (#556):** the first red step stops every lane; the steps that had not ended are `not run` and
the run is red. Use it in an implementer's inner loop (issue-task's implementer prompt and `finish-task` say so),
where a red step means another fix anyway. Never for the run that gates: the green verify the definition of done
pastes, `publish` (which runs `verify` itself, without the flag), `merge` and CI run every step, since one run must
show every red step at once; `wait --verified` and `publish` never reuse a run stopped early.
**A machine that slept (#595):** a Windows wait does not count a sleep, so a verify in flight across one reported
steps of hours. `verify` now stops every lane on a gap of 120 s or more between two clock reads: the running steps
are red with `the machine slept or was suspended (<n> s)`, `metrics` counts no step of the run, and `wait` prints the
same line. Run `verify` again.
**History:** each run appends a record to `tools/out/logs/verify-history.jsonl`, which `metrics` reads (fields:
`verify.py`'s `step_record` and the run record; since #273 a red step's `failure` line, `test`'s `shards` and
`failed_tests`, since #449 `check`'s `exit_crash`, §11.3).
**Processes Windows could not start (#441):** on the engineer's PC, Godot, git, Python and PowerShell sometimes exit
with 3221225794 (0xC0000142, STATUS_DLL_INIT_FAILED) a fraction of a second after their start, before they print a
line: none of their code ran, and the same tree passes on a rerun (which per-session resource runs short is not known
yet). `run` in `tools/runner/common.py` starts such a process once more after 10 s with a `NOT STARTED, restarted
once` warning carrying the machine's load (the evidence to find the shortage); a process that printed a line or lived
10 s is never started again, so no step that ran is retried. A start that stayed refused reads `could not start: ...
run verify again`, and the summary gets a `NOT STARTED` line: run `verify` again. Tests:
`tools/runner/tests/test_not_started.py`.
**Verify slots (#185):** on a PC, `verify --full` (a plain `verify` takes none) takes one of N machine-wide slots
(lock files in `%LOCALAPPDATA%\prime-game\verify-slots`, elsewhere `~/.cache/prime-game/verify-slots`, shared by the
main checkout and every worktree), so the tracks' runs queue instead of starving each other. N is 2, measured on the
engineer's PC: a third or fourth run at once makes every run a third longer and `test` red more often. A killed run's
slot is freed at once. The wait is bounded (600 s, about one whole verify on the loaded PC: longer means a stuck
holder); after it the run goes ahead without a slot, marked `OVER THE LIMIT`. A slot never skips or weakens a step.
`PRIME_VERIFY_SLOTS` (0: no limit), `PRIME_VERIFY_SLOT_WAIT` (seconds) and `PRIME_VERIFY_SLOTS_DIR` override the
defaults; CI and a verify inside a verify (`PRIME_VERIFY_INSIDE`) take no slot.
**Load runs (#388):** an agent that tests something under load on purpose runs `load [--loops N] [--seconds S]`, never
hand-written busy loops: it takes a slot like a verify, so one verify fewer runs beside it and every waiting run names
it, and past the wait it starts nothing (exit 1). Start it in the background (a log under the scratch folder), run
your steps after its `load: running` line, and let it end or `wait <log>`. A verify that ran beside a load may run slow
and go red on `freeze` or `stall`: rerun it after the load instead of debugging it.
**`slots` (#416):** `--status` shows holders, waiters and the last hour's runs without a slot (launch nothing while
one waits or runs over the limit) and marks a holder that slept since it took its slot STALE (#595); `--quiet <hours>`
(at most 24; `off`) leaves new verify and load runs one slot machine-wide. Tests: `tools/runner/tests/test_verify.py`,
`test_suspend.py`, `test_slots.py`, `test_load.py`, `test_wait.py`.

### 11.17 Bounded waits: `wait <log> [--max S]` and `wait --verified` [applied] (#303; #302's token research)
A workflow
agent or subagent writes its prompt cache with a 5-minute lifetime (a main or manager session has 1 hour), so a
tool call that blocks longer makes its next call write the whole context again (#302's token research: nearly all
on `verify`, `publish`, `mutants` and `gh pr checks --watch`). So such an agent blocks no tool call over 180 s,
and bounds a call with the shell's `timeout` or `wait --max`, never only with the tool's own timeout: 180 s leaves
room for the shell's start-up and the model's turn before the next call (a 4-minute step crossed 300 s, #555).
`metrics` prints the cache re-writes after `wait` calls per window and its "Tool-call start-up" line.
Since #388 every agent, a main or manager session too, runs `verify`, `publish` and `mutants` in the background with
`wait`: a verify slot's wait alone can
reach 600 s, where a foreground call is killed. A foreground `sleep N` followed by another command
(`sleep 60; cat <log>`) is refused by Claude Code itself (`Blocked: sleep 60 followed by ...`, #312; workflow
agents' prompts carry this rule, #326, #818), and so is PowerShell's `Start-Sleep -Seconds N`: wait with `wait <log>`, `run_in_background` or Monitor with an until-loop instead. The agent starts the
job in the Bash tool with `run_in_background` (its timeout 3600000 for `mutants`; the default 30 minutes covers
the rest), with a new log per run under its scratch folder:
`cd <worktree> && tools/run.sh verify > <log> 2>&1; echo "exit=$?" >> <log>`
(in the Bash tool only: PowerShell 5.1's `*>` writes UTF-16 and its `$?` is a boolean). It then calls
`tools/run.sh wait <log>` (PowerShell: `tools\run.cmd wait <log>`) with the tool's timeout at 300000, since the
default 120000 would cut a 180 s wait short. `wait` polls every 3 s for at most S seconds (default 180, 1 to 180;
else exit 2) and reads only. The job is finished only when the LAST complete non-empty line of the log is
`exit=<n>`: the marker is the job's final write, a line still being written (no newline yet) is never read, and a
bare `exit=0` in a step's output is no result. Then it prints the summary (from the last `verify summary` line,
which `publish` prints too, or `merge-train summary`, else the last 20 lines) and `wait: <log> finished: exit=<n> (whole log: <path>)`, and
exits n. Not finished: one line, `wait: still running after S s (<path>: <k> lines, last written <t> s ago); call
wait again, never start the job again`, and 124; the job runs on (a second `verify` in one worktree would fight
the first over `tools/out/` and the slots). No log after a 10 s grace (the background shell may not have created
it yet), or a log deleted during the wait: `wait: no log at <path> ...` and 2; a log it cannot read (a folder, a
locked file): `wait: cannot read <path>: ...` and 2. Every line `wait` writes itself starts with `wait: `, which tells
its own 2 from a job's (`mutants` exits 2 too). It reads UTF-16 and UTF-8 (BOM or none), CRLF, and on Windows the Git
Bash form `/c/...` of a path; a Git Bash-only path such as `/tmp` is not visible to Windows Python, and the
missing-log line says so. A log that has not grown for 10 minutes points at a background task that died (no marker is
ever written): check it. CI: `timeout 180 gh pr checks <pr> --watch --interval 30; echo rc=$?` in the Bash tool with
the tool's timeout at 300000 (its default 120000 would cut the 180 s short; in PowerShell `timeout` is Windows' own
program), repeated while rc is 124 (the timeout) or 8 (pending); rc 1 with "no checks reported" means the run has not
registered yet. `wait --verified` (no log) exits 0 when the newest record of `tools/out/logs/verify-history.jsonl`
passed at HEAD with a clean tree (`tree` set), on HEAD's tree and runner, under 2 hours ago, and the tree is still
clean, else 1 with the reason: the test `publish` runs before it reuses that verify (§4.2 step 5, #471). On a branch
whose base predates `wait`, the agents run these commands in the foreground as before. Tests:
`tools/runner/tests/test_wait.py` (a fake clock; the launch line and `wait` through Git Bash, cmd and PowerShell 5.1;
the commands pass the permission model outside bypass). The rule is one Shell bullet of root CLAUDE.md, the commands are
the workflow prompts' bounded-waits paragraph (§7.1).

### 11.18 An own `user://` per worktree [applied] (#182)
Godot names `user://` after the project, so every checkout of
"PrimeGame" shared one folder, and two worktrees' `test` runs cleared each other's GdUnit4 files in `user://tmp`.
Before every Godot start (`require_godot`, and a windowed `run`) the runner writes a gitignored `override.cfg` into
a linked worktree (one whose `.git` is a file: a task's `.claude/worktrees/<n>`, a scratch worktree) with
`application/config/use_custom_user_dir=true` and `custom_user_dir_name="Godot/app_userdata/PrimeGame-<folder>-<6
hex of its path>"`. Godot 4.7.2 joins the name to the app-data folder, so worktree 182's `user://` is
`%APPDATA%\Godot\app_userdata\PrimeGame-182-7f974f` (Linux: under `~/.local/share/godot/app_userdata/`). The main
checkout and a clone (CI, a cloud session) have a `.git` folder and get no file: the humans' settings and saves stay
in Godot's default `%APPDATA%\Godot\app_userdata\PrimeGame`. An export gets that default folder too: it packs a
non-resource file only when a preset's include filter names it (there is no preset yet), and an exported game reads
an `override.cfg` placed beside its binary. A hand-made `override.cfg` in a worktree is left alone, with a warning.
`worktree-done <n>` deletes the removed worktree's folder (#202) once `git worktree remove` succeeded, or when it
finishes a removal left half done, and says so in one line; never the default `PrimeGame` folder or another
worktree's (a missing folder is fine; one a Godot still holds open stays, with a warning). Saving
project settings in a worktree's editor (`ProjectSettings.save()`) copies both keys into `project.godot` (probed on
4.7.2), which would move every checkout's and export's `user://`: `check` fails on them; delete the two lines.

### 11.19 `test` in shards [applied] (#182)
`test` with no paths runs the suites in K GdUnit4 processes at once, K =
half the logical CPUs, at most 4 (`gdunit.SHARD_CAP`: CI's 4 vCPUs give 2, the engineer's 16 give 4). `--shards K`
or `PRIME_TEST_SHARDS=K` sets K (1: the one process of before); `test <paths>` and `gdunit.main(paths)` stay one
process unless `--shards K`; `test --repeat N` takes the same count for each of its runs since #817, its shards at
the run's clock. `PRIME_TEST_HALF=1` or `2` (#1065) is read by `test --repeat` alone (plain `test` ignores it):
without paths it runs one half of the suites (`gdunit.half_of`, as `verify --part test-1`/`test-2`), the nightly
`flaky` job's split. The shards are balanced by the last per-suite times
(`tools/out/logs/gdunit-times.json`, merged after every run; a fresh worktree reads the newest one of another
checkout, CI restores it from the Actions cache): the longest suite first, each to the least loaded shard. A
shard is one GdUnit4 process given its scripts one by one (`-a <file>`; together every `.gd` file a one-process
run's folder scan loads), with `APPDATA` (Linux: `XDG_DATA_HOME`) set to `tools/out/gdunit-user/shard-<i>`, which
gives it a `user://` of its own; its report goes to `tools/out/gdunit/shard-<i>/`, its log to
`tools/out/logs/test-shard<i>.log`, and `test.log` holds every shard's log in turn. Each shard is judged as a
one-process run (exit code, `results.xml`, orphans named), a shard whose `user://` stayed empty fails, and the
merged `tools/out/gdunit/results.xml` is counted against a one-process scan of the same folders: every suite that
declares a test function ran exactly once, with each of them (`137 suites and 1206 test cases ran in 4
processes; a one-process scan finds 137 suites with 1206 test functions`). One import runs before the shards.
CI's two test parts (#980) each shard one half of the suites so (`gdunit.main(half=1|2)`), counted against the scan
of that half, and keep their times under cache keys of their own (`gdunit-times-<part>-`).

### 11.20 The frame-bound suites at fixed fps [applied, the default without paths] (#280, #341)
Suites run with the
engine's `--fixed-fps 60` (placed before `-s`, since GdUnit4's command tool skips every argument before its own
script): each frame counts as 1/60 s of game time however fast it runs, so a suite that steps physics frames on a
simulated clock (`NetPair`'s, or the test's own over the `LoopbackHub`) runs as fast as the CPU allows. `test` with
no paths, so `verify` and CI too (#341), runs `gdunit.FIXED_FPS_SUITES`, the 9 frame-bound client suites, so, in
shards of their own within the same K (`gdunit.split_shards` picks how many), and the rest real-time; with one
process at a time (`--shards 1`, `PRIME_TEST_SHARDS=1`, 2 or 3 CPUs, no per-process `user://`) in a second process
after the rest, so every machine's `verify` runs CI's clock. `test --real-time` runs every suite real-time. `test <paths> --fixed-fps` (also with `--repeat N`) runs every named suite so; named paths and `--repeat`
are real-time without it. Seconds at fixed fps go to the `fixed_fps` map of `gdunit-times.json`, never into the
real-time one. Measured on the engineer's PC, 2026-10-04
(the tables, the load and the break list are in #280's comment): the 9 took 284 s real-time and 22.7 s at fixed fps
(medians of 10 runs each, all 90 green; beside another session's 100 % CPU load a CPU-bound one gained only 2.3x);
the whole `test` step took 119.4 s real-time and 62.2 s with the flag (mean of 3 each, alternated, 4 shards, a quiet
PC), 139.5 s and 90.7 s with `selftest` beside it as in verify, 226 s and 145 s in 2 shards (CI's count). Run with
every suite at fixed fps, only `voice_views_audio_test` breaks (it listens to the real audio mix for a wall-clock
time, so GdUnit4's 5-minute test timeout, counted in game time, runs out); the other 164 suites took 121 s real-time
and 119 s so. What it hides is the #222 class: at fixed fps a frame runs exactly one physics step, never several,
so a load bug there and `.claude/rules/tests.md`'s `OS.delay_msec` recipe (a named path) need a real-time run.
The engineer made it the default of `verify` and CI (option (b) on PR #323, the pipeline-v2 ADR's amendment of
#341); the nightly `flaky` job's `test --repeat 3` stays real-time and keeps covering that class, and
`test_github_workflows.py` pins both. A third CI process for the fixed shard (K+1) was declined for now.

### 11.21 The real app-data folder stays clean [applied] (#233)
A worktree's `user://` folder outlives the worktree,
and by 2026-10-02 22:30 UTC 62 such folders had piled up in `%APPDATA%\Godot\app_userdata\`, a new one with every
`selftest` and every scratch worktree. Each source and its fix (found by listing a temporary app-data folder before
and after one `selftest` and one `merge-check --trial`): the runner tests that start Godot in a throwaway project
(`RealUserDirTest`'s settings save made `PrimeGame-182-<hash>`, `RealNormalizeTest` the folder `n` and Godot's
editor settings, `RealRunTest` the folder `r`; PR #224's `RealStaleCacheTest` wrote into the main checkout's own
`PrimeGame` folder) run in a class marked `@starts_godot`, which now points `APPDATA`
(Linux: `XDG_DATA_HOME`) at a temporary folder of the class's own and deletes it after the class
(`common.temp_app_data`; `PYTHONUSERBASE` keeps a Python child's user site-packages); `selftest` gives its
workers a stand-in app-data folder and fails, naming the files and any empty `user://` folder, when a test wrote to
it (one that starts Godot outside a `@starts_godot` class: outside `selftest` that would have been the real folder;
only `selftest` has this check, so a direct `python -m unittest` run still writes there). The scratch worktrees of
`merge` and `merge-check --trial` (`PrimeGame-<label>-<random>-<hash>`: a new path, so a new folder, every run) and
of `mutants` (`PrimeGame-tree-<checkout>-<hash>`) delete the folder their Godot runs made when they remove the tree
(`common.remove_own_user_dir`: only a `<project>-<folder>-<6 hex>` folder in `app_userdata/`, never the default
`PrimeGame` folder nor the running checkout's own; one a Godot still holds stays, with a warning; a tree that could
not be removed keeps its folder). The folders left before the fix are a human's one-time cleanup (the PR of #233
lists them).

### 11.22 No Godot MCP server
Before M4 (§14; [ADR](decisions/2026-09-29-no-godot-mcp-before-m4.md)). API facts come
from `check`, the engine API dump that `doctor` generates into `tools/out/godot-api/4.7.2/`, and
`docs.godotengine.org/en/4.7/`.

### 11.23 `inbox [--since T] [--repo OWNER/NAME ...]` [applied] (#485)
The secretary's GitHub half (§7.2; `tools/runner/inbox.py`, read-only; tests: `test_inbox.py`): per repo
(`xperiaroco2/prime-game`, `-ui`, `-art`, `-design`) one `gh pr list --state open` with bodies and files and one `gh api
repos/<repo>/issues/comments?since=T` (newest first, 100 a page, a further page while the last was full, up to
500; past that a "Truncated:" line names the oldest comment read). It prints open PRs' "Needs the engineer" items
without "Answered: <GitHub link>" (the gate's own reading, `merge.open_needs`); in the game repo, the gate's
exceptions of each ready PR into `main` by the engineer's account (`merge.exception_reasons` over gh's file list:
the merges only he makes; for a PR with a rename, one `gh api repos/<repo>/pulls/<n>/files` adds each old path as
a delete, as the gate's `--no-renames` diff sees it); and the "For you:" blocks of each thread's latest comment by
his account that has one (all its blocks together; a "- " item is read too), with the count of later comments in
the window. `--since` defaults to 72 hours ago. A source that fails prints "Unavailable: <error>" and exits 1; the
rest is still printed.

### 11.24 Exported builds: `export [--version V] [--rev R]` [applied] (#369; the M6 ADR's E59 and D20)
The friends'
Windows x86_64 builds from the two presets of `export_presets.cfg` (`Windows Release`, `Windows Debug`; the pack
beside the `.exe`, the `.exe`'s icon and metadata left as the template's). Linux only (CI, a cloud session): it
checks the pinned export templates (`pins.py`, the release's SHA512-SUMS.txt), exports a clean `git archive` tree
of the commit (the TwoVoIP extension in it; its `ERROR:` lines on Linux are expected, and webrtc-native's too when
the probe below runs the Windows pack, which holds no Linux library), imported once before its first export
(`--headless --import`, as `check` does, #1131: the UI translations `project.godot` names are the CSV import's
gitignored products, so a clean tree lacks them until then; the probe checks that the release pack loads both), adds the license notices to both builds
(#419: `CREDITS.md` and every `LICENSE*` file of the addons whose libraries a build ships, TwoVoIP's and
webrtc-native's, under `licenses/<addon>/` beside the `.exe`, one folder per addon since two could both be
`LICENSE`; and, #422, every file of `docs/credits/licenses/<folder>/` as `licenses/<folder>/`: Godot 4.7.2-stable's
`LICENSE.txt` and `COPYRIGHT.txt`, since the `.exe` is its template, and the `COPYING` of Opus, RNNoise and SpeexDSP,
built into TwoVoIP's library, each verbatim from its primary source, its URL and SHA-256 in
`docs/credits/licenses/README.md`; a new Godot pin or TwoVoIP release fetches them again), zips both into `tools/out/export/`, checks
that the release zip holds the release template's `.exe` byte for byte, the release libraries of TwoVoIP and
webrtc-native (#367), exactly the notices of `export.NOTICES` and no console wrapper (only a release template has
`OS.is_debug_build()` false, which turns off F3, the dev tools and the debug kinds), checks that the debug zip
carries the same notices, and proves the content hash in an export with
`tools/export/export_probe.gd` run
on the pack: every level and what it reaches found, a second tree's export equal, one byte changed in each level
a new hash; and, since the game's levels reach no other file yet, on `ContentFingerprint`'s test fixtures exported
from that tree: the walk reaches the same five files as in the project, and one byte of a reached resource or of a
texture's source changes the hash. The export converts `.tscn`/`.tres` to binary under `.godot/exported/` behind a `.remap`, and ships an
imported asset's products without its source; `ContentFingerprint` hashes what is shipped, so an export's hash
differs from a source run's (M6 ADR §2.5). The debug and the release zip of one commit have one hash and play
together, so a human who hosts with the debug zip sees hidden information through F3 (invariant 8: on that machine
only). About 3 minutes after the 1.3 GB download (#369's session). The workflow
`.github/workflows/release.yml` runs it on a pushed `v*` tag (never on a PR), with LFS content (unlike `verify`),
attaches only the release zip to that tag's GitHub Release (a re-run replaces it) and keeps the debug zip as a
7-day workflow artifact. The engineer tags a merged commit:
`git tag v0.6.0 <commit>; git push origin v0.6.0`. Opening Project > Export in the editor may add the default
options to `export_presets.cfg`: commit that once; never turn on `application/modify_resources` or
`binary_format/embed_pck`, or the release check fails. A new addon with a `LICENSE*` file goes into
`export.SHIPPED_ADDONS` (its notices into `NOTICES`) or, kept out of builds by both presets' `exclude_filter`, into
`UNSHIPPED_ADDONS` (gdUnit4); `test_export.py`'s `NoticesTest` (in `verify`) fails until it does, and also when a
`LICENSE*` file is added to or removed from a shipped addon without `NOTICES` following, as `export` would. Only
files named `LICENSE*` count (not `COPYING` or `NOTICE`) in an addon; in `docs/credits/licenses/` every file of a
folder of `export.BUNDLED` counts, and a folder there not in `BUNDLED` fails `NoticesTest` too.

### 11.25 `sfx-check <files or folders> [--page] [--category C] [--out DIR]` [applied] (#524)
The gate a sound file passes before it enters the game (#525 picks the sounds; `tools/runner/sfx.py`, tests:
`test_sfx.py`, whose WAV and Ogg fixtures are generated, never committed). Python standard library only (`struct`,
`array`, `json`): numpy or ffmpeg would be a new dependency and need an ADR. What each category must measure is data,
`tools/sfx/categories.json`: the allowed sample rates, the peak ceiling, the silence level, the leading-silence and
DC-offset limits, and per category (footstep, item, ui, task; no door: the engineer's decision of 2026-10-07 on #516
and #525, no doors in M6.2, not even door sounds) its file-name globs, RMS band and duration bounds. Its numbers are provisional, not a decision, until #525 tunes them on the real
sounds; a change to them is a table edit, not code. A WAV is read whole and fails, by rule, `format`, `pcm16`,
`mono`, `sample-rate`, `category`, `duration`, `peak` (with the count of samples at full scale), `rms`,
`leading-silence` or `dc-offset`. An OGG gets its identification header (Vorbis only; channels, rate) and its length
(the last page's granule position) checked and is "header-checked only": the standard library cannot decode Vorbis.
Mono or stereo passes for an OGG only (`sfx.OGG_CHANNELS`, #525: Kenney's packs ship stereo Ogg, and without ffmpeg
nothing folds one to mono; a stereo WAV still fails `mono`).
The JSON report goes to `tools/out/sfx/<set>.json`; exit 1 on any failure, each printed as `<file>: <rule>:
<numbers>`. `--page` also writes `tools/out/sfx/<set>.html`: one file with the sounds inside it as data: URLs (no
server, no external script or font; it still plays when moved), an `<audio>` per file grouped by category with its
numbers and failures, approve or reject and a note (kept in the browser's storage for that page), and "Export
verdicts", a JSON download that the engineer saves next to the set as `sfx-verdicts.json`.

### 11.26 `ui-sync [tag] [--check] [--force] [--source S]` [applied] (#288)
Pins the UI track's pack (xperiaroco2/prime-game-ui, `dist/pack/` at a tag `ui-<semver>`) for the generated theme
(`docs/ARCHITECTURE.md` §4.7.25; `tools/runner/ui_sync.py`, tests: `test_ui_sync.py` on a fixture repository built in
a temporary folder). It clones the tag with `--no-checkout` and reads the blobs with `git cat-file` (no working tree,
no line-ending conversion, no credentials: the repository is public; `--source` takes a local clone or another URL).
The pack is checked in memory before anything is written (`format`, a known `schema`, `version` = the tag, each
asset's sha256 against the pack's `assets` record), so a bad tag leaves the pinned copy as it was. Its JSON and SVG
files land byte for byte in `client/ui/theme/pack/` (`-text` in `.gitattributes`: git converts no line ending)
under a `.gdignore` (Godot imports none of it; nothing at run
time may read it, and exports leave it out), stale ones are removed, and `client/ui/theme/pack.lock.json` records
`{repo, tag, commit, files: {path: sha256}, imported: {path: sha256}, deferred: {path: sha256}}`. Every asset of the
pack's `assets` list (its icons and card art) also lands byte for byte in `assets/ui/toy_pack/`, which Godot imports
(#520, `docs/ARCHITECTURE.md` §4.7.34): the PNGs through LFS, each SVG's `.import` with the pack's `svg_scale` (a
minimal file where none exists, else only that line changed); commit the `.import` files the next import writes. A
binary outside the `assets` list (a font, later) is not landed and is listed under `deferred`. With no tag, or `--check`, it
verifies the pinned copy offline (each file against the lock, no extra or missing file, the `.gdignore`, the lock's tag against the pack's version, the schema, the
assets' sha256, nothing deferred on disk; the imported copy against `imported`, an LFS pointer file by its oid, each
SVG's scale, no pack asset left out); a tag already pinned and intact is not fetched again unless `--force`. A
runner test runs the same check on the committed copy, so a hand edit under `client/ui/theme/pack/` fails `verify`.
Then `tools\run.cmd run tools/theme/build_theme.gd --headless` regenerates the themes.

### 11.27 `ui-copy <tag> [--from DIR]` [applied] (#208)
The UI track's copy deck into the game: `copy/strings.csv` of xperiaroco2/prime-game-ui at a release tag
`ui-<major>.<minor>.<patch>` becomes `client/i18n/strings.csv`, byte for byte, and `client/i18n/strings.lock.json`
records the repo, the tag, its commit and the file's sha256 (the shape of #288's theme pack lock; `ui-sync` copies
the pack, not the deck, so the deck has its own step). It reads GitHub through `gh api`, or with `--from` a local
checkout of prime-game-ui (its tags fetched first). It refuses another tag form, a missing tag, a deck that is not
UTF-8, has CR line ends or a byte-order mark, or another header than `keys,en,uk,?plural,?context`, and then writes
nothing. Godot's import turns the deck into `strings.en.translation` and `strings.uk.translation` beside it
(gitignored, rebuilt by every import); commit the deck, the lock and a changed `strings.csv.import`. The game's side:
`docs/ARCHITECTURE.md` §4.7.26. Tests: `tools/runner/tests/test_ui_copy.py` (a throwaway git repository as the
checkout, and the committed deck against its lock).

## 12. The designer's agent

Optional since #518 (§9): the designer contributes when he wants, his PRs go to the engineer, and nothing below
waits on him; the engineer's sessions do the content work otherwise.

- **Onboarding [applied]:** after M0 merges, the designer opens the clone in Desktop and says "налаштуй мене".
  `onboard` runs `doctor` (which sets `core.hooksPath`), writes her user settings (`env`, `language`, `defaultMode`)
  after she approves the exact content, installs gdtoolkit via a real Python with her OK, and runs
  `git lfs install --skip-repo` (§8.3). It explains the save-first rule (§11.2) and the one-time answer to a guard
  prompt (§8.2.8). Then it prints the clicks only she can make: Git for Windows (required), Python 3.11+, Godot 4.7.2,
  repo and project invites, `gh auth login` + `gh auth refresh -s project`, trusting the folder, checking her Claude
  plan, usage credits off. It ends with a one-page summary for her sign-off, where she may reopen any decision that
  binds her.
- **Reads:** root `CLAUDE.md`, `content/CLAUDE.md`, `levels/CLAUDE.md`, `docs/GDD.md`, and the content API section
  of `docs/ARCHITECTURE.md` (the contract). **Effort:** medium.
- **By milestone:** M0–M1 GDD open questions, `mechanic` issues, review of the content-API draft · M2 first content
  `.tres` · M3 bot scenarios (`content/scenarios/`, `docs/ARCHITECTURE.md` §9.7) · M4 level pieces with `shot`
  screenshots; "запусти хост і двох клієнтів" is `tools\run.cmd host --clients 2`, which M4 gives windows (#149):
  the agent hands her that command for her own PowerShell (with the `cd`), since in the agent's shell the runner
  stays headless; a second machine runs `tools\run.cmd join <address>`. For its own check the agent runs
  `host --clients 2 --local --seconds S` headless (§11.8).

## 13. How humans talk to the agent

- Existing work: "start task 42". A new idea: "нова механіка: …" → `new-mechanic`.
- Issues contain: the goal, acceptance criteria as a checklist, what is out of scope, and the expected verification
  (screenshot, bot scenario or playtest).
- Size words: "plan first" → plan mode, then wait; "ultracode: …" → a bounded workflow (§7); a manager kickoff naming a
  stage or a list of issues (no "ultracode", `docs/MANAGERS.md` §2) → the orchestrator session (§7.1); "just do it" →
  small, obvious changes only.
- Dictation: say the issue number and describe the thing; the agent reads the file name back before editing and asks
  one short question only if a misreading would change what gets built. The glossary in `docs/HUMAN_SESSIONS.md`
  grows from real misrecognitions.
- **Two readings are read back:** when a human's answer to a design question could describe different things to build
  (the look or the mechanics), the agent says its reading back in one sentence and records it in an issue, an ADR or
  a design doc only after the human confirms. A wrong guess is otherwise copied into every task built on it.
<!-- see docs/interventions/2026-09-30-engineer-ghosts-look-not-flight.md -->
- Phrases: "запам'ятай" → the question in §3; "стоп" → stop and summarise; "поясни" → explain the pending prompt or
  step.
- **The agent explains choices plainly:** start from a concrete scenario of what goes wrong (which person, agent and
  machine), then the options; jargon comes after. Before designing enforcement, it asks how the humans actually work.
- Human-reserved decisions (KICKOFF §0) come as one batched question.

## 14. Open questions (deferred past M0)

| Question | When |
|---|---|
| Godot MCP server; if needed, prefer an in-game debug autoload plus the bot harness | M4 revisit |
| GDScript LSP bridge; Context7 (off; if ever used, pin `/websites/godotengine_en_4_7`) | After M2 |
| Trial the Superpowers plugin, engineer-only, on the M1 throwaway spike | M1, optional |
| Auto permission mode | After the M0 guard tests pass |
| The designer's machine: Claude Code version, plan, Python, Node, gh | Her onboarding |

**Pending human actions 👤** (the rulesets without bypass, the board workflows, the engineer's gh scope and
version, and the PATH `claude` are done, checked live 2026-09-29; LFS in CI decided 2026-10-07, §10): usage
credits off on both accounts; invite the designer to the repo and to project 1 (the designer's handle is in
CODEOWNERS since #85).

**Verification of the Phase A setup:** done on 2026-09-28. A fresh session confirmed subagent routing for all four
agents and the user-settings `env`. M0's `agents-check` makes the routing check repeatable.

## 15. Night jobs

([ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md) item 6, the engineer's N3 answer (c);
#189.) The night runs deterministic jobs on GitHub for free and one Claude audit lens on the engineer's PC.

| What | Where and when | Report |
|---|---|---|
| `nightly.yml`, job `flaky`: `tools/run.sh test --repeat 3` | GitHub Actions, free Linux runners, once per ref of the night and half of the suites (#1065): the latest `main` commit and the newest remote `release/*` branch (#272); 01:17 UTC every night (`schedule`), or by hand (`workflow_dispatch`, optionally one ref alone) | The run's summary page and an artifact per ref and half, `nightly-flaky-half<n>-<ref>` (`/` as `-`: `nightly-flaky-half1-main`, `nightly-flaky-half2-release-m5`); on a failure a comment with the run link on the "Night jobs" issue naming each job's ref |
| `nightly.yml`, job `perf`: `tools/run.sh perf` (10 bots over the loopback, a 60 s round) with `--baseline` the same ref's last successful night's report | The same run, per ref | The run's summary page and artifact `nightly-perf-<ref>`; changes beyond the threshold are listed there, never a failure; a failed match comments like `flaky` |
| `nightly.yml`, job `chaos` (#188): `tools/run.sh bots --chaos --long --runs 10` from a random seed (printed), then `bots --chaos --long --enet` | As `flaky` | Artifact `nightly-chaos-<ref>` (the logs; a failed loopback seed is named in `tools/out/logs/chaos-loopback.log`, the ENet run's in `tools/out/logs/run/chaos_main-1.log`); on a failure a comment with the run link on the "Night jobs" issue |
| `nightly.yml`, job `lfs` (#1213): `git lfs pull --include` of only `assets/characters/slice_m1/` and the two House kit GLBs that `character_rig_art_test.gd` and `house_wrapper_test.gd` load (11,938,695 bytes, about 12 MB a night), then `tools/run.sh test` of those two suites | As `flaky`, once per ref; they print "skip" in CI, which has no LFS content | Artifact `nightly-lfs-<ref>`; red when a pull leaves a pointer file or a suite fails; a failure comments like `flaky` |
| The skill `night-audit`: one lens a night by weekday (docs drift, decisions vs docs, coverage, flaky, dead code) | The engineer's PC: the Desktop scheduled task `night-audit` (23:30 local) starts it in a detached worktree at `origin/main`; by hand, for a missed night, a manager runs it as a workflow (the skill's "Scheduled, and as a workflow") | Confirmed findings as issues (`Found by: night-audit <lens>`); a summary comment on the "Night jobs" issue |

- **`test --repeat N`** runs the GdUnit4 suites N times in a row, in real time (the #222 class,
  #341; `verify` runs the frame-bound suites at fixed fps); any failed run fails it.
  Each run takes as many processes as `test` would (§11.19: `--shards K`, else one for named paths, else
  `PRIME_TEST_SHARDS`, else half the CPUs; `<paths> --fixed-fps --shards K` runs every shard at fixed fps),
  because one real-time process outgrew the runner's `TIMEOUT` of 600 s per process when the suite grew past about 300 suites (#817: nightly run 38120577422, all three runs of
  `flaky on main` timed out). Since #1065 the job is one job per half of the suites (`gdunit.half_of`, the split of
  CI's `test-1` and `test-2`), each on its own runner with `PRIME_TEST_HALF=<n>`: `test --repeat` without paths runs
  only that half (nightly run 38689352624: the art House's suites, about 1400 s a run, made one job's two shards hit
  645 s in all three runs). Each sets `PRIME_TEST_SHARDS=2` (CI's 4 vCPUs) and restores the per-suite times of an
  earlier night of its half (else CI's `test-<n>` save, #980, else any), to balance the shards (a suite CI times at
  fixed fps alone counts its seconds there x `FIXED_FPS_SPEEDUP`); a release ref whose runner is older ignores the variables and runs every suite in one
  process per run, as before, so the job's options check (`test --repeat`) did not change. A shard's limit is 600 s, or
  1.5 x its expected seconds when longer, at most 900 s (`gdunit.shard_timeout`, #970): when a half outgrows two
  shards, raise the job's count. Only a green job saves its times (the cache's post step).
  Each run's report goes to `tools/out/gdunit-runs/run-<i>/` (the shards' merged `results.xml`) and its log to
  `tools/out/logs/test-run<i>.log` (sharded: also `test-run<i>-shard<j>.log`);
  `summary.json` (every suite: tests and failures per run; flaky tests; tests failed in every run) and `summary.md` (the same for suites with a
  failure) sit next to them. A test that passed in one run and failed in another is flaky; one with no result in a
  run (it crashed or timed out) or skipped in it counts neither way.
- **Which refs** (#272): the job `refs` picks them at run time: the run's own ref (`main` on the schedule) and the
  newest remote `release/*` branch by version order (`release/m10` after `release/m9`; none: `main` alone; one at
  `main`'s commit: once), each resolved to one commit for all its jobs. `workflow_dispatch` with the input `ref` (a
  branch, tag or commit) runs that ref alone. The schedule always runs `main`'s `nightly.yml`, but each job checks
  out its ref's commit, so a release ref runs its own setup action, `tools/run.sh` and tests (a release's extra
  suites get the same nights as `main`). A step first asks the ref's runner (`--help`) for the options the job
  calls: an older runner fails there, naming what it lacks. Every job also removes the TwoVoIP extension as M5's
  CI does (`rm -f`, so nothing on a ref without it), and keeps webrtc-native, which loads on Linux (E57, #367).
  The refs' jobs run side by side (`fail-fast: false`); each ref adds its jobs' runner minutes (`main`'s three took
  about 16 on 2026-10-03), free in this public repository.
- **One setup:** `ci.yml` and `nightly.yml` install the pinned Python, Godot and gdtoolkit through the composite action
  `.github/actions/setup-toolchain`, so a pin change still edits only `tools/runner/pins.py`. Each night job is one job
  in `nightly.yml`, a matrix over the refs (checkout of the ref, the setup, the options check, one runner command, an
  upload); the job `report` lists them and `refs` in `needs` and comments when one failed or timed out, creating the
  "Night jobs" issue (`area:tooling`) the first time; its comment lists every job of every ref with its conclusion (the
  job names hold the refs). `report` alone gets `issues: write` and `actions: read` (the run's job list); the rest has
  `contents: read`. `perf` (#187) keeps its report for the next night of the same ref in an `actions/cache` entry
  (`tools/out/perf-last/last.json`, key `nightly-perf:<ref>:<run id>` restored by the prefix `nightly-perf:<ref>:`,
  saved only when the job passed), which needs no permission beyond `contents: read`; the long chaos run is the job
  `chaos` (#188). `tools/runner/tests/test_github_workflows.py` parses every workflow and action and checks the
  triggers, permissions, the shared setup, `needs`, the refs' matrix and artifact names, and that no action beyond the
  four CI already uses appears (a new one is the engineer's call); it also runs the bash of the `refs` step and of the
  options check with stubs for gh and the runner.
- **GitHub's limits** (docs.github.com, "Events that trigger workflows", read 2026-10-02): a scheduled run uses the
  latest commit on the default branch and may start late at busy times; in a public repository the schedule is
  disabled after 60 days without activity (Actions → Nightly → Enable workflow); `workflow_dispatch` works only once
  the file is on the default branch, so a new workflow's first run is by hand after the merge; since then
  `gh workflow run nightly.yml --ref <task branch>` runs the task branch's version of the file.
- **A scheduled task starts it:** the Desktop scheduled task `night-audit` (daily at 23:30 local, about 20:30Z); the
  meta manager no longer launches it as a workflow before the night (the engineer's answer,
  [#302 comment 6166579802](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6166579802), item 2,
  reversing [comment 6107272934](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6107272934), where
  the first scheduled session stalled on a permission card in acceptEdits). A manager runs it as a workflow by hand
  for a missed night or a lens on its own.
- **Bounds of the audit** (in the skill): one lens, as a workflow 3 agents (the auditor, one skeptic of type
  `night-skeptic` and a filer; by hand 2, no filer), about 100 tool calls, about $10 list a night; read-only on the
  repo (issue bodies in its worktree's `tests/scratch/`), at most 5 issues a night, never closes or edits issues.
  Lenses beyond docs drift are the first thing to drop: set every weekday in the skill to `docs-drift`.

**Reading the reports.**
- A comment on the "Night jobs" issue from the nightly workflow: open its run link. The summary page shows "GdUnit4,
  3 runs": each run's status, **flaky tests** (an issue to fix the test or the race; never skip or delete it without
  the engineer's approval), **failed in every run** (a regression on that ref: fix first), and the suites with a
  failure, once per ref (the job's name holds it). The artifact `nightly-flaky-half<n>-<ref>` holds each run's HTML
  report of that half, `summary.json` and the logs. A failure on a release ref alone is the release's own (fix it on `release/m<k>`).
- The perf job's section of the summary page: its numbers with the wire budgets' headroom, and the metrics that
  moved by more than the threshold against the last night. A jump in the host step or the bytes per peer after a
  merge is worth an issue (timings on a shared runner are noisy: look for a move that stays); the artifact
  `nightly-perf-<ref>` holds the report JSON and the run's log. The first night after #272's merge compares `main` with
  nothing (its cache key now holds the ref), and a new release branch's first night likewise.
- A night-audit summary (one a night, first line `night-audit <lens>, <date>, origin/main <sha>`): what it checked,
  the issues it opened, and what the skeptic refuted or could not decide (those are not issues). Its issues:
  `gh issue list --search "\"Found by: night-audit\" in:body"`. A wrong one is closed by a human (label `invalid`).

**The engineer's one-time setup 👤:** after the merge, start the first nightly run by hand and check it:
`cd D:\prime-game; gh workflow run nightly.yml --ref main`, then `gh run list --workflow nightly.yml --limit 1`
(`-f ref=release/m5` added: that ref alone).
