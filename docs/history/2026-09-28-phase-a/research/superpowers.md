# Superpowers framework (obra/superpowers)

## Summary

Superpowers is at v6.4.2 (released 2026-09-25, MIT, about 292k stars, releases roughly every 1-3 weeks, 139 open issues and 135 open PRs). It is a Claude Code plugin with 15 skills, 0 agents and 1 SessionStart hook. It has had no slash commands since v5.1.0; skills are called as /superpowers:<skill>. Anthropic's official marketplace (`superpowers@claude-plugins-official`) pins it to the v6.4.1 commit. obra's own marketplace follows main with no pin.

Fixed context cost, measured locally with `claude plugin details` on a copy of v6.4.2:
- About 703 tokens always on (skill names and descriptions).
- About 800 more tokens from the SessionStart bootstrap, which injects the whole using-superpowers skill on startup, on /clear and on every compaction.
- Total is about 1.5k tokens. Per-skill bodies cost 0.7k to 8.1k tokens when invoked; subagent-driven-development is about 8.1k.

The discipline is strict on purpose. The bootstrap tells the agent to invoke a skill if there is "even a 1% chance" one applies, before any reply. Brainstorming has a hard gate: architectural work needs an approved written spec, then an approved plan, then a chosen execution method. TDD's rule is to delete any code written before its test.

