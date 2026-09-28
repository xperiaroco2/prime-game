# Claude Code operational features: effort, workflows/ultracode, plan mode, context, worktrees, desktop app

## Summary

Research on Claude Code operational features (effort levels, workflows/ultracode, plan mode, context management, worktrees, desktop app) to inform a session protocol and effort policy for two independent humans (engineer and designer) each running their own Claude Code session on Windows 11, coordinating through GitHub Issues/Project board and durable docs, with zero human-authored code.

## Facts (with verification)

- **effort-01** [corrected] Effort levels available: low, medium, high, xhigh, max, and ultracode. Set via /effort <level>, /model picker, or ANTHROPIC_MODEL env var. Ultracode combines xhigh reasoning effort with automatic workflow orchestration.  
  src: https://code.claude.com/docs/en/workflows.md#let-claude-decide-with-ultracode (official-docs)
  - CORRECTED: Model effort levels are low, medium, high, xhigh and max, and which ones you get depends on the model. Opus 4.6 and Sonnet 4.6 have no xhigh, and Haiku does not support effort at all. `ultracode` is a Claude Code setting, not a model effort level: it sends xhigh and has Claude plan a dynamic workflow for each substantive task. You can set effort with /effort <level>, the /model picker slider, the --effort flag, the CLAUDE_CODE_EFFORT_LEVEL env var, the modelSettings/effortLevel settings, or `effort` in skill/subagent frontmatter. ANTHROPIC_MODEL picks the model, not the effort. The effortLevel setting and CLAUDE_CODE_EFFORT_LEVEL do not accept `ultracode` (or max). To keep ultracode on across sessions, use the separate `"ultracode": true` key. /effort ultracode, like max, lasts for the session only.
  - note: The claim named ANTHROPIC_MODEL as the effort variable. That is wrong: the variable is CLAUDE_CODE_EFFORT_LEVEL. If CLAUDE_CODE_EFFORT_LEVEL is set to anything other than xhigh, it also turns ultracode's workflow orchestration off.
  - evidence: https://code.claude.com/docs/en/model-config.md#adjust-effort-level
