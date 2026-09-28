export const meta = {
  name: 'phase-a-research',
  description: 'Research current Claude Code / framework / Godot-MCP practice for AGENT_WORKFLOW.md, fact-check every claim, fill gaps',
  phases: [
    { title: 'Research', detail: 'one researcher per topic, primary sources only' },
    { title: 'Verify', detail: 'adversarial fact-check of every claim per topic' },
    { title: 'Gaps', detail: 'completeness critic against KICKOFF step 4, then gap fillers' },
  ],
}

const CTX = `
PROJECT CONTEXT (for focus only; do not modify the repo):
- Repo: D:\\prime-game. Read D:\\prime-game\\KICKOFF.md (sections 0, 2-6, 8, 10) for the full brief. Godot 4.7.2 (standard build, statically typed GDScript) multiplayer first-person social-deduction game with proximity voice chat, player-hosted.
- Two humans, each with their OWN Claude Code session that cannot see the other: an engineer (core owner, chats in Ukrainian) and a game designer (content owner, writes no code). Humans write zero code; agents write everything and must self-verify from the CLI. Coordination only through the repo and GitHub Issues / a GitHub Project board.
- Machine: Windows 11 Pro. Humans use the Claude desktop app (Code tab) and read code in JetBrains Rider. Claude Code version 2.1.195. Agent shells: PowerShell 5.1 (primary tool) and Git Bash. Node 20.19.5 (nvm4w), Python 3.14.0 (not on PATH; full path in env PYTHON_BIN), gdtoolkit 4.5.0 (exe dir in env GDTOOLKIT_DIR), GdUnit4 6.2.1 in addons/gdUnit4, gh 2.88.1 authenticated, git 2.49, git-lfs 3.6.1. Godot console exe path is in env GODOT_BIN (set via .claude/settings.local.json env). No Claude Code plugins installed yet.
- Today is ${args.today}. Your training data is probably stale: these tools change monthly. Use PRIMARY sources (official docs, repos, READMEs, changelogs, release notes) fetched NOW with WebFetch / WebSearch (load them via ToolSearch if they are deferred). Record the exact URL for every fact. The Claude Code docs live at https://code.claude.com/docs (an index is at https://code.claude.com/docs/llms.txt); follow redirects if that moved.
- Rules: read-only research. Do not install anything. Do not modify D:\\prime-game or ~/.claude. Do not run \`claude -p\` or anything that costs money. You MAY run harmless local read-only checks (\`--help\`, \`--version\`, gdlint/gdformat on scratch files) and write scratch files only under ${args.scratch}.
`

