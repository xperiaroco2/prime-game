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

- Invariants live in root because nested files drop out after compaction.
- A budget lint in `verify` fails over budget. The same PR then scopes a rule to paths, moves it into a skill, or
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
4. `tools\run.cmd start 42`: handles a dirty tree (include or stash, never discard), creates the branch
   `<area>/<issue>-<slug>`, assigns the issue if unassigned, and moves the board item to **In progress**.
   It creates a worktree `.claude/worktrees/<n>` **only when another Claude session is already active on this
   checkout**, engineer only; `tools\run.cmd worktree-done <n>` removes it after merge
   ([ADR](decisions/2026-09-28-worktrees-only-for-parallel-sessions.md)).
5. Restate goal, acceptance criteria, plan, verification commands and risks. Non-trivial work: plan mode, wait for "go".

### 4.2 Finish: "finish" / `/finish-task` (definition of done)
1. `tools\run.cmd verify`; paste the tail. Red → stop and report. Never weaken a test.
2. Fresh-context review: `code-reviewer` for code diffs (bundled `/code-review` at medium, or none, for docs-only and
   content-data diffs); plus `netcode-security-reviewer` if `core/`, `server/` or `net/` changed; plus
   `godot-api-checker` if `.gd`, `.tscn` or `.tres` changed. Fix findings or list them in the PR.
3. Update docs if durable knowledge changed; add intervention and credit entries if any.
4. One question: **"Publish now? (push + PR + handoff comment)"**.
5. `tools\run.cmd publish`: rebase on `origin/main`, re-run `verify`, push the task branch (§8.3).
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
- **Routing check:** each subagent transcript under
  `~/.claude/projects/D--prime-game/<session>/subagents/agent-*.jsonl` records the model that actually served it.
  M0 adds `tools\run.cmd agents-check`, which asserts the model **family**, not exact IDs.
- A new `.claude/agents/` directory is only seen by sessions started after it exists.

## 6. Skills [M0]

Committed in `.claude/skills/<name>/SKILL.md`; no plugins.

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
- The Python runner lints skill and agent frontmatter in `verify`, so CI needs no Claude Code install.

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
- `.claude/` changes are done interactively, not as workflows (protected-path prompts stall runs).
- `effortLevel` is never put in shared settings.

## 8. Permissions, guards and hooks

([ADR](decisions/2026-09-28-permissions-and-thin-guard.md))

### 8.1 Permission rules [applied]
`.claude/settings.json`, strict JSON. Every `Bash(...)` rule has a `PowerShell(...)` twin. Deny beats ask beats allow.
- **Allow:** the runner (`tools/run.sh`, `tools\run.cmd`), `git fetch origin`, `git add`, `git commit`, read-only
  `gh` (issue/pr view, list, checks, diff; run list/view; label list; `gh auth status --active --json`), and
  **`gh issue create`, `gh issue comment`, `gh pr create`**; WebFetch to Godot, Claude Code, GitHub and git docs.
  Read-only git (`status`, `diff`, `log`, `show`) needs no rule; `git log` is deliberately not allowlisted because
  of `--output=`.
- **Ask:** edits to `.claude/hooks|githooks|agents|skills/`, `.claude/settings*.json`, `.github/`, `addons/`, the
  runner files; raw `git push`, `switch`, `checkout`, `restore`, `reset`, `clean`, `rebase`, `worktree`,
  `branch -d`, `stash drop|clear`, `git -c`; recursive deletes and `Remove-Item`; `gh` with `-R/--repo`; `gh` edits,
  closes, deletes, reviews, `api`, `workflow`, `release`, `repo`, `project`, `secret`, `variable`, `ruleset`.
- **Deny:** force pushes, pushes to `main` in any spelling, `--no-verify`, remote deletes, `--prune`, `--mirror`,
  `--all`, `git branch -D`, `git config` on `hooksPath` or `--unset`, `--upload-pack`, `--output`,
  **`gh pr merge` and `mcp__ccd_pr__set_auto_merge`**, `gh repo delete`, `gh auth token`, token-printing
  `gh auth status`.
- Godot, Python and gdtoolkit run without a prompt **only through the runner**; their raw forms prompt.
- `GH_PROMPT_DISABLED=1` is set in the shared `env`.

