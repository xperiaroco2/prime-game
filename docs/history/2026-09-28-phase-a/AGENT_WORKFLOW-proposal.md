# Agent Workflow — PROPOSAL (pending approval)

| | |
|---|---|
| **Status** | **Proposal. Nothing in this document has been applied.** |
| Date | 2026-09-28 |
| Scope | KICKOFF.md Phase A, steps 3–4 |
| Approvers | The engineer, plus the designer for every item marked **✍D** (it binds her machine, habits or bill) |
| After approval | This file moves to `docs/history/AGENT_WORKFLOW-proposal.md`. `docs/AGENT_WORKFLOW.md` is rewritten as the **decided state only**: about 200 lines, one section per role, no alternatives. Reasoning, alternatives and the key local test scripts go into the ADRs (§14). |

## How to review

§1 has three tiers:
- **Tier 1:** 10 questions. Answer each with a letter, e.g. `D1 D, D2 B, D3 A, …`.
- **Tier 2:** standing defaults. Say "tier 2 OK", or name the ones you veto.
- **Tier 3:** technical choices the agent makes during M0. Each is recorded in an ADR with test output, and you can still veto it.

Each Tier 1 row has a **"What changes for you"** column. ⚠ marks a deviation from KICKOFF.md, 💰 a possible cost,
and 👤 a step only a human can do.

**Evidence.** The research was a multi-agent run:
1. 10 topic researchers, each followed by an independent adversarial fact-checker.
2. A completeness critic and 6 gap investigations.
3. An adversarial review of this draft through four lenses: facts, brief compliance, the two humans, and config
   security.

About a third of first-pass claims were corrected along the way, and this document uses the corrected versions.

Claims that drive a recommendation are tagged:
- **[doc]**: official docs fetched 2026-09-28;
- **[local]**: tested on this machine;
- **[inferred]**: reasoned, not tested.

Untagged details come from the verified research notes. All research, reviews, workflow scripts, local test
scripts and per-agent metrics are archived in `docs/history/2026-09-28-phase-a/` (see its README).

---

## 0. Facts this proposal rests on

1. **Two Claude Code builds are installed [local].**
   - The Desktop Code tab, which the humans use, runs its bundled **2.1.281**.
   - The `claude` on PATH is **2.1.195** (June). Rider's terminal or JetBrains integration would start that one.
   - **2.1.284 was released today [doc].** It makes the `sonnet` alias mean Sonnet 5.5, and turns ultracode into
     its own toggle that no longer forces xhigh effort.
   - The designer's version is unknown.
2. **PowerShell is the agent's primary shell [doc][local].**
   - `Bash(...)` permission rules and `Bash` hook matchers do not cover it. Every rule needs a `PowerShell(...)` twin.
   - PowerShell 5.1 has **no `&&` or `||`**.
   - PowerShell 5.1 strips embedded double quotes from native-exe arguments [local].
3. **Shell traps on this machine [local].**
   - `bash` typed in PowerShell starts **WSL Ubuntu**.
   - `python` on PATH is the Microsoft Store stub.
   - The gdtoolkit exes are not on PATH.
   - The machine execution policy is the Windows default, so humans cannot run `.ps1` scripts from their own
     terminal.
