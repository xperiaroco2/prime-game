# Claude Code hooks (with Windows specifics)

## Summary

Research-based proposal for Claude Code hooks configuration, shell execution on Windows, and agent workflow framework for prime-game: a Godot 4.7 multiplayer game with two independent Claude Code sessions (engineer and designer) on Windows 11 Pro. Recommends Git Bash for hook execution with PowerShell-specific fallback for edge cases, PostToolUse hook for gdformat+gdlint auto-correction, permissions allowlist/denylist for routine operations, and plain mode (no Superpowers/GSD framework) with custom project skills for discipline without token overhead.

## Facts (with verification)

- **hooks-01** [confirmed] Claude Code hook events include: SessionStart, SessionEnd, UserPromptSubmit, Stop, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, FileChanged, InstructionsLoaded, and SubagentStart/SubagentStop  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
- **hooks-02** [confirmed] Hook types: command (shell scripts), http (POST endpoints), mcp_tool (MCP server tools), prompt (single-turn LLM), agent (subagent spawning)  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
- **hooks-03** [corrected] Hook commands receive JSON on stdin containing: session_id, prompt_id, cwd, permission_mode, hook_event_name, and tool_input (for tool events)  
  src: https://www.morphllm.com/claude-code-hooks (blog)
  - CORRECTED: The common stdin fields are session_id, transcript_path, cwd, hook_event_name and permission_mode (not every event gets permission_mode). Optional fields are prompt_id (needs v2.1.196 or later, so the installed 2.1.195 does not send it), scratchpad_dir (v2.1.257+), effort, and agent_id/agent_type inside subagents. Tool events add tool_name, tool_input and tool_use_id. PostToolUse also adds tool_response and duration_ms.
  - note: The cited source is a blog. The official 'Common input fields' table says prompt_id 'Requires Claude Code v2.1.196 or later'. The claim also leaves out transcript_path.
  - evidence: https://code.claude.com/docs/en/hooks.md
- **hooks-04** [corrected] Exit code 0 = success (reads optional JSON output); exit code 2 = block action (stderr fed to Claude, cannot be overridden)  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
  - CORRECTED: Exit 0 means success. stdout is parsed as JSON only when it starts with '{' and ends with '}'. For most events stdout goes to the debug log only; for SessionStart, UserPromptSubmit, UserPromptExpansion and PostModelSwitch, plain stdout is added to Claude's context. Exit 2 is a blocking error only on events that can block, and JSON cannot override it there. What exit 2 does depends on the event. On PostToolUse, the tool has already run, so nothing is blocked: stderr is shown to Claude. On SessionStart, stderr is shown to the user only. Any other exit code is a non-blocking error and the action goes ahead.
  - note: See the 'Exit code 2 behavior per event' table. Exit 2 combined with invalid JSON blocks only from v2.1.214 on; 2.1.195 treats it as non-blocking.
  - evidence: https://code.claude.com/docs/en/hooks.md
- **hooks-05** [confirmed] Hook matchers support wildcards (*), exact matches (Bash), alternation (Edit|Write), regex with anchors (^Notebook), and MCP tool globs (mcp__memory__.*)  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
- **hooks-06** [confirmed] PostToolUse hooks can run on Edit|Write tool events and receive file_path from tool_input.file_path in stdin JSON  
  src: https://www.morphllm.com/claude-code-hooks (blog)
- **hooks-07** [confirmed] Hook timeout default is 600 seconds; can be customized per hook  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
- **windows-01** [corrected] On Windows, Claude Code executes hook commands via Git Bash (/usr/bin/bash) by default, regardless of interactive shell being PowerShell  
  src: https://github.com/anthropics/claude-code/issues/59225 (issue)
  - CORRECTED: On Windows, only shell-form hooks (no 'args') run under Git Bash by default. They run under PowerShell when Git Bash is not installed, and a per-hook 'shell' field overrides the choice. Exec-form hooks (with 'args') bypass any shell and need a real .exe as 'command'.
  - note: The hooks-guide adds that Git Bash, even as a non-interactive shell, can still source the user's profile. Any echo in that profile gets in front of the JSON output and breaks it.
  - evidence: https://code.claude.com/docs/en/hooks.md
