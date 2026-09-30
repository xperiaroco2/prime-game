export const meta = {
  name: 'pr-rebase',
  description: 'Bring one open prime-game PR up to date with its base after a semantic conflict: rebase and reconcile, verify, publish; fresh review; fix only if blocker or major',
  whenToUse: 'The orchestrate-stage skill launches it when a merge leaves an open PR with a semantic conflict (two PRs creating the same classes, a changed interface). A docs or test-list conflict the manager resolves inline instead. args: {n, pr, wt, branch, base?, why, steps?, focus?, plan?, manager?}',
  phases: [
    { title: 'Rebase', detail: 'one agent in the task worktree' },
    { title: 'Review', detail: 'code-reviewer over the range-diff; netcode-security-reviewer if core/server/net changed' },
    { title: 'Fix', detail: 'only if a review found a blocker or major' },
  ],
}

// Saved project workflow (docs/AGENT_WORKFLOW.md §7, "The orchestrator session"; skill orchestrate-stage).
// args:
//   n       the PR's issue (required)            pr      the PR number (required)
//   wt      its worktree, D:/... (required)       branch  its branch (required)
//   base    the PR's base, default 'main'
//   why     what merged and what conflicts, with the PRs and handoffs to read (required)
//   steps   how to reconcile: which side's files and payloads to keep, follow-ups the two PRs named
//   focus   what the reviewer must check beyond the usual
//   plan    the plan issue whose body no agent edits (default 30)
//   manager who runs this (default 'the manager session')
// Resume: relaunch with resumeFromRunId and the SAME args.

const A = args || {}
for (const k of ['n', 'pr', 'wt', 'branch', 'why']) {
  if (A[k] === undefined || A[k] === '') throw new Error(`pr-rebase: args.${k} is required`)
}
const N = A.n
const PR = A.pr
const WT = A.wt.replace(/\\/g, '/')
const WTB = WT.replace(/^([A-Za-z]):/, (m, d) => '/' + d.toLowerCase())
const BASE = A.base || 'main'
const SCRATCH = `r${PR}`

const RULES = [
  `You are a task agent of prime-game, run unattended by ${A.manager || 'the manager session'}. No human answers questions: never ask in chat. Root CLAUDE.md applies in full.`,
  `- Work ONLY in the worktree ${WT} (branch ${A.branch}, PR #${PR}, issue #${N}, base ${BASE}). Start every shell command with \`cd ${WTB} && ...\` (Git Bash) or \`Set-Location ${WT}; ...\`. Never change D:/prime-game itself or another worktree.`,
  `- Never: merge a PR, push to main, push by hand or force-push (the branch goes up only through \`tools\\run.cmd publish\`), close an issue, edit the body of #${A.plan || 30}. Do not run commands you expect to prompt. No Godot windows. Temporary files only under the subfolder ${SCRATCH}/ of your scratchpad (it is shared with every other agent). LF line endings. Never weaken, skip or delete a test to make it pass.`,
  '- Commits: Conventional Commits ending with the line: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>.',
].join('\n')

const REVIEW = { type: 'object', properties: { reviewer: { type: 'string' }, verdict: { type: 'string' }, findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] }, file: { type: 'string' }, line: { type: 'number' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'problem'] } } }, required: ['verdict', 'findings'] }

