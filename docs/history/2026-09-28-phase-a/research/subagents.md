# Claude Code subagents and model routing

## Summary

Claude Code subagents are delegated workers that run specialized tasks in isolated context windows with configurable tool restrictions and model routing. Model resolution is deterministic: per-invocation parameter > subagent frontmatter `model` field > `CLAUDE_CODE_SUBAGENT_MODEL` env var > main conversation model. Current Claude lineup (Sept 2026) includes Claude Opus 5.5 (strongest), Sonnet 5 (balanced), Haiku 4.5 (fastest), and Fable 5.1 (demanding reasoning). Subagents inherit CLAUDE.md, skills, and MCP from the main conversation unless explicitly restricted. They can spawn their own subagents (subagent nesting is allowed), but agent teams (experimental) do not support nested teams. Routing is verified via `/tasks` command which shows the model each subagent uses. For this Windows-based two-human project with GitHub-only coordination, subagents should each have a focused tool allowlist and explicit model selection to prevent expensive model-roaming and ensure predictable costs.

## Facts (with verification)

- **subagents-01** [confirmed] Subagent frontmatter required fields: `name` (unique identifier, no colons), `description` (when to delegate). All other fields optional: tools, disallowedTools, model, permissionMode, maxTurns, skills, mcpServers, hooks, memory, background, omitClaudeMd, effort, isolation, color, initialPrompt, experimental (with cacheTtl: 5m or 1h).  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **subagents-02** [confirmed] Model resolution order (highest to lowest priority): (1) Per-invocation `model` parameter passed to Agent tool, (2) Subagent definition `model` frontmatter field (can be alias like sonnet/opus/haiku/fable or full ID or inherit), (3) CLAUDE_CODE_SUBAGENT_MODEL env var, (4) Main conversation model.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **subagents-03** [corrected] Model alias behavior: if main conversation uses opus, subagent alias opus gets exact same model including [1m] suffix for that family. If main uses non-Anthropic provider, only opus alias gets special handling.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: The same-model rule covers any family alias (opus, sonnet, haiku, fable), not only opus. If the per-invocation parameter or the frontmatter names the family the main conversation is already using, the subagent runs on the main conversation's exact model, including any [1m] suffix. The second case is narrower than claimed. It applies only on a non-Anthropic provider when Claude Code CANNOT tell the main model's family, such as an unresolved Bedrock application inference profile ARN. It covers only 'opus', and it doesn't apply when ANTHROPIC_DEFAULT_OPUS_MODEL is set. An alias in CLAUDE_CODE_SUBAGENT_MODEL always resolves to the version the alias points to.
  - evidence: https://code.claude.com/docs/en/sub-agents