- **windows-02** [corrected] Known bug (#59225): model is told 'Shell: PowerShell' but hooks execute under bash when Git Bash is on PATH, causing syntax errors when hooks use PowerShell syntax (&, $null, etc.)  
  src: https://github.com/anthropics/claude-code/issues/59225 (issue)
  - CORRECTED: Issue #59225 (opened 2026-05-14) reported this mismatch. It was auto-closed as stale on 2026-06-13 without a fix. Since then the docs have written down the contract: shell form uses Git Bash on Windows, with a per-hook 'shell' override. So the foot-gun remains, but it is now documented behaviour, not an open bug.
  - note: The failure in the issue came from GSD's installer writing PowerShell '&' call syntax into ~/.claude/settings.json. That matters for the framework choice: GSD installs global hooks.
  - evidence: https://github.com/anthropics/claude-code/issues/59225
- **windows-03** [corrected] Per-hook 'shell' field (shell: powershell | bash | cmd) allows override; works independently of CLAUDE_CODE_USE_POWERSHELL_TOOL flag  
  src: https://zenn.dev/shogaku/articles/claude-code-powershell-tool-windows (blog)
  - CORRECTED: 'shell' accepts only "bash" or "powershell"; there is no 'cmd' value. It is ignored when 'args' is set. It does not require CLAUDE_CODE_USE_POWERSHELL_TOOL. The docs say it auto-detects pwsh.exe and falls back to powershell.exe. However, open issue #90077 (2026-08-27, labelled 'has repro') reports that shell:"powershell" spawns only pwsh, with no powershell.exe fallback, and this machine has no pwsh.
  - note: Also, ${CLAUDE_PROJECT_DIR} in a settings.json shell-form PowerShell command is rewritten only from v2.1.198. The installed 2.1.195 needs "$env:CLAUDE_PROJECT_DIR" or exec form. A bare $CLAUDE_PROJECT_DIR resolves to $null in PowerShell.
  - evidence: https://code.claude.com/docs/en/hooks.md
- **windows-04** [corrected] PowerShell tool introduced in Claude Code v2.1.84 (March 2026); opt-in via CLAUDE_CODE_USE_POWERSHELL_TOOL=1 in settings; solves Git Bash path translation issues on Windows  
  src: https://zenn.dev/shogaku/articles/claude-code-powershell-tool-windows (blog)
  - CORRECTED: The PowerShell tool arrived in v2.1.84 (2026-03-26) as an opt-in preview. It is no longer opt-in. On Windows with Git Bash installed it is on by default for claude.ai and Console accounts (CLAUDE_CODE_USE_POWERSHELL_TOOL=0 turns it off), and it is on automatically when Git Bash is absent. It is already the primary shell in this environment.
  - note: Changelog: 2.1.84 'opt-in preview'; 2.1.111 progressive rollout; 2.1.126 'Claude now treats PowerShell as the primary shell'. On versions before 2.1.214, '>' under PS 5.1 writes UTF-16LE, which affects 2.1.195.
  - evidence: https://code.claude.com/docs/en/tools-reference.md
- **windows-05** [corrected] Security fixes in v2.1.89 (April 2026): prevention of background job bypass via trailing &, debugger hangs via -ErrorAction Break, improved quote/space handling in PowerShell 5.1  
  src: https://zenn.dev/shogaku/articles/claude-code-powershell-tool-windows (blog)
  - CORRECTED: The trailing-& background-job bypass and the -ErrorAction Break debugger hang were fixed in v2.1.90, along with archive-extraction TOCTOU. The PS 5.1 hardening for arguments containing both a double quote and whitespace is in v2.1.89. Both releases are dated 2026-04-01.
  - note: The blog puts all three under 2.1.89. Later PowerShell permission-bypass fixes land after the installed 2.1.195: 2.1.214, 2.1.232 and 2.1.283.
  - evidence: https://code.claude.com/docs/en/changelog.md
- **windows-06** [corrected] hook-doctor tool can dry-run hooks to predict behavior on Windows; identifies FAIL-OPEN handlers, missing interpreters, path separator mismatches, encoding issues  
  src: https://github.com/Suyann/claude-code-windows-hooks (repo)
  - CORRECTED: The repo exists and its README describes hook-doctor this way: it lints handlers and dry-runs them under PS 5.1 and bash, flagging FAIL-OPEN, missing interpreters, .cmd/.bat shims in exec form, and similar problems. Backslash normalisation and UTF-8 stdin decoding are done by the bundled hooks, not by listed doctor checks. The repo is unvetted: created 2026-09-17, 0 stars, one push, 'Authored with Claude Code assistance', and it sells a paid kit. Its -Live mode runs claude -p, which costs money.
  - note: Its checklist is useful as reading material only. Per project rules, do not download or run it.
  - evidence: https://github.com/Suyann/claude-code-windows-hooks
- **gdformat-01** [confirmed] PostToolUse hook example: run gdformat then gdparse on .gd files outside addons/; return exit 2 on parse error with stderr message  
  src: https://github.com/RoxtonRD/dungeon-rpg/pull/37 (repo)
- **gdformat-02** [corrected] PostToolUse hooks can auto-fix formatting issues (gdformat) or report-only (gdlint); exit 2 blocks the change and sends error to Claude for rewrite  
  src: https://dev.to/ohugonnot/claude-code-hooks-real-examples-posttooluse-stop-pretooluse-620 (blog)
  - CORRECTED: A PostToolUse hook can auto-fix (gdformat) or report only (gdlint). Exit 2 does not block or undo the edit, because the tool already ran; it shows the hook's stderr to Claude so Claude can fix the file. To pass non-error findings, return JSON {hookSpecificOutput:{hookEventName:'PostToolUse', additionalContext:'...'}} with exit 0, or use decision:'block' with a reason.
  - note: Official per-event table, PostToolUse row: 'Can block? No - Shows stderr to Claude; the tool already ran'.
  - evidence: https://code.claude.com/docs/en/hooks.md
- **config-01** [confirmed] Settings files hierarchy (highest to lowest precedence): managed settings, CLI, project local (.claude/settings.local.json), shared project (.claude/settings.json), user (~/.claude/settings.json)  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **config-02** [confirmed] .claude/settings.json (shared project) affects all humans cloning the repo; .claude/settings.local.json (personal, gitignored) allows per-machine overrides (e.g., GODOT_BIN path)  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **permissions-01** [confirmed] Permission check order: deny, ask, allow (first match wins); deny blocks immediately, overriding narrower allow rules  
  src: https://blog.vincentqiao.com/en/posts/claude-code-permissions/ (blog)
- **permissions-02** [refuted] Common deny rules: git push --force-with-lease to main, rm -rf outside tools/out/, edits to .github/workflows without plan mention  
  src: https://www.developersdigest.tech/blog/claude-code-permissions-settings-guide (blog)
  - note: The cited article mentions none of these: --force-with-lease, rm -rf outside tools/out/, .github/workflows, or plan mention. The items restate KICKOFF section 6. 'Without plan mention' cannot be expressed as a permission rule; the closest are an ask rule on Edit(.github/workflows/**) or a PreToolUse hook. 'rm -rf outside tools/out/' needs a deny or ask rule on Bash(rm -rf *) plus a runner 'clean' command, because permission syntax has no negative lookahead.
  - evidence: https://www.developersdigest.tech/blog/claude-code-permissions-settings-guide
- **permissions-03** [corrected] Allow list for read-only commands: git status, git diff, git log, gh issue view, gdlint, gdformat --check (no write)  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: Built-in read-only commands (ls, cat, grep, find, read-only git forms such as git status/diff/log, and others) and file reads inside the working directory need no allow rule. gh, gdlint and gdformat --check do, and the rules must use the glob syntax, e.g. 'Bash(gh issue view *)'. Because PowerShell is the primary tool here, each rule also needs a 'PowerShell(...)' twin. Prefix rules must match how the command is actually typed; gdtoolkit is not on PATH here, so allowlisting the task-runner entry point is more reliable.
  - note: The docs do not publish a 'recommended allow list'; the claim is the researcher's own recommendation.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **subagents-01** [confirmed] Subagents defined in .claude/agents/<name>.md with frontmatter: name, description, tools (allowlist), model (sonnet|opus|haiku|inherit), permissionMode, maxTurns  
  src: https://code.claude.com/docs/en/subagents.md (official-docs)
- **subagents-02** [confirmed] Subagents can restrict tools via allowlist (tools: Read, Grep, Glob) or denylist (disallowedTools: Write, Edit)  
  src: https://code.claude.com/docs/en/subagents.md (official-docs)
- **skills-01** [confirmed] Skills loaded on-demand from .claude/skills/<name>/SKILL.md (project) or ~/.claude/skills/<name>/SKILL.md (user); support frontmatter: description, allowed-tools, agent, arguments  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **skills-02** [confirmed] Skills with disable-model-invocation: true prevent Claude from auto-triggering; useful for side-effect operations like commit, deploy, push  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **frameworks-01** [confirmed] Superpowers (test-driven): forces spec approval → test-first → red/green/refactor cycle; composes large skill library; high discipline, high token cost  
  src: https://theaiengineer.substack.com/p/superpowers-vs-gsd-vs-compound-engineering (blog)
- **frameworks-02** [confirmed] GSD (context isolation): spawns fresh-context subagents for research/plan/execute/verify phases; prevents context rot; moderate token cost, orchestration overhead  
  src: https://www.pulumi.com/blog/claude-code-orchestration-frameworks/ (blog)
- **frameworks-03** [corrected] gstack (role-switching): constraints which perspective agent occupies before task; lightweight; Y Combinator-backed (50k+ stars March 2026)  
  src: https://theaiengineer.substack.com/p/superpowers-vs-gsd-vs-compound-engineering (blog)
  - CORRECTED: gstack (garrytan/gstack, MIT, created 2026-03-11, about 134k stars on 2026-09-28) is Garry Tan's personal Claude Code setup: 23 opinionated role-based tools (CEO, Designer, Eng Manager, Release Manager, Doc Engineer, QA). It is not 'Y Combinator-backed'; Tan is YC's President and CEO, but it is his own project. The March-2026 '50k stars' figure could not be verified.
  - note: The cited substack article does not mention gstack at all.
  - evidence: https://github.com/garrytan/gstack
- **frameworks-04** [unverifiable] Plain mode (no framework): discipline enforced via CLAUDE.md rules, permissions allowlist, custom skills, and hooks; lowest token cost; requires explicit human guidance per session  
  src: inferred (inferred)
  - note: This is the researcher's own inference with no source. 'Requires explicit human guidance per session' is doubtful: a SessionStart hook plus start-task/finish-task skills can automate the session protocol without a framework.

## Missed facts (from verifier)

- **m1** The installed Claude Code is 2.1.195 (released 2026-06-26), but the docs describe 2.1.283 (released 2026-09-25). Several hook and Windows behaviours in the docs do not exist yet on this machine: PowerShell shell-form ${CLAUDE_PROJECT_DIR} rewrite (2.1.198), prompt_id (2.1.196), exit 2 with invalid JSON still blocking (2.1.214), UTF-8 '>' under PS 5.1 (2.1.214), the startup warning for Write(path) rules (2.1.210), plus PowerShell permission-bypass fixes in 2.1.214, 2.1.232 and 2.1.283. The proposal should either require an update and have doctor check `claude --version` against a minimum, or write everything for 2.1.195 behaviour.  
  src: https://code.claude.com/docs/en/changelog.md
- **m2** On Windows, an exec-form hook (one with 'args') needs 'command' to be a real .exe; .sh, .py, .ps1, .cmd and .bat files cannot be spawned. Supported Windows forms are: command 'powershell.exe' with args ['-NoProfile','-ExecutionPolicy','Bypass','-File','${CLAUDE_PROJECT_DIR}/.claude/hooks/x.ps1'], or an interpreter exe on PATH (node, py) with the script path as an arg. Only ${CLAUDE_PROJECT_DIR}, ${CLAUDE_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_DATA} are substituted, so ${PYTHON_BIN} cannot appear in 'command'. A hook that cannot start is a non-blocking error: it fails open.  
  src: https://code.claude.com/docs/en/hooks.md
- **m3** gdformat 4.5.0 on Windows rewrites LF files as CRLF. Tested locally: an LF scratch .gd came back with CRLF line terminators. The repo requires LF via .gitattributes, so a format hook has to restore LF when the file was LF, as the merged reference hook in dungeon-rpg PR #37 does. gdformat reports parse errors on stderr with exit 1. gdlint prints its findings on stderr with exit 1 and nothing on stdout. gdformat supports a committed gdformatrc, which keeps the hook and CI on the same line length.  
  src: https://github.com/RoxtonRD/dungeon-rpg/pull/37
- **m4** The toolchain on this machine does not support a bash-plus-jq hook. jq is not installed (Git Bash does not ship it). gdformat.exe and gdlint.exe live only in GDTOOLKIT_DIR and are not on PATH. `python` on PATH is the Microsoft Store redirector stub, which prints 'Python was not found'. The py launcher (real exe) and $PYTHON_BIN (3.14.0) both work. Settings `env` values reach hook subprocesses, so a hook script can read PYTHON_BIN and GDTOOLKIT_DIR, but only after workspace trust.  
  src: https://code.claude.com/docs/en/settings-reference.md
- **m5** PostToolUse tool_input.file_path is absolute with backslashes on Windows, e.g. D:\prime-game\addons\...; a relative-prefix check like ^addons/ never matches. Under Git Bash, $PWD and $HOME are POSIX-style (/d/prime-game), so path comparisons in bash hooks break (open issue #94256). The edit hook also does not fire when Bash or PowerShell rewrites a .gd file; FileChanged, or the `lint` step in verify/CI, has to cover that.  
  src: https://code.claude.com/docs/en/hooks.md
- **m6** Rules for hook output. stdout must contain only one JSON object. hookSpecificOutput requires hookEventName. For PostToolUse the supported fields are additionalContext, decision:'block' with reason, updatedToolOutput and classifierContext; unknown keys are silently ignored. JSON that fails schema validation or parsing gives a non-blocking '<hook> hook error' notice, and Claude never sees the content. Each string is capped at 10,000 characters. Stderr on exit 0 goes only to the debug log.  
  src: https://code.claude.com/docs/en/hooks.md
- **m7** The PowerShell tool is the primary shell in this environment. Bash(...) permission rules and a 'Bash' hook matcher do not cover PowerShell tool calls; every rule needs a PowerShell(...) twin, and PreToolUse matchers should read 'Bash|PowerShell'. Permission specifiers are not regex: '*' is a wildcard, and paths use gitignore syntax. Write(path), NotebookEdit(path) and MultiEdit(path) rules are accepted but never consulted, so path rules must use Edit(path) or Read(path).  
  src: https://code.claude.com/docs/en/permissions.md
- **m8** Two risks for PowerShell hooks. First, open issue #90077 (has repro) says shell:"powershell" spawns pwsh with no powershell.exe fallback, and this machine has no pwsh; exec form with an explicit 'powershell.exe' avoids that. Second, when a hook is spawned without a console, PS 5.1's [Console]::In decodes stdin as IBM437 and Python 3.14's json.load(sys.stdin) decodes it as cp1252, so non-ASCII paths are mangled. Tested locally with CREATE_NO_WINDOW; reading raw bytes and decoding UTF-8 worked.  
  src: https://github.com/anthropics/claude-code/issues/90077
- **m9** The 'if' field holds exactly one permission rule; there is no '|', '&&' or '||'. Two conditions need two handlers. 'if' is evaluated only on tool events, and on any other event a hook with 'if' never runs. File-path 'if' patterns are relative to the cwd, and 'Edit(src/**)' semantics changed in v2.1.214. The docs call 'if' best-effort: filter by extension inside the script, and enforce policy through permissions, not 'if'.  
  src: https://code.claude.com/docs/en/hooks.md
- **m10** In interactive sessions, Claude Code holds back all settings-file hooks until the workspace trust dialog is accepted, and project env values and allow rules also wait for trust. SessionStart hooks run in the background, but Claude's first reply waits for them, and their plain stdout goes into Claude's context. A doctor hook should therefore be fast and print a short summary. On SessionStart, exit 2 only shows stderr to the user.  
  src: https://code.claude.com/docs/en/hooks.md

## Options

### Git Bash for hooks (recommended baseline)
All hook commands execute under /usr/bin/bash on Windows; required Git Bash on PATH; write all hooks in POSIX shell or use shebang #!/bin/bash
- pros: Already available on developer machines running git for Windows; Hooks documentation and examples assume bash; widest ecosystem; Predictable, well-understood behavior across platforms; No version conflicts with PowerShell 5.1 quirks; Works with Python/Node hooks that read stdin JSON
- cons: Path separators (backslashes) require escaping or forward slashes; No native Windows cmdlets; batch/PowerShell syntax invalid; Requires careful handling of UTF-8 input from Claude (stdin JSON); Slower startup than native cmd.exe for simple commands
### PowerShell tool (Windows-native, opt-in)
Enable CLAUDE_CODE_USE_POWERSHELL_TOOL=1 in .claude/settings.json; hooks can use 'shell: powershell' per-hook; native Windows paths and cmdlets; v2.1.84+ only
- pros: Native Windows paths (backslashes work natively); Access to PowerShell cmdlets and full .NET libraries; Per-hook shell override without global flag; Eliminates Git Bash path translation overhead; Better integration with Windows-first toolchains (e.g., Visual Studio, WinAPI)
- cons: Requires Claude Code >= 2.1.84 (March 2026); PowerShell 5.1 quirks with stdin JSON parsing (UTF-8 BOM issues, quote escaping); v2.1.89 security fixes required for production (April 2026); unpatched versions have background job bypass; Smaller hook ecosystem (fewer examples, less tested); Inconsistent shell between developer's interactive terminal (PowerShell) and hook execution (slower model alignment)
### Hybrid (Git Bash primary, PowerShell-specific overrides)
Default to Git Bash hooks (no global PowerShell flag); use per-hook 'shell: powershell' for commands that require native Windows features; Python/Node wrappers for complex logic
- pros: Largest ecosystem support (Git Bash is baseline); Selective PowerShell use for edge cases (e.g., Windows event logs, registry); Fallback to bash if PowerShell fails (graceful degradation); Can mix script languages per-hook (bash, Python, Node, PowerShell); Model guidance is consistent (bash baseline), with documented exceptions
- cons: Requires explicit per-hook decisions; higher cognitive load during setup; Team must document which hooks use which shell; potential for mistakes; Testing matrix larger (bash + PowerShell paths for same logic); Risk of scripts failing unpredictably on new machines (shell availability varies)
### Python wrapper for hooks (portable, testable)
Write hook logic in Python, stdin JSON parsing via jq or json.load(), stdout/stderr for output; wraps bash/PowerShell calls; executable from both shells
- pros: Portable: same Python code runs on Windows/Mac/Linux; testable: unit tests before wiring to hooks; Easier stdin JSON parsing than bash jq chains; Can call both bash and PowerShell subprocesses as needed; PYTHON_BIN already set in project env; gdtoolkit already uses Python
- cons: Python startup overhead (~100-200ms per hook); Requires PYTHON_BIN or python on PATH at hook run time; Adds a build step (testing Python before hook deployment); Increased complexity vs. simple bash one-liners; Hook error stack traces harder to parse than bash error messages
### Superpowers framework
Install Superpowers skill library; agent follows test-first → spec approval → TDD → red/green/refactor discipline automatically
- pros: Enforces highest discipline; excellent for mission-critical systems; Prevents scope creep and premature optimization; Large, composable skill library (500+ skills for common tasks); Strong community; many examples in production Godot projects
- cons: High token cost: Socratic design phase + test-first overhead inflates every task; Designer (content owner) does not write code; Superpowers skills are code-centric; Requires learning Superpowers workflow; breaks project's planned plain-skills approach (KICKOFF section 6); Conflicts with two-human model: engineer session with Superpowers + designer session without it creates asymmetry
### GSD framework
Install GSD; agent spawns fresh-context subagents for research, plan, execute, verify phases; prevents context rot via isolation
- pros: Eliminates context rot (main session never directly executes, stays fresh); Good for large projects where context fills quickly; Modular phase structure (research → plan → execute → verify) maps well to CLAUDE.md rules
- cons: Orchestration overhead: main session spends turns spawning subagents instead of working; Moderate token cost (subagent spin-up + summary synthesis); Adds latency: serial phase execution (research finishes, then plan, then execute); Learning curve: two humans must understand subagent handoff protocol; Overkill for M0 scope (agent setup + foundation only)
### Plain mode with custom project skills (recommended)
No framework install; discipline enforced via CLAUDE.md, permissions allowlist, custom skills (.claude/skills/), hooks, and subagents; sessions start by reading issue and docs
- pros: Lowest token cost: no framework overhead, only custom skills needed; Aligns with KICKOFF section 6 proposal (start-task, finish-task skills); Clear ownership: both humans use identical framework (no asymmetry); Maximum flexibility: engineer and designer sessions customize rules independently; Scales down to M0 scope (no Superpowers/GSD bloat before M1)
- cons: Discipline depends entirely on CLAUDE.md quality and session adherence; No built-in guardrails; engineer must craft tight rules to prevent AI drift; Higher risk of sessions getting off track without framework structure; Requires writing custom skills upfront (start-task, finish-task, etc.) before M1

## Recommendation

Use Git Bash for hook execution (baseline) with optional per-hook PowerShell fallback for Windows-specific edge cases. Write the primary PostToolUse hook for gdformat+gdlint in POSIX bash, wrapping it with error handling to feed parse errors back to Claude (exit 2) rather than silently swallowing them. Use Python for complex logic only if a single bash implementation becomes unreadable or requires deep stdin JSON parsing. Deploy in plain mode (no Superpowers/GSD framework): enforce discipline via CLAUDE.md rules, permissions allowlist/denylist, and custom project skills (start-task, finish-task, etc.). For this project (two independent humans, Windows 11 Pro, GitHub Issues as source of truth, M0 scope, zero human code), plain mode maximizes token efficiency and aligns with the stated workflow without framework overhead. The Superpowers/GSD decision is deferred to Phase A approval; plain mode is the safe default that both humans can adopt immediately. Git Bash hooks are stable, widely documented, and require no version upgrades; PowerShell tool is available as an opt-in upgrade after v2.1.89 validation on the engineer's machine.

## Verifier critique of recommendation

The hook half of the recommendation is backwards for this machine. The case for POSIX bash with Git Bash rests on docs examples written for macOS and Linux. Here, jq is missing, gdtoolkit is not on PATH, `python` is the Store stub, file_path arrives as a backslash Windows path while Git Bash's $PWD is POSIX, and gdformat writes CRLF. The agents' primary shell is also PowerShell, so every hook edit means switching languages (issue #59225). On top of that, the concrete config uses exec form with a .sh file, which Windows cannot spawn, so the hook would fail open on every edit.

The stronger default is a small Python hook. It can read stdin as bytes and decode UTF-8, parse JSON with the stdlib, run gdformat and gdparse through the gdtoolkit Python package (sys.executable -m, or the interpreter in $PYTHON_BIN), restore LF, and skip addons/ by resolving the path against the project root. It should return lint findings as hookSpecificOutput.additionalContext and use exit 2 with stderr for parse errors. The same file runs on CI Linux, and a merged reference implementation already exists (dungeon-rpg PR #37).

The launch form is a decision the humans should approve, so present it as options:
- (A) Exec form with 'py' and the script path in args. Needs the py launcher on each machine; the script then takes gdtoolkit from PYTHON_BIN or GDTOOLKIT_DIR.
- (B) Shell form under Git Bash: "\"$PYTHON_BIN\" \"$CLAUDE_PROJECT_DIR/.claude/hooks/gd_format.py\"". Depends on Git Bash and on doctor enforcing PYTHON_BIN.
- (C) A .ps1 run through exec-form 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File'. Native to the primary shell, but PS 5.1 startup cost on every edit, an OEM-codepage stdin, and not portable to CI.
- Avoid shell:"powershell" until issue #90077 is settled, because there is no pwsh here.

Other points:
- 'PowerShell tool is available as an opt-in upgrade after v2.1.89 validation' is wrong. It is already on and primary, so the permission plan must include PowerShell(...) rules.
- 'Require no version upgrades' ignores that 2.1.195 is 88 releases behind; the proposal should set a minimum version, or at least list the gated behaviours.
- Presenting plain mode as a 'safe default both humans can adopt immediately' oversteps the user's request for options. Offer plain, Superpowers and GSD as options with trade-offs. Note two conflicts with KICKOFF section 6: GSD's on-disk planning state could become a second source of truth, and GSD has installed global hooks that broke on Windows.
- Test the hook with piped synthetic JSON (python hook < sample.json) before registering it, since the doctor script's -Live mode costs money.

## Concrete config (researcher)

{
  "description": "Proposed .claude/settings.json (shared, committed) and .claude/settings.local.json (personal, gitignored) for prime-game",
  "shared_settings": {
    "hooks": {
      "PostToolUse": [
        {
          "matcher": "Edit|Write",
          "hooks": [
            {
              "type": "command",
              "if": "Edit(*.gd)|Write(*.gd)",
              "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gdformat-gdlint.sh",
              "args": [],
              "timeout": 30,
              "statusMessage": "Formatting and linting GDScript..."
            }
          ]
        }
      ],
      "SessionStart": [
        {
          "matcher": "startup",
          "hooks": [
            {
              "type": "command",
              "command": "${CLAUDE_PROJECT_DIR}/tools/doctor.py",
              "args": [],
              "timeout": 60,
              "statusMessage": "Checking environment..."
            }
          ]
        }
      ]
    },
    "permissions": {
      "ask": [
        "Bash(git push.*main)",
        "Bash(git reset --hard)",
        "Bash(git branch -D)",
        "Bash(rm -rf)",
        "Bash(./.*\\\\.ps1.*)",
        "Bash(.github/workflows/.*)"
      ],
      "allow": [
        "Read",
        "Glob",
        "Grep",
        "Bash(git status.*)",
        "Bash(git diff.*)",
        "Bash(git log.*)",
        "Bash(git add.*)",
        "Bash(git commit.*)",
        "Bash(git branch.*)",
        "Bash(git checkout.*)",
        "Bash(git worktree.*)",
        "Bash(gh issue.*)",
        "Bash(gh pr.*)",
        "Bash(gdformat.*)",
        "Bash(gdlint.*)",
        "Bash(godot.*--headless)",
        "Bash(python.*test)",
        "Bash(python.*tools/doctor)"
      ],
      "deny": [
        "Bash(git push.*force)",
        "Bash(rm -rf (?!tools/out/))",
        "Bash(npm publish)",
        "Write(.env*)",
        "Write(.pem*)",
        "Write(.github/workflows/.*)"
      ]
    },
    "env": {
      "GODOT_BIN_SHARED": "TODO: set by engineer after Phase A",
      "GDTOOLKIT_DIR_SHARED": "TODO: set by engineer after Phase A"
    }
  },
  "local_settings_example": {
    "description": ".claude/settings.local.json (on each developer's machine, gitignored)",
    "env": {
      "GODOT_BIN": "C:\\Users\\xperi\\AppData\\Local\\Godot\\4.7.2\\godot.console.exe",
      "GDTOOLKIT_DIR": "C:\\Users\\xperi\\AppData\\Local\\Python\\Python3.14\\Scripts",
      "PYTHON_BIN": "C:\\Users\\xperi\\AppData\\Local\\Python\\Python3.14\\python.exe"
    },
    "model": "claude-opus-5-5"
  },
  "gdformat_gdlint_hook_bash": {
    "filename": ".claude/hooks/gdformat-gdlint.sh",
    "description": "PostToolUse hook: format and lint edited .gd files",
    "content": "#!/bin/bash\nset -e\n\n# Read JSON from stdin\nJSON=$(cat)\nFILE_PATH=$(echo \"$JSON\" | jq -r '.tool_input.file_path')\n\n# Skip addons/\nif [[ \"$FILE_PATH\" =~ ^addons/ ]]; then\n  exit 0\nfi\n\n# Only process .gd files\nif [[ \"$FILE_PATH\" != *.gd ]]; then\n  exit 0\nfi\n\n# Run gdformat (auto-fixes formatting)\nif ! gdformat --line-length 100 \"$FILE_PATH\" 2>/dev/null; then\n  echo \"gdformat failed on $FILE_PATH\" >&2\n  exit 2\nfi\n\n# Run gdlint (report only, don't block)\nif ! gdlint \"$FILE_PATH\" 2>/tmp/gdlint_errors.txt; then\n  # Report linting issues as context, but don't block the edit\n  LINTING_ERRORS=$(cat /tmp/gdlint_errors.txt)\n  echo '{\"hookSpecificOutput\": {\"lintingWarnings\": \"'\"$LINTING_ERRORS\"'\", \"formatted\": true}}'\nelse\n  echo '{\"hookSpecificOutput\": {\"formatted\": true, \"lintingWarnings\": \"none\"}}'\nfi\n\nexit 0\n"
  }
}

## Config corrections (verifier)

1) PostToolUse handler. The "command" is a .sh file with "args": [], which is exec form, and on Windows exec form only spawns a real .exe. The hook would never run: a non-blocking error on every Edit/Write, so it fails open. The SessionStart ${CLAUDE_PROJECT_DIR}/tools/doctor.py with args [] fails the same way. Fix: use an interpreter exe as "command", e.g. "command": "py", "args": ["-3", "${CLAUDE_PROJECT_DIR}/.claude/hooks/gd_format.py"], or "powershell.exe" with -NoProfile -ExecutionPolicy Bypass -File <script>. Alternatively use shell form under Git Bash with quoted "$PYTHON_BIN" and "$CLAUDE_PROJECT_DIR". Do not use shell:"powershell" (issue #90077, no pwsh on this machine), and do not use a bare $CLAUDE_PROJECT_DIR in PowerShell, where it resolves to $null.

2) "if": "Edit(*.gd)|Write(*.gd)" is invalid because 'if' takes exactly one rule. Drop it and filter .gd files inside the script, or use two handlers ("Edit(*.gd)" and "Write(*.gd)").

3) The bash script:
- jq is not installed, and with set -e the script exits 127.
- gdformat and gdlint are not on PATH; they are in $GDTOOLKIT_DIR.
- The `^addons/` check never matches an absolute D:\... path, so addons/gdUnit4 would be reformatted.
- gdformat converts LF to CRLF on Windows (verified), so LF must be restored.
- `2>/dev/null` throws away the parse error, so Claude sees only 'gdformat failed'. Send stderr and exit 2, and add gdparse as in the reference hook.
- The output JSON has no hookEventName, invents the keys lintingWarnings and formatted, and is concatenated from raw strings with quotes and newlines in them. It fails validation or parsing, so Claude never sees the warnings. Emit {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<escaped gdlint output>"}} built with a JSON encoder.
- /tmp/gdlint_errors.txt is a shared fixed path, so parallel subagents or worktrees can race; capture the output in memory instead.
- Decode stdin as UTF-8 bytes.

4) Permissions use regex, which permission syntax does not support. Rewrite as: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(gh issue view *), Bash(gh issue list *), Bash(gh pr view *), Bash(gh pr create *), and so on.
- 'Bash(rm -rf (?!tools/out/))' cannot be expressed. Use deny or ask on Bash(rm -rf *), PowerShell(Remove-Item *) and Bash(rm -r *), and delete tools/out through a runner 'clean' command.
- Push rules: 'Bash(git push --force *)', 'Bash(git push -f *)', 'Bash(git push * main)', 'Bash(git push *:main)'.
- 'Bash(git reset --hard)' and 'Bash(git branch -D)' match only those exact strings; add ' *'.
- Allowing 'Bash(git checkout.*)' would also allow 'git checkout -- .'. Prefer git switch or worktree, or ask on 'Bash(git checkout -- *)'.

5) 'Write(...)' path rules (.env*, .pem*, .github/workflows/.*) are never consulted. Use Edit/Read rules with gitignore globs: Read(.env*) and Edit(.env*), Edit(**/*.pem), and 'Edit(.github/workflows/**)' as an ask rule, since KICKOFF allows these edits when the plan mentions them.
- 'Bash(.github/workflows/.*)' and 'Bash(./.*\\.ps1.*)' are not meaningful commands.

6) Every Bash(...) rule needs a PowerShell(...) twin, because PowerShell is the primary tool. For example: PowerShell(git status *), PowerShell(git push --force *), PowerShell(gh issue view *).

