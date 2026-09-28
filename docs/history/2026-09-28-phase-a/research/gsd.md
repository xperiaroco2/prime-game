# GSD (Get Shit Done) framework and other alternatives

## Summary

GSD has moved. The original gsd-build/get-shit-done repo (64k stars) was archived on 2026-06-26. The old npm package `get-shit-done-cc` is deprecated. The project now continues as GSD Core: repo open-gsd/gsd-core, npm package @opengsd/gsd-core, v1.15.0 released 2026-09-26, MIT. It is very active: a release every 1-2 weeks and about 90 commits in the last 7 days. It has also grown very large: about 65 `/gsd-*` commands, 33 subagents, a CHANGELOG of about 920 KB, and single workflow prompts of about 90 KB.

For this project it has four blocking or near-blocking problems:
1. **Node version.** It needs Node >= 24 (`engines`, since v1.11.0). This machine has Node 20.19.5, so installing it means changing the Node version on both humans' machines.
2. **Solo-developer tool.** Its CONTRIBUTING.md calls it a solo-developer tool and lists "conflicts with GSD's solo-developer focus" as a reason to reject features.
3. **Competing source of truth.** Its `.planning/` directory is its own source of truth. ROADMAP.md is described as "the single source of truth for what the project is building", and STATE.md is a "living position tracker" updated after every significant action. That directly contradicts the KICKOFF rule that GitHub Issues holds all moving state. GSD never reads from or writes to GitHub Issues on its own. The issue URL is only pasted by hand into CONTEXT.md.
4. **No merge story for STATE.md.** Its only concurrency guard is a lock inside one working tree. Nothing handles merging STATE.md between two clones.

You can make GSD's planning private per human (commit_docs=false plus a gitignored `.planning/`), but that costs you its parallel worktree executors and /gsd-undo.

The other options:
- **Spec Kit** (github/spec-kit v1.0.12) and **BMAD Method** (v6.12.0) are real and current. Both need Python and uv, which this machine does not have on PATH. Spec Kit's issue export needs the GitHub MCP tools rather than the `gh` CLI. BMAD has a Game Dev Studio module with first-class Godot support.
- **Anthropic's official marketplace** (claude-plugins-official, added automatically) lists feature-dev, code-review and pr-review-toolkit. It also lists Superpowers, pinned to a commit. Claude Code already has a built-in `/code-review` skill, so the code-review plugin overlaps with it.
- **Plain plan mode plus committed project skills** needs no new dependencies. Plan files go to `~/.claude/plans` by default, so they stay private to each machine and never compete with GitHub Issues.

Recommendation: reject GSD for this project. Choose between plain plan mode plus our own skills (my pick) and Superpowers (the fallback, researched separately).

## Facts (with verification)

- **gsd-01** [confirmed] The original repo gsd-build/get-shit-done ("by TÂCHES", 64.4k stars, MIT) was archived by the owner on Jun 26, 2026 and is read-only (GitHub API: archived=true, last push 2026-05-31). Active development continues as GSD Core in open-gsd/gsd-core.  
  src: https://github.com/gsd-build/get-shit-done (repo)
