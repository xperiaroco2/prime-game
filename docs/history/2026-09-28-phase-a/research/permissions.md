# Claude Code settings and permission rules

## Summary

Research for Phase A, Step 3-4: Claude Code settings, permission rules, and Windows-specific configuration for a two-developer Godot project where agents write all code and humans write none. Covers settings file precedence and merging behavior, exact permission rule syntax for Windows (Bash/PowerShell), hook configuration for linting, and concrete allow/ask/deny lists for routine developer tasks versus dangerous operations. Key finding: on Windows 11, sandboxing is unavailable (only WSL2 supported); native PowerShell tool is available as alternative to Bash since v2.1.84; deny rules cannot be bypassed by PreToolUse hooks, requiring hooks only for instrumentation, not security.

## Facts (with verification)

- **settings-precedence-01** [confirmed] Settings file precedence from highest to lowest: Managed settings (organization) > CLI flags > Project local (.claude/settings.local.json) > Shared project (.claude/settings.json) > User (~/.claude/settings.json) > Defaults  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **settings-merge-01** [confirmed] Permission arrays (permissions.allow, permissions.deny, permissions.ask) MERGE across scopes; a key set in one file does not override the same key in lower-precedence files. For example, allow rules from ~/.claude/settings.json combine with allow rules from .claude/settings.json.  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **settings-merge-02** [confirmed] Sandbox filesystem arrays (sandbox.filesystem.allowWrite, allowRead, denyRead, denyWrite) MERGE across settings scopes, combining paths from every scope rather than replacing one scope's array.  
  src: https://code.claude.com/docs/en/sandboxing.md (official-docs)
- **bash-rule-syntax-01** [corrected] Bash permission rule syntax: `Bash(command)` matches exact command, `Bash(command *)` matches command with any suffix, `*` matches any text including spaces. Wildcards must come after the subcommand to avoid matching compound commands like 'safe-cmd && other-cmd'.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: Bash(cmd) matches that exact command. Bash(cmd *) matches cmd followed by anything, and also the bare cmd, because the space before the trailing * is part of the rule: Bash(ls *) does not match lsof. * matches any text, including spaces, and can appear anywhere. The trailing ':*' form is equivalent. Put the * after the subcommand so the words before it constrain the rule: Bash(git * main) matches every git subcommand, including -c. That advice is about subcommands, not compound commands. Compound commands (&&, ||, ;, |, |&, &, newline) are split by Claude Code no matter where the wildcard sits, and each part must match on its own.
  - note: The claim merges two separate mechanisms: the wildcard-position warning and compound-command splitting.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **bash-rule-syntax-02** [corrected] Bash rule does NOT match alternate invocations: `Bash(git push *)` matches 'git push origin main' but NOT '/usr/bin/git push origin main', 'git -C . push', or commands in subshells. Rules constrain the text Claude writes, not the underlying program.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: A Bash rule matches the command text as written, after compound splitting and wrapper stripping. It does not stop the same program in another form: an absolute path (/usr/bin/curl), sh -c / bash -c strings, git -C . push, git -c push.default=current push, or git 'push'. Deny and ask rules DO apply to commands nested in subshells, command substitutions and control-flow bodies. Deny/ask rules are not a security boundary. For that, use the sandbox (not available on native Windows) or a PreToolUse hook that inspects the full command.
  - note: 'commands in subshells' is wrong: the docs say deny/ask rules apply 'including a command nested inside a subshell, a command substitution'. The relevance note misreads hooks. A PreToolUse hook cannot loosen a deny rule, but it can ADD a block (exit 2 or permissionDecision deny), and the docs recommend one for inspecting full command text.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **bash-rule-compound-01** [confirmed] Bash rules on compound commands (with &&, ||, ;, |, |&, &) are split by Claude Code: when you approve 'git status && npm test' with 'Yes, and don't ask again', Claude Code saves separate rules for each subcommand (e.g., 'Bash(npm test *)'), not one rule for the whole string.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **bash-rule-wrappers-01** [corrected] Bash rules automatically strip wrappers (timeout, time, nice, nohup, stdbuf, command, builtin, noglob, xargs, bare), so `Bash(npm test *)` matches 'timeout 30 npm test'. Environment variable prefixes like NODE_ENV=test are also stripped for allow rules.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: Before matching, Claude Code strips a fixed, non-configurable set of wrappers: timeout, time, nice, nohup, stdbuf, the builtins command and builtin, zsh noglob, and bare xargs (only with no flags; xargs -n1 grep is matched as xargs). There is no 'bare' wrapper. For allow rules, only a leading assignment of certain known-safe env vars is stripped (NODE_ENV=test works); an allow rule does not match past any other assignment. Deny and ask rules match past ANY leading assignment. Runners such as npx, direnv exec and docker exec are not stripped. watch/setsid/ionice/flock and find -exec/-delete cannot be approved by a prefix rule.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **bash-readonly-commands-01** [confirmed] Built-in read-only Bash commands (ls, cat, echo, pwd, head, tail, grep, find, wc, which, diff, stat, du, cd, read-only git) run without permission prompt except when conditions apply: unquoted globs with write-capable flags, docker pointed at another daemon, file with path-opening flags, network paths on Windows, or commands longer than 10,000 characters.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **powershell-tool-01** [corrected] PowerShell tool is native shell on Windows (v2.1.84 March 2026+). Rules use same syntax as Bash: `PowerShell(Get-ChildItem *)`, `PowerShell(git commit *)`. Common aliases are canonicalized and case-insensitive matching applies (gci matches Get-ChildItem).  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: The PowerShell tool was added in v2.1.84 (released 2026-03-26) as an OPT-IN PREVIEW. It became a progressive rollout in 2.1.111. It became the primary shell whenever it is enabled in 2.1.126. Today it is on by default on Windows for claude.ai/Console accounts even with Git Bash installed, and docs still list preview limits: no profiles loaded, no sandbox on Windows. Rule syntax matches Bash (PowerShell(Get-ChildItem *), trailing :*, bare PowerShell = everything). Common aliases are canonicalized (gci/ls/dir match Get-ChildItem), and matching is case-insensitive.
  - note: Version history from https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (2.1.84, 2.1.111, 2.1.126); date from gh api releases/tags/v2.1.84.
  - evidence: https://code.claude.com/docs/en/tools-reference.md