7) Remove the 'Read', 'Glob' and 'Grep' allow entries (reads inside the working directory need no approval). git status, diff and log are already built-in read-only commands.

8) 'Bash(godot.*--headless)', 'Bash(python.*test)' and 'Bash(python.*tools/doctor)' won't match real invocations: Godot runs via the $GODOT_BIN path, and `python` is the Store stub. Allow the task-runner entry points instead, in both Bash and PowerShell forms.

9) Remove 'env' GODOT_BIN_SHARED and GDTOOLKIT_DIR_SHARED ('TODO') from shared settings. Machine paths belong only in settings.local.json.

10) local_settings_example has the wrong paths. The existing D:\prime-game\.claude\settings.local.json already holds the correct values:
- GODOT_BIN = D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
- GODOT_GUI_BIN = D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
- PYTHON_BIN = C:\Users\xperi\AppData\Local\Programs\Python\Python314\python.exe
- GDTOOLKIT_DIR = C:\Users\xperi\AppData\Local\Programs\Python\Python314\Scripts

'model' is a personal preference and a decision for the human.

11) SessionStart doctor: consider matcher 'startup|clear|compact', keep its output short because stdout goes into Claude's context, and note that exit 2 there only warns the user. Hooks and project env apply only after workspace trust.

12) Replace '--line-length 100' in the hook with a committed gdformatrc so the hook and CI share one setting.

