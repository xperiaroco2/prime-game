export const meta = {
  name: 'pr-rebase',
  description: 'Bring one open prime-game PR up to date with its base after a semantic conflict: rebase and reconcile, verify, publish; fresh review; fix only if blocker or major',
  whenToUse: 'The orchestrate-stage skill launches it when a merge leaves an open PR with a semantic conflict (two PRs creating the same classes, a changed interface). A docs or test-list conflict the manager resolves inline instead. args: {n, pr, wt, branch, base?, why, steps?, focus?, plan?, manager?, second_review?, skeptic?, efforts?, models?}. Agents: 2 to 4 (rebase, 1 or 2 reviewers, a fix agent after a blocker or major); second_review adds 1 where the netcode review is routed, skeptic 1 per blocker or major finding (at most 3, or its number); efforts and models add none.',
  phases: [
    { title: 'Rebase', detail: 'one agent in the task worktree' },
    { title: 'Review', detail: 'code-reviewer over the range-diff; netcode-security-reviewer if core/server/net/client/tests/harness changed (optional: a second netcode review, a skeptic per blocker or major)' },
    { title: 'Fix', detail: 'only if a review found a blocker or major' },
  ],
}

// Saved project workflow (docs/AGENT_WORKFLOW.md §7.1; skill orchestrate-stage).
// args:
//   n       the PR's issue (required)            pr      the PR number (required)
//   wt      its worktree, D:/... (required)       branch  its branch (required)
//   base    the PR's base, default 'main'
//   why     what merged and what conflicts, with the PRs and handoffs to read (required)
//   steps   how to reconcile: which side's files and payloads to keep, follow-ups the two PRs named
//   focus   what the reviewer must check beyond the usual
//   plan    the plan issue whose body no agent edits (default 30)
//   manager who runs this (default 'the manager session')
// Optional pipeline v2 review args (docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md, item 4),
// all off by default, as in issue-task.js: with none of them every agent's prompt, label, phase, schema and options are
// byte-identical to the script before v2 (tools/runner/tests/test_workflows.py snapshots them). The agents each one
// adds count toward the agent number the kickoff approves (2 to 4 without them):
//   second_review true: an extra netcode-security-reviewer pass with an attacker's lens wherever the netcode review
//                 is routed. +1 agent there
//   skeptic       true, or a number: one read-only agent tries to refute each blocker or major finding before the
//                 Fix phase, at most 3 (or that number); a refuted finding is not sent to the fix agent but listed
//                 in the PR body with the reason (by the fix agent, or by the manager when every one was refuted:
//                 the result says so). +1 agent per finding checked
//   efforts       {role: 'low' | 'medium' | 'high' | 'xhigh' | 'max'}. Roles: rebase (default 'high'), review,
//                 netcode, second_review, skeptic, fix (default 'high'). review covers the code reviewer and is the
//                 fallback of netcode, skeptic and (after netcode) second_review. A reviewer gets an effort only when
//                 one is set; otherwise its agent file's applies, as before v2. +0 agents
//   models        {role: model} for the same roles, passed to agent({model}) only when set, with the same fallbacks
//                 and no default (the model-guard ADR and its amendment A). +0 agents
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
// A release base (release/m<k>, any base that is not main or a task branch) is always passed, so the base never
// depends on the record `start --base` left in this checkout. A stacked parent's task branch is not: publish
// follows the PR's live base, which GitHub retargets once the parent merges and its branch is deleted.
const TASK_BRANCH = /^[a-z][a-z0-9]*\/[0-9]+-[a-z0-9][a-z0-9._-]*$/
const PUBLISH = `tools\\run.cmd publish${BASE === 'main' || TASK_BRANCH.test(BASE) ? '' : ` --base ${BASE}`}`