const TOPICS = [
  {
    key: 'memory',
    title: 'Claude Code memory: CLAUDE.md hierarchy, rules, imports, auto memory',
    guide: true,
    brief: `File locations and precedence (managed / user ~/.claude/CLAUDE.md / project ./CLAUDE.md or ./.claude/CLAUDE.md / CLAUDE.local.md — is it still supported?). Exactly WHEN nested CLAUDE.md files in subdirectories are loaded (at startup vs on demand when Claude reads files there) and whether they survive /compact. @path imports: syntax, max depth, approval prompt. .claude/rules/*.md and path-scoped rules via frontmatter (e.g. \`paths:\`) — do they exist, how do they load. Auto memory (autoMemoryEnabled, MEMORY.md, storage location per project path, whether it is per-machine/personal and cannot be shared, size caps, how it interacts with CLAUDE.md). Excluding CLAUDE.md files (claudeMdExcludes). Official guidance on CLAUDE.md length/content. /init, /memory. How the Claude desktop app Code tab loads these (same as CLI?).`,
    feeds: 'root vs nested CLAUDE.md vs .claude/rules vs docs split; line budget; where personal prefs like chat language go; how rules are added from INTERVENTIONS.md lessons.',
  },
  {
    key: 'subagents',
    title: 'Claude Code subagents and model routing',
    guide: true,
    brief: `Current subagent file format and ALL frontmatter fields (name, description, tools, disallowedTools, model incl. aliases like opus/sonnet/haiku/inherit and full model IDs, permissionMode, skills, hooks, memory, color, effort, maxTurns, isolation, background — confirm which exist). Locations and precedence (.claude/agents, ~/.claude/agents, plugin agents, --agents CLI JSON). Built-in agents (Explore, Plan, general-purpose, others) and their models. How the model is resolved: frontmatter vs Agent-tool model parameter vs CLAUDE_CODE_SUBAGENT_MODEL env var vs availableModels / settings. HOW TO VERIFY that routing actually took effect (e.g. subagent transcript files under ~/.claude/projects/<project>/<session>/subagents/*.jsonl with a model field, /agents UI, --debug, OpenTelemetry, cost display). Can subagents spawn subagents? Context isolation, what they inherit (CLAUDE.md, skills, MCP), background subagents, resuming, agent teams (experimental?). Current Claude model lineup and aliases as of today.`,
    feeds: 'final subagent list (godot-api-checker, test-runner, code-reviewer, netcode-security-reviewer), model per subagent, tool allowlists, and the routing verification method.',
  },
  {
    key: 'skills',
    title: 'Claude Code skills, slash commands and plugins for team sharing',
    guide: true,
    brief: `SKILL.md format and ALL frontmatter fields (name, description, allowed-tools, model, effort, disable-model-invocation, user-invocable, context: fork, agent, argument-hint, arguments/$ARGUMENTS, hooks, paths — confirm which exist). Locations and precedence (.claude/skills project, ~/.claude/skills, plugin skills, nested .claude/skills in subdirectories?). Progressive disclosure: how descriptions are loaded, the character budget for skill descriptions, how supporting files are referenced. Relation to custom slash commands (.claude/commands — merged into skills?). How a team shares skills: committing .claude/skills vs a project plugin + marketplace (.claude-plugin/plugin.json, marketplace.json, extraKnownMarketplaces and enabledPlugins in .claude/settings.json) — trade-offs. Anthropic's official skill-authoring best practices (description writing, length, testing/evals with skill-creator). Whether skills can bundle scripts and how they run on Windows.`,
    feeds: 'design of shared project skills new-mechanic, new-level-piece, start-task, finish-task and how both humans get them.',
  },
  {
    key: 'hooks',
    title: 'Claude Code hooks (with Windows specifics)',
    guide: true,
    brief: `Complete current list of hook events (PreToolUse, PostToolUse, PostToolUseFailure, UserPromptSubmit, Stop, SubagentStart/SubagentStop, SessionStart, SessionEnd, PreCompact, Notification, PermissionRequest, etc. — confirm exact names). Config schema in settings.json, matchers (tool-name regex like Edit|Write|MultiEdit, MCP tool names), hook types (command, prompt, agent, http — which exist). Stdin JSON input fields (tool_input.file_path, etc.). Exit code semantics (0, 2 = blocking with stderr fed to Claude, other). JSON output fields (decision, reason, additionalContext, suppressOutput, hookSpecificOutput, updatedInput). Timeouts, parallel execution, $CLAUDE_PROJECT_DIR, async hooks. WINDOWS: which shell executes hook commands on Windows (Git Bash? cmd? PowerShell? is there a \`shell\` field?), quoting and path issues, known Windows bugs in GitHub issues (anthropics/claude-code). Hooks defined in skill/agent frontmatter. disableAllHooks, security review of hooks, /hooks menu. Design advice: a PostToolUse hook that runs gdformat + gdlint on edited .gd files on Windows and feeds problems back to Claude (auto-format vs report-only, exit 2 vs additionalContext, avoiding stale-file conflicts when the formatter rewrites a file Claude just edited). Also evaluate SessionStart (e.g. run doctor), Stop (e.g. remind to verify), PreToolUse guards (block git push to main, block edits to .github/workflows).`,
    feeds: 'exact hook configuration proposal and its Windows implementation language (Python script vs bash vs PowerShell).',
  },
  {
    key: 'permissions',
    title: 'Claude Code settings and permission rules',
    guide: true,
    brief: `Settings files and precedence (managed, CLI flags, .claude/settings.local.json, .claude/settings.json, ~/.claude/settings.json) and how arrays merge. Settings keys relevant here: permissions.allow/ask/deny, defaultMode, additionalDirectories, env, hooks, model, effortLevel (?), enabledPlugins, extraKnownMarketplaces, statusLine, attribution / includeCoAuthoredBy, respectGitignore, cleanupPeriodDays, autoMemoryEnabled. EXACT permission rule syntax today: Bash(cmd:*) vs Bash(cmd *) prefix/wildcard forms, how compound commands (&&, ;, |) and env-var-prefixed commands are matched, whether rules can match a command that starts with "$GODOT_BIN" or & $env:GODOT_BIN. Is there a PowerShell tool rule name on Windows (PowerShell(...))? Read/Edit/Write path rule syntax (//absolute, ~/, relative to settings file, gitignore-style globs). WebFetch(domain:...), mcp__server__tool, Skill(...), Agent(...)/Task(...). Permission modes (default, acceptEdits, plan, auto, dontAsk, bypassPermissions) and what 'auto mode' does. Sandboxing availability on Windows. Whether deny rules for Bash can be bypassed (so a PreToolUse hook is needed for 'no push to main'). Produce concrete candidate allow / ask / deny lists for this project (task runner invocation, Godot console exe, git status/diff/log/add/commit/switch/branch, read-only gh, gdformat/gdlint, pwsh vs powershell) with the exact syntax.`,
    feeds: 'the exact shared .claude/settings.json permissions allow/ask/deny lists and what goes in settings.local.json.',
  },
  {
    key: 'superpowers',
    title: 'Superpowers framework (obra/superpowers)',
    guide: false,
    brief: `Current version and release date, install method (Claude Code plugin marketplace — exact commands), maintenance activity. Complete list of skills/commands (brainstorming, writing-plans, executing-plans, test-driven-development, systematic-debugging, subagent-driven-development, using-git-worktrees, requesting-code-review, finishing-a-development-branch, etc.). Where it writes plan/design files (docs/plans? docs/superpowers?) and whether that can be redirected to GitHub Issues. Context/token overhead: what is injected at SessionStart, how many tokens, how strict the "must use skills" discipline is. Windows compatibility (any bash-only hooks or scripts? known Windows issues in its GitHub issues). Whether it can be enabled per-project via committed settings (enabledPlugins + extraKnownMarketplaces) so both humans get it. Fit with Godot/GdUnit4 TDD, with a non-coder designer, and with our rule that GitHub Issues + docs + ADRs remain the only source of truth. Known criticisms / community feedback.`,
    feeds: 'framework choice: Superpowers vs GSD vs plain plan mode with our own skills.',
  },
  {
    key: 'gsd',
    title: 'GSD (Get Shit Done) framework and other alternatives',
    guide: false,
    brief: `GSD / get-shit-done (find the current canonical repo, e.g. glittercowboy/get-shit-done or its successor): current version, install (npx get-shit-done-cc? flags for local vs global), commands (/gsd:new-project, /gsd:plan-phase, /gsd:execute-phase, etc.), the .planning/ files it maintains (PROJECT.md, ROADMAP.md, STATE.md, REQUIREMENTS.md, phase plans) and whether they conflict with "GitHub Issues is the only source of moving state"; subagent orchestration and token cost; Windows support and known Windows issues; multi-user / team collaboration story (two people, merges of STATE.md); maturity. Then briefly (1-3 facts each, sources required) note other notable options in 2026 only if they are real and current: GitHub Spec Kit, BMAD Method, Anthropic's official plugins in anthropics/claude-plugins-official (e.g. feature-dev, code-review, pr-review-toolkit), and plain plan mode + custom skills.`,
    feeds: 'framework choice: Superpowers vs GSD vs plain plan mode with our own skills.',
  },
  {
    key: 'godot_mcp',
    title: 'Godot MCP servers vs pure CLI',
    guide: false,
    brief: `Survey Godot MCP servers that exist as of today (search GitHub and the MCP registry): e.g. Coding-Solo/godot-mcp, ee0pdt/Godot-MCP, bradypp/godot-mcp, GDAI MCP (gdaimcp.com), and any newer/popular ones, plus any official Godot effort. For each: capabilities (launch editor, run project and capture debug output, scene tree read/edit, screenshots, script ops, GDScript docs lookup), requires an editor plugin or not, Godot 4.7 compatibility, Windows support, runtime deps (node/python), license/cost, maintenance (last commit/release date, stars, open issues), security implications. Also: documentation lookup options for Godot 4.7 APIs (Context7 MCP, Godot docs MCP, local docs via \`godot --doctool\`, class reference XML) to prevent Godot 3 idioms. Compare against a pure CLI approach (godot --headless, script parse check, GdUnit4 CLI, custom screenshot script, reading logs). Include context/token cost of adding MCP tools (tool schema loading / tool search).`,
    feeds: 'whether a Godot MCP server adds enough over the CLI to justify it, and how the godot-api-checker subagent gets authoritative 4.7 API info.',
  },
  {
    key: 'operations',
    title: 'Claude Code operational features: effort, workflows/ultracode, plan mode, context, worktrees, desktop app',
    guide: true,
    brief: `Effort levels (low/medium/high/xhigh/max): how to set them (/effort, settings key, per-subagent/per-skill), defaults per model. The Workflow tool / "ultracode" mode: what it is, how it is triggered, cost implications, dynamic workflow size setting. Plan mode (Shift+Tab, ExitPlanMode, plan files) and its fit for design-before-code. Context management: context window sizes for current models, /clear vs /compact vs auto-compaction, what survives compaction (CLAUDE.md re-read?), /context, when to start a new session. Git worktrees: claude --worktree, EnterWorktree, .worktreeinclude, desktop app creating a worktree per session and its sync_with_base_branch behaviour. Checkpoints / rewind. /code-review (levels, --fix, --comment, ultra) and /security-review. Output styles, status line. Claude Code GitHub Actions (anthropics/claude-code-action) for PR review — setup and cost. The Claude desktop app Code tab specifics on Windows (terminal panel, PR monitoring / CI auto-fix, notifications, permission modes available). Focus on what matters for a session protocol and an effort policy for two humans on Windows.`,
    feeds: 'session protocol (start/end, when to /clear or start a new session), effort policy (ultracode vs high vs medium), how to keep workflow output reviewable, worktree usage.',
  },
  {
    key: 'godot_toolchain',
    title: 'Godot 4.7 CLI toolchain for agent self-verification',
    guide: false,
    brief: `Godot 4.7 command-line flags relevant to agents (verify against official docs AND local \`"$GODOT_BIN" --help\`): --headless, --import, --check-only (does it work for a project-wide script parse check in 4.x, or is a custom script needed?), --script/-s, --quit, --quit-after, --write-movie, --rendering-driver/--display-driver for a non-headless screenshot on Windows, --log-file, exit codes on script errors. GDScript warning settings in project.godot (debug/gdscript/warnings/untyped_declaration, inferred_declaration, unsafe_* and treating them as errors) — exact keys for 4.7. gdtoolkit 4.5.0 support for newer GDScript syntax (e.g. @abstract, typed dictionaries, variadic functions if they exist in 4.5-4.7): check gdtoolkit changelog/issues, and run a local experiment in the scratch dir with gdformat/gdlint (exes in $GDTOOLKIT_DIR) on a sample file using such syntax. GdUnit4 6.2.x CLI: options (-a, -i, --ignoreHeadlessMode, report formats incl. JUnit XML, exit codes), known issues on Windows/4.7. Godot 4.7 on GitHub Actions: setup options (chickensoft-games/setup-godot, barichello/godot-ci, others) and whether 4.7.2 is available. GDScript LSP (editor LSP on port 6005) and whether a Claude Code LSP / code-intelligence plugin for GDScript exists and is worth using. Recommended approach for screenshots on Windows from CLI.`,
    feeds: 'what the agent can verify from the CLI, which hooks/commands are feasible, godot-api-checker design, and whether an MCP server is needed.',
  },
]