Specs and plans go to committed files under docs/superpowers/specs and docs/superpowers/plans. Scratch files go to a hardcoded <repo>/.superpowers/. There is no GitHub Issues integration. Moving those paths through CLAUDE.md works only with blunt imperative wording (issue #939 is open). The execution skills need a plan file on disk.

Windows works through Git Bash, which the hook forces with "shell": "bash", but there is friction:
- The hook takes about 1.3-2.3 s on each start, /clear and compaction (#2081).
- There is an open report that interactive Windows sessions silently lose the bootstrap (#2105).
- The helper scripts open a Windows "choose an app" dialog when run from PowerShell (#2307).
- On this machine, `bash` typed in PowerShell starts WSL Ubuntu, not Git Bash.

It can be enabled per project through committed `enabledPlugins`. However, Claude Code does not download an external-source plugin for teammates: each human must run `claude plugin install ... --scope project` once. Either human can opt out in `.claude/settings.local.json`.

Main conflicts with this project:
- A second planning store in docs/superpowers (the KICKOFF forbids a competing source of truth).
- A finish menu that offers "merge locally" and deletes the branch (conflicts with PR-only work on a protected main).
- Worktrees in the project root that Godot can scan.
- Engineering rituals (TDD, code-level plans) aimed at a designer who writes no code and works mostly in .tres/.tscn data.

Local Claude Code is 2.1.195. The latest is 2.1.283, and the maintainers test on 2.1.259-2.1.283.

## Facts (with verification)

- **superpowers-01** [corrected] Latest release is v6.4.2, published 2026-09-25 (tag commit 8ca22dba9a = current main HEAD). Prior: v6.4.1 2026-09-18/19 (v6.4.0 never shipped), v6.3.0 2026-08-12, v6.2.0 2026-07-23, v6.1.1 2026-07-02, v6.1.0 2026-06-30, v6.0.0-6.0.3 2026-06-16..18, v5.1.0 2026-04-30.  
  src: https://github.com/obra/superpowers/releases (local-test: gh api repos/obra/superpowers/releases; gh api repos/obra/superpowers/tags) (repo)
  - CORRECTED: Latest release is v6.4.2, published 2026-09-25 (tag commit 8ca22dba9a, which is main HEAD). v6.4.1: GitHub release 2026-09-19 00:32 UTC, notes dated 09-18 (v6.4.0 never shipped). v6.3.0 2026-08-12. v6.2.0: release 2026-07-24 00:28 UTC, notes 07-23. v6.1.1 07-02. v6.1.0 06-30. v6.0.0, 6.0.2 and 6.0.3 on 06-16..18 (6.0.1 appears only in the release notes and has no tag). v5.1.0: GitHub release published 2026-05-04, although its release-notes heading says 2026-04-30.
  - note: Checked with gh api releases and tags. The only error is the v5.1.0 date; the rest is timezone rounding.
  - evidence: https://github.com/obra/superpowers/releases
- **superpowers-02** [confirmed] Repo obra/superpowers: MIT license, created 2025-10-09, ~292k stars, ~26k forks, pushed 2026-09-27, not archived; 139 open issues, 135 open PRs; >=100 commits on the dev branch in the last 30 days (PRs target dev, releases merge to main).  
  src: local-test: gh api repos/obra/superpowers; gh api 'search/issues?q=repo:obra/superpowers+is:issue+is:open'; gh api 'repos/obra/superpowers/commits?sha=dev&since=2026-08-28T00:00:00Z&per_page=100' (local-test)
- **superpowers-03** [confirmed] Claude Code install commands from the README: official marketplace `/plugin install superpowers@claude-plugins-official`; alternative `/plugin marketplace add obra/superpowers-marketplace` then `/plugin install superpowers@superpowers-marketplace`. Shell equivalent: `claude plugin install superpowers@claude-plugins-official --scope project`.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/README.md (repo)
- **superpowers-04** [confirmed] Anthropic's claude-plugins-official marketplace.json lists superpowers with a url source pinned by sha: {"source":"url","url":"https://github.com/obra/superpowers.git","sha":"5bf4e78011075bcfc0dc295f0724994cd123ee71"}. That commit is the v6.4.1 release (plugin.json version 6.4.1), so the official channel lags main (6.4.2).  
  src: https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json (repo)
- **superpowers-05** [confirmed] obra/superpowers-marketplace lists superpowers with {"source":"url","url":"https://github.com/obra/superpowers.git"} and no ref/sha (tracks the default branch), a stale version field "6.3.0", plus a separate superpowers-dev entry tracking the dev branch.  
  src: https://github.com/obra/superpowers-marketplace/blob/main/.claude-plugin/marketplace.json (repo)
- **superpowers-06** [confirmed] Plugin auto-update is on by default for claude-plugins-official and off for third-party marketplaces. It runs after the first message with a random delay of up to 10 min and loads the new version next session. It is disabled by DISABLE_UPDATES=1, DISABLE_AUTOUPDATER=1 or CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 unless FORCE_AUTOUPDATE_PLUGINS=1. `autoUpdate` can also be set per marketplace in extraKnownMarketplaces.  
  src: https://code.claude.com/docs/en/plugins/loading (official-docs)
- **superpowers-07** [confirmed] Skills in v6.4.2 (15): brainstorming, diagnosing-superpowers, dispatching-parallel-agents, executing-plans, finishing-a-development-branch, receiving-code-review, requesting-code-review, subagent-driven-development, systematic-debugging, test-driven-development, using-git-worktrees, using-superpowers, verification-before-completion, writing-plans, writing-skills. There are no agents/ or commands/ directories.  
  src: https://github.com/obra/superpowers/tree/v6.4.2/skills (local-test: claude --plugin-dir <scratch copy of v6.4.2 manifests+SKILL.md files> plugin details superpowers) (local-test)
- **superpowers-08** [corrected] The legacy slash commands /brainstorm, /execute-plan and /write-plan were removed in v5.1.0. Skills are invoked as namespaced plugin skills, e.g. /superpowers:brainstorming (the bare /brainstorming also works when unambiguous). The claude.com listing still advertises `/execute-plan`.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/RELEASE-NOTES.md#v510-2026-04-30 ; https://code.claude.com/docs/en/skills ; https://claude.com/plugins/superpowers (changelog)
  - CORRECTED: The /brainstorm, /execute-plan and /write-plan commands were removed in v5.1.0. Plugin skills are invoked as /superpowers:<skill>. Do not document bare names: CC 2.1.265 added bare-name matching only for slash commands typed mid-prompt, and 2.1.269 made the Skill tool's 'Unknown skill' error name the full plugin skill name when a bare name matches. Both are newer than the local 2.1.195. The claude.com listing still advertises /execute-plan and a code-reviewer agent (removed in v5.1.0).
  - note: The namespacing is documented at https://code.claude.com/docs/en/skills (plugin skills as /plugin-name:skill-name). Removal source: RELEASE-NOTES v5.1.0.
  - evidence: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- **superpowers-09** [confirmed] Measured projected context cost: always-on ~703 tokens (skill names and descriptions). On-invoke: brainstorming ~4.3k, subagent-driven-development ~8.1k, executing-plans ~5k, writing-skills ~6.6k, writing-plans ~2.6k, test-driven-development ~2.4k, systematic-debugging ~2.3k, finishing-a-development-branch ~1.9k, using-git-worktrees ~1.6k, diagnosing-superpowers ~1.6k, dispatching-parallel-agents ~1.5k, receiving-code-review ~1.5k, verification-before-completion ~830, using-superpowers ~750, requesting-code-review ~700.  
  src: local-test: claude --plugin-dir C:\Users\xperi\AppData\Local\Temp\claude\D--prime-game\40c5c58a-0dc5-4821-beca-a406804c7d8a\scratchpad\sp plugin details superpowers (local-test)
- **superpowers-10** [confirmed] The SessionStart hook has matcher "startup|clear|compact". It runs `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd" session-start` with "shell": "bash" and "async": false, and emits hookSpecificOutput.additionalContext holding the full using-superpowers SKILL.md (3,192 bytes) wrapped in <EXTREMELY_IMPORTANT>You have superpowers...</EXTREMELY_IMPORTANT>.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/hooks/hooks.json ; https://github.com/obra/superpowers/blob/v6.4.2/hooks/session-start (repo)
- **superpowers-11** [confirmed] `claude plugin details` labels the SessionStart hook 'harness-only — no model context cost', so its always-on figure undercounts Superpowers. The real fixed overhead is about 703 + ~800 ≈ 1.5k tokens per session start, /clear or compaction.  
  src: https://code.claude.com/docs/en/plugins/measure ; local-test: claude --plugin-dir <scratch> plugin details superpowers (inferred)
- **superpowers-12** [confirmed] The bootstrap skill says: "If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill", invoke skills "BEFORE any response or action — including clarifying questions", and "Before entering plan mode: if you haven't already brainstormed, invoke the brainstorming skill first." It also says user instructions (CLAUDE.md, direct requests) take precedence over skills. Subagents are told to ignore it (<SUBAGENT-STOP>).  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/using-superpowers/SKILL.md (repo)
- **superpowers-13** [confirmed] The brainstorming HARD-GATE classifies each request as spike, bounded or architectural and says it out loud. Bounded: short design in chat, then an explicit yes. Architectural: questions one at a time, 2-3 approaches, sectioned design, written spec committed to git, human review of the spec, then writing-plans, human review of the plan, and a choice of execution method. "When in doubt between two paths, take the heavier one."  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/brainstorming/SKILL.md (repo)
- **superpowers-14** [confirmed] Default output paths: specs go to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` (and are committed); plans go to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`. Both skills say in a parenthetical that user preferences for location override the default.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/writing-plans/SKILL.md ; https://github.com/obra/superpowers/blob/v6.4.2/skills/brainstorming/SKILL.md (repo)
- **superpowers-15** [confirmed] Issue #939 (open since 2026-03-26): brainstorming ignores a CLAUDE.md 'Output Paths' table and still writes to docs/superpowers/specs/. The reported workaround is a bold imperative line in CLAUDE.md. The fix PR #1020 was closed unmerged, and the maintainer suggested a README example, which the v6.4.2 README does not contain.  
  src: https://github.com/obra/superpowers/issues/939 (issue)
- **superpowers-16** [corrected] The SDD/executing-plans scratch workspace is hardcoded to `<repo-root>/.superpowers/sdd/<plan-basename>/` with a self-ignoring .gitignore; brainstorming's visual companion uses `.superpowers/brainstorm/`. Requests to make this configurable (#1991, #975, #337, #1895 and others) were consolidated on 2026-09-26 into open tracking issue #2398; nothing is implemented yet.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/subagent-driven-development/scripts/sdd-workspace ; https://github.com/obra/superpowers/issues/2398 (repo)
  - CORRECTED: The SDD workspace is hardcoded in scripts as <repo-root>/.superpowers/sdd/<plan-basename>/, and the script writes .superpowers/sdd/.gitignore containing '*'. The brainstorm companion uses .superpowers/brainstorm/ when given --project-dir; it is NOT self-ignoring, and the skill tells the agent to remind the user to add .superpowers/ to .gitignore. #1991 and #975 were closed as not_planned on 2026-09-26 and are listed in open tracking issue #2398, along with unmerged PR #1999 (SUPERPOWERS_WORKSPACE_DIR) and #1895. #1895 is listed there, but its URL now returns 404. #337 was NOT consolidated: it was closed as completed on 2026-03-10, with the maintainer saying CLAUDE.md overrides have been honored since v5.0.
  - note: sdd-workspace source: https://github.com/obra/superpowers/blob/v6.4.2/skills/subagent-driven-development/scripts/sdd-workspace ; companion: skills/brainstorming/visual-companion.md lines 56-58.
  - evidence: https://github.com/obra/superpowers/issues/2398
- **superpowers-17** [confirmed] Superpowers has no GitHub Issues integration for specs and plans. The execution helpers need a plan FILE on disk: `sdd-workspace PLAN_FILE` exits 2 with 'no such plan file' when it is missing. finishing-a-development-branch is forge-neutral (no hardcoded `gh pr create` since v6.0.0).  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/subagent-driven-development/scripts/sdd-workspace ; https://github.com/obra/superpowers/blob/v6.4.2/RELEASE-NOTES.md (repo)
- **superpowers-18** [confirmed] TDD skill Iron Law: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST" and "Write code before the test? Delete it. Start over." Exceptions (throwaway prototypes, generated code, configuration files) require asking the human partner. Since v6.4.1 the project's full test command defines green, not just the task's own test file.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/test-driven-development/SKILL.md ; https://github.com/obra/superpowers/blob/v6.4.2/RELEASE-NOTES.md#v641-2026-09-18 (repo)
- **superpowers-19** [confirmed] finishing-a-development-branch must present exactly 3 options in a normal repo: '1. Merge back to <base-branch> locally', '2. Push and create a Pull Request', '3. Keep the branch as-is'. Option 1 runs `git checkout <base>; git pull; git merge <feature>` and then deletes the feature branch.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/finishing-a-development-branch/SKILL.md (repo)
- **superpowers-20** [confirmed] using-git-worktrees asks for consent unless a preference is declared, and prefers native harness tools (e.g. EnterWorktree). Its git fallback uses an existing `.worktrees/` or `worktrees/`, otherwise creates `.worktrees/` in the project root. v6.0.0 dropped the old global ~/.config/superpowers/worktrees/.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/using-git-worktrees/SKILL.md ; https://github.com/obra/superpowers/blob/v6.4.2/RELEASE-NOTES.md#v600-2026-06-16 (repo)
- **superpowers-21** [confirmed] subagent-driven-development runs a fresh implementer subagent per task, one reviewer per task (one pass that checks both the spec and code quality), and a final whole-branch review on the most capable model. Every dispatch must name a model. Reviews dispatch a `general-purpose` subagent filled from a template, not a project-defined custom agent.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/RELEASE-NOTES.md#v600-2026-06-16 ; https://github.com/obra/superpowers/blob/v6.4.2/skills/requesting-code-review/SKILL.md (repo)
- **superpowers-22** [confirmed] Since v6.2.0 the hook declares "shell": "bash". Claude Code 2.1.81 or later resolves that to Git for Windows directly and shows an install prompt if Git Bash is missing; older versions ignore the key. This fixed a PowerShell parse failure (#1751) and cmd.exe truncation on paths with '(' (#1918).  
  src: https://github.com/obra/superpowers/blob/v6.4.2/docs/windows/polyglot-hooks.md ; https://github.com/obra/superpowers/blob/v6.4.2/RELEASE-NOTES.md#v620-2026-07-23 (repo)
- **superpowers-23** [confirmed] Issue #2081 (open, reconfirmed on 6.4.2 on 2026-09-27): on Windows, hooks/session-start takes about 1.3-2.25 s instead of ~0.3 s because of six subprocess spawns, plus two bash startups in the launch chain. It runs on every startup, /clear and auto-compaction.  
  src: https://github.com/obra/superpowers/issues/2081 (issue)
- **superpowers-24** [confirmed] Issue #2105 (open, labeled windows/needs-repro): on native Windows interactive sessions the SessionStart bootstrap was reported silently missing (hook error with a literal ${CLAUDE_PLUGIN_ROOT}), while `claude -p` still got it. The maintainer has not reproduced it. Claude Code 2.1.246 fixed hook error messages that showed the literal ${CLAUDE_PLUGIN_ROOT}.  
  src: https://github.com/obra/superpowers/issues/2105 ; https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (issue)
- **superpowers-25** [confirmed] Issue #2307 (open): SDD helper scripts are extensionless bash files; run from PowerShell they open Windows' 'choose an app' dialog, and under MSYS they print /tmp-style paths. The v6.4.2 SDD SKILL.md says `bash scripts/sdd-workspace ...`, but executing-plans SKILL.md still says `scripts/task-start PLAN_FILE N` and `scripts/task-done ...` with no interpreter.  
  src: https://github.com/obra/superpowers/issues/2307 ; https://github.com/obra/superpowers/blob/v6.4.2/skills/executing-plans/SKILL.md (issue)
- **superpowers-26** [confirmed] The repo's bug-report template says "The Windows SessionStart hook alone has been reported 29 times." 36 closed and 5 open issues carry the `windows` label.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/.github/ISSUE_TEMPLATE/bug_report.md (local-test: gh issue list --repo obra/superpowers --label windows --state closed --limit 60 --json number --jq length) (repo)
- **superpowers-27** [confirmed] Telemetry: brainstorming's visual companion loads the Prime Radiant logo from the vendor's website with the Superpowers version by default. Disable it with env SUPERPOWERS_DISABLE_TELEMETRY; it also honors DISABLE_TELEMETRY and CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC. The companion is a Node server; on Windows it runs in the foreground and needs run_in_background.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/README.md#visual-companion-telemetry ; https://github.com/obra/superpowers/blob/v6.4.2/skills/brainstorming/visual-companion.md (repo)
- **superpowers-28** [confirmed] Enabling an external-source plugin in a committed .claude/settings.json does not install it for others. Each collaborator sees 'Plugin "<name>" is enabled in project settings but isn't installed' until they run `claude plugin install <name>@<marketplace> --scope project`. Only relative-path plugins inside a marketplace load without an install.  
  src: https://code.claude.com/docs/en/plugins/org#require-plugins-per-repository ; https://code.claude.com/docs/en/settings-reference#enabledplugins (official-docs)
- **superpowers-29** [corrected] extraKnownMarketplaces entries in a repo's .claude/settings.json are honored only after the workspace trust dialog is accepted, and are ignored silently in untrusted folders and -p runs. claude-plugins-official is added automatically the first time an interactive terminal session starts; it is already configured on this machine.  
  src: https://code.claude.com/docs/en/settings-reference#extraknownmarketplaces ; https://code.claude.com/docs/en/plugins/install (local-test: claude plugin marketplace list) (official-docs)
  - CORRECTED: extraKnownMarketplaces entries in a repo's .claude/settings.json(.local) are honored only after the workspace trust dialog is accepted. In an untrusted folder they are silently ignored, and that includes -p runs there. -p runs DO honor them in folders already trusted interactively, or where hasTrustDialogAccepted is set. claude-plugins-official is registered automatically on the first interactive launch unless CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL blocks it. It is already registered on this machine.
  - note: The org page says: '-p runs: the entries apply only in a folder whose trust the user already accepted interactively'. `claude plugin marketplace list` shows claude-plugins-official.
  - evidence: https://code.claude.com/docs/en/settings-reference#extraknownmarketplaces
- **superpowers-30** [confirmed] enabledPlugins precedence is local (.claude/settings.local.json) over project (.claude/settings.json) over user. A human can opt out of a project-enabled plugin with {"enabledPlugins":{"superpowers@claude-plugins-official": false}} in .claude/settings.local.json. The desktop app's local sessions, the terminal and VS Code share these settings files.  
  src: https://code.claude.com/docs/en/plugins/loading#find-where-a-plugin-is-enabled ; https://code.claude.com/docs/en/plugins/install (official-docs)
- **superpowers-31** [corrected] `skillOverrides` in settings hides or collapses individual skills, including plugin skills keyed as "plugin:skill". The values are "on", "name-only", "user-invocable-only" and "off". It has worked since Claude Code 2.1.129. Skill(name) permission deny rules can also block skills.  
  src: https://code.claude.com/docs/en/skills ; https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (2.1.129 entry) (official-docs)
  - CORRECTED: skillOverrides has worked since CC 2.1.129, with values on / name-only / user-invocable-only / off. It does NOT apply to plugin skills: the docs say 'Overrides don't apply to plugin skills, which you manage through /plugin.' Individual Superpowers skills therefore cannot be hidden with skillOverrides. The documented per-skill lever is a Skill(...) permission deny rule, e.g. Skill(superpowers:finishing-a-development-branch). That blocks invocation, but it is not documented to remove the skill from the listing or from the bootstrap's routing.
  - note: Also in https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings ('Plugin skills are not affected by skillOverrides'). The 2.1.129 changelog entry is correct.
  - evidence: https://code.claude.com/docs/en/settings-reference#skilloverrides
- **superpowers-32** [confirmed] A single hook cannot be disabled on its own. `disableAllHooks` turns off every hook, including our own gdformat/gdlint PostToolUse hook, so the Superpowers SessionStart bootstrap can only be removed by disabling the whole plugin.  
  src: https://code.claude.com/docs/en/hooks (official-docs)
- **superpowers-33** [confirmed] Local Claude Code CLI is 2.1.195 (C:\Users\xperi\.local\bin\claude.exe); the latest CHANGELOG entry is 2.1.283. Superpowers maintainers triage on Claude Code 2.1.259-2.1.283, and several plugin fixes relevant to Windows or projects landed after 2.1.195 (2.1.246, 2.1.281, 2.1.283).  
  src: local-test: claude --version ; https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (local-test)
- **superpowers-34** [confirmed] On this machine, PowerShell resolves `bash` to C:\WINDOWS\system32\bash.exe (the WSL launcher; WSL distros Ubuntu and docker-desktop are installed), while the Git Bash tool resolves it to /usr/bin/bash 5.2.37 (msys). Git for Windows bash is at C:\Program Files\Git\bin\bash.exe.  
  src: local-test: (Get-Command bash).Source ; wsl.exe -l -q ; Test-Path 'C:\Program Files\Git\bin\bash.exe' ; bash --version (Git Bash tool) (local-test)
- **superpowers-35** [confirmed] Issue #1480 (open): the bootstrap's 'You have superpowers.' / EXTREMELY_IMPORTANT / 'YOU DO NOT HAVE A CHOICE' framing makes some Sonnet 5 sessions flag it as a prompt injection, sometimes in the visible reply. The maintainer reproduced this in 0 of 3 runs.  
  src: https://github.com/obra/superpowers/issues/1480 ; https://github.com/obra/superpowers/issues/1878 (issue)
- **superpowers-36** [confirmed] The maintainers declined to restructure SDD around Claude Code Workflow fan-outs (#1835, closed 2026-08-19). Requests for a non-interactive or autonomous mode of brainstorming and writing-plans (#1895) are unimplemented and folded into #2398.  
  src: https://github.com/obra/superpowers/issues/1835 ; https://github.com/obra/superpowers/issues/2398 (issue)
- **superpowers-37** [corrected] Recent open quality issues: #2408 (writing-plans built the plan's code twice during planning on Opus 5.5 with 6.4.1; 6.4.2 says it reduced this), #2203 (bounded tasks fill the main session context because no subagent is used without a plan), #2273 (SDD re-review loop triggers on 'Approve + Important').  
  src: https://github.com/obra/superpowers/issues/2408 ; https://github.com/obra/superpowers/issues/2203 ; https://github.com/obra/superpowers/issues/2273 (issue)
  - CORRECTED: The three issues are open, but only #2408 is from Claude Code (VS Code extension, Windows 11, Opus 5.5, Superpowers 6.4.1; 6.4.2 notes say plans now take a quarter of the time). #2203 was reported on the Codex App with GPT-5.6, and the maintainer notes that Codex refuses subagents unless asked. #2273 was reported in Cursor.
  - note: Harness matters when weighing these for a Claude Code project. #2408: https://github.com/obra/superpowers/issues/2408 ; #2273: https://github.com/obra/superpowers/issues/2273
  - evidence: https://github.com/obra/superpowers/issues/2203
- **superpowers-38** [corrected] Community reviews: a 12-session review found Superpowers about 9% cheaper and about 14% fewer tokens overall, more tokens on simple tasks, savings on complex ones, and 2-3x tighter cost variance. It claims version 6.3.0 but its publication date is April 2026, which is inconsistent. A DEV Community post (2026-09-02) calls it slower and costlier on two-line fixes, 'an observation, not a measurement', and advises naming models in dispatches and skipping tiny fixes.  
  src: https://www.mejba.me/blog/superpowers-plugin-claude-code-review ; https://dev.to/aidiveyt/superpowers-fixes-claude-code-then-it-bills-you-for-every-two-line-fix-6dg (blog)
  - CORRECTED: The mejba.me review (12 sessions, 6 with and 6 without, $2 cap) reports about 9% cheaper, about 14% fewer tokens and 2-3x tighter clustering, with more tokens on simple tasks and savings on complex ones. The page says 'Published April 14, 2026; last revised August 14, 2026' and uses 6.3.0 (released 2026-08-12), so the dates are consistent. The DEV post (2026-09-02) calls its finding 'an observation, not a measurement' and advises naming models and skipping tiny fixes.
  - note: The researcher's 'inconsistent date' point is wrong. Both are blogs, and neither is a controlled benchmark.
  - evidence: https://www.mejba.me/blog/superpowers-plugin-claude-code-review
- **superpowers-39** [confirmed] The official directory listing shows 1,009,371 installs and no 'Anthropic verified' badge (a third-party author, Jesse Vincent / Prime Radiant).  
  src: https://claude.com/plugins/superpowers (official-docs)
- **superpowers-40** [confirmed] A plugin directory with .claude-plugin/plugin.json placed under the project's .claude/skills/ loads as <name>@skills-dir after workspace trust, without any install step, and only from the primary working directory. `claude plugin init` has existed since 2.1.157. Plain project skills in .claude/skills/<name>/SKILL.md need no plugin at all.  
  src: https://code.claude.com/docs/en/plugins/loading#plugins-shared-through-a-repository ; https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (2.1.157) (official-docs)
- **superpowers-41** [confirmed] Plan mode's plan file location is configurable with the `plansDirectory` setting (added in Claude Code 2.1.9).  
  src: https://code.claude.com/docs/en/settings-reference ; https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (2.1.9) (official-docs)
- **superpowers-42** [corrected] Godot's editor does not scan folders whose names start with '.', and a folder containing a .gdignore file is also ignored. A non-dot folder such as `worktrees/` inside the project root would be scanned.  
  src: https://forum.godotengine.org/t/gdignore-file-vs-folder-name-to-hide-folder/102053 (blog)
  - CORRECTED: In the Godot 4.7.2 EditorFileSystem scan, entries with the OS hidden attribute are skipped, directories whose names start with '.' are skipped, and so are directories containing .gdignore. Directories containing their own project.godot are ALSO skipped, with the warning 'Detected another project.godot at %s. The folder will be ignored.' So a git worktree of this repo under a non-dot worktrees/ is skipped by the editor too. The official docs mention only .gdignore; the dot-folder rule comes from source code.
  - note: Lines ~1174-1185 and _should_skip_directory at ~3488. The cited forum post is secondary. The remaining risk is CLI tooling (gdlint/gdformat recursion, test discovery), not the editor.
  - evidence: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp
- **superpowers-43** [confirmed] diagnosing-superpowers reads session transcripts on disk and, after human approval, can run `gh issue create --repo obra/superpowers ... --label bug --label automated-issue-report` using the local gh auth.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/skills/diagnosing-superpowers/references/github-issues.md (repo)
- **superpowers-44** [confirmed] GSD for comparison: the original repo gsd-build/get-shit-done is archived (last push 2026-05-31, ~64k stars). A blog reports that GSD keeps phase state in `.planning/` files and installs with `npx @opengsd/gsd-core@latest`.  
  src: local-test: gh api repos/gsd-build/get-shit-done ; https://www.pulumi.com/blog/claude-code-orchestration-frameworks/ (blog)

## Missed facts (from verifier)

- **m1** Claude Code's native worktrees (claude --worktree, EnterWorktree, the desktop worktree option) are created under .claude/worktrees/<name>/ on branch worktree-<name>, and the docs recommend gitignoring .claude/worktrees/. On Claude Code, Superpowers' using-git-worktrees defers to the native tool (Step 1a), so its .worktrees/ fallback rarely applies.  
  src: https://code.claude.com/docs/en/worktrees
- **m2** Godot 4.7.2's editor scan skips any subdirectory that contains its own project.godot (it warns and ignores the folder), besides dot-folders and .gdignore folders.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp
- **m3** Project-scope plugins load in git worktrees of the same repository only on Claude Code 2.1.200 or later (changelog: 'Fixed project-scoped plugins not loading correctly from git worktrees'). The local CLI is 2.1.195.  
  src: https://code.claude.com/docs/en/worktrees
- **m4** When a url or github source plugin's only `true` is in the committed .claude/settings.json, it is not fetched. Claude Code does fetch it automatically when `true` is set in the user's settings, in an untracked .claude/settings.local.json, via --settings, or in managed settings.  
  src: https://code.claude.com/docs/en/plugins/loading#enabled-in-project-settings-but-not-installed
- **m5** Plan mode stores plan files in ~/.claude/plans by default (outside the repo). plansDirectory resolves relative to the project root and falls back to the default if the path resolves outside it.  
  src: https://code.claude.com/docs/en/settings-reference#plansdirectory
- **m6** GSD is maintained under a new name. The original gsd-build/get-shit-done was archived (Pulumi: 2026-06-26), and development continues as open-gsd/gsd-core (~9.9k stars, pushed 2026-09-28). npm @opengsd/gsd-core is at 1.15.0 (modified 2026-09-26), and it still keeps phase state in .planning/.  
  src: https://github.com/open-gsd/gsd-core
- **m7** Superpowers' execution phase has become more autonomous. v6.3.0: SDD controllers record a ruling and continue on non-catastrophic plan conflicts, and only destructive or irreversible actions stop for a human (#2077). v6.4.1: executing-plans runs the whole plan without periodic check-ins and gets one final review. The human gates now sit almost entirely in brainstorming, writing-plans and the finish menu.  
  src: https://github.com/obra/superpowers/blob/v6.4.2/RELEASE-NOTES.md
- **m8** skillOverrides cannot hide plugin skills, and no individual hook can be disabled. A Superpowers skill can only be blocked with a Skill(superpowers:<name>) permission deny rule. That is not documented to remove the skill from the listing, and the bootstrap still routes to it.  
  src: https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings
- **m9** Being listed in claude-plugins-official is not an Anthropic review. The docs say a marketplace's name tells you who publishes the catalog, not what each plugin in it does, and ask you to review a plugin before installing it whichever marketplace it comes from. The official catalog pins Superpowers by commit sha, so updates arrive only when Anthropic's catalog bumps the sha.  
  src: https://code.claude.com/docs/en/plugins/security
- **m10** Superpowers does not accept project-specific or domain-specific changes or new skills upstream; any skill change must work across all supported harnesses (README Contributing; v5.1.0 contributor guidelines).  
  src: https://github.com/obra/superpowers/blob/v6.4.2/README.md

## Options

### A. Superpowers, full, project scope
Commit enabledPlugins {"superpowers@claude-plugins-official": true}; each human runs the one-time project-scope install; use the whole workflow as shipped (brainstorming, worktrees, writing-plans, SDD, TDD, review, finishing).
- pros: Proven discipline for TDD, verification-before-completion and systematic debugging, and it matches KICKOFF section 0 rules ('never claim it works unless you ran it', design before code).; Very active maintenance and a huge user base; bugs get triaged quickly.; Enforced by a bootstrap on every session, so rules are harder to forget than CLAUDE.md prose alone.; Pinned by sha in the official marketplace (currently v6.4.1).
- cons: Writes committed specs and plans to docs/superpowers/, a second source of truth that the KICKOFF forbids.; finishing-a-development-branch offers local merge and deletes branches (conflicts with PR-only work on a protected main).; About 1.5k tokens of fixed overhead per start, /clear and compaction, plus 2-8k per invoked skill; the SDD controller loop is heavy.; Windows friction: a 1.3-2.3 s hook on every start and compaction, the #2105 silent bootstrap loss risk, and bash helpers that break or run in WSL when called from PowerShell.; Up to 3 approval gates per architectural task, which clashes with unattended ultracode workflows.; Pushes engineering rituals onto the non-coder designer.; Auto-update on the official marketplace changes behavior between sessions, and the two machines can drift.
### B. Superpowers, trimmed, project scope
Same install as A, but with skillOverrides turning off or demoting conflicting skills (finishing-a-development-branch off; using-git-worktrees, writing-skills and diagnosing-superpowers user-invocable-only). A CLAUDE.md block forcefully redirects specs and plans (approved design goes to a GitHub issue comment, plan file to gitignored tools/out/plans/), forbids local merges, and forces helper scripts through the Git Bash tool. The designer opts out via settings.local.json.
- pros: Keeps TDD, systematic debugging, verification and brainstorming for the engineer's core/net/voice work.; The conflicting skills are removed at the harness level (skillOverrides), not just by prose.; The designer is unaffected if they opt out locally.
- cons: The bootstrap mandate cannot be switched off without dropping the plugin, and it still steers toward the removed skills. writing-plans marks subagent-driven-development or executing-plans as a REQUIRED SUB-SKILL, and brainstorming hands off to writing-plans, so the skill chain partly dangles.; Path redirection through CLAUDE.md is unreliable (issue #939), and .superpowers/ scratch stays hardcoded.; Two agents configured differently read the same shared CLAUDE.md, so rules must work with and without Superpowers.; The per-machine install step and version drift remain; so do all the Windows issues listed under A.; It is configuration we maintain against a target that ships a new release every 1-3 weeks.
### C. Superpowers engineer-only trial (local scope, time-boxed)
The engineer installs at local scope ('Install for you, in this repo only'), with nothing committed, for the M1 throwaway spike only. Afterwards we compare token use and outcomes and decide in an ADR.
- pros: No shared config or designer impact; fully reversible.; Produces real data on this machine (Windows hook reliability, token cost, fit with GdUnit4).; The M1 spike maps cleanly to brainstorming's 'Spike' path (no spec files).
- cons: The trial result will not represent content work or two-human coordination.; Costs a spike's worth of extra tokens.; Only valid after updating Claude Code from 2.1.195.
### D. No framework: plan mode + own skills, with vendored and adapted Superpowers discipline skills (MIT)
Use plain plan mode (plansDirectory pointing at gitignored scratch). The durable plan and handoff live in the GitHub issue. Commit our own .claude/skills/: start-task, finish-task, new-mechanic, new-level-piece, plus adapted copies of Superpowers' test-driven-development (as tdd-gdunit), systematic-debugging and verification-before-completion (optionally receiving-code-review). Each copy carries MIT attribution and a pinned upstream version, and is rewritten for GdUnit4, PowerShell and Git Bash, and our PR flow. No SessionStart hook; our enforcement comes from CLAUDE.md, the PostToolUse gdformat/gdlint hook and the `verify` definition of done.
- pros: GitHub Issues, docs and ADRs stay the only source of truth: no docs/superpowers, no .superpowers/ and no .planning/.; Both humans get it from git with zero install steps; the designer gets only designer-facing skills.; Windows-native: no bash helper scripts, no 1-2 s hook, no WSL trap.; Lowest context overhead (only our skill descriptions); behavior is pinned and reviewed in PRs, with no silent auto-updates.; Keeps Superpowers' best-validated content (TDD iron law, root-cause debugging, evidence before claims) where it fits: core/ and server/ tests.
- cons: We own maintenance, so upstream improvements need a periodic manual diff (e.g. per milestone).; No always-on bootstrap, so enforcement is weaker and relies on CLAUDE.md and hooks. Mitigations: a short 'use skill X when Y' table in root CLAUDE.md and the definition of done in finish-task.; No SDD-style per-task reviewer loop out of the box; our code-reviewer and test-runner subagents plus ultracode workflows have to cover it.; Up-front effort to write and adapt the skills in M0.
### E. GSD
Covered by the separate GSD research topic. From this topic's sources: the original repo is archived and GSD keeps durable phase state in .planning/ files.
- pros: Fresh-context subagents per phase fight context rot (per the Pulumi blog).
- cons: .planning/ state competes with GitHub Issues, just as docs/superpowers does.; The original repo is archived; the successor's status was not verified here.

## Recommendation

Choose D: plain plan mode plus our own committed skills, vendoring adapted copies of Superpowers' test-driven-development, systematic-debugging and verification-before-completion under MIT attribution. Do not install the Superpowers plugin into the shared config. If the engineer wants evidence, run option C (an engineer-only local-scope trial on the M1 throwaway spike) after updating Claude Code, and record the result in an ADR.

Why, for this project:
1. KICKOFF section 6 says a framework's planning files must not become a competing source of truth. Superpowers writes and commits specs and plans to docs/superpowers/ by design. The CLAUDE.md override is unreliable (#939), and its .superpowers/ scratch path cannot be changed (#2398 is open).
2. Its finish menu (local merge, then branch deletion) and worktree defaults conflict with our PR-only, protected-main, CODEOWNERS flow. Both would need to be disabled, which leaves a skill chain the bootstrap still points into.
3. On Windows 11 with PowerShell as the primary agent shell, Superpowers adds a 1.3-2.3 s hook on every start and compaction (#2081). There is an unresolved report of the bootstrap silently not loading in interactive sessions (#2105). Its bash helpers hit a Windows 'choose an app' dialog (#2307), and on this machine `bash` in PowerShell is WSL Ubuntu.
4. Two humans each need a manual install step, and auto-update can put them on different versions. The designer, who writes no code, would get TDD and code-level plan rituals that do not fit .tres/.tscn content work.
5. The fixed cost is about 1.5k tokens per session, /clear and compaction, plus 2-8k per invoked skill, and there are up to 3 human approval gates per architectural task. That works against KICKOFF section 10's unattended ultracode runs.

What is worth keeping from Superpowers is its content: the TDD rule 'write the failing test first, delete code written before its test', the 4-phase debugging method, and evidence-before-claims. That content is MIT-licensed and can live in our reviewed, pinned .claude/skills/ with zero install friction.

If the humans still prefer a framework, the fallback is option B. It needs the exact config below, a Claude Code update first, and a verification step on both machines. This is a proposal only; nothing has been installed or applied.

## Verifier critique of recommendation

Option D (plain plan mode plus vendored, attributed Superpowers skills, with an optional engineer-only local trial) is still the right recommendation, and the fact-check makes it stronger. The fallback (B) depends on skillOverrides to switch off finishing-a-development-branch, using-git-worktrees, writing-skills and diagnosing-superpowers. The docs say explicitly that skillOverrides does not apply to plugin skills. That leaves only Skill(...) deny rules, with the bootstrap still routing into the blocked skills.

The strongest reasons hold up against primary sources:
- The committed docs/superpowers/specs default, with an override that users report as unreliable (#939, open; plus the 2026-07-10 comment on #337).
- The script-computed .superpowers/ paths (#2398, open, nothing implemented).
- Human gates at every stage of brainstorming and planning, with the maintainers declining Workflow fan-out (#1835) and an autonomous mode (#1895) unimplemented. This conflicts with KICKOFF section 10's unattended runs.
- A per-human install step, plus auto-update drift.

Weaker or overstated points to fix in AGENT_WORKFLOW.md:
1. Worktrees. On Claude Code the skill defers to native EnterWorktree, which puts worktrees in .claude/worktrees/ and asks for consent first. Godot 4.7.2 ignores any subdirectory that contains a project.godot. So 'worktree defaults conflict' and 'duplicate class_name' are not real risks. The real risk is our own CLI tooling recursing into those folders.
2. Finish menu. It offers 'Push and create a Pull Request' following the repo's PR template, and the human picks. It is an extra gate and duplicates finish-task, but it does not force local merges.
3. Issue #2105. The evidence is weak: it is unreproduced, and the maintainer suspects it was the error-display bug fixed in 2.1.246. Present it as 'verify on both machines', not as a known defect.
4. Token cost. About 1.5k fixed tokens is minor. The real cost is 2-8k per invoked skill plus the ceremony, and that belongs in the discipline-vs-cost trade-off.
5. GSD. It is not dead (open-gsd/gsd-core is active), so the proposal must compare against GSD Core.
6. Execution autonomy. Superpowers' execution phase is now fairly autonomous (v6.3.0 rulings, v6.4.1 native execution). Say plainly that the conflict is with design and plan approvals.

The proposal should also state the main downside of D. It loses the SessionStart '1% rule' auto-trigger discipline, so the vendored skills rely on descriptions and CLAUDE.md routing. Mitigate this by making finish-task and the definition of done require the TDD and verification evidence.

Option C must run on at least Claude Code 2.1.200 (2.1.246+ recommended), preferably at local scope via settings.local.json. Measure it with /context and plugin details rather than blogs. The 'only on the M1 throwaway spike' framing is sensible.

## Concrete config (researcher)

PROPOSAL ONLY: nothing below has been applied or installed.

=== Recommended (Option D): no plugin; vendored and adapted skills ===
.claude/settings.json (fragment; plansDirectory keeps plan-mode files out of git; tools/out/ is already gitignored per KICKOFF section 2):
{
  "plansDirectory": "tools/out/plans"
}
(Open question: check that plansDirectory resolves relative to the project root on 2.1.195 or later.)

.claude/skills/tdd-gdunit/SKILL.md frontmatter (example of an adapted, attributed copy):
---
name: tdd-gdunit
description: Use when implementing or fixing behavior in core/, server/, net/, voice/ or tools/ before writing implementation code. Red-green-refactor with GdUnit4 via the task runner. Not for .tscn/.tres content.
---
<!-- Adapted from obra/superpowers v6.4.2 skills/test-driven-development (MIT, (c) Jesse Vincent). Upstream: https://github.com/obra/superpowers/blob/v6.4.2/skills/test-driven-development/SKILL.md -->
Other vendored skills, same pattern: systematic-debugging, verify-before-done (from verification-before-completion) and optionally receiving-code-review. Put the MIT license text in .claude/skills/THIRD_PARTY_NOTICES.md (or CREDITS.md) and record the upstream version per file.

Root CLAUDE.md, one table row per skill, e.g. "Changing behavior in core/ server/ net/ voice/ tools/ -> /tdd-gdunit. Bug or failing test -> /systematic-debugging. Before claiming done or opening a PR -> /verify-before-done, then /finish-task."

=== Fallback (Option B): Superpowers trimmed, if the humans choose it ===
Prerequisite: update Claude Code on both machines (local CLI is 2.1.195; latest is 2.1.283) and confirm the desktop app's bundled version.

.claude/settings.json (committed):
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  },
  "skillOverrides": {
    "superpowers:finishing-a-development-branch": "off",
    "superpowers:using-git-worktrees": "user-invocable-only",
    "superpowers:writing-skills": "user-invocable-only",
    "superpowers:diagnosing-superpowers": "user-invocable-only"
  },
  "env": {
    "SUPERPOWERS_DISABLE_TELEMETRY": "1"
  }
}
Notes: no extraKnownMarketplaces entry is needed, because claude-plugins-official is auto-registered and its name is reserved. Only if we used obra's marketplace instead (not recommended; unpinned):
  "extraKnownMarketplaces": { "superpowers-marketplace": { "source": { "source": "github", "repo": "obra/superpowers-marketplace" }, "autoUpdate": false } }

One-time step per human (PowerShell), because project settings do not download url-source plugins:
  claude plugin install superpowers@claude-plugins-official --scope project
(Desktop app alternative: + > Plugins > Add plugin > superpowers > 'this project'.)

Designer opt-out (their gitignored .claude/settings.local.json):
{ "enabledPlugins": { "superpowers@claude-plugins-official": false } }

.gitignore additions: .superpowers/  and  tools/out/

CLAUDE.md block (use imperative, bold wording; issue #939 shows that a table alone is ignored):
## Superpowers overrides (these take precedence over skill defaults)
**IMPORTANT: Never create or commit files under docs/superpowers/. Post an approved design as a comment on the GitHub issue (`gh issue comment <n> --body-file <file>`). Save plans ONLY to tools/out/plans/<issue>-<slug>.md (gitignored) and never commit them.**
- Integration is always: rebase on main, run verify, push the branch, open a PR using our template. Never merge locally. Never delete branches.
- Worktrees: only under a dot-prefixed or out-of-project directory (never `worktrees/` inside the Godot project).
- Run Superpowers helper scripts only through the Bash (Git Bash) tool, or as & "C:\Program Files\Git\bin\bash.exe" <script> from PowerShell. Never call plain `bash` from PowerShell: on this machine it is WSL.
- TDD applies to core/ server/ net/ voice/ tools/. Content .tres and level .tscn work follows content/CLAUDE.md and levels/CLAUDE.md, not the TDD skill.
- Spike work (M1) uses brainstorming's Spike path: no spec file.

Verification after install (each machine):
  claude plugin list                     # expect superpowers@claude-plugins-official, scope project, enabled
  claude plugin details superpowers      # expect 15 skills, 1 SessionStart hook, ~0.7k always-on
  then in a fresh interactive desktop-app session: Is the phrase "You have superpowers" in your context? YES or NO   (from #2105; expect YES)

## Config corrections (verifier)

1. The Option B skillOverrides block does not work. Plugin skills are not affected by skillOverrides (settings-reference#skilloverrides; skills#override-skill-visibility-from-settings). Replace it with permissions.deny entries such as "Skill(superpowers:finishing-a-development-branch)", "Skill(superpowers:using-git-worktrees)", "Skill(superpowers:writing-skills)" and "Skill(superpowers:diagnosing-superpowers)". Mark these as needing verification: do they also hide the skill from the listing, and how does the bootstrap react to a denied skill? Otherwise, drop the pretence that the plugin can be trimmed.
2. plansDirectory open question, answered: it resolves relative to the project root, and a path outside the root falls back to the default. The default is ~/.claude/plans, already outside git, so "tools/out/plans" is optional. If kept, make sure the task runner never wipes tools/out/plans.
3. .gitignore: add .claude/worktrees/ (Claude Code's native worktree location, which Superpowers also prefers) and .worktrees/. Keep .superpowers/: brainstorm/ is not self-ignoring; only sdd/ writes its own .gitignore.
4. The CLAUDE.md line "never worktrees/ inside the Godot project" rests on a false premise: Godot 4.7.2 skips any subfolder that contains its own project.godot. Replace it with "use native worktrees (.claude/worktrees/)". Make the task runner, gdlint/gdformat and GdUnit4 exclude .claude/, .worktrees/, worktrees/ and .superpowers/.
5. Prerequisite versions: at least 2.1.200 for project-scope plugins in worktrees, and at least 2.1.246 for correct hook error text. Also check the desktop app's CLI version.
6. Install step: the shell form is from code.claude.com/docs/en/plugins/install, not the README. A zero-command alternative per human is {"enabledPlugins":{"superpowers@claude-plugins-official":true}} in their gitignored .claude/settings.local.json, which is auto-fetched. For the engineer-only trial (Option C), use --scope local, or that local-file entry, instead of committing to .claude/settings.json.
7. Version drift: optionally pin updates by declaring "claude-plugins-official" under extraKnownMarketplaces with source {"source":"github","repo":"anthropics/claude-plugins-official"} and "autoUpdate": false. The reserved name is allowed from github.com/anthropics/, and the settings entry takes precedence. The trade-off: this stops auto-update for all official plugins. Otherwise, document that both humans run `claude plugin update superpowers` together.
8. Human-facing invocation names must be /superpowers:<skill>. Bare names are not reliable (2.1.265+ mid-prompt only; the Skill tool rejects bare names).
9. Vendored-skill notice: copy the full MIT text with "Copyright (c) 2025 Jesse Vincent" and the upstream tag per file. "(c) Jesse Vincent" alone in an HTML comment is not enough.
10. "Desktop app alternative: + > Plugins > Add plugin > superpowers > 'this project'" matches the docs. Keep it.

## Windows notes

- **Git Bash is required.** The SessionStart hook declares "shell": "bash" (Superpowers 6.2.0 or later; Claude Code 2.1.81 or later), so Claude Code runs it through Git for Windows. Git for Windows is present at C:\Program Files\Git\bin\bash.exe. Without Git Bash the hook fails with an install prompt, and older versions failed silently.
- **Startup latency.** On Windows the hook costs about 1.3-2.3 s each time it fires: startup, /clear and every auto-compaction (#2081, still unfixed in 6.4.2).
- **Bootstrap may be missing.** Issue #2105 (open, not reproduced by the maintainer) reports that native-Windows interactive sessions silently lose the bootstrap, while `claude -p` keeps it. The maintainers point to a Claude Code substitution problem around versions 2.1.223-2.1.246. Local CLI 2.1.195 predates the 2.1.246 fix; update first and verify with the 'You have superpowers' question in a desktop-app session.
- **WSL trap.** In PowerShell, `bash` resolves to C:\WINDOWS\system32\bash.exe, which is WSL, and WSL has Ubuntu and docker-desktop installed. Any skill instruction like `bash scripts/sdd-workspace ...` run from the PowerShell tool would execute inside WSL Ubuntu, with /mnt/d paths and WSL's git. In the Git Bash tool, `bash` is /usr/bin/bash 5.2.37 (msys), which is correct.
- **Extensionless helper scripts.** Superpowers' helpers (sdd-workspace, task-brief, review-package, task-start, task-done) are extensionless bash files. Invoked directly from PowerShell they open Windows' 'choose an app' dialog (#2307). The v6.4.2 executing-plans SKILL.md still invokes `scripts/task-start` and `scripts/task-done` without `bash`. Under MSYS, sdd-workspace prints POSIX paths that PowerShell tools may not read.
- **Visual companion.** It is a Node server (Node 20.19.5 is available). On Windows it auto-switches to foreground mode and must be started with run_in_background; it relies on an idle timeout for shutdown.
- **Past incidents.** A Windows Defender 'Ulthar.A!ml' alert on install was reported and closed as an apparent false positive (#2143). A per-user Git install under %LOCALAPPDATA%\Programs\Git was missed by run-hook.cmd's discovery (#1863, closed).
- **Line endings.** Superpowers' own .gitattributes forces LF for *.cmd and the hook script, so a Windows git clone into the plugin cache keeps the polyglot wrapper valid. Our repo's LF policy is unaffected because plugin files live in ~/.claude/plugins/cache/, not the repo.
- **Scratch directories vs Godot.** `.superpowers/` and `.worktrees/` would sit in the Godot project root. Godot ignores dot-prefixed folders, but a non-dot `worktrees/` folder would be scanned and would duplicate class_name declarations. Confirm this on Godot 4.7.2.
- **Recommended option D avoids all of the above.** It uses no bash helpers and no SessionStart hook; skills are plain Markdown and the runner uses .ps1 and .sh wrappers.

## Gotchas

- Committing enabledPlugins does not install Superpowers for the other human. Each person must run `claude plugin install superpowers@claude-plugins-official --scope project` once; otherwise /plugin shows 'enabled in project settings but isn't installed here'.
- `claude plugin details` reports the SessionStart hook as having 'no model context cost', but it injects about 0.8k tokens. The true fixed cost is about 1.5k tokens, re-paid after every /clear and compaction.
- The official marketplace pins v6.4.1 (sha 5bf4e780), not the latest 6.4.2. obra's own marketplace is unpinned and tracks main, and its version field is stale (6.3.0).
- Official-marketplace plugins auto-update in the background by default, so the two machines can run different Superpowers versions and behave differently in the same repo. DISABLE_AUTOUPDATER or CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC turns off plugin auto-update (and other things).
- Spec and plan paths default to committed docs/superpowers/..., and the CLAUDE.md override is ignored unless phrased as a bold imperative (#939). .superpowers/ scratch cannot be moved at all (#2398).
- Switching off a Superpowers skill with skillOverrides leaves dangling references: writing-plans declares subagent-driven-development or executing-plans as a REQUIRED SUB-SKILL, and the bootstrap still tells the agent to invoke skills at a 1% chance of relevance.
- Only disabling the whole plugin removes the bootstrap. There is no per-hook disable, and disableAllHooks would also kill our gdformat/gdlint PostToolUse hook.
- finishing-a-development-branch option 1 merges locally into main and deletes the branch. On a non-coder's machine one wrong menu pick bypasses the PR and CODEOWNERS flow (branch protection on GitHub still blocks the push, but the local main diverges).
- The TDD skill says to delete code written before its test. For M1's throwaway spike, or .tscn/.tres content, the agent will stop and ask for an exception each time unless CLAUDE.md scopes TDD to code directories.
- SDD dispatches `general-purpose` subagents from templates, not our custom code-reviewer or netcode-security-reviewer agents, so our model-routing verification would not cover its reviewers.
- The bootstrap's 'EXTREMELY_IMPORTANT / YOU DO NOT HAVE A CHOICE' tone has made some Sonnet 5 sessions flag it as a prompt injection (#1480), sometimes in visible replies. That would confuse a human who dictates in Ukrainian.
- diagnosing-superpowers can draft and, after approval, file issues on obra/superpowers with the human's gh auth. Keep it user-invocable-only.
- The claude.com listing still advertises `/execute-plan`, removed in v5.1.0. Do not copy invocation names from third-party pages.
- Local Claude Code 2.1.195 is about 88 releases behind 2.1.283. Current docs describe features newer than the installed CLI (e.g. `/plugin install --marketplace` needs 2.1.275, and sync from claude.ai needs 2.1.273), so re-verify every setting on the actual version.
- If vendoring (option D), keep the MIT license notice with every adapted skill and record the upstream version, e.g. v6.4.2, so later diffs are possible.

## Open questions

- Which Claude Code version does the Claude desktop app's Code tab run on each human's machine? Should we update the CLI from 2.1.195 to 2.1.283 or later before Phase B regardless of the framework decision?
- Does the engineer accept up to 3 approval gates per architectural task (spec, plan, execution method)? Or do we want KICKOFF section 10 ultracode runs to proceed unattended, which Superpowers' brainstorming and writing-plans do not support (#1895 not implemented)?
- Should the designer's agent run any framework at all, or only the designer-facing skills (new-mechanic, new-level-piece) plus content/levels CLAUDE.md?
- If option D: which Superpowers skills should we vendor? Proposed: test-driven-development, systematic-debugging, verification-before-completion, optionally receiving-code-review. Do we attribute in CREDITS.md or a THIRD_PARTY_NOTICES.md under .claude/skills/?
- Does `plansDirectory` accept a project-relative path such as tools/out/plans on our Claude Code version, and does plan mode still work well when the durable plan is copied into the GitHub issue?
- Does Godot 4.7.2 on this machine ignore dot-prefixed folders (.worktrees/, .superpowers/, .claude/worktrees/) during a headless import? This needs a test once the repo is initialized. Where should git worktrees live (sibling directory vs .claude/worktrees)?
- If a Superpowers trial (option C) is approved: does the bootstrap actually load in an interactive desktop-app session on Windows (#2105)? What is the measured token and time overhead on the M1 spike compared with a session without the plugin?
- Is the ~1.5k-token fixed overhead plus 2-8k per invoked skill acceptable under the humans' plan limits, given two parallel sessions?