// The pipeline v2 args, checked as in issue-task.js: a wrong value throws before any agent runs; an unknown arg logs.
const KNOWN = ['n', 'pr', 'wt', 'branch', 'base', 'why', 'steps', 'focus', 'plan', 'manager', 'second_review', 'skeptic', 'efforts', 'models']
const unknown = Object.keys(A).filter(k => !KNOWN.includes(k))
if (unknown.length) log(`#${PR}: unknown args ignored: ${unknown.join(', ')}`)
if (A.second_review !== undefined && A.second_review !== null && typeof A.second_review !== 'boolean') throw new Error('pr-rebase: args.second_review must be true or false')
const SECOND_REVIEW = A.second_review === true
if (A.skeptic !== undefined && A.skeptic !== null && typeof A.skeptic !== 'boolean' && !(Number.isInteger(A.skeptic) && A.skeptic > 0)) {
  throw new Error('pr-rebase: args.skeptic must be true, false or the most findings to check (a positive integer)')
}
const SKEPTICS = A.skeptic === true ? 3 : (Number.isInteger(A.skeptic) ? A.skeptic : 0)
const ROLES = ['rebase', 'review', 'netcode', 'second_review', 'skeptic', 'fix']
// The roles a role falls back to, in order, when this launch sets nothing for it.
const CHAIN = {
  rebase: ['rebase'], review: ['review'], netcode: ['netcode', 'review'], second_review: ['second_review', 'netcode', 'review'],
  skeptic: ['skeptic', 'review'], fix: ['fix'],
}
const perRole = (k, values) => {
  const m = A[k]
  if (m === undefined || m === null) return {}
  if (typeof m !== 'object' || Array.isArray(m)) throw new Error(`pr-rebase: args.${k} must be an object {role: value}; roles: ${ROLES.join(', ')}`)
  for (const [role, v] of Object.entries(m)) {
    if (!ROLES.includes(role)) throw new Error(`pr-rebase: args.${k}.${role}: no such role; roles: ${ROLES.join(', ')}`)
    if (typeof v !== 'string' || v === '' || (values && !values.includes(v))) throw new Error(`pr-rebase: args.${k}.${role} must be ${values ? values.join(', ') : 'a model name'}`)
  }
  return m
}
const EFFORTS = perRole('efforts', ['low', 'medium', 'high', 'xhigh', 'max'])
const MODELS = perRole('models', null)
const set = (m, role) => CHAIN[role].map(r => m[r]).find(v => v !== undefined)
// Today's options keep their keys and order; an effort (reviewers only: the others carry their default) and a model
// are appended only where this launch sets them for the role.
const withModel = (o, role) => (set(MODELS, role) === undefined ? o : { ...o, model: set(MODELS, role) })
const asReviewer = (o, role) => withModel(set(EFFORTS, role) === undefined ? o : { ...o, effort: set(EFFORTS, role) }, role)
const REB_EFFORT = EFFORTS.rebase || 'high'
const FIX_EFFORT = EFFORTS.fix || 'high'

const RULES = [
  `You are a task agent of prime-game, run unattended by ${A.manager || 'the manager session'}. No human answers questions: never ask in chat. Root CLAUDE.md applies in full.`,
  `- Work ONLY in the worktree ${WT} (branch ${A.branch}, PR #${PR}, issue #${N}, base ${BASE}). Start every shell command with \`cd ${WTB} && ...\` (Git Bash) or \`Set-Location ${WT}; ...\`. Never change D:/prime-game itself or another worktree.`,
  `- Never: merge a PR, push to main, push by hand or force-push (the branch goes up only through \`tools\\run.cmd publish\`), close an issue, edit the body of #${A.plan || 30}. Do not run commands you expect to prompt. No Godot windows. Temporary files only under the subfolder ${SCRATCH}/ of your scratchpad (it is shared with every other agent). LF line endings. Never weaken, skip or delete a test to make it pass.`,
  '- Commits: Conventional Commits ending with the attribution line your system reminder gives for commits. An edit of any path under .claude/ or addons/ prompts unless the session runs in bypass: list it for the human instead.',
  `- Never use \`git stash\` (one stash serves every worktree, so the guard asks before a drop of an entry it cannot show is yours). To set work aside: a WIP commit, later \`git reset --soft HEAD~1\`. To fold a fix into an earlier commit: \`git commit --fixup=<sha>\`, then \`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/${BASE}\` (Git Bash; in PowerShell \`$env:GIT_SEQUENCE_EDITOR = ':'; git rebase -i --autosquash origin/${BASE}\`); never an interactive rebase without that variable. Both are free in your own worktree.`,
].join('\n')

const REVIEW = { type: 'object', properties: { reviewer: { type: 'string' }, verdict: { type: 'string' }, findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] }, file: { type: 'string' }, line: { type: 'number' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'problem'] } } }, required: ['verdict', 'findings'] }
const SKEPTIC_SCHEMA = { type: 'object', properties: { refuted: { type: 'boolean' }, reason: { type: 'string' }, evidence: { type: 'string' } }, required: ['refuted', 'reason'] }

