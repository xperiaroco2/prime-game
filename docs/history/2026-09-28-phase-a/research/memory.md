# Claude Code memory: CLAUDE.md hierarchy, rules, imports, auto memory

## Summary

Comprehensive proposal for how Claude Code agents should manage project memory, CLAUDE.md hierarchy, and auto memory in the prime-game Godot multiplayer game repository. The project has two separate human users (engineer, designer) each running their own Claude Code session, with GitHub Issues as the single source of truth for moving state. Covers file locations and precedence, nested CLAUDE.md loading behavior, auto memory configuration, personal preferences separation, and concrete directory layout with size budgets. Key recommendation: Three-tier CLAUDE.md structure (root ≤150 lines + nested area-specific files + path-scoped rules) with auto memory enabled for learning, GitHub Issues as primary moving-state source, personal preferences in ~/.claude/CLAUDE.md and .claude/settings.local.json.

## Facts (with verification)

- **memory-01** [corrected] CLAUDE.md precedence order: managed policy → ~/.claude/CLAUDE.md (user) → ./CLAUDE.md or ./.claude/CLAUDE.md (project) → CLAUDE.local.md. Nested CLAUDE.md in subdirectories load on demand when Claude reads files there, not at startup.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: This is a LOAD order, not a precedence or override order. Files load as managed policy (Windows: C:\Program Files\ClaudeCode\CLAUDE.md), then ~/.claude/CLAUDE.md, then ./CLAUDE.md or ./.claude/CLAUDE.md, then ./CLAUDE.local.md. All of them are concatenated and none overrides another. Files from the filesystem root down to the working directory are ordered root-first. Within each directory, CLAUDE.local.md is appended after CLAUDE.md. When two instructions conflict, Claude 'may pick one arbitrarily'. Subdirectory CLAUDE.md and CLAUDE.local.md files load on demand, when Claude reads files in that subdirectory.
  - note: The second sentence is correct. Calling it 'precedence' is misleading: a later file does not win. It is only read later.
  - evidence: https://code.claude.com/docs/en/memory.md
