export const meta = {
  name: 'quick-task',
  description: 'One small prime-game issue by one agent: change, lint and check, commit, push, PR, CI; fresh reviews only when the diff touches core, server, net, voice or tests/harness',
  whenToUse: 'The orchestrate-stage skill launches it after `tools\\run.cmd start <n>` for an issue whose `Size:` line says XS or S, one logical change and no design (a rename, a text or value change, a docs fix); CI is the gate. Not for a design task, Size M or larger, or a new mechanic: those take issue-task. args: {n, title, wt, branch, base?, notes, models?}. Agents: 1 (the quick agent); a diff under core/, server/, net/, voice/ or tests/harness/ adds 2 reviewers and, on a blocker or major, 1 fix agent.',
  phases: [
    { title: 'Quick', detail: 'one agent: the change, lint and check, commit, push, PR, CI (at most two fix rounds)' },
    { title: 'Review', detail: 'only for a diff under core/ server/ net/ voice/ tests/harness/: code-reviewer and netcode-security-reviewer, then one fix agent on a blocker or major' },
  ],
}

// Saved project workflow (#608; docs/workflow-scripts.md, docs/AGENT_WORKFLOW.md §7.1; skill orchestrate-stage).
// args:
//   n        issue number (required)          title   issue title (required)
//   wt       worktree path (required)          branch  task branch from `start` (required)
//   base     PR base branch, default 'main'
//   notes    the manager's task notes (required)
//   models   {quick, review, fix}: quick, the quick agent's model (default 'sonnet', 'opus' for a harder one); review,
//            both reviewers' (default: their agent files'); fix, the fix agent's (default: quick's)
// Returns {n, pr_url, ci_green, reviewed: {done, why}, ready_to_merge, needs_engineer, summary, ...}: the manager
// merges at once with `tools\run.cmd merge <pr> --base <base>` when ready_to_merge.

const A = args || {}
for (const k of ['n', 'title', 'wt', 'branch', 'notes']) {
  if (A[k] === undefined || A[k] === '') throw new Error(`quick-task: args.${k} is required`)
}
const KNOWN = ['n', 'title', 'wt', 'branch', 'base', 'notes', 'models']
const unknown = Object.keys(A).filter(k => !KNOWN.includes(k))
if (unknown.length) log(`#${A.n}: unknown args ignored: ${unknown.join(', ')}`)
const M = A.models === undefined || A.models === null ? {} : A.models
if (typeof M !== 'object' || Array.isArray(M)) throw new Error('quick-task: args.models must be an object {quick, review, fix}')
for (const [role, v] of Object.entries(M)) {
  if (!['quick', 'review', 'fix'].includes(role)) throw new Error(`quick-task: args.models.${role}: no such role; roles: quick, review, fix`)
  if (typeof v !== 'string' || v === '') throw new Error(`quick-task: args.models.${role} must be a model name`)
}
const N = A.n
const WT = A.wt.replace(/\\/g, '/')
const WTB = WT.replace(/^([A-Za-z]):/, (m, d) => '/' + d.toLowerCase())
const BASE = A.base || 'main'
const SCRATCH = `a${N}`
const QUICK_MODEL = M.quick || 'sonnet'
// The diff-path rule (#608): only these paths get the fresh reviews; anything else has CI as its gate.
const REVIEWED = /^(core|server|net|voice|tests\/harness)\//
const SERIOUS = /blocker|major/i

const RULES = [
  `You are the one agent of a quick-task run of prime-game, unattended (no human answers: never ask in chat). Root CLAUDE.md's hard rules apply; area CLAUDE.md files load by path. Do not read docs/AGENT_WORKFLOW.md or the finish-task skill: this prompt is the whole procedure.`,
  `- Work ONLY in the worktree ${WT} (branch ${A.branch}, PR base ${BASE}; \`start\` already ran). Every shell command starts with \`cd ${WTB} && \` (Git Bash); absolute paths under ${WT} for Read, Edit and Write. Never change the main checkout or another worktree.`,
  `- Temporary files (commit message, PR body, logs) only under ${SCRATCH}/ of your scratchpad. No \`git stash\`. Never merge, push to main, force-push, close an issue or edit another PR.`,
  '- No tool call blocks longer than 180 s: a command that may take longer runs in the Bash tool with run_in_background true and output to a new log under the scratchpad folder, then `tools/run.sh wait <log>` in separate calls (exit 124: call it again).',
  '- Commits: Conventional Commits, one logical change each, `git commit -F <file>`, the message ending with the attribution line your system reminder gives for commits; the PR body ends with the line it gives for pull requests.',
].join('\n')
const CI = `CI: \`cd ${WTB} && timeout 180 gh pr checks <pr> --watch --interval 30; echo rc=$?\` with the tool's timeout 300000, again while rc is 124 or 8 (rc 1 with "no checks reported": CI has not started, again). rc 0 is green, 1 red: find the failure with \`gh run view <id> --log-failed | grep -n -i -E "fail|error" | head -40\`, fix it, lint and check, commit, \`git push origin ${A.branch}\`, watch again. At most two fix rounds, then return ci_green false with what is still red under needs_engineer.`