const FACT = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    claim: { type: 'string' },
    source_url: { type: 'string' },
    source_type: { type: 'string', enum: ['official-docs', 'repo', 'changelog', 'issue', 'blog', 'local-test', 'inferred'] },
    relevance: { type: 'string' },
  },
  required: ['id', 'claim', 'source_url', 'source_type'],
}

const RESEARCH_SCHEMA = {
  type: 'object',
  properties: {
    topic: { type: 'string' },
    summary: { type: 'string' },
    facts: { type: 'array', items: FACT },
    options: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          description: { type: 'string' },
          pros: { type: 'array', items: { type: 'string' } },
          cons: { type: 'array', items: { type: 'string' } },
        },
        required: ['name', 'description', 'pros', 'cons'],
      },
    },
    recommendation: { type: 'string' },
    concrete_config: { type: 'string' },
    windows_notes: { type: 'string' },
    gotchas: { type: 'array', items: { type: 'string' } },
    open_questions: { type: 'array', items: { type: 'string' } },
  },
  required: ['topic', 'summary', 'facts', 'options', 'recommendation', 'windows_notes', 'gotchas', 'open_questions'],
}

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    claims: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['confirmed', 'corrected', 'refuted', 'unverifiable'] },
          corrected_claim: { type: 'string' },
          evidence_url: { type: 'string' },
          note: { type: 'string' },
        },
        required: ['id', 'verdict'],
      },
    },
    missed_facts: { type: 'array', items: FACT },
    recommendation_critique: { type: 'string' },
    config_corrections: { type: 'string' },
  },
  required: ['claims', 'missed_facts', 'recommendation_critique'],
}