## Windows notes

1. **Git Bash requirement**: Both developers must have Git for Windows installed (includes Git Bash in PATH). Verify with `git --version` and `where bash`. If `bash` is not found, hook execution will fail silently; use /status to check or run hook-doctor dry-run.

2. **Path separators in .gd files**: File paths in hook JSON use forward slashes (e.g., `scenes/player.gd`), even on Windows. Do not convert to backslashes in bash scripts.

3. **UTF-8 stdin from Claude**: Bash reads stdin JSON (prompt, tool_input) correctly; no BOM issues like PowerShell 5.1 has. If using jq to parse, ensure locale is UTF-8: `export LC_ALL=C.UTF-8`.

4. **PowerShell as fallback (future)**: If hook performance becomes an issue or native Windows paths are needed, upgrade to Claude Code >= v2.1.89 (April 2026 security fixes required) and set per-hook `"shell": "powershell"` without global CLAUDE_CODE_USE_POWERSHELL_TOOL flag. Test on one developer's machine first before committing to shared settings.

5. **gdtoolkit on Windows**: Both PYTHON_BIN and GDTOOLKIT_DIR must point to the correct installation. If gdtoolkit is installed via pip, GDTOOLKIT_DIR is the Scripts folder (e.g., `C:\\Users\\xperi\\AppData\\Local\\Python\\Python3.14\\Scripts`). Verify with `gdformat --version`.

