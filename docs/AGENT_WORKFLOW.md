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
  accidents and lost work, not attackers. Do not add privacy or security hardening that nobody asked for. Secrets
  (tokens, keys) are still never committed.
- **Humans write zero code** (KICKOFF §0). The agent verifies its own work from the command line and never claims
  something works without running it.

## 2. Environment

| Item | Decision | State |
|---|---|---|
| Surface | The Claude desktop app (Code tab), ≥ 2.1.281 on both machines. The `claude` on PATH is updated or removed 👤 so Rider cannot start an old build. `doctor` fails below 2.1.281 | 👤 / [M0] |
| Shell | PowerShell 5.1 is the agent's primary shell. No `&&`/`||`: chain with `; if ($LASTEXITCODE -eq 0) { … }`. Structured arguments go in files, not inline JSON | [M0] root `CLAUDE.md` |
| Machine paths | `GODOT_BIN`, `GODOT_GUI_BIN`, `PYTHON_BIN`, `GDTOOLKIT_DIR` in the `env` of each human's `~/.claude/settings.json`, so every session, worktree, hook and subagent sees them ([ADR](decisions/2026-09-28-machine-env-in-user-settings.md)). A human's own terminal needs no Windows variables for them: before any command the runner fills each one the process environment lacks from the `env` of the project's `.claude/settings.local.json`, then of `~/.claude/settings.json` (`$CLAUDE_CONFIG_DIR/settings.json` when that is set), and `tools\run.cmd` finds `PYTHON_BIN` there before Python starts. The process environment wins; `doctor` says where each came from and warns when none has it | [applied] engineer |
| Personal settings | Each human's `~/.claude/settings.json` holds `"language"` and `"permissions": {"defaultMode": "acceptEdits"}`. Personal rules go in `~/.claude/CLAUDE.md`. Nothing personal in shared files | [applied] engineer |
| `.claude/settings.local.json` | Personal permission approvals, plus in the main checkout on Windows the `claudeMdExcludes` pattern that the full `doctor` adds (§3 "Which copy loads", #385); gitignored and untracked | [applied] |
| Godot import scope | `docs/.gdignore` keeps the editor from importing anything under `docs/` | [applied] |
| Auto mode | Not yet. Revisit after the M0 guard tests pass (§14) | — |

### 2.1 Cloud sessions
A Claude Code cloud session (claude.ai/code, a Linux container with a fresh clone) runs `tools/run.sh verify` as CI
does (#159, #345). **First command of every cloud session:** `tools/cloud/setup.sh`, then `tools/run.sh doctor`.
- **`tools/cloud/setup.sh`** (from any folder; idempotent; 7 s in #345's session, the Godot download included): installs
  the pinned Godot Linux build in `~/godot/godot` (SHA-512 checked) and links it as `godot` on PATH, installs the pinned
  gdtoolkit with pip, and raises `net.core.rmem_default` to 416 KB when lower (some container kernels hold only 256
  small datagrams in the 208 KB default; verify's stall step queues 320). **In a cloud session only**
  (`CLAUDE_CODE_REMOTE=true`) it also leaves the Windows-only TwoVoIP extension (`addons/twovoip/twovoip.gdextension`
  and its `.uid`, the M5 voice ADR §2) out of the clone with a non-cone sparse checkout, as CI deletes them: on Linux
  Godot prints an `ERROR:` line for the extension and every Godot step of `verify` fails. git still tracks both files,
  so `git status` stays clean and no commit can take their deletion; `git update-index --skip-worktree` alone brought
  the file back on a switch to a commit that changes it, on `reset --hard` and in a new worktree, and the sparse
  patterns held through all three. Undo with `git sparse-checkout disable`. If Godot imported the project before, a
  `run` still loads the extension until the next `check` (ARCHITECTURE §6, "The addon in the repo"); `verify` runs
  `check` first. `doctor` (also `--quick`, so `verify` stops at once) fails in a cloud session while the `.gdextension`
  is in the working tree or was deleted by hand, and names the fix; it skips the machine paths and `gh` there, as on CI.
- **As the environment's setup script** (not yet tried): such a script runs before Claude Code starts, and the
  environment caches the resulting filesystem while each session starts from a fresh clone
  (code.claude.com/docs/en/cloud-environments), so the sparse checkout and the sysctl may not reach a later session,
  nor is it documented that `CLAUDE_CODE_REMOTE` is set at that point. Hence the first command above; `doctor` says
  when it is due. The sysctl also fell back to 212992 within #346's session (seemingly when the idle VM was restored),
  and `verify`'s `freeze` and `stall` failed until `setup.sh` ran again: rerun it whenever `doctor` warns.
- **Python:** the image's `python3` is 3.11, the runner's minimum (`pins.PYTHON_MIN`; 3.10, 3.12 and 3.13 are
  installed too), while CI's `verify` runs 3.12; #345 fixed three 3.12-only spots that broke `verify` and `selftest` on
  3.11, and since #349 CI's job `python-min` keeps the minimum true.
- **Network access** (what #345's session used): `github.com` with `release-assets.githubusercontent.com`
  for the Godot zip, `pypi.org` with `files.pythonhosted.org` for gdtoolkit. The session's proxy refuses API calls and
  feeds of other GitHub repositories ("sessions are bound to their configured repositories"); the WebFetch tool still
  reads public pages (docs, release pages) for research.
- **GitHub:** `gh auth status` calls the token invalid, yet `gh api` REST calls on this repository go through the
  session's GitHub proxy (`gh api user`, `gh api repos/{owner}/{repo}/issues/<n>`). GraphQL is refused (HTTP 403), so
  `gh issue view`, `gh pr create|view|checks` and `gh project` fail, and with them the runner's `start`, `board` and
  `merge`. Read issues and open PRs with the session's GitHub tools, leave the board column to the manager, and push
  with `publish --base <base>` (it needs no `gh` when given the base) or a plain `git push -u origin <branch>` after
  a green `verify`.
- **Task branches**: the container starts on its own branch; switch to the task branch from its base
  (`git fetch origin <base>; git switch -c <area>/<n>-<slug> origin/<base>`, then `git branch --unset-upstream`, so
  nothing tracks the base).
- **Agents:** the subagents in `.claude/agents/` run there (#345: `code-reviewer` on its diff, and `agents-check`
  passed on its transcript). The Workflow tool is offered, under the `small` size guideline; #345's session launched
  none.
- **Timing (measured in #345's session, 4 CPUs):** `doctor` 5 s; a full `verify` 6 minutes (the Python lane 3.8,
  the Godot lane 5.9; `test` 3.4 and `selftest` 3.3 the longest).
- **Cannot**: open Godot windows (`run` without `--headless`, the editor), take a `shot` or run `playcheck` (they
  stop with "needs a desktop session with a GPU"), or do the Windows-only steps (`tools\run.cmd`, PowerShell, the
  humans' settings files, the TwoVoIP round trip).

## 3. Instruction files and memory

| File | Loaded | Content | Budget |
|---|---|---|---|
| Root `CLAUDE.md` (engineer-owned) | Always; re-injected after compaction (which copy: "Which copy loads" below) | Hard rules, **architecture invariants**, exact runner commands, PowerShell rules, ownership map, skill routing, definition of done, stop-and-ask list, memory guardrail, dictation glossary | ≤ 150 lines, counting unscoped rule files |
| `core/ server/ net/ client/ voice/` `CLAUDE.md` | When a file there is read | Engineer area rules | ≤ 100 lines each |
| `content/ levels/` `CLAUDE.md` (designer-owned) | Same | How to author mechanics and maps without engine code | ≤ 100 lines each |
| `.claude/rules/*.md` with `paths:` | When a matching file is touched | `gdscript.md`, `tests.md`, `godot-resources.md` | ≤ 60 lines each |
| `docs/*.md` | Only when read | Architecture (with the **content API**), GDD, roadmap, ADRs. Linked, never `@imported` | none |

- Invariants live in root because nested files drop out after compaction
  ([ADR](decisions/2026-09-29-instruction-files-and-budgets.md)).
- **Which copy loads** (Claude Code 2.1.284, probed in #336). A session started in the main checkout (the manager,
  its workflow agents, and a task session that works in a worktree through `cd`/`Set-Location`, §4.1) loads main's
  root `CLAUDE.md` at launch. A Read of a file under `.claude/worktrees/<n>/` then also loads that worktree's root
  `CLAUDE.md` (a second copy, about 6k tokens at #336), its area `CLAUDE.md`, and both main's and the worktree's copy
  of each matching rule. A session started inside a worktree loads only the worktree's copies: its root `CLAUDE.md`
  at launch, never main's, and its area files and rules by path. So `claudeMdExcludes` with
  `**/.claude/worktrees/*/CLAUDE.md` in the tracked `.claude/settings.json` is wrong: the tracked file is also each
  worktree's own settings, and in a session started inside a worktree the pattern matches the only root `CLAUDE.md`
  it has (a probe session started there with it loaded none).
- **[applied] The exclude lives in the main checkout's `.claude/settings.local.json`** (#385, the engineer's option
  (a) on PR #360). On Windows Claude Code reads the local settings file of the folder a session starts in
  (code.claude.com/docs/en/settings, "Where Claude Code keeps the local file"; elsewhere a worktree session uses the
  main checkout's file instead). #385's probes, Claude Code 2.1.284, in a replica of this layout (a main checkout
  with the same root, area and rule files and a `git worktree add` under `.claude/worktrees/1`), the exclude only in
  main's `settings.local.json`: a session started in the worktree still loaded the worktree's root `CLAUDE.md` at
  launch (with the exclude also in the worktree's own `settings.local.json` it loaded none, so the pattern does
  match); a session started in the main checkout that Read worktree files loaded main's root `CLAUDE.md` at launch
  and, by path, the worktree's area files and both copies of each rule, but no worktree root `CLAUDE.md`.
  `tools\run.cmd doctor` (the full one; `onboard` runs it) adds the pattern to that file, merged into what is there
  (never to a file under `.claude/worktrees/`, should git fail to name the main checkout); `doctor --quick` (and so `verify`) only warns when it is missing. Neither touches it in CI or off Windows, where
  it would take a worktree session's only root `CLAUDE.md`. So a workflow agent reads a worktree's root `CLAUDE.md`
  only by Read; the rules still load twice by path (main's copy and the worktree's).
- **[applied]** All files in this table exist (M0 stage 3). `tools\run.cmd lint` (part of `verify`) fails over
  budget. It counts the lines Claude Code loads: frontmatter and block-level HTML comments are left out, so the
  `<!-- see docs/interventions/… -->` notes are free. It also fails on rule frontmatter that would not parse (Claude
  Code would then load the rule at every launch). The same PR then scopes a rule to paths, moves it into a skill, or
  retires it, and the intervention entry says which.
- **Auto memory stays on.** It never holds shared rules or task state. "Запам'ятай / remember" gets one question
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
   the agent works freely (§8.2), and the main checkout, where the Godot editor and the humans' files live, stays
   protected. `--here` is the exception that keeps the task in this checkout, and so do `--stash` and `--include`
   (they act on this checkout's changes) and a branch already checked out here. The designer never gets a worktree:
   with another Claude session active on this checkout, `start` stops rather than switch the branch under that
   session (`--here` when the human says it is idle). Work in the worktree: a session opened in that folder, or,
   for a task session whose shell starts in the main checkout, `cd <worktree> && ...` (Git Bash) or
   `Set-Location <worktree>; ...` (PowerShell) at the start of every command. `tools\run.cmd worktree-done <n>`
   removes the worktree, and its own `user://` folder (§11), once its branch is merged
   ([ADR](decisions/2026-09-28-worktrees-only-for-parallel-sessions.md)); `--pushed` also removes one whose branch is
   never merged (a spike) once `origin/<branch>` holds all its commits, and keeps that local branch. Run it from the
   main checkout: Windows cannot delete a folder a process sits in, so it refuses when the current folder is inside the
   worktree or any live Claude session (even one idle for days, or the calling one) has it as its folder; archive that
   session in the app first. A rerun finishes a half-done removal (an empty leftover folder, the issue's merged local
   branch).
5. Restate goal, acceptance criteria, plan, verification commands and risks. Non-trivial work: plan mode, wait for "go".

### 4.2 Finish: "finish" / `/finish-task` (definition of done)
1. `tools\run.cmd verify`; paste the tail. Red → stop and report. Never weaken a test. `verify` runs the bot
   matches too (`bots` and `bots-enet`, §11). A workflow agent or subagent (a 5-minute prompt cache) runs it in the
   background and polls it with `wait` in calls of at most 240 s (§11, "Bounded waits").
2. Fresh-context review: `code-reviewer` for code diffs (bundled `/code-review` at medium, or none, for docs-only and
   content-data diffs); plus `netcode-security-reviewer` if `core/`, `server/`, `net/`, `client/` (what it renders
   can leak) or `tests/harness/` (the information-leak test) changed; plus
   `godot-api-checker` if `.gd`, `.tscn` or `.tres` changed. Fix findings or list them in the PR.
3. Update docs if durable knowledge changed; add intervention and credit entries if any.
4. In the engineer's sessions (`gh api user` is the engineer's account, the `*` owner in `.github/CODEOWNERS`) no
   question: publish once 1 to 3 hold ([trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)).
   In the designer's sessions, or when unsure, one question: **"Publish now? (push + PR + handoff comment)"**.
5. `tools\run.cmd publish`: rebase on the open PR's base (else the `start --base` parent, else `origin/main`), re-run
   `verify`, push the task branch with a lease (§8.3). Under `bounded_waits` (§7.1) the publishing agents of
   `issue-task` and `pr-rebase` run no standalone `verify` before `publish` when `tools\run.cmd wait --verified` exits
   0 (the newest verify passed at HEAD with a clean tree), since `publish` runs it anyway.
6. Open the PR from the template: `Closes #42`, summary, verification commands and output, `shot` screenshots for
   visual changes, docs updated yes/no, `--reviewer <other human>` if the other owner's paths are touched.
7. Handoff comment on the issue (done / left / decisions / gotchas); board item → **In review** via the runner.

### 4.3 Context hygiene
- One issue per session; a new issue starts a new session.
- `/clear` between unrelated tasks, after two failed corrections on the same point, and after a plan is approved
  when the plan is enough to implement from.
- After compaction, re-read the area `CLAUDE.md` before editing.

## 5. Subagents and models

Files in `.claude/agents/` **[applied]**. Five are read-only: no Edit, Write or NotebookEdit, `disallowedTools`
includes `Agent`, no `memory:` field. The two lean writers `task-implementer` and `task-publisher` are the one
exception ([ADR](decisions/2026-10-04-lean-workflow-agent-types.md), #332): only `issue-task` and `pr-rebase`
launched with `lean: true` use them (§7.1); each keeps to its `tools:` allowlist, disallows Skill, NotebookEdit and
Agent, and sets no `effort:`. No agent file sets `permissionMode`, so every subagent runs in the session's mode;
`tools/runner/instructions.py` (`lint`) enforces both kinds. Their shell use is limited by the shared permission
rules.

| Agent | Job | Model |
|---|---|---|
| `godot-api-checker` | Check changes against the pinned Godot 4.7.2 API; flag Godot 3 idioms. Sources: `check`, the engine API dump, `docs.godotengine.org/en/4.7/` only | `sonnet`, effort high |
| `test-runner` | Run test / lint / check / bots via the runner; return only failures | `haiku` |
| `code-reviewer` | Review the branch diff against `CLAUDE.md`, `ARCHITECTURE.md` and the content API | `opus`, effort high |
| `netcode-security-reviewer` | Information leaks, unvalidated intents, host-trust assumptions | `opus`, effort high |
| `night-skeptic` | Re-check the night audit's candidates against the repo and GitHub runs: CONFIRMED, REFUTED or UNSURE each (§15) | `opus`, effort high |
| `task-implementer` | `lean: true` only: the implementer, the plan agent and the test reviewer of `issue-task`, in the task worktree, with a lean tool set (no Skill tool: it reads a skill's `SKILL.md`) | `opus`, effort from the workflow's role |
| `task-publisher` | `lean: true` only: the publisher of `issue-task` and the rebase and fix agents of `pr-rebase`; the implementer's tools plus SendUserFile | `opus`, effort from the workflow's role |

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
  printed with their label and run: a default launch's meta file has no `model` (a reviewer, or a `lean` implementer
  or publisher, is judged by its agent file; an implementer or publisher of `agentType` `workflow-subagent` inherits
  the session's model and is only listed, unless a model in neither list served it: a failure); a `models` launch is
  read from `model`, as the Agent tool records it, and any other meta key that names a model, at any depth
  (`request.model`), fails until the reader learns it. After a launch that passes `models`, `agents-check` in the
  manager's session checks it. `finish-task` runs it after the reviews.
- A new `.claude/agents/` directory is only seen by sessions started after it exists.

## 6. Skills [applied]

Committed in `.claude/skills/<name>/SKILL.md` (M0 stage 6); no plugins. The two designer skills are designer-owned
and wait for the designer's review.

| Skill | For | Does |
|---|---|---|
| `start-task`, `finish-task` | both | §4.1, §4.2 |
| `new-mechanic` | designer | Front door for an idea: interview → `mechanic` issue + `engine-request` issues (stop for OK) → `start-task` → GDD section with open questions and **no invented content**; content data only once the content API exists (M2+) |
| `new-level-piece` | designer | A room or interactable sub-scene per the level conventions; `normalize`; `shot` screenshot |
| `log-intervention` | both | Writes a `docs/interventions/` entry and promotes the rule in the same PR (§10) |
| `onboard` | both | "налаштуй мене": runs `doctor`, writes user settings after approval, prints the human-only checklist (§12) |
| `orchestrate-stage` | engineer | An "ultracode" kickoff for a stage: the manager session runs one `issue-task` workflow per issue (§7.1) |
| `night-audit` | engineer | The prompt of the nightly Desktop scheduled task: one read-only audit lens, every finding re-checked by one skeptic, issues and a summary on the "Night jobs" issue (§15) |

- No skill is named `doctor`, `verify` or `run` (they would replace bundled commands).
- All skills are model-invocable, so a dictated "заверши задачу" works; publishing still asks once.
- `start-task` and `finish-task` never use `context: fork`. `allowed-tools` carry Bash and PowerShell forms.
- The Python runner lints agent and skill frontmatter in `verify` [applied], so CI needs no Claude Code install.
  For skills: strict YAML subset, `name` = folder, no unknown field (Claude Code ignores one silently), the rules
  above, `description` + `when_to_use` within the 1,536-character listing cap, and a PowerShell twin for every Bash
  rule. `claude plugin validate .claude/skills` is no substitute: it passed a description YAML cannot parse.
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
| Manager sessions (§7.1) of every track, and the art and UI sessions | high, not xhigh (the ADR's amendment of 2026-10-04; the human sets it in the session settings) |

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
- **How:** one session in ultracode, the **manager**, runs the skill. For each task it runs `start` itself, then the
  saved workflow `issue-task` (`.claude/workflows/issue-task.js`: implementer → fresh reviewers chosen from the
  changed paths → publisher; `design: true` for a docs-only design task) with `args` (issue, worktree, branch, base,
  notes, coordination, the engineer's decisions). A semantic conflict after a merge goes to `pr-rebase`
  (`.claude/workflows/pr-rebase.js`); a docs or test-list conflict the manager resolves inline. A session runs a
  saved workflow as `/issue-task`, or with the Workflow tool by `name` or `scriptPath`; after editing one, a running
  session needs `/reload-skills` (code.claude.com/docs/en/workflows). Both route `netcode-security-reviewer` by the
  same paths as §4.2, `client/` included: a leak through rendering is an information leak (#158).
  `tools/runner/tests/test_workflows.py` runs both scripts under Node with stub agents and checks their routing and
  rules (skipped where Node is missing, except on GitHub Actions, where a missing Node fails it). Workflow agents
  read their prompt, not this file, so the rules every agent of both scripts gets (all but the read-only reviewers)
  carry one line each for the two calls that stopped them most (#312, #326): read the hooks path with
  `git rev-parse --git-path hooks` (§8.1), and wait with `wait <log>`, `run_in_background` or Monitor, never a
  foreground `sleep N; cat <log>` (§11, "Bounded waits"); the test pins both lines, identical in the two scripts.
- **Pipeline v2 options** ([ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md), item 4; #180):
  optional `issue-task` args, all off by default, so a launch or a resume with the earlier args gets the earlier
  agents byte for byte (`tools/runner/tests/workflow_snapshots/` holds their prompts and options for representative
  arg sets). `plan_review: true`: a plan agent and a fresh critique of its plan before the implementer, summarized
  in the PR (+2 agents). `test_review: true`: after the reviews one agent plants 3 to 5 faults in the diff's
  production code with `tools\run.cmd mutants` (#184), each in a scratch worktree; a survived mutant is a finding,
  and the publisher stops and reports when `mutants` exits 2; the result's `stopped` then says to relaunch, not
  resume (+1; none for a design task or a diff without `core/ server/ net/ client/ voice/` code). `second_review:
  true`: a second `netcode-security-reviewer` with an attacker's lens wherever the netcode review is routed (+1).
  `skeptic: true` or a number: a read-only agent tries to refute each blocker or major finding before the publisher
  (a number caps the agents); refuted ones are listed in the PR with the reason (+1 each). `visual: true` (the
  scenarios the notes name), a scenario or a list: the implementer runs `tools\run.cmd playcheck` (#186), the code
  reviewer reads the PNGs, and the rule on Godot windows also allows `playcheck` (+0). `efforts` and `models`: per
  role (implement, plan, plan_review, review, netcode, second_review, godot, test_review, skeptic, publish,
  publish_clean); `efforts.implement` falls back to `effort`, a reviewer gets an effort or a model only when one is
  set, and no default names a model (the model-guard ADR); a model beyond the shared list goes only into a launch's
  `models`, where the kickoff allows it (its amendment A, §5). `publish_clean` (#308, a one-wave trial; falls back to
  `publish`) is the full publisher of a run with no blocker or major left open after the reviews, the test review
  and the skeptics, never of a design task; the result's `publish_clean` says whether it applied. A missing
  `mutants` or `playcheck` on the task's branch is reported in the result and the PR, and the run goes on.
  `bounded_waits: true` (#303; `issue-task` and `pr-rebase`, +0): each agent that runs `verify`, `publish`, `mutants`
  or a CI watch gets one paragraph, after the steps it replaces, with the exact background launch, `wait` and CI
  commands of §11 "Bounded waits" (its publishing agents also skip a standalone verify that `wait --verified` shows
  done). The root CLAUDE.md rule reaches every workflow agent without it once on main; the arg adds the commands.
  `pr-rebase` takes `second_review`, `skeptic`, `bounded_waits`, `efforts` and `models` (roles rebase, review,
  netcode, second_review, skeptic, fix); when skeptics refute every blocker or major, no fix agent runs and the
  result's `note` asks the manager to list the refuted findings with their reasons in the PR body. The kickoff's
  approved agent count must cover the options the manager will pass; each script's
  `whenToUse` and args comment give the counts, the roles and their fallbacks.
- **Lean agent types** ([ADR](decisions/2026-10-04-lean-workflow-agent-types.md), #332): `lean: true` (`issue-task`
  and `pr-rebase`, +0 agents, off by default) runs the implementer, the plan agent and the test reviewer as
  `task-implementer` and the publisher, the rebase and the fix agents as `task-publisher` (§5), with no desktop, MCP
  or Skill tools. The ADR's CLI probe measured a lean first call of about 20k tokens before the task prompt, against a
  median of about 57k for a general implementer's whole first call under a desktop manager; the A/B measures the real
  difference. It appends only `agentType` to their options; prompts, efforts and models stay. Opt-in until the
  manager's A/B on 3-4 tasks (results on #302) and the engineer's call on the default; the manager's checkout must
  have both agent files (`agentType` resolves there), and a task whose agents need a skill through the Skill tool
  stays off it.
- **Bounds:** at most three tasks at once; implementer about 250 tool calls, reviewers about 60, publisher about
  150; with the v2 options the plan agent about 80, its critique about 40, the test reviewer about 60, each skeptic
  about 30, and a publisher that only reports a stop about 30. Every agent writes temporary files only under its
  issue's scratchpad subfolder `a<n>/`. `issue-task` runs up to five agents (more with the v2 options above), over
  the `small` guideline, so the kickoff approves that and the stage's budget once; within 15% of the weekly limit per
  stage or track the manager's restatement is a report and it goes on, above it or for an "ask and wait" item it
  waits for the human's yes (§7, the [trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)).
  Code tasks wait for the engineer's review of the stage's design PR; before
  launching anything, the manager lists the runs another session may still own (issues In progress with no PR, fresh
  worktree commits, a rebase in progress) and asks.
- **Git flow** ([ADR](decisions/2026-10-01-release-branch-per-milestone.md)): each milestone gets `release/m<k>` from
  `main`, and every task PR of the stage targets it (`start --base release/m<k>`, `publish --base release/m<k>`). Before
  each merge the manager runs `tools\run.cmd merge-check` (#181): every open PR onto its base tip and each pair into the
  same base, textually (`git merge-tree --write-tree`) and by symbols (what one side removes, renames or changes, used
  by the other side's added lines: GDScript and runner Python members and signatures, wire rows and fields, `.tres`
  fields, deleted files; a signature that only appends parameters with defaults is a note, not an overlap, #207); and,
  across bases, each PR with every open PR into another base when both change a shared file, the same one or different
  ones (Parallel tracks below); seconds, no Godot; a Markdown table per base and one across bases for the wave comment,
  each overlap with file:line on both sides, exit 1 on a conflict, an overlap or a PR it could not check (its base gone
  from origin). On an overlap it merges the side that changes the symbol first and has the other rebased (`pr-rebase`),
  or first runs `merge-check --trial <pr>...`: the base plus the PRs merged in order in a scratch detached worktree
  under `tools/out/merge/`, that tree's own `verify`, then the worktree removed. The manager merges a task PR once CI is
  green, the fresh reviews left no open blocker or major, and `verify` passes on the merged tree, with `tools\run.cmd
  merge <pr> --base release/m<k>` from the main checkout or its `release-m<k>` worktree (into `main` only through the
  gate below; it refuses any other base and a task's checkout): fetch (a PR a human already merged is only fetched),
  green CI (`gh pr checks`), `git merge --no-ff` with GitHub's message in a scratch detached worktree at
  `origin/release/m<k>`, `verify` on the merged tree (always: no shortcut for an unchanged tree; a red run or a conflict
  pushes nothing and leaves nothing to undo), `git push origin <commit>:refs/heads/release/m<k>` by hash (a fast-forward
  the pre-push hook allows; the deny rule `git push *HEAD*` refuses `HEAD:` typed by hand), the scratch worktree
  removed, the PR confirmed merged on GitHub, and one `wave:` line for the wave comment. Its `verify` takes minutes: run
  it with `run_in_background`. At a wave boundary, when the AI productivity track (#170) says `main` has something the
  stage needs, `merge --sync-main --base release/m<k>` takes `origin/main` in the same way. Its git commands run inside
  the runner, so the session types only `tools\run.cmd merge ...`, which runs without a prompt from the main checkout
  and from the `release-m<k>` worktree. A red `verify` of `merge` or `merge-check --trial` keeps the merged tree's logs
  and GdUnit reports in `tools/out/merge-logs/<log>/`. A typed `gh pr merge` stays denied (the `main` rulesets ask only
  for a PR and green checks, so it would let any agent merge into `main`). The stage ends with one PR from
  `release/m<k>` into `main`, which the manager merges through the gate below once the engineer gave the milestone's go;
  the stage's issues stay open until then (`Closes` fires only on the default branch) and the manager closes them.
  - **Into `main`** (#300, the [trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)): the
    engineer's manager runs `tools\run.cmd merge <pr> --base main` from the main checkout once the fresh reviews left no
    open blocker or major. Its gate collects every refusal: not open into `main` or a draft; not authored by the
    engineer's account, or gh not running as it (the designer's PRs keep their flow); CI not green on the head;
    `mergeable` CONFLICTING; `origin/<head>` moved; **behind `main`** (`origin/main` not in the head: `publish` or
    `pr-rebase` first, then its CI); the exceptions in the paths since the fork (the designer's area without the
    designer's approving review or a line starting "agreed with the designer, relayed by the engineer";
    `.claude/settings*.json`, `.claude/githooks/` and `tools/runner/guard.py`, always; an ADR added, changed or deleted
    without "Approved by the engineer: <GitHub link>"); a closing PR (head `release/*`) without that line, the
    engineer's go, which also clears its designer-area paths and ADRs; and any top-level item, or sub-heading or bold
    label with no item under it, in "Needs the engineer" without "Answered: <GitHub link>" (the manager adds it with `gh
    pr edit --body-file` once the answer is recorded on GitHub; "None" passes; an unreadable section refuses). Markers
    inside HTML comments do not count. **No local `verify`:** with `main` in the head, the merged tree is the head's
    own, which `publish` verified on Windows and CI (on `refs/pull/<n>/merge`) on Linux; a local run would hold a verify
    slot 12 to 14 minutes per merge for nothing. `merge-check` rows that involve the PR and PRs stacked on it print as
    `gate: note:` lines and never refuse: the partner is behind `main` afterwards (the gate refuses it until its
    re-publish tests the pair), and across bases the milestone takes `main` in. Then `origin/main` is read again (moved:
    refused), the runner runs `gh pr merge <n> --merge --match-head-commit <oid>` as its own subprocess and prints one
    `wave:` line. `--dry-run` prints the verdict, merges nothing and runs from any checkout; a real merge refuses a
    task's checkout. Each merge is one chat line to the engineer; when `main` breaks after one, the manager opens a
    revert PR (`git revert -m 1 <merge>` on a task branch), merges it through the same gate and says so. "стоп мерджі"
    from the engineer returns merges into `main` to the engineer until the engineer says otherwise (recorded on the plan
    issue and #170). A solo session merges only where the engineer said so, from the main checkout.
  - **A list into `main`: `merge-train`** (#387). Each merge leaves the other open PRs behind `main`, so they go in
    series: on 2026-10-04 the manager drove 9 merges by hand, about 20 minutes each. `tools\run.cmd merge-train <pr>...
    --base main` (from the main checkout, in the background with a log ending `exit=<n>`, polled with `wait`) takes the
    PRs in the order given with no manager turn between them. Before the train, the manager's own check (trust ADR) for
    every PR in the list: no open blocker or major in its findings table and `not_fixed`; the gate does not read them.
    For each: the PR read (every `gh` call bounded); skipped with the reason when not open into `main`, its head is not
    a task branch, the gate would refuse it whatever a publish does (a draft, not the engineer's PR or session, an
    exception, an open "Needs the engineer": read by the gate's own code before any verify), no worktree has its branch
    checked out (`git worktree list`), or a live run holds that worktree (a verify slot holder there, a Claude Code
    session there that is busy or was updated within `--recent` minutes, a rebase, merge, cherry-pick, revert or bisect
    in progress, uncommitted changes, a HEAD that is not the PR's head, or a commit younger than `--recent` minutes,
    default 10; `--recent 0` once the manager knows the run ended). Then the way, printed: `main` already in the head,
    no publish; a history with merge commits (which `publish`'s rebase can trip on), `git merge origin/main` in the
    worktree, its `verify`, a fast-forward push of the task branch (a conflict is aborted, a red verify undoes the merge
    commit); otherwise the worktree's own `publish`. A red `verify` is retried once and the retry logged (a timeout on a
    busy PC is the usual cause); a rebase or merge conflict, a second red or any other stop skips the PR, and a publish
    that pushed nothing has its rebase undone (`git reset --keep` to the PR's head), so a later run takes the PR again.
    Then CI: GitHub shows the pushed head, and the checks are read from the JSON of `gh pr checks` (its exit code is
    non-zero both while a check is pending and when one failed): a failed or cancelled check (a new required job too, as
    "runner on the minimum Python" was) skips at once, all green goes on, no verdict in 40 minutes skips. Then `merge
    <pr> --base main` (the same code: the gate as above, its `wave:` line). A final `merge-train summary` lists the
    merged and skipped PRs (exit 0 only when all merged); a git call that hangs skips its PR, and the summary is printed
    even when the train stops on an unexpected error. `--dry-run` prints each PR's worktree and way, or why it would be
    skipped, and each gate's verdict now, and changes nothing. It never pushes `main` and never merges a gate exception.
- **Parallel tracks** ([pipeline v2 ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md) item 7, the
  engineer's answers N2 and N5, 2026-10-02): one milestone at a time; beside it the AI productivity track (#170) sends
  its PRs straight into `main`, each merged by its manager through the gate (Git flow above, "Into `main`"; how a
  milestone takes `main` in: Git flow above). At most about six task workflows run at once across all tracks (three per
  stage). Each kickoff states its budget as a percentage of the weekly limit, and its manager reports its own spend in
  every wave comment from `tools\run.cmd metrics --since <wave start> --session <its id> --compact`, plus the stage's
  running total (`--since <stage start>`): a run counts in the window it started in. Shared files (N5 (c)):
  `.claude/workflows/` and the orchestrate-stage skill change only through the tooling track (an issue there, landing
  between the other managers' waves: a mid-wave change breaks their resumes); `tools/runner/` and this file may be
  changed by any track between waves, after `merge-check`. `merge-check` also pairs each PR with every open PR into
  another base (a PR stacked on one of its own track counts as its track's) when both change a shared file (`tools/`,
  `.claude/`, `.github/`, this file), the same one or different ones (a signature changed in `tools/runner/x.py` that
  the other PR calls from `tools/runner/y.py`, #231): the textual conflicts in the files both change and the same symbol
  check over each whole PR, in a table "across bases" that names both bases (#207); the pairs where at most one side
  changes a shared file it names as not compared. A flagged pair: its manager names it on the other track's plan issue;
  the PR into `main` merges first (through the gate, or by a human for an exception; the milestone's manager holds its
  own PR meanwhile and merges the rest of the wave), the milestone takes `main` in (`merge --sync-main`) and its PR is
  rebased on that (`pr-rebase`) before it merges. After a change to a shared file reaches `main`, the tooling track's
  manager says so on each running manager's plan issue.
- **The human:** writes the kickoff (template in the skill, with the budget as a percentage of the weekly limit),
  answers the numbered "Needs the engineer" questions, gives each milestone's go (a playtest) and merges the gate's
  exceptions. The manager closes issues whose work is on `main` (a comment linking the PRs and merge commits) and runs
  `worktree-done` for its merged tasks when no live session sits there. Every message from the manager ends with one
  short "For you:" block in the human's language, numbered, listing only what needs the human now (a refused merge, a
  decision, a command), or "nothing"; housekeeping the human must run (a pull of `D:\prime-game`, a worktree a live
  session holds) is batched there once per wave ([intervention](interventions/2026-10-04-engineer-for-you-block.md)).
  The manager reports on the plan issue after each wave and stops with a comment when nothing more can run without the
  human. While it waits (a run of its own in flight, or a stop with a context over about 150k and no once-a-day handover
  due, #279) it keeps its 1-hour prompt cache warm with one background `sleep 3000` re-armed on each cheap wake, for at
  most about 12 hours of the human's absence (the skill's §7, #305). Each command the human must run (a workflow's
  `human_steps`, housekeeping) goes into the chat itself, one runnable PowerShell block per command
  ([intervention](interventions/2026-10-03-engineer-commands-in-the-chat.md)); the plan issue may list it too. The
  publishing agents return `human_steps` as `{why, command}` pairs, each command one PowerShell line that starts with
  `cd` to its absolute folder.
- **Recovery:** a crashed run resumes with `resumeFromRunId` and the same args; the prompts tell each agent to check
  what an earlier attempt already did, so a fresh run with the same args also continues. Each wave comment on the
  plan issue lists the running runs with their args, so a new manager session can take over from GitHub alone.
  Once a day that handover is deliberate (#279, the engineer's option A): a manager that stops for the human with no
  run of its own in flight and either its session over 12 hours old or its context over 500k tokens (`wave` prints
  both) posts a handover wave comment and gives the human the kickoff to paste into a new session (the skill's §7).

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
YYYY-MM-DD` keeps the calls from that day on, `--mode default` models a mode that prompts, `--list` names each cause
with examples, and `--observed` reports what the transcripts record instead: the guard's asks, deny rule denials,
Claude Code's own blocks and the human's rejections, with roles and waits, but not an ask rule's prompt that the human
approved, which leaves no trace: the replay's "ask rules" count holds those); a rule that would have stopped routine
work is judged by its target in the guard (§8.2) instead of by its text
([intervention](interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md)). `runner.permissions` models
Claude Code's matcher (subcommands, wrappers, `*`, deny before ask before allow, its documented read-only commands and
a guess at git's read-only forms, which a `cd` elsewhere in the same call takes away), and its selftests
(`tests/test_permissions.py`) check the lists with the guard: reads of other repositories pass in every mode, writes
there ask, and every `Bash(...)` rule has its `PowerShell(...)` twin. **Inside its own worktree and
task branch an agent has full freedom**: every git operation and every delete there runs without a prompt, and it
stops only for design and other human-reserved decisions and for what reaches beyond them
([intervention](interventions/2026-09-30-engineer-full-freedom-in-own-worktree.md)).
- Deny and ask rules apply in **every** permission mode, including bypass; allow rules matter only in the modes that
  prompt (the designer's `acceptEdits`).
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
  act (§8.2), so they are free in the agent's own worktree and on its task branch, and ask in the main checkout, in
  another worktree and on another branch.
- **Deny:** force pushes; pushes to `main` in any spelling, including a bare `git push`, `git push [-u] origin` with
  no branch and any push naming `HEAD` (always push an explicit branch name); `--no-verify`, remote deletes,
  `--prune`, `--mirror`, `--all`, `git config` on `hooksPath` or `--unset`, `--upload-pack`,
  `--output`, **`gh pr merge` and `mcp__ccd_pr__set_auto_merge`**, `gh repo delete`, `gh auth token`,
  token-printing `gh auth status`. A deny rule matches reads too and denies the whole call: read the hooks path with
  `git rev-parse --git-path hooks` (it prints `.claude/githooks`) or `doctor`, never `git config --get core.hooksPath`
  (10 denied calls in the week to 2026-10-04, #312), and the merge help with `gh help pr merge`, never
  `gh pr merge --help`.
- Godot, Python and gdtoolkit run without a prompt **only through the runner**; their raw forms prompt in modes that
  prompt.
- `GH_PROMPT_DISABLED=1` is set in the shared `env`.

### 8.2 Thin guard [applied]
Hooks live in `.claude/settings.json` and run in Git Bash through `.claude/hooks/run-hook.sh`, which finds Python as
`PYTHON_BIN`, else `py -3`, else a `python3` that really runs; the logic is in the runner (`run hook <name>`), so
`selftest` covers it in CI ([ADR](decisions/2026-09-29-claude-code-hooks-in-git-bash.md)). **Fail-closed:** no Python,
a crash, or any exit code other than 0 and 2 becomes exit 2, which blocks the call. A hook that cannot start, or
that times out, fails open: `doctor` is red when Git Bash is missing.

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
commands, by the repository they name (issue #68, a read of another repository must not stop it):
- **The session's own worktree and task branch are free** (issue #51,
  [intervention](interventions/2026-09-30-engineer-full-freedom-in-own-worktree.md)). The own worktree is the
  `.claude/worktrees/<n>` that the session's working directory is in; a session whose shell starts in the main
  checkout (a manager's task session) owns the first worktree its command enters with `cd`, `Set-Location` or
  `git -C` (`cd D:/prime-game/.claude/worktrees/51 && git rebase origin/main` passes; a second worktree in the same
  command asks), unless another live Claude session works in that worktree (`sessions.active_on`): then it owns
  none. The main checkout is never owned: the designer's sessions and the engineer's `start --here` sessions keep
  every prompt. The task branch is known by the worktree's identity: the branch checked out in
  `.claude/worktrees/<n>` when its name is `<area>/<n>-<slug>`, as `start` makes it. Another branch checked out
  there (a parent, a spike) is not the task's, so work that discards on it asks, whatever an earlier call did; a
  detached HEAD moves no branch and stays free. Its helpers are branches named `<task branch>-x`,
  `<task branch>/x`, `<task branch>.x` or `<task branch>_x`. The hook reads branch, ref and stash names from the
  files in `.git` (`hooks.GitFiles`, no git call).
- **Workflow agents' hooks take the manager session's working directory** (the `cwd` of the hook input), not their
  own. A manager whose shell stands in a worktree (a `cd` in the Bash tool persists between its calls) makes that
  worktree every agent's own, and each agent's own worktree someone else's: on the M3 night run a publisher's
  autosquash in its own worktree asked that way, and a replay with `tools\run.cmd permissions` showed the same
  command passing from `D:\prime-game`. So the manager enters worktrees only through subshells `(cd <wt> && ...)`,
  `git -C <wt>` or PowerShell `Push-Location`/`Pop-Location`, and its shell stays in the main checkout
  ([intervention](interventions/2026-10-01-engineer-night-run-prompts.md)).
- **Recursive deletes** (`rm -r|-R|-rf|--recursive` or `--rec` in bash, `Remove-Item -Recurse` or `-r`, `rmdir /s`,
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
- **`tests/scratch/`** is for temporary files that must be under `res://` (a probe test). It is gitignored but not
  gdignored, so `tools\run.cmd test tests/scratch/<file>` and `check res://tests/scratch/<file>` run what is there;
  full `check` (its UID lint too, #264), `test` and `lint` runs leave it out, so a half-written probe or a leftover
  `.gd.uid` never turns `verify` red. Godot still imports it: no `class_name` and no uid copied from a project file
  there (a `.tscn`/`.tres` header, or a suite's `.gd.uid` copied with it): Godot gives the uid to whichever file it
  scans last, so the import and the UID lint both fail on a copy. Never create a link or junction there: the guard
  judges a delete by its text path, and PowerShell 5.1 `Remove-Item -Recurse` on a junction deletes what it points to.
- **`git reset`** asks with `--hard`, `--merge` or `--keep`, or when it moves the branch to another commit
  (`git reset HEAD~1`, `git reset --soft origin/main`, `git reset v0.1.0`), in a repository anywhere in the project
  but the own worktree, `tools/out/` included; `-C`, `--git-dir` and `--work-tree` name that repository. Unstaging passes: `git reset`, `git reset -q`, `git reset -- <paths>`,
  `git reset HEAD -- <paths>`, `git reset core`. A lone argument without `--` is a commit when it looks like one (a
  SHA, `~`, `^`, `origin/x`, `refs/x`, `v1.2`, a task branch `net/40-x`, `main`) and a path otherwise, so
  `git reset feature-x` passes.
- **Other git that discards work or rewrites history** passes in the own worktree on the task branch, and in a
  repository outside the project (a clone in the scratchpad); it asks in the main checkout and in another worktree
  (`-C`, `cd`, `--git-dir`, `--work-tree`, `GIT_DIR`, `GIT_WORK_TREE`; the repository and the working tree are
  judged apart and the worse wins), when a pathspec reaches another checkout (`git checkout -- ../47/core`), and
  after the same command switched away from the task branch (`git checkout main && git reset --hard`, also inside
  `bash -c`):
  `checkout` of paths or `-f`, `switch -f|--discard-changes`, `restore` (not `--staged` alone), `clean` (not `-n`),
  `rebase` (`--continue` and `--abort` too), `worktree remove|move` of anything but the own worktree's folder or an
  absolute path outside the project (git also takes a worktree's last path parts: `git worktree remove 47`),
  `update-ref HEAD`. A plain `git switch x` or
  `git checkout x` discards nothing and passes anywhere. Branches and the stash are shared by every checkout, so
  they are judged by name: `branch -d|-D`, `branch -f`, `branch -M|-C`, `checkout -B`, `switch -C`, a rebase that
  names its branch, `update-ref refs/heads/<x>` and a forced switch pass only for the task branch and its helpers;
  `stash drop|clear` only for entries made on them (a human's `start --stash` entry is made on `main` and asks),
  and never after the same command changed the stash (the indices shift); agents use no stash at all, a WIP commit
  instead (root `CLAUDE.md`, Shell). An interactive rebase whose
  `GIT_SEQUENCE_EDITOR` the command sets to `:` or `true` (a prefix; in bash `export`, in PowerShell `$env:`, as that
  shell's last value; it outranks every other editor setting) opens no todo editor and is judged like a plain
  rebase: `git commit --fixup=HEAD` then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>` stays
  editor-free (a `squash!` commit would still open the message editor) (#104). `git -c core.editor=true`,
  `-c sequence.editor=:` and `GIT_EDITOR=true` do not count, on purpose: a `GIT_SEQUENCE_EDITOR` inherited from the
  environment or a `sequence.editor` in a git config file, which the guard cannot see, would outrank them (a publisher
  that used `-c core.editor=true` on 2026-10-03 waited 23 minutes, #312). Always asks: another
  interactive rebase (`-i`, `--edit-todo`: an agent cannot use the editor), `rebase --update-refs` (moves other
  branches), `rebase -x|--exec` (runs commands the guard cannot judge), `update-ref --stdin` and
  `git -c core.hooksPath=...` (the deny rule on `git config *hooksPath*` cannot see it).
  Rebase options are read as git reads them (#105): a cluster letter by letter (`-qi`, `-qx cmd`), an attached
  value (`-x'cmd'`), a unique prefix of a long option (`--interac`, `--exe=cmd`, `--up`), and `rebase.updateRefs`
  from `git -c` or `--config-env` (any true value, unless `--no-update-refs` follows) like `--update-refs`. A nested
  shell inherits its command's `VAR=value` prefixes (`GIT_SEQUENCE_EDITOR=: bash -c 'git rebase -i ...'` passes).
- **`gh` aimed at another repository** (issue #68) asks unless it only reads. The repository is the value of `-R|--repo`
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
  of another repository without naming it. Sibling repositories of this project (`prime-game-art`, `prime-game-ui`)
  are other repositories too: a session that manages one runs in that repository's checkout, never in
  `D:\prime-game`, where each of its `gh` writes there asks (30 asks on 2026-10-02 and 10-03, about 12.6 hours of
  waiting, one `gh pr create` over a whole night, #312).
- In a worktree session the rest of the project stays protected: `rm -rf D:/prime-game/core` and
  `git -C D:/prime-game clean -fdx` ask there.
- It resolves each target against the session's working directory, `cd`, and the variables the same command assigns;
  `$TEMP`, `$env:TEMP` and `~` are outside the project, so scratch copies never ask. A target it cannot resolve (an
  unknown variable, `$(...)`, a PowerShell `(...)` argument) asks when its text names a protected path. Content is
  not a target: `Add-Content .gitignore "addons/"` stays silent. Out of scope: scripts it would have to run, globs
  that match only by expansion (`a*ons`), `git apply`, `awk -i`, `ed`. It does not check ownership or the editor.
- The prompt appears in every mode, bypass included. 👤 Answer it with a one-time "Yes" or "No": "don't ask again"
  silences the guard for the rest of the session (verified live 2026-09-29).
- Replayed over the 1,683 distinct shell commands of the Phase A and B transcripts (stage 4 included): no crash; it
  asks for the real install of GdUnit4 into `addons/` and the three commands of the live test, nothing else. It adds
  about 0.2 s to each shell command.
- Target-judged deletes and resets, replayed on 2026-09-30: the overnight run `wf_65292cf4-8b4` (309 shell commands)
  went from 4 prompts (two scratch `rm -rf`, one `git reset -q`, one `rm -r tests/integration/tmp` in a worktree) to
  1 with the guard and without the text rules: the delete inside the project still asks. With that probe folder in
  `tests/scratch/`, as §7 now asks, the same replay has 0 prompts. Over all 3,421 distinct
  shell commands of this machine's transcripts, no crash; against the guard before #47 it asks 5 more times: four
  real changes to the project (two installs into `addons/`, a `git reset --hard origin/...`, that `rm -r`) and one
  false ask, a heredoc whose test data holds the text `shutil.rmtree('core')`. After the second fresh review
  (arrays, subshells, variables no call assigned), the overnight replay is unchanged (1 prompt, 0 with
  `tests/scratch/`), and over the 2,709 distinct shell commands of this machine's transcripts on that day it changes
  one verdict: a scratch-folder delete after `(cd tools && ...)`, which the old guard read inside `tools/`, now
  passes.
- The own worktree (#51), replayed on 2026-09-30 in the engineer's bypass mode (deny rules block; ask rules and the
  guard prompt) over every Bash and PowerShell call in `~/.claude/projects/D--prime-game` (101 transcripts, 2,921
  calls): 103 prompts before (97 ask rules, 6 guard), 67 after (63 ask rules, 4 guard), 22 denied in both, no crash,
  and no call that was silent before asks now. The 36 prompts gone: `git worktree list` and other git status reads
  in the main checkout, git in scratch clones, a `git checkout` and `rm -r tests/integration/tmp` in a task's own
  worktree. What still asks: 63 `gh ... -R|--repo` reads of other repositories (research), three writes to
  `addons/` and `.claude/` from the live test of stage 4, and one `Remove-Item -Recurse` of worktree 46's
  `tests/integration/tmp` by absolute path from a session in the main checkout (without a `cd` it owns no worktree).
  Over every `D--prime-game*` folder (128 transcripts, 3,847 calls): 125 prompts before, 80 after.
- Reads of other repositories (#68), replayed on 2026-09-30 with `tools\run.cmd permissions` (bypass mode,
  `origin/main` against the branch) over every Bash and PowerShell call in `~/.claude/projects/D--prime-game*`
  (224 transcripts, 6,591 calls): 95 prompts before (79 ask rules, 16 guard), 18 after (0 ask rules, 18 guard), 22
  denied in both, no crash, and no call that was silent before asks now. The 77 prompts gone are `gh ... -R|--repo`
  reads (issues, PRs, releases, search, `api` GET of Godot, GdUnit4, gdtoolkit, TwoVoIP, Claude Code and other
  upstreams), four reads of this repository with `-R|--repo`, and calls where a text rule matched other text (an
  issue comment on this repository whose body held `-R`, `gh release --help`). Two calls still ask, now through the
  guard: `gh issue create --repo godotengine/godot` (an upstream bug report) and a `gh issue create -R` probe of a
  missing repository. The other 16 guard prompts are unchanged (§8.2 above).
- What blocked agents in the week to 2026-10-04 (#312), from `tools\run.cmd permissions --observed --since
  2026-09-29` over this project's transcripts (about 910 of them and 24,800 shell calls on 2026-10-04; the earlier
  replays above also read the `D--prime-game-art` and `-ui` folders, this one does not): 109 stopped calls, nearly
  all in bypass mode. 58 guard
  asks: the 30 `gh` writes to the sibling repositories (above); 20 git commands that discard work, of which 11 came
  from a manager's shell standing in a worktree and from `git stash drop` on 2026-09-30 (fixed by the 2026-10-01
  intervention and the no-stash rule), 1 from a no-op editor rebase before #104 landed, 1 from `-c core.editor`
  (above), 2 from custom sequence editors, and 5 were right (`branch -d|-D`, `reset --hard` of a release branch or in
  a loop over another repository's worktrees, `worktree remove --force` in a loop); 8 writes to `addons/` (the TwoVoIP
  install, and the missing-addon test above). 13 deny rule denials: 10 hooksPath reads (§8.1), `gh pr merge --help`,
  and two pushes without a branch. 30 of Claude Code's own blocks: 28 foreground `sleep`s (§11, "Bounded waits"), and 2
  `Remove-Item` on a "system path", one right (`D:\c`) and one false: a PowerShell command held `Remove-Item $out` and
  a cmd.exe `/c` argument, which Claude Code read as its target; put such code in a `.ps1` file in the scratchpad
  and run it with `powershell -File`. The human said no 8 times. No stop called for an allow rule or a guard change:
  each was right or a wrong command pattern. The fixes for the wrong patterns are documented here; workflow agents
  read their workflow prompt instead, which gets the hooks-path and `sleep` rules through #326. Outside bypass the
  model (`--mode default`, an upper bound) asks for about 12,800 of the calls: `$PYTHON_BIN` about 3,400, git reads
  (`diff`, `status`, `show`) about 2,200, nearly all after a `cd` into a worktree (Claude Code prompts for git after a
  `cd` elsewhere, and workflow agents start every command that way), `sed`, PowerShell filters and loops. Allow rules
  for the plain filters (`cut`, `tr`, `printf`, `date`, `Select-Object` and the like) and `mkdir` would remove about
  1,500 of them, so unattended work stays in bypass mode.

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
  parent `start --base` recorded, else `main`; then `verify` and the lease push. It stops before touching anything
  when the remote branch has a commit this branch never had (a suggestion committed on GitHub, "Update branch", a push
  from the other machine): the lease alone would not protect it, because the fetch just updated the expected value. A
  conflict aborts the rebase and leaves the branch as it was; a red `verify` pushes nothing. After its parent was
  rebased or amended, a stacked child replays only its own commits: those after the parent commit `start` recorded
  (`branch.<task>.primeBaseTip`, renewed by each publish on the parent; `rebase --onto`), else those after the fork
  point (`--fork-point`, which needs the reflog of the parent's remote ref).
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
- "Automatically delete head branches" is on: a merged PR's branch is deleted, and GitHub retargets its stacked
  children to `main` itself.

## 9. Ownership

([ADR](decisions/2026-09-28-ownership-by-codeowners-and-convention.md))

| Owner | Paths |
|---|---|
| Engineer | `core/ server/ net/ client/ voice/ tools/ tests/ addons/ .github/ .claude/` (except the two designer skills) `project.godot CLAUDE.md docs/{ARCHITECTURE,AGENT_WORKFLOW,ROADMAP}.md` |
| Designer | `content/ levels/ docs/GDD.md docs/design/ .claude/skills/{new-mechanic,new-level-piece}/` |
| Shared | `docs/interventions/ docs/decisions/ docs/credits/ docs/history/ CREDITS.md .claude/rules/` |

- Enforced by **`.github/CODEOWNERS` and the rules in `CLAUDE.md` files**, not by a hook.
- The designer's agent never edits engine code. A missing primitive becomes an `engine-request` issue with a precise
  spec, and the agent continues with data. This rule is in `content/CLAUDE.md` and `levels/CLAUDE.md`.
- The engineer's agent does not change the designer's area (rebalance or redesign content, edit `docs/GDD.md`,
  `docs/design/` or `levels/`) without the designer's approval in the PR, except on a **relayed agreement**
  (the engineer, 2026-10-01, option (a), permanent;
  [intervention](interventions/2026-10-01-engineer-relayed-design-agreement.md)):
  - The engineer's agent works in the designer's area when the engineer says the change was agreed with the
    designer. Without that word it stops and asks, as before.
  - The PR says "agreed with the designer, relayed by the engineer" under "Cross-area" and tags @SwiftySinister
    there for a later look. It is merged without the designer's approval, by the engineer or by the manager, into
    `release/m<k>` or through the gate into `main` (this replaces "a cross-area PR is approved by the other owner
    first" in §10 for such a PR).
  - If the designer objects, a follow-up PR reverts the change.
  - A scene the designer has an open PR on is still never edited (`gh pr list --state open --json
    number,author,files`).
  - The designer keeps his area and his skills (`new-mechanic`, `new-level-piece`); the engineer acts in it on his
    behalf. The M3 decisions D1 to D3 on #96 were relayed the same way.
- The gate of `merge <pr> --base main` (§7.1) keeps ownership: it refuses a PR not authored by the engineer's
  account, or run outside the engineer's sessions, and a PR that changes the designer's area without the designer's
  approving review or the relay phrase; `.claude/settings*.json`, `.claude/githooks/` and the guard are always the
  engineer's to merge, and an ADR change needs "Approved by the engineer: <link>"
  ([trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)).
- MVP exception: the engineer's agent builds the MVP's `content/` data and `levels/` scenes, each PR with the
  engineer's explicit approval and marked provisional; the designer may replace them
  ([ADR](decisions/2026-09-29-mvp-content-built-by-the-engineer.md)).

## 10. GitHub coordination

- **Repo:** public, GitHub Free ([ADR](decisions/2026-09-28-public-repo-on-github-free.md)). The Phase A archive
  is published as is.
- **Merging:** the engineer's manager merges into `main` through the gate of `tools\run.cmd merge <pr> --base main`
  (§7.1, [trust ADR](decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)); the gate's exceptions and
  the designer's PRs are merged by a human, with the Merge button on GitHub or in the Desktop PR pane, after CI is
  green. A cross-area PR is approved by the other owner first. The designer reviews through `shot` screenshots and a
  playtest, never the diff ([ADR](decisions/2026-09-28-humans-merge-prs.md)). In a stage the manager merges task
  PRs into the milestone's `release/m<k>` (§7.1, [ADR](decisions/2026-10-01-release-branch-per-milestone.md)).
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
  #85); GitHub accepts an owner only once they have write access, so the entries count from the accepted invitation.
- **ADRs:** `docs/decisions/YYYY-MM-DD-<slug>.md`, never sequential numbers, so two branches cannot collide on
  the same number. Short: status, date, deciders, context, decision, alternatives, consequences.
- **Append-style logs are one file per entry** ([ADR](decisions/2026-09-28-one-file-per-entry-logs.md)):
  interventions in `docs/interventions/YYYY-MM-DD-<who>-<slug>.md`, asset credits in `docs/credits/<asset>.md`.
  `/log-intervention` writes the entry and promotes the rule in the same PR; each promoted rule carries a
  `<!-- see docs/interventions/… -->` comment.
- **Credits [applied]:** one file per asset or pack, `docs/credits/<asset-slug>.md`: a `# <name>` title, then
  `- **Files:**` (repo-relative globs in backticks; `*` stays in one folder, `**` crosses folders), `- **Author:**`,
  `- **Source:**` and `- **License:**` lines; more fields and free text are copied as they are
  ([example](credits/gdunit4.md)). `tools\run.cmd credits` writes `CREDITS.md` from them; nobody edits it by hand.
  `check` fails when a file that `.gitattributes` routes through LFS, outside `addons/`, matches no entry (untracked
  files count, so it fails before the commit), when an entry's glob matches no file, and when `CREDITS.md` is out of
  date. `addons/` is exempt from the check (its code keeps its own LICENSE and its images stay out of LFS), but each
  addon still gets an entry.

## 11. Godot specifics

- **Stack** ([ADR](decisions/2026-09-29-technical-stack-from-the-brief.md)): Godot 4.7.2 standard build (not .NET),
  typed GDScript, GdUnit4, gdtoolkit, ENet behind a transport abstraction, Opus voice (M1 spike decides the addon).
  Native Windows first, never WSL: the agent runs the Godot `*_console.exe`, humans the regular exe. Binary assets go
  through Git LFS, `addons/` stays outside it ([ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md)).
- **Editor convention** ([ADR](decisions/2026-09-28-godot-editor-save-first-convention.md)): nobody edits by hand
  while an agent works. Before asking the agent for anything, Scene → **Save All Scenes** (Ctrl+Shift+Alt+S;
  Ukrainian UI «Зберегти всі сцени»). If Godot asks about files changed on disk, always choose **Reload from disk**
  (Ukrainian UI: **«Джерело отримання»**; never «Ігнорувати зовнішні зміни»). The agent reminds the human; nothing blocks. Headless runs next to an open editor were verified in M0.
- **`.tscn` / `.tres`** ([ADR](decisions/2026-09-29-hand-written-scenes-then-normalize.md)): the agent hand-writes
  readable text and never copies a uid or a `.uid` sidecar; `tools\run.cmd normalize <files>` **[applied]**
  re-saves them in headless editor context (`--headless -e -s`, after the first file-system scan), which adds the
  header uid and node `unique_id`s the editor would. A second run leaves the file byte-identical. Godot drops a property it does not know (a typo), one at its default, and any line
  after a parse error, without an error: `normalize` compares property keys before and after, and on a loss restores
  the file and fails. `check` fails on UID problems, on files left modified by `--import`, and on an `ext_resource`
  uid that resolves to a different file than its `path=`.
- **`shot <scene>` [applied]:** a real window at `--position -30000,-30000` (off-screen), never headless or minimized
  (Godot then never draws), a 60 s watchdog, a PNG in `tools/out/shots/`. A scene with no camera (a level piece) gets
  one that frames all its geometry, plus a light if it has none. It prints the driver it drew with (`renderer: vulkan
  forward_plus`; the runner's `--no-header` hides Godot's own line). Desktop only: CI never runs it, and the designer
  gets the PNG to drag into the PR (`gh` cannot upload images). `tools/shot/probe.tscn` is its smoke test.
- **`run <scene.tscn | script.gd>` [applied]:** runs a scene, or a `-s` script that extends `SceneTree`, with the
  pinned Godot; arguments after `--` reach `OS.get_cmdline_user_args()`. `--headless` uses `GODOT_BIN`; a window
  uses `GODOT_GUI_BIN` (else `GODOT_BIN`), and `--offscreen` puts it at `shot`'s off-screen position. `--seconds N`
  (default 60) kills the process tree; `--instances N` (up to 8) starts N copies at once, each with
  `PRIME_INSTANCE=<i>` in its environment and its own log `tools/out/logs/run/<name>-<i>.log` (the next run of the
  same name replaces them). `--audio dummy` (default) or `default`; `--headless --audio default` keeps the real
  audio driver (`--display-driver headless`). Fails when an instance exits non-zero, times out or prints an
  `ERROR:` / `SCRIPT ERROR:` line (Godot exits 0 after both), and names the instance and its first error lines. A
  scene that never calls `quit()` therefore fails at `--seconds`: read its log. The agent's own checks run
  `--headless` (never a window while a human uses the machine). It imports the project first when the import is not
  current (the next item). `tools/run/probe.gd` is its smoke test.
- **The import before a launch [applied]** (#174): `host`, `join`, `run` (and through it `perf` and `bots`),
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
- **`mutants <spec.json> [--seconds N]` [applied]** (#184; item 4 (b) of the
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
  the reason and the log). At the end it removes the scratch worktree (and its `user://` folder, §11), also after an
  exception, and confirms the task's `git status` unchanged. A lock in `tools/out/mutants/` allows one run per
  checkout (the OS releases it when a run is killed). The table is printed and written to
  `tools/out/mutants/<spec name>.md` after every mutant, with each test run's output and Godot's log in
  `<spec name>-<step>.log` beside it. Exit 0: the run completed, whatever the results; 1: an invalid spec, or a run that could not start or finish (a dirty tree, another run, a failed
  import), nothing left behind; 2: the scratch worktree could not be removed or the task's tree changed: run no more
  mutants and tell the human (`git worktree list` shows it; the next run removes it first). One mutant per call takes
  about 17 to 19 s with small suites (setup about 9 s, baseline and mutant about 4 s each); several, or tests that
  name all of `tests/` (two full runs: 596 s while other worktrees verified), go in the background, and their report
  file shows the progress. The runner's own git commands are not the session's shell
  commands, so the guard judges only `tools\run.cmd mutants <spec>`, which passes from a task worktree and the main
  checkout; a hand-typed `git worktree remove` of the scratch tree asks (§8.2).
- **`host` and `join` [applied]** (3i, #103; windows since #149; `docs/ARCHITECTURE.md` §4.6 and §4.7, the M4 ADR's
  E20): the game over ENet. `host [--port P] [--clients N] [--local] [--seconds S]` hosts on every interface, or on
  127.0.0.1 only with `--local` (no firewall prompt), and with `--clients N` (up to 7) starts N clients that join it
  on 127.0.0.1 once it hosts. `join <address> [--port P] [--seconds S]` joins a host. The default port, 24600, is a
  placeholder ("not a decision"). Each process gets `PRIME_INSTANCE` (1 the host, 2 and on the clients in tile order),
  so each window keeps its own settings file (`user://settings.cfg`, `settings_2.cfg`, ...; the M5 ADR §1.7).
  - **Windows** (the default for a human): each process is the game, `client/app/game.tscn`, started with the
    command line `LaunchOptions` reads (`--host [--local]` or `--join=<address>`, `--port=`, the stop and alive files
    below), so it skips the menu and goes straight to the lobby. A host and its `--clients` are tiled over the primary
    screen (`--position`, `--resolution`); a windowed host on every interface prints what to type on another PC. A
    host that cannot listen stays at its menu with the reason, and its clients do not start. A window never welcomed
    into a lobby (it could not host, or its join ended) fails the run with the reason, though the game exits 0.
  - **`--headless`**: M3's `tools/run/headless_session.gd` (a `HostSession` and its own `ClientSession` of the base
    mode). Each process prints `session:` lines: the roster (`Player1 [1] ready, Player2 [<peer>]`), the phase, and
    the counters (the transport's rejects and LATEST merges, the client's undecodable messages; on the host the
    budgets' `over_budget`, `bad_payloads`, `malformed_disconnects` and `voice_dropped`) when they change, at most
    once a second; a refused join says why in words (`wrong_version`, `wrong_content`, `joins_closed`, `full`, no
    answer). Exit 1 is a refused or unanswered join, a client stopped before `Welcome` or ended by anything but its
    host, or a host that cannot start or ends for an error.
  - **An agent's shell** (`CLAUDECODE` is set) gets `--headless` by default, so an unattended run never opens a window
    on a human's screen; `--windows` opens them there, and agents never pass it. A human who asks an agent for
    windows ("запусти хост і двох клієнтів") gets the command to run in their own PowerShell, starting with `cd`.
  - The runner echoes every process's lines live as `[host]`, `[client 2]` or `[join]` (a label is a process, not a
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
    scene headless through its command line (CI below).
- **`bots [scenario ...]` [applied]** (#102; `docs/ARCHITECTURE.md` §4.6, §9.7): plays every bot scenario in
  `content/scenarios/` (or those named) through `HostSession` and one `ClientSession` per bot, in one headless process
  over the loopback on a simulated clock (60 steps per simulated second: the six MVP scenarios take about 8 s), and
  asserts the information-leak test (§5 there) for every bot, a lurker and a refused bot. `--instances N` (N > 1) plays one
  scenario of N bots over ENet on 127.0.0.1 on a free port, one process per bot, on the real clock; `--seconds`
  overrides the timeout (300, over ENet 180). It runs `tests/harness/bots/bots_main.gd` through `run`, so `run`'s
  failure rules apply. A failed scenario prints its seed and each failure (the bot, its step, its last events) and
  writes the command log that replays it (`ReplayFiles.read`, then `Match.replay`) to `tools/out/bots/<scenario>/`,
  next to each bot's view file `bot-<i>.bin`; every run starts with that folder empty. Over ENet a scenario step that
  needs two events in one poll (an `Expect` with `within_s` 0 after a `WaitFor`) is timing-dependent
  (`dropped_at_the_loading_deadline` failed once in four runs); a failure there is not a leak by itself (§4.6).
  `bots --chaos [--seed N] [--runs K] [--long] [--enet]` (#188; `docs/ARCHITECTURE.md` §4.6 "Chaos bots") runs the
  chaos bots instead: `tests/harness/chaos/chaos_main.gd`, a hostile player and a malformed peer against the host
  beside honest bots, for K seeds from N (without `--seed` a random one, printed first, so a failed night run names
  the seed that replays it); per seed a baseline with the chaos peers idle, the chaos run and one with hidden roles
  swapped, in one process over the loopback; `--long` is the match in which the hostile also dies, `--enet` one run
  over ENet on 127.0.0.1 on a free port (the invariants only). A failure prints `CHAOS seed <n>: FAILED` and each
  broken rule (the input, the phase and life state, what was expected and what came).
- **`perf [--bots N] [--seconds S] [--enet] [--baseline FILE]` [applied]** (#187; item 6 of the [AI productivity
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
  and their headroom (the 1024-byte unreliable cap, E7's per-peer budgets, E11's tick on `VoiceDown`). It compares
  with `--baseline`, else `tools/out/perf/baseline.json`, else the newest earlier report of the same transport, bots
  and round, and lists every metric that moved by more than 20% (a placeholder, not a decision); only a failed match
  fails it. Not a `verify` step: the nightly job `perf` runs it (§15). Copy a report you trust to `baseline.json` to
  pin the comparison. The pinned Godot is a debug build (unoptimised GDScript): compare runs with each other, not
  with a release host's cost.
- **`wave --since T [--base B] [--plan N] [--title T] [--notes FILE] [--stage-since T] [--no-merge-check] | --args <n>
  [--workflow NAME] [--session ID] [--out FILE]` [applied]** (#277, #278; round 2 of the AI productivity track, a
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
  on a red implementer, a pr-rebase rebase is red or unpublished, or the result says stopped; other workflows, such as a
  read-only scouting run, are listed by their name with no issue), the running runs (title, worktree, branch, base, the
  agent working now: each `started` with no `result`, and the minutes since the launch and since the newest write to the
  run's journal or agent transcripts, which tell a live run from one whose session died); the open PRs into the base and
  those stacked on them (issues, base, draft, a CI cell from `statusCheckRollup`: red beats pending, else green, "none"
  when nothing reported; `mergeStateStatus`); merge safety (`merge-check --base B` with its printed lines captured: its
  exit code and verdict line, and only when it flagged something or failed its tables and details exactly as printed;
  `--no-merge-check` skips it and its `git fetch`); the cost (what `metrics --since T --session <this session>
  --compact` prints, computed in memory with no metrics file written, plus with `--stage-since S` the stage's `total API
  list $` and `% of a Max 20x week` lines; `COST_EXTRAS` in `wave.py` takes more lines over metrics' JSON record, the
  hook for #314); housekeeping (below); the handover args of each running run and of each failed, killed or stopped one
  that no later launch of its issue and workflow has replaced (the args exactly as passed, `indent=1`,
  `ensure_ascii=False`; a resume without args inherits its run's); and a footer (the session's age, its last call's
  context, the mean API list $ per call of its first and last 20 calls, and any records it skipped). A section says
  "None." when it has nothing, and "Unavailable: <error>" (with a warn line) when its source failed: the rest of the
  body is still written and `wave` exits 0. Housekeeping, from `git worktree list --porcelain` in the main checkout: one
  fenced PowerShell block per command (`cd D:\prime-game; tools\run.cmd worktree-done <n>`; for the manager's
  `release-m<k>` worktree its `git worktree remove` and `git branch -D`) for each worktree whose branch's PR merged and
  whose work is on main (directly, or through a release or parent branch whose own PR into main merged later), with no
  running run of this session there, its HEAD at the merged head and no live Claude session in it; the manager runs
  those itself (orchestrate-stage §8, the trust ADR). The section's first line, which the manager lifts into its chat
  message, names only what needs the engineer, a worktree a live session holds: `For you: close the Claude session in
  worktree <n> (...), then run its block below.` (`For you: nothing.` when none; the ready blocks stay out of it,
  #343). The other cases are one-line waits (after `release/m<k>` reaches main, a run still running there, HEAD not
  the merged head). It also names the issues still open whose PR reached main since T. One `gh pr list --state merged
  --search sort:updated-desc` (the 500 most recently updated, every base; gh's default order is by creation) serves
  the merged section and housekeeping (gh's `merged:>=` search is date-only, so mergedAt is filtered here); when gh
  returns all 500, the merged section names the oldest update among them, before which a merged PR (and its worktree)
  may be missing. A body over 60,000 characters (GitHub's limit is 65,536) moves its handover data, each run's block
  whole, to `<out>-2.md` (and `-3.md`, ...), posted as the next comments; the first body says so, every path is printed,
  a part one run's args alone push over 65,536 gets a warn, and a part left from an earlier run is named, never deleted.
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
- **`metrics [--session ID[=LABEL] ...] [--since T] [--until T] [--ci N] [--out DIR] [--compact] [--no-gh]` [applied]**
  (#178; item 1 of the [AI productivity ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md), whose
  baseline it reproduces): time, tokens and API list $ of the task workflows, read-only from Claude Code transcripts. It
  reads `~/.claude/projects/<key>/` (`CLAUDE_CONFIG_DIR` replaces `~/.claude`), where `<key>` is the main checkout's
  path with every character but letters and digits replaced by `-` (`D--prime-game`), plus
  `<key>--claude-worktrees-<n>/`. The main checkout is the parent of `git rev-parse --path-format=absolute
  --git-common-dir`, so every worktree gets the same answer (workflow agents log under their parent session's folder
  anyway). Per session: its own `<session>.jsonl` (the manager), the subagents it ran by hand, and each workflow run
  under `subagents/workflows/wf_*/` (`journal.jsonl`, `agent-*.jsonl`, `*.meta.json`). Usage is deduplicated by message
  id; a run counts when its first line is at or after `--since` and its last before `--until` (default now), so a rerun
  with a past `--until` gives the same tables while sessions keep working. A session's rows are labelled by its first 8
  characters, or `--session dd93bf79=M4` (sessions given one label form one stage). It prints and writes
  `tools/out/metrics/metrics.md` and `.json`: per finished `issue-task` run and per session (a stage), per agent role
  (from the label: `implement`, `publish`, `review:code`, `review:netcode`, `review:godot-api`, `rebase`, `fix`, and
  issue-task v2's `plan`, `review:plan`, `review:netcode-second`, `test-review` and `skeptic`; any other is "other"),
  local `verify` by step with its verify-slot wait and runs over the limit (#185) (from the summaries agents printed,
  the managers' own runs and `tools/out/logs/verify-history.jsonl` of the main checkout and its worktrees when `verify`
  writes it, #179; from that file also the red runs' failing tests, each red step's first failure line with its numbers
  as N, and the `test` shards that did not end with exit 0, #273), review findings by reviewer (a task's blockers and
  majors count only its diff reviewers', as in the baseline), the prompt cache after waits, manager sessions with their
  % of a Max 20x week, each manager session's cache re-writes after an idle gap over 1 hour (count, tokens, API list $,
  by what held when the gap began: a keep-alive timer, a run of its own in flight, or a stop; its timers and its last
  call's context; #305, the skill's §7), and the other runs; `--ci N` adds CI from `gh` (the runs of `ci.yml` in the
  window, and the jobs and `verify` steps of the last N green runs). `--compact` prints only its summary of at most 11
  lines (time and API list $ per task and in total, quality, the % of the week, `verify` medians): the manager pastes
  `metrics --since <wave start> --compact` into each wave comment. The % of the week counts cache reads at the central
  weight #307 measured (the pipeline v2 ADR's #307 amendment; `WEEK_CENTRAL`, #333): (list $ without cache reads, plus
  0.75 times the cache-read $) / $23.0 per 1%, whatever the cache reads' share of list $. A bracket beside it is the
  range #307 measured, the limit counting cache reads at 60 to 100% of their list $ ((list $ without cache reads, plus
  0.6 or 1 times the cache-read $) / $21.5 or $25.5; `WEEK_BRACKET`). At 1, $25.5 is #304's full list $ per 1% (66% at
  2026-10-03 20:54 UTC was $1,690 list since the counter restarted at the plan change). The calibration readings, 66%
  and 77%, both round to the reading at the central weight. It covers only this checkout's sessions (the main checkout
  and its worktrees) that ran a workflow or that `--session` names; the weekly counter counts every session of the
  account. API list $ is a weight (one price table in
  `metrics.py`, its source and date beside it), not money spent; no transcripts is a message and exit 0, and so is an
  empty window, which also writes an empty report over an older one. Its quality scorecard (#314), so a cost change
  (#303, #308's publisher trial, effort levels) is judged by quality too, has three tables, per finished `issue-task`
  run, per session (a wave with `--since <wave start>`; medians) and per role setting (role, model and effort from each
  agent's transcript; a clean run's publisher also as "publisher (clean run)"), and `quality` in `metrics.json`. From
  the journal: the diff reviewers' and test review's blockers and majors, the skeptics' refutations, "clean" (none left
  open, not stopped by mutants, not a design task: #315's rule, derived because a run's return value is not
  journaled), the publisher's `fixed`, `not_fixed`,
  `needs_engineer` and PR, and its fix rounds (`publish` calls minus one). From `gh`, read-only and by default
  (`--no-gh` skips it; a failure is a note, never an exit code): the PR's state, its CI rounds (one per head SHA of
  `ci.yml`'s pull_request runs on its branch; red rounds, those after the run, and "green on the first CI round"),
  Found-by follow-up issues (a lower bound: only those whose "Found by" line names the task) and later `revert` or
  `fix` PRs naming it in the title or in a sentence that reverts or repairs it (not under Merge order or
  Verification); a first round re-run to green is unknown, since `gh` shows only the last attempt. Unknown is `?` (null), never 0: no PR, an older result shape, skeptics not run, a PR of another
  repository, no CI run, or `gh` not read; medians and sums say how many are known. The compact `quality:` line ends
  with the API list $ per PR green on its first CI round (the merged count beside it). A caller of `metrics.build`
  (wave's cost block once #278's PR lands) gets the line's journal half; passing `github=metrics.read_github()` adds
  the GitHub half. Its section "Instructions and docs per agent role" (#337) is the instruction-diet ADR's method (#313,
  "How it was measured"), so the diet's issues are measured against one baseline. Per role: agents, the median
  launch-loaded, path-loaded and read tokens, the list $ split into first writes, re-writes after a lapsed cache and
  reads, its share of the role's $, the points at w = 0, 0.5 and the central 0.75 ((non-read $ + w x cache-read $) /
  $15.3, $20.3 or $23.0, `POINT_WEIGHTS`, the last from `WEEK_CENTRAL`, for the window) and the files loaded twice in
  one agent (either copy, before a compaction). Then the cost by file, the duplicates, ARCHITECTURE's and
  AGENT_WORKFLOW's list $ by § of today's file, and per manager session (one row each; `--since <wave start>` for a
  single wave) the open-PR pairs whose `merge-check` output names an ARCHITECTURE conflict (N1 (c)'s trigger);
  `instructions` in `metrics.json`, and one compact line.
- **`playcheck [scenario ...]` [applied]** (#186, P9 of the AI productivity ADR, item 8): the real game in off-screen
  windows running scripted steps, with screenshots at named steps, for the UI and camera bugs only a playtest saw before
  (#168, #169). A scenario, `tools/playcheck/scenarios/<name>.txt` (grammar: `tools/runner/playcheck.py`), names its
  players: window 1 hosts (`client/app/game.tscn` with `--host --local` on a free port), up to two more windows join it,
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
  edit, and a timeout prints what the window drew (`hud.hand 'Hand: empty'`). `lacks` holds at once on a hidden field
  (it reads as ""): put a `has` or `wait shown <field> on` on the same field before it. The windows sit at `shot`'s
  off-screen position with the dummy audio driver, never headless. The game gets a pointer that only remembers, and
  playcheck presses keys only, so the real mouse is never captured; what needs a captured mouse (`use`, spectate
  cycling) is out of its reach, and `aim` is the only way to turn. PNGs: `tools/out/playcheck/<scenario>/<shot>.png`
  (`gh` cannot upload them: the PR lists their paths and says what each shows); logs:
  `tools/out/logs/playcheck/<scenario>/`. A run fails on a wait past its timeout (the window prints the step's line and
  what it saw, and saves `failed-window-<n>.png`), an engine error line or a non-zero exit of any process, a window not
  done within `--seconds` (default 300; it names the last step) or a missing PNG, and stops every process it started
  through the stop file (else a kill: a window after 30 s, since its renderer's exit can wait seconds on the GPU
  driver when every core is busy, #354; the bots after 10 s). Desktop only: CI and `verify` never run it; an agent
  may (off-screen windows, like `shot`). Scenarios: `esc_menu` (#169), `spectate` (#168), `items` (a knife picked
  up, swapped to the belt and back and put down, #276) and `end` (a match ended by the clock, Back to lobby and a
  second round, #276).
- **Warnings [applied]:** `untyped_declaration`, `unsafe_method_access`, `unsafe_property_access`,
  `unsafe_call_argument` = Error; the rest stay Warn and are reported by `check`; `inferred_declaration` stays off.
- **Runner [applied]** ([ADR](decisions/2026-09-29-python-task-runner.md)): Python core `tools/run.py` with
  `tools\run.cmd` (immune to the execution policy) and `tools/run.sh`. Commands so far: `doctor`, `lint`, `check`,
  `test`, `verify`, `wait` (below), `selftest`, `pins`, `board`, `start`, `worktree-done`, `publish`, `merge-check`,
  `merge` (§7.1), `normalize`, `shot`, `run`, `agents-check`, `credits`, `host`, `join`, `bots`, `wave`, `metrics`,
  `mutants`, `playcheck`, `perf` (the last eight above), `permissions` (§8.1), and `hook` (for Claude Code only). Pins
  and pass/fail rules: [ADR](decisions/2026-09-28-toolchain-pins.md). On this machine `bash` on PATH is the WSL
  launcher, not Git Bash; `doctor` finds Git Bash through git's install folder. Outside a Claude Code session (a human's
  PowerShell) the runner takes the machine paths from the Claude settings (§2).
- **CI [applied]:** `.github/workflows/ci.yml`, job `verify` on ubuntu-24.04, runs `tools/run.sh verify` on every PR
  (whatever its base, `release/m<k>` included) and on pushes to `main`, with the checksum-checked Godot build from the
  pins. The game targets Windows for now; CI stays on GitHub's free Linux runner as an extra check, and a problem
  seen only on Linux is low priority (the engineer, 2026-10-01). A push to `release/m<k>` runs no CI: the manager's
  `verify` on the merged tree is the check there (§7.1). A second job, `python-min` (#349), sets up the pinned
  minimum Python (`pins --get python_min`, 3.11), checks it runs that version, compiles every runner file and runs
  `selftest --group python` (199 s on 3.11 in a cloud session, beside `verify`; Actions minutes cost nothing on a
  public repository): `verify`'s 3.12 never ran the stated minimum, and 3.12-only code broke `verify` in a cloud
  session on 3.11 (#345). It is a required check of `main` like `verify` (§8.5), so neither `merge` nor a human's
  merge button takes a PR while it is red. `verify` (#179) runs `doctor --quick`
  first (red: nothing else runs), then two lanes at once, each a process of its own and serial inside: the Python lane
  (`lint`, then `selftest`: the runner tests that start no Godot, each test in one of the worker processes, a quarter of
  the logical CPUs and at least one, since the lane runs beside `freeze` and `stall`) and the Godot lane (`check`, then
  `selftest-godot`: the runner test classes marked `@starts_godot`, after `check` so that a fresh checkout has
  imported the project, then `test`, `enet`, `freeze` and `stall` (the headless ENet runs of `net/`, below), `bots`
  and `bots-enet`, `chaos`, and `game`), so no two Godot runs overlap. Every step runs and any red step fails it; each step's
  output is printed whole when the step ends (`== <step> (<lane> lane, <seconds>, <status>)`). After both lanes: the
  clean-tree check, and the runner tests counted against a serial discovery (each ran once, and a decorator skipped
  it exactly where a serial run skips it; `selftest` alone runs both groups at once with the same check;
  `selftest --group python|godot` runs one group without it). The
  summary keeps the serial order (`doctor`, `lint`, `check`, `test`, `enet`, `freeze`, `stall`, `bots`,
  `bots-enet`, `chaos`, `game`, `selftest`, `selftest-godot`), then each lane's wall time, the CPU count and the
  test count.
  Each run appends a line to `tools/out/logs/verify-history.jsonl`, which `metrics` reads: `start`, `worktree`,
  `branch`, `head`, `tree` (HEAD's tree hash with a clean tree, else null), `runner` (the tree hash of `tools/runner/`
  at HEAD), `status`, `seconds`, `steps` (name, lane, status, seconds), `lanes` (wall seconds), `cpus`, `workers`,
  `selftest` (run, skipped) and `slot` (below; null without one). Since #273 a red step adds `failure`, its first `FAIL`
  line with the reason under it when a step that runs the game (`check`, `enet` to `game`) printed one (the first engine
  error line, or the first line under a `BOTS`/`CHAOS` FAILED header, such as `bots-enet`'s "a Correction outside a
  placement", #284); the `test` step adds `shards` (each GdUnit4 process's `shard`, `rc` and `seconds`, plus `results:
  false` when it wrote no `results.xml`, such as a crash's 3221225477, `timed_out` and an `error` that kept it from
  starting; shard 1 is the one process of a run without shards) and, when red, `failed_tests` (`test` as
  `<suite>::<test>`, with the failure's `message` on one line, or `orphans` for a leak) and `failed_tests_more` past 20.
  A message is cut at 240 characters, so a red record stays about 1 KB; `metrics` lists the red runs' failing tests,
  first failure lines and shard exits. **Verify slots (#185):** on a PC, after `doctor`, `verify` takes one of N
  machine-wide slots for its lanes, so the tracks' runs queue instead of starving each other (and `freeze` and `stall`):
  a lock file per slot in `%LOCALAPPDATA%\prime-game\verify-slots` (elsewhere
  `~/.cache/prime-game/verify-slots`), outside every checkout, so the main checkout and every worktree share them. The
  operating system frees a slot's lock when its process ends however it ends, so a killed run's slot is taken over at
  once (the next run names it: "left by a run that ended without releasing it"). While every slot is held the run prints
  every minute which worktrees, branches and pids hold them. The wait is bounded (default 600 s since #388; 95 s
  before, to fit an agent's 600 s foreground call, which agents no longer make: they run verify and publish in the
  background and poll them with `wait`, below). With 95 s, 7 of the 59 runs left in the verify history files (to
  2026-10-04) ran over the limit, all on 2026-10-04 with three or four tracks verifying at once, and they were slow
  (median 603 s against 359 s slotted); for the five whose holders the files name, a slot freed 207 to 536 s after the
  wait began. 600 s covers them all and is about one whole verify on the loaded PC (45 of 51 slotted runs took less):
  a longer wait means a stuck holder. After the wait the run goes ahead without a slot, with `OVER THE LIMIT` in
  its output, its summary's last line and its record (`over`). A slot never skips or weakens a step. N is 2, measured on
  the engineer's PC with #182's shards (the PR of #185): one or two runs at once took 315 to 386 s each, three 431 to
  441 s, four 452 s; two runs of 4 shards and 4 selftest workers fill the 16 logical CPUs, while a third or fourth makes
  every run a third longer (no room left for a wait in a 600 s call) and `test` red more often (freeze, stall, enet and
  bots-enet stayed green). `PRIME_VERIFY_SLOTS` (0: no limit), `PRIME_VERIFY_SLOT_WAIT` (seconds) and
  `PRIME_VERIFY_SLOTS_DIR` override the defaults; CI and a verify inside a verify (`PRIME_VERIFY_INSIDE`) take no slot.
  **Load runs (#388):** an agent that tests something under load on purpose (as #318 and #354 did with 32 hand-written
  busy loops on 16 logical CPUs, which the slots could not see while the other tracks' verify runs went on beside them)
  runs `load [--loops N] [--seconds S]` (default 2 loops per logical CPU for 600 s; at most 256 loops and 1140 s). It
  first takes a slot like a verify (the same wait and waiting line), so one verify fewer runs beside it and every
  waiting run names it (`slot 2: load run in <worktree> (...)`; its holder file has `kind: load`); past the wait it
  starts nothing and exits 1 (a load is no gate, and it would push the slotted runs over the limit). Taking a slot
  was chosen over `verify` counting load runs as extra holders: the same operating-system lock frees a killed load's
  slot at once, there is one count to reason about, and nothing else has to find and judge the load's processes. Each
  loop is its own Python process that ends by itself at most S seconds after it starts, and the runner stops any loop
  that outlives S by 5 s. A killed `load` frees its slot at once while its loops run out their time without one, so S
  is at most 1140 s: the 600 s wait, S, the 5 s grace and a 55 s start margin fit the 30-minute default limit of a
  background command, which therefore never kills a `load`. The agent starts it in the background (a log under its
  scratch folder), runs its own steps after the log's `load: running` line, and lets it end or waits for it with
  `wait <log>`.
  Tests: `tools/runner/tests/test_slots.py`, `tools/runner/tests/test_load.py`.
  The record's `slot` is {`slot`, `of`, `waited`, `over`, `reclaimed`} (and `error` when the slot folder failed: the run
  then goes ahead without a slot, a slot never stops the gate), its `seconds` leave the wait out, and the summary's last
  line adds `(after <s>s waiting for a verify slot)`; `metrics` shows the wait (median and maximum) and the runs over
  the limit. A lane process and its workers carry `PRIME_VERIFY_INSIDE`, so a runner test that reaches the real lanes
  fails instead of starting `verify` inside `verify`; a runner test that starts Godot carries `@starts_godot`
  (`runner.verify`). `bots` is `bots` (every scenario in one process, about 8 s) and `bots-enet` is `bots
  dissident_kills_the_crew --instances 3` (about 48 s since M4-3, #139: the scenario ends by time up on a 40 s clock
  that it forces, `clock_s`; M4-2's one-minute match took about 67 s). `chaos` (#188, about 6 s) is `bots --chaos --seed
  188001`, the short match's three runs; 20 runs in a row passed (2026-10-02). `game` (#149, about 5 s) starts
  `client/app/game.tscn` headless through its command line, a host (`--host --local --no-replay`) and one client
  (`--join=127.0.0.1`) on a free port: both must be welcomed into the lobby, then stop through the runner's stop
  file with exit 0 and no engine error line (logs in `tools/out/logs/game/`). The `enet` step is
  `run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3 --seconds 90`, and `freeze` (a
  5.2 s main-thread freeze of the host, then of a client, #70; about 16 s) is
  `run tests/integration/net/enet_freeze.gd --headless --instances 3 --seconds 60`; `stall` (ENet's timeouts on
  both sides and a backlog taken in one poll, #95; about 13 to 25 s, since the drops depend on the round trip) is
  `run tests/integration/net/enet_stall.gd --headless --seconds 60`, one process whose hosts take `<p>` to
  `<p> + 2`. Each gets
  `-- --port=<p>`, a random free UDP port on 127.0.0.1 in 20000–31999 (below the ephemeral ranges), so
  worktrees verifying at once very rarely share a port (if they do, the host fails with
  `host on 127.0.0.1:<p> failed`; run `verify` again). Test suites are named `<name>_test.gd`
  (GdUnit4's snake_case convention). Tested once (KICKOFF §4): a deliberately failing commit on the throwaway
  branch `tooling/2-ci-red-probe` turned CI red on 2026-09-28; repeat it after a structural change to `ci.yml`.
- **Bounded waits: `wait <log> [--max S]` and `wait --verified` [applied]** (#303; #302's token research): a workflow
  agent or subagent writes its prompt cache with a 5-minute lifetime (a main or manager session has 1 hour), so a
  tool call that blocks longer makes its next call write the whole context again. From 10-02 10:30 UTC to 10-03 20:54
  that happened 261 times (46.5M tokens, $233 of list $, 13.3 of the 66 limit points used, net of the polls), nearly
  all on `verify`, `publish`, `mutants` and `gh pr checks --watch`; the edge is sharp: 0 misses in 69 gaps of 240 to
  300 s, 64 in 91 gaps of 300 to 360 s. So such an agent blocks no tool call over 240 s, and bounds a call with the
  shell's `timeout` or `wait --max`, never only with the tool's own timeout. Since #388 every agent, a main or manager
  session too, runs `verify`, `publish` and `mutants` in the background with `wait`: a verify slot's wait alone can reach 600 s, where a
  foreground call is killed. A foreground `sleep N` followed by another
  command (`sleep 60; cat <log>`) is refused by Claude Code itself (`Blocked: sleep 60 followed by ...`, 28 times in
  the week to 2026-10-04, 26 by workflow agents, #312; their prompts get this rule through #326): wait with
  `wait <log>`, `run_in_background` or Monitor with an until-loop instead. The agent starts the job in the Bash tool with
  `run_in_background` (its timeout 3600000 for `mutants`; the default 30 minutes covers the rest), with a new log per
  run under its scratch folder: `cd <worktree> && tools/run.sh verify > <log> 2>&1; echo "exit=$?" >> <log>` (in
  the Bash tool only: PowerShell 5.1's `*>` writes UTF-16 and its `$?` is a boolean). It then calls
  `tools/run.sh wait <log>` (PowerShell: `tools\run.cmd wait <log>`) with the tool's timeout at 300000, since the
  default 120000 would cut a 240 s wait short. `wait` polls every 3 s for at most S seconds (default 240, 1 to 270;
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
  ever written): check it. CI: `timeout 240 gh pr checks <pr> --watch --interval 30; echo rc=$?` in the Bash tool with
  the tool's timeout at 300000 (its default 120000 would cut the 240 s short; in PowerShell `timeout` is Windows' own
  program), repeated while rc is 124 (the timeout) or 8 (pending); rc 1 with "no checks reported" means the run has not
  registered yet. `wait --verified` (no log) exits 0 when the newest record of `tools/out/logs/verify-history.jsonl`
  passed at HEAD with a clean tree (`tree` set) and the tree is still clean, else 1 with the reason: a publisher then
  skips its standalone `verify`, since `publish` runs one. On a branch whose base predates `wait`, the agents run these
  commands in the foreground as before. Tests: `tools/runner/tests/test_wait.py` (a fake clock; the launch line and
  `wait` through Git Bash, cmd and PowerShell 5.1; the commands pass the permission model outside bypass). The rule is
  one Shell bullet of root CLAUDE.md, the commands are `bounded_waits` (§7.1).
- **An own `user://` per worktree [applied]** (#182): Godot names `user://` after the project, so every checkout of
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
- **`test` in shards [applied]** (#182): `test` with no paths runs the suites in K GdUnit4 processes at once, K =
  half the logical CPUs, at most 4 (`gdunit.SHARD_CAP`: CI's 4 vCPUs give 2, the engineer's 16 give 4). `--shards K`
  or `PRIME_TEST_SHARDS=K` sets K (1: the one process of before); `test <paths>`, `test --repeat N` and
  `gdunit.main(paths)` stay one process. The shards are balanced by the last per-suite times
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
- **The frame-bound suites at fixed fps [applied, the default without paths]** (#280, #341): suites run with the
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
- **The real app-data folder stays clean [applied]** (#233): a worktree's `user://` folder outlives the worktree,
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
- **No Godot MCP server** before M4 (§14; [ADR](decisions/2026-09-29-no-godot-mcp-before-m4.md)). API facts come
  from `check`, the engine API dump that `doctor` generates into `tools/out/godot-api/4.7.2/`, and
  `docs.godotengine.org/en/4.7/`.

## 12. The designer's agent

- **Onboarding [applied]:** after M0 merges, the designer opens the clone in Desktop and says "налаштуй мене".
  `onboard` runs `doctor` (which sets `core.hooksPath`), writes her user settings (`env`, `language`, `defaultMode`)
  after she approves the exact content, installs gdtoolkit via a real Python with her OK, and runs
  `git lfs install --skip-repo` (§8.3). It explains the save-first rule (§11) and the one-time answer to a guard
  prompt (§8.2). Then it prints the clicks only she can make: Git for Windows (required), Python 3.11+, Godot 4.7.2,
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
  `host --clients 2 --local --seconds S` headless (§11).

## 13. How humans talk to the agent

- Existing work: "start task 42". A new idea (designer): "нова механіка: …" → `new-mechanic`.
- Issues contain: the goal, acceptance criteria as a checklist, what is out of scope, and the expected verification
  (screenshot, bot scenario or playtest).
- Size words: "plan first" → plan mode, then wait; "ultracode: …" → a bounded workflow (§7), or, naming a stage or
  a list of issues, the orchestrator session (§7.1); "just do it" → small, obvious changes only.
- Dictation: say the issue number and describe the thing; the agent reads the file name back before editing and asks
  one short question only if a misreading would change what gets built. The glossary in root `CLAUDE.md` grows from
  real misrecognitions.
- **Two readings are read back:** when a human's answer to a design question could describe different things to build
  (the look or the mechanics), the agent says its reading back in one sentence and records it in an issue, an ADR or
  a design doc only after the human confirms. A wrong guess is otherwise copied into every task built on it.
<!-- see docs/interventions/2026-09-30-engineer-ghosts-look-not-flight.md -->
- Phrases: "запам'ятай" → the question in §3; "стоп" → stop and summarise; "поясни" → explain the pending prompt or
  step.
- **The agent explains choices plainly:** start from a concrete scenario of what goes wrong, then the options; jargon
  comes after. Before designing enforcement, it asks how the humans actually work.
- Human-reserved decisions (KICKOFF §0) come as one batched question.

## 14. Open questions (deferred past M0)

| Question | When |
|---|---|
| Godot MCP server; if needed, prefer an in-game debug autoload plus the bot harness | M4 revisit |
| GDScript LSP bridge; Context7 (off; if ever used, pin `/websites/godotengine_en_4_7`) | After M2 |
| Trial the Superpowers plugin, engineer-only, on the M1 throwaway spike | M1, optional |
| Auto permission mode | After the M0 guard tests pass |
| `tools\run.cmd merge` (agent merges after the human says "merge", with CI and approval checks) | If manual merging becomes friction |
| The designer's machine: Claude Code version, plan, Python, Node, gh | Her onboarding |
| Git LFS in CI (uses LFS bandwidth quota), or `check` skipping pointer files ([ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md)) | Before the first LFS asset outside `addons/`; ask the humans |

**Pending human actions 👤** (the rulesets without bypass, the board workflows, the engineer's gh scope and
version, and the PATH `claude` are done, checked live 2026-09-29): usage credits off on both accounts; invite the
designer to the repo and to project 1 (the designer's handle is in CODEOWNERS since #85);
decide LFS in CI before the first LFS asset outside `addons/`.

**Verification of the Phase A setup:** done on 2026-09-28. A fresh session confirmed subagent routing for all four
agents and the user-settings `env`. M0's `agents-check` makes the routing check repeatable.

## 15. Night jobs

([ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md) item 6, the engineer's N3 answer (c);
#189.) The night runs deterministic jobs on GitHub for free and one Claude audit lens on the engineer's PC.

| What | Where and when | Report |
|---|---|---|
| `nightly.yml`, job `flaky`: `tools/run.sh test --repeat 3` | GitHub Actions, free Linux runners, once per ref of the night: the latest `main` commit and the newest remote `release/*` branch (#272); 01:17 UTC every night (`schedule`), or by hand (`workflow_dispatch`, optionally one ref alone) | The run's summary page and an artifact per ref, `nightly-flaky-<ref>` (`/` as `-`: `nightly-flaky-main`, `nightly-flaky-release-m5`); on a failure a comment with the run link on the "Night jobs" issue naming each job's ref |
| `nightly.yml`, job `perf`: `tools/run.sh perf` (10 bots over the loopback, a 60 s round) with `--baseline` the same ref's last successful night's report | The same run, per ref | The run's summary page and artifact `nightly-perf-<ref>`; changes beyond the threshold are listed there, never a failure; a failed match comments like `flaky` |
| `nightly.yml`, job `chaos` (#188): `tools/run.sh bots --chaos --long --runs 10` from a random seed (printed), then `bots --chaos --long --enet` | As `flaky` | Artifact `nightly-chaos-<ref>` (the logs; a failed loopback seed is named in `tools/out/logs/chaos-loopback.log`, the ENet run's in `tools/out/logs/run/chaos_main-1.log`); on a failure a comment with the run link on the "Night jobs" issue |
| The skill `night-audit`: one lens a night by weekday (docs drift, coverage, flaky, dead code) | The engineer's PC: a Desktop local scheduled task in its own worktree, daily after the nightly run | Confirmed findings as issues (`Found by: night-audit <lens>`); a summary comment on the "Night jobs" issue |

- **`test --repeat N`** runs the GdUnit4 suites N times in a row, one process per run, in real time (the #222 class,
  #341; `verify` runs the frame-bound suites at fixed fps); any failed run fails it.
  Each run's report goes to `tools/out/gdunit-runs/run-<i>/` and its log to `tools/out/logs/test-run<i>.log`;
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
  CI does (`rm -f`, so nothing on a ref without it). The refs' jobs run side by side (`fail-fast: false`); each
  ref adds its jobs' runner minutes (`main`'s three took about 16 on 2026-10-03), free in this public repository.
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
- **Desktop's limits** (code.claude.com/docs/en/desktop-scheduled-tasks, read 2026-10-02): a local task runs only
  while the Desktop app is open and the PC awake; a sleeping PC skips the run, and on wake Desktop starts one
  catch-up run for the latest missed time of the last seven days (the skill stops if that day's summary exists). A
  permission prompt stalls the run until someone answers it in the session under **Scheduled** in the sidebar.
- **Bounds of the audit** (in the skill): one lens, at most 2 agents (the auditor and one skeptic of type
  `night-skeptic`), about 100 tool calls, about $10 list a night; read-only on the repo (issue bodies in its
  worktree's `tests/scratch/`), at most 5 issues a night, never closes or edits issues. Lenses beyond docs drift
  are the first thing to drop: set every weekday in the skill to `docs-drift`.

**Reading the reports.**
- A comment on the "Night jobs" issue from the nightly workflow: open its run link. The summary page shows "GdUnit4,
  3 runs": each run's status, **flaky tests** (an issue to fix the test or the race; never skip or delete it without
  the engineer's approval), **failed in every run** (a regression on that ref: fix first), and the suites with a
  failure, once per ref (the job's name holds it). The artifact `nightly-flaky-<ref>` holds each run's HTML report,
  `summary.json` and the logs. A failure on a release ref alone is the release's own (fix it on `release/m<k>`).
- The perf job's section of the summary page: its numbers with the wire budgets' headroom, and the metrics that
  moved by more than the threshold against the last night. A jump in the host step or the bytes per peer after a
  merge is worth an issue (timings on a shared runner are noisy: look for a move that stays); the artifact
  `nightly-perf-<ref>` holds the report JSON and the run's log. The first night after #272's merge compares `main` with
  nothing (its cache key now holds the ref), and a new release branch's first night likewise.
- A night-audit summary (one a night, first line `night-audit <lens>, <date>, origin/main <sha>`): what it checked,
  the issues it opened, and what the skeptic refuted or could not decide (those are not issues). Its issues:
  `gh issue list --search "\"Found by: night-audit\" in:body"`. A wrong one is closed by a human (label `invalid`).

**The engineer's one-time setup 👤** (checked against the Desktop docs above on 2026-10-02; Claude Desktop 1.1.5368
or later):
1. After the merge, start the first nightly run by hand and check it:
   `cd D:\prime-game; gh workflow run nightly.yml --ref main`, then `gh run list --workflow nightly.yml --limit 1`
   (`-f ref=release/m5` added: that ref alone).
2. In Claude Desktop, **Code** tab: **Routines** in the sidebar (or in the sidebar's **More** menu), **New
   routine**, **Local**.
3. **Name** `night-audit`; **Description** "One audit lens a night (AGENT_WORKFLOW §15)"; **Instructions**
   `/night-audit` and nothing else. In the pickers of the instructions box: the permission mode you use for your own
   sessions (never bypass), and the strongest model the picker offers (N1 (b): an audit is one of its per-launch
   uses; no shared file names it). Below it: the folder `D:\prime-game`, and the **worktree** toggle on (the skill
   stops without a worktree of its own).
4. **Schedule** **Daily** at 06:00: the 01:17 UTC nightly run starts at 04:17 in Kyiv in summer time, may start
   late, and may take up to its 45-minute timeout, so its results are in by then; save.
5. Settings → **Desktop app** → **General** → **Keep computer awake** on (a closed laptop lid still sleeps).
6. On the task's page, **Run now** once while at the PC; answer each permission prompt with "always allow" (later
   runs approve the same tools; the page lists them under **Always allowed**). Expect one summary comment on the
   "Night jobs" issue and at most 5 new issues.
7. After a week, check that the scheduled sessions' worktrees do not pile up under `.claude/worktrees/` (not tried
   yet). Pause: the task's page, **Status** → **Paused**.