- **powershell-tool-02** [corrected] PowerShell pipeline operators (|, ;, &&, ||) split compound commands into subcommands; each must match its own rule for the compound command to be allowed.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: Claude Code parses the PowerShell AST. Pipelines '|' and statement separators ';' split compound commands. The chain operators && and || split them only on PowerShell 7+. Every subcommand must match a rule.
  - note: This machine's agent shell is Windows PowerShell 5.1 (verified locally: 5.1.26100). There, && and || are parse errors, not separators.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **read-edit-rules-01** [corrected] Read/Edit rule path syntax: `//path` = absolute from filesystem root, `~/path` = from home directory, `/path` = from settings source (project root for .claude/settings.json, ~/.claude for user settings), `./path` or `path` = relative to current directory. Rules use gitignore pattern syntax (*, **, !).  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: Read/Edit rules use gitignore syntax. //path is absolute from the filesystem root. ~/path is from home. /path is relative to the settings source: the session's PRIMARY WORKING DIRECTORY for both .claude/settings.json and .claude/settings.local.json (not necessarily the repo root), ~/.claude for user settings, and the file's directory for --settings. path or ./path is relative to the current directory. A single-segment directory pattern such as src/** matches only <cwd>/src in allow rules, but at any depth in deny/ask rules. A leading ! negation works only in deny/ask lists and only against earlier rules from the same source. On Windows, paths are normalized to /c/Users/... before matching. Write/NotebookEdit/Glob path rules are never consulted: use Edit/Read.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **read-edit-rules-02** [corrected] Read deny rules also block Edit and Write tools on the same path, including file creation (v2.1.208+). A `Read` deny rule for `.env` blocks both reading and writing `.env`.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: A Read deny rule also blocks Edit and Write on the same path, including creating a new file. This needs v2.1.208+ for edits and v2.1.228+ for writes. NotebookEdit is not covered, so add an Edit deny for paths no tool may change.
  - note: The PATH CLI here is 2.1.195, so it has neither behavior. The Desktop app's bundled 2.1.281 has both.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **webfetch-rules-01** [corrected] WebFetch rules use `WebFetch(domain:hostname)` syntax. Wildcards match at leading position only (`*.example.com` matches `api.example.com` but not `example.com`). `WebFetch(domain:*)` or bare `WebFetch` rule matches all domains.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: WebFetch(domain:host) matches the hostname, case-insensitively. A leading '*.' matches subdomains at any depth but not the apex. * may also appear elsewhere but then matches only text between two dots (example.* matches example.org, not example.evil.com), so it is not 'leading only'. WebFetch(domain:*) and a bare WebFetch both cover every URL but behave differently. A bare deny removes the tool; domain:* keeps the tool and refuses each fetch. Only the domain: form feeds the sandbox allowlist. Artifact reads also differ. Wildcards need v2.1.172+. There is also a built-in set of preapproved documentation domains.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **mcp-rules-01** [confirmed] MCP tool rules: `mcp__<server>` matches any tool from that server, `mcp__<server>__<tool>` matches specific tool. Allow rules accept tool-name globs only after literal `mcp__<server>__` prefix (e.g., `mcp__github__get_*`). Unanchored globs like `"mcp__*"` are invalid for allow rules.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **agent-rules-01** [corrected] Subagent rules: `Agent(name)` matches subagent by name (e.g., `Agent(code-reviewer)`). Rules can also match on parameter: `Agent(model:opus)`, `Agent(isolation:worktree)`. Use to control which subagents Claude can invoke.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: Agent(name) matches a subagent by name, e.g. Agent(Explore) or Agent(my-custom-agent), and is mainly used in deny. Parameter rules such as Agent(model:opus) and Agent(isolation:worktree) work ONLY in deny and ask rules. Allow rules keep each tool's own specifier syntax. The value is compared to the literal input: 'opus' matches the alias, not a full model ID. Omitted parameters never match. Auto mode drops Agent allow rules on entry.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **skill-rules-01** [confirmed] Skill rules: `Skill(name)` or `Skill(name *)` for exact or prefix match. For anthropic-provided skills: `Skill(anthropic-skills:pdf)` or `Skill(anthropic-skills *)`. Deny rules block nested skills (e.g., `Skill(deploy)` blocks `apps/web:deploy`).  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **permission-modes-01** [corrected] Permission modes from lowest to highest autonomy: `default` (Manual, asks on first use of each tool), `acceptEdits` (auto-approves edits and common fs commands), `plan` (reads only, classifier-approved cmds when auto available), `auto` (everything with background safety checks), `dontAsk` (pre-approved tools only), `bypassPermissions` (everything, no checks—containers/VMs only).  
  src: https://code.claude.com/docs/en/permission-modes.md (official-docs)
  - CORRECTED: The six modes are not an autonomy ladder in that order. default (labeled Manual; the 'manual' alias needs v2.1.200+) runs reads only. acceptEdits adds file edits and mkdir/touch/rm/rmdir/mv/cp/sed on in-scope paths, plus Set-Content/Remove-Item etc. when the PowerShell tool is on. plan runs reads plus classifier-approved commands if auto is available, and is more restrictive than acceptEdits. auto runs everything with classifier checks. dontAsk auto-DENIES anything that would prompt; it suits CI and is not 'more autonomy'. bypassPermissions skips prompts except the actions no mode auto-approves. Deny rules block in every mode, including bypassPermissions.
  - evidence: https://code.claude.com/docs/en/permission-modes.md
- **permission-modes-02** [corrected] Auto mode is built-in starting mode for v2.1.283+ interactive terminal/VS Code. Earlier versions default to auto only on Pro/Max/Team plans. Set `permissions.defaultMode` in settings to override. Local settings cannot set 'auto' or 'bypassPermissions' (ignored); project settings cannot either.  
  src: https://code.claude.com/docs/en/permission-modes.md (official-docs)
  - CORRECTED: auto is the built-in starting mode for terminal and VS Code with v2.1.283+. Before that, it was the starting mode only on Pro/Max/Team in sessions that fetch feature flags, and the built-in auto default needs v2.1.233+ on native Windows (Manual otherwise). defaultMode 'auto' in .claude/settings.json or settings.local.json does not take effect, AND Claude Code then uses the built-in default instead of the user's own ~/.claude defaultMode. 'bypassPermissions' from those files starts Manual (ignored since v2.1.257; before that it applied from any file). In the Desktop app, the mode picked in the selector is remembered per folder and overrides defaultMode.
  - evidence: https://code.claude.com/docs/en/permission-modes.md