4. **Hooks on Windows [doc].**
   - Shell-form hooks run under **Git Bash**.
   - `"shell": "powershell"` spawns only `pwsh` (open issue #90077), which is not installed here.
   - A hook that cannot start, crashes with exit 1, or times out does **not** block. It fails open.
5. **Permission rules match command text, so they are not a boundary [doc][local].**
   - `git -C . push`, abbreviated flags (`--no-veri`), `GIT_CONFIG_*` variables, and **allowed commands with
     side-effect flags** all get past them. Examples: `git log --output=<file>` overwrote a file, and `git fetch
     --upload-pack=<cmd>` ran a command.
   - Native Windows has no sandbox.
   - `ask` rules prompt even in Auto mode, and even when a hook returns "allow".
6. **Protected paths are only a speed bump [doc].** Writes to `.claude/`, `.git/` and `.idea/`:
   - prompt in Manual and Accept edits;
   - go to the classifier in Auto;
   - are allowed in Bypass.

   One prompt option also allows all `.claude/` edits for the rest of the session.
7. **A private repo on GitHub Free has no server-side enforcement [doc][local].** There are no protected branches,
   rulesets, required checks or code-owner review. The API returned 403 on this account's existing private repos.
8. **GitHub CLI [local].**
   - The token lacks the `project` scope.
   - `gh issue create --template` cannot run non-interactively.
   - gh 2.88.1 predates fixes for four security advisories. One of them: `gh auth status` could print part of some
     token types.
9. **Godot's CLI misleads naive checks [local].**
   - Runtime errors exit 0.
   - An error inside a `-s` script's `_initialize` hangs forever.
   - Bare `-d` hangs at a `debug>` prompt.
   - `--import` is not a parse check.
   - `--check-only` false-fails on autoload references.
   - gdlint misses Godot 3 APIs; the engine parser catches them.
   - gdformat writes CRLF on Windows.
   - Screenshots cannot be taken headless; a windowed run placed off-screen works.
10. **The Godot editor never merges external changes to an open scene [doc: engine source; GUI not tested].**
    - "Reload from disk" discards the designer's unsaved edits.
    - "Ignore external changes" re-saves the editor's copy over the agent's file.
    - A loaded `.tres` reloads silently and drops unsaved inspector edits.

    The editor was open on `D:\prime-game` during this research, and it is easy to detect by process command line.
11. **Context [doc].**
    - Nested `CLAUDE.md` files and path-scoped rules load only when a matching file is read, and **drop out after
      compaction**.
    - Auto memory is **machine-local**: the two agents never share it.
12. **Fable [doc][local].**
    - On Pro, Fable bills usage credits. Credits are off by default, so without them a Fable request either shows a
      consent prompt, silently runs on the default model, or does something undocumented for subagents and
      workflows.
    - On Max, Fable may use 50% of the weekly limit.
    - This account is Max 5x. The designer's plan is unknown.
13. **Built-in name collisions [doc].** Claude Code bundles `/doctor`, `/verify` and `/run`. A project skill with any
    of those names replaces the bundled one.
14. **Disk [local].** C: has about 10 GB free. Godot's user data and shader cache live there.

---

## 1. Decision register

### Tier 1: decide now (answer with a letter)

| ID | Decision (section) | Options | Rec. | What changes for you |
|---|---|---|---|---|
| **D1** 💰👤✍D | Repo visibility and GitHub plan (§9.1) | A public, Free · B private, personal **Pro** · C private, org **Team** ($4/user/month) · D private, Free | **B**, or A if public source is acceptable. **D** is fine to *start*: the client-side guards ship in every option, so upgrading later needs no rework | A–C: GitHub itself blocks direct pushes, force pushes and deletions on main, and requires green CI before merge. Review stays a D2 agreement, not a server rule. D: only the local guards do this, and they can be bypassed (§8.5) |
| **D2** ✍D | Who merges PRs (§9.2) | A humans click **Merge** on GitHub or in the Desktop PR pane; agents never merge · B the author human says "merge", and the agent runs `tools\run.cmd merge`, which checks CI is green and the cross-area approval exists | **A** | A: one click per PR. The designer reviews through screenshots and a playtest, never the diff |
| **D3** 💰✍D | Model guard (§6.2) | A `availableModels: opus, sonnet, haiku` shared; Fable only as the engineer's personal opt-in · B no guard · C force one subagent model | **A**, plus usage credits **off** or a spend cap on both accounts (👤) | A: nothing changes. B: a Fable agent may bill or silently downgrade |
| **D4** | Workflow framework (§2) | A plain plan mode + own skills · B = A + adapted Superpowers discipline skills (MIT) · C Superpowers plugin, project-wide · D Superpowers engineer-only trial on the M1 spike · E GSD Core | **B** (D optional later) | Nothing to install. You see `/tdd-gdunit`, `/systematic-debugging` and `/verify-before-done` next to our task skills |
| **D5** ⚠ | Shared append-style files: interventions, asset credits (§3.3) | A one file per entry (`docs/interventions/…`, `docs/credits/…`; CREDITS.md generated) · B single files + `merge=union` + rebase before merge · C single files, single writer | **A** | No merge conflicts on these files, ever |
| **D6** ⚠✍D | Where machine paths live (§4.2) | A `.claude/settings.local.json` (KICKOFF §6) · B `env` in each human's `~/.claude/settings.json` · C Windows user environment | **B** | One approved edit to your user settings; it then works in every session and worktree |
| **D7** | Worktrees (§4.3) | A the runner decides: a worktree **iff** a GUI editor is open on the main checkout or another session is active; **engineer only** · B always · C never | **A** | Engineer: when your editor is open, the agent works in `.claude\worktrees\<n>`; open that folder in Rider to follow along. Designer: no change |
| **D8** ✍D | Ownership enforcement (§8.3) | A CODEOWNERS and review only · B **asymmetric guard**: designer session → *deny* on engineer paths; engineer session → *ask* on designer paths; unknown role → deny outside `docs/` · C deny rules in the designer's personal settings | **B** | Designer: engine-code edits are simply refused with "file an engine-request". Engineer: a prompt before touching content |
| **D9** ✍D | Designer ↔ own agent on scenes (§12.3) | A **runner-enforced**: before start, finish, normalize, or content changes, "Save All and close Godot"; the runner refuses while the editor has this checkout open · B an honour-system rule only · C the designer's agent works in a worktree | **A** | Designer: close Godot when the agent asks, reopen afterwards. No lost edits |
| **D10** | Pushing after a rebase (§8.4) | A the pre-push hook allows non-fast-forward pushes **only** to the task's own `<area>/<n>-*` branch, never main or deletes · B never force; after a rebase, push a new `-r2` branch and retarget the PR · C merge `origin/main` instead of rebasing ⚠ (KICKOFF §5.4 says rebase) | **A** | None visible |

### Tier 2: standing defaults (say "tier 2 OK" or veto by ID)

| ID | Default | Section |
|---|---|---|
| S1 | Instruction files: root `CLAUDE.md` ≤150 lines (counting unscoped rules) holding the **architecture invariants**; nested `CLAUDE.md` per area; path-scoped `.claude/rules`; a budget lint in `verify` | §3.1 |
| S2 | Auto memory stays on, with a guardrail rule. "Запам'ятай" gets one question back: *для проєкту (PR) чи тільки для вас?* | §3.2 |
| S3 ✍D | Each human sets `"language"` in their user settings, and personal rules in `~/.claude/CLAUDE.md` | §3.4 |
| S4 👤 | Desktop is the only surface. The PATH CLI is updated (`claude update`) or removed, so Rider cannot start 2.1.195. `doctor` fails on <2.1.281 | §4.1 |
| S5 ⚠ | Subagents: `godot-api-checker` (sonnet), `test-runner` (haiku), `code-reviewer` (**opus, not Fable**: KICKOFF says "strongest"), `netcode-security-reviewer` (opus). Routing is proven by a transcript check in M0; it **cannot be proven before the agents exist** | §6 |
| S6 ⚠ | Guards and permissions per Appendix A/C. Godot, Python, gdtoolkit, branch creation, push and board moves run **without a prompt only through the runner**. Raw forms prompt (KICKOFF §6 named the Godot exe and gdtoolkit directly). Issue comments, issue creation and PR creation are allowed without a prompt (KICKOFF said read-only gh) | §8 |
| S7 ✍D | Both humans start in **Accept edits**, set as `defaultMode` in user settings. Auto mode only after the M0 guard tests pass | §8.6 |
| S8 ⚠ | Effort: foundation stages = **effort xhigh + the `ultracode` keyword, one workflow per stage** (KICKOFF describes one uninterrupted run). Core work and runner/guard/hook tooling: high (KICKOFF puts small tooling changes at medium). Everything else: medium | §11 |
| S9 👤✍D | Board: a Project owned by the engineer and linked to the repo; the designer invited; both run `gh auth refresh -s project`; **upgrade gh to ≥2.97** (security fixes); Markdown issue templates; board moves only via the runner | §9.3 |
| S10 | Skills: start-task, finish-task, new-mechanic (a front door into the task skills), new-level-piece, log-intervention, onboard, plus the three adapted discipline skills. All model-invocable; finish-task asks one "publish now?" before its first GitHub write | §7 |
| S11 | Bot-scenario format and location are **deferred** to the pre-M2 content-API design. Until then, new-mechanic writes only the issue, GDD open questions and engine-requests | §7 |
| S12 | No Godot MCP in M0–M3. The M4 revisit prefers an in-game debug autoload plus the bot harness | §10 |

### Tier 3: agent's call during M0 (an ADR with test output for each; veto possible)

| ID | Choice | Section |
|---|---|---|
| T1 | `.gd` post-edit hook: auto-format, then lint, then engine parse check; Python, launched from Git Bash | §8.7 |
| T2 | `.tscn`/`.tres`: hand-written text, then `run normalize`, then UID lint in `check` | §12.4 |
| T3 | GDScript warnings: typing and unsafe-access rules = Error; others Warn, reported but not failing | §12.5 |
| T4 ⚠ | Runner: Python core with `tools\run.cmd` + `tools/run.sh` wrappers (KICKOFF said `.ps1`; `.cmd` avoids the execution policy) | §8.2 |
| T5 | Skill and agent frontmatter lint inside the Python runner (no Claude Code install in CI) | §7 |
| T6 | No SessionStart hook; start-task runs `doctor --quick` | §5.1 |

---

## 2. Framework (D4)

| Option | For | Against |
|---|---|---|
| **A** Plain plan mode + own skills | No dependency; comes with `git pull`; plans stay private in `~/.claude/plans`, so GitHub Issues remains the only moving state; lowest fixed cost | We write the discipline ourselves; there is no always-on bootstrap |
| **B** A + our adapted copies of Superpowers v6.4.2 `test-driven-development`, `systematic-debugging` and `verification-before-completion` (MIT notice, pinned upstream tag, rewritten for GdUnit4, PowerShell and our PR flow) | Keeps the best-validated discipline content; Windows-native; reviewed in PRs; no silent updates | Manual upstream diff each milestone; no "1% rule" auto-trigger (CLAUDE.md routing, finish-task gates and a fresh reviewer replace it) |
| **C** Superpowers plugin (the official marketplace installs **v6.4.1**) | Mature discipline; SessionStart bootstrap; very active project | Commits specs and plans to `docs/superpowers/`, which competes with Issues (KICKOFF §6), and the CLAUDE.md redirect is reported unreliable (#939); `.superpowers/` is hardcoded (#2398); up to 3 human gates per architectural task; a finish menu with local merge; Windows friction (1.3–2.3 s hook #2081, bash helpers #2307); each human installs it; `skillOverrides` cannot hide plugin skills |
| **D** Superpowers, engineer-only, local-scope trial on the M1 throwaway spike | Real data here; no designer impact | Extra spike tokens; the result goes into an ADR |
| **E** GSD Core 1.15 (the original GSD is archived) | The most complete pipeline | Needs **Node ≥24** (we have 20); `ROADMAP.md` is "the single source of truth" and `STATE.md` a live tracker, which violates KICKOFF §5; a self-described solo-developer tool; ~65 commands, 35 agents; installs about 15 hooks |

Spec Kit (Python 3.11+, uv optional) and BMAD (needs uv) keep their own planning stores. BMAD's game module
generates GDD content, which KICKOFF forbids. Neither is recommended.

**Token cost.**
- **C:** about 1.5k tokens fixed per start, `/clear` or compaction, plus 2–8k per skill invoked.
- **B:** about 0.3k always-on for descriptions, plus about 2.4k, 2.3k and 0.8k when the adapted skills are invoked.
- **The larger recurring cost in B is the fresh review at every finish** (§5.2):
  - code-reviewer on Opus at high effort;
  - the security reviewer only for `core/`, `server/` and `net/` diffs;
  - `godot-api-checker` only for `.gd`, `.tscn` and `.tres` diffs.

  Lever: for docs-only and content-data PRs, finish-task uses the bundled `/code-review` at medium or skips review.

---

## 3. Instruction files, memory and interventions

### 3.1 Layout (S1)

| File | Loaded | Content | Budget |
|---|---|---|---|
| `CLAUDE.md` (root, engineer-owned) | Always, and re-injected after compaction | Hard rules; **architecture invariants** (host authority, per-peer filtering, pure `core/`, Godot 4 only, designer never edits engine code, never claim without running); exact runner commands; PowerShell 5.1 rules (§8.2); ownership map; skill routing; definition of done; dictation glossary | **≤150 lines**, root plus every rule file without `paths:` |
| `core/ server/ net/ client/ voice/ CLAUDE.md` | When a file in that directory is read | Engineer area rules | ≤100 lines each |
| `content/ levels/ CLAUDE.md` (designer-owned) | Same | How to author mechanics and maps without engine code | ≤100 lines each |
| `.claude/rules/*.md` with `paths:` | When a matching file is touched | `gdscript.md` (`**/*.gd`), `tests.md` (`tests/**`), `godot-resources.md` (`content/**`, `levels/**`: UID and close-first rules) | ≤60 lines each |
| `docs/*.md` | Only when read | ARCHITECTURE (with the **content API**), GDD, ROADMAP, ADRs; linked, never `@imported` (imports load at startup anyway) | none |

**Invariants live in root, because nested files vanish after compaction [doc].**

When the budget lint fails, the same PR must do one of these to a rule, and the intervention entry records which:
- scope it to paths;
- move it into a skill;
- retire it.

### 3.2 Auto memory (S2)

Auto memory stays on. Root `CLAUDE.md` says: *never store shared rules or task state in auto memory; project
lessons go through `/log-intervention`; task state goes to the issue.*

"Запам'ятай / remember" gets one question: *для проєкту (PR) чи тільки для вас?*
- **Project** → `/log-intervention`.
- **Personal** → `~/.claude/CLAUDE.md`, after the human approves the edit.

The alternative is `autoMemoryEnabled: false` in shared settings.

### 3.3 Interventions and credits (D5 ⚠)

**Tested [local]:** two branches that each append a block at the end of the same file produce a git conflict. Git's
`merge=union` avoids that locally, but can silently drop identical trailing lines.

GitHub's merge button and mergeability check appear to ignore `.gitattributes` **[inferred]**. The evidence is the
open community discussion #9288 and third-party reports; it has not been tested on our repo.

`CREDITS.md`, where the designer records every imported asset, has the same problem.

- **A (rec.):** one file per entry.
  - Interventions: `docs/interventions/YYYY-MM-DD-<who>-<slug>.md`, mirroring the ADR names.
  - Credits: `docs/credits/<asset-slug>.md`. `CREDITS.md` is generated by `run credits`, and `check` verifies that
    every LFS asset has a credits file.
- **B:** single files with union, plus a rebase immediately before every merge.
- **C:** single files with a single writer (the engineer's agent).

**Flow of `/log-intervention`.** In the same PR, it writes the entry and promotes the rule to the right place. Under
D5-C, only the engineer's agent writes entries; the designer's agent files an `intervention` issue instead.
Promotion targets depend on the role:

| Session | May promote into | Otherwise |
|---|---|---|
| Designer | `content/CLAUDE.md`, `levels/CLAUDE.md`, rules scoped to `content/**` or `levels/**` | Files an `intervention` issue assigned to the engineer and links it from the entry |
| Engineer | root, nested, skills, hooks | Content-area rules need the designer's approval in the PR |

Each promoted rule gets a block-level `<!-- see docs/interventions/… -->` comment, which costs no context tokens
[doc]. A lesson that arrives outside a task first gets an `intervention` issue, then a short branch and PR.

### 3.4 Personal preferences (S3 ✍D)

- **Reply language:** `"language": "ukrainian"` in the engineer's `~/.claude/settings.json`.
- **Other personal rules:** `~/.claude/CLAUDE.md`, e.g. "Never reply in Russian".
- `language` also sets `/voice` dictation, **but `/voice` is a CLI feature, not a Desktop one [doc]**. M0 records
  which dictation tool the engineer uses in Desktop and tests it on about 10 project terms.
- Nothing personal goes in shared files.

---

## 4. Environment and surface

### 4.1 Surface and version (S4 👤)

**The Desktop Code tab is the only surface, at ≥2.1.281 on both machines.** The PATH CLI is either updated with
`claude update` (a human-approved install) or removed. `doctor` checks both versions and fails below 2.1.281.

When Desktop picks up 2.1.284+, `sonnet` becomes Sonnet 5.5 and the ultracode behaviour changes (§11). The routing
check tolerates this (§6.3).

**Desktop controls** (terminal shortcuts do not work in Desktop):

| What | How |
|---|---|
| Permission mode | `Ctrl+Shift+M` |
| Effort | `Ctrl+Shift+E` |
| Model | `Ctrl+Shift+I` |
| Side question that stays out of context | `Ctrl+;` |
| Context and plan usage | usage ring next to the model picker |
| Subagents and workflows | tasks / Background tasks pane |

`/config key=value` and `/permissions` do nothing in Desktop; the agent edits settings files instead.

### 4.2 Machine paths (D6 ⚠)

**Today:** `GODOT_BIN`, `GODOT_GUI_BIN`, `PYTHON_BIN` and `GDTOOLKIT_DIR` are in `.claude/settings.local.json`, and
new commands see them in the main checkout [local].

**Problems:**
- **On Windows, that file is read from the session's own directory [doc]**, so worktree sessions do not see the main
  checkout's copy.
- `.worktreeinclude` copies it only into worktrees that Claude Code itself creates, not into `git worktree add` ones.
- The global git-excludes line on this machine uses a backslash, so git does **not** ignore the file [local].

| Option | For | Against |
|---|---|---|
| A keep `settings.local.json` | Project-scoped | Invisible in worktrees; needs the `.gitignore` fix |
| **B (rec.)** `env` in each human's `~/.claude/settings.json` | Reaches every session, worktree, hook, subagent and workflow agent; applies at startup with no trust gate [doc] | Applies to all projects on that machine (harmless for these variables); editing it needs the human's approval |
| C Windows user environment | Reaches everything, including tools outside Claude | Set manually; Desktop restart needed |

Set each variable in **one** place (Appendix B). M0 adds `.claude/settings.local.json` to the repo `.gitignore`
regardless, because personal approvals still collect there.

### 4.3 Worktrees (D7)

Worktrees isolate parallel sessions on **one** machine. The two humans are kept apart by branches, ownership and
single-owner scenes, not by worktrees.

**A (rec.).** `run start <issue>` decides deterministically:
- **Worktree** if and only if a GUI Godot editor has this checkout open, or another Claude session is active on it.
  - The runner creates `.claude/worktrees/<n>` on branch `<area>/<issue>-<slug>` (correct naming, unlike Desktop's
    `worktree-<name>`).
  - The agent enters it with `EnterWorktree` (to be verified in M0).
  - The engineer opens that folder in Rider to follow along.
  - After the PR merges, `tools\run.cmd worktree-done <n>` removes the worktree. Archiving the session or
    `ExitWorktree` does not remove worktrees that were entered by path.
- **Designer's sessions never use worktrees.** They follow the close-first agreement instead (D9).

Costs:
- Each worktree needs one cold `--import`.
- In Desktop-created worktrees, LFS content may arrive as pointer files [doc]. Worktrees made by the runner with
  `git worktree add` do not have that problem.

B (always) and C (never) are simpler rules, but pay those costs every time, or give up the protection for the
engineer's open editor.

---

## 5. Session protocol

### 5.1 Start: "start task 42" / `/start-task 42`

1. `tools\run.cmd doctor --quick`. **Red blocks the task**, with a plain-language fix.
2. `gh issue view 42`.
3. Read the linked docs and the area's `CLAUDE.md`. Check ownership (§8.3). Check open PRs: **stop if another
   human's open PR touches a scene the task will edit** (KICKOFF §5.3).
4. `tools\run.cmd start 42` does five things:
   - refuses if the designer's editor has this checkout open (D9);
   - handles a dirty tree with two plain choices, **include in this task** or **set aside (stash)**, and never
     discards;
   - creates the branch or worktree (D7);
   - assigns the issue to the human if it is unassigned (raw `gh issue edit` prompts by design);
   - moves the board item to **In progress**.
5. **Restate** the goal, acceptance criteria, plan, verification commands and risks. For non-trivial work, use plan
   mode and wait for "go".

There is no SessionStart hook (T6): step 1 does the environment check.

### 5.2 Finish: "finish" / `/finish-task` (definition of done)

1. Run `tools\run.cmd verify` and paste the tail of the output. On red: stop and report. Never weaken a test.
2. **Fresh-context review:**
   - `code-reviewer` for code diffs; bundled `/code-review` at medium, or none, for docs-only and content-data diffs;
   - plus `netcode-security-reviewer` if `core/`, `server/` or `net/` changed;
   - plus `godot-api-checker` if `.gd`, `.tscn` or `.tres` changed.

   Findings are fixed or listed in the PR.
3. Docs are updated if durable knowledge changed; intervention and credit entries are added if any.
4. **One question:** "Publish now? (push + PR + handoff comment)". A misheard dictation cannot publish silently.
5. `tools\run.cmd publish` rebases on `origin/main`, re-runs verify, and pushes the task branch (D10).
6. Open the PR from the template:
   - `Closes #42`, summary, verification commands and output;
   - `shot` screenshots for visual changes;
   - whether docs were updated;
   - `--reviewer <other human>` when the diff touches the other owner's paths. CODEOWNERS does not auto-request on
     private Free.
7. Post the **handoff comment** on the issue (done / left / decisions / gotchas), and move the board item to
   **In review** via the runner.

### 5.3 Context hygiene

- **One issue per session.** A new issue starts a new session.
- `/clear` in three cases:
  - between unrelated tasks;
  - after two failed corrections on the same point (restart with a better prompt);
  - after a plan is approved, when the plan is enough to implement from.
- After compaction, the root rules come back on their own; the agent re-reads the area `CLAUDE.md` before editing.

---

## 6. Subagents and model routing

### 6.1 Roster (S5 ⚠)

Rules shared by all four agents:
- **No Edit, Write or NotebookEdit, and `disallowedTools: Agent`.**
- No `memory:` field: it would auto-grant Write and Edit, and commit files that both humans edit.
- `permissionMode` is not relied on: it is ignored when the main session runs in Accept edits or Auto [doc].
- Shell and WebFetch are limited by a **fail-closed** frontmatter PreToolUse hook (Appendix D).
- Their permitted runner commands write to `tools/out/` and `.godot/`. `check`'s import step can also create missing
  script `.uid` sidecars, which `check` then reports as a failure (§12.4).

| Agent | Job | Model | Alternatives |
|---|---|---|---|
| `godot-api-checker` | Check changes against the **pinned 4.7.2 API**, flag Godot 3 idioms | `sonnet` | haiku is cheaper, but its training predates Godot 4.4–4.7 |
| `test-runner` | Run test / lint / check / bots and return **only failures** | `haiku` | sonnet |
| `code-reviewer` | Review the diff against CLAUDE.md, ARCHITECTURE.md and the content API | `opus`, effort high | `fable` (D3, 💰); or the bundled `/code-review`, which follows CLAUDE.md but has no agent-specific checklist and no model pin |
| `netcode-security-reviewer` | Hunt for information leaks, unvalidated intents and host-trust assumptions | `opus`, effort high | fable |

Notes:
- Haiku 4.5 ignores `effort`. Its retirement is "not sooner than 2026-10-15" [doc], and `agents-check` raises an
  alarm if the haiku agent is served by another family.
- Requests flagged by the cybersecurity safety filter re-run on a fallback model, with a notice in the transcript
  [doc].
- A new `.claude/agents/` directory needs a session restart before it is seen.

### 6.2 Model guard (D3 💰)

**A (rec.).** Put `"availableModels": ["opus", "sonnet", "haiku"]` in the shared settings [doc].
- It applies to subagent frontmatter, Agent calls and workflow agents; a blocked model falls back with a warning.
- The lists from different settings files merge, so this is a guardrail, not enforcement.
- Fable exists only as the engineer's personal opt-in: a `~/.claude/agents/code-reviewer-deep.md` plus a local
  `availableModels` entry, called explicitly and never inside workflows.
- An `Agent(model:fable)` deny would block only the main agent passing `fable` per call. It misses frontmatter, full
  IDs and inheritance [doc], and most likely workflow stages [inferred]. It is not needed on top of
  `availableModels`.

**B:** no guard. Any agent file or workflow that names Fable can bill (if usage credits are on) or silently
downgrade.

**C:** `CLAUDE_CODE_SUBAGENT_MODEL` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` forces every subagent onto one model. That
loses the haiku/sonnet cost routing.

**👤 Account level.** Keep **usage credits off**, or set a monthly spend limit, on both accounts. This is the only hard
stop on money. Never run an ultracode session with Fable or `best` selected: every workflow agent inherits the
session model.

### 6.3 Routing verification

Every subagent's transcript `~/.claude/projects/D--prime-game/<session>/subagents/**/agent-<id>.jsonl` records the
model that **actually served** each message.

**Proven in this session [local]:** 6 agents of type `claude-code-guide` ran on `claude-haiku-4-5-20251001`, and 21
workflow agents ran on `claude-opus-5-5`.

M0 adds `tools\run.cmd agents-check`. It asserts **model family** (`claude-opus-*`, `claude-sonnet-*`,
`claude-haiku-*`), not exact IDs, so an alias re-point is not a false failure. M0 runs each custom agent once and puts
the table in the PR.

---

## 7. Skills (S10, S11, T5)

All skills live in committed `.claude/skills/<name>/SKILL.md`. There is no plugin and no install step.

| Skill | For | Does |
|---|---|---|
| `start-task`, `finish-task` | both | §5.1, §5.2 |
| `new-mechanic` | designer | **Front door for a new idea.**<br>1. Interview, then create the `mechanic` issue and any `engine-request` issues; stop for OK.<br>2. Run `start-task`.<br>3. At most two PRs: the GDD section (open questions, **no invented content**), then, **once the content API exists (M2+)**, the content data built from existing primitives.<br>4. Bot scenarios wait for S11 |
| `new-level-piece` | designer | A room or interactable sub-scene per the level conventions; `normalize` (§12.4); `shot` screenshot |
| `log-intervention` | both | §3.3 |
| `onboard` | both | §12.1 |
| `tdd-gdunit`, `systematic-debugging`, `verify-before-done` | engineer mostly | Adapted Superpowers skills (D4-B), with the full MIT notice ("Copyright (c) 2025 Jesse Vincent") and upstream tag, credited |

Rules:
- **No skill is named `doctor`, `verify` or `run`.**
- All skills are model-invocable, so a dictated "заверши задачу" works. The publish step asks once (§5.2).
- `start-task` and `finish-task` never use `context: fork`: they need the conversation.
- `allowed-tools` entries carry both Bash and PowerShell forms.
- A personal `~/.claude/skills/<same-name>` silently shadows a project skill. `doctor` warns about it.
- **T5:** `verify` lints skill and agent frontmatter with the Python runner (YAML parse, required fields, name
  rules), so CI needs no Claude Code install.

---

## 8. Guards, hooks and permissions

### 8.1 Principles

- Rules match text (§0.5), and private Free has no server enforcement (§0.7). So three layers stack, all shipped in
  every D1 option:
  1. permission rules (cheap, best-effort);
  2. the PreToolUse **guard hook** (sees each command before it runs);
  3. the git **pre-push hook** (sees every push from any tool).
- Every `Bash(...)` rule has a verbatim `PowerShell(...)` twin. Order is deny → ask → allow, first match wins.
  Settings files are **strict JSON**.
- **Risky operations run without a prompt only through the runner**, which enforces its own rules: Godot, Python and
  gdtoolkit calls, `start` (branch or worktree), `publish` (the push path), `merge` (D2-B only), `board` moves,
  `worktree-done` and `clean` (deletes in `tools/out/`). Their raw forms prompt (Appendix A).
- **Runner, guard and hook files are ask-protected** by explicit `ask` rules, so edits to them prompt even in Auto
  (Appendix A).
- Allow rules for read-only git (`status`, `diff`, `log`, `show`) are **deliberately absent**. They are already built
  in, and `Bash(git log *)` would pre-approve `--output=<file>` [local].

### 8.2 Runner entry point (T4 ⚠) and PowerShell rules

**Runner.** The core is `tools/run.py`, using the Python that gdtoolkit already requires. It has two wrappers:
- `tools\run.cmd`: `.cmd` is immune to the execution policy, and it ends with `exit /b %ERRORLEVEL%`;
- `tools/run.sh`: for Git Bash and CI.

Root `CLAUDE.md` prescribes exactly `tools\run.cmd <cmd>` in PowerShell and `tools/run.sh <cmd>` in Bash.

**PowerShell 5.1 rules for the agent** (in root `CLAUDE.md`):
- Chain commands with `; if ($LASTEXITCODE -eq 0) { … }`, never `&&`.
- Put structured arguments in files, not inline JSON or `--jq` strings.

### 8.3 Ownership enforcement (D8)

The guard reads a committed ownership map `.claude/ownership.json` **from `origin/main`** (via `git show`), so a
branch cannot widen its own rights. The map holds two things:
- roles → path globs;
- roles → GitHub handles.

`CODEOWNERS` is generated from it. Until the map exists on `origin/main` (early M0), ownership checks return **ask**,
not deny.

The guard computes paths relative to the worktree root, so edits inside `.claude/worktrees/<n>/` are checked too.

| Owner | Paths |
|---|---|
| Engineer | `core/ server/ net/ client/ voice/ tools/ tests/ addons/ .github/ .claude/{hooks,githooks,agents,workflows}/ .claude/settings.json .claude/ownership.json project.godot CLAUDE.md docs/{ARCHITECTURE,AGENT_WORKFLOW,ROADMAP}.md` |
| Designer | `content/ levels/ docs/GDD.md docs/design/ .claude/skills/{new-mechanic,new-level-piece}/` |
| Shared, no prompt | `docs/interventions/ docs/decisions/ docs/credits/ docs/history/ CREDITS.md .claude/rules/` (a rule's `paths:` must stay inside the author's own area; the guard checks this) |
| Unlisted | ask, for both |

Behaviour by session role (from `PRIME_GAME_ROLE`):

| Session | Edits the other owner's paths | Missing or unknown role |
|---|---|---|
| Designer | **Deny**: "file an `engine-request` instead" | deny outside `docs/` |
| Engineer | **Ask**; the PR must link the designer's approval | deny outside `docs/` |

`doctor` is red when the role is unset.

### 8.4 Git pre-push hook and publish (D10)

The pre-push hook is committed under `.claude/githooks/pre-push`. `doctor` sets `core.hooksPath` to the **absolute**
path of the main checkout's copy, and verifies it every session.

It blocks main, `+main` and `refs/heads/main`, all deletions (`--delete`, `-d`, `:ref`, `--prune`, `--mirror`), and
force pushes. Under **D10-A**, the one exception is a non-fast-forward update of the current task branch
`<area>/<n>-*`.

**Tested [local], git 2.49:**
- Blocked: push to main, `+main`, `--force`, `--force-with-lease`, `--delete` and `:ref`.
- Main and `--delete` were also tested from PowerShell; the rest from Git Bash only.
- Rider coverage is [inferred].
- The D10-A exception must be re-proven in M0.

The runner's `publish` never passes `--no-verify`, `-c` or `--admin`, and refuses if given them.

### 8.5 Guard hook, and what remains open

The guard (spec and test table in Appendix C) matches `Bash|PowerShell|Monitor|Edit|Write|NotebookEdit`. It is
**fail-closed**: a missing `PYTHON_BIN`, a crash, or a non-zero exit becomes exit 2. It parses arguments rather than
substrings, and handles:
- git flag abbreviations;
- case-insensitive config keys;
- `GIT_CONFIG_*` variables;
- `--output`, `--upload-pack` and `--ext-diff`;
- `$env:` assignments to protected variables;
- shell commands that write to ask-protected paths (`Copy-Item`, `Move-Item`, `Set-Content`, `Out-File`, `>`, `cp`,
  `mv` targets under `.claude/`, `tools/run*`, `tools/runner/`, `.github/`), which get **ask**;
- raw branch operations (`git switch`, `checkout`, `rebase`, `merge`, `pull`, `stash`) while a GUI Godot editor has
  this checkout open: **deny** with the close-first message (D9);
- indirection (`iex`, `cmd /c`, `bash -c`, `Start-Process`, `-EncodedCommand`), which gets **ask**.

**Remaining gaps. These are why D1 A–C still matter:**
- A hook **timeout** does not block [doc].
- An agent can write a script under `tests/` or `tools/` and run it through the runner. The guard sees only
  `tools\run.cmd test`. Runner files are ask-protected, but tests are not. **Only server-side rulesets (D1 A–C) stop a
  script from pushing to main or admin-merging.**
- Humans acting outside Claude (web UI, Rider) are not covered.
- The Desktop tool `mcp__ccd_pr__set_auto_merge` can land a PR. It is in `deny` under D2-A (Appendix A).

### 8.6 Permission mode (S7 ✍D)

Each human sets `"permissions": {"defaultMode": "acceptEdits"}` in **user** settings, so the mode survives new
folders and worktrees. It is never set in shared settings [doc].

**Auto mode** only after the M0 guard tests pass. In Auto, protected-path edits go to a classifier; the explicit
`ask` rules still force prompts.

**Prompts to expect.** M0 runs a scripted start → finish dry run for each role and counts every prompt. The target
for a normal content task is **one** designer prompt at most. The designer docs get a short "prompts you will see"
table with two rules:
- *If you don't understand a prompt, answer No and say "поясни".*
- *Never choose "don't ask again" unless the engineer said so.*

`doctor` lists local allow rules that are not in the shared settings.

### 8.7 `.gd` post-edit hook (T1)

Matcher `Edit|Write`. The hook itself filters to `*.gd` and skips `addons/` and `tools/out/`. It finds the project
root by walking up from the file. Then:
1. gdformat, then restore LF if CRs appear;
2. gdlint;
3. engine parse check via the project checker in single-file mode. It runs in `_initialize()`, so autoloads resolve;
   it has an **inner timeout of 60 s** that reports "engine check timed out".

Problems → **exit 2** with `file:line: message` on stderr, which Claude sees.

About 2 s per edit, measured on the prototype [local]. The checker **instantiates autoloads**, so autoloads must be
side-effect-free when started with `--check-mode`: no network, microphone or voice start-up. Shell-side file
changes skip the hook; `check` in `verify` covers them.

---

## 9. GitHub coordination

### 9.1 Visibility and plan (D1 💰👤✍D)

The repo does not exist yet.

| Option | Cost | Server-side enforcement |
|---|---|---|
| A Public, Free | $0 | Rulesets: block force push, restrict deletion, require PR, required checks, code-owner review. Game source and hidden-role logic become public |
| B Private, personal **Pro** | Pro price (not shown on the pricing page; unconfirmed) | Same as A |
| C Private, org **Team** | $4/user/month | Same as A |
| D Private, Free | $0 | **None**; only §8's local layers, which agent-authored scripts can bypass (§8.5) |

**In A–C:**
- Use a **ruleset on main** with: block force push, restrict deletion, require PR, and required status checks.
  Required checks are added **only after the CI PR has merged**. Before that, no check ever reports and every PR
  would wait forever (§14).
- **Code-owner review stays off.** It would force the engineer to approve every designer-only PR, because authors
  cannot approve their own. Cross-area approval is handled by D2 and §5.2 instead.
- No admin bypass, or bypass "for pull requests only". The owner is an admin, and admins bypass classic protection
  by default.

### 9.2 Merging (D2 ✍D)

**A (rec.):** only humans merge, by clicking Merge on GitHub or in the Desktop PR pane after CI is green.
- Agents: `gh pr merge` and `mcp__ccd_pr__set_auto_merge` are **denied**.
- **Cross-area PR:** the other owner approves on GitHub first.
- **The designer reviews through `shot` screenshots and a playtest**, never the diff.

**B:** the author human says "merge". The agent runs `tools\run.cmd merge <pr>`, which checks two things:
- `gh pr checks` is green;
- a cross-area PR has an APPROVED review from the other owner (handles from `ownership.json`).

Raw `gh pr merge` stays denied, so the guard itself never needs network calls.

### 9.3 Board and issues (S9 👤✍D)

1. **Setup:**
   - Both humans run `gh auth refresh -s project` (a browser flow, from the Desktop terminal panel ``Ctrl+` ``).
   - Upgrade gh to ≥2.97, for its security fixes and name-based board edits.
   - `doctor` reads scopes only via `gh auth status --active --json hosts`, and never echoes the raw status.
2. **Project:**
   - It is owned by the engineer and linked to the repo (`gh project link`).
   - The designer is invited as project **Write** collaborator **and** as repo collaborator. Project access does not
     grant repo access.
   - Built-in workflows, set once in the UI:
     - keep "closed → Done", "PR merged → Done" and "auto-close on Done";
     - set "item added → Backlog" with one auto-add `is:issue`;
     - **disable "PR linked → In progress"**, which would race finish-task.
3. **Agents only set In progress and In review, via `tools\run.cmd board move`**, which refuses Done. Done comes only
   from merging a PR with `Closes #n` into main.
4. **Issue templates** (`feature`, `mechanic`, `bug`, `engine-request`, `intervention`) are **Markdown with front
   matter**. `gh` cannot read YAML forms, so agents build issue bodies from the Markdown template and pass `--label`
   explicitly. `GH_PROMPT_DISABLED=1` is set in the shared env.

---

## 10. Godot MCP, LSP and API docs (S12)

**No Godot MCP server in M0–M3.** An ADR records a revisit at M4, against criteria: the bot harness cannot drive a
needed input or observation, or the designer's agent keeps needing live editor state.

At M4, the preferred path is **an in-game, debug-only input and inspection autoload plus the bot harness**:
reviewable and runnable in CI.

The fallback is a runtime MCP scoped to one subagent, e.g. Erodenn/godot-mcp-runtime. Note what it does:
- it edits `project.godot` (adds an autoload) and `.gitignore` during runs;
- it drives one Godot process at a time;
- it refuses to run without a display.

Why:
- **CI parity:** MCP tools cannot run in CI.
- **Multi-process needs:** the headless server Coding-Solo keeps one process at a time and uses `-d`, which hangs on
  the first runtime error.
- **Editor-plugin servers** add an addon, a localhost port and usually an eval tool. The best-featured ones are paid
  and closed.
- **Context cost is not the argument:** tool search defers MCP schemas.
- **The CLI already covers the value [local]:**
  - the parser's explicit Godot-3-removal errors;
  - `--validate-conversion-3to4`, a read-only whole-project idiom scan;
  - an exact API reference from `--dump-extension-api-with-docs` plus `--doctool`, generated by `doctor` into
    gitignored `tools/out/godot-api/4.7.2/`;
  - windowed off-screen `shot` PNGs that the agent reads back.

`godot-api-checker` sources, in order:
1. `check` output;
2. the API dump;
3. a ClassDB lookup;
4. WebFetch restricted to `docs.godotengine.org/en/4.7/`, enforced by its hook.

Never memory, never `/stable/` or `/latest/`.

- **Context7:** off; if ever used, pin `/websites/godotengine_en_4_7`.
- **GDScript LSP bridge:** revisit after M2.

---

## 11. Effort and orchestration (S8 ⚠)

| Work | How | Model |
|---|---|---|
| Foundation stages with no mid-task human input: M0 execution, the core architecture and content-API design before M2, project-wide audits | **Set effort to xhigh (`Ctrl+Shift+E`), then put `ultracode` in that one prompt.** Return to high or medium afterwards. The keyword alone keeps the session effort [doc], and from 2.1.284 ultracode no longer implies xhigh | Opus 5.5 |
| Everyday `core/ server/ net/ voice/` work, and runner, guard or hook changes | high | Opus 5.5 |
| Docs, content data, routine fixes; the designer's default | medium (Opus 5.5's default) | Opus 5.5 |

The alternative (KICKOFF-literal) is one session-wide ultracode run for all of M0. Workflows cannot take mid-run
input, so that means one huge unreviewed result, which KICKOFF itself calls a failed run.

Rules for workflow runs:
- **One workflow per stage** (design → implement → verify), with human review in between. Design runs produce
  documents first: options, an adversarial critique, ADR drafts.
- A run never decides a human-reserved item. It records the options and continues with the rest.
- Output is split into focused PRs, each with its verification. Verification is done by a **fresh** agent. `/rewind`
  does not cover workflow edits, so work goes through git.
- **Protected paths stall workflows.** Writes to `.claude/` prompt in Accept edits, and each prompt pauses the run.
  So M0's `.claude/` PRs (settings, agents, skills, hooks) are done **interactively, not as workflows**.
- **Reusable workflow scripts:** the agent copies the run's script into `.claude/workflows/<name>.js` in a PR. The
  terminal's `s` key in `/workflows` is unverified in Desktop.
- **Cost:**
  - every workflow agent counts against plan limits;
  - mechanical stages name cheaper models;
  - a new workflow is tried on a small slice first;
  - the size guideline default is medium, or small on Pro;
  - `effortLevel` is never put in shared settings.

---

## 12. The designer's agent

### 12.1 Onboarding (M0 deliverable)

**Bootstrap order.** The guard is fail-closed, so the machine must be able to run it before anything else. Three
things make that possible:
- The runner wrapper and the hook commands find Python as `PYTHON_BIN` if set, otherwise `py -3`. With neither, every
  shell and edit call is blocked.
- In that no-Python case the agent can still talk. It explains in chat how to install Python from python.org and
  Git for Windows. These are installer clicks, not code.
- **Bootstrap mode:** while `PRIME_GAME_ROLE` is unset, the guard allows only `tools\run.cmd doctor|onboard` and
  reads. `onboard` writes the user settings through the runner, after the human approves the exact content.

Missing Git Bash is the dangerous case. Hook commands then run under PowerShell, where the bash-syntax wrapper
errors with a non-2 exit, so **hooks fail open**. That is why `doctor` treats missing Git Bash as red and it is the
first checklist item.

After M0 merges, the designer opens the cloned folder in Desktop and says **"налаштуй мене" / "set me up"**. The
`onboard` skill then:
1. Runs `doctor`.
2. Fixes what it can, **after her approval**:
   - user-settings `env`, `language`, `PRIME_GAME_ROLE=designer` and `defaultMode`;
   - gdtoolkit, installed via a real Python (the Store stub does not count);
   - `git lfs install`, global;
   - `core.hooksPath`.
3. Prints a numbered checklist of **clicks only she can make**, each with a time estimate:
   - install Git for Windows (**required**: without Git Bash the hooks fail open) and Python 3.11+ (python.org
     installer);
   - install Godot 4.7.2 portable;
   - accept the repo and project invites;
   - `gh auth login` and `gh auth refresh -s project`;
   - trust the folder in Desktop;
   - check her Claude plan: on Pro, workflows are off until enabled and Fable bills;
   - set usage credits off.
4. Shows a **one-page summary for her sign-off**:
   - what she does differently (close-first, merge click);
   - which prompts she will see;
   - what can cost money on her plan.

`doctor` red blocks `start-task`.

### 12.2 What it does, by milestone

| Milestone | Designer's agent |
|---|---|
| M0–M1 | GDD skeleton open questions, `mechanic` issues, review of the content-API draft |
| M2 | First content `.tres` against the content API; `check` |
| M3 | Bot scenarios, in the format decided under S11 |
| M4 | Level pieces with `shot` screenshots; playtest: say "запусти хост і двох клієнтів" and the agent runs `run host` / `run join` |

Throughout:
- **Reads:** root `CLAUDE.md`, `content/CLAUDE.md`, `levels/CLAUDE.md`, `docs/GDD.md`, and the **content API**
  section of `docs/ARCHITECTURE.md`, which is the contract.
- **Boundary:** no engine code. Anything missing becomes an `engine-request` issue with a precise spec, and the agent
  continues with data.
- **Effort:** medium.

### 12.3 Close-first agreement (D9 ✍D)

**Rule:** before "start task", "finish", or asking for level or content changes, the designer does **Save All
(`Ctrl+Shift+S`) and closes Godot**.

**Enforcement (A):** `run start`, `run publish`, `run normalize` and any branch switch or rebase refuse while a GUI
Godot process has this checkout open. The agent relays the refusal in her language, e.g. *"Збережіть усе в Godot і
закрийте його, потім скажіть «продовжуй»"*.

This also covers the files that `start` and `publish` rewrite across the whole tree. If a reload prompt ever appears,
always choose **"Reload from disk"**. Keep the editor setting `save_on_focus_loss` off (the default).

**Gate:** M0 tests a headless run next to an open editor **before** the designer is onboarded (§15).

### 12.4 `.tscn` / `.tres` authoring (T2)

**Failures Godot does not report [local][doc: engine source]:**
- A uid that belongs to a **different** existing file is followed silently, and the next editor save makes it
  canonical. This happens with a copy-pasted template uid, or a copied `.uid` sidecar.
- Duplicate uids only produce a warning (exit 0).
- A missing script `.uid` on a fresh clone gets a new uid; references then warn "invalid UID" and fall back to their
  path.

**Plan:**
- The agent hand-writes readable text. It **never copies a uid or a `.uid` sidecar**.
- `tools\run.cmd normalize <files>` then re-saves the files in headless editor context. That is exactly what the
  designer's editor would save. The mode is undocumented but works on 4.7.2, so it is smoke-tested on every Godot
  upgrade.
- `check` fails on:
  - `UID duplicate`, `invalid UID`, `Missing .uid` and `Unrecognized UID` lines;
  - files left new or modified in `git status` after `--import`;
  - a load pass over `content/` and `levels/`;
  - a static lint that every `ext_resource` uid resolves to the same file as its `path=`.
- Known false positive: Godot #117362 (fixed only in 4.8). `main_scene` and the bus layout are referenced by `res://`
  path in `project.godot` until then.

### 12.5 Warnings policy (T3)

- **Error (2):** `untyped_declaration`, which also forces typed parameters, plus `unsafe_method_access`,
  `unsafe_property_access` and `unsafe_call_argument`. The unsafe ones catch bad calls through autoloads [local].
- **Everything else stays at Warn.** `check` reports those warnings (via `-d --ignore-error-breaks`) but does not fail.
- `inferred_declaration` stays at 0, so `var x := 5` remains fine.
- The 4.7 default already exempts `res://addons`.

---

## 13. How humans talk to the agent

- **Existing work:** "start task 42". **New idea (designer):** "нова механіка: …", which runs `new-mechanic`.
- **Issues should contain:**
  - the goal;
  - **acceptance criteria as a checklist** (e.g. "host rejects a kill intent from a dead player");
  - what is out of scope;
  - the verification you expect: screenshot, bot scenario or playtest.
- **Size words:**
  - "plan first" → plan mode, then wait;
  - "ultracode: …" → a workflow, with effort raised first (§11);
  - "just do it" → small, obvious changes only.
- **Dictation:**
  - Say the issue number and describe the thing. The agent finds the file and **reads its name back before editing**.
  - If a misheard word would change what gets built, it asks one short question.
  - The **glossary** in root `CLAUDE.md` starts empty and is built from real misrecognitions in the first week.
    Ukrainian forms only (e.g. "ґодо / годот" → Godot, "треси" → `.tres`).
- **Phrases:**
  - "запам'ятай" → the one question in §3.2;
  - "стоп" → stop and summarise;
  - "поясни" → explain the pending prompt or step.
- Human-reserved decisions (KICKOFF §0) always come as one batched question.

---

## 14. After approval

**Phase A step 5:**
- **ADRs** for every ⚠ item and every Tier 1 decision. Each carries the reasoning, the alternatives, and the key local
  test scripts and outputs, linked from the archive `docs/history/2026-09-28-phase-a/`.
- `AGENT_WORKFLOW.md` rewritten as the decided state; this file moves to `docs/history/`.
- **Personal/machine items applied**, each edit shown to the human first: the engineer's S3, S4, D6, S7 and
  `PRIME_GAME_ROLE`.

**Human actions (👤):**
- create the repo per D1;
- `gh auth refresh -s project` and the gh upgrade;
- set the usage-credit setting;
- invite the designer (repo + project);
- set up the project workflows in the UI;
- the designer's onboarding (§12.1);
- `claude update` or remove the PATH CLI;
- optionally free space on C:.

**M0 bootstrap. This happens before any guard exists:**
1. A human creates the **empty** GitHub repo, with no ruleset yet.
2. The agent runs `git init` and writes `.gitignore` with `.claude/settings.local.json`, `.claude/worktrees/`,
   `tools/out/`, and `.idea/` except shared files. The global-excludes backslash bug makes this entry essential.
3. The agent writes `.gitattributes`: LF plus LFS patterns (`addons/gdUnit4` already has 9 PNGs).
4. It checks `git check-ignore .claude/settings.local.json` and `git lfs ls-files`.
5. **One initial commit goes directly to `main`**, as KICKOFF §9.4 allows for an empty repo: KICKOFF, project files,
   the addon, the ADRs and the decided `AGENT_WORKFLOW.md`. It is pushed **before** the guard hooks are installed.
6. The humans then create the ruleset (D1 A–C): block force push, restrict deletion, require PR. Required status
   checks are added after the CI PR below has merged.
7. The rest of M0 lands as focused PRs, in this order:
   - runner + `doctor`;
   - instruction files + rules + budget lint;
   - hooks and guards (interactive);
   - settings and permissions (interactive);
   - subagents (interactive);
   - skills (interactive);
   - CI;
   - labels, milestones and the first M1 issues.

**Proofs (each by a fresh agent, not the author):**

| Piece | Proof |
|---|---|
| Hooks | Synthetic-JSON unit tests, then one live edit each |
| Guard + pre-push | The Appendix C table, run through **both** shells, including `publish` twice after a rebase |
| Permissions | A scripted check that the runner spellings and deny rules match, run on the Desktop build. It includes `$env:X='…'; tools\run.cmd check` and `$env:GIT_CONFIG_COUNT=…; git push` cases |
| Routing | `agents-check` output for all four agents |
| Prompts | The start → finish dry run per role, with the prompt count |
| Leak test and CI | Test-the-tests (KICKOFF §4): inject a leak and a failing commit, see red, revert |

---

## 15. Open risks and questions

- **Designer machine unknown:** Claude Code version, plan, Python, Node, gh.
- **Guard timeouts fail open.** The guard must stay fast (no network, no `gh` calls); only the editor-process check
  costs about 1 s, and only on branch commands.
- **Missing Git Bash makes every hook fail open** (hooks fall back to PowerShell). `doctor` treats it as red.
- **Headless Godot next to an open editor:** it writes `.godot/` and the shared `%APPDATA%\Godot\editor_settings-4.7.tres`
  [local]. Interference is [inferred]; it is tested in M0 before the designer is onboarded.
- **`shot` needs a GPU desktop:** it is local-only, and CI `verify` skips it.
- **Tooling issues:**
  - gdtoolkit 4.5.0 has had no commits since 2025-10 and has open formatter bugs. The engine re-check in T1 catches
    them.
  - GdUnit4's summary line can say PASSED on a failure (#1330). We trust exit codes and `results.xml`.
  - GdUnit4 officially lists support up to 4.7.1; 4.7.2 works locally.
- **Git LFS in CI** consumes LFS bandwidth quota (💰; ask before enabling it).
- **Claude Code releases almost daily** (2.1.284 today). Version-gated items are re-checked when the Desktop build
  changes. `/doctor prompt-audit` (≥2.1.283) can audit these files once available.

---

## Appendix A — Draft shared `.claude/settings.json` (PROPOSAL; strict JSON)

Only the Bash forms are shown. **The committed file repeats every `Bash(...)` rule as `PowerShell(...)`**, and the M0
permission test fails if a twin is missing. The runner's PowerShell forms are `PowerShell(tools\\run.cmd *)` and
`PowerShell(.\\tools\\run.cmd *)`. Under D2-B, move `Bash(gh pr merge *)` from deny to ask.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": { "GH_PROMPT_DISABLED": "1" },
  "availableModels": ["opus", "sonnet", "haiku"],
  "permissions": {
    "allow": [
      "Bash(tools/run.sh *)", "Bash(./tools/run.sh *)",
      "Bash(git fetch origin)", "Bash(git fetch origin main)", "Bash(git fetch --prune origin)",
      "Bash(git add *)", "Bash(git commit *)",
      "Bash(gh issue view *)", "Bash(gh issue list *)", "Bash(gh issue comment *)", "Bash(gh issue create *)",
      "Bash(gh pr view *)", "Bash(gh pr list *)", "Bash(gh pr checks *)", "Bash(gh pr diff *)", "Bash(gh pr create *)",
      "Bash(gh run list *)", "Bash(gh run view *)", "Bash(gh label list *)",
      "Bash(gh auth status --active --json *)",
      "WebFetch(domain:docs.godotengine.org)", "WebFetch(domain:code.claude.com)",
      "WebFetch(domain:docs.github.com)", "WebFetch(domain:git-scm.com)"
    ],
    "ask": [
      "Edit(**/.claude/hooks/**)", "Edit(**/.claude/githooks/**)", "Edit(**/.claude/settings.json)",
      "Edit(**/.claude/settings.local.json)", "Edit(**/.claude/agents/**)", "Edit(**/.claude/skills/**)",
      "Edit(**/.claude/ownership.json)", "Edit(**/.github/**)", "Edit(**/addons/**)", "Edit(**/tools/run*)",
      "Edit(**/tools/runner/**)",
      "Bash(git push *)", "Bash(git switch *)", "Bash(git checkout *)", "Bash(git restore *)",
      "Bash(git reset *)", "Bash(git clean *)", "Bash(git stash drop*)", "Bash(git stash clear*)",
      "Bash(git branch -d *)", "Bash(git worktree *)", "Bash(git rebase *)", "Bash(git -c *)",
      "Bash(rm *-*r*)", "Bash(rm *-*R*)", "Bash(rm *--recursive*)", "PowerShell(Remove-Item *)",
      "Bash(gh * -R *)", "Bash(gh * --repo*)",
      "Bash(gh issue comment * --delete-last*)", "Bash(gh issue comment * --edit-last*)",
      "Bash(gh issue edit *)", "Bash(gh issue close *)", "Bash(gh issue delete *)",
      "Bash(gh pr close *)", "Bash(gh pr edit *)", "Bash(gh pr review *)",
      "Bash(gh api *)", "Bash(gh workflow *)", "Bash(gh release *)", "Bash(gh repo *)",
      "Bash(gh project *)", "Bash(gh secret *)", "Bash(gh variable *)", "Bash(gh ruleset *)"
    ],
    "deny": [
      "Bash(git push --force*)", "Bash(git push -f*)", "Bash(git push * --force*)", "Bash(git push * -f)",
      "Bash(git push * -f *)", "Bash(git push * +*)", "Bash(git push * main)", "Bash(git push * main *)",
      "Bash(git push *refs/heads/main*)", "Bash(git push *:main)", "Bash(git push *--no-veri*)",
      "Bash(git push *--dele*)", "Bash(git push * -d *)", "Bash(git push *--prune*)", "Bash(git push *--mirr*)",
      "Bash(git push *--all*)", "Bash(git branch -D *)",
      "Bash(git config *hooksPath*)", "Bash(git config *hookspath*)", "Bash(git config --unset*)",
      "Bash(git * --upload-pack*)", "Bash(git * --output*)",
      "Bash(gh pr merge *)", "mcp__ccd_pr__set_auto_merge",
      "Bash(gh repo delete *)", "Bash(gh auth token*)", "Bash(gh auth status *-t*)", "Bash(gh auth status *--show-token*)"
    ]
  },
  "hooks": {
    "PreToolUse": [{ "matcher": "Bash|PowerShell|Monitor|Edit|Write|NotebookEdit", "hooks": [{
      "type": "command", "timeout": 30,
      "command": "PY=\"${PYTHON_BIN:-$(command -v py)}\"; [ -n \"$PY\" ] || { echo 'guard: no Python - install Python 3.11+, then run doctor' >&2; exit 2; }; if [ -n \"$PYTHON_BIN\" ]; then \"$PY\" \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.py\"; else \"$PY\" -3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.py\"; fi || exit 2" }] }],
    "PostToolUse": [{ "matcher": "Edit|Write", "hooks": [{
      "type": "command", "timeout": 120, "statusMessage": "GDScript: format, lint, parse check",
      "command": "PY=\"${PYTHON_BIN:-$(command -v py)}\"; [ -n \"$PY\" ] || { echo 'gd hook: no Python' >&2; exit 2; }; if [ -n \"$PYTHON_BIN\" ]; then \"$PY\" \"$CLAUDE_PROJECT_DIR/.claude/hooks/gd_post_edit.py\"; else \"$PY\" -3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/gd_post_edit.py\"; fi || exit 2" }] }]
  }
}
```

Notes:
- Raw `git push`, branch switches and board edits prompt by design. The routine path is `run start`, `run publish`
  and `run board`.
- Read-only git (`status`, `diff`, `log`, `show`) has no allow rule, because it is built in (§8.1).
- The guard adds the checks that text rules cannot express (Appendix C).
- With no Python at all, the guard blocks every shell and edit call. That is fail-closed by intent. The agent explains
  the Python install in chat, and bootstrap mode (§12.1) takes over once Python exists.

## Appendix B — Personal user settings (per human, outside the repo; PROPOSAL)

```json
{
  "language": "ukrainian",
  "permissions": { "defaultMode": "acceptEdits" },
  "env": {
    "GODOT_BIN": "D:\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64_console.exe",
    "GODOT_GUI_BIN": "D:\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64.exe",
    "PYTHON_BIN": "C:\\Users\\xperi\\AppData\\Local\\Programs\\Python\\Python314\\python.exe",
    "GDTOOLKIT_DIR": "C:\\Users\\xperi\\AppData\\Local\\Programs\\Python\\Python314\\Scripts",
    "PRIME_GAME_ROLE": "engineer"
  }
}
```

This is the engineer's `~/.claude/settings.json`. The designer's uses her own paths, language and `"designer"`.
`~/.claude/CLAUDE.md` holds personal rules only.

## Appendix C — Guard hook specification (PROPOSAL)

**Input:** the PreToolUse JSON on stdin, read as UTF-8 bytes. For shell tools: `tool_input.command`, split with
shlex-style rules. PowerShell handling includes `&`, `--%` and `git.exe`.

**Output:** exit 2 with a one-line reason for a deny; JSON `permissionDecision: "ask"` with exit 0 for an ask. Any
internal error exits 2.

`doctor` asserts that Git Bash prints nothing when started non-interactively (`bash -c true`). Echoes from a shell
profile would corrupt the guard's JSON, and a corrupted "ask" is silently ignored [doc].

| Case | Decision |
|---|---|
| `git push` targeting main in any form (`main`, `HEAD:main`, `refs/heads/main`, `+main`) | deny |
| Push with delete in any form (`--delete` or a prefix of it, `-d`, `:ref`, `--prune`, `--mirror`, `--all`) | deny |
| Push with `--force` / `-f` / `--force-with-lease` / `+ref` | deny (the runner's `publish` is the only path, under D10) |
| `--no-verify` or any prefix down to `--no-veri`; `-c core.hookspath` in any case; `GIT_CONFIG_*` in env or `$env:` | deny |
| `git config … core.hooksPath` or `--unset` | deny |
| `--output`, `--ext-diff`, `--textconv`, `--upload-pack`, `-u` on fetch/pull/clone, `--receive-pack`, `--exec` | deny |
| `gh pr merge` (D2-A), `gh … --admin`, `gh api` with DELETE, `gh auth token`, `gh auth status -t` | deny |
| `gh … --body-file <path>` outside `tools/out/` or the session scratchpad | ask |
| Recursive `rm` / `Remove-Item -Recurse` (any flag order), or any target outside `tools/out/` | ask |
| `$env:` / `Set-Item env:` assignments to `PYTHON_BIN`, `GODOT_BIN`, `GDTOOLKIT_DIR`, `PRIME_GAME_ROLE`, `GIT_*` | ask |
| Indirection: `iex`, `Invoke-Expression`, `Start-Process`, `cmd /c`, `bash -c`, `sh -c`, `-EncodedCommand` | ask |
| Shell writes (`Copy-Item`, `Move-Item`, `Set-Content`, `Out-File`, `>`, `cp`, `mv`) targeting `.claude/`, `tools/run*`, `tools/runner/`, `.github/` | ask |
| `git switch`, `checkout`, `rebase`, `merge`, `pull`, `stash` while a GUI Godot editor has this checkout open | deny, with the close-first message (D9) |
| Edit/Write on the **other owner's** paths (§8.3), checked relative to the worktree root | designer: deny · engineer: ask |
| Edit/Write on shared paths · on unlisted paths | no prompt · ask |
| Role unset (bootstrap mode, §12.1) | allow only `tools\run.cmd doctor\|onboard` and reads; deny other edits outside `docs/` |
| `ownership.json` not yet on `origin/main` | ownership checks return ask |

**M0 test table.** Every row above is run as a positive and a negative case, in Git Bash **and** PowerShell. Extra
cases:
- a normal feature commit;
- `run publish` twice after a rebase;
- edits under `.claude/worktrees/<n>/`;
- `git log --output=.claude/hooks/x`;
- `git fetch --upload-pack=…`.

## Appendix D — Subagent frontmatter draft (PROPOSAL)

```yaml
---
name: godot-api-checker
description: Use after editing .gd/.tscn/.tres files and before opening a PR. Verifies against the pinned Godot 4.7.2 API using engine-generated references (never memory) and flags Godot 3 idioms. Never edits files.
model: sonnet
tools: Read, Grep, Glob, Bash, PowerShell, WebFetch
disallowedTools: Edit, Write, NotebookEdit, Agent
hooks:
  PreToolUse:
    - matcher: "Bash|PowerShell|Monitor|WebFetch"
      hooks:
        - type: command
          timeout: 30
          command: "[ -n \"$PYTHON_BIN\" ] || exit 2; \"$PYTHON_BIN\" \"$CLAUDE_PROJECT_DIR/.claude/hooks/agent_guard.py\" godot-api-checker || exit 2"