- **memory-02** [confirmed] Nested CLAUDE.md files (e.g., core/CLAUDE.md, content/CLAUDE.md) do NOT load at session start; they load on demand when Claude opens a file in that directory. This keeps area-specific rules out of every session's context.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-03** [confirmed] After /compact, project-root CLAUDE.md survives and re-injects; nested CLAUDE.md files and path-scoped rules reload as Claude reads files they apply to. Conversation history and some context is replaced with a summary.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-04** [confirmed] Auto memory enabled by default; stored per-project at ~/.claude/projects/<project>/memory/ (derives from git repo, so all worktrees share one auto memory). First 200 lines or 25KB of MEMORY.md loads at startup; topic files load on demand via file Read.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-05** [confirmed] Auto memory is machine-local (not shareable across developers). Each project's memory directory is tied to the git repo path on that machine. Worktrees within same repo share one memory directory.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-06** [confirmed] .claude/rules/*.md files (path-scoped rules) can use YAML frontmatter with `paths:` glob patterns. Rules without paths load at startup like CLAUDE.md; path-scoped rules load when Claude works with matching files. Subdirectories in .claude/rules/ are auto-discovered.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-07** [confirmed] CLAUDE.md can import files using @path/to/file syntax (relative or absolute). Maximum import depth is 4 hops. External imports (outside working directory) require approval dialog first time. Imported files expand and load at startup, increasing context; splitting is for organization only.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-08** [confirmed] claudeMdExcludes setting (array of glob patterns) skips specific CLAUDE.md and rules files by path. Useful for monorepos to exclude other teams' areas. Managed policy CLAUDE.md cannot be excluded. Can be set at user, project, local, or policy scope.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-09** [corrected] CLAUDE.md files should target under 200 lines for best adherence. Files over 4 MiB are skipped entirely. Combined CLAUDE.md + rules files that exceed recommended length trigger warnings at startup and via /status. Use path-scoped rules to reduce context load.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: Target under 200 lines per CLAUDE.md file. Files over 4 MiB are skipped. If ONE instruction file is over the recommended length, a warning appears at startup and in /status. A separate warning appears at session start when files that are each within the limit add up past a combined limit. Each CLAUDE.md, rules file and @import counts as its own file. Path-scoped rules reduce what loads at startup. @imports do NOT reduce it.
  - note: The claim merged the per-file and combined warnings into one mechanism.
  - evidence: https://code.claude.com/docs/en/memory.md
- **memory-10** [corrected] /init command generates a starter CLAUDE.md from codebase analysis. Setting CLAUDE_CODE_NEW_INIT=1 enables interactive multi-phase flow covering CLAUDE.md, skills, hooks, and personal memory. /init also imports config from other tools (AGENTS.md, .cursor/rules/, .copilot-instructions.md).  
  src: https://code.claude.com/docs/en/commands.md (official-docs)
  - CORRECTED: /init generates a starter CLAUDE.md, or suggests improvements if one already exists. With CLAUDE_CODE_NEW_INIT=1 it becomes an interactive flow that asks which artifacts to create (CLAUDE.md files, skills, hooks, and a personal CLAUDE.local.md option), explores with a subagent, and presents a proposal before writing anything. By default /init reads .cursor/rules/, .cursorrules and .github/copilot-instructions.md. AGENTS.md, .devin/rules, .windsurf/rules and .clinerules are read only when NEW_INIT is set. Codex and Gemini config is handed to /import (v2.1.213+).
  - note: The Copilot filename is .github/copilot-instructions.md, not '.copilot-instructions.md'. Plain /init does NOT read AGENTS.md. Supporting evidence: https://code.claude.com/docs/en/commands.md
  - evidence: https://code.claude.com/docs/en/memory.md
- **memory-11** [confirmed] /memory command opens CLAUDE.md, CLAUDE.local.md, and auto memory files in editor. Lists locations for user and project scopes. Allows toggling auto memory on/off (saves to ~/.claude/settings.json). /context shows which memory files loaded in current session.  
  src: https://code.claude.com/docs/en/commands.md (official-docs)
- **memory-12** [corrected] Claude desktop app Code tab and CLI share the same memory system. Both read project CLAUDE.md, CLAUDE.local.md, .claude/rules/, and auto memory from ~/.claude/projects/<project>/memory/. Sessions are independent but use same underlying files.  
  src: https://code.claude.com/docs/en/desktop.md (official-docs)
  - CORRECTED: The desktop Code tab and the CLI run the same engine and read the same CLAUDE.md, CLAUDE.local.md and settings files, and auto memory lives in the same ~/.claude/projects/<project>/memory/. BUT on this machine the desktop app runs its OWN bundled Claude Code v2.1.281 (C:\Users\xperi\AppData\Roaming\Claude\claude-code\2.1.281\claude.exe), while the terminal `claude` on PATH is v2.1.195. Version-gated memory features therefore differ between the two surfaces.
  - note: desktop.md: 'They share configuration and project memory via CLAUDE.md files.' It does not explicitly mention auto memory or .claude/rules. The version split comes from a local check of CLAUDE_CODE_EXECPATH vs `claude --version`. The '2.1.195' figure in the project context is the CLI only.
  - evidence: https://code.claude.com/docs/en/desktop.md
- **memory-13** [corrected] CLAUDE.local.md is gitignored by convention for personal, project-specific overrides. It loads alongside CLAUDE.md with same precedence logic. Use for personal preferences, sandbox URLs, test credentials that should not be committed.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: CLAUDE.local.md is for personal project-specific preferences (the docs' examples are sandbox URLs and preferred test data). You must add it to .gitignore yourself; the NEW_INIT personal option does this for you. Within each directory it is appended after CLAUDE.md. It exists only in the worktree where you created it. To share personal instructions across worktrees, import a file from home, e.g. @~/.claude/my-project-instructions.md.
  - note: The docs never suggest credentials. Putting test credentials in CLAUDE.local.md would inject them into model context on every session. The worktree caveat matters because KICKOFF 5.4 prefers worktrees.
  - evidence: https://code.claude.com/docs/en/memory.md
- **memory-14** [confirmed] User-level ~/.claude/CLAUDE.md applies to all projects on the machine. Loaded before project CLAUDE.md so project instructions appear later in context. Use for personal coding style, workflow preferences, personal tool shortcuts.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-15** [corrected] Subagents can maintain their own auto memory if enabled in frontmatter with `memory: true`. Each subagent's memory is separate from parent session and other subagents. Not loaded in main session; keeps research out of parent context.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: Subagent memory is enabled with the frontmatter field `memory: user|project|local`, not `memory: true`. The directories are ~/.claude/agent-memory/<agent>/ (user), .claude/agent-memory/<agent>/ (project, committable, and the docs' recommended default), or .claude/agent-memory-local/<agent>/. It stays separate from the main session's auto memory. It has no effect when auto memory is disabled. When enabled, the first 200 lines or 25KB of its MEMORY.md go into the subagent's system prompt, and Read/Write/Edit are enabled automatically.
  - note: `memory: true` is not a documented value. Project scope is shared through git, so this memory is not necessarily machine-local.
  - evidence: https://code.claude.com/docs/en/sub-agents.md
- **memory-16** [corrected] /doctor prompt-audit (requires v2.1.283+) audits CLAUDE.md and rules files for outdated guidance, references to non-existent files, conflicting instructions, and suggestions for trimming per codebase. Requires /claude-api skill enabled.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: `/doctor prompt-audit [path]` (v2.1.283+) reads CLAUDE.md, CLAUDE.local.md, AGENTS.md and the rules, skills, commands, subagents and output styles under .claude/ and ~/.claude/. It flags instructions written for older models, references to missing files or commands, and contradictions. It proposes edits and applies nothing without asking. It runs through the bundled /claude-api skill and is unavailable if that skill is disabled. Trimming CLAUDE.md is a different feature: the plain /doctor checkup (v2.1.206+).
  - note: prompt-audit is NOT available on this machine today: desktop bundles 2.1.281 and the CLI is 2.1.195, both below 2.1.283.
  - evidence: https://code.claude.com/docs/en/memory.md
- **memory-17** [confirmed] AGENTS.md support (v2.1.277+): Claude reads AGENTS.md only when no CLAUDE.md/.claude/CLAUDE.md/CLAUDE.local.md exist in working directory or parents. Can be configured with 'Project instructions' setting to read both, CLAUDE.md only, or managed-only. Not relevant for prime-game which will have project CLAUDE.md.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-18** [confirmed] autoMemoryDirectory setting (in any settings scope) stores auto memory at custom path instead of ~/.claude/projects/<project>/memory/. Must be absolute or start with ~/. Useful for custom storage but remains machine-local.  
  src: https://code.claude.com/docs/en/settings-reference.md (official-docs)
- **memory-19** [corrected] autoMemoryEnabled setting (boolean, any scope) toggles auto memory on/off. Default is on. Can disable globally (user settings), per-project (project settings), or via CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 env var. Subagents inherit from parent unless they have their own memory.  
  src: https://code.claude.com/docs/en/settings-reference.md (official-docs)
  - CORRECTED: autoMemoryEnabled is a boolean at any scope and defaults to true. /memory writes it to user settings. Setting it in the project's .claude/settings.json turns it off per project. CLAUDE_CODE_DISABLE_AUTO_MEMORY overrides it for one session in either direction: 1 disables, 0 forces it on even with --bare or autoMemoryEnabled:false. Subagents do NOT inherit the parent's auto memory. The main conversation's auto memory is never loaded into a non-fork subagent. Only a subagent's own `memory` field gives it memory, and that also stops working when auto memory is off.
  - note: The claim 'Subagents inherit from parent' is wrong. See also https://code.claude.com/docs/en/settings-reference.md and https://code.claude.com/docs/en/env-vars.md
  - evidence: https://code.claude.com/docs/en/sub-agents.md
- **memory-20** [corrected] Context window startup order: system prompt → auto memory → environment info → MCP tools (deferred) → skills (descriptions only, not full content) → ~/.claude/CLAUDE.md → project CLAUDE.md → .claude/rules/ (non-path-scoped) → subagent declarations. Path-scoped rules load on demand.  
  src: https://code.claude.com/docs/en/context-window.md (official-docs)
  - CORRECTED: The context-window page is an ILLUSTRATIVE timeline with representative token counts. Its startup sequence is: system prompt, auto memory (MEMORY.md), environment info, MCP tools (deferred), skill descriptions, ~/.claude/CLAUDE.md, project CLAUDE.md. That timeline does not show '.claude/rules/' or 'subagent declarations' entries. Separately, memory.md says unscoped rules load at launch with the same priority as .claude/CLAUDE.md, and that CLAUDE.md content arrives as a user message after the system prompt.
  - note: Checked both the .md and the rendered page source: the startup events end at 'Project CLAUDE.md'. Treat any exact ordering as non-normative.
  - evidence: https://code.claude.com/docs/en/context-window.md
- **memory-21** [corrected] Best practice: target CLAUDE.md under 200 lines per file. Include build/test commands, coding standards, naming conventions, architectural decisions, gotchas. Exclude: directory layouts, API docs (link instead), architecture Claude can derive from code, self-evident practices.  
  src: https://code.claude.com/docs/en/best-practices.md (official-docs)
  - CORRECTED: best-practices.md does not give a line number. Its test is 'Would removing this cause Claude to make mistakes?' (the <200-lines target comes from memory.md and the context-window page). Include: Bash commands Claude can't guess, style rules that differ from defaults, test instructions, repo etiquette (branch naming, PR conventions), project-specific architectural decisions, dev-environment quirks (required env vars), gotchas. Exclude: anything derivable from code, standard language conventions, detailed API docs (link instead), INFORMATION THAT CHANGES FREQUENTLY, long tutorials, file-by-file descriptions, self-evident practices.
  - note: The claim's list leaves out 'information that changes frequently', which directly supports KICKOFF's issues-not-docs rule. memory.md lists 'project layout' as acceptable content, while /doctor trims directory layouts, so 'exclude directory layouts' is only partly supported.
  - evidence: https://code.claude.com/docs/en/best-practices.md
- **memory-22** [confirmed] Skills vs CLAUDE.md: use CLAUDE.md for context Claude always needs (coding standards, workflows). Use skills for procedures you invoke manually, reference material that loads on demand, or large multi-step workflows. Skills descriptions (name + one-liner) load at startup; full content loads only when skill is used.  
  src: https://code.claude.com/docs/en/skills.md (official-docs)
- **memory-23** [corrected] Personal preferences (chat language, verbosity, personal shortcuts) belong in ~/.claude/CLAUDE.md and .claude/settings.local.json (gitignored). Never in project CLAUDE.md or .claude/settings.json. Two humans' agents each read their own ~/.claude/ when they run.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: memory.md puts all-project personal preferences in ~/.claude/CLAUDE.md (or ~/.claude/rules/) and personal project-specific preferences in CLAUDE.local.md (not settings.local.json, which holds JSON settings and cannot carry prose instructions). Chat language has a dedicated setting, `language` (e.g. "ukrainian"), valid at any scope and best placed in ~/.claude/settings.json. It is passed verbatim as a 'respond in X' instruction and also sets the /voice dictation language (Ukrainian 'uk' is supported) and session titles. The 'never in shared files' rule comes from KICKOFF §6, not the docs; memory.md only says to focus project CLAUDE.md on project-level standards.
  - note: Also: on Windows, .claude/settings.local.json is read from the session's starting directory, so desktop worktree sessions under .claude/worktrees/ do not see the main checkout's copy (settings.md, worktrees.md). User-level settings avoid this problem.
  - evidence: https://code.claude.com/docs/en/settings-reference.md
- **memory-24** [corrected] KICKOFF.md section 5.2 prescribes: root CLAUDE.md (≤150 lines), nested CLAUDE.md for core/, net/, voice/ (engineer), content/, levels/ (designer). section 5.4: docs/INTERVENTIONS.md logs append-only rules from human corrections, each as self-contained block to avoid merge conflicts.  
  src: D:\prime-game\KICKOFF.md (repo)
  - CORRECTED: KICKOFF §5.2 prescribes a root CLAUDE.md (≤150 lines, shared) plus nested CLAUDE.md in core/, net/, voice/ (engineer-facing) and content/, levels/ (designer-facing). docs/INTERVENTIONS.md is ALSO defined in §5.2, not §5.4 (§5.4 is Branching and PRs): 'append-only log of human interventions and the rule each one produced', with each entry a self-contained block appended at the end.
  - note: Wrong section number. KICKOFF §7 (M0) and §9.2 also make the CLAUDE.md files, including the designer-facing ones, M0 deliverables.
  - evidence: D:\prime-game\KICKOFF.md
- **memory-25** [confirmed] KICKOFF.md: personal preferences (like engineer's Ukrainian chat language) belong in ~/.claude/CLAUDE.md, NOT shared project files. Durable knowledge in docs (rarely changes); moving state in GitHub Issues (constantly changes).  
  src: D:\prime-game\KICKOFF.md (repo)
- **memory-26** [confirmed] KICKOFF.md: agents must self-verify from CLI (tests, headless runs, screenshots). If something cannot be verified by agent, state explicitly and tell human exactly what to check and how. Do not claim something works unless you ran it.  
  src: D:\prime-game\KICKOFF.md (repo)
- **memory-27** [corrected] HTML comments (<!-- comment -->) in CLAUDE.md are stripped before context injection. Use for maintainer notes without consuming tokens. Comments inside code blocks are preserved. Comments visible when file is read directly with Read tool.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
  - CORRECTED: BLOCK-LEVEL HTML comments (<!-- ... -->) in CLAUDE.md are stripped before injection. Comments inside code blocks are kept. The comments remain visible when the file is opened with the Read tool.
  - note: The docs specify block-level comments only, so don't rely on inline comments being stripped. This is useful for zero-token provenance links from a rule back to its INTERVENTIONS entry.
  - evidence: https://code.claude.com/docs/en/memory.md
- **memory-28** [confirmed] Nested CLAUDE.md example: running Claude from foo/bar/ loads foo/bar/CLAUDE.md, foo/CLAUDE.md, and all ancestor CLAUDE.md files. Content is concatenated root-to-leaf order, so bar/CLAUDE.md appears last. Subdirectories under bar/ load on demand when files there are read.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-29** [confirmed] autoMemoryEnabled can be toggled via /memory UI (saves to ~/.claude/settings.json globally) or set in project .claude/settings.json for that project only. Auto memory decisions depend on whether information is useful in future conversation and not already in CLAUDE.md.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)
- **memory-30** [confirmed] For large projects, /doctor checkup proposes trimming checked-in CLAUDE.md by cutting content Claude can derive (directory layouts, tech-stack lists, architecture overviews) while keeping gotchas, rationale, non-standard conventions. Available v2.1.206+.  
  src: https://code.claude.com/docs/en/memory.md (official-docs)

## Missed facts (from verifier)

- **missed-01** A first-class `language` setting (any scope) makes Claude respond in the named language. Its value is passed verbatim, e.g. "language": "ukrainian". The same value sets the /voice dictation language (Ukrainian 'uk' is supported; unsupported languages fall back to English for dictation only) and auto-generated session titles. For the engineer, who dictates by voice, ~/.claude/settings.json {"language":"ukrainian"} plus one line in ~/.claude/CLAUDE.md ('Never reply in Russian') is sturdier than prose alone.  
  src: https://code.claude.com/docs/en/settings-reference.md
- **missed-02** On Windows, .claude/settings.local.json is kept and read in the session's starting directory, not the repository root. In a worktree, permission approvals stay with that worktree. CLAUDE.local.md exists only in the worktree where it was created. The desktop app puts worktrees in <repo>/.claude/worktrees/. Gitignored files are copied into new worktrees only when listed in a root `.worktreeinclude` file (gitignore syntax).  
  src: https://code.claude.com/docs/en/worktrees.md
- **missed-03** Path-scoped rules and nested CLAUDE.md files are loaded into message history, so compaction summarizes them away. They return only when a matching file is read again. The docs say: 'If a rule must persist across compaction, drop the paths: frontmatter or move it to the project-root CLAUDE.md.'  
  src: https://code.claude.com/docs/en/context-window.md
- **missed-04** When a user tells Claude to 'remember X', Claude saves it to auto memory, not CLAUDE.md, unless told 'add this to CLAUDE.md'. Auto memory is machine-local and never shared across machines. It has a 'project' type for 'ongoing work, deadlines, and decisions'.  
  src: https://code.claude.com/docs/en/memory.md
- **missed-05** The docs give explicit triggers for adding to CLAUDE.md: Claude repeats a mistake, code review catches something Claude should have known, the same correction is typed again, or a new teammate would need it. They also give routing rules: a multi-step procedure becomes a skill, something that matters for one part of the codebase becomes a path-scoped rule or nested CLAUDE.md, and anything that must happen at a fixed point (every edit, every commit) becomes a hook, because CLAUDE.md is advisory. The large-codebases guide suggests reviewing CLAUDE.md edits in PRs and a Stop hook that reads the transcript and proposes CLAUDE.md updates.  
  src: https://code.claude.com/docs/en/memory.md
- **missed-06** Version split on this machine: the desktop Code tab runs bundled Claude Code 2.1.281 (CLAUDE_CODE_EXECPATH=...\AppData\Roaming\Claude\claude-code\2.1.281\claude.exe), while the PATH `claude` is 2.1.195. Memory features gated above 2.1.195 include: /doctor CLAUDE.md trim (2.1.206), AGENTS.md reading (2.1.277), rules-glob fixes (2.1.207/2.1.217), the memory `modified` timestamp (2.1.214), and settings.local.json repo-root placement (2.1.211). /doctor prompt-audit (2.1.283) is unavailable on BOTH surfaces.  
  src: https://code.claude.com/docs/en/commands.md
- **missed-07** Custom subagents load the full CLAUDE.md hierarchy, including ~/.claude/CLAUDE.md, rules, CLAUDE.local.md and managed files. They do NOT get the main session's auto memory. Built-in Explore and Plan skip CLAUDE.md entirely. `omitClaudeMd: true` (v2.1.271+) skips user, project and local CLAUDE.md for a custom subagent. Rules that must reach Explore or Plan must be restated in the delegation prompt.  
  src: https://code.claude.com/docs/en/sub-agents.md
- **missed-08** The InstructionsLoaded hook fires for every CLAUDE.md or rules load with load_reason session_start, nested_traversal, path_glob_match, include or compact, and reports trigger_file_path. /context lists the loaded 'Memory files'. Together they let an agent verify that nested files and path rules actually load.  
  src: https://code.claude.com/docs/en/hooks.md
- **missed-09** The large-codebases guide gives a decision rule. Use a per-directory CLAUDE.md when 'directory owners maintain their own conventions; instructions are versioned with the code'. Use a path-scoped rule in the central .claude/rules/ when 'you want all conventions in one place, or the same rule applies to many scattered paths'. Nested .claude/rules/ directories inside subdirectories also load on demand.  
  src: https://code.claude.com/docs/en/large-codebases.md
- **missed-10** If a CLAUDE.md sets commit or PR rules (Conventional Commits, PR template), Claude Code's built-in git instructions compete with them. The docs say to turn those off with `includeGitInstructions: false` (which also removes the git status snapshot) and to set the `attribution` setting.  
  src: https://code.claude.com/docs/en/memory.md

## Options

### Option A: Single root CLAUDE.md + nested area files + auto memory enabled
One lean root CLAUDE.md (≤150 lines) with repository-wide rules (build commands, commit style, ownership). Each area (core/, net/, voice/, content/, levels/) has its own nested CLAUDE.md (engineer-facing vs designer-facing). Auto memory enabled globally. Path-scoped rules in .claude/rules/ for file-type-specific guidance. Personal prefs in ~/.claude/CLAUDE.md per human.
- pros: Aligns with KICKOFF.md section 5.2 explicit recommendation; Lean startup context: root + auto memory only at session start; Nested files load on demand, no bloat for irrelevant areas; Clear ownership: each subsystem owner maintains their nested file; Auto memory captures lessons from interventions without manual CLAUDE.md edits; Path-scoped rules keep file-type rules out of general context; Personal prefs stay separate, no merges when Ukrainian/English language differs; Git-friendly: few conflicts, each owner has their area
- cons: Requires discipline to keep root file short (easy to let it grow); Auto memory is machine-local, not shared between engineer/designer sessions; GitHub Issues must be the primary for moving state (memory is secondary); More files to maintain (root + 5+ nested + rules/); Path-scoped rules still load into context when matching files open (cost if over-specified); New people ramp slower if they don't read all nested files upfront
### Option B: Single large root CLAUDE.md with no nesting + auto memory disabled
All project conventions in one root CLAUDE.md file (~300-400 lines total, compromising the 200-line recommendation). Split into sections: Commands, Ownership (engineer vs designer areas), Godot API rules, Networking/Voice, Content/Design, Test/Verify. No nested files. Auto memory disabled. All lessons from interventions manually added to root CLAUDE.md. Everything shared between sessions.
- pros: Simpler mental model: one file to read for all rules; No on-demand loading complexity (all rules in context from start); Clear single source of truth; no file discovery needed; Easier onboarding for new people (one file to read)
- cons: Violates KICKOFF.md explicit recommendation for nested files per area; Higher startup context cost: bloats every session even when working on one area; Greater merge conflict risk: root file touched by both humans constantly; Less scalable: as content API and mechanics grow, file becomes unmanageable; Auto memory disabled means no passive learning from corrections; Personal prefs (language) leak into shared file (must use comments); KICKOFF.md says durable knowledge (docs) rarely changes; this file changes constantly; Harder to keep under 200-line recommendation; Claude's adherence suffers
### Option C: Nested CLAUDE.md files only (no root) + auto memory + skills for workflows
No root CLAUDE.md. Each area (core/, net/, etc.) has its own CLAUDE.md (4–5 files total, ~100 lines each). Repository-wide rules (build commands, commit style) in .claude/rules/*.md as path-scoped or non-scoped rules. Workflows (new-mechanic, start-task, finish-task) live in .claude/skills/. Auto memory enabled. Personal prefs in ~/.claude/CLAUDE.md.
- pros: Extremely lean startup context: only ancestor CLAUDE.md files load (empty if starting from root); Perfect scalability: add areas without bloating existing contexts; Clear separation: area rules live with area code; Skills handle workflows (no need to put procedures in CLAUDE.md); Rules can be organized by topic (.claude/rules/godot-api.md, .claude/rules/git.md); Strong read separation: designer agent never loads core/net/voice files
- cons: Significantly deviates from KICKOFF.md, which explicitly calls for root CLAUDE.md with 'hard rules'; Starting Claude from repo root loads no area rules until files are opened (disorienting for new sessions); Harder to enforce repository-wide conventions (no single 'this applies everywhere' file); Subagents starting from root have no guidance until they navigate to a specific area; History/roadmap (ROADMAP.md) not anchored with any CLAUDE.md; New contributor must explore directory structure to find relevant CLAUDE.md files; Rules duplication risk (multiple ways to express same rule across files)
### Option D: Root CLAUDE.md + .claude/rules only (no nested CLAUDE.md files) + auto memory
Single root CLAUDE.md (≤150 lines) with repository-wide rules, build commands, definitions of done, ownership map. All area-specific and file-type-specific rules in .claude/rules/*.md, including non-scoped rules for core/net/voice/content/levels and path-scoped rules for file types. No nested CLAUDE.md files. Auto memory enabled. Personal prefs in ~/.claude/CLAUDE.md.
- pros: Aligns with KICKOFF.md: root CLAUDE.md with hard rules; Single file for shared context; all derived from one location; Avoids duplicate/conflicting rules across nested files; Lean startup context (just root CLAUDE.md loaded at start); Rules centralized in .claude/rules/: easier to govern and review; Path-scoped rules reduce context load for specific file types; Good for both engineer and designer (both see root rules)
- cons: Violates KICKOFF.md section 5.2 which explicitly recommends nested CLAUDE.md per area; All rules in .claude/rules/ must be discovered via file names (no narrative structure); Path-scoped rules proliferate if used to replace nested files (subdirectories in .claude/rules/ hard to manage); Designer-facing rules (content/levels) and engineer-facing rules (core/net/voice) lumped together; Area owners don't own their rules (all under .claude/, not in their directory); Harder to inherit rules when starting from a subdirectory (would need CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD)

## Recommendation

**Recommend Option A: Single root CLAUDE.md (≤150 lines) + nested area files + auto memory enabled + .claude/rules/ for path-scoped rules.**

Rationale:
1. **Alignment with project intent**: KICKOFF.md section 5.2 explicitly prescribes root CLAUDE.md (≤150 lines) plus nested CLAUDE.md in core/, net/, voice/, content/, levels/. This is the declared architecture.

2. **Two humans, different areas**: Engineer owns core/net/voice; designer owns content/levels. Each has their own nested CLAUDE.md versioned with their code. When engineer's agent reads core/auth.gd, it auto-loads core/CLAUDE.md with engine-specific rules. Designer's agent reading content/role.tres loads content/CLAUDE.md with mechanics-composition rules. No cross-contamination.

3. **GitHub Issues as primary**: KICKOFF.md section 5.1 states moving state lives in GitHub Issues. Auto memory is secondary and machine-local. Memory captures Claude's learnings (build-command patterns, gotchas), not project state. This keeps the architecture clean.

4. **Startup efficiency**: At session start, only root + auto memory load (est. ~2–3KB of tokens). Nested files and path-scoped rules load on demand. For a session focused on one area, context stays lean.

5. **Personal preferences isolation**: Engineer's Ukrainian language preference and designer's preferences stay in their own ~/.claude/CLAUDE.md and .claude/settings.local.json (gitignored). No merge conflicts; each human's session respects their own settings.

6. **Scalability**: As content API and mechanics grow (M2+), nested area files can grow without bloating the root or other areas. Root stays a stable governance document.

7. **Handles interventions cleanly**: KICKOFF.md section 5.2 calls for append-only INTERVENTIONS.md log. Auto memory captures lessons from those interventions. When a lesson becomes permanent policy, it can be promoted from auto memory to the relevant nested CLAUDE.md or rule, then removed from memory.

**Implementation sequence** (Phase A step 4 feedback):
- Write root CLAUDE.md now (~100 lines: ownership, commands, workflow, definition of done)
- Write nested CLAUDE.md files for each area (core, net, voice, content, levels) after M0 when area boundaries solidify
- Use .claude/rules/ for file-type-specific rules (Godot version checks, typing rules, test patterns)
- Enable auto memory; review quarterly to promote lessons to permanent rules
- Keep personal prefs in ~/.claude/CLAUDE.md per human (engineer: language setting, designer: design preferences)

## Verifier critique of recommendation

The broad direction is right and matches KICKOFF §5.2 and the docs' large-codebases guidance: a lean root CLAUDE.md, nested per-area CLAUDE.md files versioned with the code, and a few path-scoped rules. Several parts of the recommendation are wrong or contradict the brief:

1. **INTERVENTIONS go to the wrong place.** Routing lessons into AUTO MEMORY breaks the project's core coordination rule. Auto memory is machine-local, so a lesson from the engineer's correction never reaches the designer's agent. Its 'project' memory type also becomes a second, uncommitted source of work state, which KICKOFF §5 and §6 forbid. The flow should be:
   - The agent appends a self-contained INTERVENTIONS.md entry.
   - It promotes the rule, in the same PR, to the right committed mechanism, using the docs' routing: always-needed goes to root; one area goes to nested CLAUDE.md or a path rule; a procedure goes to a skill; must-happen goes to a hook.
   - The entry records the file and section changed. A block-level HTML comment in the rule can link back to the entry at zero token cost.
   - Root CLAUDE.md should tell agents not to use auto memory for shared rules or task state. 'Review quarterly' is far too slow.

2. **Deferring nested CLAUDE.md to after M0 contradicts the brief.** KICKOFF §7 and §9.2 make the CLAUDE.md files, especially the designer-facing content/ and levels/ ones, M0 deliverables.

3. **Compaction is ignored.** Nested files and path rules vanish after /compact until a matching file is re-read. Architecture invariants (host authority, per-peer filtering, the designer never editing engine code, Godot-3-is-a-bug) must therefore sit in root, not only in core/CLAUDE.md.

4. **Personal preferences leak into the shared root.** The sample root CLAUDE.md puts chat language in the shared file ('Chat language: Ukrainian', 'English (default)'). That contradicts KICKOFF §6 and the researcher's own claim 23, and it assumes the designer's language. The dedicated `language` setting in ~/.claude/settings.json was missed. The designer's 'check ARCHITECTURE.md for the content API' is a project rule and belongs in content/CLAUDE.md, not a personal file.

5. **Unverified or invented content.**
   - `dotnet tools.csx ...` is not a real or agreed runner. KICKOFF §4 proposes a GDScript or Python entry point with .ps1/.sh wrappers, the Godot build is non-.NET, and .csx is not natively runnable by dotnet. The list also drops the lint, host and join commands.
   - The '~2–3KB at startup' estimate is unmeasured and should be checked with /context.
   - 'Nested CLAUDE.md for your area (loads automatically)' is misleading: files load only on read.

6. **Surface and version split not addressed.** The humans' desktop sessions run 2.1.281 and the CLI runs 2.1.195, so /doctor prompt-audit is unavailable and trim checks work only in the desktop app. With worktrees on Windows, settings.local.json and CLAUDE.local.md don't follow into worktree sessions.

7. **Options are not presented for approval.** The user asked for options, not applied decisions. AGENT_WORKFLOW.md should list them:
   - (a) auto memory on, with a CLAUDE.md guardrail, vs off per project via .claude/settings.json;
   - (b) personal preferences via the `language` setting and ~/.claude/CLAUDE.md vs CLAUDE.local.md with .worktreeinclude;
   - (c) includeGitInstructions on vs off;
   - (d) enforcing the line budget with a `verify` check that counts CLAUDE.md and rules lines (a project convention, not a docs feature).

   Budget framing: KICKOFF's ≤150 lines is stricter than the docs' 200 and is fine. The budget should count root plus unscoped rules together, because both load at launch and each triggers the docs' per-file and combined warnings.

## Concrete config (researcher)

## Concrete Configuration Proposal

### File Structure (Phase A)

```
D:\prime-game\
├── CLAUDE.md                          # Root: ≤150 lines, shared ownership map, commands, workflow
├── .claude\
│   ├── settings.json                  # Shared: permissions allowlist, hooks (PostToolUse for gdformat)
│   ├── settings.local.json            # Gitignored: env vars (GODOT_BIN, GDTOOLKIT_DIR, PYTHON_BIN)
│   ├── rules\
│   │   ├── godot-api.md               # Godot 4.x only, no Godot 3, strict typing
│   │   ├── git-workflow.md            # Commit conventions (area: prefix), branch naming
│   │   ├── test-patterns.md           # Paths: **/*.test.gd | GdUnit4 patterns, no mocks of core/
│   │   └── netcode-security.md        # Paths: core/server/net/ | Per-peer filtering, no leaks
│   └── skills\
│       ├── start-task\SKILL.md        # Shared: read issue, check docs, restate plan
│       └── finish-task\SKILL.md       # Shared: run verify, write handoff, open PR
├── core\
│   └── CLAUDE.md                      # Will add in M0+: host-authoritative, RefCounted, no Nodes
├── net\
│   └── CLAUDE.md                      # Will add in M0+: intent/event protocol, filtering, serialization
├── voice\
│   └── CLAUDE.md                      # Will add in M0+: audio pipeline, jitter buffer, routing
├── content\
│   └── CLAUDE.md                      # Will add in M0+: Resources, triggers, conditions, effects, composition
├── levels\
│   └── CLAUDE.md                      # Will add in M0+: sub-scenes, reusable rooms, interactables
└── docs\
    └── INTERVENTIONS.md               # Append-only: rule + context for each human decision