const QUICK = {
  type: 'object',
  properties: {
    pr_url: { type: 'string' },
    pr_number: { type: 'number' },
    ci_green: { type: 'boolean' },
    changed_paths: { type: 'array', items: { type: 'string' } },
    commits: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string', maxLength: 600 },
    needs_engineer: { type: 'array', items: { type: 'string' } },
  },
  required: ['pr_url', 'ci_green', 'changed_paths', 'summary'],
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
const FIX = {
  type: 'object',
  properties: {
    fixed: { type: 'array', items: { type: 'string' } },
    open: { type: 'number' },
    ci_green: { type: 'boolean' },
    needs_engineer: { type: 'array', items: { type: 'string' } },
  },
  required: ['fixed', 'open', 'ci_green'],
}
const opts = (o, model) => (model === undefined ? o : { ...o, model })
const items = a => (Array.isArray(a) ? a.filter(x => typeof x === 'string' && x.trim() && !/^none\.?$/i.test(x.trim())) : [])
const line = (s, max = 200) => {
  const t = s === undefined || s === null ? '' : String(s).trim().split('\n')[0].trim()
  return t.length > max ? `${t.slice(0, max - 1).trimEnd()}…` : t
}

phase('Quick')
const quick = await agent([
  RULES,
  `Task: issue #${N} (${A.title}). Read it first: \`gh issue view ${N} --comments\`. Budget: at most 60 tool calls. An earlier attempt may have got part of the way (a resumed run): check \`git log --oneline origin/${BASE}..HEAD\` and \`gh pr list --head ${A.branch} --state all\` before doing anything twice.`,
  `Task notes from the manager:\n${A.notes}`,
  [
    'Steps:',
    `1. Make the change the issue asks, and only that: one logical change. Never invent content (names, numbers, rules); a change in content/, levels/, docs/GDD.md or docs/design/ needs the engineer's word in the issue or notes. If the task turns out bigger than one small change or needs a decision, stop: push nothing, return pr_url "" with the reason under needs_engineer.`,
    `2. \`cd ${WTB} && tools/run.sh lint\`, then \`cd ${WTB} && tools/run.sh check\` (not \`verify\`: CI runs the full suite). If logic changed (not only names, text or docs), also the tests for it by path (\`tools/run.sh test <path>\`). Red: fix it; never weaken, skip or delete a test.`,
    `3. Commit, then \`cd ${WTB} && git push -u origin ${A.branch}\`.`,
    `4. \`gh pr create --base ${BASE} --title "<conventional title> (#${N})" --body-file <file under ${SCRATCH}/>\`: what changed and why in a few lines, the lint and check result, \`Closes #${N}\`, and last the attribution line. If \`gh pr view ${A.branch}\` already finds a PR, update its body with \`gh pr edit\` instead.`,
    `5. ${CI}`,
  ].join('\n'),
  `Return the structured result. changed_paths: \`git diff --name-only origin/${BASE}...HEAD\`. summary: at most 600 characters. needs_engineer: anything only the engineer can decide (a content file to approve, a decision), else empty.`,
].join('\n\n'), { label: `publish:#${N}`, phase: 'Quick', model: QUICK_MODEL, agentType: 'task-publisher', schema: QUICK })

const brief = (fields) => {
  const q = quick || {}
  const out = { n: N, pr_url: q.pr_url || '', ci_green: q.ci_green === true, ...fields }
  out.needs_engineer = [...items(q.needs_engineer), ...items(fields.needs_engineer)]
  out.ready_to_merge = !!out.pr_url && out.ci_green && out.open_serious === 0 && !out.needs_engineer.length
  out.summary = line(q.summary)
  return out
}

if (!quick) return brief({ stopped: 'the quick agent returned nothing; relaunch with resumeFromRunId and the same args', reviewed: { done: false, why: 'no PR' }, open_serious: 0 })
if (!quick.pr_url) return brief({ stopped: 'no PR: see needs_engineer', reviewed: { done: false, why: 'no PR' }, open_serious: 0 })

const paths = quick.changed_paths || []
// No paths returned with a PR open: unknown, so reviewed (as issue-task does).
const touched = paths.filter(p => REVIEWED.test(p))
if (paths.length && !touched.length) {
  log(`#${N}: PR ${quick.pr_url}, CI ${quick.ci_green ? 'green' : 'RED'}; no reviewer: no path under core/ server/ net/ voice/ tests/harness/`)
  return brief({ reviewed: { done: false, why: 'no path under core/ server/ net/ voice/ tests/harness/: CI is the gate' }, open_serious: 0 })
}

phase('Review')
const base = [
  `Issue #${N} (${A.title}), a quick task (one small change). Branch ${A.branch} in the worktree ${WT}; PR ${quick.pr_url}, base origin/${BASE}.`,
  `Review read-only: \`git -C ${WTB} diff origin/${BASE}...HEAD\` and the files in ${WT}, against the issue (\`gh issue view ${N} --comments\`), the area CLAUDE.md files and the ARCHITECTURE sections the change touches, by section (\`cd ${WTB} && tools/run.sh section docs/ARCHITECTURE.md\` prints its outline). Budget: about 30 tool calls. Edit nothing.`,
  `The agent's summary: ${line(quick.summary, 600)}`,
  'Report findings with severity (blocker, major, minor, nit), file, line, the problem and a concrete fix. Blocker: wrong behaviour against the issue or an invariant, a leak, a broken test. No findings is a valid answer.',
].join('\n\n')
const reviews = (await parallel([
  () => agent(base, opts({ label: `review:code:#${N}`, phase: 'Review', agentType: 'code-reviewer', schema: REVIEW }, M.review)),
  () => agent(base + '\n\nFocus: information leaks through events, audiences, snapshots and view_of (ARCHITECTURE §5, §4.2 and §4.6: `tools/run.sh section docs/ARCHITECTURE.md 5 4.2 4.6`); intents the host does not validate; host-trust assumptions.', opts({ label: `review:netcode:#${N}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }, M.review)),
])).map(r => r || { reviewer: 'none', verdict: 'returned nothing', findings: [] })
const serious = reviews.flatMap(r => (r.findings || []).filter(f => SERIOUS.test(f.severity)))
const why = paths.length ? `the diff touches ${touched.slice(0, 3).join(', ')}${touched.length > 3 ? ', ...' : ''}` : 'no changed paths returned'
const counts = reviews.map((r, i) => ({ by: ['code-reviewer', 'netcode-security-reviewer'][i], findings: (r.findings || []).length, serious: (r.findings || []).filter(f => SERIOUS.test(f.severity)).length }))
const died = reviews.filter(r => r.reviewer === 'none').length
if (!serious.length) {
  return brief({ reviewed: { done: true, why }, reviews: counts, open_serious: 0, ...(died ? { needs_engineer: [`${died} reviewer(s) returned nothing: review PR ${quick.pr_url} before a merge`] } : {}) })
}

const fix = await agent([
  RULES,
  `Task: fix the fresh reviewers' blocker and major findings on PR ${quick.pr_url} (issue #${N}, ${A.title}). Budget: at most 40 tool calls.`,
  `Findings: ${JSON.stringify(serious)}`,
  `Fix each in its own commit, with a test where it is a behaviour; one you think is wrong: say why in a PR comment (\`gh pr comment <pr> --body-file <file>\`) and count it as open. Then \`cd ${WTB} && tools/run.sh lint\` and \`tools/run.sh check\`, \`git push origin ${A.branch}\`, and add a short "Review fixes" comment to the PR.`,
  CI,
  'Return the structured result: fixed (a line each), open (blocker or major findings left unfixed), ci_green.',
].join('\n\n'), { label: `fix:#${N}`, phase: 'Review', model: M.fix || QUICK_MODEL, agentType: 'task-publisher', schema: FIX })

return brief({
  ...(fix ? { ci_green: fix.ci_green === true } : {}),
  reviewed: { done: true, why },
  reviews: counts,
  fixed: fix ? items(fix.fixed).length : 0,
  open_serious: fix ? (typeof fix.open === 'number' ? fix.open : serious.length) : serious.length,
  needs_engineer: fix ? items(fix.needs_engineer) : ['the fix agent returned nothing: the blocker or major findings are open'],
})