const researchPrompt = (t) => `You are researching ONE topic for a proposal document (docs/AGENT_WORKFLOW.md) that will define how Claude Code agents work in this repository.
${CTX}
TOPIC: ${t.title}

WHAT TO FIND:
${t.brief}

DECISIONS THIS FEEDS: ${t.feeds}

Output requirements:
- facts: atomic, specific, each with a source URL (or "local-test: <exact command>"). Prefer current official docs, repos and changelogs over blogs. Anything you could not confirm in a primary source gets source_type "inferred". Give each fact a short unique id like "${t.key}-01". Aim for 20-40 facts; exact names, syntax and version numbers matter more than prose.
- options: the realistic choices for this project with honest trade-offs.
- recommendation: what you would pick for THIS project and why (two humans on Windows, humans write zero code, GitHub Issues is the only source of moving state).
- concrete_config: if relevant, exact config/snippets you would propose (JSON, frontmatter, commands). Mark it as a proposal.
- windows_notes, gotchas, open_questions: be specific.`

const verifyPrompt = (t, r) => `You are an ADVERSARIAL fact-checker. Another agent researched "${t.title}" for a proposal document; its claims will be used to configure this project, so wrong claims are expensive.
${CTX}
For EACH claim below: fetch the primary source (the cited URL, and the current official docs / repo / changelog if the citation is weak) and actively try to REFUTE it. Verdicts: "confirmed" (primary source says so today), "corrected" (partly wrong or outdated; give corrected_claim), "refuted" (wrong), "unverifiable" (no primary evidence found; default to this rather than confirming from memory). Be especially suspicious of: renamed settings/fields, syntax that changed between versions, Windows behaviour, and anything that reads as recalled from memory rather than read from a page. Give evidence_url for every non-unverifiable verdict.
Then list up to 10 important facts the researcher MISSED that matter for: ${t.feeds}
Then critique the researcher's recommendation and, if concrete_config is present, list any errors in it (config_corrections).

CLAIMS (JSON):
${JSON.stringify(r.facts, null, 1)}

RESEARCHER'S RECOMMENDATION:
${r.recommendation}

RESEARCHER'S CONCRETE CONFIG:
${r.concrete_config || '(none)'}`