- **deny-rules-01** [corrected] Deny rules are evaluated FIRST in all modes and cannot be bypassed. PreToolUse hooks cannot override deny rules: even if a hook returns 'allow', a matching deny rule still blocks the call. Ask rules (second evaluation) also override allow rules.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
  - CORRECTED: Rules evaluate in the order deny, then ask, then allow. The first match wins, and specificity does not matter. Deny rules block in every mode, including bypassPermissions. PreToolUse hook decisions do not bypass them: deny and ask rules are evaluated regardless of what the hook returns. But deny rules CAN be sidestepped by writing the command differently, because they match the text as written (see bash-rule-syntax-02). 'Cannot be bypassed' is overstated.
  - note: Also confirmed in hooks.md: 'Deny and ask rules are still evaluated regardless of what the hook returns'. A hook's exit 2 blocks BEFORE rules are evaluated, so hooks can tighten but not loosen.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **sandbox-windows-01** [confirmed] Sandboxing (Bash/PowerShell filesystem and network isolation) is built-in on macOS/Linux/WSL2 only. Native Windows is NOT supported. On Windows 11, sandboxing is unavailable; use WSL2 or rely on permission rules.  
  src: https://code.claude.com/docs/en/sandboxing.md (official-docs)
- **hooks-01** [corrected] Hooks fire at session/turn/tool-call lifecycle points (SessionStart, PreToolUse, PostToolUse, etc.). Hook types: command, http, mcp_tool, prompt. Hook matchers target tools (Bash, Edit, mcp__server__tool, Agent, Skill) and can filter with 'if' condition. Hooks receive JSON input on stdin.  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
  - CORRECTED: There are five handler types: command, http, mcp_tool, prompt and agent (agent is experimental). Events cover session, turn and tool-call points plus many others (PermissionRequest, PermissionDenied, PostToolUseFailure, PostToolBatch, SubagentStart/Stop, ConfigChange, FileChanged, etc.). Tool-event matchers are an exact name or a |/,-separated list, otherwise an unanchored JS regex. 'if' holds exactly ONE permission rule and is evaluated only on tool events. Command hooks get JSON on stdin; HTTP hooks get it as the POST body.
  - evidence: https://code.claude.com/docs/en/hooks.md
- **hooks-02** [corrected] PostToolUse hook with command exit code 0 signals success; 2 signals blocking error (halts tool). Hooks can return JSON output `{"hookSpecificOutput": {"permissionDecision": "allow|deny|ask", ...}}` to influence execution. Hooks run in a temporary context with resolved `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}` placeholders.  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
  - CORRECTED: PostToolUse cannot block, because the tool already ran. On exit 2, stderr is shown to Claude as a warning. On exit 0, stdout goes to the debug log only (except for UserPromptSubmit/SessionStart and similar), and stderr is never seen by Claude. hookSpecificOutput.permissionDecision (allow/deny/ask/defer) is a PreToolUse field. PostToolUse uses top-level decision:'block' + reason, and hookSpecificOutput.additionalContext / updatedToolOutput. Handlers run in the current directory with Claude Code's environment, not a 'temporary context'. ${CLAUDE_PROJECT_DIR} and the other placeholders are substituted and also exported as env vars. Exit 1 is non-blocking.
  - evidence: https://code.claude.com/docs/en/hooks.md
- **env-config-01** [corrected] Environment variables for agent use: set in `permissions.env` or `.claude/settings.local.json` `env` object. Variables set here are passed to Claude Code's own tool calls (e.g., `GODOT_BIN`, `PYTHON_BIN`). Variables are inherited by Bash/PowerShell/subagent subprocess calls.  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
  - CORRECTED: env is a TOP-LEVEL settings key (an object of string values), not permissions.env. It can be set in any settings file. When several files set the same variable, the highest-precedence file wins per variable, and the value OVERWRITES the same variable exported in the shell. It reaches every subprocess Claude Code starts. Values from project/local settings apply only after workspace trust (or at startup with -p). Project/local files cannot set some variables (CLAUDE_CONFIG_DIR, TMP/TEMP/HOME, telemetry exporters, etc.).
  - note: No variable expansion inside env values is documented, so '$env:GODOT_BIN' would be passed as a literal string.
  - evidence: https://code.claude.com/docs/en/settings-reference.md
- **settings-trust-01** [corrected] Project settings in .claude/settings.json apply only after workspace trust. First time running Claude in an untrusted directory prompts 'Trust this folder?' Allow rules in .claude/settings.local.json skip trust (personal overrides). Once committed to git, shared settings require trust.  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
  - CORRECTED: The trust dialog gates only the capability-granting keys: permissions.allow, additionalDirectories, extraKnownMarketplaces, and most env values from project settings. deny and ask rules apply immediately. Hooks, env and helpers ARE used when only a parent folder is trusted or under -p. Allow rules in .claude/settings.local.json skip trust only while the file is untracked and .claude is not a symlink. Claude Code runs git to check this only after trust. Until then, outside the config home, it holds the local file's rules like project settings. A tracked local file is treated as repository-supplied and needs trust.
  - note: Version quirks: 2.1.196-2.1.199 held local rules in more cases; before 2.1.207, untracked local rules applied before the dialog.
  - evidence: https://code.claude.com/docs/en/permissions.md
- **permission-rule-eval-order-01** [confirmed] Rule evaluation order: deny (highest priority, blocks all), then ask (prompts), then allow (lowest priority). Specificity does not change order: broad deny blocks narrower allow. Example: `Bash(aws *)` deny blocks `Bash(aws s3 ls)` allow.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **windows-network-paths-01** [confirmed] On Windows, Bash and PowerShell commands with UNC network paths (\\server\share\file) prompt for permission even in read-only Bash commands, because network access may send Windows credentials to the host.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **settings-local-json-gitignore-01** [confirmed] .claude/settings.local.json is automatically added to git global excludes (core.excludesFile) the first time Claude Code writes it, so it stays out of commits. Personal env vars and approval rules saved there don't leak to teammates.  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **version-note-01** [corrected] Current Claude Code version for this research: v2.1.195 (per KICKOFF.md). Documentation reflects features as of 2.1.283+ (auto mode default). Some features mentioned (v2.1.247+, v2.1.268+) may be unavailable; verify with `claude --version` and check changelog for backport status.  
  src: local-test: claude --version (local-test)
  - CORRECTED: There are two Claude Code versions on this machine. The `claude` CLI on PATH is 2.1.195 (C:\Users\xperi\.local\bin\claude.exe). The Desktop app's Code tab, which the humans use, runs its own bundled 2.1.281 (running process C:\Users\xperi\AppData\Roaming\Claude\claude-code\2.1.281\claude.exe). The latest release is 2.1.283 (2026-09-25). Most version-gated doc features up to 2.1.281 therefore apply to Desktop sessions; 2.1.283-only features (auto as the built-in default for every plan, the cmd rd/del drive-root deny) do not. The 2.1.195 CLI lacks many of them and still has a Windows PowerShell 5.1 permission-check bypass that was fixed in 2.1.214. There is no 'backport' concept in the changelog.
  - note: Local tests: `claude --version` returned 2.1.195; Win32_Process shows claude.exe 2.1.281 running under the Desktop app; release dates from gh api repos/anthropics/claude-code/releases.
  - evidence: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md