# Per human (gitignored, personal machine only)
~/.claude\
├── CLAUDE.md                          # Personal: language (eng:  \"Use English\" | ukr: \"Use Ukrainian\"), shortcuts
└── settings.json                      # Personal: effort level, model preference per machine
```

### Root CLAUDE.md (~120 lines)

```markdown
# prime-game — Multiplayer Social Deduction in Godot 4.7.2

## Ownership & Communication

**Engineer** (core owner): game rules engine, networking, host logic, voice pipeline, tooling, CI, architecture.
- Chat language: Ukrainian (read from ~/.claude/CLAUDE.md)
- Areas: core/, net/, voice/, tools/, .github/, CLAUDE.md, docs/ARCHITECTURE.md

**Game Designer** (content owner): mechanics design, roles/abilities/items/tasks as data, level design, balancing, GDD.
- Chat language: English (default)
- Areas: content/, levels/, docs/GDD.md, docs/design/

Coordination through GitHub Issues + this repo only. No moving state in chat or memory files.

## Meta Rules

- **Humans write zero code.** Agents write everything and self-verify from CLI.
- **Verify always.** If you cannot verify something, state explicitly and tell the human exactly what to check and how.
- **Never skip or delete a test.** Never claim something works unless you ran it and saw the output.

## Godot & Stack

