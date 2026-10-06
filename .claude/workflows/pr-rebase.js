export const meta = {
  name: 'pr-rebase',
  description: 'Bring one open prime-game PR up to date with its base after a semantic conflict: rebase and reconcile, verify, publish; fresh review; fix only if blocker or major',
  whenToUse: 'The orchestrate-stage skill launches it when a merge leaves an open PR with a semantic conflict (two PRs creating the same classes, a changed interface). A docs or test-list conflict the manager resolves inline instead. args: {n, pr, wt, branch, base?, why, steps?, focus?, plan?, manager?, second_review?, skeptic?, bounded_waits?, efforts?, models?, lean?}. Agents: 2 to 4 (rebase, 1 or 2 reviewers, a fix agent after a blocker or major); second_review adds 1 where the netcode review is routed, skeptic 1 per blocker or major finding (true: every one; a number: at most that many); bounded_waits, efforts, models and lean add none.',
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
// all off by default but bounded_waits (on since #411), as in issue-task.js: with none of them and bounded_waits false
// every agent's prompt, label, phase, schema and options are byte-identical to the script before v2
// (tools/runner/tests/test_workflows.py snapshots them, and the default too), but for the deliberate changes of the
// default prompts that rewrote those snapshots (#413's and #456's RULES lines, #339's netcode sections). The agents
// each one adds count toward the agent number the kickoff approves (2 to 4 without them):
//   second_review true: an extra netcode-security-reviewer pass with an attacker's lens wherever the netcode review
//                 is routed. +1 agent there
//   skeptic       true, or a number: one read-only agent tries to refute each blocker or major finding before the
//                 Fix phase (true: every one; a number: at most that many, the rest go to the fix unchecked); a
//                 refuted finding is not sent to the fix agent but listed in the PR body with the reason (by the fix
//                 agent, or by the manager when every one was refuted: the result's note says so). +1 agent per
//                 finding checked
//   bounded_waits true, the default (#411; missing or null is true): the rebase and fix agents run verify and
//                 publish in the background and poll them with `tools\run.cmd wait` (#303), wait on CI in calls of
//                 at most 240 s, and skip a standalone verify that `wait --verified` shows done, as in issue-task.js.
//                 false: the prompts of before #411, byte for byte. +0 agents
//   efforts       {role: 'low' | 'medium' | 'high' | 'xhigh' | 'max'}. Roles: rebase (default 'high'), review,
//                 netcode, second_review, skeptic, fix (default 'high'). review covers the code reviewer and is the
//                 fallback of netcode, skeptic and (after netcode) second_review. A reviewer gets an effort only when
//                 one is set; otherwise its agent file's applies, as before v2. +0 agents
//   models        {role: model} for the same roles, passed to agent({model}) only when set, with the same fallbacks
//                 and no default (the model-guard ADR and its amendment A). +0 agents
//   lean          true: the rebase and fix agents run as the agent type task-publisher (a lean tool allowlist, no
//                 Skill tool; #332, docs/decisions/2026-10-04-lean-workflow-agent-types.md), as in issue-task.js.
//                 Only agentType is appended to their options. Opt-in until the A/B on #302. +0 agents
// Returns a compact result (#386), as issue-task.js does: pr, n, stopped (why, when the run stopped), the PR's state after
// the last agent (published, ci_green, verify_green), up_to_date, the rebase's conflicts and fixes as counts and its
// problems (in full on a stop), human_steps of the rebase and fix agents in full, the reviews' findings by severity,
// fix (null when none ran) and not_fixed, the skeptics' counts and note (with the refuted findings in full), and
// `full`, a pointer to the run's journal.jsonl with every agent's whole result.
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
const KNOWN = ['n', 'pr', 'wt', 'branch', 'base', 'why', 'steps', 'focus', 'plan', 'manager', 'second_review', 'skeptic', 'bounded_waits', 'efforts', 'models', 'lean']
const unknown = Object.keys(A).filter(k => !KNOWN.includes(k))
if (unknown.length) log(`#${PR}: unknown args ignored: ${unknown.join(', ')}`)
if (A.second_review !== undefined && A.second_review !== null && typeof A.second_review !== 'boolean') throw new Error('pr-rebase: args.second_review must be true or false')
const SECOND_REVIEW = A.second_review === true
if (A.bounded_waits !== undefined && A.bounded_waits !== null && typeof A.bounded_waits !== 'boolean') throw new Error('pr-rebase: args.bounded_waits must be true or false')
// On unless a launch passes false (#411): a missing or null arg is the default.
const BOUNDED = A.bounded_waits !== false
if (A.lean !== undefined && A.lean !== null && typeof A.lean !== 'boolean') throw new Error('pr-rebase: args.lean must be true or false')
const LEAN = A.lean === true
if (A.skeptic !== undefined && A.skeptic !== null && typeof A.skeptic !== 'boolean' && !(Number.isInteger(A.skeptic) && A.skeptic > 0)) {
  throw new Error('pr-rebase: args.skeptic must be true, false or the most findings to check (a positive integer)')
}
// true checks every blocker or major (the issue's criterion: one refuting agent each); a number caps the agents.
const SKEPTICS = A.skeptic === true ? Infinity : (Number.isInteger(A.skeptic) ? A.skeptic : 0)
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
// are appended only where this launch sets them for the role, and under lean the agent type of a role that has none
// (a reviewer's own agentType wins), resolved through CHAIN, last.
const LEAN_TYPES = { rebase: 'task-publisher', fix: 'task-publisher' }
const leanType = (o, role) => (LEAN && !o.agentType ? CHAIN[role].map(r => LEAN_TYPES[r]).find(Boolean) : undefined)
const withModel = (o, role) => {
  const m = set(MODELS, role)
  const t = leanType(o, role)
  const out = m === undefined ? o : { ...o, model: m }
  return t === undefined ? out : { ...out, agentType: t }
}
const asReviewer = (o, role) => withModel(set(EFFORTS, role) === undefined ? o : { ...o, effort: set(EFFORTS, role) }, role)
const REB_EFFORT = EFFORTS.rebase || 'high'
const FIX_EFFORT = EFFORTS.fix || 'high'

const RULES = [
  `You are a task agent of prime-game, run unattended by ${A.manager || 'the manager session'}. No human answers questions: never ask in chat. Root CLAUDE.md applies in full.`,
  `- Work ONLY in the worktree ${WT} (branch ${A.branch}, PR #${PR}, issue #${N}, base ${BASE}). Start every shell command with \`cd ${WTB} && ...\` (Git Bash) or \`Set-Location ${WT}; ...\`. Never change D:/prime-game itself or another worktree.`,
  `- Never: merge a PR, push to main, push by hand or force-push (the branch goes up only through \`tools\\run.cmd publish\`), close an issue, edit the body of #${A.plan || 30}. Do not run commands you expect to prompt. No Godot windows. Temporary files only under the subfolder ${SCRATCH}/ of your scratchpad (it is shared with every other agent). LF line endings. Never weaken, skip or delete a test to make it pass.`,
  '- Commits: Conventional Commits ending with the attribution line your system reminder gives for commits. An edit of any path under .claude/ or addons/ prompts unless the session runs in bypass: list it for the human instead.',
  '- Never use `git stash` (one stash serves every worktree, so the guard asks before a drop of an entry it cannot show is yours). To set work aside: a WIP commit, later `git reset --soft HEAD~1` (free in your own worktree).',
  // #456: a fix agent's own sequence editor (a Python script that reworded a commit) made the guard ask, and the night
  // run waited 9 hours. `git commit --fixup=reword:` and `--fixup=amend:` open the message editor (git refuses -m and -F
  // with them), so a reword is an `amend!` commit made with -F, which autosquash applies as `fixup -C`, editor-free.
  `- Change an earlier commit only with \`git commit --fixup=<sha>\`, then \`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/${BASE}\` (Git Bash; in PowerShell \`$env:GIT_SEQUENCE_EDITOR = ':'; git rebase -i --autosquash origin/${BASE}\`), free in your own worktree. To reword one: \`git commit --allow-empty -F <file>\` with the file's first line \`amend! <that commit's subject>\`, then a blank line and the whole new message, then the same rebase; or leave the message as it is. Nothing else: another sequence editor (a script, \`sed\`, \`-c sequence.editor=...\`), an interactive rebase without \`GIT_SEQUENCE_EDITOR=:\`, \`--fixup=reword:\` or \`--fixup=amend:\` (both open the message editor) and a \`squash!\` commit each open an editor or make the guard ask, which blocks the run until the human returns (a night run waited 9 hours on one, #456).`,
  '- Read the hooks path with `git rev-parse --git-path hooks`, never `git config --get core.hooksPath`: the deny rule `git config *hooksPath*` refuses the whole call.',
  '- Never poll with a foreground `sleep N; cat <log>` (Claude Code blocks it): wait with `tools/run.sh wait <log>`, run_in_background or Monitor.',
  '- Write no file outside your worktree and your scratchpad subfolder, not even an empty throwaway: it prompts and blocks the run (`cat > ../../../../tmp_unused` from a worktree reached D:\\ and waited two hours) or leaves a stray file for a human. Never open a command with a no-op write such as `cat > "$TMP/x" 2>/dev/null;`: `$TMP`, `$TEMP`, `$TMPDIR` and `/tmp` are the system Temp folder, not your scratchpad; output you drop goes to `/dev/null` (Git Bash) or `$null` (PowerShell). A Git Bash path `/c/...` given to `tools\\run.cmd`, PowerShell or another Windows program writes under `D:\\c\\`.',
].join('\n')

const REVIEW = { type: 'object', properties: { reviewer: { type: 'string' }, verdict: { type: 'string' }, findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] }, file: { type: 'string' }, line: { type: 'number' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'problem'] } } }, required: ['verdict', 'findings'] }
const SKEPTIC_SCHEMA = { type: 'object', properties: { refuted: { type: 'boolean' }, reason: { type: 'string' }, evidence: { type: 'string' } }, required: ['refuted', 'reason'] }
// human_steps (#266), as in issue-task.js: each step the engineer takes himself comes back with its whole command, which
// the manager copies into the chat as is (root CLAUDE.md, "Talking to the humans").
const HUMAN_STEPS_SCHEMA = { type: 'array', items: { type: 'object', properties: { why: { type: 'string' }, command: { type: 'string' } }, required: ['why', 'command'] } }
const HUMAN_STEPS = `human_steps: each step only the engineer can take after you (a cleanup, a leftover worktree to remove, a PNG to drag into the PR, a decision), as {why, command}. command: the whole command, ready to paste: ONE PowerShell 5.1 line that starts with \`cd <absolute folder>;\` (\`cd D:\\prime-game;\` for the main checkout, where his terminal is; \`cd ${WT.replace(/\//g, '\\')};\` for your worktree), commands joined with \`;\` (never \`&&\`), never a pointer such as "the command in the PR body". Preview it from that folder first (\`--dry-run\` where the command has one, a read-only listing such as \`git worktree list\`); run it outright only when it is read-only, never one that does his step, changes \`D:\\prime-game\` or prompts. A step without a command (a click in GitHub, a decision) has command "" and says in why what to do and where. The PR and your comment on the issue may carry the commands too.`
// bounded_waits (#303), the same text as in issue-task.js (test_workflows.py compares the two): one paragraph for each
// agent that runs verify, publish or a CI watch, placed after the steps it replaces.
const waits = publishes => [
  'Bounded waits (bounded_waits): this replaces how every `verify`, `publish`, `mutants` and `gh pr checks --watch` step in this prompt and the skills it names is run. A tool call that blocks over about 5 minutes makes your next call write your whole context again (your prompt cache lives 5 minutes). No tool call blocks longer than 240 s: bound it with the shell\'s `timeout` or `wait --max`, never only with the tool\'s timeout.',
  `- Start each one in the Bash tool with run_in_background true (timeout 3600000 for mutants), with a NEW log under ${SCRATCH}/ of your scratchpad for each run (verify-1.log, verify-2.log, publish-1.log, ...): \`cd ${WTB} && tools/run.sh <command> > <log> 2>&1; echo "exit=$?" >> <log>\` (<command>: \`verify\`, \`publish\` with the arguments given above, or \`mutants <spec.json>\`).`,
  `- Then wait in separate calls of \`cd ${WTB} && tools/run.sh wait <log>\` in the Bash tool (in PowerShell \`tools\\run.cmd wait <log>\`), with the tool's timeout set to 300000 (its default of 120000 cuts a 240 s wait short). Exit 124 with a \`wait: still running\` line: call wait again, and never start the job again while it runs. Any other exit is the job's own, its summary printed above a \`wait: ... finished: exit=<n>\` line (verify and publish: 0 is green; mutants: 0 the run completed, 1 a bad spec or a run that could not finish, 2 its scratch worktree could not be removed). Exit 2 with a \`wait: no log\`, \`wait: cannot read\` or \`wait: --max\` line is wait's own error (check the log path), never mutants' exit 2. A log that has not grown for 10 minutes: check the background task.`,
  `- CI: \`cd ${WTB} && timeout 240 gh pr checks <pr> --watch --interval 30; echo rc=$?\` in the Bash tool with the tool's timeout set to 300000 (in PowerShell \`timeout\` is another program), repeated while rc is 124 or 8; rc 1 with "no checks reported" means CI has not started yet: run it again. Otherwise rc 0 is green and 1 red.`,
  publishes ? '- Before `publish`, run `tools/run.sh wait --verified`: exit 0 (the newest verify passed at HEAD with a clean tree) means no standalone `verify` first, because `publish` runs `verify` itself; after any new commit, verify as before.' : '',
  '- If `tools/run.sh wait --help` fails in the worktree (its base predates #303), run them in the foreground as before.',
].filter(Boolean).join('\n')