## Missed facts (from verifier)

- **mf-01** The humans' Desktop Code tab runs bundled Claude Code 2.1.281, not the 2.1.195 CLI on PATH. Version-gated behavior differs between the two surfaces. The 2.1.195 CLI has a known Windows PowerShell 5.1 permission-check bypass (fixed 2.1.214), plus PowerShell permission bypasses fixed in 2.1.221 and 2.1.232. Test the config on the surface actually used, and update or avoid the stale CLI.  
  src: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- **mf-02** PowerShell is the primary shell on Windows whenever the PowerShell tool is enabled, which is the default for claude.ai accounts. Bash(...) rules do not match PowerShell tool calls, and a hook matching only 'Bash' never fires for them. Every allow/ask/deny rule needs a PowerShell(...) twin, and shell-inspecting hooks must match 'Bash|PowerShell'.  
  src: https://code.claude.com/docs/en/tools-reference.md
- **mf-03** defaultMode 'auto' in .claude/settings.json or .claude/settings.local.json is ignored, and it makes Claude Code fall back to the built-in default instead of the user's own ~/.claude defaultMode. The mode belongs in each human's ~/.claude/settings.json or the Desktop mode selector, which is remembered per folder and overrides defaultMode.  
  src: https://code.claude.com/docs/en/permission-modes.md
- **mf-04** .claude/ (except .claude/worktrees), .idea/, .git/, .vscode/, .gitmodules and .mcp.json are protected paths. Writes to them prompt in default/acceptEdits, go to the classifier in auto, and are denied in dontAsk. permissions.allow rules cannot pre-approve them, although the prompt offers a session-scoped 'allow edits to this project's .claude folder' option.  
  src: https://code.claude.com/docs/en/permission-modes.md
- **mf-05** On entering auto mode, broad allow rules that grant arbitrary code execution are dropped: Bash(*)/PowerShell(*), wildcarded interpreters like Bash(python*), package-manager run commands, Agent and Monitor allow rules. By default the classifier ALLOWS pushing to any branch of the working repo, including the default branch, and opening PRs. It BLOCKS force push, git reset --hard, git clean -fd, git stash drop/clear, and merging PRs no human approved. Content-scoped ask rules such as Bash(git push *) still force a prompt in auto mode.  
  src: https://code.claude.com/docs/en/permission-modes.md
- **mf-06** An allow rule cannot carve an exception out of an ask or deny rule, because ask beats allow regardless of specificity. So 'rm -rf-style deletes outside tools/out/' cannot be written as an ask rule plus an allow exception for tools/out. It needs a PreToolUse hook (exit 2 or permissionDecision) matching 'Bash|PowerShell', or a task-runner 'clean' command. Built-in protections already exist: critical-path rm/rmdir are never approved by allow rules; Remove-Item on system paths, bare '*' and '/*' or '\*' targets is denied in every mode; Remove-Item -Recurse on the working directory or its parents prompts.  
  src: https://code.claude.com/docs/en/permissions.md
- **mf-07** Hook output semantics: a PostToolUse hook exiting 0 has its stdout written to the debug log and its stderr dropped, so Claude never sees either. To feed lint results back, exit 2 with stderr, or print JSON with hookSpecificOutput.additionalContext or decision:'block' + reason. Shell-form command hooks on Windows run in Git Bash by default; 'shell': 'powershell' is available. Placeholders should be quoted, or exec form ('args') used. tool_input.file_path arrives absolute with backslashes on Windows.  
  src: https://code.claude.com/docs/en/hooks.md
- **mf-08** Local environment facts that break the proposed hook and rules. jq is not installed in Git Bash. gdformat.exe and gdlint.exe live in C:\Users\xperi\AppData\Local\Programs\Python\Python314\Scripts (GDTOOLKIT_DIR), which is not on PATH, so bare 'gdformat'/'gdlint' invocations and Bash(gdformat *) rules will not match how the agent actually calls them. The existing settings.local.json also defines GODOT_GUI_BIN.  
  src: local-test: which jq; ls $GDTOOLKIT_DIR; D:\prime-game\.claude\settings.local.json
- **mf-09** On Windows, Claude Code keeps .claude/settings.local.json next to .claude/settings.json in the session's starting directory, not at the git repo root (the repo-root placement from v2.1.211 excludes Windows). 'Yes, and don't ask again' approvals are saved there per human and never shared. Shared .claude/settings.json is read only from the primary working directory, with no parent fallback. Sessions must start at D:\prime-game or a worktree root.  
  src: https://code.claude.com/docs/en/settings.md
- **mf-10** Read/Edit deny rules also cover recognized Bash file commands (cat, head, tail, sed, tee) and redirection targets. They do NOT cover arbitrary subprocesses such as a Python task runner or the Godot exe. Path rules for Write/NotebookEdit/Glob are never consulted: use Edit(...)/Read(...), which get a startup warning from v2.1.210. Parameter rules such as Bash(command:...) are ignored. Invalid rules are skipped with a Settings Warning and are listed by /status and `claude doctor`.  
  src: https://code.claude.com/docs/en/permissions.md

## Options

### Option A: Minimal Shared Settings + Personal Overrides
Commit only essential team-wide allow rules in .claude/settings.json (task runner, git status/diff/log, gdtoolkit, Godot console exe). Each developer's personal .claude/settings.local.json contains their own approval rules (e.g., 'git commit *' after local testing). Deny rules go in shared settings to block force-push, delete-branch, etc.
- pros: Lowest friction: agents don't interrupt on routine safe tasks (status, diff, lint); Flexible: each human can add personal rules in settings.local.json without committing; Trust once per project: workspace trust applies to shared settings, then personal rules follow; Clear separation: shared=team policy, local=personal workflow
- cons: Requires each developer to manually approve 'git commit *' or 'npm run *' once per repo before it's saved; If team rule omitted by mistake, developers see prompts across their own machines; No central audit trail of who approved what (approvals saved in local settings only)
### Option B: Comprehensive Shared Allow/Deny Lists + Hooks for Instrumentation
Commit detailed allow rules in .claude/settings.json for all safe operations (git status/diff/log/add/commit, npm run *, godot console, gdformat, gdlint, read-only gh commands). Deny rules block force-push, delete-branch, rm -rf outside tools/out. Use PostToolUse hook to auto-run gdformat/gdlint on .gd edits and log results. No PreToolUse hooks for security (deny rules are sufficient).
- pros: Zero interruptions once workspace trust granted: agents run routine work without prompting; Strong policy enforcement: deny rules in shared settings block dangerous ops for all developers; Audit trail in hook logs: when agents edit files, hook logs show what gdformat/gdlint did; Scales: new developers inherit full team workflow from .claude/settings.json
- cons: Requires maintenance: allow list must be reviewed and updated when new tools/patterns introduced; Hook failure can block work: if PostToolUse hook crashes, edits may be delayed or rejected; Shared settings apply to all developers; deviations require settings.local.json overrides; More complex settings file to review/merge on main branch
### Option C: Hybrid with Subagent Isolation and Tool Restrictions
Shared settings define allow/deny lists for main session. Define task-specific subagents (.claude/agents/test-runner, code-reviewer, etc.) with restricted tool sets and model assignments. Each subagent has its own permissions (disallowedTools field in YAML frontmatter). Main session only allows safe read-only and tool-invocation tools; subagents handle specialized work.
- pros: Fine-grained isolation: code-reviewer agent sees only Read/Grep/Glob, never Bash; Cost control: specialized agents can use cheaper models (Haiku) for read-only checks; Clear responsibility: each agent has a defined scope (test runner, API checker, etc.); Composable: agents can be reused across projects and reviewed independently
- cons: Complexity: requires designing subagent interfaces and documenting when to invoke them; Context overhead: each subagent runs in its own context, so state doesn't flow between them; Not fully autonomous: main session still needs comprehensive allow/deny rules to delegate safely; Learning curve: team must agree on which work goes to which agent