phase('Research')
const results = await pipeline(
  TOPICS,
  (t) => agent(researchPrompt(t), {
    label: `research:${t.key}`,
    phase: 'Research',
    schema: RESEARCH_SCHEMA,
    agentType: t.guide ? 'claude-code-guide' : undefined,
  }),
  (r, t) => {
    if (!r) return null
    return agent(verifyPrompt(t, r), { label: `verify:${t.key}`, phase: 'Verify', schema: VERIFY_SCHEMA })
      .then((v) => ({ key: t.key, title: t.title, research: r, verification: v }))
  },
)

const done = results.filter(Boolean)
const missing = TOPICS.filter((t) => !done.find((d) => d.key === t.key)).map((t) => t.key)
if (missing.length) log(`Topics with no result: ${missing.join(', ')}`)
for (const d of done) {
  const c = (d.verification && d.verification.claims) || []
  const tally = {}
  c.forEach((x) => { tally[x.verdict] = (tally[x.verdict] || 0) + 1 })
  log(`${d.key}: ${d.research.facts.length} facts, verdicts ${JSON.stringify(tally)}`)
}

phase('Gaps')
const digest = done.map((d) => ({
  topic: d.title,
  summary: d.research.summary,
  recommendation: d.research.recommendation,
  open_questions: d.research.open_questions,
  critique: d.verification ? d.verification.recommendation_critique : '(no verification)',
  refuted_or_unverifiable: ((d.verification && d.verification.claims) || [])
    .filter((x) => x.verdict !== 'confirmed')
    .map((x) => ({ id: x.id, verdict: x.verdict, corrected: x.corrected_claim, note: x.note })),
}))