### 8.2 Thin guard [M0]
A PreToolUse hook (`Bash|PowerShell|Edit|Write|NotebookEdit`), Python, fail-closed (a crash or missing Python becomes
exit 2), no network calls. It only asks before **shell commands that write to protected paths** (`Copy-Item`,
`Move-Item`, `Set-Content`, `Out-File`, `>`, `cp`, `mv` into `.claude/`, `tools/run*`, `tools/runner/`,
`.github/`), which text rules cannot see. It does not check ownership or the Godot editor. The runner and hooks find
Python as `PYTHON_BIN`, else `py -3`. `doctor` is red when Git Bash is missing, because hooks then fail open.

### 8.3 Pre-push hook and publishing [M0]
Committed at `.claude/githooks/pre-push`; `doctor` sets `core.hooksPath` to it. It blocks pushes to `main`, all
deletions and force pushes, with one exception: a non-fast-forward update of the **current task branch**
`<area>/<n>-*`, which `tools\run.cmd publish` does with `--force-with-lease` after a rebase. The agent never
force-pushes by hand ([ADR](decisions/2026-09-28-force-with-lease-on-task-branches.md)).

### 8.4 `.gd` post-edit hook [M0]
`Edit|Write` on `*.gd` (not `addons/` or `tools/out/`): gdformat, restore LF, gdlint, then an engine parse check with
a 60 s inner timeout. Problems → exit 2 with `file:line: message`. Autoloads must be side-effect-free under
`--check-mode`.

### 8.5 Server side 👤
A ruleset on `main` of the public repo: block force pushes, restrict deletions, require a PR. Required status checks
are added **after the CI PR has merged**. Code-owner review stays off. No bypass for admins.

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
- **Issue templates:** `feature`, `mechanic`, `bug`, `engine-request`, `intervention`, as Markdown with front matter;
  agents build bodies from them and pass `--label` explicitly.
- **Append-style logs are one file per entry** ([ADR](decisions/2026-09-28-one-file-per-entry-logs.md)):
  interventions in `docs/interventions/YYYY-MM-DD-<who>-<slug>.md`, asset credits in `docs/credits/<asset>.md`.
  `CREDITS.md` is generated by `tools\run.cmd credits`; `check` verifies every LFS asset has a credits file.
  `/log-intervention` writes the entry and promotes the rule in the same PR; each promoted rule carries a
  `<!-- see docs/interventions/… -->` comment.

## 11. Godot specifics

- **Editor convention** ([ADR](decisions/2026-09-28-godot-editor-save-first-convention.md)): nobody edits by hand
  while an agent works. Before asking the agent for anything, **Save All** in Godot. If Godot asks about files changed
  on disk, always choose **Reload from disk**. The agent reminds the human; nothing blocks.
- **`.tscn` / `.tres`:** the agent hand-writes readable text and never copies a uid or a `.uid` sidecar;
  `tools\run.cmd normalize <files>` re-saves them in headless editor context; `check` fails on UID problems, on files
  left modified by `--import`, and on an `ext_resource` uid that resolves to a different file than its `path=`.
- **Warnings:** `untyped_declaration`, `unsafe_method_access`, `unsafe_property_access`, `unsafe_call_argument` =
  Error; the rest stay Warn and are reported by `check`; `inferred_declaration` stays off.
- **Runner:** Python core `tools/run.py` with `tools\run.cmd` (immune to the execution policy) and `tools/run.sh`.
- **No Godot MCP server** before M4 (§14). API facts come from `check`, the engine API dump that `doctor` generates
  into `tools/out/godot-api/4.7.2/`, and `docs.godotengine.org/en/4.7/`.

## 12. The designer's agent

- **Onboarding [M0]:** after M0 merges, the designer opens the clone in Desktop and says "налаштуй мене". `onboard`
  runs `doctor`, writes her user settings (`env`, `language`, `defaultMode`) after she approves the exact content,
  installs gdtoolkit via a real Python, runs `git lfs install` and sets `core.hooksPath`. Then it prints the clicks
  only she can make: Git for Windows (required), Python 3.11+, Godot 4.7.2, repo and project invites,
  `gh auth login` + `gh auth refresh -s project`, trusting the folder, checking her Claude plan, usage credits off.
  It ends with a one-page summary for her sign-off, where she may reopen any decision that binds her.
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
| Git LFS in CI (uses LFS bandwidth quota) | Ask the humans before enabling |

**Pending human actions 👤:** add the ruleset on `main` of the existing public repo `xperiaroco2/prime-game`;
`gh auth refresh -s project` and upgrade gh; usage credits off; update or remove the PATH `claude`; invite the
designer; set the board workflows.

**Verification of the Phase A setup:** done on 2026-09-28. A fresh session confirmed subagent routing for all four
agents and the user-settings `env`. M0's `agents-check` makes the routing check repeatable.