// The compact result (#386): the harness prints a run's return value into the manager's context, and each later call of
// the manager reads it again. It keeps every field the manager acts on (orchestrate-stage §4) and cuts each long text
// to a line or a count; the agents' full results stay in the run's journal.jsonl, a result line per agent.
const FULL = 'whole results: ~/.claude/projects/<project>/<manager session>/subagents/workflows/<run id>/journal.jsonl (orchestrate-stage §4)'
const line = (s, max = 160) => {
  const t = s === undefined || s === null ? '' : String(s).trim()
  const first = t.split('\n')[0].trim()
  return first.length > max ? `${first.slice(0, max - 1).trimEnd()}…` : first.length < t.length ? `${first} …` : first
}
const lines = (a, max) => (Array.isArray(a) ? a.map(s => line(typeof s === 'string' ? s : JSON.stringify(s), max)) : [])
const SEVERITIES = ['blocker', 'major', 'minor', 'nit']
const tally = (list, key, order) => {
  const c = {}
  for (const x of list || []) { const k = String(x && x[key]); c[k] = (c[k] || 0) + 1 }
  return Object.fromEntries([...order.filter(k => c[k]), ...Object.keys(c).filter(k => !order.includes(k))].map(k => [k, c[k]]))
}
const briefReviews = (by, rs) => rs.map((r, i) => ({ by: by[i], ...tally(r.findings, 'severity', SEVERITIES) }))
const pick = (o, keys) => Object.fromEntries(keys.filter(k => o && o[k] !== undefined && o[k] !== null).map(k => [k, o[k]]))
// A list's "None" or empty entries say nothing.
const items = a => (Array.isArray(a) ? a.filter(x => !(typeof x === 'string' && /^(none\.?)?$/i.test(x.trim()))) : [])

