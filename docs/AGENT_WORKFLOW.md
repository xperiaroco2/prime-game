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
| `.claude/settings.local.json` | Personal permission approvals only; gitignored and untracked | [applied] |
| Godot import scope | `docs/.gdignore` keeps the editor from importing anything under `docs/` | [applied] |
| Auto mode | Not yet. Revisit after the M0 guard tests pass (§14) | — |

## 3. Instruction files and memory

| File | Loaded | Content | Budget |
|---|---|---|---|
| Root `CLAUDE.md` (engineer-owned) | Always; re-injected after compaction | Hard rules, **architecture invariants**, exact runner commands, PowerShell rules, ownership map, skill routing, definition of done, stop-and-ask list, memory guardrail, dictation glossary | ≤ 150 lines, counting unscoped rule files |
| `core/ server/ net/ client/ voice/` `CLAUDE.md` | When a file there is read | Engineer area rules | ≤ 100 lines each |
| `content/ levels/` `CLAUDE.md` (designer-owned) | Same | How to author mechanics and maps without engine code | ≤ 100 lines each |
| `.claude/rules/*.md` with `paths:` | When a matching file is touched | `gdscript.md`, `tests.md`, `godot-resources.md` | ≤ 60 lines each |
| `docs/*.md` | Only when read | Architecture (with the **content API**), GDD, roadmap, ADRs. Linked, never `@imported` | none |

- Invariants live in root because nested files drop out after compaction
  ([ADR](decisions/2026-09-29-instruction-files-and-budgets.md)).
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
   removes the worktree once its branch is merged
   ([ADR](decisions/2026-09-28-worktrees-only-for-parallel-sessions.md)); `--pushed` also removes one whose branch is
   never merged (a spike) once `origin/<branch>` holds all its commits, and keeps that local branch. Run it from the
   main checkout: Windows cannot delete a folder a process sits in, so it refuses when the current folder is inside the
   worktree or any live Claude session (even one idle for days, or the calling one) has it as its folder; archive that
   session in the app first. A rerun finishes a half-done removal (an empty leftover folder, the issue's merged local
   branch).
5. Restate goal, acceptance criteria, plan, verification commands and risks. Non-trivial work: plan mode, wait for "go".

### 4.2 Finish: "finish" / `/finish-task` (definition of done)
1. `tools\run.cmd verify`; paste the tail. Red → stop and report. Never weaken a test. Once the bot harness
   exists (M3), `verify` runs the bot match too.
2. Fresh-context review: `code-reviewer` for code diffs (bundled `/code-review` at medium, or none, for docs-only and
   content-data diffs); plus `netcode-security-reviewer` if `core/`, `server/` or `net/` changed; plus
   `godot-api-checker` if `.gd`, `.tscn` or `.tres` changed. Fix findings or list them in the PR.
3. Update docs if durable knowledge changed; add intervention and credit entries if any.
4. One question: **"Publish now? (push + PR + handoff comment)"**.
5. `tools\run.cmd publish`: rebase on the open PR's base (else the `start --base` parent, else `origin/main`), re-run
   `verify`, push the task branch with a lease (§8.3).
6. Open the PR from the template: `Closes #42`, summary, verification commands and output, `shot` screenshots for
   visual changes, docs updated yes/no, `--reviewer <other human>` if the other owner's paths are touched.
7. Handoff comment on the issue (done / left / decisions / gotchas); board item → **In review** via the runner.

### 4.3 Context hygiene
- One issue per session; a new issue starts a new session.
- `/clear` between unrelated tasks, after two failed corrections on the same point, and after a plan is approved
  when the plan is enough to implement from.
- After compaction, re-read the area `CLAUDE.md` before editing.

## 5. Subagents and models

Files in `.claude/agents/` **[applied]**. All four are read-only: no Edit, Write or NotebookEdit, `disallowedTools`
includes `Agent`, no `memory:` field. Their shell use is limited by the shared permission rules.

| Agent | Job | Model |
|---|---|---|
| `godot-api-checker` | Check changes against the pinned Godot 4.7.2 API; flag Godot 3 idioms. Sources: `check`, the engine API dump, `docs.godotengine.org/en/4.7/` only | `sonnet` |
| `test-runner` | Run test / lint / check / bots via the runner; return only failures | `haiku` |
| `code-reviewer` | Review the branch diff against `CLAUDE.md`, `ARCHITECTURE.md` and the content API | `opus`, effort high |
| `netcode-security-reviewer` | Information leaks, unvalidated intents, host-trust assumptions | `opus`, effort high |

- **Model guard [applied]:** `"availableModels": ["opus", "sonnet", "haiku"]` in the shared settings. A request for
  another model falls back with a warning. Fable appears in no shared file
  ([ADR](decisions/2026-09-28-model-guard-no-fable-in-shared-config.md)). 👤 Both humans keep **usage credits off**
  or set a spend cap: the only hard stop on money.