- **Engine**: Godot 4.7.2 standard build (pin exact version in CI, task runner, ADRs)
- **Language**: Statically typed GDScript (typed vars, typed arrays, typed signal args, class_name)
- **Tests**: GdUnit4 6.2.1 headless from CLI
- **Lint**: gdtoolkit 4.5.0 (gdformat, gdlint)
- **Networking**: High-level multiplayer, start with ENet; transport behind abstraction
- **Voice**: Opus-based addon (M1 spike to verify Windows build first)
- **Dev environment**: Native Windows 11 (Godot console exe on PATH via env var GODOT_BIN)

## Commands (Windows PowerShell or Git Bash)

All scripts read from tools/ runner (cross-platform wrapper):

- `dotnet tools.csx doctor` — check Godot version, git, gh auth, gdtoolkit, GdUnit4
- `dotnet tools.csx test` — GdUnit4 headless unit + integration tests
- `dotnet tools.csx check` — headless import + parse check + lint (warnings enforced)
- `dotnet tools.csx bots` — headless host + N bot clients, full scripted match, assert win/no-leaks
- `dotnet tools.csx shot <scene>` — screenshot to tools/out/
- `dotnet tools.csx verify` — everything CI runs (check, test, bots)

If a command doesn't exist yet, propose it to the human with exact rationale and implementation.