phase('Rebase')
const reb = await agent([
  RULES,
  `Task: bring PR #${PR} up to date with origin/${BASE} and make both sides one coherent whole. Effort: ${REB_EFFORT}. Budget: at most about 150 tool calls.`,
  `An earlier attempt may have got part of the way (a resumed run): check \`git status\` (a rebase in progress?), \`git log --oneline origin/${BASE}..HEAD\` and PR #${PR}'s latest body and comments first.`,
  `Why:\n${A.why}`,
  [
    'Steps:',
    `1. Record the old tip (\`git rev-parse HEAD\`). \`git fetch --prune origin\`, \`git rebase origin/${BASE}\`. Resolve each conflict keeping both sides' intent: an add/add class keeps the base's file and uid and folds in what this PR needs; data files keep every line of both sides with unique ids (then \`tools\\run.cmd normalize <file>\` if check asks); docs keep both texts.`,
    A.steps ? `2. Reconcile:\n${A.steps}` : '2. Fix what the new base breaks in this PR\'s code and tests, each fix in its own commit.',
    `3. \`tools\\run.cmd verify\` until green; \`${PUBLISH}\` (it can fail right after a rebase that changed tools/runner: run it again).`,
    `4. Update PR #${PR}'s body (\`gh pr edit ${PR} --body-file\`): a "Rebased on ${BASE}" section with the conflicts, how each was resolved and the fixes; keep the rest. \`gh pr checks ${PR} --watch\`, at most two fix rounds. A short comment on #${N}.`,
  ].join('\n'),
  `Return the structured result. changed_paths: \`git diff --name-only origin/${BASE}...HEAD\`.`,
].join('\n\n'), withModel({
  label: `rebase:#${PR}`, phase: 'Rebase', effort: REB_EFFORT,
  schema: { type: 'object', properties: { up_to_date: { type: 'boolean' }, verify_green: { type: 'boolean' }, ci_green: { type: 'boolean' }, published: { type: 'boolean' }, old_tip: { type: 'string' }, new_tip: { type: 'string' }, changed_paths: { type: 'array', items: { type: 'string' } }, conflicts: { type: 'array', items: { type: 'string' } }, fixes: { type: 'array', items: { type: 'string' } }, problems: { type: 'array', items: { type: 'string' } } }, required: ['up_to_date', 'verify_green', 'published'] },
}, 'rebase'))
if (!reb) throw new Error(`#${PR}: the rebase agent returned nothing; resume this run with the same args`)
// A red or unpublished rebase is not reviewed: the reviewer would read a local state that is not the PR.
if (!reb.verify_green || !reb.published) {
  log(`#${PR}: rebase ${reb.verify_green ? 'green' : 'RED'}, ${reb.published ? 'published' : 'NOT published'}; stopped before review`)
  return { pr: PR, reb, reviews: [], fix: null, stopped: 'rebase red or unpublished: nothing reviewed; read reb.problems, then relaunch (not a resume) with them in steps' }
}