---
```

`agent_guard.py` allowlists exact argument shapes: `tools/run.* check|api|api-ref|convert-check`, and WebFetch only to
`docs.godotengine.org/en/4.7/…`. It rejects everything else.

The other three agents follow the same pattern:

| Agent | model | effort | Tools | Allowlisted commands |
|---|---|---|---|---|
| `test-runner` | haiku | — | Bash, PowerShell, Read | runner `test \| lint \| check \| bots` |
| `code-reviewer` | opus | high | Read, Grep, Glob, Bash, PowerShell | `git diff \| log \| show` without output flags |
| `netcode-security-reviewer` | opus | high | Read, Grep, Glob, Bash, PowerShell | `git diff \| log \| show` without output flags, plus runner `bots` |

M0 validates all agent files with the T5 lint.

## Appendix E — Root `CLAUDE.md` outline (≤150 lines, PROPOSAL)

1. What this repo is (3 lines)
2. Hard rules (KICKOFF §0)
3. Architecture invariants (KICKOFF §3, condensed)
4. Commands (exact runner spellings)
5. PowerShell 5.1 rules
6. Ownership map pointer
7. Skill routing table
8. Session protocol pointer (decided `AGENT_WORKFLOW.md` sections)
9. Definition of done
10. Stop-and-ask list
11. Memory guardrail
12. Dictation glossary

## Appendix F — Key sources (fetched 2026-09-28)

- **Claude Code docs:** memory, sub-agents, skills, hooks, permissions, permission-modes, settings /
  settings-reference, model-config, workflows, worktrees, desktop, code-review, context-window, voice-dictation,
  changelog (2.1.281–2.1.284) — `https://code.claude.com/docs/en/<page>`
