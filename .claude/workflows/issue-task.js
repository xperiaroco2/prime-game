export const meta = {
  name: 'issue-task',
  description: 'One prime-game issue in its worktree: implement (or design), fresh reviews chosen from the changed paths, fix, publish, PR, CI, handoff',
  whenToUse: 'The orchestrate-stage skill launches it once per task, after the manager ran `tools\\run.cmd start <n>`. args: {n, title, wt, branch, base?, notes, coord?, decisions?, reading?, testing?, design?, effort?, plan?, manager?}',
  phases: [
    { title: 'Implement', detail: 'one agent in the task worktree; commits, verify green, never publishes' },
    { title: 'Review', detail: 'code-reviewer; netcode-security-reviewer if core/server/net changed or a design task; godot-api-checker if .gd/.tscn/.tres changed' },
    { title: 'Publish', detail: 'fix findings, verify, publish, PR, CI, handoff, board' },
  ],
}

// Saved project workflow (docs/AGENT_WORKFLOW.md §7.1; skill orchestrate-stage).
// args:
//   n        issue number (required)          title   issue title (required)
//   wt       worktree path, D:/... (required)  branch  task branch from `start` (required)
//   base     PR base branch, default 'main' (a parent's branch for a task started with `start --base`)
//   notes    the manager's task notes: specifics, ownership splits of shared files, merge order (required)
//   coord    what runs in parallel and which shared files to touch minimally
//   decisions the engineer's standing decisions that apply, each with where it is recorded
//   reading  what to read first (default: the issue's links, handoffs, ADRs and area CLAUDE.md files)
//   testing  the test expectations (default: unit tests through a seeded Match; code tasks only)
//   design   true: a docs-only design task (options for the engineer, a proposed issue split, the netcode reviewer)
//   effort   the implementer's effort: default 'high', 'xhigh' for a design task
//   plan     the plan issue whose body no agent edits (default 30)
//   manager  who runs this, for the agents' first line (default 'the manager session')
// Resume after a crash or a stop: relaunch with resumeFromRunId and the SAME args (the prompts depend only on args
// and earlier results, and each prompt tells its agent to check what an earlier attempt already did).

const A = args || {}
for (const k of ['n', 'title', 'wt', 'branch', 'notes']) {
  if (A[k] === undefined || A[k] === '') throw new Error(`issue-task: args.${k} is required`)
}
const N = A.n
const WT = A.wt.replace(/\\/g, '/')
const WTB = WT.replace(/^([A-Za-z]):/, (m, d) => '/' + d.toLowerCase())
const BASE = A.base || 'main'
const PLAN = A.plan || 30
const DESIGN = A.design === true
const SCRATCH = `a${N}`

const RULES = [
  `You are a task agent of prime-game, run unattended by ${A.manager || 'the manager session'} through a workflow. No human answers questions: never ask in chat; everything goes into the repo or GitHub. Root CLAUDE.md applies in full (hard rules, invariants, ownership, shell notes).`,
  `- Work ONLY in the worktree ${WT} (branch ${A.branch}, PR base ${BASE}; the manager already ran \`start\`, never run it again). Start every shell command with \`cd ${WTB} && ...\` (Git Bash) or \`Set-Location ${WT}; ...\` (PowerShell), and use absolute paths under ${WT} for Read, Edit and Write. Never change D:/prime-game itself (that is main) or another worktree.`,
  `- Never: merge a PR, push to main, push by hand or force-push (the branch goes up only through \`tools\\run.cmd publish\`), close or reopen an issue (humans close issues), edit the body of #${PLAN}, \`gh pr merge\`.`,
  '- Do not run a command you expect to prompt (a delete, reset, rebase or branch delete outside your worktree and task branch; an edit of .claude/settings*.json or addons/): a prompt blocks the run until the human returns. List such a step in the handoff for the human instead.',
  '- No Godot windows: headless runs only; a screenshot only through `tools\\run.cmd shot` (off-screen).',
  `- Temporary files (commit messages, PR bodies, comments, probes): only under the subfolder ${SCRATCH}/ of your scratchpad, which every agent of every running workflow shares (another task's agent once overwrote a pr_body.md); or ${WT}/tests/scratch/ (gitignored) when they must be under res://. Nowhere else.`,
  '- Write files with LF line endings (Python: newline="" or bytes). The content API classes are GameRole and RuleEffect (never Role or Effect).',
  '- A game rule that no ADR, ARCHITECTURE section or issue comment settles: do not invent it. Write options with a recommendation under "Needs the engineer" (PR and handoff) and continue with the recommended one if it can be reverted. A placeholder number you must add is marked "not a decision".',
  '- Files in content/ and levels/ are provisional under docs/decisions/2026-09-29-mvp-content-built-by-the-engineer.md: the engineer approves them in the PR; the PR says so and names them.',
  '- The engineer\'s answers in issue and PR comments override older text, including these notes.',
  '- Commits: small Conventional Commits, one logical change each, message from a file (`git commit -F`), each ending with the line: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>. A PR body ends with the line: 🤖 Generated with [Claude Code](https://claude.com/claude-code).',
  A.decisions ? `- The engineer's standing decisions for this work:\n${A.decisions}` : '',
].filter(Boolean).join('\n')