## Recommendation

**Option B (Comprehensive Shared Allow/Deny Lists + Hooks) is recommended for prime-game.**

**Rationale:**
1. **Zero interruptions after workspace trust**: With full allow lists for task runner, git status/diff/log/add/commit, read-only gh, and gdtoolkit in shared settings, agents run without permission prompts. This is critical for a two-human two-agent setup where coordination happens only through the repo—an interrupted agent waiting for approval blocks the pipeline.

2. **Windows has no sandboxing**: Native Windows 11 sandboxing is unavailable; deny rules are the only enforcement mechanism. Comprehensive deny rules (git push *, branch -D, rm -rf outside tools/out) make the security boundary explicit and testable.

3. **Hooks for instrumentation, not security**: The KICKOFF.md Phase A calls for a PostToolUse hook to auto-run gdformat/gdlint on edited `.gd` files. Hooks cannot bypass deny rules (key finding), so they're only for logging/instrumentation. A hook that runs `gdformat --check` and reports violations doesn't replace deny rules; deny rules prevent the dangerous ops themselves.

4. **Audit trail and scalability**: When agents edit files, hook logs show what gdformat/gdlint did. As the project grows and more agents are added, the shared allow/deny lists provide a single source of truth for what all agents can do.

5. **Manageable complexity**: The allow/deny lists are explicit and reviewable; developers can read `.claude/settings.json` and immediately see what the team permits. Changes to the policy are PR reviews, not implicit in permission prompts.

**Implementation steps (for approval):**
1. Create `.claude/settings.json` with:
   - Allow: `Bash(npm run *)`, `Bash(git status)`, `Bash(git diff *)`, `Bash(git log *)`, `Bash(git add *)`, `Bash(git commit *)`, `Bash(git switch *)`, `Bash(git branch *)`, `PowerShell(...)` equivalents, `Bash(gdformat *)`, `Bash(gdlint *)`, Read/Glob for project files, `WebFetch(domain:...)` for docs
   - Deny: `Bash(git push *)`, `Bash(git branch -D)`, `Bash(rm -rf /)`-style operations outside tools/out, `Edit(.github/workflows/*)` (only with human approval)
   - Mode: `permissions.defaultMode: "auto"` (once verified available in session)
2. Create `.claude/settings.local.json` (gitignored) for machine-specific env vars: `GODOT_BIN`, `PYTHON_BIN`, `GDTOOLKIT_DIR`
3. Add PostToolUse hook in shared settings that runs `gdformat --check` and `gdlint` on `.gd` files and reports results to Claude
4. Document the rules in `.claude/CLAUDE.md` under "Permissions & Workflow" section
5. Test with a dry run: agent tries to commit a code change and verify the workflow works without interruption

**Gotchas and open questions** follow below.


## Verifier critique of recommendation

Option B (shared allow/deny lists plus hooks) is a reasonable direction, but the rationale has several load-bearing errors.

(1) "Deny rules are the only enforcement mechanism" is wrong. The docs say Bash/PowerShell deny rules match text as written and are "not a security boundary" (git -C . push, sh -c, absolute paths all get past them). The real boundaries are:
- GitHub branch protection, required CI and CODEOWNERS on main. The auto-mode docs say "the remote's own branch protection still applies".
- The built-in critical-path and Remove-Item guards.
- PreToolUse hooks. These CAN block: exit 2 blocks before rules are evaluated. They cannot loosen a deny rule, but they are not "instrumentation only". Point 3 of the rationale has this backwards.

(2) "Zero interruptions after workspace trust" is unattainable.
- Writes to .claude/ and .idea/ are protected paths that allow rules cannot pre-approve.
- Ask rules prompt even in auto mode.
- defaultMode "auto" cannot come from a project file. Worse, putting it there suppresses the user's own default.