// pr-rebase's own result: the rebase's verdict, the reviews' counts, the last agent's state and the skeptics'.
const brief = (stopped, reviews, fix, extra) => {
  const out = { pr: PR, n: N }
  if (stopped) out.stopped = stopped
  // The last agent that ran says what the PR is now: the fix agent's state, else the rebase's.
  Object.assign(out, pick(fix || reb, ['published', 'ci_green', 'verify_green']), pick(reb, ['up_to_date']))
  out.conflicts = items(reb.conflicts).length
  out.fixes = items(reb.fixes).length
  // In full on a stop: the fresh relaunch's steps need them (orchestrate-stage §5).
  if (items(reb.problems).length) out.problems = stopped ? items(reb.problems) : lines(items(reb.problems))
  out.human_steps = [...(reb.human_steps || []), ...((fix && fix.human_steps) || [])]
  out.reviews = reviews.length ? briefReviews(labels, reviews) : []
  out.fix = fix ? { fixed: items(fix.fixed).length } : null
  if (fix) out.not_fixed = lines(items(fix.not_fixed))
  Object.assign(out, extra)
  out.full = FULL
  return out
}

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
  ...(BOUNDED ? [waits(true)] : []),
  HUMAN_STEPS,
  `Return the structured result. changed_paths: \`git diff --name-only origin/${BASE}...HEAD\`.`,
].join('\n\n'), withModel({
  label: `rebase:#${PR}`, phase: 'Rebase', effort: REB_EFFORT,
  schema: { type: 'object', properties: { up_to_date: { type: 'boolean' }, verify_green: { type: 'boolean' }, ci_green: { type: 'boolean' }, published: { type: 'boolean' }, old_tip: { type: 'string' }, new_tip: { type: 'string' }, changed_paths: { type: 'array', items: { type: 'string' } }, conflicts: { type: 'array', items: { type: 'string' } }, fixes: { type: 'array', items: { type: 'string' } }, problems: { type: 'array', items: { type: 'string' } }, human_steps: HUMAN_STEPS_SCHEMA }, required: ['up_to_date', 'verify_green', 'published'] },
}, 'rebase'))
if (!reb) throw new Error(`#${PR}: the rebase agent returned nothing; resume this run with the same args`)
// A red or unpublished rebase is not reviewed: the reviewer would read a local state that is not the PR.
if (!reb.verify_green || !reb.published) {
  log(`#${PR}: rebase ${reb.verify_green ? 'green' : 'RED'}, ${reb.published ? 'published' : 'NOT published'}; stopped before review`)
  return brief('rebase red or unpublished: nothing reviewed; read problems, then relaunch (not a resume) with them in steps', [], null, {})
}