- **gsd-02** [confirmed] The npm package get-shit-done-cc is deprecated ("Package no longer supported"). Its last latest version is 1.42.3. It was renamed to @opengsd/gsd-core (issue #607) and the version counter restarted at 1.2.0.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/cleanup-get-shit-done-cc.md (official-docs)
- **gsd-03** [confirmed] Current GSD Core release is v1.15.0 (2026-09-26), npm dist-tag latest=1.15.0. Recent cadence: v1.9.0 07-31, v1.10.0 08-08, v1.11.0 08-19, v1.12.0 08-30, v1.13.0 09-06, v1.14.0 09-14, v1.15.0 09-26.  
  src: https://github.com/open-gsd/gsd-core/releases (changelog)
- **gsd-04** [corrected] open-gsd/gsd-core: created 2026-05-22, default branch `next`, 9.9k stars, 711 forks, 184 open issues. Top contributors are trek-e (3,727 commits) and glittercowboy (945). There were about 90 commits on `next` between 2026-09-21 and 2026-09-28.  
  src: https://github.com/open-gsd/gsd-core (repo)
  - CORRECTED: open-gsd/gsd-core: created 2026-05-22, default branch `next`, 9,917 stars, 711 forks. The '184 open issues' is the API open_issues_count, which includes PRs; the real split is 154 open issues and 30 open PRs. Top contributors: trek-e 3,727 and glittercowboy 945. There were exactly 90 commits on `next` from 2026-09-21 to 2026-09-28.
  - note: Checked with gh api repos/open-gsd/gsd-core, the search/issues counts, /contributors and /commits?sha=next&since=...
  - evidence: https://github.com/open-gsd/gsd-core
- **gsd-05** [confirmed] @opengsd/gsd-core package.json declares engines node >=24.0.0 and npm >=10.0.0. CHANGELOG 1.11.0 (2026-08-19) says "GSD now requires Node 24 or newer". The install how-to still says "Node.js 18+" (the docs are inconsistent). I found no runtime Node-version check in bin/install.js.  
  src: https://github.com/open-gsd/gsd-core/blob/next/CHANGELOG.md (changelog)
- **gsd-06** [corrected] Install commands: interactive `npx @opengsd/gsd-core@latest`; Claude Code global `npx @opengsd/gsd-core@latest --claude --global`; project-local `npx @opengsd/gsd-core@latest --claude --local`. Optional flags: `--minimal` (aliases `--core-only`, `--profile=core`), `--profile=standard|full`, `--relative-includes` (local installs across git worktrees), `--portable-hooks`, `--dry-run`. A native plugin path also exists (`claude plugin install gsd-core`, commands namespaced `/gsd-core:<command>`).  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/install-on-your-runtime.md (official-docs)
  - CORRECTED: The npx commands and flags are correct: --claude --global/--local, --minimal = --core-only = --profile=core, --profile=standard|full (composable, e.g. core,audit), --relative-includes, --portable-hooks and --dry-run. The native plugin path is weaker than stated. The doc labels `claude plugin install gsd-core` as 'marketplace or git install (once listed)', so it is not in any Anthropic marketplace. It still needs the npm package's `gsd-tools` on PATH. Install-time config such as model_overrides and agent_tools is never applied on that path. Commands are namespaced /gsd-core:<command>.
  - evidence: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/install-on-your-runtime.md
- **gsd-07** [corrected] A local Claude install writes into the project's ./.claude/: commands/gsd/*.md, agents/gsd-*.md, hooks/ and the gsd-core/ engine. It registers GSD hooks in .claude/settings.local.json (not the shared settings.json, per #338) and sets worktree.baseRef:"head" there. Its @-includes are absolute paths unless you pass --relative-includes.  
  src: https://github.com/open-gsd/gsd-core/blob/next/bin/install.js (repo)
  - CORRECTED: A local Claude install writes FLAT `.claude/commands/gsd-<name>.md` files; `commands/gsd/` is the legacy pre-#1367 layout, which the installer removes. It also writes `.claude/agents/gsd-*.md`, `.claude/hooks/` and `.claude/gsd-core/`. Global installs use `skills/gsd-*/SKILL.md` instead. Hooks go into .claude/settings.local.json (#338, localInstallStyle 'legacy-flat'). worktree.baseRef:'head' is set there only when no baseRef exists in either settings file (#683). @-includes are absolute unless you pass --relative-includes. If settings.local.json cannot be parsed (for example it contains comments), the installer skips hook registration.
  - evidence: https://github.com/open-gsd/gsd-core/blob/next/capabilities/claude/capability.json
- **gsd-08** [confirmed] Commands use the hyphen form `/gsd-<name>` on Claude Code (the legacy form was `/gsd:<name>`). The core loop is /gsd-new-project, /gsd-onboard, /gsd-discuss-phase N, /gsd-plan-phase N, /gsd-execute-phase N, /gsd-verify-work N and /gsd-ship N. Also /gsd-quick, /gsd-autonomous, /gsd-manager, /gsd-progress, /gsd-pause-work, /gsd-resume-work, /gsd-workstreams, /gsd-workspace and /gsd-pr-branch. There are about 65 documented commands and 6 namespace routers (/gsd-workflow, /gsd-project, /gsd-quality, /gsd-context, /gsd-manage, /gsd-ideate).  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/COMMANDS.md (official-docs)
- **gsd-09** [confirmed] .planning/ holds PROJECT.md, ROADMAP.md, REQUIREMENTS.md, STATE.md, config.json, optional BACKLOG.md/LEARNINGS.md/DECISIONS-INDEX.md, a transient HANDOFF.json, and phases/<NN>-<slug>/ containing CONTEXT, DISCUSSION-LOG, RESEARCH, VALIDATION, PATTERNS, <NN>-<PP>-PLAN, <NN>-<PP>-SUMMARY, VERIFICATION and UAT .md files. The docs call ROADMAP.md "The single source of truth for what the project is building and in what order". STATE.md is a "Living position tracker" that is "Updated after every significant action".  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/reference/planning-artifacts.md (official-docs)
- **gsd-10** [confirmed] planning.commit_docs defaults to true, so .planning/ is committed. To keep it private: `gsd-tools config-set planning.commit_docs false`, add `.planning/` to .gitignore, and `git rm -r --cached .planning/`. The docs say this breaks parallel executor worktrees and /gsd-undo. The alternative is to keep commits and set `planning.pr_strict true`, then run `/gsd-pr-branch`, which creates `<branch>-pr` with no .planning/ paths; you push that branch instead.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/keep-planning-docs-private.md (official-docs)
- **gsd-11** [confirmed] GSD has no built-in tracker integration. Quotes: "GSD does not poll GitHub or Linear" and "GSD never opens, comments on, or closes a tracker issue without an explicit user-initiated command". The tracker issue URL is a human input pasted into the phase CONTEXT.md, and each issue is mapped by hand onto a ROADMAP.md phase (/gsd-phase or /gsd-phase --insert).  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/issue-driven-orchestration.md (official-docs)
- **gsd-12** [confirmed] Syncing GitHub Projects exists only as an external third-party capability (The-Artificer-of-Ciphers-LLC/projects-sync-capability, ADR-1244) that mirrors GSD state out to a GitHub Project. A task-level v2 mirror is an open proposal (#2763).  
  src: https://github.com/open-gsd/gsd-core/issues/2763 (issue)
- **gsd-13** [confirmed] GSD CONTRIBUTING.md calls GSD "a solo-developer tool maintained by a small team" and lists "feature conflicts with GSD's solo-developer focus" as a rejection reason. The feature-request template requires "the solo-developer problem being solved".  
  src: https://github.com/open-gsd/gsd-core/blob/next/CONTRIBUTING.md (repo)
- **gsd-14** [confirmed] STATE.md concurrency protection is a .planning/milestone.lock keyed by phase + session id, for parallel phases in the same working tree (CHANGELOG 1.11.0). No git merge driver for STATE.md is documented; the only documented union merge driver is for graphify's graph.json. Per-session, role-keyed pause/handoff records are still an open proposal (#4845).  
  src: https://github.com/open-gsd/gsd-core/issues/4845 (issue)
- **gsd-15** [confirmed] Workstreams (`/gsd-workstreams create|switch|progress|complete <name>`) give each area its own .planning/workstreams/<name>/ with STATE.md, ROADMAP.md, REQUIREMENTS.md and phases/. PROJECT.md, config.json and codebase/ stay shared. The active workstream is scoped to the session.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/work-in-parallel-with-workstreams.md (official-docs)
- **gsd-16** [confirmed] `/gsd-workspace --new --name <slug> --repos . --strategy worktree` creates ~/gsd-workspaces/<slug>/ with an independent .planning/ and a git worktree on branch workspace/<slug> (override with --branch).  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/isolate-work-with-workspaces.md (official-docs)
- **gsd-17** [corrected] Orchestration: heavy work runs in fresh-context subagents ("each executor starts with a clean 200k-token context"). Defaults: the plan-check loop runs up to 3 iterations, parallelization.enabled=true, max_concurrent_agents=3, and workflow.research/plan_check/verifier are all true. 33 agents ship, including gsd-planner, gsd-executor, gsd-phase-researcher, gsd-plan-checker, gsd-verifier and gsd-code-reviewer.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/CONFIGURATION.md (official-docs)
  - CORRECTED: The defaults are as stated: plan_check up to 3 iterations, parallelization.enabled=true, max_concurrent_agents=3, and research/plan_check/verifier all true. The README says 'each executor starts with a clean 200k-token context'. But `next` ships 35 agents, not 33 (agents/ holds 35 unique gsd-*.md plus 29 .compact.md siblings). AGENTS.md contradicts itself, saying both '34 shipped agents total' and 'authoritative 35-agent roster'. With parallelization on, executors commit with --no-verify.
  - evidence: https://github.com/open-gsd/gsd-core/blob/next/docs/AGENTS.md
- **gsd-18** [confirmed] Model profiles: quality, balanced (default; Opus planner, Sonnet executor/researchers/verifier), budget (Sonnet/Haiku), adaptive, and inherit. Per-agent `model_overrides` and a per-phase-type `models` block are available. On Claude Code, /gsd-plan-phase, /gsd-execute-phase and /gsd-autonomous declare `effort: max` in their frontmatter.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/configure-model-profiles.md (official-docs)
- **gsd-19** [corrected] Measured file sizes on `next`: gsd-core/workflows/plan-phase.md 96,328 bytes, execute-phase.md 91,289 bytes, new-project.md 49,932 bytes, verify-work.md 45,045 bytes. Each of agents/gsd-executor.md, gsd-planner.md, gsd-plan-checker.md, gsd-verifier.md and gsd-phase-researcher.md is about 46.5 KB. At chars/4 that is roughly 23-24k tokens per heavy workflow and about 11-12k tokens per agent prompt, before any project context (my estimate).  
  src: local-test: gh api "repos/open-gsd/gsd-core/contents/gsd-core/workflows?ref=next" and ".../contents/agents?ref=next" (size field) (local-test)
  - CORRECTED: All the byte sizes are exact on `next`: plan-phase.md 96,328, execute-phase.md 91,289, new-project.md 49,932, verify-work.md 45,045; executor 46,756, planner 46,743, plan-checker 46,561, verifier 46,741, phase-researcher 46,244. The token estimate is a lower bound, though. With the default workflow.compact_content=false, the spine reads its detail/elaboration.md back in: +12,295 bytes for plan-phase and +8,461 for execute-phase. There are also lazily-read steps/ files (plan-phase 40,631 bytes in 10 files, execute-phase 193,765 bytes in 21 files) and @-included references such as ui-brand.md. Setting workflow.compact_content=true skips the elaboration read-back.
  - evidence: https://github.com/open-gsd/gsd-core/tree/next/gsd-core/workflows
- **gsd-20** [confirmed] `--minimal` installs only 8 skills (new-project, discuss-phase, plan-phase, execute-phase, phase, help, update, surface) and no sub-agents. The docs put cold-start skill-description cost at about 130 tokens, versus about 700 for `standard` and about 1,200 for `full` (the default).  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/install-minimal-and-add-skills.md (official-docs)
- **gsd-21** [confirmed] On Claude Code, GSD registers these hooks: SessionStart (gsd-check-update.js, gsd-session-state.sh); PostToolUse (gsd-context-monitor.js, gsd-read-injection-scanner.js, gsd-phase-boundary.sh, gsd-graphify-update.sh); PreToolUse (gsd-prompt-guard.js, gsd-read-guard.js, gsd-workflow-guard.js, gsd-worktree-path-guard.js, gsd-agent-isolation-guard.js, gsd-secret-read-guard.js, gsd-validate-commit.sh); plus SubagentStop, Stop and PreCompact (context monitor) and FileChanged (config.json).  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/install-on-your-runtime.md (official-docs)
- **gsd-22** [corrected] Since v1.4.0 the installer pre-populates Claude Code permissions.allow/deny with GSD patterns, for example Bash(npx gsd-core *), Read(.planning/*), Write(.planning/*), Read(STATE.md), Write(STATE.md).  
  src: https://github.com/open-gsd/gsd-core/blob/next/CHANGELOG.md (changelog)
  - CORRECTED: The v1.4.0 changelog did add Bash(npx gsd-core *), Read(.planning/*), Write(.planning/*), Read(STATE.md), Write(STATE.md) plus deny rules Read(.env), Read(.env.*), Read(.secrets). The current installer differs. It writes `Edit(.planning/*)` and `Edit(STATE.md)` (#2278: Write(...) never matched anything) and deletes the legacy Write forms. Under #4221 it also REMOVES the three Read() deny rules, 'a user's own hand-written identical rule ... is removed too'. The merge is otherwise additive.
  - evidence: https://github.com/open-gsd/gsd-core/blob/next/bin/install.js
- **gsd-23** [confirmed] GSD generates a CLAUDE.md at `claude_md_path`, default ./.claude/CLAUDE.md, with managed sections embedded between GSD markers (claude_md_assembly.mode embed|link).  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/CONFIGURATION.md (official-docs)
- **gsd-24** [confirmed] Git keys: git.branching_strategy none|phase|milestone (default none); git.phase_branch_template default `gsd/phase-{phase}-{slug}`; git.create_tag default true (creates a `v[X.Y]` tag on milestone completion); git.allow_default_branch_commits default false. Executors commit each task atomically.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/CONFIGURATION.md (official-docs)
- **gsd-25** [confirmed] Windows: the GSD CI test.yml has a windows-latest conformance lane (3 shards). Recent changelogs fix many Windows bugs: CRLF STATE.md/PLAN.md frontmatter parsing, UTF-8 BOM frontmatter written by PowerShell, .cmd shim spawning, project paths with spaces, and taskkill process trees. Open Windows issues as of 2026-09-28 include #4838 (hook commands pin a versioned node.exe path that breaks after a Node upgrade), #5082 (runHook 'bash' resolves to WSL bash when run from PowerShell, in tests) and #5084.  
  src: https://github.com/open-gsd/gsd-core/issues/4838 (issue)
- **gsd-26** [confirmed] A BETA, default-off 'Claude orchestration backend' can run execute-phase waves through Claude Code's Workflow tool (/effort ultracode). Enable it with `gsd-tools query config-set claude_orchestration.enabled true`. It needs the full profile and fails closed to inline execution.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/enable-claude-orchestration-workflow-backend.md (official-docs)
- **gsd-27** [confirmed] Historical token-overhead bugs in the legacy repo, now closed: #2548 ("discuss-phase: SKILL.md @file imports waste ~13k tokens on every invocation regardless of mode"), #2196 ("gsd-autonomous complains of too many input tokens"), #2895 ("GSD burns tokens while updating itself").  
  src: https://github.com/gsd-build/get-shit-done/issues/2548 (issue)
- **alt-01** [corrected] GitHub Spec Kit: github/spec-kit v1.0.12 (2026-09-25), about 139k stars, MIT. Install with `uv tool install specify-cli`, then `specify init <project> --integration claude`. It needs Python 3.11+ and uv. Windows PowerShell scripts are supported without WSL, and the Claude integration installs skills into .claude/skills.  
  src: https://github.com/github/spec-kit/blob/main/docs/installation.md (official-docs)
  - CORRECTED: github/spec-kit v1.0.12 (2026-09-25), 139,255 stars, MIT. It needs Python 3.11+. uv is only RECOMMENDED: pipx and plain `pip install specify-cli` are documented alternatives, so this machine's Python 3.14 (PYTHON_BIN) could install it without uv. Setup is `specify init <project> --integration claude`. PowerShell scripts are supported without WSL and are the Windows default. The Claude integration installs skills into .claude/skills.
  - evidence: https://github.com/github/spec-kit/blob/main/docs/installation.md
- **alt-02** [confirmed] Spec Kit commands: /speckit.constitution, specify, clarify, plan, checklist, tasks, analyze, implement, converge. /speckit.taskstoissues turns tasks.md into GitHub issues but "requires a GitHub origin remote and access to the GitHub MCP tools". The active feature is tracked in .specify/feature.json.  
  src: https://github.com/github/spec-kit/blob/main/docs/reference/agentic-sdd.md (official-docs)
- **alt-03** [confirmed] BMAD Method: bmad-code-org/BMAD-METHOD v6.12.0 (2026-09-04), about 53.6k stars. Install with `npx skills add bmad-code-org/BMAD-METHOD`, or on Claude Code with `/plugin marketplace add bmad-code-org/bmad-plugins` and then install bmad-method and bmad-core-tools. It needs uv; the npm engines field is node >=20.12.0.  
  src: https://github.com/bmad-code-org/BMAD-METHOD (repo)
- **alt-04** [confirmed] BMad Game Dev Studio (bmad-code-org/bmad-module-game-dev-studio v0.7.2, 2026-08-31, 243 stars) claims first-class Godot support. It produces a GDD, narrative design, UX specs (DESIGN.md, EXPERIENCE.md), technical architecture and epic-driven sprints. It needs Python >=3.11 and uv.  
  src: https://github.com/bmad-code-org/bmad-module-game-dev-studio (repo)
- **alt-05** [confirmed] Anthropic's official marketplace is named `claude-plugins-official` (repo anthropics/claude-plugins-official). Claude Code adds it on the first interactive terminal session. Anthropic-maintained plugins include feature-dev (`/feature-dev`, a 7-phase workflow with agents code-explorer, code-architect, code-reviewer), code-review (`/code-review`, 4 parallel agents, reports only issues with confidence >= 80, posts a PR comment) and pr-review-toolkit (`/review-pr`; agents comment-analyzer, pr-test-analyzer, silent-failure-hunter, type-design-analyzer, code-reviewer, code-simplifier).  
  src: https://code.claude.com/docs/en/plugins/anthropic-marketplaces.md (official-docs)
- **alt-06** [confirmed] The official marketplace.json (314 entries) lists `superpowers`, sourced from https://github.com/obra/superpowers.git pinned to sha 5bf4e78011075bcfc0dc295f0724994cd123ee71. It has no entry for GSD, get-shit-done, BMAD or Spec Kit.  
  src: https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json (repo)
- **alt-07** [corrected] Claude Code ships a bundled `/code-review` skill (alias `/review`) that takes a diff, PR number, branch or path, with effort levels low through ultra plus `--fix` and `--comment`. It also bundles `/simplify`, `/security-review`, `/batch` and `/ultrareview`.  
  src: https://code.claude.com/docs/en/commands.md (official-docs)
  - CORRECTED: The current docs match the claim. The local CLI (2.1.195) predates parts of it: `/review` became an alias of `/code-review` only in 2.1.223, `/code-review` became a background subagent in 2.1.218, and an earlier change had made `/review <pr>` a separate fast single-pass review. /security-review is a command, not marked as a bundled skill, and /ultrareview is an alias of `/code-review ultra` (a cloud review). Check against the version the Desktop app actually runs.
  - evidence: https://code.claude.com/docs/en/changelog.md
- **alt-08** [corrected] Plan mode: press Shift+Tab or prefix one prompt with `/plan`; the CLI flag is `claude --permission-mode plan`; set `"defaultMode": "plan"` in .claude/settings.json to make it the default for terminal sessions. Ctrl+G opens the plan in your editor. In the Desktop app, picking Plan applies to the current session only.  
  src: https://code.claude.com/docs/en/permission-modes.md (official-docs)
  - CORRECTED: Shift+Tab, a `/plan` prompt prefix and `claude --permission-mode plan` are correct. The settings key is `permissions.defaultMode: "plan"` in .claude/settings.json, not a top-level `defaultMode`. Ctrl+G, which opens the plan in your editor, is described for the terminal. In the Desktop app, a mode picked in the selector is remembered per folder, except that picking Plan applies to the current session only. The Desktop app DOES read `permissions.defaultMode` from the same settings files and applies it to new local sessions.
  - evidence: https://code.claude.com/docs/en/permission-modes.md
- **alt-09** [confirmed] `plansDirectory` sets where plan mode writes plan files, as a path relative to the project root; unset means ~/.claude/plans. `showClearContextOnPlanAccept` (default false) adds a 'Yes, clear context and …' option that approves the plan and starts implementing from the plan alone.  
  src: https://code.claude.com/docs/en/settings-reference.md (official-docs)
- **alt-10** [confirmed] Project skills live in .claude/skills/<name>/SKILL.md and are shared through git. On name collisions, enterprise beats personal and personal beats project. Plugin skills are namespaced `/plugin-name:skill-name`. The combined `description` + `when_to_use` is truncated at 1,536 characters in the skill listing. The frontmatter supports disable-model-invocation, allowed-tools, model, effort, context: fork, agent and paths.  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **alt-11** [confirmed] `enabledPlugins` in a repo's .claude/settings.json: a plugin listed in its marketplace by relative path loads once the folder is trusted. A plugin whose entry points at an external source (for example its own GitHub repo, as superpowers does) is not installed by repo settings alone. Each contributor sees 'enabled in project settings but isn't installed' until they run `claude plugin install <name>@<marketplace> --scope project`.  
  src: https://code.claude.com/docs/en/plugins/org.md (official-docs)
- **alt-12** [confirmed] Superpowers v6.4.2 (2026-09-25). Its brainstorming skill writes designs to docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md and commits them. Its writing-plans skill saves plans to docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md.  
  src: https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md (repo)
- **alt-13** [confirmed] Claude Code costs docs: "Aim to keep CLAUDE.md under 200 lines". Every subagent and every agent a dynamic workflow spawns sends its own requests on top of the main conversation. Plan mode is recommended to avoid expensive re-work. Agent teams use about 7x more tokens when teammates run in plan mode.  
  src: https://code.claude.com/docs/en/costs.md (official-docs)
- **alt-14** [corrected] Local environment: Claude Code 2.1.195, no plugins installed (`claude plugin list`). `claude plugin details <name>` reports a plugin's component inventory and projected token cost. Node v20.19.5, npm 10.8.2, uv not found, Git Bash 5.2.37 (msys).  
  src: local-test: claude --version; claude plugin --help; claude plugin list; node --version; npm --version; uv --version; bash --version (local-test)
  - CORRECTED: The local facts are right: Claude Code 2.1.195, no plugins, Node v20.19.5, npm 10.8.2, uv not found, GNU bash 5.2.37 (msys). But `claude plugin details` cannot measure a plugin before it is loaded: it has to be installed, in a skills directory, or passed with --plugin-dir. It also counts hooks as 'harness-only — no model context cost', so it misses context injected by a SessionStart hook. Also, 2.1.195 (June 26) is far behind npm latest 2.1.283 and stable 2.1.274.
  - evidence: https://code.claude.com/docs/en/plugins/measure.md

## Missed facts (from verifier)

- **m-01** The Claude Code CLI on PATH (2.1.195, released June 26, 2026) is about 88 releases behind npm latest 2.1.283 and stable 2.1.274. The docs the researcher read describe current behaviour, and some of it arrived after 2.1.195: /review aliasing /code-review came in 2.1.223, and /code-review running as a background agent in 2.1.218. Before approving, confirm which version the Desktop app bundles for each human, and have `doctor` report it.  
  src: https://code.claude.com/docs/en/changelog.md
- **m-02** superpowers@claude-plugins-official is pinned to sha 5bf4e780, which is v6.4.1, not v6.4.2. The v6.4.2 writing-plans rewrite, reported as producing plans in a quarter of the time with about a third of the tokens, is only available from obra/superpowers-marketplace (`superpowers@superpowers-marketplace`) until Anthropic moves the pin.  
  src: https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json
- **m-03** Superpowers registers a SessionStart hook (matcher startup|clear|compact, shell: bash). It injects the whole using-superpowers SKILL.md (3,192 bytes, about 800 tokens) as additionalContext every time a session starts, clears or compacts. `claude plugin details` reports hooks as having no model context cost, so it will understate this always-on cost.  
  src: https://github.com/obra/superpowers/blob/main/hooks/session-start
- **m-04** Superpowers' plan location can be overridden by user preference ('User preferences for plan location override this default'). Subagent-driven development keeps per-plan moving state (ledger, briefs, reports) in a GIT-IGNORED `.superpowers/sdd/<plan>/progress.md` workspace, not in committed files.  
  src: https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md
- **m-05** Superpowers v6.4.1 rebuilt executing-plans as 'Native' inline execution, described as 'the cheapest way to run a plan'. It runs the whole plan and then one fresh whole-branch review, and no longer stops every few tasks to check in. The subagent-driven controller can also run nested on a mid-tier model, measured at about half the cost.  
  src: https://github.com/obra/superpowers/releases/tag/v6.4.1
- **m-06** With GSD's default parallelization.enabled=true, executor agents commit with `--no-verify` and hooks are only validated after each wave.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/CONFIGURATION.md
- **m-07** Running or updating the current GSD installer deletes any byte-identical `Read(.env)`, `Read(.env.*)` or `Read(.secrets)` deny rule, including ones the user wrote by hand (#4221). It writes `Edit(.planning/*)` and `Edit(STATE.md)` allow rules.  
  src: https://github.com/open-gsd/gsd-core/blob/next/bin/install.js
- **m-08** GSD's `--profile=core`/`--minimal` installs only new-project, discuss-phase, plan-phase, execute-phase, phase, help, update and surface, with no sub-agents. It lacks /gsd-verify-work, /gsd-ship, /gsd-pr-branch, /gsd-progress and pause/resume. The Claude orchestration backend requires `full`.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/install-minimal-and-add-skills.md
- **m-09** PowerShell tool calls are governed by separate `PowerShell(...)` permission rules. `Bash(...)` rules, including those in a skill's allowed-tools, do not pre-approve a command the agent runs through the PowerShell tool.  
  src: https://code.claude.com/docs/en/permissions.md
- **m-10** GSD documents that on Claude Code, backgrounded-agent nesting (#853) forces execute-phase waves inline. Real wave parallelism needs the BETA, default-off Workflow backend on the full profile.  
  src: https://github.com/open-gsd/gsd-core/blob/next/docs/how-to/enable-claude-orchestration-workflow-backend.md

## Options

### A. Plain plan mode + our own committed project skills (no framework)
Use built-in plan mode (Shift+Tab or /plan) for non-trivial tasks. Encode the discipline in .claude/skills: start-task, finish-task, new-mechanic, new-level-piece. Use the built-in /code-review and /simplify skills plus our own read-only subagents. Plans stay in ~/.claude/plans (private to each machine). GitHub Issues holds all moving state, and handoffs are issue comments.
- pros: No new dependencies: works with Node 20 and needs no uv/Python.; No second source of truth: plans are local and ephemeral, and the durable output goes into issues, ADRs and docs.; Smallest token overhead: no framework prompts to load on each invocation, and skills load only when invoked.; Fully tailored to Godot/GDScript, the verify runner, the ownership map and the designer's no-code boundary.; Both humans get it with a plain git pull, with nothing to install per machine.; Stable: it depends only on Claude Code built-ins, not on a framework releasing weekly.
- cons: We have to write and maintain the discipline ourselves (TDD, verification before completion, reviewing each subagent's output).; No ready-made brainstorm → plan → subagent-execute pipeline; quality depends on how good our skills are.; Plan mode in the Desktop app is per session, so the humans or the skills have to remember to enter it.
### B. Superpowers (superpowers@claude-plugins-official) + our project skills
Install the Superpowers plugin (pinned in the official marketplace) for brainstorming, writing-plans, subagent-driven-development, TDD and verification-before-completion. Add our own skills on top. Covered in depth by a separate research topic.
- pros: Mature, opinionated discipline (TDD, a review after each task) with no build step or Node-version requirement.; Listed in Anthropic's official marketplace and pinned to a commit.; Plans and specs are dated per-feature files, so they rarely cause merge conflicts.
- cons: Writes specs and plans into docs/superpowers/ and commits them. That needs a rule so these files never hold task status, or a decision to redirect or ignore them.; Each human must run `claude plugin install superpowers@claude-plugins-official --scope project`; committed enabledPlugins alone does not install it.; Extra token cost from a fresh subagent plus review per task; not yet measured here (use `claude plugin details`).; Its general-purpose TDD rules may clash with Godot-specific verification (bots, shot).
### C. GSD Core with shared, committed .planning/
`npx @opengsd/gsd-core@latest --claude --local` on both machines, with .planning/ committed (the default) and optional workstreams per human.
- pros: The most complete built-in pipeline: discuss → plan (with plan-checker) → parallel execute → verify/UAT → ship.; Fresh-context executors resist context rot, and model profiles give cost levers.; Actively maintained, with a Windows CI lane.
- cons: Needs Node >= 24; this machine has Node 20.19.5, so both machines need an upgrade.; ROADMAP.md and STATE.md are GSD's source of truth for moving state, which directly violates KICKOFF 5.1/6. GitHub Issues sync would be manual.; Its authors call it a solo-developer tool. STATE.md has no merge driver, so two clones will conflict.; Heavy: about 65 commands, 33 agents, roughly 23k-token workflow prompts and about 12k-token agent prompts, and `effort: max` on the heavy skills.; Very high churn (weekly releases, about 90 commits a week). Registers about 15 hooks, edits the permission lists, generates .claude/CLAUDE.md and creates v[X.Y] tags by default.; Far too much ceremony for a designer who writes no code.
### D. GSD Core with private .planning/ (commit_docs=false, gitignored)
The same as C, but each human's .planning/ stays local, so GitHub Issues remains the only shared moving state.
- pros: Removes the shared-state conflict and STATE.md merges.; Keeps GSD's per-phase research, plan-check and verify discipline for the engineer's own sessions.
- cons: The docs say this breaks parallel executor worktrees and /gsd-undo, which are GSD's main advantages.; Still needs Node 24, and each human still has to install it and keep up with weekly updates.; Planning knowledge stays on one machine; the handoff to issues is still manual.; Carries all the token and complexity costs of C.
### E. GitHub Spec Kit
`uv tool install specify-cli` + `specify init . --integration claude`. Workflow: constitution → specify → plan → tasks → implement → converge per feature.
- pros: Very popular (about 139k stars), MIT, and the Windows PowerShell scripts work without WSL.; /speckit.taskstoissues can push tasks into GitHub Issues.
- cons: Needs Python 3.11+ and uv; uv is absent and Python is not on PATH.; The issue export needs GitHub MCP tools, not `gh`.; spec.md, plan.md, tasks.md and .specify/feature.json are another planning store.
### F. BMAD Method (+ Game Dev Studio for the designer)
`/plugin marketplace add bmad-code-org/bmad-plugins` or `npx skills add bmad-code-org/BMAD-METHOD`, plus the BMGD module for GDD and game design.
- pros: The only option with explicit game-dev and Godot support, including GDD and narrative templates for the designer.
- cons: Needs uv and Python; not in Anthropic's official marketplace.; Persona-heavy and token-heavy, with its own epic and sprint tracking that competes with GitHub Issues.; Its generated GDD content risks the agent inventing mechanics, which KICKOFF forbids.

## Recommendation

Pick Option A: plain plan mode plus our own committed project skills. Keep Option B (Superpowers) as the fallback, and adopt it only if the separate Superpowers research shows its token cost is acceptable and its docs/superpowers/ output can be confined to design history (never status). Reject GSD (C and D) for this project. Do not adopt Spec Kit or BMAD.

Why GSD is rejected:
1. **Node version.** It needs Node >= 24 and both machines run Node 20. Upgrading is a dependency change the humans would have to approve and repeat on the designer's machine.
2. **Competing source of truth.** Its data model makes .planning/ROADMAP.md and STATE.md the source of truth for moving state, which is exactly what KICKOFF sections 5 and 6 forbid. GSD has no GitHub Issues integration beyond pasting a URL into CONTEXT.md.
3. **Not built for two people.** Its maintainers call it a solo-developer tool. STATE.md has no merge driver, and the only way to keep planning private also disables its parallel worktree executors and /gsd-undo.
4. **Token cost.** Plan and execute workflows are each about 90 KB of prompt, core agent prompts are about 46 KB each, and the heavy skills declare `effort: max`. That works against our effort policy of high for core and medium for content.
5. **Churn and side effects.** It ships weekly and registers about 15 hooks. The installer edits permission lists and generates its own CLAUDE.md. The designer would face about 65 commands.

Why Option A fits this project:
- Humans write zero code, so the workflow the agents follow must be ours: the verify runner, bot matches, `shot`, the ownership map, and engine-request issues. None of the frameworks knows about these.
- Plan files in ~/.claude/plans stay private to each machine, so the rule that GitHub Issues is the only moving state holds without any configuration.
- Both humans get the skills through `git pull`, with no per-machine installs.
- It has the lowest token overhead.

Borrow the best ideas from Superpowers and GSD into our skills: explicit verification-before-completion, a fresh-agent verification step, a short restated plan at start-task, and discuss-before-plan questions for the designer.

Do not install the official code-review plugin, because `/code-review` is already built in. Consider pr-review-toolkit later only if reviews prove weak. All of this is a proposal for the engineer's approval; nothing has been installed or changed.

## Verifier critique of recommendation

The conclusion holds up: Option A (plan mode plus our own committed skills) as the default, and GSD rejected. The decisive reason is the one the researcher lists second. GSD's documented data model makes .planning/ROADMAP.md the 'single source of truth' and STATE.md a live tracker. It has no inbound GitHub Issues sync; the only GitHub sync is a 4-star third-party one-way mirror out of ROADMAP. That directly contradicts KICKOFF sections 5 and 6.

Weaknesses in the case:
(1) Node 24 is presented as reason 1. With nvm4w it is a small, reversible switch, so it should be a supporting point, not the lead.
(2) 'Not built for two people' leans on the CONTRIBUTING 'solo' wording, but GSD ships team-repo how-tos: keep-planning-docs-private, pr_strict/pr-branch, workstreams, workspaces. The stronger version is that STATE/ROADMAP have no merge driver and each privacy option costs something (worktree executors and /gsd-undo, or a separate -pr branch).
(3) The token numbers are a lower bound (see gsd-19), and GSD has mitigations the researcher omitted: workflow.compact_content, budget/inherit profiles, and a core profile with no agents. The fair statement is that GSD's overhead can be reduced, but only by dropping the parts that justify it.
(4) Several supporting details are stale or wrong: 35 agents not 33, a flat commands layout, Edit rather than Write permission rules, deny-rule removal, and the plugin path being 'once listed'. None changes the verdict, but they should not be copied into AGENT_WORKFLOW.md.

The biggest gap is that Superpowers is under-examined, even though it is the real alternative. It has no central mutable STATE file. Its SDD ledger is gitignored under .superpowers/sdd/, and its plan location is explicitly overridable by user preference. v6.4.1 added a cheap 'Native' execution mode. Its measurable costs are a roughly 800-token SessionStart injection on every start/clear/compact (invisible to `claude plugin details`), a bash-shell hook, about 15 auto-triggering skills, and brainstorming that auto-commits specs to docs/superpowers/specs. The official marketplace also installs v6.4.1, not the leaner-planning v6.4.2. The researcher should present B with these concrete numbers rather than 'pending separate research'.

For Option A:
- The claim that plan files stay private 'without any configuration' is true only while plansDirectory stays unset. It also depends on plan mode being used at all: the Desktop app only persists Plan per session, and nothing enforces it except the start-task skill text.
- Since discipline comes entirely from our own skills, the proposal should name what enforces verification-before-completion: finish-task, a fresh verifier subagent, and possibly a Stop or TaskCompleted-style hook. It should also recommend checking and upgrading the humans' Claude Code version.
- Not installing the code-review plugin is right; the built-in /code-review covers it.

## Concrete config (researcher)

PROPOSAL ONLY. Not applied. Needs approval.

1) .claude/settings.json (shared, committed). These are only the keys this topic affects; the permissions and hooks lists come from the other topics.
{
  "showClearContextOnPlanAccept": true
  // Leave "plansDirectory" UNSET, so plans stay in ~/.claude/plans (private per machine, never a second source of truth).
  // Do not set permissions.defaultMode to "plan" globally. The Desktop app treats Plan as per-session anyway. The start-task skill tells the agent to propose a plan and wait for approval on non-trivial work.
  // No enabledPlugins entry for Option A.
}

2) .claude/skills/start-task/SKILL.md (frontmatter sketch)
---
name: start-task
description: Begin work on one GitHub issue. Reads the issue with gh, reads the docs it links (ARCHITECTURE.md content API, GDD section, ADRs), checks ownership against CODEOWNERS, creates or switches to branch <area>/<issue>-<slug>, and restates the plan with acceptance criteria and verification commands before any edit. Use at the start of every task session.
argument-hint: [issue-number]
disable-model-invocation: true
allowed-tools: Bash(gh issue view *) Bash(git status) Bash(git switch *) Bash(git fetch *) Read Grep Glob
---

3) .claude/skills/finish-task/SKILL.md (frontmatter sketch)
---
name: finish-task
description: Definition of done for the current issue. Runs the task runner's verify, has a fresh subagent re-check claims against the diff, writes the handoff comment on the issue (done / left / decisions / gotchas), and opens a PR using the template with verification output pasted in.
argument-hint: [issue-number]
disable-model-invocation: true
allowed-tools: Bash(gh issue comment *) Bash(gh pr create *) Bash(git status) Bash(git diff *) Bash(git log *) Read
---

4) Only if Option B (Superpowers) is approved instead:
.claude/settings.json: { "enabledPlugins": { "superpowers@claude-plugins-official": true } }
Each human then runs once: claude plugin install superpowers@claude-plugins-official --scope project
Before approving, measure cost with: claude plugin details superpowers@claude-plugins-official
Add a CLAUDE.md rule: "docs/superpowers/** holds design history only; task status lives only in GitHub Issues."

5) Only if GSD is chosen against this recommendation (requires Node >= 24 on both machines first):
npx @opengsd/gsd-core@latest --claude --local --profile=core --relative-includes
.planning/config.json:
{
  "mode": "interactive",
  "model_profile": "balanced",
  "planning": { "commit_docs": false },
  "git": { "branching_strategy": "none", "create_tag": false },
  "workflow": { "auto_advance": false }
}
.gitignore: .planning/
(Trade-off, from the GSD docs: private planning disables parallel executor worktrees and /gsd-undo.)

## Config corrections (verifier)

1) The shared .claude/settings.json comment says 'The Desktop app treats Plan as per-session anyway'. That rationale is wrong. The Desktop app reads `permissions.defaultMode` from the same settings files and applies it to new local sessions; only choosing Plan in the mode selector is session-only. Keeping defaultMode unset is still fine, but change the stated reason. Desktop support for `showClearContextOnPlanAccept` is undocumented; verify it in the Desktop app before relying on it.

2) start-task allowed-tools:
- `Bash(git status)` is an exact match and will not cover `git status --short` or `-sb`. Use `Bash(git status *)`; a trailing ` *` also matches the bare command.
- Add `PowerShell(...)` equivalents such as `PowerShell(gh issue view *)`, `PowerShell(git status *)`, `PowerShell(git switch *)` and `PowerShell(git fetch *)`. The agents' primary shell is PowerShell, and Bash rules do not cover it.
- Consider `git worktree add *`, because KICKOFF section 5.4 prefers worktrees.
- Assigning the issue and moving the board card (`gh issue edit --add-assignee`, `gh project item-edit`) are writes. Leave them prompting, but have the skill do them.

3) finish-task allowed-tools cannot complete the flow as written:
- `gh pr create` fails in a non-interactive shell unless the branch is already pushed, so the skill needs a `git push -u origin <branch>` step. Pushing is a shared-state write, so decide whether it is pre-approved; if it is, deny pushes to main.
- KICKOFF section 5.4 requires rebasing on main and re-running tests before the PR, so it also needs `git fetch` and `git rebase origin/main`.
- Add the verify runner invocation (e.g. `PowerShell(./tools/<runner>.ps1 verify)`) and its Bash twin.
- Add PowerShell twins for every Bash rule.
- `Bash(git diff *)` and `Bash(git log *)` are fine.
- Pre-approving `gh pr create` and `gh issue comment` auto-publishes to GitHub. Make that an explicit decision for the engineer.

4) Option B:
- `claude plugin details superpowers@claude-plugins-official` will not work before installation. Clone obra/superpowers at 5bf4e780 (v6.4.1, which is what the official marketplace installs) into scratch, run `claude --plugin-dir <clone> plugin details superpowers`, and add about 800 tokens for the SessionStart injection, which the tool does not count. Confirm with /context in a trial session.
- The official entry gives v6.4.1. For v6.4.2 you would need `superpowers@superpowers-marketplace`, another third-party marketplace.
- Rather than only a CLAUDE.md rule that 'docs/superpowers/** holds design history only', use the documented plan-location override to route plans somewhere non-committed. Also gitignore `.superpowers/`, since SDD expects its workspace to be git-ignored; verify whether the helper script adds this itself.

5) GSD fallback:
- `--profile=core` omits /gsd-verify-work, /gsd-ship, /gsd-pr-branch, /gsd-progress and pause/resume. Use `--profile=standard` at minimum, or add clusters with /gsd-surface.
- Add `"parallelization": {"enabled": false}`. Parallel worktrees break anyway with commit_docs=false, and parallel executors commit with --no-verify.
- Consider `"workflow": {"compact_content": true}` and `"hooks": {"community": false}` (already the default).
- Warn that the installer will delete any `Read(.env)`, `Read(.env.*)` or `Read(.secrets)` deny rules we add (#4221), and writes `Edit(.planning/*)` and `Edit(STATE.md)` allows.
- With commit_docs=false, gsd-generated `.claude/CLAUDE.md` (claude_md_path) is still generated. Decide whether to gitignore it or point claude_md_path elsewhere.
- The local install writes flat `.claude/commands/gsd-*.md`, `.claude/agents/gsd-*.md` and `.claude/gsd-core/`. Decide whether these are committed; if they are, the designer's sessions load 35 GSD agent descriptions too. If they are gitignored, each human must run the installer.
- Node >= 24 is required first. With nvm4w, verify that hook commands resolve node through the stable nvm symlink, not a versioned path (#4838).

## Windows notes

- **GSD Core needs Node >= 24.** `engines` has required it since v1.11.0. This machine has Node 20.19.5 via nvm4w. The installer does not check the Node version itself, so running it on Node 20 would probably only give an npm EBADENGINE warning and then untested runtime behaviour (my inference).
- **GSD hooks pin node.exe paths.** Open issue #4838: the installer writes absolute, versioned node.exe paths into hook commands, so a Node upgrade silently breaks every GSD hook until you reinstall. With nvm4w, whether the recorded path is the stable C:\nvm4w\nodejs symlink or the versioned target is unverified.
- **GSD needs Git Bash.** Several GSD hooks are .sh scripts run through bash (Git Bash 5.2.37 is present). Issue #5082 shows that from PowerShell, 'bash' can resolve to WSL bash. Make sure the Git Bash that Claude Code uses comes before any WSL bash.exe on PATH.
- **CRLF and BOM break frontmatter parsers.** GSD recently fixed parsing bugs for CRLF files and for the UTF-8 BOM that PowerShell writes. The same risk applies to our own SKILL.md and agent frontmatter: write them as LF with no BOM. Avoid PowerShell 5.1 Set-Content/Out-File -Encoding utf8, which writes a BOM; use the Write tool or Git Bash instead. Our .gitattributes forcing LF on *.md helps.
- **Spec Kit and BMAD need Python 3.11+ and uv.** uv is not installed, and Python 3.14 is not on PATH (only in PYTHON_BIN). Spec Kit's PowerShell scripts do support Windows without WSL.
- **Built-in options need nothing extra.** Plain plan mode, project skills and official-marketplace plugins such as Superpowers or pr-review-toolkit are markdown plus hooks and need no extra runtimes. In the Desktop app (which both humans use), choosing Plan in the mode selector applies to that session only, so plan-first behaviour has to come from our skills or CLAUDE.md, not a sticky setting.

## Gotchas

- Search results and older blog posts point at glittercowboy/get-shit-done, gsd-build/get-shit-done (archived), `npx get-shit-done-cc` (deprecated) and `/gsd:<cmd>` colon commands. The canonical project is now open-gsd/gsd-core, installed with `npx @opengsd/gsd-core@latest`, with `/gsd-<cmd>` hyphen commands (or `/gsd-core:<cmd>` for the plugin install). Forks such as girishlade111/get-shit-done and b-r-a-n/gsd-claude are not canonical.
- GSD's own docs contradict each other on Node: the install how-to says 'Node.js 18+', but package.json engines requires >=24.0.0 and the CHANGELOG says Node 24 is required from v1.11.0 on.
- A local GSD install writes hooks to .claude/settings.local.json (gitignored). Committing the .claude/ payload does not give the other human working hooks; each human must run the installer.
- GSD's defaults conflict with our conventions: git.create_tag=true tags v[X.Y] on milestone completion; workspaces create branch workspace/<name>; phase branches are gsd/phase-{phase}-{slug}; the installer pre-populates permissions.allow/deny; it generates .claude/CLAUDE.md; heavy skills declare `effort: max`.
- GSD's 'keep planning private' mode (commit_docs=false) disables parallel executor worktrees and /gsd-undo, per GSD's own docs. You cannot have both private planning and GSD's main feature.
- Spec Kit's /speckit.taskstoissues needs the GitHub MCP tools, not the gh CLI. Our standard is gh, and the Claude Code costs doc recommends CLI tools over MCP for context efficiency.
- The official `code-review` plugin duplicates Claude Code's built-in `/code-review` skill (alias /review). The demo marketplace (anthropics/claude-code) also carries duplicate copies of code-review and feature-dev; install only from claude-plugins-official, if at all.
- Committing `enabledPlugins` in .claude/settings.json does not install a plugin whose marketplace entry points at an external GitHub source (Superpowers does). Each human must run `claude plugin install <name>@claude-plugins-official --scope project`.
- The live Claude Code docs describe features gated on versions up to v2.1.283, but this machine runs 2.1.195. Check that each setting we rely on (showClearContextOnPlanAccept, skillListingBudgetFraction, plansDirectory) exists in 2.1.195 before putting it in shared settings.
- BMad Game Dev Studio generates GDD, narrative and mechanics content. That clashes with KICKOFF's rule that the agent must not invent final game content and must propose options for the humans to pick.

## Open questions

- Does the separate Superpowers research find its per-task subagent-and-review overhead acceptable, and can its docs/superpowers/specs and plans output be limited to design history (or redirected)? That decides A vs B.
- Which Claude plan does each human have (Pro, Max, Team)? Framework token overhead matters much more on smaller seat allowances.
- Does the designer's machine have Node, Git Bash and gh installed, and at which versions? Any framework with a Node 24 or uv dependency multiplies setup work there.
- Should plan-mode plans stay private (plansDirectory unset, my recommendation), or should approved plans be kept, for example as an issue comment, a PR description section, or a committed docs/plans/ directory?
- Do the humans want to evaluate BMad Game Dev Studio for the designer's GDD and brainstorming work despite the uv/Python dependency and the content-invention risk?
- After approval, run `claude plugin details superpowers@claude-plugins-official` (and pr-review-toolkit) to get a measured token projection. I did not run it because it may fetch or modify ~/.claude marketplace state.
- Should we add pr-review-toolkit (Anthropic-maintained) later for silent-failure and test-coverage review, or do the built-in /code-review and our netcode-security-reviewer subagent cover it?