const IMPL = {
  type: 'object',
  properties: {
    verify_green: { type: 'boolean' },
    verify_tail: { type: 'string' },
    changed_paths: { type: 'array', items: { type: 'string' } },
    commits: { type: 'array', items: { type: 'string' } },
    complete: { type: 'boolean' },
    left: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    decisions: { type: 'array', items: { type: 'string' } },
    needs_engineer: { type: 'array', items: { type: 'string' } },
    provisional_content: { type: 'array', items: { type: 'string' } },
    proposed_issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['verify_green', 'complete', 'summary', 'changed_paths'],
}
const REVIEW = {
  type: 'object',
  properties: {
    reviewer: { type: 'string' },
    verdict: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
          file: { type: 'string' }, line: { type: 'number' },
          problem: { type: 'string' }, fix: { type: 'string' },
        },
        required: ['severity', 'problem'],
      },
    },
  },
  required: ['reviewer', 'verdict', 'findings'],
}
const PUB = {
  type: 'object',
  properties: {
    published: { type: 'boolean' },
    pr_number: { type: 'number' },
    pr_url: { type: 'string' },
    ci_green: { type: 'boolean' },
    handoff_posted: { type: 'boolean' },
    board_in_review: { type: 'boolean' },
    closes_issue: { type: 'boolean' },
    fixed: { type: 'array', items: { type: 'string' } },
    not_fixed: { type: 'array', items: { type: 'string' } },
    needs_engineer: { type: 'array', items: { type: 'string' } },
    merge_notes: { type: 'string' },
    human_steps: { type: 'array', items: { type: 'string' } },
  },
  required: ['published', 'handoff_posted'],
}

const WORK = DESIGN
  ? [
    'This is a DESIGN task: documents only (docs/ARCHITECTURE.md, a new ADR in docs/decisions/, area CLAUDE.md files, as the issue asks). No code in core/, server/, net/, client/ or voice/. Tables where they fit; each choice names the failure it prevents; rejected alternatives go in the ADR. Verify each Godot API you name against tools/out/godot-api/4.7.2/extension_api.json. Decide nothing reserved for the engineer: each such choice is options with a recommendation, marked "Needs the engineer", and the design proceeds with the recommendation where it can be reverted.',
    'If the issue asks for a split into later issues, return it in proposed_issues (each: title, goal, acceptance criteria, depends on, files); do not open issues.',
  ].join('\n\n')
  : `Plan, then implement every acceptance criterion. ${A.testing || 'Unit tests in tests/unit/ mirroring core/, each rule driven by commands through a seeded Match and asserted on the events and on view_of; a part\'s unit test never loads content/ or levels/ (ARCHITECTURE §9.6). Where you fix a guard, see its test fail without the code first.'} If a file you need comes from a PR that is not merged yet (the notes say so), build and test with fixtures first, and before you finish \`git fetch\` and check whether it reached origin/${BASE}; if it did, rebase on it inside your worktree and use it.`