phase('Review')
const paths = reb.changed_paths || []
const base = [
  `Fresh read-only review of PR #${PR} (issue #${N}) after its rebase on origin/${BASE} (worktree ${WT}; D:/prime-game is main). Budget: at most about 60 tool calls; do not edit anything; you may run \`tools\\run.cmd test <path>\` in the worktree.`,
  `The rebase agent reported: ${JSON.stringify(reb)}`,
  `Check that each conflict resolution keeps both sides' intent and that the fixes for the new base are correct: \`git -C ${WTB} range-diff <old_tip>...<new_tip>\` where the tips are known, and \`git -C ${WTB} diff origin/${BASE}...HEAD\`. One copy of each shared class, used consistently; no lost or duplicate lines in data files; no weakened test.${A.focus ? '\n' + A.focus : ''}`,
  'Report findings with severity (blocker, major, minor, nit), file, line, problem and fix. No findings is a valid answer.',
].join('\n\n')
// #339 (the instruction-diet ADR's N1 (a)), the same sentence as in issue-task.js (test_workflows.py compares the
// two): the netcode reviewers (the second_review pass too) always read the sections where a leak shows, whatever the
// change touches; a change that touches only §4.7 or §7.1 can still add a snapshot field the leak test does not compare.
const NETCODE_SECTIONS = `Always read ARCHITECTURE §5 (per-peer filtering), §4.2 (each event's audience) and §4.6 (the client, the bots and the leak test), whatever the change touches: \`cd ${WTB} && tools/run.sh section docs/ARCHITECTURE.md 5 4.2 4.6\` (read-only; you may run it). A change to §4.7 or §7.1 alone can still add a snapshot field the leak test does not compare.`
const labels = ['code-reviewer']
const thunks = [() => agent(base, asReviewer({ label: `review:code:#${PR}`, phase: 'Review', agentType: 'code-reviewer', schema: REVIEW }, 'review'))]
// tests/harness/ holds the information-leak test, and client/ renders public data (a rendering leak is an
// information leak, #158), as in issue-task.js.
const netcode = !paths.length || paths.some(p => /^(core|server|net|client|tests\/harness)\//.test(p))
if (netcode) {
  labels.push('netcode-security-reviewer')
  thunks.push(() => agent(base + '\n\nFocus: the ARCHITECTURE §5 invariants over view_of, event audiences and snapshots after the merge of both sides. ' + NETCODE_SECTIONS, asReviewer({ label: `review:netcode:#${PR}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }, 'netcode')))
}
// second_review: a second netcode review where leaks matter, with another lens (and, per launch, another model).
if (netcode && SECOND_REVIEW) {
  labels.push('second netcode-security-reviewer')
  thunks.push(() => agent(base + '\n\nFocus: you are a second, independent netcode review (second_review); another reviewer covers view_of, event audiences and snapshots. Take the attacker\'s side over the merged code instead: what a modified client could now send that the host accepts, and what a curious player could now learn from the wire, logs, audio or screen (the host\'s own client included) because the two sides were joined; and whether the information-leak test (tests/harness/) would still fail on a leak in what changed. A gap there is a finding. ' + NETCODE_SECTIONS, asReviewer({ label: `review:netcode-second:#${PR}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }, 'second_review')))
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
    BOUNDED ? waits(true) : '',
    HUMAN_STEPS,
    'Return the structured result.',
  ].filter(Boolean).join('\n\n'), withModel({
    label: `fix:#${PR}`, phase: 'Fix', effort: FIX_EFFORT,
    schema: { type: 'object', properties: { fixed: { type: 'array', items: { type: 'string' } }, not_fixed: { type: 'array', items: { type: 'string' } }, verify_green: { type: 'boolean' }, published: { type: 'boolean' }, ci_green: { type: 'boolean' }, human_steps: HUMAN_STEPS_SCHEMA }, required: ['fixed', 'verify_green', 'published', 'ci_green'] },
  }, 'fix'))
  if (!fix) throw new Error(`#${PR}: the fix agent returned nothing, so ${toFix.length} blocker/major finding(s) may be unfixed; resume this run with the same args`)
}
if (!SKEPTICS) return brief(null, reviews, fix, {})
const extra = { skeptic: { refuted: skeptic.refuted.length, stood: skeptic.stood.length, unchecked: skeptic.unchecked.length } }
if (serious.length && !toFix.length) {
  extra.note = `every blocker and major finding was refuted, so no fix agent ran: add refuted, each with its reason, to PR #${PR}'s body`
  // In full: the manager copies them into the PR body.
  extra.refuted = skeptic.refuted.map(s => ({ from: s.from, ...pick(s.finding, ['severity', 'file', 'line', 'problem']), reason: s.reason }))
}
return brief(null, reviews, fix, extra)