## Workflow: Session Start

1. Run `dotnet tools.csx doctor` and fix any issues
2. Open the assigned GitHub issue (`gh issue view <number>`)
3. Read relevant docs:
   - ARCHITECTURE.md (engineer working on core/net/voice)
   - GDD.md + design/ (designer working on content/levels)
   - Nested CLAUDE.md for your area (loads automatically)
4. Restate the plan in the issue as a comment (confirm or ask for clarification)

## Definition of Done

All of these before opening a PR:
- Lint clean (gdformat + gdlint pass)
- Tests green (unit, integration, bots if it applies)
- Headless verify succeeds (`dotnet tools.csx verify`)
- Durable knowledge updated if it changed (ARCHITECTURE.md, GDD.md, or this file)
- Issue handoff comment written (what was done, what's left, decisions, gotchas)
- PR opened with template filled (linked issue, summary, verification commands + output, screenshots)

## When to Ask the Human

Stop and ask before:
- Adding a dependency or addon (risk/benefit tradeoff, Windows availability)
- Changing an architecture boundary (design review, cross-owner impact)
- Touching another owner's area (is it a blocker? should it be an engine-request issue?)
- Anything destructive to git history (force-push, rebase on main)
- Anything that costs money (API calls, external services)
```

### Key Settings

**`.claude/settings.json` (committed, shared)**

```json
{
  "permissions": {
    "allow": [
      "Bash(dotnet *)",
      "Bash(godot *)",
      "Bash(gdformat *)",
      "Bash(gdlint *)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push)",
      "Bash(gh issue *)",
      "Bash(gh pr *)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(rm -rf *)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "tools": [".gd"],
        "hooks": [
          {
            "type": "command",
            "command": "cd $WORKDIR && gdformat \"$PATH\""
          }
        ]
      }
    ]
  }
}
```

**`.claude/settings.local.json` (gitignored, personal)**

```json
{
  "env": {
    "GODOT_BIN": "C:\\path\\to\\godot_4.7.2_win64_console.exe",
    "GDTOOLKIT_DIR": "C:\\path\\to\\gdtoolkit\\bin",
    "PYTHON_BIN": "C:\\path\\to\\python.exe"
  },
  "autoMemoryEnabled": true
}
```

**`~/.claude/CLAUDE.md` (personal, per human)**

Engineer's version (Ukrainian):
```markdown
# Personal: Engineer Session