phase('Implement')
const impl = await agent([
  RULES,
  `Task: GitHub issue #${N} (${A.title}). Effort: ${A.effort || (DESIGN ? 'xhigh' : 'high')}. Budget: at most about 250 tool calls; if it runs out, stop at a green, committed state and list what is left.`,
  `An earlier attempt may have got part of the way (a resumed run): first run \`git log --oneline origin/${BASE}..HEAD\` and \`git status\` in the worktree, and continue from that state; uncommitted files there are that attempt's work.`,
  `Read: \`gh issue view ${N} --comments\`; ${A.reading || 'the docs, ADRs and handoff comments the issue links (`gh issue view <n> --comments` for each handoff it builds on); the ARCHITECTURE sections it names; the CLAUDE.md of every area it touches and .claude/rules/; the code it builds on and its tests'}.`,
  `Task notes from the manager:\n${A.notes}`,
  A.coord ? `Parallel work:\n${A.coord}` : '',
  WORK,
  'Update docs/ARCHITECTURE.md (the rows and "Built in"/"Tests" lines your work completes, and anything it makes stale) and other durable docs in the same branch. Commit as you go.',
  '`tools\\run.cmd verify` in the worktree until green (it takes a few minutes: its selftest is slow). If it fails in a way that points at another worktree\'s run at the same time (GdUnit4 temp files under user://, a busy port), run it once more before debugging.',
  'Do NOT publish, push, open a PR or comment on GitHub: fresh reviewers check the branch next.',
  `Return the structured result. changed_paths: \`git diff --name-only origin/${BASE}...HEAD\`. verify_tail: the lines from "verify summary" to the end.`,
].filter(Boolean).join('\n\n'), { label: `implement:#${N}`, phase: 'Implement', effort: A.effort || (DESIGN ? 'xhigh' : 'high'), schema: IMPL })

if (!impl) throw new Error(`#${N}: the implementer returned nothing (died or was skipped); resume this run with the same args`)
log(`#${N}: implemented, verify ${impl.verify_green ? 'green' : 'RED'}, ${(impl.changed_paths || []).length} paths`)