const GAP_SCHEMA = {
  type: 'object',
  properties: {
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          question: { type: 'string' },
          why_it_matters: { type: 'string' },
          how_to_answer: { type: 'string' },
        },
        required: ['question', 'why_it_matters', 'how_to_answer'],
      },
    },
  },
  required: ['gaps'],
}

const critic = await agent(`You are a completeness critic. Below is a digest of verified research that will be used to write docs/AGENT_WORKFLOW.md for this project.
${CTX}
The document must cover at least (KICKOFF.md section 8 step 4): framework choice (Superpowers vs GSD vs plain plan mode + own skills, with trade-offs incl. token cost); CLAUDE.md hierarchy (root vs nested vs docs, lean line budget, how rules are added from INTERVENTIONS.md lessons); session protocol (start: doctor, read issue, read docs; end: verify, handoff comment, PR; when to /clear or start a new session); subagents (final list, model per subagent, tool allowlists, how routing was verified); hooks and permissions (exact allow/deny lists); whether a Godot MCP server is justified; an effort policy (ultracode vs high vs medium) and keeping workflow output reviewable; how the designer's agent works without engine code; how humans should phrase requests (issue templates, acceptance criteria, dictation tips). Also KICKOFF section 6 (subagents, settings, hooks, skills) and section 5 (coordination via GitHub).

Find the most important remaining GAPS: questions that the research did not answer (or answered only with unverifiable/refuted claims) and that would change what the proposal recommends. Return at most 6, ordered by importance, each answerable by focused research of primary sources. Do not list gaps that are purely human decisions (those will be put to the humans as options).

DIGEST (JSON):
${JSON.stringify(digest, null, 1)}`, { label: 'completeness-critic', phase: 'Gaps', schema: GAP_SCHEMA })

const gaps = (critic && critic.gaps) || []
log(`Critic found ${gaps.length} gaps`)

const GAP_ANSWER = {
  type: 'object',
  properties: {
    question: { type: 'string' },
    answer: { type: 'string' },
    facts: { type: 'array', items: FACT },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
  },
  required: ['question', 'answer', 'facts', 'confidence'],
}

const gapAnswers = await parallel(gaps.map((g, i) => () => agent(`Answer ONE focused research question for docs/AGENT_WORKFLOW.md.
${CTX}
QUESTION: ${g.question}
WHY IT MATTERS: ${g.why_it_matters}
SUGGESTED APPROACH: ${g.how_to_answer}
Use primary sources fetched now; cite a URL (or "local-test: <command>") for every fact; mark anything not confirmed in a primary source as "inferred". Give a direct answer, then the supporting facts (ids like "gap${i + 1}-01").`, { label: `gap:${i + 1}`, phase: 'Gaps', schema: GAP_ANSWER })))

return { topics: done, missing, gaps, gapAnswers: gapAnswers.filter(Boolean) }