(3) The proposal treats one shared file as policy for both agents, but the two humans need different boundaries. Designer versus engineer restrictions (the designer's agent must not edit core/ server/ net/ voice/ tools/) can only live in each human's settings.local.json deny/ask rules or in a role-aware PreToolUse hook. That is a human decision and should be listed as an option.

(4) The permission mode (Manual, acceptEdits or auto) is also a per-human choice, set in ~/.claude/settings.json or the Desktop selector. It should be presented as options, not baked into the shared file.

(5) A blanket deny on git push contradicts the PR workflow in KICKOFF 5.4 (feature branches must be pushed to open PRs). KICKOFF asks to deny or confirm only force-push, pushing to main and branch deletion. The docs pattern is "ask" for checkpoints and "deny" for never.

(6) Hook "audit trail" is false: exit-0 output goes only to the debug log.

(7) The CLI/Desktop version skew (2.1.195 vs 2.1.281) is not addressed, and the test plan runs `claude`, which is the stale CLI.

(8) The proposal ignores that PowerShell is the agent's primary shell. Every rule needs a PowerShell twin, and hooks must match "Bash|PowerShell".

(9) Missing entirely: gh rules. Read-only gh should be allowed; `gh pr merge`, `gh api` and `gh workflow` should be ask. Also missing: .env/secret Read denies, and anchored paths (/.github/workflows/**).

A better proposal for approval lists three options:
- (a) Manual/acceptEdits plus a curated allowlist.
- (b) auto mode in user settings plus ask rules for push, merge and workflow edits.
- (c) Either of these plus a PreToolUse guard hook for force-push, push-to-main and recursive deletes outside tools/out.
Each should state its trade-offs, with GitHub branch protection as the non-negotiable backstop.

## Concrete config (researcher)


**Proposed .claude/settings.json (shared, committed):**

```json
{
  "permissions": {
    "defaultMode": "auto",
    "allow": [
      "Bash(npm run *)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git switch *)",
      "Bash(git branch *)",
      "Bash(git merge *)",
      "Bash(git rebase *)",
      "Bash(git stash *)",
      "Bash(gdformat *)",
      "Bash(gdlint *)",
      "Bash($GODOT_BIN *)",
      "Bash($PYTHON_BIN *)",
      "Bash(cat *)",
      "Bash(ls *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(head *)",
      "Bash(tail *)",
      "PowerShell(Get-ChildItem *)",
      "PowerShell(git status)",
      "PowerShell(git diff *)",
      "PowerShell(git log *)",
      "PowerShell(git add *)",
      "PowerShell(git commit *)",
      "PowerShell(git switch *)",
      "Read(./)",
      "Edit(src/**)",
      "Edit(tools/**)",
      "Edit(tests/**)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:github.io)",
      "WebFetch(domain:*.githubusercontent.com)",
      "WebFetch(domain:npmjs.org)",
      "WebFetch(domain:*.npmjs.org)"
    ],
    "deny": [
      "Bash(git push *)",
      "Bash(git branch -D *)",
      "Bash(git branch -d *)",
      "Bash(rm -rf /)",
      "Edit(.github/workflows/*)",
      "Edit(.claude/settings.json)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit",
        "if": "Edit(**.gd)",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/format-gd.sh",
            "timeout": 10
          }
        ]
      }
    ]
  },
  "env": {
    "GODOT_BIN": "$env:GODOT_BIN",
    "PYTHON_BIN": "$env:PYTHON_BIN",
    "GDTOOLKIT_DIR": "$env:GDTOOLKIT_DIR"
  }
}
```

**Proposed .claude/settings.local.json template (gitignored, per-machine):**

```json
{
  "env": {
    "GODOT_BIN": "C:\\path\\to\\Godot_v4.7.2_win64_console.exe",
    "PYTHON_BIN": "C:\\path\\to\\python.exe",
    "GDTOOLKIT_DIR": "C:\\Users\\username\\AppData\\Local\\Python\\Python314\\Scripts"
  }
}
```

**Proposed .claude/hooks/format-gd.sh (on Windows, save as .ps1 or wrap in bash):**

```bash
#!/bin/bash
# PostToolUse hook: auto-run gdformat/gdlint on .gd file edits

HOOK_INPUT=$(cat)
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

echo "Running gdformat on $FILE_PATH..." >&2
if gdformat "$FILE_PATH" --check 2>&1; then
  echo "✓ gdformat passed"
else
  echo "⚠ gdformat would make changes (would fail CI); Claude should fix manually"
fi

echo "Running gdlint on $FILE_PATH..." >&2
if gdlint "$FILE_PATH" 2>&1; then
  echo "✓ gdlint passed"
else
  echo "⚠ gdlint found issues; output above"
fi

exit 0  # Don't block the edit; just inform Claude
```

**Permission rule notes for this project:**
- `Bash($GODOT_BIN *)` and `Bash($PYTHON_BIN *)` rely on env vars being set in settings.local.json; if env lookup fails, the rule may not match—verify with a test run.
- PowerShell aliases (like `gci` for `Get-ChildItem`) are canonicalized, so the rule works for both.
- `Deny` rules for workflow files protect CI from accidental edits; humans can still edit via PR.
- WebFetch allow list permits documentation fetches for Godot 4.7.2 and npm packages; expand as needed.
- The PostToolUse hook does NOT block (exit 0) so agents aren't stuck waiting; it just informs Claude of linting results.

**Testing the config:**
1. Start a session: `claude`
2. Run `git status` → should not prompt
3. Run `git push origin main` → should be denied
4. Edit a .gd file → hook should run gdformat/gdlint and report
5. Verify no trust prompts after first workspace trust


## Config corrections (verifier)

Errors in the concrete config:

1. `"defaultMode": "auto"` in shared .claude/settings.json does not take effect. It also makes Claude Code use the built-in default instead of each user's ~/.claude defaultMode. Remove it; the mode goes in user settings or the Desktop selector (permission-modes.md).

2. The shared `"env": {"GODOT_BIN": "$env:GODOT_BIN", ...}` block is harmful. No expansion is documented, so the literal string "$env:GODOT_BIN" would overwrite the real variable on any machine whose settings.local.json does not set it (for example, the designer's). Remove env from the shared file entirely and keep the paths only in settings.local.json. The local template's GDTOOLKIT_DIR path shape is wrong: the real one is ...\AppData\Local\Programs\Python\Python314\Scripts. It also omits GODOT_GUI_BIN, which the existing local file defines.

3. Every deny rule is Bash-only. The agent's primary tool is PowerShell (5.1), so add PowerShell(...) twins. PowerShell && and || do not exist in 5.1.

4. `Bash(git push *)` deny blocks all pushes and breaks PR creation. Instead:
   - Deny force variants: `git push --force*`, `git push -f*`, `git push * --force*`, `git push * -f*`, `--force-with-lease`, `+refspec`.
   - Deny main targets: `git push * main`, `git push * HEAD:main`, `git push * *:main`.
   - Put other pushes under ask, or allow them.
   - Keep branch protection as the real guard.

5. `Bash(git branch -d *)` in deny blocks safe deletion of merged branches. KICKOFF wants deny or ask; -d is a candidate for ask. `Bash(git branch *)` in allow also allows -f and -M; narrow it (for example `git branch --list*`, `git branch --show-current`), or rely on read-only built-ins.

6. `Bash(rm -rf /)` is an exact-match rule that only matches that literal string, and the built-in critical-path guard already covers it. For "rm -rf outside tools/out", allow rules cannot carve exceptions from ask/deny. Use ask on `Bash(rm -r*)`, `Bash(rm -fr*)`, `Bash(rm -Rf*)` and `PowerShell(Remove-Item *)` (possibly with -Recurse patterns), plus a PreToolUse hook or a task-runner clean command for tools/out.

7. `Edit(.github/workflows/*)` should be ask, not deny: KICKOFF says confirmation unless the edit is in the plan. Anchor it as `Edit(/.github/workflows/**)`.

8. `Edit(.claude/settings.json)` deny stops the agent from applying approved config changes, although humans write zero code. .claude/ is already a protected path; drop the rule or use ask.

9. `Edit(src/**)` refers to a directory that does not exist in the KICKOFF layout. Allow rules also only remove prompts; they do not restrict. List the real dirs (core, server, net, client, voice, content, levels, tools, tests, docs), or rely on acceptEdits/auto. Put designer boundaries in the designer's local deny/ask rules.

10. `Bash($GODOT_BIN *)` and `Bash($PYTHON_BIN *)`: matching on a variable-expanded command name is undocumented (unverifiable), and in PowerShell the call is `& $env:GODOT_BIN ...`. The PYTHON_BIN rule amounts to arbitrary code execution, and auto mode drops wildcarded interpreter rules. Replace both with literal task-runner wrapper rules, for example `PowerShell(./tools/run.ps1 *)` and `Bash(./tools/run.sh *)`, verified with a test.

11. `Bash(gdformat *)` and `Bash(gdlint *)` will not match, because the tools are not on PATH and the agent uses full paths. Route them through the task runner.

12. `Bash(npm run *)` and the npmjs WebFetch rules are irrelevant (there is no npm project).

13. Read-only gh allows are missing: `gh issue view *`, `gh issue list *`, `gh pr view *`, `gh pr list *`, `gh pr checks *`, `gh run list *`, `gh run view *`. `gh pr merge *`, `gh api *` and `gh workflow *` should be ask.

14. `Bash(git stash *)` allows `stash drop` and `stash clear`; narrow it.

15. `Bash(cat/ls/find/grep/head/tail *)` and `Read(./)` are redundant with the built-in read-only set, and `Bash(find *)` does not cover -exec/-delete anyway.

16. WebFetch rules: `domain:github.io` matches only the apex, so use `*.github.io`. Add docs.godotengine.org and code.claude.com.

17. PostToolUse hook problems:
   - Matcher "Edit" misses Write, so new .gd files are skipped. Use "Edit|Write", and verify that `if: "Edit(*.gd)"` fires for Write.
   - `"Edit(**.gd)"` is non-idiomatic (gitignore treats `**.gd` as `*.gd`).
   - Unquoted `${CLAUDE_PROJECT_DIR}` in Git Bash shell form. Use exec form (`args`) or `"shell": "powershell"` with `"& \"$env:CLAUDE_PROJECT_DIR\\.claude\\hooks\\format-gd.ps1\""`.
   - jq is not installed.
   - gdformat/gdlint are not on PATH; use `$GDTOOLKIT_DIR` or the task runner.
   - Normalize backslash file_path.
   - Most important: exit 0 with stdout means Claude never sees the results. Emit JSON `hookSpecificOutput.additionalContext`, or exit 2 with the lint output on stderr, when problems are found.

18. Test plan: run it in the Desktop app (2.1.281), or update the CLI first. Add `/status`, `/permissions` and `claude doctor` checks for rejected rules, and test the PowerShell forms (`git push --force` via the PowerShell tool) as well as Bash.

## Windows notes


**Windows 11 Pro 10.0.26200 Specific Notes:**

1. **Sandboxing unavailable**: Bash sandbox (filesystem and network isolation) requires macOS, Linux, or WSL2. Native Windows has no sandbox. Permission rules are the only enforcement; rely on deny rules for security boundaries. If absolute isolation needed (e.g., preventing agents from writing to .git), a WSL2 session or managed CI runner is required.

2. **PowerShell vs Bash**: Claude Code v2.1.195 (current in session) may not have native PowerShell tool yet (added v2.1.84 March 2026+). Verify with `/status` or `claude --help`. If PowerShell tool is available, it is the native shell on Windows and shares permission rule syntax with Bash. If not available, Bash runs under Git Bash or WSL. The recommended approach is to commit Bash rules (tested, portable) in shared settings and add PowerShell equivalents when the tool is stable.

3. **Environment variable syntax**: In settings.json, use `$env:VARNAME` (PowerShell syntax) or bare `$VARNAME` (Bash in Git Bash). If Claude Code normalizes to one form, verify behavior. KICKOFF.md specifies setting `GODOT_BIN`, `PYTHON_BIN`, `GDTOOLKIT_DIR` via env; place these in `.claude/settings.local.json` (gitignored) so each developer's machine-specific paths don't leak to the repo.

4. **UNC paths prompt even as read-only**: Windows UNC network paths (\\server\share\file) trigger permission prompts in Bash/PowerShell even for read-only commands, because the OS may send the user's credentials to the host. If agents need to access shared drives, explicitly allow the rule or add a deny rule to prevent accidental access.

5. **Carriage return sensitivity**: Git is configured with `.gitattributes` to enforce LF for text files. Ensure Bash/PowerShell scripts in `.claude/hooks/` are LF-only (not CRLF); some Windows editors convert to CRLF on save, breaking shell script parsing. Use `git config core.autocrlf false` or edit `.gitattributes` to include hook scripts.

6. **Hook command syntax for Windows**: PostToolUse hooks run as command or HTTP. For Bash scripts on Windows, either:
   - Save as .sh and invoke via `bash .claude/hooks/format-gd.sh` in the hook
   - Save as .ps1 and invoke via `powershell .claude/hooks/format-gd.ps1`
   - Commit both and let Claude Code choose based on available shell
   
   The simplest is to save as .sh and rely on Git Bash, which ships with Git.

7. **Path anchoring in rules**: Relative paths in permission rules (e.g., `Edit(src/**)`) are anchored to the current working directory or the settings source (project root for .claude/settings.json). On Windows with mixed drive letters and WSL paths, use absolute paths with `//c/` (POSIX form of C:) or `~/` (home directory) to avoid confusion. Example: `Read(//c/Users/username/project/docs/**)`.


## Gotchas

- **Deny rules cannot be bypassed by PreToolUse hooks**: A `Bash(git push *)` deny rule will always block the command, even if a PreToolUse hook returns 'allow'. Hooks are for instrumentation (e.g., logging, linting), not security. If you want agents to sometimes push but not to `main`, use a hook to check the branch, not a PreToolUse hook that tries to override deny.
- **Environment variable rules may not match alternate invocations**: A rule `Bash($GODOT_BIN *)` matches 'C:\path\to\godot.exe args' only if Claude writes the literal env var. If Claude expands the variable inline or uses a full path, the rule may not match. Test with a dry run and use `--verbose` to see the exact command Claude writes.
- **Array merging across settings scopes**: Permission.allow rules from ~/.claude/settings.json COMBINE with rules from .claude/settings.json. If the personal file has `["Bash(npm test *)"]` and the shared file has `["Bash(npm run *)"]`, the effective allow list is both. This is powerful but can silently add approvals you didn't expect if a teammate's personal rule gets committed by mistake.
- **Workspace trust applies to shared settings only**: .claude/settings.json allow rules wait for 'Trust this folder?' on first run. .claude/settings.local.json rules don't wait (they're personal). If you add an allow rule to shared settings, every developer must trust the folder once before it takes effect.
- **PowerShell tool availability unclear**: KICKOFF.md lists Claude Code v2.1.195, but PowerShell native tool was added in v2.1.84 (March 2026, claimed). Research found some references to PowerShell tool issues (v2.1.84+), but your version may not have it. Verify with `claude --help` or `/status`. If only Bash is available, all rules must use `Bash` syntax; if PowerShell is available, add `PowerShell` equivalents to settings for Windows developers.
- **Sandboxing unavailable on native Windows, only WSL2**: The project environment specifies native Windows 11 Pro as primary. Filesystem and network isolation (sandbox) do not work natively. Permission rules (allow/deny/ask) are the sole enforcement mechanism. If a deny rule is accidentally removed or bypassed (e.g., by changing the command to `git -C . push`), there is no OS-level protection.
- **Settings.local.json auto-gitignore may fail on older git**: Claude Code auto-adds settings.local.json to `.git/info/exclude` or `core.excludesFile`. On very old git or if `core.excludesFile` points to a read-only location, the file may be tracked by mistake. Manually add `**/.claude/settings.local.json` to .gitignore as a safeguard.
- **Compound command approval splitting**: If an agent runs `git status && npm test` and you click 'Yes, and don't ask again', Claude Code saves two separate rules (`Bash(git status)` and `Bash(npm test *)`) rather than one rule for the whole compound. This is good for granularity but means your approval intent may be split in unexpected ways. Review saved rules after first-run approvals.
- **Read/Edit rules don't apply to subprocess file access**: A `Read(.env)` deny rule blocks Claude's Read tool and Bash commands that Claude Code recognizes (cat, grep, head, sed, tee). It does NOT block a Python script or Node script that Claude writes and then runs; those subprocesses access files outside Claude Code's enforcement. To block environment files at the OS level, enable sandbox network/filesystem isolation (not available on native Windows).
- **Glob patterns in allow rules are strict**: `Edit(src/**)` as an ALLOW rule matches only `<cwd>/src` and below, not nested `src` directories (e.g., `vendor/pkg/src`). But `Edit(src/**)` as a DENY rule matches `src` at any depth. This asymmetry is intentional (deny rules are more conservative) but confusing. Document your intent in CLAUDE.md.
- **PreToolUse hooks run BEFORE permission checks but AFTER tool lookup**: A hook can modify Claude's decision, but deny rules are checked regardless. If a hook tries to 'allow' a call that matches a deny rule, the deny rule wins. This means hooks cannot override security boundaries; they're for side effects (logging, validation, instrumentation).

## Open questions

- **Is PowerShell native tool available in v2.1.195?** Research found references to PowerShell tool at v2.1.84 (March 2026), but the session is running v2.1.195. Verify with `claude --help` | grep -i powershell or `/status` to see if PowerShell(…) rules are applicable now. If not, recommend an upgrade or switch to WSL2 for native Bash.
- **Can deny rules on '$GODOT_BIN' env-var-prefixed commands reliably prevent unintended invocations?** If Claude expands the env var inline (e.g., writes the full path instead of `$GODOT_BIN`), the rule `Bash($GODOT_BIN *)` won't match. A safer approach might be to create a wrapper script `godot` in PATH and allow `Bash(godot *)`, but that adds complexity. Recommend a dry run test: agent runs `$GODOT_BIN --version` and verify the rule matches.
- **Should the project use managed settings in the future?** The KICKOFF.md mentions coordination through GitHub Issues and the repo only. If an organization later wants to enforce team-wide permissions or deploy sandboxed CI, should those be considered managed settings or remain in .claude/settings.json? Recommend deferring; start with shared repo settings and migrate to managed if centralized control is needed.
- **Do 'Bash(git push *)' deny rules and PreToolUse hooks satisfy the KICKOFF.md requirement to prevent 'pushing to main'?** KICKOFF.md section 6 says 'Deny or require confirmation for: force-push, pushing to main, deleting branches, rm -rf-style deletes outside tools/out/.' A deny rule `Bash(git push *)` blocks all push commands, regardless of branch. To allow pushing to branches OTHER than main, you'd need to either: (a) remove the deny and instead use a PreToolUse hook to check the branch and deny conditionally, or (b) accept that agents must ask before any push and manually verify the branch. Which approach matches the project's risk tolerance?
- **Are read-only git commands (git status, git log, git diff) truly read-only in all contexts?** The KICKOFF.md trusts git status/diff/log as harmless, but git hooks can execute arbitrary code. If a developer's local git config includes a `post-checkout` or `pre-push` hook, does running `git status` or `git log` trigger hooks? If yes, should these commands require approval? Recommend testing with a dummy repo that has a hook and observing the behavior.
- **How should the designer's agent configuration differ from the engineer's if they share settings?** The KICKOFF.md section 6 says the designer's agent 'does not modify engine code' and works with content data instead. Should settings distinguish tool access per human, or should one shared settings.json accommodate both? For example, deny `Edit(core/**, server/**)` for the designer's agent? This requires either subagent-level tool restrictions or a second settings file per human.
- **What version of gdtoolkit (gdformat, gdlint) should be pinned?** KICKOFF.md specifies gdtoolkit 4.5.0. If the hook runs `gdformat` without a version check, a developer with a newer version might auto-format code differently than CI expects. Should the hook pin the version (e.g., `gdformat --version 4.5.0`) or should GDTOOLKIT_DIR point to a specific isolated installation?
- **Should the PostToolUse hook fail the edit if linting fails, or just warn?** The proposed hook exits 0 (success) and informs Claude of linting results. If you want to block edits that don't pass linting, change to exit code 2 (failure). This slows agents but enforces quality. Which is preferred: fast iteration with post-commit linting (via CI) or pre-commit validation (via hook)?
- **What should happen if a deny rule blocks an agent's work and the human must manually override?** For example, if agents need to edit `.github/workflows/` for CI work, a deny rule `Edit(.github/workflows/*)` blocks them. How should overrides work: (a) human temporarily removes the deny, agents run, human adds it back, or (b) deny rule is removed and a different enforcement (e.g., PreToolUse hook that requires explicit approval) takes over, or (c) humans create the workflow files and agents only edit existing patterns?
- **Is 'permissions.defaultMode: auto' safe to set in shared settings when auto mode is v2.1.283+ only?** The session is v2.1.195. If the setting says 'auto' but the session doesn't support auto mode (feature not yet in 2.1.195), Claude Code falls back to Manual mode. Should the shared settings.json stay at Manual (default) until the team upgrades, or commit 'auto' and accept the fallback?