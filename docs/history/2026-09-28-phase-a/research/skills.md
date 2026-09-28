# Claude Code skills, slash commands and plugins for team sharing

## Summary

Phase A research on configuring shared project skills for the prime-game team. Two independent humans (engineer and designer) work in separate Claude Code sessions on Windows 11, coordinating only through GitHub Issues and committed code. Skills can be shared via (1) committed .claude/skills/ directory, loaded automatically by both humans in their independent sessions; or (2) packaged as a plugin with .claude-plugin/plugin.json, which adds versioning and marketplace distribution but is unnecessary overhead for single-repo team coordination. Custom slash commands (.claude/commands/) are legacy; use skills (.claude/skills/) for all new work. Skills support bundled supporting files, Windows execution via PowerShell or Bash, and character-limited descriptions (1,536 characters combined). No external marketplace needed for internal team sharing. The key recommendation for this project is to use committed .claude/skills/ for the four shared skills (new-mechanic, new-level-piece, start-task, finish-task) because it is simplest, most transparent, requires no setup beyond git commit, and fits the coordination model already established through GitHub Issues.

## Facts (with verification)

- **skill-frontmatter-01** [confirmed] SKILL.md frontmatter supports fields: name, description, when_to_use, argument-hint, arguments, disable-model-invocation, user-invocable, allowed-tools, disallowed-tools, model, effort, context, agent, background, hooks, paths, shell, metadata, license, compatibility  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **skill-location-precedence-01** [corrected] Skills load from five locations with precedence: enterprise managed, personal ~/.claude/skills, project .claude/skills, nested subdirectory .claude/skills, plugin skills. Project .claude/skills automatically loads for all sessions in that repo  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
  - CORRECTED: The docs list seven locations: enterprise (managed settings dir), personal ~/.claude/skills, project .claude/skills (the start dir and every parent up to the repo root; in a worktree only up to the worktree root), nested <subdir>/.claude/skills (loaded lazily), --add-dir directories, plugins (as /plugin:skill), and skills synced from the claude.ai account. Name precedence only applies between enterprise > personal > project, so a personal ~/.claude/skills/start-task silently shadows the project one. A root skill and a nested skill with the same name both stay available. Plugin skills never collide because they are namespaced. A skill beats a same-named .claude/commands file. A local skill beats a synced skill's short name. Project skills load in every session started in the repo, with no install step.
  - note: The claim says five locations with a single precedence chain. That is wrong on both counts.
  - evidence: https://code.claude.com/docs/en/skills.md#where-skills-live
- **skill-description-limit-01** [confirmed] Skill description and when_to_use combined truncated at 1,536 characters. Compatibility field max 500 characters  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **commands-vs-skills-01** [confirmed] Custom slash commands (.claude/commands/) are legacy. Skills (.claude/skills/) are the recommended approach for new work. Both invoke as /name. Skills support bundled directories with supporting files; commands are flat Markdown  
  src: https://code.claude.com/docs/en/claude-directory.md (official-docs)