6. **Godot console exe**: GODOT_BIN must point to the `_console.exe` build, not the regular `.exe`, so CI output is captured in hooks. Set in .claude/settings.local.json, not shared settings.

7. **Hook error messages**: When a hook exits 2, stderr is fed to Claude as "Claude Code hook failed: ...". Keep error messages under 200 chars and actionable (e.g., "gdformat failed: syntax error on line 42" rather than full stack trace).

## Gotchas

- Exit code 2 blocks the tool call permanently; Claude cannot override it. Use for parse errors only (gdlint failures), not warnings. For warnings, return exit 0 and include JSON feedback instead.
- Hook command execution in Windows is asynchronous by default; do not assume hooks run sequentially. Use timeout to prevent runaway processes (default 600s is long; gdformat+gdlint should be <5s).
- If Git Bash is not on PATH, hooks silently fail (exit status 127) and the tool proceeds anyway. Developer will not know unless they run doctor or check /status.
- jq is not available in Git Bash by default on Windows; either install it or use Python to parse stdin JSON (safer for production).
- Permissions rules and hook rules are evaluated separately: a hook can block exit 2, but if the tool itself is denied by permissions, Claude never even spawns the hook.
- PostToolUse hooks run after tool success, so they cannot prevent a bad edit—they can only report issues for Claude to fix. Use PreToolUse for blocking (e.g., 'don't edit .env'), PostToolUse for cleanup (e.g., 'format after write').
- Do not store secrets (API keys, GitHub tokens) in .claude/settings.json; it is committed. Use .claude/settings.local.json for sensitive env vars.
- Hooks receive tool_input from stdin JSON, but environment variables like $CLAUDE_TOOL_INPUT are unreliable in some builds; always parse stdin JSON, never rely on env vars for hook parameters.
- The model is told 'Shell: PowerShell' but hooks execute under bash on Windows (if Git Bash is on PATH). This is documented as a known issue (#59225). Workaround: explicitly set `"shell": "bash"` in hook config or document the mismatch in CLAUDE.md.
- If a hook command returns a non-JSON stdout (e.g., plain text error), Claude treats it as an error. Always return valid JSON for exit 0 (even empty `{}`), or return exit 2 with stderr message instead.

## Open questions

- Should the gdformat+gdlint hook auto-fix (exit 0 after formatting) or report-only (exit 2 on parse errors)? Trade-off: auto-fix prevents errors from propagating to test, but may mask intent; report-only lets Claude see and fix, but requires more turns.
- Should PreToolUse hooks block edits to .github/workflows/*.yml without explicit plan mention? This prevents accidental CI breakage but requires tuning the regex matcher to avoid false positives.
- Which subagent models to use (Opus, Sonnet, Haiku) for code-reviewer, test-runner, godot-api-checker (KICKOFF section 6)? Recommendation: Opus for reviews (highest quality), Sonnet for testing (balanced), Haiku for API checking (cheap).
- Should skills (start-task, finish-task, new-mechanic, new-level-piece) have disable-model-invocation: true to prevent Claude from auto-invoking, or allow auto-invocation with clear descriptions? Recommendation: start-task and finish-task should auto-invoke (force discipline), others user-invocable only.
- If PowerShell tool is adopted later, which hooks should migrate from bash to PowerShell? Recommendation: only those that need Windows event log access, registry queries, or .NET libraries; keep gdformat+gdlint and git hooks in bash for portability.
- Should the permissions allowlist pre-approve all git status/diff/log/add/commit/checkout, or require confirmation for branch/worktree operations? Recommendation: approve status/diff/log, ask for branch creation/deletion/push.
- What is the maximum gdformat+gdlint hook timeout on Windows? (Default 30s may be too aggressive for large codebases.) Recommendation: test with largest .gd file expected in project, add 50% buffer.