let reviews = []
if (impl.verify_green) {
  phase('Review')
  const paths = impl.changed_paths || []
  const netcode = DESIGN || !paths.length || paths.some(p => /^(core|server|net)\//.test(p))
  const godot = paths.some(p => /\.(gd|tscn|tres)$/.test(p)) || (!DESIGN && !paths.length)
  const base = [
    `Issue #${N} (${A.title}). Branch ${A.branch} in the worktree ${WT}; its PR base is origin/${BASE}. D:/prime-game is main: read the branch's files under ${WT}.`,
    `Review read-only${DESIGN ? ', adversarially, a DESIGN (documents only)' : ''}: \`git -C ${WTB} diff origin/${BASE}...HEAD\` and the files in ${WT}, against the issue and its comments (\`gh issue view ${N} --comments\`), docs/ARCHITECTURE.md, the ADRs the issue links, root CLAUDE.md and the area CLAUDE.md files. Budget: at most about 60 tool calls. ${DESIGN ? 'Edit nothing.' : 'You may run `tools\\run.cmd test <path>` in the worktree to confirm a finding; do not edit anything.'}`,
    A.coord ? `Context: other issues are built in parallel on other branches; a missing piece that another issue owns is not a finding. ${A.coord}` : '',
    `The implementer reported: ${JSON.stringify(impl)}`,
    `Report findings with severity (blocker, major, minor, nit), file, line, the problem and a concrete fix. ${DESIGN ? 'A design that would let information reach a peer that is not entitled to it, trust a client field, leave an intent unvalidated, or contradict an accepted ADR or the code on main is a blocker or major.' : 'Blocker: wrong behaviour against an acceptance criterion or an invariant, a leak, a broken test.'} No findings is a valid answer.`,
  ].filter(Boolean).join('\n\n')
  const codeFocus = DESIGN
    ? '\n\nFocus: consistency with the code on main (real payloads, public APIs, tables), with the accepted ADRs and with ARCHITECTURE elsewhere; Godot 4.7.2 APIs named exist (tools/out/godot-api/4.7.2/extension_api.json); a proposed issue split is complete and ordered; every engineer decision is marked as such.'
    : ''
  const thunks = [() => agent(base + codeFocus, { label: `review:code:#${N}`, phase: 'Review', agentType: 'code-reviewer', schema: REVIEW })]
  if (netcode) thunks.push(() => agent(base + '\n\nFocus: information leaks through events, audiences, snapshots, view_of, recorded recipients and rejection reasons (the ARCHITECTURE §5 invariants); intents the rules do not validate; host-trust assumptions; floods and rate limits; determinism and replay.', { label: `review:netcode:#${N}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }))
  if (godot) thunks.push(() => agent(base, { label: `review:godot-api:#${N}`, phase: 'Review', agentType: 'godot-api-checker', schema: REVIEW }))
  reviews = (await parallel(thunks)).filter(Boolean)
  if (!reviews.length) throw new Error(`#${N}: every reviewer returned nothing; resume this run with the same args`)
  log(`#${N}: ${reviews.length} reviews, ${reviews.reduce((s, r) => s + (r.findings || []).length, 0)} findings`)
}

phase('Publish')
const pub = await agent([
  RULES,
  `Task: publish issue #${N} (${A.title}) from the worktree ${WT}, PR base ${BASE}. Effort: high. Budget: at most about 150 tool calls.`,
  `An earlier attempt may have got part of the way (a resumed run): check \`gh pr list --head ${A.branch} --state all\`, the issue's latest comments and \`git status\` before doing anything twice.`,
  `The implementer reported: ${JSON.stringify(impl)}`,
  impl.verify_green
    ? `Fresh reviewers found: ${JSON.stringify(reviews)}\n\nFix every blocker and major finding and the cheap minor ones, each in its own commit, with a test where it is a behaviour; a finding you think is wrong gets the reason in the PR. List the rest. \`tools\\run.cmd verify\` until green.`
    : `verify was not green. Make it green (at most about 60 tool calls; never weaken, skip or delete a test). If it stays red, publish nothing: post a comment on #${N} (Done / Red and why / Needs the engineer) and return.`,
  [
    'Then follow .claude/skills/finish-task/SKILL.md from its docs step: "Publish now?" is answered yes; the reviews above replace its review step; skip agents-check.',
    `- \`tools\\run.cmd publish\`. Known traps: it can fail right after a rebase that changed tools/runner (verify ran with the old runner modules): run it again; "Could not resolve hostname github.com" is transient: check with \`git ls-remote origin\` and run it again. If it stops on a rebase conflict, rebase by hand inside your worktree (\`git rebase origin/${BASE}\`, resolve keeping both sides' intent, \`git rebase --continue\`, verify), then publish again.`,
    `- PR: \`gh pr create --base ${BASE} --title "<conventional title>" --body-file <file under ${SCRATCH}/>\` from .github/pull_request_template.md: \`Closes #${N}\` when every acceptance criterion is met (else \`Part of #${N}\` and what is left); the summary; the verification commands and the verify tail; screenshots "none" unless visual; docs updated; under Cross-area, the content/ and levels/ files as provisional under the MVP content ADR, for the engineer's approval; a table of every reviewer finding and what happened to it; "Needs the engineer" with options and a recommendation for each; "Merge order" (which open PRs this depends on or will conflict with, from the notes below; a stacked PR says "merge only into main, after its parent").${DESIGN ? ' The proposed issues as titles, one line each.' : ''}`,
    `- \`gh pr checks <pr> --watch\`. Red: fix, verify, publish again; at most two rounds, then report what is still red.`,
    `- The handoff comment on #${N} (\`gh issue comment ${N} --body-file <file>\`): "## Handoff", the PR link, then Done / Left / Decisions / Gotchas / Needs the engineer${DESIGN ? ', and the proposed issues in full' : ''}.`,
    `- \`tools\\run.cmd board move ${N} in-review\`.`,
  ].join('\n'),
  `Task notes from the manager (for the PR's merge order and the handoff):\n${A.notes}${A.coord ? '\n\n' + A.coord : ''}`,
  'Return the structured result.',
].join('\n\n'), { label: `publish:#${N}`, phase: 'Publish', effort: 'high', schema: PUB })

if (!pub) throw new Error(`#${N}: the publisher returned nothing; resume this run with the same args`)
return { n: N, impl, reviews, pub }