- **Superpowers:** https://github.com/obra/superpowers (v6.4.2; official marketplace pins v6.4.1; issues #939, #2081,
  #2307, #2398)
- **GSD Core:** https://github.com/open-gsd/gsd-core (the original gsd-build/get-shit-done is archived)
- **Godot 4.7:** https://docs.godotengine.org/en/4.7/ (command line, ProjectSettings, TSCN format, the 4.7 migration
  guide); engine source at `4.7.2-stable` (EditorFileSystem, EditorNode, resource_format_text); issue #117362
- **gdtoolkit:** https://github.com/Scony/godot-gdscript-toolkit (#414, #424, #428)
- **GdUnit4:** https://github.com/godot-gdunit-labs/gdUnit4 (v6.2.1, #1330)
- **Godot MCP survey:** Coding-Solo/godot-mcp, ee0pdt/Godot-MCP, gdaimcp.com, youichi-uda/godot-mcp-pro,
  tugcantopaloglu/godot-mcp, hybridindie/godot-mcp, Erodenn/godot-mcp-runtime
- **GitHub:** plans, protected branches, rulesets, code owners, Projects built-in automations, issue templates;
  community discussion #9288; cli/cli#5865; gh v2.97.0 security advisories
- **Claude plans:** https://support.claude.com/en/articles/15424964 (Fable on plans),
  https://support.claude.com/en/articles/12429409 (usage credits)