- **effort-02** [confirmed] Default effort levels: Opus 5.5 defaults to 'medium' (equivalent to or exceeding Opus 5's 'high' in testing); Opus 4.7 defaults to 'xhigh'; all other models supporting effort default to 'high'.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **workflow-01** [confirmed] Dynamic workflows (ultracode mode) orchestrate many subagents from a JavaScript script Claude writes. Triggered by 'ultracode' keyword in prompt or /effort ultracode setting. Runs in background, returns one result instead of turn-by-turn transcript. Agent caps: 16 concurrent by default (configurable), 1000 agents per run max.  
  src: https://code.claude.com/docs/en/workflows.md#orchestrate-subagents-at-scale-with-dynamic-workflows (official-docs)
- **workflow-02** [confirmed] Ultracode keyword only triggers in interactive prompt (human input at CLI/IDE/Remote Control/Agent SDK), not in -p non-interactive mode, scheduled tasks, webhooks, or pull request comments. Keywords marked in input, can dismiss with Alt+W (Windows: Alt+W).  
  src: https://code.claude.com/docs/en/workflows.md#where-the-keyword-works (official-docs)
- **workflow-03** [corrected] Workflow size guideline: unrestricted (default), small (<5 agents), medium (<10 agents, default for Pro v2.1.271+), large (<50 agents). Can be set via /config workflowSizeGuideline=<value> or settings['workflowSizeGuideline']. Larger workflow warning at >25 agents or 1.5M projected tokens.  
  src: https://code.claude.com/docs/en/workflows.md#set-a-size-guideline (official-docs)
  - CORRECTED: Size guideline values: unrestricted (no guideline), small (<5 agents), medium (<10), large (<50). The DEFAULT is medium, or small on a Pro plan with v2.1.271+. Unrestricted was the default only before v2.1.219. You can set it in /config ('Dynamic workflow size'), with `/config workflowSizeGuideline=small` (CLI only), or with the workflowSizeGuideline settings key (v2.1.219+). The settings key overrides /config and hides that row. It is advice to Claude, not a cap. A 'Large workflow' warning appears above 25 agents or 1.5M projected tokens. If you pick a guideline, its agent count replaces the 25 threshold. The warning is never shown while ultracode is on.
  - note: In the Desktop Code tab, /config just opens Settings and ignores any text after it, so `/config workflowSizeGuideline=...` does nothing there (https://code.claude.com/docs/en/desktop.md#whats-not-available-in-desktop).
  - evidence: https://code.claude.com/docs/en/workflows.md#set-a-size-guideline
- **workflow-04** [confirmed] Cost per workflow run: each spawns many agents, so single run can use more tokens than turn-by-turn work. Runs count toward plan usage limits. Suggested approach: test on small slice first to gauge spend before committing to large task.  
  src: https://code.claude.com/docs/en/workflows.md#cost (official-docs)
- **context-01** [corrected] Context window sizes: 200k tokens (standard models), 1M tokens (Fable, Sonnet 5, Opus 4.8+, via [1m] suffix on others). CLAUDE.md loads at session start; auto-memory (first 200 lines or 25KB) loads; MEMORY.md is auto-written by Claude between sessions.  
  src: https://code.claude.com/docs/en/context-window.md (official-docs)
  - CORRECTED: On the Anthropic API, Fable 5.1/5, Sonnet 5, and Opus 4.7 and later (so the default Opus 5.5) run with a native 1M-token window on every plan, including Pro. They auto-compact at about 967K by default. Opus 4.6 and Sonnet 4.6 reach 1M only through their [1m] variant, subject to plan. A 200K window applies on some 3P providers or with CLAUDE_CODE_DISABLE_1M_CONTEXT=1. CLAUDE.md files load at session start. The first 200 lines or 25KB of the MEMORY.md index loads at session start. Claude writes auto memory DURING sessions, and topic files are read on demand.
  - note: The '200k for standard models' framing is out of date for this setup (Desktop, Anthropic API, Opus 5.5 default).
  - evidence: https://code.claude.com/docs/en/model-config.md#extended-context
- **context-02** [corrected] /clear resets full context window; /compact compacts conversation history, keeping latest turns; auto-compaction triggers when context approaches limit. CLAUDE.md is re-read after compaction.  
  src: https://code.claude.com/docs/en/context-window.md (official-docs)
  - CORRECTED: /clear starts a new conversation with empty context. The old one is saved and can be resumed with /resume. /compact [instructions] replaces the conversation with a structured summary. It does not keep the latest turns verbatim; to do that, use /rewind -> 'Summarize up to here'. Auto-compaction runs at the model's context limit (~967K on 1M-window models) unless you set /autocompact. After compaction, the project-root CLAUDE.md, unscoped rules and auto memory are re-injected from disk. Nested CLAUDE.md files and path-scoped rules return only when matching files are read again. The skill listing is not re-injected. Up to 5 recently modified files are re-read.
  - evidence: https://code.claude.com/docs/en/context-window.md#what-survives-compaction
- **context-03** [confirmed] /context command shows interactive view of what loads in context window (system prompt, MCP tools, skills, CLAUDE.md size, etc). Helps diagnose why session is reaching context limit.  
  src: https://code.claude.com/docs/en/context-window.md (official-docs)
- **worktree-01** [confirmed] claude --worktree <name> creates isolated git worktree at .claude/worktrees/<name>/ on new branch worktree-<name>. Each session in own worktree prevents file-edit collisions. Desktop app can create worktree per session.  
  src: https://code.claude.com/docs/en/worktrees.md#start-claude-in-a-worktree (official-docs)
- **worktree-02** [confirmed] .worktreeinclude file (gitignore syntax) copies gitignored files (.env, config/secrets.json, etc.) into each new worktree automatically. Only matches files that are both in pattern and gitignored.  
  src: https://code.claude.com/docs/en/worktrees.md#copy-gitignored-files-into-worktrees (official-docs)
- **worktree-03** [confirmed] EnterWorktree tool allows Claude to switch to existing worktree during session. Exiting moves session back to main checkout. Worktrees created by Claude or --worktree are cleaned up automatically on exit if no work remains; named sessions prompt to keep or remove.  
  src: https://code.claude.com/docs/en/worktrees.md#ask-claude-to-create-a-worktree (official-docs)
- **worktree-04** [corrected] Worktree isolation enforced: Claude Code blocks file edits to main checkout, command working directories outside worktree, git redirects to main, and commands with unparseable git syntax. Blocks prevent accidental cross-session file corruption.  
  src: https://code.claude.com/docs/en/worktrees.md#how-claude-code-enforces-isolation (official-docs)
  - CORRECTED: While a session is in a worktree, Claude Code runs four checks. (1) It blocks Edit/Write/NotebookEdit targeting the main checkout. (2) It blocks Bash/PowerShell/Monitor commands whose working directory resolves to the main checkout, or that it can't verify stay outside it. (3) It blocks Bash/Monitor commands that redirect git into the main checkout (git -C, --git-dir, GIT_DIR/GIT_WORK_TREE, cd). (4) It blocks Bash/Monitor commands whose git usage it can't verify from the text. PowerShell commands get ONLY the working-directory check. The checks also apply to subagents spawned from the isolated session.
  - note: These checks prevent collisions between sessions on the SAME machine. They do nothing about the engineer and designer colliding, because the two work in separate clones.
  - evidence: https://code.claude.com/docs/en/worktrees.md#how-claude-code-enforces-isolation
- **desktop-01** [confirmed] Desktop app on Windows: Integrated terminal panel (Ctrl+backtick), PR monitoring with gh CLI required (auto-fix toggles when gh is installed and authenticated), auto-merge (requires GitHub repo setting first). Terminal runs in session's working directory.  
  src: https://code.claude.com/docs/en/desktop.md (official-docs)
- **desktop-02** [confirmed] Desktop app permission modes on Windows: Manual (asks before actions), Accept edits (auto-accepts file edits + mkdir/touch/mv), Plan (proposes plan without editing), Auto (background safety checks, Opus 4.6+/Sonnet 4.6+ only), Bypass (requires Pro/Max setting). No WSL required for primary Windows support.  
  src: https://code.claude.com/docs/en/desktop.md (official-docs)
- **desktop-03** [corrected] Desktop app worktree sessions: Select 'worktree' option when starting session to give it isolated git worktree. Desktop creates one per session automatically. PR monitoring available in worktree sessions too.  
  src: https://code.claude.com/docs/en/worktrees.md (official-docs)
  - CORRECTED: Desktop does NOT create a worktree for every session automatically. For a git repo you pick the 'worktree' option next to the branch name when you start a session. The default location is <project-root>/.claude/worktrees/, which you can change under Settings -> Claude Code -> 'Worktree location'. There is also an optional branch prefix. You remove a worktree by archiving the session. After a PR is opened, the session shows a CI status bar with Auto-fix/Auto-merge.
  - evidence: https://code.claude.com/docs/en/desktop.md#work-in-parallel-with-sessions
- **codereview-01** [corrected] /code-review command (local): Reviews current branch's diff at effort levels low/medium/high. Runs as background subagent in isolated context. Flags correctness bugs, reuse, simplification, efficiency. Reuses last effort level typed (low-max), or uses session effort if never typed.  
  src: https://code.claude.com/docs/en/code-review.md#review-a-diff-locally (official-docs)
  - CORRECTED: /code-review [low|medium|high|xhigh|max|ultra] [--fix] [--comment] [target] reviews your branch's commits ahead of upstream plus any uncommitted changes, or a PR number/branch/path/ref range you pass. It runs as a background subagent with its own context. It reports correctness bugs, and reuse/simplification/efficiency cleanups depending on model and effort. low and medium report only high-confidence findings; high through max cover more ground. With no level given, it reuses the last low-max level you typed, or the session effort if you never typed one. In Desktop the findings come back as a ReportFindings list.
  - note: The claim listed only low/medium/high; xhigh, max and ultra also exist. /review is an alias. The local review follows CLAUDE.md but does not read REVIEW.md.
  - evidence: https://code.claude.com/docs/en/code-review.md#review-a-diff-locally
- **codereview-02** [confirmed] /code-review ultra escalates to cloud review (ultrareview) on Anthropic infrastructure. Requires claude.ai account, not available on Bedrock/Vertex/Foundry. Can post findings to GitHub PR with --post flag (v2.1.227+). Returns deeper analysis than local review.  
  src: https://code.claude.com/docs/en/code-review.md#escalate-to-ultrareview (official-docs)
- **codereview-03** [confirmed] /code-review --fix applies findings to working tree after review. /code-review --comment posts findings on GitHub PR as inline comments or single note on GitLab. Works locally without Code Review service.  
  src: https://code.claude.com/docs/en/code-review.md#tune-effort-and-arguments (official-docs)
- **codereview-04** [corrected] /security-review is a separate skill (mentioned in /skills) for security-focused review. Code Review (GitHub service, managed) and /code-review (local command) are distinct; local requires no setup, GitHub service requires admin enablement.  
  src: https://code.claude.com/docs/en/code-review.md (official-docs)
  - CORRECTED: /security-review is a built-in command (the commands reference does not mark it as a bundled Skill). It reviews the diff between your branch and origin's default branch for security issues and needs an `origin` remote. The managed Code Review GitHub service is a research preview for Team/Enterprise only. An Owner enables it at claude.ai/admin-settings. It costs about $15-25 per review, billed as usage credits, and is unavailable with ZDR. Local /code-review needs no setup.
  - evidence: https://code.claude.com/docs/en/commands.md
- **github-actions-01** [confirmed] anthropics/claude-code-action runs Claude Code in GitHub Actions. Setup via /install-github-app (quick) or manual (install app, add secret ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN, copy workflow.yml). Requires GitHub CLI (gh) and auth.  
  src: https://code.claude.com/docs/en/github-actions.md#setup (official-docs)
- **github-actions-02** [confirmed] GitHub Actions modes: Interactive (responds to @claude mentions in issues/PRs) or Automation (runs on cron/event with prompt input). Cost: GitHub Actions minutes (GitHub's billing) + API tokens (Claude billing). Can set --max-turns and other CLI args in claude_args to control per-run cost.  
  src: https://code.claude.com/docs/en/github-actions.md#interactive-and-automation-modes (official-docs)
- **github-actions-03** [corrected] GitHub App permissions: Contents (read/write), Issues, Pull requests, Workflows, Checks, all read by default but Claude Code Action needs write. Shared by Code Review and web auto-fix. Single permission set for all Claude features.  
  src: https://code.claude.com/docs/en/github-actions.md#github-app-permissions (official-docs)
  - CORRECTED: The official Claude GitHub App asks for one fixed set of permissions, and you cannot accept only part of it. The set is: Actions RW, Checks RW, Contents RW, Discussions RW, Issues RW, Members R, Metadata R, Pull requests RW, Repository hooks RW, Statuses R, Workflows RW. The Action itself relies on Contents, Issues and Pull requests RW. The app is shared with Code Review and web auto-fix. For narrower permissions, create a custom app (Action only).
  - note: 'All read by default' is wrong: most of these permissions are read/write.
  - evidence: https://code.claude.com/docs/en/github-actions.md#github-app-permissions
- **memory-01** [corrected] CLAUDE.md loads at session start from working directory up to repository root (additive hierarchy). Nested CLAUDE.md in subdirectories load as Claude accesses those files. Keep root CLAUDE.md under 200 lines; move reference material to skills.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: At launch, Claude Code loads CLAUDE.md and CLAUDE.local.md from the working directory and EVERY ancestor directory. It does not stop at the repo root, so a D:\CLAUDE.md would load too. The files are concatenated root-first. CLAUDE.md files in subdirectories load on demand when Claude reads files there. The docs aim for under 200 lines per file; KICKOFF sets a stricter ≤150. Move reference material to skills or path-scoped rules. @imports do not save context, because they load at launch.
  - evidence: https://code.claude.com/docs/en/memory.md#how-claude-md-files-load
- **memory-02** [confirmed] .claude/rules/ directory allows path-scoped rules (with frontmatter 'paths' field) to reduce context bloat. Rules load only when Claude works with matching files. Supports language-specific and directory-specific guidelines.  
  src: https://code.claude.com/docs/en/memory.md#organize-rules-with-claude/rules/ (official-docs)
- **memory-03** [corrected] Auto memory (MEMORY.md): Claude writes notes to itself between sessions (first 200 lines or 25KB loaded). Captures build commands learned, patterns noticed, mistakes to avoid. Persists across sessions same project, automatically curated.  
  src: https://code.claude.com/docs/en/memory.md#auto-memory (official-docs)
  - CORRECTED: Auto memory is on by default. Claude writes it DURING sessions, as typed notes (user, feedback, project, reference) under ~/.claude/projects/<project>/memory/ with a MEMORY.md index. It skips anything it can derive from the code (architecture, file paths, debugging fixes) and anything already in CLAUDE.md. The first 200 lines or 25KB of the index loads; topic files are read on demand. Memory is machine-local: shared across worktrees of the repo on one machine, but NOT across machines or between the two humans.
  - evidence: https://code.claude.com/docs/en/memory.md#auto-memory
- **subagent-01** [confirmed] Subagents are markdown files in .claude/agents/ with YAML frontmatter (name, description, model, tools, permissionMode). Can run in isolated context with own system prompt. Tool allowlist via 'tools:' field, model via 'model:' field. Built-in agents: Explore (read-only), Plan (read-only), General-purpose.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **subagent-02** [confirmed] Subagent model routing: per-invocation param > subagent definition > CLAUDE_CODE_SUBAGENT_MODEL env > main session model. Can force all subagents to one model with CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1.  
  src: https://code.claude.com/docs/en/sub-agents.md#model-routing (official-docs)
- **subagent-03** [confirmed] Subagents with isolation: worktree automatically runs in separate git worktree. Each gets temporary worktree removed auto on completion; worktrees with work stay on disk. Subagent worktrees use same base branch (default or 'head') as main --worktree.  
  src: https://code.claude.com/docs/en/worktrees.md#isolate-subagents-with-worktrees (official-docs)
- **session-01** [corrected] Session resumption via --resume finds most recent session from launch directory. Named sessions can be resumed explicitly. Checkpointing via /checkpoint and /rewind stores/restores session state within a conversation.  
  src: https://code.claude.com/docs/en/sessions.md (official-docs)
  - CORRECTED: `claude --continue` reopens the most recent conversation in the current directory. `claude --resume` opens a picker, or resumes by name/ID/transcript path. `--from-pr` filters to sessions linked to a PR. Checkpoints are AUTOMATIC: one per prompt that starts a turn, 100 kept. /rewind opens the restore/summarize menu, and /checkpoint and /undo are just aliases of it. Checkpoints do not track Bash-made file changes or most subagent edits. Desktop keeps its own session history; /resume inside Desktop can pick up CLI sessions.
  - evidence: https://code.claude.com/docs/en/checkpointing.md
- **claude-code-version** [corrected] Current Claude Code version in this environment: 2.1.195. Many features (workflows, ultracode keyword, worktree syncing, desktop app details) added in versions >= 2.1.195.  
  src: local-test: claude --version (local-test)
  - CORRECTED: There are two Claude Code builds on this machine. The CLI on PATH (~/.local/bin/claude) is v2.1.195 (June 26, 2026). The Desktop app runs its bundled v2.1.281 (%APPDATA%\Claude\claude-code\2.1.281\claude.exe), and this Desktop session is running on it. Workflows (v2.1.154) and the ultracode keyword (v2.1.160) are OLDER than 2.1.195. Many features the proposal relies on need a newer version: Opus 5.5 (2.1.280), --effort ultracode (2.1.203), the workflowSizeGuideline key (2.1.219), the keyword-origin fix (2.1.210), CLAUDE_CODE_SUBAGENT_MODEL_FORCE (2.1.257). The PATH CLI lacks all of them. The newest release is 2.1.283.
  - note: Checked locally: `claude --version` gives 2.1.195; `%APPDATA%/Claude/claude-code/2.1.281/claude.exe --version` gives 2.1.281; the running process path is ...\claude-code\2.1.281\claude.exe.
  - evidence: https://code.claude.com/docs/en/changelog.md
- **tools-01** [corrected] Built-in tools (available in all Claude Code sessions): Read, Write, Edit, Bash (PowerShell on Windows), Glob, Grep, WebSearch, WebFetch. MCP tools connect to external services. Subagents filter which tools they can use.  
  src: https://code.claude.com/docs/en/how-claude-code-works.md (official-docs)
  - CORRECTED: Built-in tools include Read, Write, Edit, Bash, PowerShell, Glob, Grep, WebFetch, WebSearch, Agent, LSP, Monitor, Workflow, EnterWorktree/ExitWorktree, TodoWrite, Skill and others. On Windows, PowerShell is a SEPARATE tool, and the primary shell for claude.ai accounts. Bash (Git Bash) stays available for POSIX scripts. Glob/Grep are present on Windows but absent by default on macOS/Linux/WSL. LSP stays inactive until a code-intelligence plugin is installed. Permission rules and hook matchers name these tools exactly, e.g. PowerShell(...) is separate from Bash(...).
  - evidence: https://code.claude.com/docs/en/tools-reference.md#powershell-tool
- **hooks-01** [confirmed] Hooks (in .claude/settings.json): PostToolUse (run after tool), PreToolUse (block/allow before tool), SessionStart/SessionEnd (on lifecycle), WorktreeCreate/WorktreeRemove. Can run shell commands, HTTP requests, MCP tools, LLM prompts, or spawn subagents.  
  src: https://code.claude.com/docs/en/hooks-guide.md (official-docs)
- **permissions-01** [corrected] Permission allowlist/denylist in .claude/settings.json. Can pre-approve routine commands (git, task runner, gdformat) to reduce approval prompts. Deny or require confirmation for: force-push, push to main, deletes outside tools/out/, .github/workflows edits without mention.  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
  - CORRECTED: allow/ask/deny rules in .claude/settings.json can pre-approve routine commands. The syntax is Tool(specifier) with `*` globs, not regex. Bash and PowerShell need SEPARATE rules. Path rules use Edit(...)/Read(...) with gitignore-style patterns; Write(path) rules are never consulted. A condition like 'without mention in the plan' cannot be expressed as a rule, so use an `ask` rule. Bash deny rules match only the command text: `git -C . push` bypasses Bash(git push *). They are not a security boundary, so enforce 'no push to main' with GitHub branch protection.
  - evidence: https://code.claude.com/docs/en/permissions.md#permission-rule-syntax
- **plan-mode-01** [corrected] Plan mode (Shift+Tab in desktop app, /plan command, or --plan CLI flag): Claude explores, gathers context, proposes a plan without editing code. Useful for design-before-code. ExitPlanMode command exits plan mode to begin implementation.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: You can enter plan mode by: Shift+Tab (CLI and JetBrains terminal only, not the Desktop app); a /plan [description] prefix; the Desktop mode selector (Ctrl+Shift+M), where Plan lasts for the current session only; or `claude --permission-mode plan`. There is no --plan flag. You can also set defaultMode 'plan'. ExitPlanMode is the TOOL Claude calls to present the plan for approval; it is not a user command. You exit by approving (Yes + a mode) or by switching mode. showClearContextOnPlanAccept adds 'approve and clear context'.
  - evidence: https://code.claude.com/docs/en/permission-modes.md#analyze-before-you-edit-with-plan-mode
- **model-selection-01** [corrected] Current recommended models (2026-09): Fable (best for complex reasoning), Opus 5.5 (complex tasks, medium default effort), Sonnet 5 (daily coding), Haiku 4.5 (simple tasks). All support low/medium/high/xhigh/max effort. Fable also supports ultracode.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
  - CORRECTED: Anthropic API aliases today: opus = Opus 5.5 (the `default` on Pro/Max/Team/Enterprise, default effort medium), sonnet = Sonnet 5 (native 1M), fable = Fable 5.1 (most capable; never the default; may bill usage credits). Haiku is the fast model but does NOT support effort. Effort (low-max, including xhigh) works on Fable 5.1/5, Opus 5.5/5/4.8/4.7 and Sonnet 5. Ultracode works on ANY model that supports xhigh; it is not Fable-specific.
  - evidence: https://code.claude.com/docs/en/model-config.md#model-aliases

## Missed facts (from verifier)

- **mf-01** The Desktop Code tab runs its own bundled Claude Code (v2.1.281), while the `claude` on PATH is v2.1.195. Running `claude --worktree` or `claude --effort ultracode` from a terminal therefore uses the old CLI. That CLI cannot run Opus 5.5 (needs 2.1.280), has no --effort ultracode (2.1.203), ignores workflowSizeGuideline (2.1.219), and still lets the ultracode keyword fire from non-human input (fixed in 2.1.210). The session protocol should say Desktop is the canonical surface, or tell humans to run `claude update` before using the CLI.  
  src: https://code.claude.com/docs/en/model-config.md#available-models
- **mf-02** On Windows, Claude Code does not resolve .claude/settings.local.json to the main checkout. The file stays in the session's own directory, so a new worktree session will not see the gitignored settings.local.json. GODOT_BIN, PYTHON_BIN and GDTOOLKIT_DIR are then missing. Fixes: list `.claude/settings.local.json` in .worktreeinclude, which only copies gitignored files; or set the variables in Desktop's local environment editor or as Windows user environment variables. Desktop inherits user/system env on Windows. Also, a settings.local.json created by hand, as this one was, is NOT auto-excluded from git, so add it to .gitignore.  
  src: https://code.claude.com/docs/en/settings.md#where-claude-code-keeps-the-local-file-in-a-git-repository
- **mf-03** The docs give concrete rules for when to /clear. Run /clear between unrelated tasks. If you have corrected Claude more than twice on the same issue, /clear and restart with a better prompt. After an interview or spec session, execute the spec in a fresh session. `showClearContextOnPlanAccept: true` adds a plan-approval option that clears the planning context and implements from the plan alone. /clear is reversible via /resume. Use /btw for side questions that shouldn't enter context.  
  src: https://code.claude.com/docs/en/best-practices.md#manage-your-session
- **mf-04** /effort ultracode applies to the WHOLE session: every substantive request can become several workflows. While it is on, the Large-workflow warning is off, the concurrent-subagent cap is not enforced, and auto mode skips the first-launch approval. It lasts for the session; drop back with /effort high. To run a single task as a workflow, use the per-prompt `ultracode:` keyword instead. On Pro, workflows must first be turned on in /config, and the default size guideline there is small.  
  src: https://code.claude.com/docs/en/workflows.md#let-claude-decide-with-ultracode
- **mf-05** Ways to keep workflow output reviewable. A workflow cannot take user input mid-run, so for sign-off between stages (design, then implement, then verify), run each stage as its own workflow. Each run's script is saved under ~/.claude/projects/<session>/. Press `s` in /workflows to save it to the project's .claude/workflows/ (committed and reviewable, rerun as /<name>). Desktop shows an approval card with the phase list and Once/Always/Deny, plus a Background tasks pane. Workflow and subagent edits are NOT covered by /rewind checkpoints, so use git and a separate worktree. Use /code-review in a fresh subagent as the independent verification step. Tell the reviewer to flag only correctness or requirement gaps, so it doesn't push toward over-engineering.  
  src: https://code.claude.com/docs/en/workflows.md#approve-the-plan-before-it-runs
- **mf-06** Desktop-specific differences. Shift+Tab and other terminal shortcuts do not work in Desktop. Use Ctrl+Shift+M for the permission-mode menu, Ctrl+Shift+E for the effort menu and Ctrl+Shift+I for the model menu. /config ignores text after it, so /config key=value does nothing. /permissions replies 'isn't available in this environment', so edit settings files instead. Agent teams are CLI-only. The worktree option has to be picked per session. Settings -> Claude Code offers a worktree branch prefix, a worktree location, and auto-archive after PR merge.  
  src: https://code.claude.com/docs/en/desktop.md#whats-not-available-in-desktop
- **mf-07** Worktrees created by --worktree, Desktop or `isolation: worktree` branch from origin's default branch ('fresh') and are named worktree-<name>. That conflicts with KICKOFF's `<area>/<issue>-<slug>` naming. They also do not include unpushed work unless worktree.baseRef is 'head' (it cannot be a branch name). Reusing a name reopens the old worktree, or resets it if it was merged and clean. To get correctly named branches, either `git worktree add ../x -b <area>/<issue>-<slug>` and open that folder, or set Desktop's branch prefix and rename the branch before the PR.  
  src: https://code.claude.com/docs/en/worktrees.md#choose-the-base-branch
- **mf-08** If Git LFS is installed with `git lfs install --local`, worktrees that Claude Code creates contain LFS pointer files, not the real assets, because Claude Code skips repo-local filter drivers; run `git lfs pull` inside the worktree. A global `git lfs install` avoids this. The global git config on this machine currently has no filter.lfs entry. Separately, a fresh worktree has no .godot/ import cache, because it is gitignored. Godot headless tests will likely need an import pass (e.g. `--headless --import`) before they run; this last point is inferred from Godot behaviour, not from the Claude docs.  
  src: https://code.claude.com/docs/en/worktrees.md#git-lfs-content-is-missing-from-a-worktree-claude-code-created
- **mf-09** On Windows the PowerShell tool is the primary shell, and Bash(...) rules do not cover it. Every allow/deny/ask rule needs a PowerShell(...) twin; aliases are canonicalized and matching is case-insensitive. Hooks that inspect shell commands must match `Bash|PowerShell`. Command hooks run in Git Bash by default when it is installed; set `shell: powershell` to change that. Worktree isolation gives PowerShell only the working-directory check, with no git-redirect check. Remove-Item has its own built-in checks: wildcards and system paths are always denied.  
  src: https://code.claude.com/docs/en/tools-reference.md#powershell-tool
- **mf-10** Claude Code ships bundled skills named /doctor and /verify (plus /run and /run-skill-generator). KICKOFF's task-runner commands are also called `doctor` and `verify`. A protocol line such as 'run doctor first' is ambiguous: a human typing /doctor gets Claude Code's setup checkup, not the project's. A project skill named `verify` or `doctor` would REPLACE the bundled one. Always write the full command, e.g. `"$PYTHON_BIN" tools/task_runner.py doctor`, or give the project skills distinct names such as start-task and finish-task.  
  src: https://code.claude.com/docs/en/skills.md#bundled-skills

## Options

### Option A: Medium-Effort Foundation with Planned Ultracode Escalation
Start all sessions at /effort high (or medium for Opus 5.5) by default. Use ultracode mode (workflows, xhigh) only for explicitly planned foundation work (M0 setup, architecture design, large refactors, cross-verification tasks). Non-foundation work (content, small features, bug fixes) stays at high or medium to conserve tokens. Designer's sessions default to medium for exploration.
- pros: Lower baseline token cost and faster feedback for routine work; Preserves ultracode budget for high-impact tasks where multi-agent reasoning adds most value; Clear protocol: foundation work = ultracode, everything else = high/medium. Humans know when to expect long runs.; Easier to track spending if ultracode is only on explicitly-planned tasks; Matches KICKOFF.md Phase A guidance: ultracode for research, M0, core architecture; high for everyday work; medium for docs/content/routine; Designer agent can run medium-effort design tasks without token pressure, focusing on content ideation/iteration
- cons: Requires discipline: agent must recognize foundation work vs routine and set effort appropriately, or humans must set it via /effort each session; Medium-effort tasks may need multiple turns; high-effort gives faster convergence on complex problems; If humans forget to set effort for a foundation task, it runs at default (high), missing the intended ultracode reasoning
### Option B: High-Effort Default with Ultracode Gates
All sessions start at /effort high (or medium for Opus 5.5). Ultracode mode is opt-in: only triggered by explicit 'ultracode' keyword in prompt, or /effort ultracode command before a task. No automatic workflows. Agent recognizes when prompt includes 'ultracode' keyword and writes a workflow script instead of turn-by-turn work.
- pros: High as default accelerates most work (architecture, netcode, complex features). Foundation still gets reasonable reasoning.; Ultracode is explicit and intentional: keyword in prompt ensures human oversight.; Halfway point between low-cost and high-cost. Most work is rich but not workflow-orchestrated.; Matches typical Claude Code usage: high is the standard productive effort; No session startup delay from setting effort; humans can still opt into ultracode when needed
- cons: High-effort costs more tokens than medium, so daily work (docs, content iteration, small fixes) is more expensive; Humans may overuse ultracode keyword if they think 'big task' = workflow, not just 'task that benefits from multi-agent cross-check'; No default ultra-reasoning for M0 (humans would need to request ultracode explicitly for M0 execution)
### Option C: Session-Specific Effort Policy (Flexible Per-Task)
No single default effort. Engineer sets effort based on task: /effort medium for quick fixes, /effort high for core work, /effort ultracode for M0/architecture/audits. Designer does the same for content iteration. CLAUDE.md documents when to use each. Agent is taught to suggest effort level based on task complexity when human hasn't set one.
- pros: Maximum flexibility: each task gets the right effort level for its scope; No token waste on overkill or underinvestment per task; Humans can experiment and learn what effort suits their needs; Matches modern Claude Code best practice: choose effort per session based on task
- cons: Requires discipline and knowledge from both humans: they must decide effort each time or set it via /config; No clear protocol; inconsistent choices lead to unpredictable costs and speed; Agent cannot easily predict which effort to use, leading to either over-specification or wasted turns; More cognitive load on humans: 'should this be high or xhigh?'; Harder to track spending and predict runway
### Option D: Framework-Driven Workflow Orchestration (Superpowers or GSD)
Install Superpowers or GSD plugin/framework to structure agent work automatically. Framework handles orchestration, staging, handoffs, and cost tracking. Agent learns framework's task description language and produces consistent output structure. Framework may integrate with workflows automatically.
- pros: Repeatable structure: every task follows same stages (plan, implement, verify), reducing ad-hoc decisions; Built-in cost and progress tracking; Clearer handoff between sessions (engineer → designer, or across branches); Framework enforces 'design before code' pattern KICKOFF.md wants; Workflow output is inherently cleaner if framework shapes it
- cons: Additional complexity: learn framework, maintain framework configuration, debug framework issues; Token overhead: framework prompts and structure add to every session; Framework may dictate effort levels; less flexible than direct /effort control; GitHub Issues + ADR docs are already the source of truth per KICKOFF.md §5; framework adds a competing layer if not carefully scoped; Superpowers/GSD are not lightweight; may be overkill for a two-person project; Maintenance burden: frameworks change monthly; need to keep up
### Option E: Worktree-Per-Task (Parallel Sessions) + Coordination via Cross-Session Messaging
Engineer and designer each use --worktree for every issue, so work is isolated per-branch. Use cross-session messaging (SendMessage tool) for findings that need to move from one human's session to the other's. No attempt to coordinate live; instead, each human pushes results to shared repo, and the other fetches and resumes in their own worktree.
- pros: Complete file-level isolation: zero risk of one session's edits colliding with the other's; Matches git workflow: feature branches, PRs, reviews. Each worktree = one issue/branch.; Scales: if a third human joins, or agents need to work in parallel, worktrees handle it; Desktop app can create per-session worktrees automatically; Cleanup automatic for short-lived worktrees; named sessions prompt to keep or remove
- cons: Adds overhead: each session starts a fresh worktree, fetches dependencies, imports Godot, etc.; Periodic cleanup sweep may remove old worktrees after cleanupPeriodDays; need to monitor retention; Windows: symlinks in worktree path break isolation; requires careful .gitignore setup; Cross-session messaging is one-way per message; full back-and-forth is slower than shared context; Git LFS pointer files in worktree instead of real files unless git lfs pull is run first (minor; documented workaround)
### Option F: Subagent Specialists for Owned Areas (Engineer Subagents for Core, Designer Subagents for Content)
Engineer creates subagents for specialized work: `godot-api-checker`, `netcode-reviewer`, `test-runner`, etc. Designer creates subagents for content authoring: `mechanics-designer`, `level-builder`, etc. Each subagent is pre-tuned with specific model, tools, and rules. When needed, agent spawns the appropriate subagent instead of doing all work in main session.
- pros: Specialization: each subagent knows its domain (netcode security, mechanics balancing) without main agent forgetting; Cleaner main session: exploration and implementation keep separate contexts; main window doesn't fill with search results; Tool isolation: content designer's subagents don't have access to code-write tools; core reviewer subagents are read-only; Model routing: cheaper models for routine work (haiku for godot-api-check), expensive models for complex reasoning (opus for netcode-reviewer); Reusable across tasks: once defined, subagent can be invoked many times with consistent behavior
- cons: Setup overhead: write 4–6 subagent definitions, tune model/tools per each, test; Maintenance burden: as domain knowledge evolves (new Godot API, new content mechanic), update subagent system prompts; Subagents in foreground block main conversation (unless 'background' flag); background subagents have restricted tools; Subagent can still overflow context if given hundreds of files; not a panacea for large codebases; Requires discipline: agent must recognize when to spawn subagent vs do work inline

## Recommendation

**Option A (Medium-Effort Foundation with Planned Ultracode Escalation) + Option E (Worktree-Per-Task) + partial Option F (light subagent setup for core reviewers and content verification)**

**Why this combination for prime-game:**

1. **Effort Policy (Option A)**: Start at /effort high (or medium for Opus 5.5). Reserve ultracode mode explicitly for M0 setup, core architecture design, large refactors, and cross-checked audits (e.g., netcode security, information leaks). Rationale:
   - M0 is the foundation: maximum reasoning and multi-agent verification justified.
   - Everyday core work (M1+ features, netcode increments, voice pipeline) at high effort is fast and thorough.
   - Designer's content work (mechanics, level design) at medium is cost-efficient for iterative ideation.
   - Matches KICKOFF.md §10 guidance exactly.
   - Tokens stay predictable; humans know when to expect long runs (M0, architecture reviews).

2. **Worktree Strategy (Option E)**: Enforce --worktree per issue (or manually git worktree add). Rationale:
   - Engineer and designer never collide on files; each worktree is a git feature branch.
   - Matches trunk-based workflow (KICKOFF.md §5.4).
   - Desktop app creates worktrees automatically per session.
   - GitHub Issues/PRs are already the coordination point; worktrees just isolate file edits.
   - Scales to parallel work (engineer on M2 core while designer builds M1 mechanics).

3. **Light Subagent Setup (partial Option F)**: Define 2–3 subagents in .claude/agents/:
   - **`netcode-security-reviewer`**: read-only model (sonnet), system prompt tuned for host-authority, intent validation, per-peer filtering, information leaks. Pre-approved by KICKOFF.md §6.
   - **`test-runner`**: cheap model (haiku), runs test/lint/bot commands, returns only failures.
   - **`content-verifier`** (for designer): reads mechanics spec, checks consistency with resources (data-driven design from KICKOFF.md §3.4).
   
   Rationale: These are natural bottleneck specialists. Engineer doesn't run netcode review himself every time; spawns reviewer subagent. Designer doesn't hand-verify every mechanic; spawns verifier. Keeps main context clean.

4. **Session Protocol**:
   - Each session: run `doctor` first, read issue, read relevant CLAUDE.md + ARCHITECTURE.md, confirm branch/worktree.
   - Engineer: `/effort high` for core/net/voice work; `/effort ultracode` only for M0, architecture decisions, large audits.
   - Designer: `/effort medium` for content iteration; `/effort high` for GDD updates or new mechanic prototypes.
   - End: `verify` locally, handoff comment with decisions, open PR from worktree branch.
   - No GitLab/Superpowers; GitHub Issues + durable docs remain sole coordination channel.

5. **Windows-Specific Adjustments**:
   - Terminal panel (Ctrl+backtick) in desktop app available; use it for running `doctor`, git status, test output.
   - PR monitoring: install gh CLI, authenticate once. Desktop app can auto-fix CI on PRs if toggled.
   - Worktrees: ensure .claude/worktrees/ is in .gitignore; no symlinks in worktree paths to avoid isolation breaks.
   - Godot console exe path in .claude/settings.local.json (GODOT_BIN env var); agent reads it automatically.

6. **Cost Tracking**:
   - Baseline expectation: M0 (ultracode) ~= 1–2M tokens; each M1 sprint (high effort) ~= 200–400k tokens per human per week; content iteration (medium) ~= 100–200k tokens per week.
   - Monitor via /context command (see context window breakdown each session).
   - Monthly budget: negotiate with Anthropic based on team size and project pace.

7. **Coordination via Durable Docs**:
   - CLAUDE.md (engineer-owned): core conventions, build commands, architecture boundaries, subagent definitions.
   - docs/ARCHITECTURE.md (engineer): layers, protocol, content API (what primitives designer can compose).
   - docs/GDD.md (designer-owned): game design, mechanics specs, roles/abilities/items.
   - docs/AGENT_WORKFLOW.md (this proposal + approval): session protocol, effort policy, worktree usage, subagent list.
   - docs/decisions/YYYY-MM-DD-*.md: ADRs for why we chose effort policy, Godot 4.7.2, ENet, voice approach, etc.
   - GitHub Issues: moving work state (board columns: Backlog → Ready → In Progress → In Review → Done). No stateful docs here.
   - GitHub Project board: visual drag-drop status, filters by label (area:core, area:content, etc.).

No framework overhead (Superpowers/GSD) needed; Option A + E + light Option F keeps it simple and focused.

## Verifier critique of recommendation

The overall direction is reasonable: normal effort with explicit ultracode escalation, worktrees, and a few subagents. It matches KICKOFF §10. Several parts rest on wrong or unverified facts.

1. **Effort policy is ambiguous for Opus 5.5.** 'high (or medium for Opus 5.5)' is unclear. Opus 5.5 is the default model and defaults to medium, and the docs say its medium matches or beats Opus 5 at high, with levels calibrated per model. The policy should be written per model, e.g. core/net/voice at high on Opus 5.5 and designer work at the medium default. It should not be forced through the committed settings.json: a project-level effortLevel applies to EVERY model and to BOTH humans, which overrides the designer's medium.

2. **Ultracode is conflated.** The draft treats the per-prompt `ultracode:` keyword and session-wide `/effort ultracode` as the same thing. Session-wide ultracode turns every substantive task into workflows and turns off the Large-workflow warning and the subagent cap. For one-off foundation tasks, the policy should use the keyword, then return to /effort high. It should also note that workflows take no mid-run input, so each stage (design, then implement, then verify) needs its own run. That is exactly how KICKOFF's 'design before code' and 'reviewable output' rules can be met, and the proposal never explains reviewability: saving scripts to .claude/workflows/, one PR per unit, fresh-context /code-review, git instead of /rewind.

3. **The worktree rationale is wrong.** The two humans work in separate clones on separate machines. What keeps them from colliding is branches, CODEOWNERS and single-owner scenes; worktrees only isolate parallel sessions on ONE machine (KICKOFF §5.4). The claim that 'Desktop creates worktrees automatically' is false; it is opt-in per session. The proposal also ignores four real costs:
   - branch naming (worktree-<name> vs <area>/<issue>-<slug>)
   - the fresh base branch
   - settings.local.json/GODOT_BIN missing in worktrees on Windows
   - LFS pointer files, plus the Godot .godot/ import cache that must be rebuilt
   
   For the designer, a worktree also means opening a different folder in the Godot editor and Rider. 'Worktree per issue' should be optional for the designer and scoped to parallel sessions for the engineer.

4. **Subagents dropped without justification.** It drops KICKOFF's godot-api-checker and code-reviewer. The built-in /code-review and /security-review could replace a custom code-reviewer, and that trade-off should be stated. It also adds a content-verifier that refers to invented files (content/triggers.tres etc.). It never says how routing will be verified: /tasks shows each subagent's model on v2.1.242+.

5. **Cost section is made up or misdirected.** The token estimates have no source. /context measures context, not spend; /usage and the Desktop usage ring show plan usage. 'Negotiate a monthly budget with Anthropic' does not apply to a subscription plan. Also missing: ultrareview costs $5-25 per run after 3 free runs (Pro/Max), and managed Code Review is Team/Enterprise only at ~$15-25 per review.

6. **Session protocol omits /clear rules and Desktop specifics.** It gives no rule for when to /clear: between unrelated tasks, after two failed corrections, in a fresh session to execute a spec. It also ignores that Shift+Tab, /config key=value and /permissions do not work in Desktop, and that 'run doctor' collides with the bundled /doctor skill.

7. **The PATH CLI is out of date.** It is 2.1.195, so any instruction to launch `claude` from a terminal needs a `claude update` step first.

8. **The Superpowers/GSD framework decision and the Godot MCP question are dismissed in one line**, without the trade-off analysis §8.4 asks for.

## Concrete config (researcher)

{
  "proposed_claude_md_root": "# CLAUDE.md (Proposed)\n\n## Build and Verify\n- Run `python tools/task_runner.py doctor` before starting any session.\n- `verify` runs every check: lint, type check, import, unit tests, bot match, leak test.\n- Never commit without `verify` green and PR template filled.\n\n## Effort Policy\n- **High effort (default)** for core/net/voice/tooling work. Fast iteration, rich reasoning.\n- **Medium effort** for content/data/GDD updates and designer's iteration loops.\n- **Ultracode (xhigh + workflows)** ONLY for: M0 setup, architecture ADRs, large refactors (50+ files), cross-verified audits (netcode security, information leaks).\n- Ultracode is **explicit**: type 'ultracode' in prompt or run `/effort ultracode` before the task.\n\n## Session Protocol\n1. Run `doctor` (diagnose env).\n2. Read issue: `gh issue view <n>`.\n3. Read relevant docs: ARCHITECTURE.md (core engineer), GDD.md (designer), AGENT_WORKFLOW.md (everyone).\n4. Start worktree: `claude --worktree <issue-n-slug>` OR `git worktree add` manually.\n5. Confirm branch: `git status`, worktree root is `.claude/worktrees/<name>/`.\n6. Work: high/medium effort, no framework. Use subagents (`/agent netcode-reviewer`) for bottlenecks.\n7. End session: `verify` (green), handoff comment to issue, open PR from worktree.\n\n## Ownership and No-Nos\n- **Engineer** owns: core/, server/, net/, voice/, tools/, tests/, .github/, CI, CLAUDE.md, ARCHITECTURE.md.\n- **Designer** owns: content/, levels/, GDD.md, docs/design/*, CODEOWNERS entry.\n- Designer: never edit `.gd` code. Open `engine-request` if a new primitive is needed.\n- Engineer: never rebalance content without designer's approval (open issue, link ADR).\n\n## Subagents in .claude/agents/\n- `netcode-security-reviewer.md`: reviews diff for host-authority, intent validation, per-peer filtering, info leaks. Read-only, sonnet.\n- `test-runner.md`: runs test/lint/bots, returns only failures. Haiku.\n- `content-verifier.md` (designer): verifies mechanics consistency with Resource specs. Designer invokes.\n\n## Godot\n- Version: 4.7.2 pinned in CI and `doctor`.\n- GDScript: fully typed everywhere (var, array, signal args, class_name).\n- Warnings as errors: gdlint + gdformat.\n- Tests: GdUnit4 headless.\n- Console exe path in .claude/settings.local.json: `GODOT_BIN` env var.\n\n## Git & GitHub\n- Trunk-based: main always green. Feature branches `<area>/<issue>-<slug>`.\n- Worktree per issue (or `git worktree add` manually).\n- PR template: issue link, summary, how verified (commands+output), screenshots (shot for visual), docs updated.\n- CODEOWNERS: engineer/designer listed per area.\n\n## Docs Hierarchy\n- `CLAUDE.md` (root): this file, shared by both agents.\n- `core/CLAUDE.md`, `net/CLAUDE.md`, `voice/CLAUDE.md` (engineer): area rules.\n- `content/CLAUDE.md`, `levels/CLAUDE.md` (designer): how to author without touching engine code.\n- `docs/ARCHITECTURE.md` (engineer): layers, protocol, content API (triggers, conditions, effects, interactables, task stations).\n- `docs/GDD.md` (designer): game design, mechanics, roles, abilities, items.\n- `docs/AGENT_WORKFLOW.md` (engineer): this workflow proposal (approval needed from designer).\n- `docs/ROADMAP.md`: M0–M7+ milestones, links to GitHub milestones.\n- `docs/decisions/YYYY-MM-DD-*.md`: ADRs (date-slug names, never sequential).\n- `docs/INTERVENTIONS.md`: append-only log of human decisions & rules learned (prevents repeated mistakes).\n\n## Memory\n- Auto memory (MEMORY.md) captured by Claude between sessions; kept under 25KB.\n- No .claude/rules/ needed initially; add path-scoped rules if CLAUDE.md grows above 200 lines.\n\n## What NOT to do\n- Never use a framework (Superpowers, GSD). GitHub Issues + durable docs are the source of truth.\n- Never weaken or skip a test to make it pass.\n- Never claim something works without running it; show command + output.\n- Do not modify the other person's area without asking (issue comment, cross-CODEOWNERS review).\n- Do not commit generated files or .idea/ directory (except shared run configs).\n- Do not use Godot 3 syntax (bug).\n- Do not make decisions section 0 reserves for humans (e.g., deciding whether to merge major branches).\n",
  "proposed_settings_json": {
    "effortLevel": "high",
    "workflowSizeGuideline": "medium",
    "permissions": {
      "allow": [
        "Read",
        "Bash(pattern: '(git|npm|python|gdformat|gdlint|test-runner|task-runner|docot.*)')/*",
        "Bash(pattern: 'python tools/task_runner\\.py (doctor|test|lint|check|bots|shot|verify).*')",
        "Bash(pattern: 'git (status|diff|log|add|commit|branch|checkout|push|pull|fetch|rebase).*')",
        "bash(pattern: 'gh (issue|pr|api).*')",
        "Write(pattern: '\\.gd$')",
        "Write(pattern: '\\.(tres|tscn|cfg|json|md|yaml)$')",
        "Edit(pattern: '\\.gd$')"
      ],
      "deny": [
        "Bash(pattern: 'git (force-push|push.*main|reset --hard)')",
        "Bash(pattern: 'rm -rf /')",
        "Write(pattern: '^\\.github/workflows/(?!.*claude).*\\.yml$')",
        "Write(pattern: '^\\.env')"
      ]
    },
    "hooks": {
      "PostToolUse": [
        {
          "type": "command",
          "pattern": "Edit.*\\.gd$|Write.*\\.gd$",
          "command": "cd ${CLAUDE_PROJECT_DIR} && ${GODOT_TOOLS_PATH:=.}/gdformat --check '${TOOL_RESULT_PATH}' && gdlint '${TOOL_RESULT_PATH}'"
        }
      ]
    }
  },
  "proposed_settings_local_json": {
    "env": {
      "GODOT_BIN": "C:\\path\\to\\Godot_v4.7.2_windows_console.exe",
      "GODOT_TOOLS_PATH": "C:\\path\\to\\gdtoolkit",
      "PYTHON_BIN": "C:\\path\\to\\python.exe"
    }
  },
  "proposed_agent_definitions": [
    {
      "filename": ".claude/agents/netcode-security-reviewer.md",
      "frontmatter": {
        "name": "netcode-security-reviewer",
        "description": "Hunts for host-authority violations, unvalidated client intents, per-peer filtering leaks, and information-leak opportunities in netcode changes",
        "model": "sonnet",
        "tools": "Read, Grep, Glob, LSP"
      },
      "body": "You are a security specialist for multiplayer game netcode. Review every change for:\n- Host-authority violations: clients sending state, not intents.\n- Intent validation: is every client intent validated by host against rules?\n- Per-peer filtering: does host filter hidden info (roles, votes, ability results) per receiver?\n- Information leaks: any message sent to a client that it shouldn't see?\n- Race conditions: can client race the host's validation?\n\nFor each issue, explain why it's a leak, cite the file:line, and suggest a fix.\nDo not rubber-stamp; be adversarial."
    },
    {
      "filename": ".claude/agents/test-runner.md",
      "frontmatter": {
        "name": "test-runner",
        "description": "Runs test suite, linting, and bot match. Reports only failures with minimal context.",
        "model": "haiku",
        "tools": "Bash, Read"
      },
      "body": "Run the full verification suite:\n```\npython tools/task_runner.py test\npython tools/task_runner.py lint\npython tools/task_runner.py bots\n```\n\nCapture output. For any failure, extract the file:line, error message, and what was being tested. Ignore passing tests. Return only failures in one concise list."
    },
    {
      "filename": ".claude/agents/content-verifier.md",
      "frontmatter": {
        "name": "content-verifier",
        "description": "(Designer use) Verifies mechanics data against Resource specs and GDD. Catches inconsistent role definitions, missing effect handlers, broken ability chains.",
        "model": "sonnet",
        "tools": "Read, Grep, Glob"
      },
      "body": "You are a content consistency checker. For a mechanic or role definition, verify:\n- All triggers referenced exist in content/triggers.tres.\n- All conditions exist in content/conditions.tres.\n- All effects exist in content/effects.tres and are implemented in core/.\n- Ability chains resolve: if ability A grants ability B, does B exist?\n- No typos in resource paths (content/roles/MafiaRoleDefinition.tres vs .tres).\n- GDD.md mechanics section matches the Resource definitions.\n\nCite issues with file:line. Flag unimplemented effects as 'engine-request needed'."
    }
  ]
}


## Config corrections (verifier)

1. **Permission syntax is invalid.** There is no `Bash(pattern: '<regex>')` form. Rules are `Tool(specifier)` with `*` globs, e.g. `Bash(git status *)`, `Bash(git diff *)`, `Bash(git log *)`, `Bash(git add *)`, `Bash(git commit *)`, `Bash(gh issue view *)`, `Bash(gh pr view *)`, `Bash(gh pr checks *)`. A matching rule on a primary field like `command` is ignored with a warning. `bash(` in lowercase is not a tool name, and `docot.*` is a typo.

2. **Write path rules do nothing.** `Write(pattern: ...)` and `Write(path)` rules are accepted but never consulted. Use `Edit(...)` with gitignore-style paths, e.g. `Edit(/core/**)`, which covers Edit, Write and NotebookEdit. The `Read` allow is redundant, since reads inside the working directory never prompt.

3. **PowerShell needs its own rules.** It is the primary tool on Windows, and Bash rules do not cover it. Every allow, deny and ask rule needs a `PowerShell(...)` twin, e.g. `PowerShell(git status *)`.

4. **Task-runner rules will never match.** Python is NOT on PATH. `Bash(python tools/task_runner.py ...)` cannot match the command the agent actually runs (`"$PYTHON_BIN" tools/task_runner.py ...` or `& $env:PYTHON_BIN ...`). Add a stable wrapper (e.g. `tools/tr.ps1` / `tools/tr.sh`), allow exactly that, and document its usage in CLAUDE.md. Do not allow bare `python *` or `git *`: that is arbitrary code execution. Do not allow `git push`/`rebase`/`checkout` wholesale.

5. **Rewrite the deny/ask lists as globs.** For both Bash and PowerShell:
   - deny `Bash(git push --force *)`, `Bash(git push -f *)`, `Bash(git push --force-with-lease *)`, `Bash(git push * main)`, `Bash(git reset --hard *)`, `Bash(git branch -D *)`, `Bash(git push * --delete *)`
   - ask `Bash(rm -rf *)`, `PowerShell(Remove-Item *)`, `Edit(/.github/workflows/**)`
   
   'Without mention in the plan' cannot be expressed as a rule, so use `ask`. Deny `Read(./.env)` rather than a Write regex. Note that Bash deny rules are not a boundary (`git -C . push` bypasses them), so also require GitHub branch protection on main.

6. **The hook schema is wrong.** Required shape:
   ```json
   {"hooks":{"PostToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","if":"Edit(**/*.gd)","command":"...","shell":"powershell"}]}]}}
   ```
   - `pattern` is not a field.
   - Matchers match tool names only, not file paths.
   - `${TOOL_RESULT_PATH}` does not exist; read `tool_input.file_path` from the stdin JSON.
   - `${GODOT_TOOLS_PATH:=.}` is bash syntax, and the variable doesn't exist. The real variable is GDTOOLKIT_DIR.
   - gdformat/gdlint failures exit 1, which Claude never sees. The hook must exit 2 with stderr, or print JSON `additionalContext`.
   - `${CLAUDE_PROJECT_DIR}` stays at the main checkout after EnterWorktree; use the `cwd` from the input JSON.
   - Prefer a committed script (`.claude/hooks/gd-lint.ps1`) called in exec form.

7. **Remove `effortLevel: "high"` from the shared settings.json.** In project settings it applies to every model, Opus 5.5 included, and to the designer. Effort belongs to each human's /effort, which is saved per model in their user settings. `workflowSizeGuideline` is fine, but needs v2.1.219+; the PATH CLI 2.1.195 ignores it.

8. **settings.local.json proposal:**
   - It invents `GODOT_TOOLS_PATH` and placeholder paths that would overwrite the real file. The actual keys are GODOT_BIN, GODOT_GUI_BIN, PYTHON_BIN and GDTOOLKIT_DIR.
   - The file was created by hand, so add `.claude/settings.local.json` to .gitignore.
   - Add `.claude/worktrees/` to .gitignore.
   - Add `.claude/settings.local.json` to `.worktreeinclude`, because on Windows worktree sessions do not read the main checkout's local settings.

9. **CLAUDE.md draft:**
   - `/agent netcode-reviewer` does not exist. Use natural language, `@agent-netcode-security-reviewer`, or `--agent`.
   - 'Run `doctor`' / '`verify`' collide with the bundled /doctor and /verify skills; write the full task-runner command.
   - `claude --worktree` starts the stale 2.1.195 CLI; describe Desktop's worktree option or `git worktree add -b <area>/<issue>-<slug>`.
   - 'Worktree root is .claude/worktrees/<name>' produces branch `worktree-<name>`, which violates the branch convention.
   - 'Auto memory kept under 25KB' is managed by Claude Code, and memory is per-machine, not shared between the humans.
   - Root CLAUDE.md must stay ≤150 lines (KICKOFF), not 200.
   - 'Designer owns CODEOWNERS entry' conflicts with engineer owning .github/.
   - Ultracode should be written as the per-prompt `ultracode:` keyword, followed by /effort high afterwards.

10. **Agent definitions:**
   - `LSP` in tools is inactive without a code-intelligence plugin. None is installed, and none exists for GDScript as far as the docs show.
   - netcode-security-reviewer has no Bash, so it cannot run `git diff`. Either the caller must pass the diff, or Bash must be granted, still governed by the deny rules.
   - KICKOFF asks for the strongest model for review, but the draft uses 'sonnet'; consider `opus` or inherit.
   - test-runner commands must use the task-runner wrapper, because python is not on PATH.
   - Add `effort` or `maxTurns` where useful.
   - content-verifier refers to files that do not exist yet.
   - godot-api-checker and code-reviewer from KICKOFF §6 are missing.

11. **Plan mode:** there is no `--plan` flag (use `--permission-mode plan`), and Shift+Tab does not work in Desktop (use Ctrl+Shift+M).

## Windows notes

1. **Godot console exe**: Store full path to `Godot_v4.7.2_windows_console.exe` in .claude/settings.local.json as `GODOT_BIN` env var. Agent reads it; doctor command validates it. CLI tools (gdformat, gdlint, bot runner) read the same variable.

2. **PowerShell 5.1 is primary shell**: Claude Code uses PowerShell first on Windows. Bash (Git Bash) is available as fallback. Task runner should have `.ps1` wrappers in addition to `.sh` scripts; Python or GDScript entry point is best for cross-platform.

3. **Terminal panel in desktop app** (Ctrl+backtick): local sessions only. Use it to run `doctor`, see git status, verify output. Multi-tab support.

4. **PR monitoring (gh CLI)**: Must install and run `gh auth login` manually before desktop app can enable auto-fix toggle. Auto-merge requires GitHub repo to have auto-merge turned on first in settings.

5. **Worktree on Windows**: `.claude/worktrees/` directory must be in .gitignore. Avoid symlinks in worktree paths (NTFS junctions break isolation enforcement). If a submodule inside a worktree links elsewhere, Claude Code deletes only the link, not the target folder (v2.1.205+ behavior).

6. **Git LFS on Windows**: If .gitattributes defines LFS filters in repo's own .git/config (via `git lfs install --local`), worktree creation skips those filter drivers (v2.1.247+) to avoid security issues. Result: LFS files appear as pointer files. Workaround: run `git lfs pull` inside worktree after creation.

7. **Permissions and UAC**: Claude Code runs as your user; no special admin needed for most work. Code edits, file I/O, git, Godot CLI all work under normal user permissions. If task runner calls anything requiring UAC, it will hang.

8. **Path separators**: Use forward slashes (/) in JSON glob patterns in settings. Bash scripts can use `/`, PowerShell scripts use `\`. Python (if used in task runner) handles both.

9. **Environment variables**: Set in .claude/settings.local.json `env` block. Claude Code passes them to all tool calls (Bash, PowerShell, scripts). Do NOT rely on system PATH; be explicit with full paths or add to .claude/settings.local.json.

10. **UTF-8 and newlines**: `.gitattributes` should enforce LF for text files (.gd, .md, .json, .cfg) and CRLF only on .ps1 scripts if needed. GDScript and JSON must be LF for cross-platform consistency.

11. **ARM64 support**: If running on ARM64 (e.g., Surface Pro X, Windows on ARM), use the ARM64 installer for desktop app. Most CLI tools and Godot 4.7.2 have ARM64 builds or cross-compile support; test locally first.

12. **Cost tracking on Windows**: Use `/context all` to see current session's context window breakdown. Desktop app shows token usage per turn at the bottom. No special Windows-specific cost logging.

13. **Disk layout**: Godot takes 1.5–2GB per version. Node (nvm4w) and Python (3.14.0) are full-featured. Ensure C: drive has at least 10GB free for comfortable development. Worktrees (one per issue, auto-cleanup after a few days) are lightweight (~100MB each, mostly git metadata).

14. **Firewall / Proxy**: If behind corporate proxy, set `https_proxy` and `http_proxy` env vars in .claude/settings.local.json. Claude Code inherits them for WebFetch, WebSearch, and git clone operations.

## Gotchas

- Ultracode keyword triggers ONLY in interactive prompts (human input at CLI, IDE, Remote Control, Agent SDK with human origin). It does NOT trigger from -p non-interactive mode, scheduled tasks, webhooks, or PR comments. If you set /effort ultracode in a run, it persists only for that session; next session reverts to default. Do not rely on ultracode for automation.
- Workflow agents in ultracode mode have restricted tools (no full code edit, no deploy). Individual agents have 100-turn limit per agent (practical: most finish in 5–10). 1000 agents per run hard limit prevents runaway workflows. If a workflow design includes a loop that can generate unlimited agents, the run hits the cap and fails.
- Worktree isolation is NOT an OS sandbox. Commands with unparseable git syntax (e.g., `${!var}` or `;` chains) are rejected conservatively; workarounds include splitting into plain separate commands or moving logic into a script file.
- Desktop app PR monitoring requires gh CLI to be installed AND authenticated. Auto-fix toggle only appears if gh is available. If gh auth expires, auto-fix silently stops; no error message.
- GitHub Actions workflow file is NOT auto-updated by /install-github-app. If you ran it in v2.1.200 and later update to v2.1.210, the workflow still uses old inputs (mode, direct_prompt). Manually update the workflow YAML or re-run /install-github-app to get the new one.
- /code-review ultra (cloud review) is NOT available on Bedrock, Vertex, Foundry, or with Zero Data Retention enabled. Calling it returns an error and falls back to local review. Ultra also requires Claude.ai account (not API key). Non-interactive -p runs cannot launch ultra review; use `claude ultrareview` CLI subcommand instead (consent to charge printed).
- CLAUDE.md is re-read after compaction (/compact). If you manually edit CLAUDE.md mid-session and rely on it being loaded, compaction will pick up the new version. Edits mid-session do NOT auto-reload; only after /compact or session restart.
- Subagent model routing via CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 forces ALL subagents to one model, including ones spawned inside workflows. This can break a workflow's design if the cheaper model is too weak for a critical subagent. Test the configuration on a small workflow first.
- Auto memory (MEMORY.md) is capped at 25KB or 200 lines. If Claude writes a 30KB file, only the first 25KB loads at session start. Past that, it's not loaded and may be silently dropped on next session. Keep auto-memory concise; manually archive old notes into docs/decisions/ if needed.
- Worktree cleanup sweep runs periodically (configurable cleanupPeriodDays, default 14). Named worktrees are kept; unnamed ones from --worktree are auto-removed if clean. If you run a worktree session and exit without naming it, the worktree and branch are gone in 2 weeks. Named sessions persist until you manually remove them.
- Permission rules (allow/deny in settings.json) use regex patterns. A pattern like `git push.*main` matches `git push origin main`, but `git -c core.bare=true push` might sneak through if the regex doesn't cover all flag variants. Test permission rules on a dummy command first.
- Hooks run OUTSIDE Claude's context by default. If a PostToolUse hook runs `gdformat` and it fails, Claude doesn't see the error unless the hook sends output back (which it can do). Silent hook failures can mask problems.
- /effort settings are per-session and per-model. If you set /effort ultracode, then switch to a different model (e.g., /model sonnet), the new model does NOT inherit the ultracode setting. You must re-run /effort ultracode if you want it to persist across model switches.
- GdUnit4 test discovery in worktrees requires all test files to match naming convention (test_*.gd). If you have legacy tests with different names, gdunit4 from CLI may skip them. Verify test discovery before assuming tests are running.
- Designer's agent should NOT be given Write/Edit permissions to .gd files in settings. If you accidentally allow it via broad glob (e.g., `Write(pattern: '.\*\.gd$')`), designer's session can modify engine code, violating the boundary. Review permission rules during initial setup.
- Windows .gitattributes LF/CRLF settings apply to all worktrees in the repo. If worktree creation encounters a filter driver the repo's .git/config defines, creation fails until the filter is moved to global config. Error message names the specific config key; follow it.
- Cross-session messaging (SendMessage) is one-way. If engineer sends findings to designer, designer must reply in their own session; there's no automatic back-channel. For back-and-forth, use GitHub Issues instead.
- Hoisting effort to ultracode costs more tokens and takes longer. If you set /effort ultracode for M0 and find it's using 500k+ tokens in one session, consider breaking M0 into smaller tasks and running them at high effort instead. Ultracode has no per-run cost cap; only your account limit applies.

## Open questions

- Should the engineer pre-create the `.claude/agents/` subagent files and commit them to the repo so both humans' sessions see them, or should each human create their own personal subagent copies in ~/.claude/agents/? (Recommendation: commit to repo for engineer, designer creates hers in project if needed.)
- What task runner entry point (Python, GDScript, .ps1 batch) is best for cross-platform (Windows primary, later cross-platform)? (Python is most portable; needs to be installed.)
- Should GitHub Actions be set up immediately in M0, or deferred until M1+ when there's real code to test? (Recommendation: set up template in M0, enable on first feature branch.)
- How should the engineer and designer handle async feedback? If designer's issue is blocked on an engine request, should they push a comment to the issue, or wait for engineer's next session? (Recommendation: comment immediately with @engineer mention in issue, engineer reads at session start via 'gh issue view'.)
- Should /code-review be run on every PR, or only on engineer's PRs (to catch netcode bugs)? Should it be manual (@claude review) or automatic (CI trigger)? (Recommendation: manual for now; add automatic on core/ PRs only after M1 is stable.)
- If ultracode workflow run exhausts the monthly token budget, should it retry at high effort, or fail and wait for next billing period? (No setting for this; Claude Code stops on budget, workflow pauses per-agent while waiting.)
- Should the .claude/settings.json permission allowlist be committed to the repo (shared between humans) or personal in .claude/settings.local.json (per human)? (Recommendation: Commit a baseline; each human extends theirs locally.)
- How often should docs/INTERVENTIONS.md be reviewed and consolidated into CLAUDE.md or new ADRs? (Recommendation: Every milestone; if INTERVENTIONS.md grows >1000 lines, distill lessons learned.)
- Should the task runner support a 'quick-check' mode (lint + import only, no tests) for rapid feedback, or always run full verify? (Recommendation: Add quick-check for pre-commit hook; full verify only before PR.)
- Does the Opus voice GDExtension (two-voip-godot-4) build on Windows? KICKOFF.md flags risk; should M1 spike include fallback options (one-voip, GodotSteam, PCM)? (Recommendation: M1 spike must test Windows build first; if it fails, immediately try fallbacks.)