phase('Rebase')
const reb = await agent([
  RULES,
  `Task: bring PR #${PR} up to date with origin/${BASE} and make both sides one coherent whole. Effort: high. Budget: at most about 150 tool calls.`,
  `An earlier attempt may have got part of the way (a resumed run): check \`git status\` (a rebase in progress?), \`git log --oneline origin/${BASE}..HEAD\` and PR #${PR}'s latest body and comments first.`,
  `Why:\n${A.why}`,
  [
    'Steps:',
    `1. Record the old tip (\`git rev-parse HEAD\`). \`git fetch --prune origin\`, \`git rebase origin/${BASE}\`. Resolve each conflict keeping both sides' intent: an add/add class keeps the base's file and uid and folds in what this PR needs; data files keep every line of both sides with unique ids (then \`tools\\run.cmd normalize <file>\` if check asks); docs keep both texts.`,
    A.steps ? `2. Reconcile:\n${A.steps}` : '2. Fix what the new base breaks in this PR\'s code and tests, each fix in its own commit.',
    '3. `tools\\run.cmd verify` until green; `tools\\run.cmd publish` (it can fail right after a rebase that changed tools/runner: run it again).',
    `4. Update PR #${PR}'s body (\`gh pr edit ${PR} --body-file\`): a "Rebased on ${BASE}" section with the conflicts, how each was resolved and the fixes; keep the rest. \`gh pr checks ${PR} --watch\`, at most two fix rounds. A short comment on #${N}.`,
  ].join('\n'),
  `Return the structured result. changed_paths: \`git diff --name-only origin/${BASE}...HEAD\`.`,
].join('\n\n'), {
  label: `rebase:#${PR}`, phase: 'Rebase', effort: 'high',
  schema: { type: 'object', properties: { up_to_date: { type: 'boolean' }, verify_green: { type: 'boolean' }, ci_green: { type: 'boolean' }, published: { type: 'boolean' }, old_tip: { type: 'string' }, new_tip: { type: 'string' }, changed_paths: { type: 'array', items: { type: 'string' } }, conflicts: { type: 'array', items: { type: 'string' } }, fixes: { type: 'array', items: { type: 'string' } }, problems: { type: 'array', items: { type: 'string' } } }, required: ['up_to_date', 'verify_green', 'published'] },
})
if (!reb) throw new Error(`#${PR}: the rebase agent returned nothing; resume this run with the same args`)

phase('Review')
const paths = reb.changed_paths || []
const base = [
  `Fresh read-only review of PR #${PR} (issue #${N}) after its rebase on origin/${BASE} (worktree ${WT}; D:/prime-game is main). Budget: at most about 60 tool calls; do not edit anything; you may run \`tools\\run.cmd test <path>\` in the worktree.`,
  `The rebase agent reported: ${JSON.stringify(reb)}`,
  `Check that each conflict resolution keeps both sides' intent and that the fixes for the new base are correct: \`git -C ${WTB} range-diff <old_tip>...<new_tip>\` where the tips are known, and \`git -C ${WTB} diff origin/${BASE}...HEAD\`. One copy of each shared class, used consistently; no lost or duplicate lines in data files; no weakened test.${A.focus ? '\n' + A.focus : ''}`,
  'Report findings with severity (blocker, major, minor, nit), file, line, problem and fix. No findings is a valid answer.',
].join('\n\n')
const thunks = [() => agent(base, { label: `review:code:#${PR}`, phase: 'Review', agentType: 'code-reviewer', schema: REVIEW })]
if (!paths.length || paths.some(p => /^(core|server|net)\//.test(p))) {
  thunks.push(() => agent(base + '\n\nFocus: the ARCHITECTURE §5 invariants over view_of, event audiences and snapshots after the merge of both sides.', { label: `review:netcode:#${PR}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }))
}
const reviews = (await parallel(thunks)).filter(Boolean)

let fix = null
const serious = reviews.flatMap(r => r.findings || []).filter(f => /blocker|major/i.test(f.severity))
if (serious.length) {
  phase('Fix')
  fix = await agent([
    RULES,
    `Task: fix the blocker and major findings of a fresh review of PR #${PR}, each with a test where it is a behaviour, plus cheap minor ones. Budget: at most about 100 tool calls. Check \`git log\` and PR #${PR}'s body first (a resumed run may have fixed some). Findings: ${JSON.stringify(reviews)}`,
    `\`tools\\run.cmd verify\` until green, \`tools\\run.cmd publish\`, add the findings and what happened to each to PR #${PR}'s body, \`gh pr checks ${PR} --watch\` (at most two fix rounds).`,
    'Return the structured result.',
  ].join('\n\n'), {
    label: `fix:#${PR}`, phase: 'Fix', effort: 'high',
    schema: { type: 'object', properties: { fixed: { type: 'array', items: { type: 'string' } }, not_fixed: { type: 'array', items: { type: 'string' } }, ci_green: { type: 'boolean' } }, required: ['fixed', 'ci_green'] },
  })
}
return { pr: PR, reb, reviews, fix }