- **Routing check [applied]:** each subagent transcript under
  `~/.claude/projects/D--prime-game/<session>/subagents/agent-*.jsonl` records the model that actually served it,
  and `agent-*.meta.json` next to it the `agentType` and any requested `model`. `tools\run.cmd agents-check`
  (this session; `--all` for every session of the checkout and its worktrees) asserts the model **family**, not exact
  IDs: the requested model, else the agent file's `model:`. A request outside `availableModels` must be served by
  another family (the model guard). `finish-task` runs it after the reviews.
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
- **When:** a whole stage or a list of issues that can run in parallel, with the engineer around to merge and
  answer. One issue alone stays a normal task session (§4).
- **How:** one session in ultracode, the **manager**, runs the skill. For each task it runs `start` itself, then the
  saved workflow `issue-task` (`.claude/workflows/issue-task.js`: implementer → fresh reviewers chosen from the
  changed paths → publisher; `design: true` for a docs-only design task) with `args` (issue, worktree, branch, base,
  notes, coordination, the engineer's decisions). A semantic conflict after a merge goes to `pr-rebase`
  (`.claude/workflows/pr-rebase.js`); a docs or test-list conflict the manager resolves inline. A session runs a
  saved workflow as `/issue-task`, or with the Workflow tool by `name` or `scriptPath`; after editing one, a running
  session needs `/reload-skills` (code.claude.com/docs/en/workflows).
- **Bounds:** at most three tasks at once; implementer about 250 tool calls, reviewers about 60, publisher about 150;
  every agent writes temporary files only under its issue's scratchpad subfolder `a<n>/`. `issue-task` runs up to
  five agents, over the `small` guideline, so the kickoff approves that and the stage's budget once, confirmed by
  the human's yes to the manager's restatement (§7). Code tasks wait for the engineer's review of the stage's
  design PR; before launching anything, the manager lists the runs another session may still own (issues In
  progress with no PR, fresh worktree commits, a rebase in progress) and asks.
- **The human:** writes the kickoff (template in the skill), merges in the order the manager gives, answers the
  numbered "Needs the engineer" questions, and runs the housekeeping (`worktree-done`). The manager reports on the
  plan issue after each wave and stops with a comment when nothing more can run without merges.
- **Recovery:** a crashed run resumes with `resumeFromRunId` and the same args; the prompts tell each agent to check
  what an earlier attempt already did, so a fresh run with the same args also continues. Each wave comment on the
  plan issue lists the running runs with their args, so a new manager session can take over from GitHub alone.

## 8. Permissions, guards and hooks

([ADR](decisions/2026-09-28-permissions-and-thin-guard.md))

### 8.1 Permission rules [applied]
`.claude/settings.json`, strict JSON. Every `Bash(...)` rule has a `PowerShell(...)` twin. Deny beats ask beats allow.
**Goal: an agent can work alone overnight** (read status, branch, commit, push its task branch, open PRs and issues,
edit tooling, clean up its scratchpad and `tests/scratch/`) and stops only for the rare items below
([ADR](decisions/2026-09-28-unattended-work-permissions.md)). **Test for a new ask or deny rule:** "can an agent work
alone overnight?" Replay the latest unattended run's transcripts against the new rule
(`tools\run.cmd permissions --before origin/main` replays every local transcript through the rules and the guard of
`origin/main` and of the checkout, in bypass mode); a rule that would have stopped routine work is judged by its
target in the guard (§8.2) instead of by its text
([intervention](interventions/2026-09-30-engineer-night-run-blocked-by-prompts.md)). `runner.permissions` models
Claude Code's matcher (subcommands, wrappers, `*`, deny before ask before allow), and its selftests
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
  token-printing `gh auth status`.
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
cover Edit, Write and NotebookEdit.

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
  full `check`, `test` and `lint` runs leave it out, so a half-written probe never turns `verify` red. Godot still
  imports it: no `class_name` and no copied `.tscn`/`.tres` uid there (the UID lint fails on a copy). Never create
  a link or junction there: the guard judges a delete by its text path, and PowerShell 5.1 `Remove-Item -Recurse`
  on a junction deletes what it points to.
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
  and never after the same command changed the stash (the indices shift). An interactive rebase whose
  `GIT_SEQUENCE_EDITOR` the command sets to `:` or `true` (a prefix; in bash `export`, in PowerShell `$env:`, as that
  shell's last value; it outranks every other editor setting) opens no todo editor and is judged like a plain
  rebase: `git commit --fixup=HEAD` then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>` stays
  editor-free (a `squash!` commit would still open the message editor) (#104). Always asks: another
  interactive rebase (`-i`, `--edit-todo`: an agent cannot use the editor), `rebase --update-refs` (moves other
  branches), `rebase -x|--exec` (runs commands the guard cannot judge), `update-ref --stdin` and
  `git -c core.hooksPath=...` (the deny rule on `git config *hooksPath*` cannot see it).
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
  of another repository without naming it.
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

### 8.3 Pre-push hook and publishing [applied]
Committed at `.claude/githooks/pre-push`; `doctor` sets `core.hooksPath` to `.claude/githooks` (the agent's own
`git config *hooksPath*` is denied). It blocks pushes to `main`, all deletions and force pushes (any non-fast-forward
update), with one exception: the **current task branch** `<area>/<n>-*` pushed by `tools\run.cmd publish`, which
marks its `--force-with-lease` push with `PRIME_GAME_PUBLISH=force-with-lease`. A force push typed by hand has no
marker and is blocked; `--dry-run` pushes run the hook too. The agent never force-pushes by hand
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
- **Live state (read 2026-09-29 with `gh api .../rulesets`):** `main-1` blocks deletions and non-fast-forward
  pushes; `main-2` requires a PR (0 approvals) and the `verify` check. Neither has a bypass: the engineer removed
  `main-2`'s admin bypass on 2026-09-29, so the admin account the agents push as cannot skip them either.
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
- The engineer's agent does not rebalance or redesign content without the designer's approval in the PR.
- MVP exception: the engineer's agent builds the MVP's `content/` data and `levels/` scenes, each PR with the
  engineer's explicit approval and marked provisional; the designer may replace them
  ([ADR](decisions/2026-09-29-mvp-content-built-by-the-engineer.md)).

## 10. GitHub coordination

- **Repo:** public, GitHub Free ([ADR](decisions/2026-09-28-public-repo-on-github-free.md)). The Phase A archive
  is published as is.
- **Merging:** only humans merge, with the Merge button on GitHub or in the Desktop PR pane, after CI is green.
  A cross-area PR is approved by the other owner first. The designer reviews through `shot` screenshots and a
  playtest, never the diff ([ADR](decisions/2026-09-28-humans-merge-prs.md)).
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
  one that frames all its geometry, plus a light if it has none. Desktop only: CI never runs it, and the designer
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
  `--headless` (never a window while a human uses the machine). The first run in a fresh worktree imports the
  project; after adding scripts or assets run `check` first. `tools/run/probe.gd` is its smoke test.
- **Warnings [applied]:** `untyped_declaration`, `unsafe_method_access`, `unsafe_property_access`,
  `unsafe_call_argument` = Error; the rest stay Warn and are reported by `check`; `inferred_declaration` stays off.
- **Runner [applied]** ([ADR](decisions/2026-09-29-python-task-runner.md)): Python core `tools/run.py` with
  `tools\run.cmd` (immune to the execution policy) and `tools/run.sh`. Commands so far: `doctor`, `lint`, `check`,
  `test`, `verify`, `selftest`, `pins`, `board`, `start`, `worktree-done`, `publish`, `normalize`, `shot`, `run`,
  `agents-check`, `credits`, and `hook` (for Claude Code only); `bots`, `host` and `join` come with the bot harness
  (M3) and the M1 spike. Pins and pass/fail rules: [ADR](decisions/2026-09-28-toolchain-pins.md). On this machine
  `bash` on PATH is the WSL launcher, not Git Bash; `doctor` finds Git Bash through git's install folder. Outside a
  Claude Code session (a human's PowerShell) the runner takes the machine paths from the Claude settings (§2).
- **CI [applied]:** `.github/workflows/ci.yml`, job `verify` on ubuntu-24.04, runs `tools/run.sh verify` on every PR
  and on `main`, with the checksum-checked Godot build from the pins. `verify` runs, in this order: `doctor --quick`,
  `lint`, `check`, `test`, `enet`, `freeze` and `stall` (the headless ENet runs of `net/`, below) and `selftest`;
  any red step fails it. The `enet` step is
  `run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3 --seconds 90`, and `freeze` (a
  5.2 s main-thread freeze of the host, then of a client, #70; about 16 s) is
  `run tests/integration/net/enet_freeze.gd --headless --instances 3 --seconds 60`; `stall` (ENet's timeouts on
  both sides and a backlog taken in one poll, #95; about 15 to 25 s, since the drops depend on the round trip) is
  `run tests/integration/net/enet_stall.gd --headless --seconds 60`, one process whose hosts take `<p>` to
  `<p> + 2`. Each gets
  `-- --port=<p>`, a random free UDP port on 127.0.0.1 in 20000–31999 (below the ephemeral ranges), so
  worktrees verifying at once very rarely share a port (if they do, the host fails with
  `host on 127.0.0.1:<p> failed`; run `verify` again). Test suites are named `<name>_test.gd`
  (GdUnit4's snake_case convention). Tested once (KICKOFF §4): a deliberately failing commit on the throwaway
  branch `tooling/2-ci-red-probe` turned CI red on 2026-09-28; repeat it after a structural change to `ci.yml`.
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
  screenshots; "запусти хост і двох клієнтів" runs `run host` / `run join`.

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
| A Fable `code-reviewer-deep` as the engineer's personal opt-in, never in workflows | On demand |
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