## Мова

Відповідай українською (Don't answer in Russian; use Ukrainian).

## Shortcuts

- When I say "run it", use `dotnet tools.csx verify` and show me the output.
- When I mention a Godot 3 feature, flag it immediately.
```

Designer's version (English):
```markdown
# Personal: Designer Session

## Language

Respond in English.

## Preferences

- When designing mechanics, prioritize player agency over complexity.
- Always check ARCHITECTURE.md for the content API before inventing new effect types.
```

### Nested CLAUDE.md Files (add after M0, when areas stabilize)

**`core/CLAUDE.md`**
```markdown
# Core Rules Engine (Engineer-facing)

## Architecture

- Pure GDScript RefCounted classes; zero dependency on Nodes, scenes, networking.
- All state deterministic: commands in → events out. RNG injected.
- State accessible only by filtered views per peer (no direct access to core state from UI).

## Testing

- Unit tests for all new effects, conditions, triggers.
- Information-leak test mandatory: prove no peer ever receives info it's not entitled to.
- Bot-match tests for role, ability, task combinations.

## Code Style

- Favor composition over inheritance for effects (traits/mixins).
- Event names: past tense (PlayerKilled, VoteEnded, RoleAssigned).
- Never import from server/, client/, voice/ in core/ (dependency inversion).
```

(Repeat for net/, voice/, content/, levels/)

### Auto Memory & INTERVENTIONS.md

**`docs/INTERVENTIONS.md`** (append-only; each entry is self-contained to avoid merge conflicts)

```markdown
# Interventions Log

## 2026-09-28: Godot 3 idiom detection (Lesson for auto memory)

**Context**: Engineer's agent wrote `onready var` instead of `@onready var`.

**Correction**: This is Godot 3 syntax. GDScript in Godot 4.7.2 uses `@onready`, `@export`, etc.

**Rule added to auto memory**: "Godot 4.7.2 decorators are @ prefixed, not keyword-based. No onready, export, tool keywords."

---

## 2026-10-05: Test isolation for multiplayer state

**Context**: Integration test of intent validation did not clean up match state between runs, causing race-condition test failures.

**Correction**: Always reset `MatchState.reset()` and re-seed RNG in test setup. Isolation is critical for async networking tests.

**Rule added to auto memory**: "Test setup must reset MatchState and seed RNG. Teardown must verify no dangling subagents or async timers."

---
```

Auto memory captures these lessons in ~/.claude/projects/D--prime-game/memory/feedback_*.md. They stay visible in /memory but don't clutter CLAUDE.md.

### Subagent Configuration (for future multi-agent orchestration)

No subagents configured yet. When Phase A research identifies roles (godot-api-checker, test-runner, code-reviewer, netcode-security-reviewer), each will be defined in .claude/agents/ with its own model and tool restrictions. Each can optionally have memory: true to track its own learnings.

## Config corrections (verifier)

1. **PostToolUse hook is invalid.**
   - `"tools": [".gd"]` is not a hook field. Filter with a per-handler `"if": "Edit(*.gd)"` (plus a second handler for `Write(*.gd)`) or inside the script.
   - `$WORKDIR` does not exist.
   - `$PATH` is the system PATH variable, not the edited file. The file arrives as JSON on stdin at `tool_input.file_path`, as an absolute Windows path with backslashes.
   - On Windows, command hooks run under Git Bash by default. Set `"shell": "powershell"` or use the exec form.
   - gdformat is not on PATH on this machine (it lives in GDTOOLKIT_DIR). Use `${CLAUDE_PROJECT_DIR}/tools/hooks/<script>` and call `$GDTOOLKIT_DIR` explicitly.
   - KICKOFF §6 also asks for gdlint, not only gdformat. (Sources: https://code.claude.com/docs/en/hooks.md)

2. **Permissions are Bash-only**, but the PowerShell tool is the primary shell here. Add `PowerShell(...)` equivalents (same rule shape; aliases are canonicalized). Other problems:
   - `Bash(godot *)` won't match invocations of the console exe via `$GODOT_BIN` or a full path.
   - `Bash(gh issue *)` and `Bash(gh pr *)` allow writes (close, edit, merge), while KICKOFF §6 says read-only gh.
   - `Bash(git push)` is allowed, but KICKOFF requires deny or ask for pushing to main.
   - Missing deny or ask rules: branch deletion, `Remove-Item -Recurse` (PowerShell), and editing `.github/workflows/**` (Edit/Write ask rules).
   - `Bash(git push --force*)` misses `git push -f` and `git push origin main --force`. The docs call argument-constraining patterns fragile and recommend a PreToolUse hook. (https://code.claude.com/docs/en/permissions.md)

3. **Rules frontmatter.**
   - `# Paths: **/*.test.gd` must be real YAML frontmatter (`---\npaths:\n  - "..."\n---`).
   - The pattern itself matches nothing. The installed GdUnit4 names suites `<name>_test.gd` (snake case) or `<Name>Test.gd` (pascal case), per addons/gdUnit4/src/core/GdUnitTestSuiteScanner.gd `_to_naming_convention`. Use e.g. `tests/**/*_test.gd`.
   - `core/server/net/` is not a glob and conflates three top-level dirs. Use `server/**` and `net/**`.
   - `git-workflow.md` and `godot-api.md` have no paths, so they load at every launch. Count them in the line budget, or move git workflow into the finish-task skill.

4. **settings.local.json.**
   - `"autoMemoryEnabled": true` is redundant: it is the default and is already set in ~/.claude/settings.json.
   - On Windows this file is not visible in desktop worktree sessions. Add `.worktreeinclude` with `.claude/settings.local.json`, or put machine env in user settings or the desktop local-environment editor.
   - If created by hand, it must be added to .gitignore explicitly, as KICKOFF §2 requires.

5. **Root CLAUDE.md sample.**
   - Replace the `dotnet tools.csx` commands with the agreed runner, and add lint, host and join.
   - Delete both chat-language lines.
   - Fix '(loads automatically)' to say the file loads when a file in that directory is read, and is lost after /compact.
   - 'Godot console exe on PATH via env var GODOT_BIN' is garbled: GODOT_BIN holds the path, with a fallback to `godot` on PATH.
   - The ownership map omits server/, tools/ and tests/ from the §5.3 CODEOWNERS list, and client/ is unassigned.

6. **~/.claude files.**
   - Use `{"language": "ukrainian"}` in the engineer's ~/.claude/settings.json, and keep 'never reply in Russian' in ~/.claude/CLAUDE.md.
   - Move the designer's content-API rule to content/CLAUDE.md.
   - Labelling ~/.claude as 'gitignored' is meaningless, because it is outside the repo.
   - The engineer's shortcut references the non-existent `dotnet tools.csx verify`.

7. **INTERVENTIONS.md sample.** 'Rule added to auto memory' should read 'Rule added to <committed file/section> in PR #n'. The `feedback_*.md` filenames are Claude-chosen, not a contract. The 2026-10-05 entry is fabricated and should be marked illustrative or removed.

8. **Subagents.** Use `memory: project|user|local`, not `memory: true`.

9. **Nested files timing.** Nested CLAUDE.md files, at least content/ and levels/, should be created in M0, not 'after M0'.

## Windows notes

- **GODOT_BIN environment variable**: Must point to `godot_4.7.2_win64_console.exe` (not the regular .exe). The console version prints stdout/stderr so agents can parse test output. Set in .claude/settings.local.json via env block.
- **Python path**: Python 3.14.0 is not on PATH by default on Windows 11. Set PYTHON_BIN to full path in settings.local.json (e.g., C:\\Users\\xperi\\AppData\\Local\\Programs\\Python\\Python314\\python.exe).
- **Git LFS on Windows**: git-lfs 3.6.1 must be installed. GitHub requires LFS for binary assets. Ensure git config has `core.symlinks` set appropriately (symlinks in .claude/rules/ may require admin or developer mode).
- **PowerShell vs Bash**: Primary is PowerShell 5.1. Git Bash available for POSIX scripts. Path separators: PowerShell uses backslash; Bash uses forward slash. When crafting commands, ensure they're shell-agnostic or specify which shell.
- **Godot on Windows**: Godot 4.7.2 standard build (not .NET). No WSL assumed. Headless mode works natively with console exe. Ensure GODOT_BIN path uses actual exe, not shortcut.
- **Settings files**: .claude/settings.local.json must be gitignored. Use this for machine-specific paths. Project .claude/settings.json is committed so both humans' agents get the same permissions and hooks.

## Gotchas

- Auto memory is machine-local and not shared between engineer and designer sessions. Engineer's auto memory lives on engineer's Windows machine; designer's on designer's machine. GitHub Issues + INTERVENTIONS.md are the shared source of truth for lessons.
- Nested CLAUDE.md files in subdirectories (core/CLAUDE.md) load on demand, not at startup. If agent starts from repo root and immediately reads a file in content/, content/CLAUDE.md loads then. This is correct but can surprise if agent is first looking at core files — core/ rules don't load until core/ is touched.
- /compact preserves project-root CLAUDE.md but compresses conversation history. After /compact, nested CLAUDE.md files and path-scoped rules reload when those directories are read again. Skill descriptions in the skill index DO NOT survive /compact (only ones you invoked get restored, capped at 5KB per skill).
- CLAUDE.md files over 200 lines reduce adherence; over 4 MiB are skipped entirely. If you add a large import with @path/docs/ARCHITECTURE.md, it counts toward the file size. Monitor with /context and run /doctor prompt-audit to trim.
- Path-scoped rules with complex glob patterns (many braces, e.g., {a,b}/{c,d}/*.{ts,tsx}) share a 1,000-pattern-expansion budget and 4 MiB limit across the whole rules/ set. If you hit the budget, patterns may not match as expected. Keep patterns simple.
- External imports in project CLAUDE.md (e.g., @~/.claude/shared-patterns.md) require approval dialog first time, and dialog only appears if Claude Code fetches feature settings (first-party, most custom ANTHROPIC_BASE_URL, CI). On Bedrock/Vertex/Foundry, the dialog may not appear; keep external imports out of project files.
- Subagents do NOT inherit parent session's auto memory unless the subagent has memory: true in its frontmatter AND is a defined subagent in .claude/agents/. Forked subagents inherit parent's CLAUDE.md and MCP but not auto memory by default.
- If both humans edit the root CLAUDE.md at the same time (engineering-focused changes vs design-focused changes), git merges may conflict. Mitigation: keep root lean and push area-specific rules to nested CLAUDE.md files or .claude/rules/. Assign root ownership to one human or rotate.
- Claude desktop app (Code tab) and CLI share the same CLAUDE.md files and auto memory location, but sessions are independent. If human opens Code tab in Desktop and also opens CLI in terminal, they are separate sessions with separate conversation histories but same underlying memory files. This is intentional but can be confusing.
- GitHub Issues is the source of truth for moving state (task assignment, decision log, blockers). Do not rely on auto memory MEMORY.md or CLAUDE.md for 'what are we building?' — that lives in docs/GDD.md and issues. Auto memory is for 'how did Claude learn?' not 'what is the project status?'.
- .claude/rules/ rules without a paths: field load at startup like CLAUDE.md, consuming context. Rules with paths: load on demand. If you have many always-on rules, split into multiple files and mark some with paths: patterns so they don't all load upfront.
- autoMemoryEnabled can be toggled per human via /memory command (saves to ~/.claude/settings.json globally) or disabled per project via project .claude/settings.json. If project settings disable auto memory, individual human toggles don't override. Be careful which scope you set it at.
- CLAUDE.local.md is gitignored by convention but it's up to the human to add it to .gitignore. Do not commit it. Similarly, .claude/settings.local.json must be gitignored before human edits it with env vars.
- Skills in .claude/skills/ load only when invoked or when Claude auto-triggers them. Their descriptions (not full content) load at startup. If a skill name conflicts with a /command, the skill wins. Skill names must be unique across project, user, and enterprise scopes.
- If a human adds a large file to project CLAUDE.md via import and later deletes the import, the file is no longer injected but may still exist on disk. Agents should confirm with human before deleting large imported files to avoid data loss.
- Path-scoped rules with paths: patterns that match no files still load the rule (wasted context). If you create a path-scoped rule for a file pattern that doesn't exist yet (e.g., for a directory you'll create in M2), be aware the rule loads when the first matching file is opened, not before.

## Open questions

- Should docs/INTERVENTIONS.md be append-only with human writing blocks, or should agents be able to add summaries of their own lessons? KICKOFF.md implies human-written (each entry a 'decision + rule'), but auto memory already captures Claude's learnings separately.
- Once nested CLAUDE.md files are written (M0+), how will they be maintained? Should one human own all nested files, or should each area owner (engineer for core/net/voice, designer for content/levels) maintain their own? This affects merge conflict risk and accountability.
- For path-scoped rules, should they be organized by file type (rules/gdscript.md, rules/test-gdscript.md, rules/resource-tres.md) or by subsystem (rules/core/, rules/net/)? Current proposal uses file type; subsystem may be clearer for area ownership.
- Should .claude/rules/ files include tool-specific rules (e.g., gdformat configuration, linter warnings) or keep those in config files (.editorconfig, gdlint.json)? Currently, only behavior rules are in CLAUDE.md/rules; tool config is separate.
- When should auto memory be reviewed and promoted to permanent CLAUDE.md/rules? Suggest quarterly, but is that too often (creates constant churn) or too rare (stale memory accumulates)?
- If a lesson in INTERVENTIONS.md applies to both engineer and designer (e.g., 'always run verify before PR'), should it go in root CLAUDE.md or repeated in both nested CLAUDE.md files? Single source of truth vs. area-owner autonomy.
- For subagent setup (Phase A step 6 on AGENT_WORKFLOW.md): should subagents be defined in .claude/agents/ now with placeholder prompts, or only after M0 when we know their exact roles and tool restrictions?
- Should ~/.claude/CLAUDE.md personal prefs include model choice (e.g., engineer prefers opus for core logic, designer prefers haiku for fast iteration), or always use the model configured in root settings.json?
- The current plan is to add nested CLAUDE.md files after M0. What's the trigger: when subdirectory structure is finalized, or after first substantial code is written in each area? Should agents write the nested files themselves or is that a human decision?