- **subagents-04** [confirmed] Blocked model handling: family alias (e.g., opus) substitutes newest allowed version from availableModels allowlist; other blocked values fall back to inherited model.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **subagents-05** [confirmed] Built-in subagents: (1) Explore (read-only, inherited model capped at Opus on Claude API), (2) Plan (read-only, inherited model in plan mode), (3) General-purpose (full tools, CLAUDE_CODE_SUBAGENT_MODEL or main model), (4) claude (catch-all), (5) statusline-setup (Sonnet, internal), (6) claude-code-guide (Haiku, internal).  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **subagents-06** [confirmed] Force all subagents to one model: set CLAUDE_CODE_SUBAGENT_MODEL and CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 in settings.json env section. Overrides every subagent model field except forks and skills with model: inherit.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **subagents-07** [confirmed] Subagent scope and priority (highest to lowest): (1) Managed settings (.claude/agents/ in managed directory), (2) --agents CLI flag (current session), (3) .claude/agents/ (current project, checked in), (4) ~/.claude/agents/ (all user projects), (5) Plugin agents/directory (plugin-scoped).  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **subagents-08** [confirmed] Project subagents (.claude/agents/) discoverable walking up from current directory; closest .claude/agents/ wins for duplicate names; checked into git for team sharing; can be organized into subfolders (folder name doesn't affect identity).  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **models-01** [confirmed] Current Claude model lineup (Sept 2026): Claude Fable 5.1 (demanding reasoning, 1M context, claude-fable-5-1), Claude Opus 5.5 (agentic work, 1M context, claude-opus-5-5), Claude Sonnet 5 (balanced, 1M context, claude-sonnet-5), Claude Haiku 4.5 (fastest, 200K context, claude-haiku-4-5-20251001 dated or claude-haiku-4-5 alias).  
  src: https://platform.claude.com/docs/en/models/overview.md (official-docs)
- **models-02** [confirmed] Dateless model IDs (4.6 generation and later: claude-sonnet-5, claude-opus-5-5, claude-fable-5-1) are pinned snapshots, NOT evergreen pointers. Weights do not change; infrastructure updates may cause minor behavioral differences.  
  src: https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions.md (official-docs)
- **models-03** [confirmed] Retirement dates (Anthropic-operated platforms): Claude Opus 5.5 not sooner than 2027-09-22, Claude Sonnet 5 not sooner than 2027-06-30, Claude Haiku 4.5 not sooner than 2026-10-15.  
  src: https://platform.claude.com/docs/en/models/overview.md (official-docs)
- **models-04** [confirmed] Model pricing base rates (per million tokens, 2026): Fable 5.1 $10 input / $50 output, Opus 5.5 $4 input / $20 output, Sonnet 5 $2 input / $10 output, Haiku 4.5 $1 input / $5 output. Batch API is 50% off; prompt cache reads 10% (2.5% Fable/Mythos, 5% Opus).  
  src: https://platform.claude.com/docs/en/models/overview.md (official-docs)
- **routing-01** [corrected] Verify model routing took effect: run `/tasks` command in session (requires Claude Code v2.1.242+) to see subagent rows with model name and effort level. Also check subagent `.md` file frontmatter directly to confirm model field.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: In the terminal CLI, /tasks names each subagent's model on its row and adds the effort level only when the definition sets `effort`. The docs say this needs v2.1.242 or later; the changelog records it under v2.1.243. Neither version the claim implies works as stated. The `claude` on PATH is 2.1.195, which is too old. The humans work in the desktop Code tab, which runs its own bundled 2.1.281. That tab has a tasks pane instead, and the docs say terminal-dialog commands with no argument form reply 'isn't available in this environment'. The docs don't say whether the desktop tasks pane shows the model. Reading a subagent's .md frontmatter only shows what was configured, not what actually ran. A reliable check the agent can run from the CLI is to read the subagent transcripts, which record the model on every assistant message.
  - note: Changelog 2.1.243: 'Added the model (and effort level) each subagent ran on to /tasks' (https://code.claude.com/docs/en/changelog). Desktop restrictions: https://code.claude.com/docs/en/desktop
  - evidence: https://code.claude.com/docs/en/sub-agents
- **routing-02** [corrected] Subagent context isolation: each subagent has own context window sized by its model. Subagents inherit main conversation's extended thinking setting (v2.1.198+). Subagents receive spawn prompt from lead but not conversation history.  
  src: https://code.claude.com/docs/en/agent-teams.md (official-docs)
  - CORRECTED: Each subagent's context window is sized by its own model, per the 'What loads at startup' section of the sub-agents docs. Since v2.1.198 subagents inherit the main conversation's thinking on/off setting, and there is no per-subagent thinking setting. Thinking can't be turned off on Opus 5.5 or the Fable models at all. A non-fork subagent receives a delegation (task) message that Claude writes, plus CLAUDE.md files, a git status snapshot and any preloaded skills. It does not receive the conversation history. The 'spawn prompt from the lead' wording describes agent-team teammates, not subagents.
  - evidence: https://code.claude.com/docs/en/sub-agents
- **routing-03** [confirmed] Subagents can spawn their own subagents. Agent teams (experimental, disabled by default) do not support nested teams: only the lead manages the team, teammates cannot spawn their own teammates.  
  src: https://code.claude.com/docs/en/agent-teams.md (official-docs)
- **tools-01** [confirmed] Tools never available to any subagent: Agent (at depth limit or fork), AskUserQuestion, EndConversation, EnterPlanMode, ExitPlanMode (unless permissionMode: plan), ScheduleWakeup, WaitForMcpServers, Workflow.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **tools-02** [confirmed] Background subagents (default) retain: Read, Grep, Glob, LSP, Bash, PowerShell, Edit, Write, NotebookEdit, WebFetch, WebSearch, TodoWrite, Skill, ToolSearch, EnterWorktree, ExitWorktree, Monitor, TaskStop, SendMessage, Artifact, SubagentHandback, plus all MCP tools.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **tools-03** [corrected] Tool allowlist and denylist syntax: comma-separated (tools: Read, Grep, Bash) or YAML list. Restrict spawnable agent types: tools: Agent(worker, researcher), Read, Bash. MCP pattern: disallowedTools: mcp__github (remove all github), mcp__* (remove all MCP).  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: The comma-separated and YAML list formats are correct, as are the MCP patterns: mcp__<server> or mcp__<server>__* in either field, and mcp__* only in disallowedTools. The claim is wrong that `Agent(worker, researcher)` in `tools` restricts which agent types can be spawned in general. That allowlist applies only to an agent running as the main thread via `claude --agent`. In a subagent definition the list in parentheses is ignored, and listing Agent simply allows nesting. Also, a disallowedTools entry with a specifier such as Bash(git push *) removes the whole tool, not just those commands.
  - evidence: https://code.claude.com/docs/en/sub-agents
- **permissions-01** [confirmed] Permission modes: default/manual (prompts), acceptEdits (auto-accept file edits), auto (classifier reviews), dontAsk (auto-deny), bypassPermissions (skip all), plan (read-only). Main conversation override: if main is bypassPermissions/acceptEdits/auto, subagent inherits that mode.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **memory-01** [corrected] Subagent persistent memory scope: user (shared across user's projects), project (shared per project), local (isolated to this subagent). Set with memory: field in frontmatter.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: Every scope is per agent name. user = ~/.claude/agent-memory/<agent>/ and applies across all your projects. project = .claude/agent-memory/<agent>/, which is project-specific and shared through version control. local = .claude/agent-memory-local/<agent>/, which is project-specific and not checked in. 'local' does not mean 'isolated to this subagent'. Enabling memory automatically turns on Read, Write and Edit, and the field has no effect when auto memory is disabled.
  - evidence: https://code.claude.com/docs/en/sub-agents
- **hooks-01** [corrected] Hooks can be defined at subagent scope (lifecycle hooks scoped to that subagent definition). Main conversation hooks also apply to subagents unless overridden.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: Frontmatter hooks run only while that subagent is active, and a Stop hook there is converted to SubagentStop. Hooks from settings files, managed policy and plugins ALSO fire inside subagents. Frontmatter hooks run alongside those hooks; they don't replace them, and no override mechanism is documented. Frontmatter hooks in a project .claude/agents file run only after the workspace trust dialog has been accepted for that folder.
  - evidence: https://code.claude.com/docs/en/sub-agents
- **isolation-01** [corrected] Set isolation: worktree in subagent frontmatter to give each subagent an isolated git worktree. Project subagents from .claude/agents/ and subagents launched from main conversation follow background-default isolation rules.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: `isolation: worktree` runs the subagent in a temporary git worktree. That worktree is branched by default from the DEFAULT branch, not the parent session's HEAD, and is cleaned up automatically if the subagent makes no changes. There is no 'background-default isolation rule': 'background default' is about foreground versus background, not isolation. With agent teams enabled, a named subagent launches as a teammate in the main working directory even if its frontmatter sets isolation. A reviewer with isolation: worktree would therefore NOT see the branch's uncommitted diff.
  - evidence: https://code.claude.com/docs/en/sub-agents
- **cli-01** [corrected] Claude Code v2.1.195 (per KICKOFF.md) is in use. Latest documented version features include: maxTurns field (v2.1.246+), omitClaudeMd field (v2.1.271+), /tasks command showing model (v2.1.242+), cross-session messaging same-machine Windows support (v2.1.234+).  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: Two Claude Code builds are installed. The `claude` on PATH is 2.1.195 (June 26, 2026), confirmed with `claude --version`. The desktop Code tab the humans actually use runs its own bundled build, 2.1.281 (%APPDATA%\Claude\claude-code\2.1.281\claude.exe, confirmed with --version). The latest release in the changelog is 2.1.283 (Sept 25, 2026). The maxTurns field itself is older than v2.1.246; only the 'partial output' marking needs v2.1.246. omitClaudeMd needs v2.1.271 (correct). The /tasks model column needs v2.1.242 per the docs, v2.1.243 per the changelog. Windows cross-session messaging needs v2.1.234 (correct). Also, KICKOFF.md does not state a Claude Code version.
  - note: Local checks: `claude --version` returned 2.1.195; `$CLAUDE_CODE_EXECPATH --version` returned 2.1.281 with CLAUDE_CODE_ENTRYPOINT=claude-desktop.
  - evidence: https://code.claude.com/docs/en/changelog
- **windows-01** [corrected] Cross-session messaging on native Windows requires Claude Code v2.1.234 or later (not WSL). Project uses Windows 11 Pro; ensure Claude Code is updated to at least v2.1.234 for subagent-to-subagent messaging.  
  src: https://code.claude.com/docs/en/cross-session-messaging.md (official-docs)
  - CORRECTED: Cross-session messaging on native Windows does require v2.1.234 or later. It is for messaging between separate Claude Code sessions, not between subagents. Subagents message each other within a session through SendMessage, which doesn't depend on cross-session messaging. The desktop app is already on 2.1.281. The project coordinates only through GitHub, so this feature isn't needed.
  - evidence: https://code.claude.com/docs/en/cross-session-messaging
- **agents-01** [confirmed] Five ways to run parallel work in Claude Code: (1) subagents (delegated workers in one session, own context, return summary), (2) agent view (dispatch sessions, monitor in background), (3) agent teams (multiple coordinated sessions, shared task list, experimental/disabled by default), (4) dynamic workflows (script runs many subagents, verifies results), (5) projects (cloud or Remote Control, long-running).  
  src: https://code.claude.com/docs/en/agents.md (official-docs)
- **teams-01** [confirmed] Agent teams are experimental and disabled by default. Enable with CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json env. Agent teams in non-interactive mode (e.g. Agent SDK, -p flag) don't spawn teammates; subagents run as subagents instead.  
  src: https://code.claude.com/docs/en/agent-teams.md (official-docs)
- **effort-01** [corrected] Subagent effort field accepts: low, medium, high, xhigh, max. Default depends on model. Teammates inherit lead's effort level.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: The levels are low, medium, high, xhigh and max; which ones are available depends on the model. A subagent's `effort` default INHERITS FROM THE SESSION; it is not a per-model default. Frontmatter effort overrides the session level but not the CLAUDE_CODE_EFFORT_LEVEL env var, and maxEffortLevel or org caps still apply. Models that don't support effort, including Haiku 4.5, ignore it. Teammates inherit the lead's effort (correct).
  - evidence: https://code.claude.com/docs/en/model-config
- **effort-02** [corrected] Claude Fable 5.1 default effort: high (adaptive thinking always on). Claude Opus 5.5 default: medium. Claude Sonnet 5 default: high. Claude Haiku 4.5: extended thinking not supported.  
  src: https://platform.claude.com/docs/en/models/overview.md (official-docs)
  - CORRECTED: The default efforts are correct: Fable 5.1 high (adaptive thinking always on), Opus 5.5 medium (adaptive thinking always on), Sonnet 5 high (adaptive). Haiku 4.5 does NOT support EFFORT, but it DOES support extended thinking (the table's Thinking row says 'Extended').
  - evidence: https://platform.claude.com/docs/en/models/overview
- **mcp-01** [corrected] Subagent mcpServers field: list or object. Can be scoped to specific subagent. Plugin subagents don't support mcpServers field (ignored). Built-in Explore subagent doesn't inherit main conversation's extended thinking on Claude API (capped at Opus); other providers inherit directly.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
  - CORRECTED: mcpServers is a list. Each entry is either a string naming an already-configured server or an inline definition keyed by server name, supporting stdio, http, sse and ws. It is ignored for plugin subagents (correct). Inline servers in project agent files load only after workspace trust (v2.1.238+). The Explore sentence is wrong: the Opus cap applies to Explore's inherited MODEL on the Claude API, not to extended thinking. Since v2.1.198 all subagents inherit the main thinking setting.
  - evidence: https://code.claude.com/docs/en/sub-agents
- **features-01** [refuted] Feature availability on Anthropic Console (API key auth): subagents work; web search, fast mode, Advisor, channels, analytics, server-managed settings not available. Cross-session messaging available same-machine only (v2.1.234+ on Windows).  
  src: https://code.claude.com/docs/en/feature-availability.md (official-docs)
  - CORRECTED: On the Anthropic Console (API key) column, web search, fast mode (provisioned orgs), Advisor, Channels, the analytics dashboard/API and server-managed settings (Team/Enterprise) are all AVAILABLE. The claim describes the Bedrock column. Cross-session messaging with API key auth is same-machine only (correct). It doesn't matter here anyway: the humans use Claude Desktop, which requires a claude.ai subscription.
  - evidence: https://code.claude.com/docs/en/feature-availability

## Missed facts (from verifier)

- **mf-01** Two different Claude Code versions are on this machine. The desktop Code tab the humans use runs its own bundled Claude Code: v2.1.281 at %APPDATA%\Claude\claude-code\2.1.281\claude.exe, desktop app 2.9939.2. The `claude` on PATH is v2.1.195. That older build predates Sonnet 5 (v2.1.197), the /tasks model column (v2.1.243), the subagent model precedence change (v2.1.251; before it CLAUDE_CODE_SUBAGENT_MODEL beat frontmatter), CLAUDE_CODE_SUBAGENT_MODEL_FORCE (v2.1.257) and opus resolving to Opus 5.5 (v2.1.280). Routing results can therefore differ between desktop and terminal sessions. AGENT_WORKFLOW.md should set a minimum version, have `doctor` check it, and note that the designer's desktop version is unknown.  
  src: https://code.claude.com/docs/en/changelog
- **mf-02** Routing can be checked reliably from the CLI. Each subagent run writes a transcript at ~/.claude/projects/<project>/<session>/subagents/[workflows/<id>/]agent-<id>.jsonl, and every assistant message in it records a "model" field. A sibling agent-<id>.meta.json records agentType. I checked this locally: this session's research agent (agentType claude-code-guide) logged "model":"claude-haiku-4-5-20251001" and other agents logged claude-opus-5-5. A SubagentStop hook also receives agent_type and agent_transcript_path, so a small PowerShell hook or doctor check can assert agent_type -> expected model automatically.  
  src: https://code.claude.com/docs/en/hooks
- **mf-03** The frontmatter model can be silently overridden. A per-invocation Agent `model` parameter has the highest priority, and a model a workflow script names for a stage counts as per-invocation. That covers ultracode runs, which KICKOFF plans to use heavily. A permissions.deny rule `Agent(model:*)` blocks any Agent call that explicitly passes a model, because parameter matching applies only when the parameter is set. That forces frontmatter routing. The trade-off is that workflow stages can then no longer pick models.  
  src: https://code.claude.com/docs/en/permissions
- **mf-04** A subagent's permissionMode is IGNORED whenever the main session runs in auto, acceptEdits or bypassPermissions; the subagent runs in the main mode. Desktop users commonly work in Accept edits or Auto. So `permissionMode: plan` does not make the reviewers read-only. Read-only behaviour has to come from the `tools` list: omit Edit, Write and NotebookEdit, and omit Bash/PowerShell or guard them with a PreToolUse hook, since shell commands can write files. A subagent in plan mode also gains ExitPlanMode and is steered toward producing a plan, which is the wrong fit for a reviewer.  
  src: https://code.claude.com/docs/en/sub-agents
- **mf-05** Claude Haiku 4.5 has a reliable knowledge cutoff of Feb 2025 and training data up to Jul 2025. That is before most of the Godot 4.4-4.7 API changes, so a Haiku godot-api-checker cannot verify 4.7 APIs from memory. The installed Godot 4.7.2 standard (editor) build can dump the real API: `--dump-extension-api` / `--dump-extension-api-with-docs` produce extension_api.json, and `--doctool <path>` produces the XML class reference (checked with $GODOT_BIN --help). The checker should grep that generated file in tools/out/ and `--check-only` parse results rather than rely on model knowledge.  
  src: https://platform.claude.com/docs/en/models/overview
- **mf-06** Haiku 4.5 does not support the effort parameter, so `effort: low` does nothing on the two proposed Haiku agents. Haiku 4.5's retirement is 'not sooner than October 15, 2026', 17 days away, although it is still listed as Active. If Haiku is used, it should be named by the `haiku` alias, which Claude Code re-points, not by the dated ID.  
  src: https://code.claude.com/docs/en/model-config
- **mf-07** `memory: project` writes to .claude/agent-memory/<agent>/, which is meant to be committed. Both humans' agents would write to it, which breaks KICKOFF section 5's rule against shared, frequently changing Markdown. Enabling memory also automatically grants Read, Write and Edit, so the reviewer stops being read-only. The proposed code-reviewer prompt asks it to 'save findings to your agent memory' but sets no `memory` field, so that instruction does nothing.  
  src: https://code.claude.com/docs/en/sub-agents
- **mf-08** On Windows with Git Bash, the PowerShell tool is on by default for claude.ai accounts and is the primary shell. A subagent with `tools: Bash` gets only Git Bash. Hooks that inspect shell commands must match `Bash|PowerShell`, and each hook entry runs in PowerShell via `"shell": "powershell"`. Locally, `python` on PATH resolves to the WindowsApps Store stub. gdformat.exe and gdlint.exe are standalone launchers in $GDTOOLKIT_DIR (the Python314\Scripts folder). The GdUnit4 6.2.1 entry point is res://addons/gdUnit4/bin/GdUnitCmdTool.gd or addons/gdUnit4/runtest.cmd, which reads GODOT_BIN. There is no run_tests.gd.  
  src: https://code.claude.com/docs/en/tools-reference
- **mf-09** The `.claude/agents/` directory doesn't exist yet. A running session watches only agents directories that existed when it started, so a restart is needed after the first agent file is created. Claude Code silently skips agent files with bad YAML, a missing description, or a name containing ':' or starting with '-', and silently ignores unknown or misspelled fields. `claude plugin validate .claude/agents` (v2.1.233+, so not the 2.1.195 PATH CLI) checks that the frontmatter parses. Project-agent frontmatter hooks and inline MCP servers need workspace trust.  
  src: https://code.claude.com/docs/en/sub-agents
- **mf-10** The built-in Explore agent now inherits the main model, capped at Opus: with an Opus 5.5 session, every exploration runs on Opus 5.5. A project `.claude/agents/Explore.md` with `model: haiku` overrides it, if cheaper exploration is wanted. Subagent descriptions share a 15,000-token startup budget, so detail belongs in the body. With agent teams enabled, which Desktop doesn't support anyway, named subagents become teammates.  
  src: https://code.claude.com/docs/en/sub-agents

## Options

### Option A: Explicit per-subagent model + strict tool allowlists
Each of the four subagents (godot-api-checker, test-runner, code-reviewer, netcode-security-reviewer) gets its own .claude/agents/ file with explicit model choice (Haiku for checkers, Sonnet for runner, Opus for reviewer/security), minimal tool allowlist, and permissionMode: plan or dontAsk to prevent accidental edits.
- pros: Predictable cost control: each subagent uses exactly its assigned model, no fallback-wandering; Minimal context bloat: restricted tool lists reduce permission prompts and cognitive load; Auditable and reproducible: durable .md files in git track what each subagent can do; Verification is trivial: /tasks command immediately shows which model each subagent used; Safe by default: read-only modes (plan) prevent accidental code changes from specialist subagents
- cons: Four separate .md files to maintain in .claude/agents/; If tool lists are too restrictive, subagents may fail silently instead of requesting tools; Requires discipline to not let subagents grow into kitchen-sink agents over time; Model choices are static; no adaptive routing based on task complexity
### Option B: Subagents with model: inherit + environment-var override
Subagents inherit main conversation model, with global CLAUDE_CODE_SUBAGENT_MODEL and CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 to override all at once when testing cheaper models (e.g., all-Haiku for cost audit).
- pros: Simpler maintenance: one model change for all subagents via env var; Flexible: can quickly test a subagent on Opus vs Sonnet vs Haiku without rewriting files; Adapts to main conversation: if engineer switches to Opus, subagents follow (unless forced); Lower barrier to experimentation
- cons: No explicit cost control per subagent: model wandering if env vars are unset or wrong; Harder to audit: need to check both frontmatter (model: inherit) and env var at runtime; If FORCE flag is set globally, specialist subagents (e.g., godot-api-checker designed for Haiku) run on expensive models unnecessarily; Coupling between main conversation model and subagent models makes them less independent
### Option C: Hybrid—default aliases (sonnet, haiku) with fallback to Opus via availableModels allowlist
Subagents use short aliases (model: sonnet, model: haiku) for easy reading. Main conversation and settings.json define availableModels allowlist and fallback rules. If a model blocks (e.g., Haiku quota hit), Claude Code substitutes the newest allowed version from the list or falls back to main model.
- pros: Human-readable frontmatter: model: haiku is clearer than model: claude-haiku-4-5-20251001; Built-in fallback resilience: if Haiku is unavailable, system falls back automatically; Scales well: availableModels can be a managed setting pushed to all humans' machines; Aliases remain stable across model releases (e.g., sonnet alias always points to latest Sonnet)
- cons: Aliases resolve differently per provider: Anthropic API resolves sonnet to claude-sonnet-5, but Bedrock/Vertex/Foundry use provider-specific IDs; Fallback behavior is implicit: hard to predict exactly which model will run if primary is blocked; Requires understanding of availableModels allowlist and family-alias substitution logic; Aliases may point to different versions in 6 months (for pre-4.6 models, not for dateless IDs like sonnet-5)
### Option D: Agent teams for parallel review + model-per-role specialization
Enable CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1, spawn code-reviewer and netcode-security-reviewer as teammates with explicit models (Opus for both), run in parallel with shared task list and inter-agent messaging. Godot-api-checker and test-runner remain subagents (single session, simpler).
- pros: Leverage parallel exploration: two reviewers can investigate different aspects simultaneously, debate findings; Explicit routing: each teammate gets named model at spawn time or from subagent definition; Shared task list prevents duplicate work (if Task tools available); More aligned with two-human workflow: review work is high-value and benefits from multi-perspective
- cons: Agent teams are experimental and disabled by default: may change or break in future releases; Significantly higher token cost: each teammate is a full session with own context window; Limited resume/restore behavior (known limitation on in-process teammates); Coordination overhead: teammates must message each other; single session is simpler; Requires understanding of experimental feature stability and limitations

## Recommendation

**Option A (Explicit per-subagent model + strict tool allowlists) with a fallback to Option C (hybrid aliases) for maintainability.** This project has two key constraints: (1) zero human code-writing (agents write everything, must self-verify from CLI), (2) GitHub-only coordination (no AI-to-AI state sharing beyond PRs and issues). For those constraints, explicit, auditable routing is more valuable than flexibility. Recommend: godot-api-checker (model: haiku, tools: Read/Grep/Bash, permissionMode: plan), test-runner (model: haiku, tools: Bash/Read, permissionMode: dontAsk), code-reviewer (model: sonnet, tools: Read/Grep/Glob, permissionMode: plan), netcode-security-reviewer (model: opus, tools: Read/Grep/Bash, permissionMode: plan). All four placed in .claude/agents/ and checked into git so both humans' agents load them. Verification: run `/tasks` after invoking each subagent to confirm model. Cost savings: Haiku for read-only checks (faster feedback loops), Sonnet for balanced review, Opus only for the highest-risk security review. Avoid agent teams for now (experimental, higher token cost, overkill for read-only review work).

## Verifier critique of recommendation

1. It makes decisions the brief reserves for the humans. The user asked for options to approve, and KICKOFF section 10 says a workflow records options rather than deciding. The researcher instead presents one favoured configuration as a finished recommendation.

2. It contradicts the brief without saying so. KICKOFF section 6 says code-reviewer uses the 'Strongest model'; the proposal puts it on sonnet. The options should be Fable 5.1 (strongest, $10/$50, slowest, may consume usage credits), Opus 5.5 (inherit/opus, $4/$20) and Sonnet 5 ($2/$10).

3. Its guarantees don't hold:
- permissionMode: plan is ignored whenever the human's main session is in Accept edits or Auto, which are common Desktop modes.
- Bash in the reviewers' tool lists means they are not actually read-only.
- Frontmatter model can be overridden per call, including by ultracode workflow stages. The explicit, auditable routing it promises needs an `Agent(model:*)` deny rule or transcript checks.

4. Its verification method is weak. /tasks is a terminal dialog: the PATH CLI (2.1.195) is too old to show the model, and whether the Desktop tasks pane does is unverified. Reading the .md frontmatter only shows the configuration, not what ran. Use the transcript model field (mf-02), which I verified locally.

5. Haiku for godot-api-checker is risky. Its Feb 2025 knowledge cutoff is older than most of the Godot 4.4-4.7 API changes, so it can only work by grepping an engine-generated API dump. Otherwise use Sonnet 5 or better. Haiku for test-runner is reasonable, as long as it calls the project task runner rather than raw commands.

6. The cost figures are invented and don't agree with each other. Sonnet is 2x Haiku and Opus 5.5 is 2x Sonnet, so the per-agent numbers imply about $0.21 for all-Sonnet and $0.42 for all-Opus, not $0.60 and $1.00. The humans are on subscriptions, so the real cost is usage limits. Subagents also load CLAUDE.md and git status, and the largest cost is likely the built-in Explore inheriting Opus.

7. Some advice is irrelevant. 'Avoid agent teams' doesn't matter because Desktop doesn't support them. Cross-session messaging isn't needed because coordination goes through GitHub. The claim that both humans' agents load the files from `.claude/agents` checked into git is correct, but a restart is needed after the directory is first created, and the designer's Claude Code version is unknown and needs pinning.

8. What to present instead: a table of options per agent, covering model, tools with and without a shell, a PreToolUse guard, and whether to add the `Agent(model:*)` deny. Add a transcript-based routing check that `doctor` or a SubagentStop hook can run. Also add a minimum Claude Code version, and an explicit note on how the PATH CLI and the desktop's bundled CLI differ.

## Concrete config (researcher)

**Proposed `.claude/agents/` structure and files:**

File: `.claude/agents/godot-api-checker.md`
```yaml
---
name: godot-api-checker
description: Verifies code against Godot 4.7 APIs and flags Godot 3 idioms. Read-only specialist.
tools: Read, Grep, Bash
model: haiku
permissionMode: plan
effort: low
color: blue
---

You are a Godot 4.7 API specialist. Your job:
1. Check code against Godot 4.7 reference (not Godot 3 or 4.6)
2. Flag any Godot 3 idioms (e.g., yield, _ready without type hints, untyped signals)
3. Verify static typing: all var/func/signal declarations must have types
4. Check for deprecated methods or properties
5. Flag any unsafe casts or type mismatches

Report only findings with line numbers. Do not edit code.
```

File: `.claude/agents/test-runner.md`
```yaml
---
name: test-runner
description: Runs GdUnit4 tests, gdformat/gdlint checks, and reports only failures with minimal context. Cheap and fast.
tools: Bash, Read
model: haiku
permissionMode: dontAsk
effort: low
color: green
---

Run these checks in order. Report only failures:
1. Run: python $GDTOOLKIT_DIR/gdformat --check --diff src/ core/ server/ net/ voice/ client/
2. Run: python $GDTOOLKIT_DIR/gdlint src/ core/ server/ net/ voice/ client/
3. Run: $GODOT_BIN --headless --script addons/gdUnit4/bin/run_tests.gd (GdUnit4 tests)
4. For each failure: show the error, the failing code (read the file), suggest a fix

Do not edit files. Only report.
```

File: `.claude/agents/code-reviewer.md`
```yaml
---
name: code-reviewer
description: Thorough code review against CLAUDE.md, ARCHITECTURE.md, and coding standards. Senior reviewer.
tools: Read, Grep, Glob, Bash
model: sonnet
permissionMode: plan
effort: high
color: purple
---

Review the current diff. For each issue:
1. Explain the problem (reference CLAUDE.md rule or architectural boundary if applicable)
2. Show the problematic code
3. Suggest an improved version with explanation

Focus on:
- Adherence to CLAUDE.md architecture boundaries (core/ is pure, no Nodes; server/ is host-authoritative, etc.)
- Type safety (all vars, arrays, signals typed; no untyped declarations)
- Information leak risks (per-peer filtering enforced correctly)
- Test coverage: is there a unit or integration test for this change?

Save findings to your agent memory (project scope) to detect patterns over time.
```

File: `.claude/agents/netcode-security-reviewer.md`
```yaml
---
name: netcode-security-reviewer
description: Hunts for information leaks, unvalidated client intents, and host-trust assumptions. Security specialist.
tools: Read, Grep, Bash
model: opus
permissionMode: plan
effort: high
color: red
---

Security audit for network code and state filtering. Check:
1. **Information leaks:** Do any peers receive state they shouldn't? (Roles, votes before reveal, ability results)
2. **Unvalidated intents:** Do clients send commands the host accepts without validation?
3. **Host trust:** Are there assumptions that the host (or a client pretending to be host) is trustworthy?
4. **Serialization:** Are floating-point positions/velocities sent directly, or rounded/quantized?
5. **Race conditions:** Can two clients trigger conflicting events in the same tick?

For each issue: severity (critical/high/medium), description, code snippet, proposed fix.
```

**Proposed `.claude/settings.json` additions (shared, committed):**
```json
{
  "env": {
    "GDTOOLKIT_DIR": "C:\\path\\to\\gdtoolkit\\bin",
    "GODOT_BIN": "C:\\path\\to\\godot_4.7.2_console.exe",
    "PYTHON_BIN": "C:\\path\\to\\python.exe"
  },
  "permissions": {
    "allow": [
      "Bash: ^(python|powershell|git|gh|.+?_console\\.exe)",
      "Read: .*\\.(gd|md|json|yaml|tres|tscn|cfg)$",
      "Grep: .*",
      "Glob: .*"
    ]
  }
}
```

**Verification steps (for Haiku, Sonnet, Opus routing):**
After invoking any subagent, run:
```
/tasks
```
Should show rows like:
```
godot-api-checker      haiku        low
test-runner            haiku        low
code-reviewer          sonnet       high
netcode-security-      opus         high
reviewer
```

**Model pricing estimate for typical M1 spike (rough):**
- godot-api-checker (Haiku) on 500 lines of code: ~$0.02
- test-runner (Haiku) per test cycle: ~$0.01
- code-reviewer (Sonnet) on one PR: ~$0.05
- netcode-security-reviewer (Opus) on one PR: ~$0.20
Total per review cycle: ~$0.28 (vs. $0.60 if all ran on Sonnet, or $1.00 if all ran on Opus).

## Config corrections (verifier)

The errors below are in the proposed .claude/agents files and the proposed settings.json. They are listed for the user to approve; none of them has been applied.

1. Permission rule syntax is invalid throughout settings.json.
   - 'Bash: ^(python|...)', 'Read: .*\\.(gd|...)$', 'Grep: .*' and 'Glob: .*' are regex-style strings that Claude Code doesn't recognise.
   - Correct form: `Tool` or `Tool(specifier)` with `*` wildcards placed after the subcommand, for example `Bash(git status *)`, `Bash(git diff *)`, `Bash(gh issue view *)`, `PowerShell(git status *)`, `PowerShell(& $env:GODOT_BIN *)`.
   - Reads, Grep and Glob inside the working directory don't need allow rules.
   - Add matching PowerShell(...) rules, because PowerShell is the primary tool on Windows.
   - The deny/ask rules KICKOFF requires are missing: force-push, pushing to main, deleting branches, rm -rf-style deletes outside tools/out/, and editing .github/workflows/.
   - The KICKOFF PostToolUse gdformat/gdlint hook is missing. It should match Edit|Write and use "shell": "powershell".

2. The `env` block with placeholder paths must not go in the shared, committed settings.json. KICKOFF §6 puts machine-specific env in the gitignored .claude/settings.local.json, which already holds GODOT_BIN, GODOT_GUI_BIN, PYTHON_BIN and GDTOOLKIT_DIR. Committing placeholders would break the designer's machine.

3. test-runner has several errors.
   - `python $GDTOOLKIT_DIR/gdformat` is wrong. `python` on PATH is the WindowsApps Store stub, and gdformat and gdlint are .exe launchers. Call "$GDTOOLKIT_DIR/gdformat.exe" --check <paths> and "$GDTOOLKIT_DIR/gdlint.exe" <paths> directly, or better, call the project task runner (`test`, `lint`, `verify`) once M0 builds it.
   - `addons/gdUnit4/bin/run_tests.gd` doesn't exist. Use `"$GODOT_BIN" --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests` or addons/gdUnit4/runtest.cmd.
   - The `src/` path doesn't exist in the KICKOFF layout. The directories are core/ server/ net/ voice/ client/ content/ levels/ tools/ tests/.
   - `permissionMode: dontAsk`, combined with the invalid allow rules, would auto-deny every Godot and gdtoolkit command. And if the main session is in acceptEdits or auto, the setting is ignored anyway.
   - `effort: low` is a no-op on Haiku 4.5.
   - Step 4 ('read the file, suggest a fix') contradicts the job of returning 'only failures with minimal context'.
   - Consider adding PowerShell to its tools.

4. godot-api-checker has several errors.
   - model: haiku can't know Godot 4.5-4.7 APIs. Its prompt should grep an extension_api.json generated by `$GODOT_BIN --headless --dump-extension-api-with-docs` into tools/out/, or use --doctool output.
   - `effort: low` is a no-op on Haiku.
   - `permissionMode: plan` doesn't guarantee read-only.
   - 'Godot 3 idioms (e.g., ... _ready without type hints)' is not a Godot 3 idiom. It is a static-typing policy item.
   - Add Glob, or accept Grep only.

5. code-reviewer has several errors.
   - KICKOFF asks for the strongest model. `sonnet` should be presented as one option alongside opus or inherit (Opus 5.5) and fable (Fable 5.1).
   - The prompt says to 'save findings to your agent memory (project scope)' but no `memory:` field is set. Adding `memory: project` would automatically grant Write and Edit and would commit a file both humans' agents edit to .claude/agent-memory/, so remove that line instead.
   - Do not add isolation: worktree, because it branches from the default branch and would hide the diff.

6. All four agents set `permissionMode: plan` or `dontAsk`, which is ignored when the main session is in acceptEdits, auto or bypassPermissions. Enforce read-only with `tools` that exclude Edit, Write and NotebookEdit. Either drop Bash, or guard Bash and PowerShell with a frontmatter PreToolUse hook (shell: powershell) that allows only read-only commands (git diff, git log, rg, the Godot dump). Also add `disallowedTools: Agent` to stop nesting.

7. The expected /tasks output is fabricated. The docs give no format, and the model is shown as a model name, not the alias. Effort appears only when set, and it is meaningless on Haiku. The PATH CLI 2.1.195 has no model column, and Desktop may not support /tasks at all. Replace this with a transcript check: for each ~/.claude/projects/D--prime-game/<session>/subagents/**/agent-*.meta.json, read agentType, then assert the "model" values in the sibling .jsonl match the expected ID. The expected IDs are claude-haiku-4-5-20251001, claude-sonnet-5, claude-opus-5-5 and claude-fable-5-1. Optionally have a SubagentStop hook log agent_type plus the model into tools/out/.

8. Optionally, and only as an option for the humans, add `"deny": ["Agent(model:*)"]` so Claude or a workflow can't override the frontmatter model per call.

9. Descriptions should say when to delegate. For example, 'Use proactively after editing .gd files' for godot-api-checker, and 'Use before opening a PR that touches server/ or net/' for netcode-security-reviewer.

10. The pricing estimate should be removed or relabelled as a guess. Its totals contradict its own per-model ratios.

## Windows notes

1. **Cross-session messaging:** Requires Claude Code v2.1.234 or later on native Windows (not WSL). Subagent-to-subagent SendMessage works same-machine only. Ensure `claude --version` shows >= 2.1.234. Project KICKOFF specifies v2.1.195; must update before relying on inter-subagent messaging for coordination.

2. **Path handling:** `.claude/settings.local.json` (gitignored) should use absolute paths with backslashes or forward slashes (PowerShell accepts both). Example: `\"GODOT_BIN\": \"C:\\\\Users\\\\username\\\\godot_4.7.2_console.exe\"` (escaped backslashes in JSON) or `\"C:/Users/username/godot_4.7.2_console.exe\"` (forward slashes work in PowerShell).

3. **Shell execution:** Subagent `tools: Bash` runs Git Bash (POSIX environment), while `tools: PowerShell` runs native PowerShell. gdtoolkit Python scripts may need explicit `python` or `python.exe` depending on PATH. Recommend explicit path in env: `PYTHON_BIN` and invoke as `$PYTHON_BIN script.py`.

4. **Environment inheritance:** Claude Code applies `.claude/settings.local.json` env vars to its own tool calls, so subagents inherit them. Test locally: `echo $GODOT_BIN` in a Bash subagent should print the path.

5. **Git LFS and worktrees:** Subagent isolation with `isolation: worktree` may create worktrees via git. Ensure Git LFS is installed and `git config lfs.allowincompletepush false` is set (to prevent incomplete LFS uploads on Windows network shares or slow drives).

6. **Permissions and UAC:** Running the Godot console exe may require elevated permissions on some Windows configs. Test `claude` session can run `$GODOT_BIN --version` before assigning it to subagents. If UAC blocks it, consider running Claude Code session as Administrator or adjusting User Account Control settings (risky; not recommended for long-term workflow).

## Gotchas

- Model aliases (sonnet, opus, haiku) resolve to different full IDs per provider. On Anthropic API: opus → claude-opus-5-5, sonnet → claude-sonnet-5, haiku → claude-haiku-4-5. On Bedrock/Vertex/Foundry: different model IDs entirely. For portability across providers, use explicit model IDs instead of aliases (but KICKOFF specifies Anthropic Console with API key, so aliases are safe here).
- CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 overrides EVERY subagent model field, including ones explicitly set in .md files. If this var is set globally and you add a new subagent with model: opus, it will still run on the value of CLAUDE_CODE_SUBAGENT_MODEL. Avoid this var unless you're deliberately testing all subagents on one model; prefer per-subagent model fields.
- Subagents inherit extended thinking setting from main conversation (v2.1.198+). If main session has extended thinking disabled and a Fable 5.1 subagent runs (which has adaptive thinking always on), thinking will still occur in the subagent but may not match the main conversation's setting. Not a breaking issue but be aware.
- Read-only tools (Read, Grep, Bash with no Write/Edit) do NOT trigger permission prompts in permissionMode: plan or permissionMode: dontAsk. But if a subagent tries to use Write or Edit (e.g., auto-fix a lint error), it will fail silently or error. Test tool lists carefully: ask the subagent to attempt the operation and verify it works before relying on it.
- Subagent memory (memory: project or memory: user) persists across sessions. If a subagent learns a false pattern (e.g., 'Godot 3 syntax is fine'), it may propagate that error to future reviews. Periodically audit subagent memory files (~/.claude/memory/project/ or ~/.claude/memory/user/) or reset them if a subagent gives consistent wrong answers.
- Agent teams (experimental, disabled by default) spawn only in interactive sessions. If you enable CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS and run Claude Code with `-p` flag (non-interactive), teammates will NOT spawn; subagents run as regular subagents instead. This means any workflow scripts or CI runners using `-p` will bypass agent teams entirely—by design, but easy to forget.
- The /tasks command was added in v2.1.242. Project runs v2.1.195; must upgrade to verify model routing. Without /tasks, you can only verify routing by reading the subagent .md file frontmatter or checking the session output for model names (less reliable).
- Subagent max output is not separately limited; output length follows the subagent's model limits (Haiku 64K, Sonnet 128K, Opus 128K). If a subagent's answer is cut off, it hit the output limit, not an agent-specific cap.
- Disallowed tools removed from a subagent's inherited list do NOT error; they silently disappear from the tool menu. If you set disallowedTools: Write, Edit but the subagent still needs to write files, it will error when it tries—at runtime, not parse time. Test tool restrictions before committing.
- Subagents are NOT isolated at the OS level. They run in the same process/environment as the main session. A subagent can read your HOME dir, access git credentials, invoke arbitrary commands if Bash is allowed. Only use subagents you trust (from .claude/agents/ you author or from trusted sources). The project's rule that only agents write code means untrusted subagents are a risk.

## Open questions

- Should subagents spawn subagents of their own (subagent nesting)? Docs confirm nesting is allowed, but no best-practices guidance on depth limits or coordination between nested subagents. For this project's specialist agents (godot-api-checker, test-runner), single-level delegation seems sufficient; decide after M0 if deeper hierarchies are needed.
- Will the engineer or designer roles ever need to trigger subagents directly from their chat, or only indirectly (main agent spawns them)? KICKOFF says humans write zero code, but it's unclear if humans can request a subagent run via `/` commands. Recommend testing `/` commands in both humans' sessions during Phase A.
- How to handle subagent memory drift over time? If code-reviewer's project memory accumulates false patterns (e.g., 'Godot 3 syntax X is acceptable'), how do you clean it up without a manual memory-wipe? Docs don't cover memory auditing workflows.
- GitHub Issues + PRs are the only coordination surface between the two humans' agents. Should subagents post findings to issues, or return them only to the agent that spawned them? If godot-api-checker finds a critical issue, should it create an issue, comment on the PR, or just report in the main session? Need to define that protocol in AGENT_WORKFLOW.md.
- Verify model routing actually takes effect: the /tasks command (v2.1.242+) is the documented way, but the project runs v2.1.195. Should Phase A include a `claude update` step, or is v2.1.195 good enough? If not upgrading, fallback verification is reading .md files + checking session output logs (less reliable).
- Agent teams with model-per-teammate specialization could add value for parallel code review (security-focused + performance-focused reviewers debate findings). But agent teams are experimental. Should the proposal include an opt-in flag to enable them for future M phases, or explicitly avoid them for now (lower risk)?
- Should subagents have a common library of error patterns saved to shared project memory, or should each subagent learn in isolation? E.g., if test-runner finds a recurring CI failure pattern, should code-reviewer know about it to flag it in reviews? Memory scope options are user/project/local; project-scope memory enables sharing but may introduce coupling.
- The Godot API checker needs access to Godot 4.7 documentation. Currently proposed as read-only (no Bash `$GODOT_BIN` tool call, just Read/Grep). Should it get Bash access to run `godot --headless --script docs-extract.gd` to pull Godot API info, or rely on its training data + context from provided .md docs? Recommend context-first (lower cost) but test during M1.