- **skill-arguments-01** [confirmed] Skills support arguments field (space-separated string or YAML list) for positional parameters. Substitutions: $ARGUMENTS, $ARGUMENTS[N], $N, $name, ${CLAUDE_SESSION_ID}, ${CLAUDE_EFFORT}, ${CLAUDE_SKILL_DIR}, ${CLAUDE_PROJECT_DIR}  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **skill-context-fork-01** [confirmed] Skills can run in isolated subagent context with context: fork and agent field (Explore, Plan, general-purpose). background field controls if skill waits for result (requires v2.1.218+). Isolated context useful for skills that should not enter main conversation  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **skill-windows-shell-01** [corrected] Skills shell field accepts bash (default) or powershell. Windows execution works with both. Injected commands run in specified shell (! prefix syntax)  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
  - CORRECTED: shell accepts bash (default) or powershell. It governs the !`cmd` inline form and ```! fenced blocks. An explicit shell: bash makes the invocation fail on Windows when Git Bash is missing. shell: powershell uses the PowerShell tool only if that tool is enabled. With shell omitted, commands go through the Bash tool when bash exists and otherwise through PowerShell. Injected commands never prompt for permission. Outside auto mode, a command that the permission rules or allowed-tools do not allow aborts the whole skill invocation. So does a non-zero exit, except exit 1 from search or compare commands; the docs suggest appending `|| true` under bash.
  - note: This machine has both Git Bash and the PowerShell tool, so either value works here. The blanket statement 'Windows works with both' is conditional.
  - evidence: https://code.claude.com/docs/en/skills.md#how-injected-commands-run
- **skill-allowed-tools-01** [confirmed] allowed-tools field pre-approves specific tools for single invocation turn only. Format: space/comma-separated or YAML list. disallowed-tools removes tools from Claude pool during skill invocation. Both clear after next user message  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **plugin-structure-01** [confirmed] Plugin is directory with .claude-plugin/plugin.json manifest. Can contain: skills/, agents/, hooks/hooks.json, .mcp.json. Plugin skills invoke as /plugin-name:skill-name to avoid naming collisions  
  src: https://code.claude.com/docs/en/plugins/create.md (official-docs)
- **plugin-vs-committed-skills-01** [confirmed] Use plugins when packaging multiple components (skills, agents, hooks, MCP servers) to share as one unit for multiple projects or publish versioned releases. Use committed .claude/skills when skills are project-specific and only need to load in one repository  
  src: https://code.claude.com/docs/en/plugins/overview.md (official-docs)
- **skill-sharing-repo-01** [confirmed] To share skills in a repository: commit to .claude/skills/<name>/SKILL.md. All team members working in that repository will automatically load them. No installation step, no marketplace needed  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **plugin-marketplace-01** [confirmed] Plugin marketplace is .claude-plugin/marketplace.json listing plugin sources. Optional: only needed if plugin will be versioned and distributed across multiple projects or teams. Not required for single-repo team sharing  
  src: https://code.claude.com/docs/en/plugins/publish.md (official-docs)
- **skill-nested-loading-01** [corrected] Nested skills in subdirectories (.claude/skills at subdirectory level) load on-demand when Claude reads files there. Naming: /skill-name (root) and /parent:skill-name (nested) can coexist. Both loads simult aneously  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
  - CORRECTED: Skills in a .claude/skills below the start directory do not load at startup. They load the first time Claude reads or edits a file in that subdirectory (or via /add-dir on v2.1.257+) and then stay loaded. A nested skill gets a directory-qualified name only when its name clashes, and the qualifier is the subdirectory path relative to the working directory, e.g. /apps/web:deploy, not /parent:skill-name. /deploy runs the root skill, and Claude is told to use the variant whose directory holds the files it is working on.
  - evidence: https://code.claude.com/docs/en/skills.md#discovery-from-parent-and-nested-directories
- **skill-disable-model-01** [confirmed] disable-model-invocation: true means only human can invoke; Claude cannot and description is hidden from Claude. user-invocable: false means only Claude can invoke; hidden from human /name menu  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **skill-eval-01** [refuted] claude plugin eval command runs eval cases for skills. Requires evals/ directory with prompt.md and graders/. Works on both plugin skills and project skills. Helps test reliability before shipping  
  src: https://code.claude.com/docs/en/plugin-evals.md (official-docs)
  - CORRECTED: claude plugin eval was added in v2.1.269 and, since v2.1.283, needs git 2.31 or later. It evaluates plugins only: a plugin root directory, an installed plugin, or a name@skills-dir plugin. Each run is an isolated `claude -p` child with only that plugin loaded. Project .claude/, CLAUDE.md and project skills are explicitly not loaded, so plain .claude/skills cannot be evaluated unless they are packaged as a plugin. Cases live in <plugin>/evals/<case>/ with prompt.md and/or case.yaml plus graders/. Runs and llm graders call the model and cost usage. For a single skill, the skill-creator plugin is a separate install with its own incompatible evals/evals.json format.
  - evidence: https://code.claude.com/docs/en/plugin-evals.md#how-runs-are-isolated
- **skill-supporting-files-01** [confirmed] Skills support bundled reference files in skill directory: referenced as relative paths from SKILL.md or using ${CLAUDE_SKILL_DIR}/file.md. Large reference material should stay under 500 lines in SKILL.md body  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **subagent-model-routing-01** [corrected] Subagent model resolved from: (1) per-invocation parameter, (2) subagent definition model field, (3) CLAUDE_CODE_SUBAGENT_MODEL env var, (4) main conversation model fallback. Project subagents in .claude/agents/ shared via git  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: The order per-invocation > frontmatter > CLAUDE_CODE_SUBAGENT_MODEL > main model applies from v2.1.251. Before v2.1.251, CLAUDE_CODE_SUBAGENT_MODEL came first and overrode both frontmatter and the per-invocation value. Before v2.1.196, setting it to inherit forced the main model. The env var alone does not change the built-in Explore or Plan agents; to force one model on every subagent, also set CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 (v2.1.257+). Desktop sessions (2.1.281) follow the current order; the 2.1.195 PATH CLI follows the old one. Project .claude/agents/ is shared via git: confirmed.
  - evidence: https://code.claude.com/docs/en/sub-agents.md#choose-a-model
- **hooks-posttooluse-01** [confirmed] PostToolUse hook runs after Write or Edit. Can run shell commands with matcher patterns. Supports Windows PowerShell and Bash. Configured in .claude/settings.json hooks block. Committed settings shared across team  
  src: https://code.claude.com/docs/en/hooks-guide.md (official-docs)
- **claude-md-hierarchy-01** [corrected] CLAUDE.md files load in precedence: project root CLAUDE.md, nested CLAUDE.md in subdirectories. Keep root under 200 lines. Complex rules can move to .claude/rules/ with optional path-based activation (paths: frontmatter)  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: CLAUDE.md files are concatenated, not ranked by precedence. At launch Claude Code loads the managed file, ~/.claude/CLAUDE.md, and CLAUDE.md plus CLAUDE.local.md in the working directory and every ancestor, ordered from the root down. CLAUDE.md files in subdirectories load on demand when Claude reads files there. The docs target under 200 lines per CLAUDE.md file; KICKOFF sets 150 or fewer for the root. .claude/rules/**/*.md, found recursively, load at launch unless they have paths: frontmatter, in which case they load only when Claude works on matching files.
  - evidence: https://code.claude.com/docs/en/memory.md#how-claude-md-files-load
- **version-requirement-claude-code-01** [refuted] Claude Code v2.1.195 used by prime-game team. Plugin eval available >=2.1.210 with stable --json output. Context: fork for skills requires v2.1.218+. Check version with claude --version  
  src: https://code.claude.com/docs/en/quickstart.md (inferred)
  - CORRECTED: The humans' Desktop Code-tab sessions run the app's embedded Claude Code. On this machine that is 2.1.281 (CLAUDE_CODE_EXECPATH=%APPDATA%\Claude\claude-code\2.1.281\claude.exe, CLAUDE_CODE_ENTRYPOINT=claude-desktop, app 2.9939.2). Only the standalone `claude` on PATH (~/.local/bin) is 2.1.195, released 2026-06-26. claude plugin eval needs v2.1.269, not 2.1.210. context: fork has existed since v2.1.0; only background needs v2.1.218. `claude --version` in the agent's shell reports the PATH binary, not the running session. Use `& $env:CLAUDE_CODE_EXECPATH --version` or Help > About instead.
  - note: Local test: `claude --version` printed 2.1.195 and `$CLAUDE_CODE_EXECPATH --version` printed 2.1.281. The desktop docs confirm the app runs an 'embedded CLI' (https://code.claude.com/docs/en/desktop.md).
  - evidence: https://code.claude.com/docs/en/changelog.md

## Missed facts (from verifier)

- **mf-embedded-version** Desktop Code-tab sessions run an embedded Claude Code (2.1.281 here) that is separate from the `claude` on PATH (2.1.195). Version gates must be checked against the embedded binary on each human's machine. Any `claude ...` CLI command an agent runs from its shell, such as plugin validate or plugin eval, hits the stale 2.1.195 unless it calls $CLAUDE_CODE_EXECPATH or the PATH CLI is updated. `doctor` should report both versions.  
  src: https://code.claude.com/docs/en/desktop.md#shared-configuration
- **mf-validate-skills** `claude plugin validate .claude/skills` (v2.1.233+) lints bare project skills and exits 1 on a SKILL.md whose YAML fails to parse. Tested with 2.1.281: it caught a malformed file and exited 1. It does not flag unknown or misspelled field names, even with --strict. The 2.1.195 PATH CLI rejects the directory with 'No manifest found'.  
  src: https://code.claude.com/docs/en/skills.md#skill-not-triggering
- **mf-injection-abort** !`cmd` injections never prompt. Outside auto mode, a command that permission rules or allowed-tools do not allow aborts the whole skill invocation, and Claude never sees the skill. A non-zero exit also aborts, except exit 1 from search and compare commands. With shell omitted and Git Bash installed, injections run through the Bash tool.  
  src: https://code.claude.com/docs/en/skills.md#permission-checks-on-injected-commands
- **mf-powershell-rules** On Windows, when the PowerShell tool is enabled, Claude treats PowerShell as its primary shell. Bash(...) permission and allowed-tools rules do not match PowerShell-tool calls, which need PowerShell(...) rules of the same shape. The PowerShell tool splits compound commands on `;` and `|`, and each subcommand must match a rule.  
  src: https://code.claude.com/docs/en/permissions.md#powershell
- **mf-personal-shadowing** Among the enterprise, personal and project locations, the higher one wins: a personal ~/.claude/skills/<name> overrides the committed project skill with the same name, silently.  
  src: https://code.claude.com/docs/en/skills.md#resolve-skills-that-share-a-name
- **mf-worktrees** Desktop parallel sessions use git worktrees under <repo>/.claude/worktrees/ by default, so .gitignore must cover them. A worktree loads the .claude/skills of its own checkout. On Windows, .claude/settings.local.json (where GODOT_BIN and GDTOOLKIT_DIR live) is not shared from the main checkout, so new worktrees lack those env vars unless .worktreeinclude lists the file.  
  src: https://code.claude.com/docs/en/settings.md#where-claude-code-keeps-the-local-file-in-a-git-repository
- **mf-fork-no-history** A context: fork skill runs with only the SKILL.md text as its prompt and no conversation history. It runs in the background by default with a narrower tool set, and its edits are outside checkpoints, so /rewind cannot undo them.  
  src: https://code.claude.com/docs/en/skills.md#run-skills-in-a-subagent
- **mf-dmi-blocks-agent** With disable-model-invocation: true, Claude cannot invoke the skill. If it tries, Claude Code blocks the call and tells it not to reproduce the steps another way. The description is also removed from Claude's context, and the skill cannot be preloaded into subagents or run by scheduled tasks.  
  src: https://code.claude.com/docs/en/skills.md#control-who-invokes-a-skill
- **mf-bundled-verify-writes** The bundled /verify (v2.1.200+) writes .claude/skills/verify/SKILL.md at the repo root when it has no recorded recipe, and that file then replaces the bundled /verify. /run-skill-generator commits .claude/skills/run-<name>/.  
  src: https://code.claude.com/docs/en/skills.md#run-and-verify-your-app
- **mf-paths-scoping** The skill `paths:` frontmatter, given as globs, limits automatic loading to work on matching files. It does not stop a user from typing /name.  
  src: https://code.claude.com/docs/en/skills.md#frontmatter-reference

## Options

### Option 1: Committed .claude/skills/ (Recommended)
Place all four shared skills (new-mechanic, new-level-piece, start-task, finish-task) in .claude/skills/ directory at project root. Commit to git. Both humans load them automatically in their independent sessions with zero setup. Simple coordination through GitHub Issues. No versioning or marketplace complexity.
- pros: Simplest to implement and maintain; No setup friction; both humans load automatically on git pull; Skills visible in repo for code review and human approval before merge; Transparent; all rules and commands visible in diffs; Fits existing GitHub-based coordination model; Scales to nested subdirectory skills if needed later; No external dependencies or marketplace infrastructure; Skills can reference supporting docs/files within skill directory
- cons: No version pinning or rollback mechanism (use git tags if needed); All humans always load all skills (cannot selectively disable at team level); Less suitable if skills are reused across multiple unrelated projects; Breaking changes require coordination through PRs
### Option 2: Plugin in .claude-plugin/ with marketplace
Package shared skills in a plugin with .claude-plugin/plugin.json manifest and .claude-plugin/marketplace.json. Commit both to repo. Provides versioning, namespace prefixing (/plugin-name:skill-name), and ability to publish as plugin artifact. More infrastructure.
- pros: Versioning support; each release increments version; Namespace isolation prevents skill name collisions if code reuses plugins; Can publish to internal marketplace for reuse across projects; Plugin can bundle agents, hooks, MCP servers alongside skills; Version pinning in enabledPlugins settings.json; Easier to test and validate as unit with claude plugin eval; Supports usenConfig for user prompts during install
- cons: Adds .claude-plugin/ directory overhead for team coordination; Requires creating and maintaining marketplace.json file; Humans must enable plugin after installing (extra install step); Plugin skills named /plugin-name:skill-name (not /skill-name); More configuration needed for marketplace setup; Overkill if single repo never reuses skills elsewhere; Context footprint: plugin name/description always in Claude context even if not invoked
### Option 3: Mixed approach (Committed skills + local plugins for development)
Keep shared team skills in committed .claude/skills/ for simplicity and transparency. Allow each human to develop local-only plugins under ~/.claude/skills/<name>/ for personal workflow automation and development tooling. Two layers: team-shared skills (transparent, committed) and personal skills (local, not committed).
- pros: Combines simplicity of committed skills with flexibility of local tools; Humans can iterate on personal skills without affecting team; Clear separation of team rules (committed) vs personal tooling (local); Personal skills in ~/.claude/skills/ load in all projects on same machine; No conflict: both layers load together; Humans can share personal skills later by moving to .claude/skills/ if they prove useful to team
- cons: Requires discipline to keep committed vs local skills separate; Personal skills not visible to other human or in code review; No mechanism to enforce team skills (unlike subagent permissionMode); Two different skill locations may cause confusion

## Recommendation

Use Option 1 (Committed .claude/skills/) for the four shared skills: new-mechanic, new-level-piece, start-task, finish-task. This aligns perfectly with the project's coordination model through GitHub and CLAUDE.md hierarchy. Both humans load the same skill files automatically from the repo with zero setup, diffs are transparent for code review before merge, and there is no unnecessary plugin infrastructure overhead. If versioning or multi-project reuse becomes necessary later, the skills can be packaged into a plugin without rewriting them. Start simple: use the .claude/skills/ directory, commit four skill folders (each with SKILL.md and optional supporting files), and update CLAUDE.md to document when each skill is used and any human-facing guidelines. Add PostToolUse hooks to .claude/settings.json to auto-run gdformat/gdlint on .gd files after edits (for the engineer's session). Use .claude/settings.local.json (gitignored) for machine-specific env vars like GODOT_BIN and GDTOOLKIT_DIR (already planned in KICKOFF.md section 6).

## Verifier critique of recommendation

The core recommendation holds up. Four committed .claude/skills folders with no plugin match the docs' guidance for single-repo sharing and reach both humans through git with no install step. Several supporting facts are wrong or missing, though, and the user asked for options rather than decisions, so the choices below should go to the humans for approval instead of being fixed in config.

1. The version premise is wrong. Desktop sessions run 2.1.281; only the PATH CLI is 2.1.195. Version-gated features are available in Desktop, but CLI commands the agent runs from its shell are stale. The proposal should record both versions and have `doctor` report them.

2. The claim that plugin eval can test project skills is false. The real options are (a) a manual with/without-skill baseline in fresh sessions, (b) packaging the skills as a skills-dir plugin so `claude plugin eval` works (costs money), or (c) the skill-creator plugin (a new dependency, also costs money). All of these need human approval under KICKOFF section 0.

3. Windows handling is missing. allowed-tools and allowlists need PowerShell(...) twins. Injections abort when a command is not allowed.

4. Worktree effects are ignored: stale skills per branch, GODOT_BIN missing from new worktrees on Windows, and .claude/worktrees/ needing a gitignore entry.

5. Invocation control needs an explicit decision per skill. finish-task and new-mechanic have side effects. disable-model-invocation: true is safer but blocks autonomous runs.

6. start-task and finish-task must not use context: fork, because they need the conversation history.

7. Skills cannot enforce the designer boundary. The options are CODEOWNERS plus review, and/or Edit deny rules in the designer's personal settings.local.json (e.g. Edit(core/**)). new-mechanic's 'bot scenario' output would land in engineer-owned tests/ unless the scenarios are data files under content/. That needs a decision.

8. Add `claude plugin validate .claude/skills`, run with a 2.1.233+ binary, to lint and CI.

9. Watch for personal-skill shadowing and for bundled /verify writing .claude/skills/verify.

10. Don't restate the skill descriptions in CLAUDE.md. The descriptions are already listed to Claude every turn.

11. The hook is described as being 'for the engineer's session', but committed settings apply to both humans.

## Concrete config (researcher)

.claude/skills/new-mechanic/SKILL.md frontmatter:\n---\nname: new-mechanic\ndescription: Turn mechanic idea into issue, GDD section, Resources, bot scenario, engine-request\nuser-invocable: true\ndisable-model-invocation: false\nargument-hint: \"[mechanic-name]\"\narguments: [mechanic_name]\nallowed-tools: \"Bash(git *) Bash(gh *) Read\"\n---\n\n.claude/skills/new-level-piece/SKILL.md frontmatter:\n---\nname: new-level-piece\ndescription: Guide for building reusable room or interactable sub-scene following level conventions\nuser-invocable: true\ndisable-model-invocation: false\nargument-hint: \"[room|interactable]\"\n---\n\n.claude/skills/start-task/SKILL.md frontmatter:\n---\nname: start-task\ndescription: Read issue, check relevant docs, confirm branch, restate plan\nuser-invocable: true\ndisable-model-invocation: false\nallowed-tools: \"Bash(gh issue view *) Read\"\n---\n\n.claude/skills/finish-task/SKILL.md frontmatter:\n---\nname: finish-task\ndescription: Run definition-of-done checks (lint, tests, bots), write handoff comment, open PR\nuser-invocable: true\ndisable-model-invocation: false\nallowed-tools: \"Bash(tools/verify *) Bash(git *) Bash(gh pr *)\"\n---\n\nIn .claude/settings.json (committed, shared):\n{\n  \"hooks\": {\n    \"PostToolUse\": [\n      {\n        \"matcher\": \"Write|Edit\",\n        \"patterns\": [\"\\\\.gd$\"],\n        \"hooks\": [\n          {\"type\": \"command\", \"command\": \"powershell -NoProfile -Command \\\"& $env:GDTOOLKIT_DIR/gdformat $tool_input.file_path; & $env:GDTOOLKIT_DIR/gdlint $tool_input.file_path\\\"\"}\n        ]\n      }\n    ]\n  },\n  \"skillOverrides\": {\n    \"new-mechanic\": \"on\",\n    \"new-level-piece\": \"on\",\n    \"start-task\": \"on\",\n    \"finish-task\": \"on\"\n  }\n}

## Config corrections (verifier)

Hook block in .claude/settings.json:

(1) "patterns" is not a field. The hook matcher object accepts only "matcher" and "hooks"; the schemastore schema sets additionalProperties:false. Claude Code will show a Settings Error or Warning and skip the entry. Filter the extension inside the script, or add "if": "Edit(*.gd)" per handler, remembering that one if holds one rule.

(2) The command is broken. Hook input arrives as JSON on stdin, and $tool_input does not exist. The command runs under Git Bash by default on Windows, which expands $env and $tool_input to empty strings. Tested: bash turns the command into `& :GDTOOLKIT_DIR/gdformat .file_path`. Run directly under PowerShell, gdformat got a null path and printed its usage text with exit 1.

(3) Lint failures never reach Claude. PostToolUse exit codes other than 2 are non-blocking and hidden from Claude. The hook should exit 2 with the lint output on stderr, or print JSON {"decision":"block","reason":...}.

A working shape, tested locally with PowerShell 5.1 (pwsh is not installed): a committed script .claude/hooks/gd-format-lint.ps1 containing
$p=([Console]::In.ReadToEnd()|ConvertFrom-Json).tool_input.file_path; if($p -notlike '*.gd'){exit 0}; & "$env:GDTOOLKIT_DIR\gdformat.exe" $p *> $null; $o=& "$env:GDTOOLKIT_DIR\gdlint.exe" $p 2>&1; if($LASTEXITCODE){[Console]::Error.WriteLine(($o|Out-String)); exit 2}
registered in exec form:
{"matcher":"Write|Edit","hooks":[{"type":"command","command":"powershell.exe","args":["-NoProfile","-ExecutionPolicy","Bypass","-File","${CLAUDE_PROJECT_DIR}/.claude/hooks/gd-format-lint.ps1"]}]}
Exec form substitutes ${CLAUDE_PROJECT_DIR} inside args. Keep in mind:
- gdformat rewrites the file after Claude's edit, so Claude's view of the file goes stale (confirmed locally: line numbers shifted).
- The hook runs in both humans' sessions and fails without GDTOOLKIT_DIR.
- jq is not installed on this machine.

skillOverrides: remove it. "on" is already the default, so the entries do nothing. The /skills menu writes overrides to settings.local.json anyway.

Frontmatter:
(a) user-invocable: true and disable-model-invocation: false are defaults and only add noise. Whether finish-task and new-mechanic should be human-only is a decision to put to the humans, not a default to hard-code.
(b) Every Bash(...) rule needs a PowerShell(...) twin, because Claude routes commands through PowerShell on Windows.
(c) Scopes are wrong in both directions:
  - new-mechanic: "Bash(gh *)" is far too broad. It pre-approves gh repo delete, gh api and gh pr merge. Narrow it to e.g. Bash(gh issue create *) Bash(gh issue view *) Bash(gh label list *).
  - finish-task: "Bash(gh pr *)" includes gh pr merge. "Bash(git *)" pre-approves push --force and reset --hard, which only settings deny rules still block. The skill also lacks gh issue comment for the handoff.
  - start-task: lacks git branch, git switch and git status for 'confirm branch'.
(d) The finish-task rule "Bash(tools/verify *)" must match the runner's real invocation on Windows, e.g. PowerShell(./tools/run.ps1 verify *) or Bash(tools/run.sh verify *).
(e) "Read" in allowed-tools does nothing, since file reads in the project don't need approval.
(f) Add when_to_use trigger phrases and put the key use case first in each description. Consider paths: levels/** and content/** for the designer skills.
(g) Don't add context: fork to start-task or finish-task.
(h) If start-task injects `!gh issue view $0`, pre-approve it in allowed-tools and make it tolerate failure (e.g. `|| true` under bash). Otherwise a bad issue number aborts the skill.
(i) Add .claude/worktrees/ to .gitignore. List .claude/settings.local.json in .worktreeinclude so Desktop worktree sessions on Windows get GODOT_BIN and GDTOOLKIT_DIR.

## Windows notes

Windows 11 is primary platform. PowerShell 5.1 is available; Bash via Git Bash. Skills shell field can specify powershell or bash (default). Hook commands should use powershell for Windows paths and env vars. For injected commands in skills (! prefix), use forward slashes in paths or use ${CLAUDE_SKILL_DIR} substitution. gdtoolkit is installed at path in GDTOOLKIT_DIR env var (set via .claude/settings.local.json). Godot console exe path in GODOT_BIN env var. Do NOT assume /tmp; use scratchpad or CLAUDE_SKILL_DIR for temp files. Git LFS and .gitattributes already configured. All tool runners and task scripts tested against native Windows Godot binary, not WSL.

## Gotchas

- Skill names in .claude/commands/ are legacy and will not auto-trigger Claude; use .claude/skills/ instead. Do not create both .claude/commands/skill-name.md AND .claude/skills/skill-name/SKILL.md (they can coexist but confuse intent).
- Description character limit is strict at 1,536 combined; plugin eval and skill-creator will reject longer descriptions. Test with claude plugin eval or skill-creator after writing initial text.
- disable-model-invocation: true hides skill from Claude's context entirely; only use for side-effect commands (git, deploy). For domain skills like new-mechanic or new-level-piece, leave false so Claude auto-invokes when relevant.
- Skills load at session start and re-read on file change within session. Changes on disk appear within a session, but hooks/ .mcp.json changes require /reload-plugins. Plugin manifest changes always require restart.
- allowed-tools grant for single invocation turn only; cleared on next user message. For persistent permissions (e.g. always allow Bash for a skill), use .claude/settings.json permissions block instead.
- Nested skills syntax is /parent:child_skill, not /parent/child_skill. Both project root and nested skills can coexist and both load.
- If two humans work in the same project repo simultaneously on different branches (e.g., git worktrees), they share the same .claude/skills/ files. One human's edit to a skill file could affect the other's session if both are running. Mitigate with clear PR process and test skills in personal session first.
- env vars set in .claude/settings.json are inherited by Claude Code tool calls. Personal/machine-specific vars (GODOT_BIN, GDTOOLKIT_DIR) belong in .claude/settings.local.json (gitignored). Committed settings should never include personal paths.
- skill folders support wildcard paths in allowed-tools, e.g. Bash(git *) allows any git subcommand. Be specific to avoid over-permissioning; Bash(*) allows all Bash commands.

## Open questions

- Should new-mechanic and new-level-piece skills be designer-facing only (disable-model-invocation: true for engineer), or fully available to both humans? Answer depends on whether engineer should auto-suggest mechanics/levels.
- How will the designer test and approve skill content before committing? Recommend: developer (engineer) tests in project session, commits as draft PR for designer review, designer runs skill in their session to validate, then approves PR.
- Should start-task and finish-task skills include hardcoded links to specific docs (CLAUDE.md, ARCHITECTURE.md, GDD.md), or reference them dynamically? Hardcoded links are clearer but need updates if docs move.
- Will skills be tested with claude plugin eval as part of definition-of-done? This would verify skill behavior and catch regressions if mechanics/level conventions change. Recommend: create evals/ suite alongside first skill version.
- Should subagents (godot-api-checker, test-runner, code-reviewer, netcode-security-reviewer from KICKOFF section 6) be implemented as separate .claude/agents/ files or deferred to later? These are separate from skills and orthogonal; can be set up in Phase A or deferred to M0 execution.