phase('Review')
const paths = reb.changed_paths || []
const base = [
  `Fresh read-only review of PR #${PR} (issue #${N}) after its rebase on origin/${BASE} (worktree ${WT}; D:/prime-game is main). Budget: at most about 60 tool calls; do not edit anything; you may run \`tools\\run.cmd test <path>\` in the worktree.`,
  `The rebase agent reported: ${JSON.stringify(reb)}`,
  `Check that each conflict resolution keeps both sides' intent and that the fixes for the new base are correct: \`git -C ${WTB} range-diff <old_tip>...<new_tip>\` where the tips are known, and \`git -C ${WTB} diff origin/${BASE}...HEAD\`. One copy of each shared class, used consistently; no lost or duplicate lines in data files; no weakened test.${A.focus ? '\n' + A.focus : ''}`,
  'Report findings with severity (blocker, major, minor, nit), file, line, problem and fix. No findings is a valid answer.',
].join('\n\n')
const labels = ['code-reviewer']
const thunks = [() => agent(base, asReviewer({ label: `review:code:#${PR}`, phase: 'Review', agentType: 'code-reviewer', schema: REVIEW }, 'review'))]
// tests/harness/ holds the information-leak test, and client/ renders public data (a rendering leak is an
// information leak, #158), as in issue-task.js.
const netcode = !paths.length || paths.some(p => /^(core|server|net|client|tests\/harness)\//.test(p))
if (netcode) {
  labels.push('netcode-security-reviewer')
  thunks.push(() => agent(base + '\n\nFocus: the ARCHITECTURE §5 invariants over view_of, event audiences and snapshots after the merge of both sides.', asReviewer({ label: `review:netcode:#${PR}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }, 'netcode')))
}
// second_review: a second netcode review where leaks matter, with another lens (and, per launch, another model).
if (netcode && SECOND_REVIEW) {
  labels.push('second netcode-security-reviewer')
  thunks.push(() => agent(base + '\n\nFocus: you are a second, independent netcode review (second_review); another reviewer covers view_of, event audiences and snapshots. Take the attacker\'s side over the merged code instead: what a modified client could now send that the host accepts, and what a curious player could now learn from the wire, logs, audio or screen (the host\'s own client included) because the two sides were joined; and whether the information-leak test (tests/harness/) would still fail on a leak in what changed. A gap there is a finding.', asReviewer({ label: `review:netcode-second:#${PR}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }, 'second_review')))
}
const results = await parallel(thunks)
// Every routed reviewer must answer: an empty review list is not a clean review. A resume replays the ones that did.
const missing = labels.filter((l, i) => !results[i])
if (missing.length) throw new Error(`#${PR}: reviewer(s) ${missing.join(', ')} returned nothing; resume this run with the same args`)
const reviews = results

let fix = null
const serious = reviews.flatMap(r => r.findings || []).filter(f => /blocker|major/i.test(f.severity))
// skeptic: one read-only agent per blocker or major finding tries to refute it; a refuted one is not sent to the fix.
let skeptic = null
let toFix = serious
if (SKEPTICS) {
  const all = []
  reviews.forEach((r, i) => (r.findings || []).forEach(f => { if (/blocker|major/i.test(f.severity)) all.push({ from: labels[i], finding: f }) }))
  const checked = all.slice(0, SKEPTICS)
  skeptic = { refuted: [], stood: [], unchecked: all.slice(SKEPTICS) }
  if (skeptic.unchecked.length) log(`#${PR}: ${skeptic.unchecked.length} blocker or major finding(s) over the skeptic limit of ${SKEPTICS} go to the fix unchecked`)
  if (checked.length) {
    const verdicts = await parallel(checked.map(s => () => agent([
      `PR #${PR} (issue #${N}) after its rebase on origin/${BASE} (worktree ${WT}; D:/prime-game is main).`,
      'A skeptic\'s read-only check of ONE review finding (skeptic), before a fix agent fixes it. Budget: at most about 30 tool calls. Edit nothing; you may run `tools\\run.cmd test <path>` in the worktree.',
      `The finding, from the ${s.from}: ${JSON.stringify(s.finding)}`,
      `Try to refute it: read the code, the tests and the docs it names, the rebase report (${JSON.stringify(reb)}) and PR #${PR}'s body, and decide whether it is wrong: the code already handles it, it misreads the code or one of the two sides, it contradicts an accepted ADR or the engineer's answers, or the fault cannot happen. refuted true only with evidence (file:line, or a command and its output); uncertain, or right in part: refuted false. A finding about an invariant or a leak is refuted only when the code is shown to meet it.`,
    ].join('\n\n'), asReviewer({ label: `skeptic:#${PR}`, phase: 'Review', agentType: 'code-reviewer', schema: SKEPTIC_SCHEMA }, 'skeptic'))))
    if (verdicts.some(v => !v)) throw new Error(`#${PR}: a skeptic returned nothing; resume this run with the same args`)
    checked.forEach((s, k) => (verdicts[k].refuted ? skeptic.refuted : skeptic.stood).push({ ...s, reason: verdicts[k].reason, evidence: verdicts[k].evidence || '' }))
  }
  toFix = skeptic.stood.concat(skeptic.unchecked).map(s => s.finding)
  log(`#${PR}: skeptics refuted ${skeptic.refuted.length} of ${checked.length} blocker or major finding(s)`)
}
if (toFix.length) {
  phase('Fix')
  fix = await agent([
    RULES,
    `Task: fix the blocker and major findings of a fresh review of PR #${PR}, each with a test where it is a behaviour, plus cheap minor ones. Budget: at most about 100 tool calls. Check \`git log\` and PR #${PR}'s body first (a resumed run may have fixed some). Findings: ${JSON.stringify(reviews)}`,
    skeptic && skeptic.refuted.length ? `Skeptics refuted these blocker or major findings (skeptic): ${JSON.stringify(skeptic.refuted)}\n\nDo not fix a refuted finding unless you find the skeptic wrong; list each with the skeptic's reason in PR #${PR}'s body.` : '',
    `\`tools\\run.cmd verify\` until green, \`${PUBLISH}\`, add the findings and what happened to each to PR #${PR}'s body, \`gh pr checks ${PR} --watch\` (at most two fix rounds).`,
    'Return the structured result.',
  ].filter(Boolean).join('\n\n'), withModel({
    label: `fix:#${PR}`, phase: 'Fix', effort: FIX_EFFORT,
    schema: { type: 'object', properties: { fixed: { type: 'array', items: { type: 'string' } }, not_fixed: { type: 'array', items: { type: 'string' } }, verify_green: { type: 'boolean' }, published: { type: 'boolean' }, ci_green: { type: 'boolean' } }, required: ['fixed', 'verify_green', 'published', 'ci_green'] },
  }, 'fix'))
  if (!fix) throw new Error(`#${PR}: the fix agent returned nothing, so ${toFix.length} blocker/major finding(s) may be unfixed; resume this run with the same args`)
}
if (!SKEPTICS) return { pr: PR, reb, reviews, fix }
const out = { pr: PR, reb, reviews, fix, skeptic }
if (serious.length && !toFix.length) out.note = `every blocker and major finding was refuted, so no fix agent ran: add skeptic.refuted, each with its reason, to PR #${PR}'s body`
return out
