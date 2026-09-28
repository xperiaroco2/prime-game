export const meta = {
  name: 'agent-workflow-review',
  description: 'Adversarial multi-lens review of the docs/AGENT_WORKFLOW.md proposal draft',
  phases: [
    { title: 'Review', detail: '4 independent lenses: facts, KICKOFF compliance, humans/usability, config security' },
  ],
}

const CTX = `You are reviewing a DRAFT proposal: D:\\prime-game\\docs\\AGENT_WORKFLOW.md (read it fully). It was written from verified research notes in ${args.research} (one .md per topic plus gaps.md; each fact carries a verifier verdict and corrections, use the CORRECTED versions). The founding brief is D:\\prime-game\\KICKOFF.md (sections 0, 2-6, 8, 10 matter most). Today is ${args.today}. Environment: Windows 11, Claude Desktop Code tab running bundled Claude Code 2.1.281 (PATH CLI 2.1.195), PowerShell 5.1 primary tool + Git Bash, Godot 4.7.2, two humans (engineer chats in Ukrainian; designer writes no code). The user explicitly asked: research, then write the proposal, DO NOT apply any decisions, list options for approval.
Rules: read-only. Do not edit any file in D:\\prime-game. Do not install anything or run anything that costs money. You may WebFetch primary sources (official docs at https://code.claude.com/docs, docs.godotengine.org, docs.github.com, GitHub repos) and run harmless local read-only commands. Report only real problems; do not pad. For each finding give the exact quoted text or section, why it is wrong/risky, the evidence (URL, research-note id, or local command), and a concrete fix.`

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          section: { type: 'string' },
          quote: { type: 'string' },
          problem: { type: 'string' },
          evidence: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['severity', 'section', 'problem', 'fix'],
      },
    },
    overall: { type: 'string' },
  },
  required: ['findings', 'overall'],
}

const LENSES = [
  {
    key: 'facts',
    prompt: `LENS: FACTUAL ACCURACY. Check every factual claim tagged [doc] or [local] and every version number, setting name, flag, frontmatter field, hook field, permission-rule syntax, plan/pricing statement and issue number against the research notes (corrected versions) and, where a claim is load-bearing or the notes are ambiguous, against the primary source now. Pay special attention to: statements the research notes flagged as corrected/refuted/unverifiable that the draft may still state in the uncorrected form; overclaiming (inferred stated as fact); anything about Claude Code 2.1.281 vs 2.1.195 feature availability; Godot CLI behaviours; GitHub plan features; Fable billing.`,
  },
  {
    key: 'kickoff',
    prompt: `LENS: BRIEF COMPLIANCE AND COMPLETENESS. (1) Does the draft cover every item KICKOFF section 8 step 4 requires (framework with trade-offs incl. token cost; CLAUDE.md hierarchy + line budget + how rules get added from INTERVENTIONS; session protocol start/end/when to /clear or new session; subagents final list + model + tool allowlists + how routing was verified; hooks and permissions with exact allow/deny lists; whether a Godot MCP is justified; effort policy + keeping workflow output reviewable; how the designer's agent works; how humans should phrase requests)? (2) Does it respect section 0 (humans decide reserved things; nothing applied; deviations from KICKOFF clearly flagged) and section 6 (framework files must not become a competing source of truth)? (3) Is anything decided or presented as done that should be an option? (4) Are there contradictions between sections (e.g. decision register vs body, recommended options vs appendix configs)? (5) Are the Phase A step 5 vs Phase B (M0) boundaries right?`,
  },
  {
    key: 'humans',
    prompt: `LENS: THE TWO HUMANS. Read it as (a) the engineer, who will approve it, dictates by voice in Ukrainian, uses the Desktop app and Rider, writes zero code; and (b) the game designer, a non-coder whose agent must be productive without engine code. Find: places that are unclear, too dense, or impossible to approve quickly; decisions whose options are not actually distinguishable; missing practical steps (setup on the designer's machine, what the human must click/do); friction that will make the workflow fail in practice (too many prompts, rules the agent cannot follow, the close-first rule, worktrees); jargon without explanation where it matters for a decision. Also judge whether the decision register is the right size and whether any decisions could be merged, deferred, or dropped. Suggest concrete rewrites.`,
  },
  {
    key: 'config',
    prompt: `LENS: CONFIG CORRECTNESS AND SECURITY. Scrutinise Appendix A (permissions allow/ask/deny + hooks JSON), Appendix B, C, D and sections 7-8. Using the documented semantics (deny > ask > allow, first match; '*' globs; compound-command splitting; PowerShell tool rules; Edit/Read path rules with leading '/' relative to settings file; hooks schema: matcher, hooks[], type, command, timeout, statusMessage, shell form under Git Bash on Windows), find: rules that will never match, rules that unintentionally shadow others (an ask pattern overriding an intended allow, an allow that lets a dangerous command through), missing PowerShell considerations (e.g. PowerShell 5.1 has no && operator; aliases), dangerous commands still allowed (e.g. 'git switch' variants that discard work, 'gh issue edit' capabilities, 'git worktree add' or 'git fetch' abuse, runner allowlisting risk), guard-hook design holes (fail-open, matcher coverage, quoting of $PYTHON_BIN Windows paths in Git Bash), and JSON/YAML that would not validate. If you can verify a syntax question cheaply against https://code.claude.com/docs/en/permissions or /hooks, do so.`,
  },
]

phase('Review')
const results = await parallel(LENSES.map((l) => () =>
  agent(`${CTX}\n\n${l.prompt}`, { label: `review:${l.key}`, phase: 'Review', schema: FINDINGS })
    .then((r) => ({ lens: l.key, ...r }))))

return results.filter(Boolean)
