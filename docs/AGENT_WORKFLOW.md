# Agent Workflow

| | |
|---|---|
| **Status** | Decided 2026-09-28 (KICKOFF Phase A, step 5). Owned by the engineer, read by both agents. |
| Reasons | One ADR per significant decision in `docs/decisions/2026-09-28-*.md` |
| History | The proposal, research, reviews and metrics: `docs/history/2026-09-28-phase-a/` |

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
| Machine paths | `GODOT_BIN`, `GODOT_GUI_BIN`, `PYTHON_BIN`, `GDTOOLKIT_DIR` in the `env` of each human's `~/.claude/settings.json`, so every session, worktree, hook and subagent sees them ([ADR](decisions/2026-09-28-machine-env-in-user-settings.md)) | [applied] engineer |
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
4. `tools\run.cmd start 42` **[applied]**: creates `<area>/<issue>-<slug>` from `origin/main` with no upstream (the
   area from the issue's single `area:*` label, else `--area`), or resumes the issue's existing branch; assigns the
   issue if unassigned; moves the board item to **In progress**. Uncommitted changes stop it with the list:
   `--include` carries them onto the task branch, `--stash` stashes them; it never discards. `--dry-run` only
   fetches. It creates a worktree `.claude/worktrees/<n>` instead **only when another Claude session is active on
   this checkout**, engineer only (`--worktree` / `--here` override); for the designer it then stops rather than
   switch the branch under that session. `tools\run.cmd worktree-done <n>` removes the worktree once its branch is
   merged ([ADR](decisions/2026-09-28-worktrees-only-for-parallel-sessions.md)).
5. Restate goal, acceptance criteria, plan, verification commands and risks. Non-trivial work: plan mode, wait for "go".

### 4.2 Finish: "finish" / `/finish-task` (definition of done)
1. `tools\run.cmd verify`; paste the tail. Red → stop and report. Never weaken a test.
2. Fresh-context review: `code-reviewer` for code diffs (bundled `/code-review` at medium, or none, for docs-only and
   content-data diffs); plus `netcode-security-reviewer` if `core/`, `server/` or `net/` changed; plus
   `godot-api-checker` if `.gd`, `.tscn` or `.tres` changed. Fix findings or list them in the PR.
3. Update docs if durable knowledge changed; add intervention and credit entries if any.
4. One question: **"Publish now? (push + PR + handoff comment)"**.
5. `tools\run.cmd publish`: rebase on the open PR's base (else `origin/main`), re-run `verify`, push the task branch
   with a lease (§8.3).
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
  size guideline needs the human's explicit approval in that same message; "ultracode" alone does not count.
- A run never decides a human-reserved item; it records options and a recommendation and continues.
- Design runs produce documents first. Output lands as focused PRs, each with its verification, checked by a
  **fresh** agent.
- Changes to `.claude/settings*.json` and `addons/` wait for the human (ask rules prompt in every mode). Other
  `.claude/` paths are protected by Claude Code itself and prompt in every mode except bypass, so unattended runs
  that edit them need bypass.
- `effortLevel` is never put in shared settings.

## 8. Permissions, guards and hooks

([ADR](decisions/2026-09-28-permissions-and-thin-guard.md))

### 8.1 Permission rules [applied]
`.claude/settings.json`, strict JSON. Every `Bash(...)` rule has a `PowerShell(...)` twin. Deny beats ask beats allow.
**Goal: an agent can work unattended for an hour** (read status, branch, commit, push its task branch, open PRs and
issues, edit tooling) and stops only for the rare items below
([ADR](decisions/2026-09-28-unattended-work-permissions.md)).
- Deny and ask rules apply in **every** permission mode, including bypass; allow rules matter only in the modes that
  prompt (the designer's `acceptEdits`).
- **Allow:** the runner; `git fetch origin`, `add`, `commit`, `log`, `switch`, `branch`, `stash` (push/list/pop),
  `git push [-u] origin <branch>`; `gh` issue and PR create/view/list/comment/edit/close/ready, run
  list/view/watch/rerun, workflow list/view, `label`, `project`, `ruleset`, `repo view`, `api` (GET and POST);
  WebFetch to Godot, Claude Code, GitHub and git docs.
- **Ask (the agent's stop points):** edits to `.claude/settings*.json` (its own permissions) and `addons/`
  (dependencies); work-discarding or history-rewriting git (`checkout`, `switch --discard-changes|-f`, `restore`,
  `reset`, `clean`, `rebase`, `worktree`, `branch -d`, `stash drop|clear`, `git -c`); recursive deletes; `gh` with
  `-R/--repo`; `gh api` PUT/PATCH/DELETE; deleting issues, labels, projects or the last comment; `gh pr review`;
  `gh workflow run|enable|disable`; `gh release`, `secret`, `variable`; `gh repo edit|rename|archive|deploy-key`.
- **Deny:** force pushes; pushes to `main` in any spelling, including a bare `git push`, `git push [-u] origin` with
  no branch and any push naming `HEAD` (always push an explicit branch name); `--no-verify`, remote deletes,
  `--prune`, `--mirror`, `--all`, `git branch -D`, `git config` on `hooksPath` or `--unset`, `--upload-pack`,
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

The guard is a PreToolUse hook on `Bash|PowerShell`, with no network calls. It only asks before **shell commands
that write to the ask-protected paths** of this project (top-level `.claude/settings*.json` and `addons/`, of the
main checkout or a worktree): `Copy-Item`, `Move-Item`, `Set-Content`, `Out-File`, `>`, `tee`, `cp`, `mv`, `rm`,
`sed -i`, archive extraction, downloads, `git checkout|restore|rm|mv|clean|stash` naming those paths, paths fed by a
pipeline (`Get-ChildItem addons | Remove-Item`, `| xargs rm`), `for` loops over them, `bash -c`, `powershell -Command`
and `$(...)` bodies, and the inline code of interpreters and .NET calls (`python -c`, a heredoc fed to Python,
`node -e`, `[IO.File]::WriteAllText`). Text rules cannot see these writes: Claude Code checks a redirect or `tee`
target against Edit allow and deny rules, not ask rules. The file tools need no guard, because `Edit(...)` rules
cover Edit, Write and NotebookEdit.
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
- `publish`: `git fetch --prune origin`, rebase (`--fork-point`) on the open PR's base (a stacked PR's parent) or
  `main`, `verify`, then the lease push. It stops before touching anything when the remote branch has a commit this
  branch never had (a suggestion committed on GitHub, "Update branch", a push from the other machine): the lease
  alone would not protect it, because the fetch just updated the expected value. A conflict aborts the rebase and
  leaves the branch as it was; a red `verify` pushes nothing. `--fork-point` lets a stacked child replay only its own
  commits after its parent was rebased or amended.
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
  pull requests and closed issues. 👤 The built-in workflows above can only be set in the web UI.
- **Issue templates [applied]:** `feature`, `mechanic`, `bug`, `engine-request`, `intervention` in
  `.github/ISSUE_TEMPLATE/`, as Markdown with front matter, plus `.github/pull_request_template.md`. Agents build
  bodies from them and pass `--label` explicitly.
- **Labels and milestones [applied]:** one area label per folder, `area:core`, `area:server`, `area:net`,
  `area:client`, `area:voice`, `area:content`, `area:level`, `area:tooling` (KICKOFF §5.1 plus `server` and
  `client`, the engineer's choice on 2026-09-29), and `blocked`, `needs-design`, `needs-engine`; milestones `M0` to
  `M7` with the
  roadmap goals.
- **CODEOWNERS [applied]:** `.github/CODEOWNERS` mirrors §9. 👤 `@REPLACE_WITH_DESIGNER_HANDLE` is a placeholder
  until the designer's handle is known.
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
  readable text and never copies a uid or a `.uid` sidecar; `tools\run.cmd normalize <files>` **[applied]** re-saves
  them in headless editor context (`--headless -e -s`, after the first file-system scan), which adds the header uid and node `unique_id`s the editor would. A second run
  leaves the file byte-identical. Godot drops a property it does not know (a typo), one at its default, and any line
  after a parse error, without an error: `normalize` compares property keys before and after, and on a loss restores
  the file and fails. `check` fails on UID problems, on files left modified by `--import`, and on an `ext_resource`
  uid that resolves to a different file than its `path=`.
- **`shot <scene>` [applied]:** a real window at `--position -30000,-30000` (off-screen), never headless or minimized
  (Godot then never draws), a 60 s watchdog, a PNG in `tools/out/shots/`. A scene with no camera (a level piece) gets
  one that frames all its geometry, plus a light if it has none. Desktop only: CI never runs it, and the designer
  gets the PNG to drag into the PR (`gh` cannot upload images). `tools/shot/probe.tscn` is its smoke test.
- **Warnings [applied]:** `untyped_declaration`, `unsafe_method_access`, `unsafe_property_access`,
  `unsafe_call_argument` = Error; the rest stay Warn and are reported by `check`; `inferred_declaration` stays off.
- **Runner [applied]** ([ADR](decisions/2026-09-29-python-task-runner.md)): Python core `tools/run.py` with
  `tools\run.cmd` (immune to the execution policy) and `tools/run.sh`. Commands so far: `doctor`, `lint`, `check`,
  `test`, `verify`, `selftest`, `pins`, `board`, `start`, `worktree-done`, `publish`, `normalize`, `shot`,
  `agents-check`, `credits`, and `hook` (for Claude Code only); `bots`, `host` and `join` come with the bot harness
  (M3) and the M1 spike. Pins and pass/fail rules: [ADR](decisions/2026-09-28-toolchain-pins.md). On this machine
  `bash` on PATH is the WSL launcher, not Git Bash; `doctor` finds Git Bash through git's install folder.
- **CI [applied]:** `.github/workflows/ci.yml`, job `verify` on ubuntu-24.04, runs `tools/run.sh verify` on every PR
  and on `main`, with the checksum-checked Godot build from the pins. Test suites are named `<name>_test.gd`
  (GdUnit4's snake_case convention).
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
  `.tres` · M3 bot scenarios · M4 level pieces with `shot` screenshots; "запусти хост і двох клієнтів" runs
  `run host` / `run join`.

## 13. How humans talk to the agent

- Existing work: "start task 42". A new idea (designer): "нова механіка: …" → `new-mechanic`.
- Issues contain: the goal, acceptance criteria as a checklist, what is out of scope, and the expected verification
  (screenshot, bot scenario or playtest).
- Size words: "plan first" → plan mode, then wait; "ultracode: …" → a bounded workflow (§7); "just do it" → small,
  obvious changes only.
- Dictation: say the issue number and describe the thing; the agent reads the file name back before editing and asks
  one short question only if a misreading would change what gets built. The glossary in root `CLAUDE.md` grows from
  real misrecognitions.
- Phrases: "запам'ятай" → the question in §3; "стоп" → stop and summarise; "поясни" → explain the pending prompt or
  step.
- **The agent explains choices plainly:** start from a concrete scenario of what goes wrong, then the options; jargon
  comes after. Before designing enforcement, it asks how the humans actually work.
- Human-reserved decisions (KICKOFF §0) come as one batched question.

## 14. Open questions (deferred past M0)

| Question | When |
|---|---|
| Bot-scenario format and location | Pre-M2 content-API design |
| Godot MCP server; if needed, prefer an in-game debug autoload plus the bot harness | M4 revisit |
| GDScript LSP bridge; Context7 (off; if ever used, pin `/websites/godotengine_en_4_7`) | After M2 |
| Trial the Superpowers plugin, engineer-only, on the M1 throwaway spike | M1, optional |
| A Fable `code-reviewer-deep` as the engineer's personal opt-in, never in workflows | On demand |
| Auto permission mode | After the M0 guard tests pass |
| `tools\run.cmd merge` (agent merges after the human says "merge", with CI and approval checks) | If manual merging becomes friction |
| The designer's machine: Claude Code version, plan, Python, Node, gh | Her onboarding |
| Git LFS in CI (uses LFS bandwidth quota), or `check` skipping pointer files ([ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md)) | Before the first LFS asset outside `addons/`; ask the humans |

**Pending human actions 👤:** add the ruleset on `main` of the existing public repo `xperiaroco2/prime-game`;
`gh auth refresh -s project` and upgrade gh; usage credits off; update or remove the PATH `claude`; invite the
designer and replace the CODEOWNERS placeholder; set the board workflows (web UI only).

**Verification of the Phase A setup:** done on 2026-09-28. A fresh session confirmed subagent routing for all four
agents and the user-settings `env`. M0's `agents-check` makes the routing check repeatable.
