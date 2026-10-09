export const meta = {
  name: 'issue-task',
  description: 'One prime-game issue in its worktree: implement (or design), fresh reviews chosen from the changed paths, fix, publish, PR, CI, handoff',
  whenToUse: 'The orchestrate-stage skill launches it once per task, after the manager ran `tools\\run.cmd start <n>`. args: {n, title, wt, branch, base?, notes, coord?, decisions?, reading?, testing?, design?, effort?, plan?, manager?, plan_review?, test_review?, second_review?, skeptic?, visual?, bounded_waits?, efforts?, models?, lean?, lean_reason?, ab_review?, checkpoint?, tier?}. Review tier (#606): the diff after the implementer chooses, the worst path winning: full (a path under core/, server/, net/, client/ but client/ui/, voice/ or tests/harness/, no changed paths, a design task, or tier full) runs the chain below; light (any other diff, client/ui/ included) drops the netcode review, test_review, second_review and skeptic even when passed, and plan_review too when the branch area (decided before the implementer) is content, level or tooling. Agents: 3 to 5 (implementer, 1 to 3 reviewers, publisher); plan_review adds 2, test_review 1 (none for a design task or a diff without core, server, net, client or voice code), second_review 1 where the netcode review is routed, skeptic 1 per blocker or major finding (true: every one; a number: at most that many), ab_review 2 (a control code reviewer and a judge; needs models.code), checkpoint none or up to 2 (a fresh implementer for each handoff of one past 150k context); visual, bounded_waits, efforts, models and lean add none.',
  phases: [
    { title: 'Implement', detail: 'one agent in the task worktree; commits, verify green, never publishes (plan_review: a plan agent and a fresh critique of its plan first)' },
    { title: 'Review', detail: 'code-reviewer; netcode-security-reviewer if core/server/net/client/tests/harness changed or a design task; godot-api-checker if .gd/.tscn/.tres changed (optional: a second netcode review, a test review with mutants, a skeptic per blocker or major, ab_review: a control code reviewer and a judge; the light review tier, client/ui/ included, drops the netcode review, the first three and plan_review)' },
    { title: 'Publish', detail: 'fix findings, verify, publish, PR, CI, handoff, board' },
  ],
}

// Saved project workflow (docs/AGENT_WORKFLOW.md §7.1; skill orchestrate-stage).
// args:
//   n        issue number (required)          title   issue title (required)
//   wt       worktree path, D:/... (required)  branch  task branch from `start` (required)
//   base     PR base branch, default 'main' (a stage's release/m<k>, or a parent's branch for a task started with
//            `start --base`); a non-main base reaches `publish --base` and `gh pr create --base`
//   notes    the manager's task notes: specifics, ownership splits of shared files, merge order (required)
//   coord    what runs in parallel and which shared files to touch minimally
//   decisions the engineer's standing decisions that apply, each with where it is recorded
//   reading  what to read first (default: the issue's links, handoffs and ADRs, the ARCHITECTURE sections it names by
//            section, and the code; area CLAUDE.md files and .claude/rules/ load by path, #339)
//   testing  the test expectations (default by the branch's area: core/ a seeded Match; net/ and server/ the
//            loopback transport plus the ENet runs; tooling the runner selftest; code tasks only)
//   design   true: a docs-only design task (options for the engineer, a proposed issue split, the netcode reviewer)
//   effort   the implementer's effort: default 'high', 'xhigh' for a design task
//   plan     the plan issue whose body no agent edits (default 30)
//   manager  who runs this, for the agents' first line (default 'the manager session')
//   tier     'full' forces the full review chain; missing or null, the review tier follows the change's risk (#606, the
//            engineer's answer on #302: the full chain only where a mistake becomes a cheat, a desync or a leak). The
//            implementer's changed paths choose, the worst one winning: full for a path under core/ server/ net/
//            client/ voice/ tests/harness/ (quick-task.js's REVIEWED), no changed paths or a design task; light for any
//            other diff (docs, content, levels, tooling, and the UI's client/ui/: the engineer's answer 2b on #302,
//            comment 6085059719; the rest of client/ stays full, #158). Light runs the code reviewer (and
//            godot-api-checker on a .gd/.tscn/.tres change; ab_review still adds its pair) and the publisher, and
//            drops the netcode review, test_review, second_review and skeptic even when passed. plan_review runs
//            before the diff exists, so the branch's area (`start`'s <area>/ prefix) decides it: content, level and
//            tooling skip it, unless tier is 'full'.
//            Only full can be forced: the diff's worst path always wins. The publisher's prompt names the tier
//            (`metrics` groups the runs by it) and the result carries tier and tier_skipped
// Optional pipeline v2 args (docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md, item 4), all off
// by default but bounded_waits (on since #411) and lean (on since #458). With none of them and bounded_waits and lean
// false every agent's prompt, label, phase, schema and options are byte-identical to the script before v2
// (tools/runner/tests/test_workflows.py snapshots them, and the default too), so a launch or resume with the earlier
// args, bounded_waits false and lean false is unchanged, but for
// the deliberate changes of the default prompts that rewrote those snapshots (#413's and #456's RULES lines, #339's
// section reads, #468's reading line, #470's digests: the reviewers' and the test reviewer's digest of the
// implementer's report, the implementer's summary cap, and the publisher's plan summary and inline finish-task
// steps; #606's review tier line in the publisher's prompt and #605's fast-verify wording). The agents each one adds count toward the agent number the kickoff approves (3 to 5 without them):
//   plan_review   true: a plan agent writes the plan (files, interfaces, tests, risks), a fresh code-reviewer
//                 critiques it, then the implementer builds with both; the PR summarizes them. +2 agents. Since #469
//                 the whole plan is the plan agent's comment on the issue and its result the short form (at most
//                 about 8,000 characters of JSON; capPlan cuts a longer one), with a file_map (paths, line ranges
//                 and facts, read at base_sha) the implementer trusts for each file unchanged since that sha. The
//                 manager passes models.plan (Sonnet, orchestrate-stage §3); the critique stays on the review model
//   test_review   true: after the reviews one agent plants 3 to 5 mutants in the diff's production code with
//                 `tools\run.cmd mutants` (P7, #184), each in a scratch worktree; a survived mutant is a finding, and
//                 the publisher stops and reports when `mutants` exits 2. Missing on the task's branch: reported in
//                 the result and the PR, and the run goes on. +1 agent (none for a design task, or a diff with no
//                 path under core/ server/ net/ client/ voice/)
//   second_review true: an extra netcode-security-reviewer pass with an attacker's lens wherever the netcode review
//                 is routed (core/ server/ net/ client/ tests/harness/ or a design task). +1 agent there
//   skeptic       true, or a number: one read-only agent tries to refute each blocker or major finding before the
//                 publisher (true: every one; a number: at most that many, the rest go to the publisher unchecked);
//                 a refuted finding is listed in the PR with the reason. +1 agent per finding checked
//   visual        true (the playcheck scenarios the notes name), or a scenario name or a list of them: the
//                 implementer runs `tools\run.cmd playcheck <scenario>` (P9, #186) and returns the PNGs, the code
//                 reviewer reads them, and the rules line on Godot windows also allows playcheck. Missing on the
//                 task's branch: reported in the result and the PR. +0 agents
//   bounded_waits true, the default (#411; missing or null is true): the implementer, the test reviewer and the full
//                 publisher run verify, publish and mutants in the background and poll them with `tools\run.cmd wait`
//                 (#303), and wait on CI in calls of at most 180 s, so no tool call outlasts their 5-minute prompt
//                 cache; the publisher runs no standalone verify before `publish`, which verifies itself unless an
//                 identical tree was just verified green (#471). Without `wait` on the branch: the foreground.
//                 false: the prompts of before #411, byte for byte. +0 agents
//   efforts       {role: 'low' | 'medium' | 'high' | 'xhigh' | 'max'}. Roles: implement (falls back to effort, which
//                 falls back to today's default), plan (falls back to implement's), plan_review, review, code,
//                 netcode, second_review, godot, test_review (default 'high'), skeptic, publish (default 'high'),
//                 publish_clean (falls back to publish). review is the fallback of code (the diff's code reviewer
//                 alone, #535), plan_review, netcode, skeptic and (after netcode) second_review. An agentType reviewer
//                 gets an effort only when one is set; otherwise its agent file's applies, as before v2. +0 agents
//   models        {role: model} for the same roles, passed to agent({model}) only when set, with the same fallbacks
//                 (plan falls back to implement, publish_clean to publish, code to review, none to a default). No
//                 default names a model (the model-guard ADR and its amendment A: the manager passes one per launch
//                 where the kickoff allows it). +0 agents
//                 The role code is the diff's code-reviewer only: models.code changes no other reviewer, where
//                 models.review also changes the plan critique, the netcode reviews and the skeptics (#535's A/B).
//                 The role publish_clean is the full publisher of a run that the reviews, the test review and the
//                 skeptics left with no blocker or major open (a skeptic-refuted finding is closed, one over the
//                 skeptic limit is open; the plan critique's findings do not count), never of a design task or of a
//                 run stopped by mutants. It is the one-wave trial of #308 of a cheaper model from the shared list
//                 for that publisher (docs/decisions/2026-09-28-effort-and-workflow-bounds.md, amended 2026-10-04);
//                 when models or efforts name it, the result's publish_clean says whether it applied.
//   lean          true (the default since #458; a missing or null arg is true): the implementer, the plan agent and
//                 the test reviewer run as the agent type task-implementer, the publisher (both kinds) as
//                 task-publisher: lean tool allowlists, no Skill tool (#332,
//                 docs/decisions/2026-10-04-lean-workflow-agent-types.md). Only agentType is appended to their
//                 options; prompts, efforts and models stay. A task editing .claude/workflows/ stays lean: its agents
//                 read docs/workflow-scripts.md (#557). false: the general workflow agent, only with lean_reason.
//                 .claude/agents/ in the manager's checkout must have both files (`tools\run.cmd agents-check
//                 --launch`; an agentType with no file throws at agent()). +0 agents
//   lean_reason   with lean false (required then, #557): why the general agent, a non-empty string, e.g. a resume of a
//                 run launched before #458. It changes no prompt or option; the result carries it. Ignored with lean
//                 on (a log line says so). +0 agents
//   ab_review     true: the A/B of the code reviewer's model (#535, docs/decisions/2026-10-07-code-reviewer-model-ab.md).
//                 Needs models.code, the model on trial, other than the review model (models.review, else the model in
//                 .claude/agents/code-reviewer.md), which is the control's. A control code-reviewer runs beside the trial one with the same
//                 prompt on the review model, and both reviews go on as usual (the publisher fixes the union, so the run
//                 is reviewed at least as an all-Opus run is). Then a read-only judge on the review model, told neither
//                 model, rules each finding of both valid, invalid or unsure with its own severity and pairs the
//                 findings that name the same defect; `metrics` scores the runs from the journal. Nothing to judge
//                 (neither reviewer found anything): no judge. +2 agents (+1 with nothing to judge)
//   checkpoint    true (#559; opt-in, off until the engineer's yes after a measurement): an implementer past 150,000
//                 tokens of context hands over to a fresh one. It reads its context from the harness's reminder
//                 `<total_tokens>N tokens left` after each tool result (the budget B, 15,000,000, less N is the context:
//                 282 of 283 readings exact on 2026-10-08) or, seeing none, stops after 60 tool calls; it commits, writes
//                 a note (done, left, decisions, gotchas, verify state) to a<n>/handoff-<k>.md in the scratchpad and
//                 returns handoff, the note's path. A fresh implementer, labelled implement:#<n>#<k> (k = 2, 3) with the
//                 same type, effort and model, continues from the note and the worktree; at most 2 handoffs (the third
//                 implementer cannot hand over). The implementer's result is then the last one's with the union of the
//                 decisions, needs_engineer, proposed_issues, provisional_content and commits, and the compact result
//                 gains handoffs. Off: every prompt, label and option unchanged. +0 agents, up to +2 with handoffs
// Returns a compact result (#386), not the agents' results: n, stopped (why, when the run stopped), the PR (pr, pr_url,
// published, ci_green, closes_issue), the implementer's verify_green, complete and summary line, needs_engineer and
// human_steps in full, not_fixed and merge_notes a line each, fixed as a count, the reviews' findings by severity, the
// review tier (tier; tier_skipped, the agents passed that it dropped, #606), and
// what each v2 option adds (plan, test_review, skeptic, visual, publish_clean, ab_review), and under lean false
// lean_off (#557: how many general agents it launched, and the lean_reason); `full` points to the run's
// journal.jsonl, which holds every agent's whole result. 1.1 to 2 kB on 8 real runs (median 1.25 kB), where the whole
// was 8 to 17 kB.
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
// A release base (release/m<k>, any base that is not main or a task branch) is always passed, so the base never
// depends on the record `start --base` left in this checkout. A stacked parent's task branch is not: publish
// follows the PR's live base, which GitHub retargets once the parent merges and its branch is deleted.
const TASK_BRANCH = /^[a-z][a-z0-9]*\/[0-9]+-[a-z0-9][a-z0-9._-]*$/
const PUBLISH = `tools\\run.cmd publish${BASE === 'main' || TASK_BRANCH.test(BASE) ? '' : ` --base ${BASE}`}`

// The pipeline v2 args. A wrong value throws before any agent runs: a typo must not silently drop a review the
// kickoff paid for. An unknown arg only logs, as before v2 (a manager may pass extra fields).
const KNOWN = ['n', 'title', 'wt', 'branch', 'base', 'notes', 'coord', 'decisions', 'reading', 'testing', 'design', 'effort', 'plan', 'manager', 'plan_review', 'test_review', 'second_review', 'skeptic', 'visual', 'bounded_waits', 'efforts', 'models', 'lean', 'lean_reason', 'ab_review', 'checkpoint', 'tier']
const unknown = Object.keys(A).filter(k => !KNOWN.includes(k))
if (unknown.length) log(`#${N}: unknown args ignored: ${unknown.join(', ')}`)
const flag = k => {
  if (A[k] !== undefined && A[k] !== null && typeof A[k] !== 'boolean') throw new Error(`issue-task: args.${k} must be true or false`)
  return A[k] === true
}
const PLAN_REVIEW = flag('plan_review')
const TEST_REVIEW = flag('test_review') && !DESIGN
if (flag('test_review') && DESIGN) log(`#${N}: test_review skipped: a design task changes no production code`)
const SECOND_REVIEW = flag('second_review')
if (A.skeptic !== undefined && A.skeptic !== null && typeof A.skeptic !== 'boolean' && !(Number.isInteger(A.skeptic) && A.skeptic > 0)) {
  throw new Error('issue-task: args.skeptic must be true, false or the most findings to check (a positive integer)')
}
// true checks every blocker or major (the issue's criterion: one refuting agent each); a number caps the agents.
const SKEPTICS = A.skeptic === true ? Infinity : (Number.isInteger(A.skeptic) ? A.skeptic : 0)
// On unless a launch passes false (#411): a missing or null arg is the default.
const BOUNDED = flag('bounded_waits') || A.bounded_waits === undefined || A.bounded_waits === null
// On unless a launch passes false (#458, the engineer's N4 (b)): a missing or null arg is the default.
const LEAN = flag('lean') || A.lean === undefined || A.lean === null
// #557: lean false needs a reason, so a stray false (2026-10-06 to 08: 27 general implementers and publishers at about
// twice the first-call tokens) is refused before any agent runs. The reason changes no prompt or option.
if (A.lean_reason !== undefined && A.lean_reason !== null && !(typeof A.lean_reason === 'string' && A.lean_reason.trim())) throw new Error('issue-task: args.lean_reason must be a non-empty string')
if (!LEAN && !A.lean_reason) throw new Error('issue-task: args.lean false needs args.lean_reason (a non-empty string: why the general agent, e.g. a resume of a run launched before #458; its agents stay unchanged). A task editing .claude/workflows/ runs lean: its agents read docs/workflow-scripts.md')
if (LEAN && A.lean_reason) log(`#${N}: lean_reason ignored: lean is on`)
const V = A.visual
const SCENES = V === true
  ? 'the playcheck scenarios the task notes name (none named: the scenarios under tools/playcheck/ that show what this task changes)'
  : typeof V === 'string' && V !== '' ? `\`${V}\``
  : Array.isArray(V) && V.length && V.every(s => typeof s === 'string' && s !== '') ? V.map(s => `\`${s}\``).join(', ')
  : null
if (SCENES === null && V !== undefined && V !== null && V !== false) throw new Error('issue-task: args.visual must be true, a playcheck scenario name or a list of them')
const VISUAL = SCENES !== null
const ROLES = ['implement', 'plan', 'plan_review', 'review', 'code', 'netcode', 'second_review', 'godot', 'test_review', 'skeptic', 'publish', 'publish_clean']
// The roles a role falls back to, in order, when this launch sets nothing for it.
const CHAIN = {
  implement: ['implement'], plan: ['plan', 'implement'], plan_review: ['plan_review', 'review'], review: ['review'],
  code: ['code', 'review'], netcode: ['netcode', 'review'], second_review: ['second_review', 'netcode', 'review'], godot: ['godot'],
  test_review: ['test_review'], skeptic: ['skeptic', 'review'], publish: ['publish'],
  publish_clean: ['publish_clean', 'publish'],
}
const perRole = (k, values) => {
  const m = A[k]
  if (m === undefined || m === null) return {}
  if (typeof m !== 'object' || Array.isArray(m)) throw new Error(`issue-task: args.${k} must be an object {role: value}; roles: ${ROLES.join(', ')}`)
  for (const [role, v] of Object.entries(m)) {
    if (!ROLES.includes(role)) throw new Error(`issue-task: args.${k}.${role}: no such role; roles: ${ROLES.join(', ')}`)
    if (typeof v !== 'string' || v === '' || (values && !values.includes(v))) throw new Error(`issue-task: args.${k}.${role} must be ${values ? values.join(', ') : 'a model name'}`)
  }
  return m
}
const EFFORTS = perRole('efforts', ['low', 'medium', 'high', 'xhigh', 'max'])
const MODELS = perRole('models', null)
const set = (m, role) => CHAIN[role].map(r => m[r]).find(v => v !== undefined)
// ab_review (#535): an A/B needs a model on trial that differs from the control's (the review model).
const AB_REVIEW = flag('ab_review')
if (AB_REVIEW && MODELS.code === undefined) throw new Error('issue-task: args.ab_review needs models.code, the code reviewer\'s model on trial')
if (AB_REVIEW && DESIGN) throw new Error('issue-task: args.ab_review is for code tasks, not a design task: another population')
if (AB_REVIEW && MODELS.code === MODELS.review) throw new Error('issue-task: args.ab_review needs models.code other than models.review, the control\'s model')
const CHECKPOINT = flag('checkpoint')
// #606: only the full tier can be forced; a forced light tier would let a core/ diff skip the reviews it needs.
if (A.tier !== undefined && A.tier !== null && A.tier !== 'full') throw new Error('issue-task: args.tier must be \'full\' (or missing: the diff after the implementer chooses the review tier, its worst path winning; light cannot be forced)')
const FORCED_FULL = A.tier === 'full'
// Today's options keep their keys and order; an effort (agentType reviewers only: the others carry their default)
// and a model are appended only where this launch sets them for the role, and under lean the agent type of a role
// that has none (a reviewer's own agentType wins), resolved through CHAIN, last.
const LEAN_TYPES = { implement: 'task-implementer', plan: 'task-implementer', test_review: 'task-implementer', publish: 'task-publisher' }
const leanType = (o, role) => (LEAN && !o.agentType ? CHAIN[role].map(r => LEAN_TYPES[r]).find(Boolean) : undefined)
// #557: every agent's options are built here, as agent() is called, so this counts the general agents it launched.
let GENERAL = 0
const withModel = (o, role) => {
  const m = set(MODELS, role)
  const t = leanType(o, role)
  const out = m === undefined ? o : { ...o, model: m }
  if (!t && !o.agentType) GENERAL += 1
  return t === undefined ? out : { ...out, agentType: t }
}
const asReviewer = (o, role) => withModel(set(EFFORTS, role) === undefined ? o : { ...o, effort: set(EFFORTS, role) }, role)
const IMPL_EFFORT = EFFORTS.implement || A.effort || (DESIGN ? 'xhigh' : 'high')
const PLAN_EFFORT = EFFORTS.plan || IMPL_EFFORT
const TEST_EFFORT = EFFORTS.test_review || 'high'
const PUB_EFFORT = EFFORTS.publish || 'high'
const SERIOUS = /blocker|major/i

// #468: the reading rule for code, every agent's (the token audit of 2026-10-06: big code files read whole, the
// same content read twice, one read per turn). The same text in issue-task.js and pr-rebase.js; test_workflows.py
// compares the two. It names no value of this run, so it is the same in every prompt.
const READ_RULE = '- Reading (the docs-by-section rule of #339, extended to code by #468): a code file over 400 lines gets its outline or a `grep -n` (the Grep tool) first, then only the range you need; read it whole only when you restructure it. `cd <your worktree> && tools/run.sh section <file>` (read-only; you may run it) prints its line count and its top-level symbols with line ranges (run from main it shows main\'s copy), and `tools/run.sh section <file> <symbol>` prints one symbol (a name or Class.method); otherwise Read with offset and limit. If the rows of that outline do not each start with a kind (def, async, class, func, static, signal, enum, const, let, var, function, assign or block), that is, it shows `#` comments as headings or nothing after its first line (a base before #468), use `grep -n`. What you read stays in your context: read it again only after an edit, a rebase, a checkout, a failed Edit or a compaction. Reads that do not depend on each other go in one message as parallel calls, or, where your shell commands allow it, as several `sed -n` ranges in one command.'
const RULES = [
  `You are a task agent of prime-game, run unattended by ${A.manager || 'the manager session'} through a workflow. No human answers questions: never ask in chat; everything goes into the repo or GitHub. Root CLAUDE.md applies in full (hard rules, invariants, ownership, shell notes).`,
  `- Work ONLY in the worktree ${WT} (branch ${A.branch}, PR base ${BASE}; the manager already ran \`start\`, never run it again). Start every shell command with \`cd ${WTB} && ...\` (Git Bash) or \`Set-Location ${WT}; ...\` (PowerShell), and use absolute paths under ${WT} for Read, Edit and Write. Never change D:/prime-game itself (that is main) or another worktree.`,
  `- Never: merge a PR, push to main, push by hand or force-push (the branch goes up only through \`tools\\run.cmd publish\`), close or reopen an issue (humans close issues), edit the body of #${PLAN}, \`gh pr merge\`.`,
  '- Do not run a command you expect to prompt (a delete, reset, rebase or branch delete outside your worktree and task branch; an edit of any path under .claude/ or addons/ unless the session runs in bypass): a prompt blocks the run until the human returns. List such a step in the handoff for the human instead.',
  '- Never use `git stash` (one stash serves every worktree, so the guard asks before a drop of an entry it cannot show is yours). To set work aside: a WIP commit, later `git reset --soft HEAD~1` (free in your own worktree).',
  // #456: a fix agent's own sequence editor (a Python script that reworded a commit) made the guard ask, and the night
  // run waited 9 hours. #457 lets any editor through in the own worktree on its task branch, but an editor that opens
  // still hangs a headless agent, so the recipe stays editor-free. `git commit --fixup=reword:` and `--fixup=amend:`
  // open the message editor (git refuses -m and -F with them), so a reword is an `amend!` commit made with -F, which
  // autosquash applies as `fixup -C`.
  `- Change an earlier commit only with \`git commit --fixup=<sha>\`, then \`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/${BASE}\` (Git Bash; in PowerShell \`$env:GIT_SEQUENCE_EDITOR = ':'; git rebase -i --autosquash origin/${BASE}\`), free in your own worktree on your task branch. To reword one: \`git commit --allow-empty -F <file>\` with the file's first line \`amend! <that commit's subject>\`, then a blank line and the whole new message, then the same rebase; or leave the message as it is. The last commit alone: \`git commit --amend --no-edit\` or \`--amend -F <file>\`, never a bare \`--amend\`, which opens the editor. Nothing else: another sequence editor (a script, \`sed\`, \`-c sequence.editor=...\`), an interactive rebase without \`GIT_SEQUENCE_EDITOR=:\`, \`--fixup=reword:\` or \`--fixup=amend:\` (both open the message editor) and a \`squash!\` commit each can open an editor or run a program on the todo list (a script can add \`exec\` lines): an editor that opens hangs the call until its timeout, and under Claude Code's \`GIT_EDITOR=true\` a \`--fixup=reword:\` keeps the old message without a word. Since #457 the guard lets each of these through in your own worktree on your task branch (before it, its ask held a night run 9 hours, #456); it still asks for \`git rebase --exec\` and for any rebase in the main checkout or another worktree.`,
  '- Read the hooks path with `git rev-parse --git-path hooks`, never `git config --get core.hooksPath`: the deny rule `git config *hooksPath*` refuses the whole call.',
  '- Never poll with a foreground `sleep N; cat <log>` (Claude Code blocks it): wait with `tools/run.sh wait <log>`, run_in_background or Monitor.',
  '- Write no file outside your worktree and your scratchpad subfolder, not even an empty throwaway: it prompts and blocks the run (`cat > ../../../../tmp_unused` from a worktree reached D:\\ and waited two hours) or leaves a stray file for a human. Never open a command with a no-op write such as `cat > "$TMP/x" 2>/dev/null;`: `$TMP`, `$TEMP`, `$TMPDIR` and `/tmp` are the system Temp folder, not your scratchpad; output you drop goes to `/dev/null` (Git Bash) or `$null` (PowerShell). A Git Bash path `/c/...` given to `tools\\run.cmd`, PowerShell or another Windows program writes under `D:\\c\\`.',
  VISUAL
    ? '- No Godot windows: headless runs only; a screenshot only through `tools\\run.cmd shot` or `tools\\run.cmd playcheck` (both off-screen).'
    : '- No Godot windows: headless runs only; a screenshot only through `tools\\run.cmd shot` (off-screen).',
  `- Temporary files (commit messages, PR bodies, comments, probes): only under the subfolder ${SCRATCH}/ of your scratchpad, which every agent of every running workflow shares (another task's agent once overwrote a pr_body.md); or ${WT}/tests/scratch/ (gitignored) when they must be under res://. Nowhere else.`,
  READ_RULE,
  '- Write files with LF line endings (Python: newline="" or bytes). The content API classes are GameRole and RuleEffect (never Role or Effect).',
  '- A game rule that no ADR, ARCHITECTURE section or issue comment settles: do not invent it. Write options with a recommendation under "Needs the engineer" (PR and handoff) and continue with the recommended one if it can be reverted. A placeholder number you must add is marked "not a decision".',
  '- Files in content/ and levels/ are provisional under docs/decisions/2026-09-29-mvp-content-built-by-the-engineer.md: the engineer approves them in the PR; the PR says so and names them.',
  '- The engineer\'s answers in issue and PR comments override older text, including these notes.',
  '- Commits: small Conventional Commits, one logical change each, message from a file (`git commit -F`), each ending with the attribution line your system reminder gives for commits; a PR body ends with the line it gives for pull requests.',
  A.decisions ? `- The engineer's standing decisions for this work:\n${A.decisions}` : '',
].filter(Boolean).join('\n')

// #470: the implementer's summary is capped (3,552 characters on average in the token audit of 2026-10-06, written
// once and read by every later agent): a few lines on what changed and why; the why of each choice goes in decisions.
const SUMMARY_MAX = 1200
const IMPL = {
  type: 'object',
  properties: {
    verify_green: { type: 'boolean' },
    verify_tail: { type: 'string' },
    changed_paths: { type: 'array', items: { type: 'string' } },
    commits: { type: 'array', items: { type: 'string' } },
    complete: { type: 'boolean' },
    left: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string', maxLength: SUMMARY_MAX },
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
    human_steps: { type: 'array', items: { type: 'object', properties: { why: { type: 'string' }, command: { type: 'string' } }, required: ['why', 'command'] } },
  },
  required: ['published', 'handoff_posted'],
}
// human_steps (#266): each step the engineer takes himself comes back with its whole command, which the manager copies
// into the chat as is (root CLAUDE.md, "Talking to the humans"; docs/interventions/2026-10-03-engineer-commands-in-the-chat.md).
const HUMAN_STEPS = `human_steps: each step only the engineer can take after you (a cleanup, a leftover worktree to remove, a PNG to drag into the PR, a decision), as {why, command}. command: the whole command, ready to paste: ONE PowerShell 5.1 line that starts with \`cd <absolute folder>;\` (\`cd D:\\prime-game;\` for the main checkout, where his terminal is; \`cd ${WT.replace(/\//g, '\\')};\` for your worktree), commands joined with \`;\` (never \`&&\`), never a pointer such as "the command in the PR body". Preview it from that folder first (\`--dry-run\` where the command has one, a read-only listing such as \`git worktree list\`); run it outright only when it is read-only, never one that does his step, changes \`D:\\prime-game\` or prompts. A step without a command (a click in GitHub, a decision) has command "" and says in why what to do and where. The PR and your comment on the issue may carry the commands too.`
// bounded_waits (#303): one paragraph for each agent that runs verify, publish, mutants or a CI watch, placed after the
// steps it replaces. pr-rebase.js carries the same text (test_workflows.py compares the two). `loops` (#574): the
// implementer's inner loop may run `verify --fail-fast`; the verify it reports, and publish's, run every step.
const waits = (publishes, loops = false) => [
  'Bounded waits (bounded_waits): this replaces how every `verify`, `publish`, `mutants` and `gh pr checks --watch` step in this prompt and the skills it names is run. A tool call that blocks over about 5 minutes makes your next call write your whole context again (your prompt cache lives 5 minutes). No tool call blocks longer than 180 s: bound it with the shell\'s `timeout` or `wait --max`, never only with the tool\'s timeout.',
  `- Start each one in the Bash tool with run_in_background true (timeout 3600000 for mutants), with a NEW log under ${SCRATCH}/ of your scratchpad for each run (verify-1.log, verify-2.log, publish-1.log, ...): \`cd ${WTB} && tools/run.sh <command> > <log> 2>&1; echo "exit=$?" >> <log>\` (<command>: \`verify\`, \`publish\` with the arguments given above, or \`mutants <spec.json>\`).`,
  `- Then wait in separate calls of \`cd ${WTB} && tools/run.sh wait <log>\` in the Bash tool (in PowerShell \`tools\\run.cmd wait <log>\`), with the tool's timeout set to 300000 (its default of 120000 cuts a 180 s wait short). Exit 124 with a \`wait: still running\` line: call wait again, and never start the job again while it runs. Any other exit is the job's own, its summary printed above a \`wait: ... finished: exit=<n>\` line (verify and publish: 0 is green; mutants: 0 the run completed, 1 a bad spec or a run that could not finish, 2 its scratch worktree could not be removed). Exit 2 with a \`wait: no log\`, \`wait: cannot read\` or \`wait: --max\` line is wait's own error (check the log path), never mutants' exit 2. A log that has not grown for 10 minutes: check the background task.`,
  `- CI: \`cd ${WTB} && timeout 180 gh pr checks <pr> --watch --interval 30; echo rc=$?\` in the Bash tool with the tool's timeout set to 300000 (in PowerShell \`timeout\` is another program), repeated while rc is 124 or 8; rc 1 with "no checks reported" means CI has not started yet: run it again. Otherwise rc 0 is green and 1 red. CI runs every test (\`verify --full\`; a local \`verify\` is doctor, lint and check, #605): its green is the test gate, so never run \`verify --full\` locally.`,
  publishes ? '- No standalone `verify` before `publish`: after fixes, run the tests they touch and `check`, then `publish`. It verifies, unless the newest verify passed on this identical tree under 2 hours ago (it says so and pushes on that), and a red verify inside it pushes nothing.' : '',
  loops ? '- In your inner loop you may run `verify --fail-fast` (it stops at the first red step); the run you report as verify_tail, and publish\'s, is a plain `verify`.' : '',
  '- If `tools/run.sh wait --help` fails in the worktree (its base predates #303), run them in the foreground as before.',
].filter(Boolean).join('\n')
// #455: with bounded waits the test reviewer runs each mutants spec, and the publisher a survived mutant again, in the
// background with a new log and `wait`, as verify and publish; bounded_waits false keeps the text of before #411.
const MUTANTS_RUN = BOUNDED
  ? `Run each spec in the background, never in the foreground (a foreground call dies at 600 s, and setup and the baseline come before the first mutant): \`cd ${WTB} && tools/run.sh mutants <spec.json> > <log> 2>&1; echo "exit=$?" >> <log>\` in the Bash tool with run_in_background true and its timeout 3600000, a NEW log under ${SCRATCH}/ of your scratchpad for each run (mutants-1.log, mutants-2.log, ...), then \`cd ${WTB} && tools/run.sh wait <log>\` in separate calls until it finishes, as the bounded waits below say. A spec may hold several mutants (setup and the baseline then run once); one run at a time: another mutants run in the same checkout exits 1.`
  : 'Run ONE mutant per `tools\\run.cmd mutants <spec.json>` call (a foreground call dies at 600 s), or start it in the background and wait for it.'
const MUTANTS_RERUN = BOUNDED
  ? `then run that mutant again in the background (a NEW log under ${SCRATCH}/ of your scratchpad, then \`tools/run.sh wait <log>\`, as the bounded waits below say) to show it killed`
  : 'then run that mutant again (one per call, or in the background: a foreground call dies at 600 s) to show it killed'
// The pipeline v2 schemas.
const STRINGS = { type: 'array', items: { type: 'string' } }
// #469 (the token audit of 2026-10-06): 3 plan agents sent 23 to 28 KB of StructuredOutput JSON that did not parse
// and had to emit it again, and the implementer re-read 105 of the 168 files its planner had read. So the whole plan
// goes in one comment on the issue and the result is its short form, capped at PLAN_MAX characters of JSON (capPlan
// cuts a longer one before the critique and the implementer get it); its file_map holds the paths, line ranges and
// facts the plan rests on, read at base_sha, which the implementer trusts for each file unchanged since that sha.
const PLAN_MAX = 8000
const PLAN_SUMMARY_MAX = 1500
const PLAN_LISTS = ['criteria', 'files', 'interfaces', 'tests', 'docs', 'risks', 'questions', 'steps']
const FILE_MAP = {
  type: 'object',
  properties: {
    base_sha: { type: 'string' },
    files: {
      type: 'array',
      items: { type: 'object', properties: { path: { type: 'string' }, lines: { type: 'string' }, facts: STRINGS }, required: ['path', 'facts'] },
    },
  },
  required: ['base_sha', 'files'],
}
const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string', maxLength: PLAN_SUMMARY_MAX }, criteria: STRINGS, files: STRINGS, interfaces: STRINGS,
    tests: STRINGS, docs: STRINGS, risks: STRINGS, questions: STRINGS, steps: STRINGS, file_map: FILE_MAP,
    comment_url: { type: 'string' },
  },
  required: ['summary', 'criteria', 'files', 'tests', 'file_map'],
}
const PLAYCHECK = {
  type: 'object',
  properties: {
    available: { type: 'boolean' }, scenarios: STRINGS, exit_codes: { type: 'array', items: { type: 'number' } },
    pngs: STRINGS, notes: { type: 'string' },
  },
  required: ['available', 'pngs'],
}
const IMPL_SCHEMA = VISUAL ? { ...IMPL, properties: { ...IMPL.properties, playcheck: PLAYCHECK }, required: [...IMPL.required, 'playcheck'] } : IMPL
const TEST_REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    available: { type: 'boolean' },
    exit_2: { type: 'boolean' },
    mutants: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' }, line: { type: 'number' }, original: { type: 'string' }, replacement: { type: 'string' },
          tests: STRINGS, result: { type: 'string', enum: ['killed', 'survived', 'error', 'equivalent'] },
          failing_tests: STRINGS, exit_code: { type: 'number' },
        },
        required: ['file', 'result'],
      },
    },
    findings: REVIEW.properties.findings,
    notes: { type: 'string' },
  },
  required: ['available', 'exit_2', 'findings'],
}
const SKEPTIC_SCHEMA = {
  type: 'object',
  properties: { refuted: { type: 'boolean' }, reason: { type: 'string' }, evidence: { type: 'string' } },
  required: ['refuted', 'reason'],
}
// ab_review (#535): the judge's verdict on each finding of reviewer 1 (the trial) and 2 (the control), and the pairs.
const AB_JUDGE_SCHEMA = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          reviewer: { type: 'number', enum: [1, 2] }, index: { type: 'number' },
          verdict: { type: 'string', enum: ['valid', 'invalid', 'unsure'] },
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] }, reason: { type: 'string' },
        },
        required: ['reviewer', 'index', 'verdict', 'severity'],
      },
    },
    matches: {
      type: 'array',
      items: { type: 'object', properties: { first: { type: 'number' }, second: { type: 'number' } }, required: ['first', 'second'] },
    },
    notes: { type: 'string' },
  },
  required: ['verdicts', 'matches'],
}

// The default test expectations follow the task branch's area (`<area>/<n>-<slug>`, from `start`); args.testing
// overrides them.
const AREA = String(A.branch).split('/')[0]
const TESTING = {
  core: 'Unit tests in tests/unit/ mirroring core/, each rule driven by commands through a seeded Match and asserted on the events and on view_of; a part\'s unit test never loads content/ or levels/ (ARCHITECTURE §9.6).',
  net: 'GdUnit4 tests under tests/unit/net/ (and tests/unit/server/ for the host session) over the loopback transport (net/transport/loopback_hub.gd), asserting what each peer receives; the ENet runs (tests/integration/net/, on CI) still pass, and a new ENet scenario joins them when the issue asks for one.',
  tooling: `Runner tests in tools/runner/tests/ for every new command, rule or behaviour change (CI runs them all in \`selftest\`, about 10 minutes even without the Godot ones; while you work run only the modules you change: \`cd ${WTB}/tools && "$PYTHON_BIN" -m unittest runner.tests.<module>\`).`,
}
TESTING.server = TESTING.net
const TESTS = A.testing || `${TESTING[AREA] || 'Tests under tests/unit/ or tests/integration/ mirroring the folders you change.'} Where you fix a guard, see its test fail without the code first.`
// #339 (the instruction-diet ADR's N1 (a)): docs are read by section, never whole. READING names no area CLAUDE.md
// file and no .claude/rules/: they load by path when the agent Reads a file there, which it does before every Edit.
// Root CLAUDE.md is loaded at launch, so no prompt asks to read it. The reviewers read the ARCHITECTURE sections the
// change touches (a design's: the outline, then every section it could contradict), and the netcode reviewers always
// read §5, §4.2 and §4.6 (NETCODE_SECTIONS; the second_review pass too, which audits the leak test).
const SECTION = `\`cd ${WTB} && tools/run.sh section docs/ARCHITECTURE.md\` prints its outline (§, title, line range, tokens) and \`tools/run.sh section docs/ARCHITECTURE.md 4.5 9.3\` exactly those sections, subsections included; AGENT_WORKFLOW and the ADRs alike`
const arch = what => DESIGN
  ? `ARCHITECTURE by section: its outline first, then every section ${what} could contradict, not only the ones it edits (${SECTION}; read-only, so you may run it)`
  : `the ARCHITECTURE sections ${what} touches, by section, never the whole doc (${SECTION}; read-only, so you may run it)`
// The same sentence as in pr-rebase.js (test_workflows.py compares the two): a change that touches only §4.7 or §7.1
// can still add a snapshot field the leak test does not compare.
const NETCODE_SECTIONS = `Always read ARCHITECTURE §5 (per-peer filtering), §4.2 (each event's audience) and §4.6 (the client, the bots and the leak test), whatever the change touches: \`cd ${WTB} && tools/run.sh section docs/ARCHITECTURE.md 5 4.2 4.6\` (read-only; you may run it). A change to §4.7 or §7.1 alone can still add a snapshot field the leak test does not compare.`
const READING = A.reading || `the docs, ADRs and handoff comments the issue links (\`gh issue view <n> --comments\` for each handoff it builds on); the ARCHITECTURE sections it names, by section, never the whole doc (${SECTION}); the code it builds on and its tests`

const WORK = DESIGN
  ? [
    'This is a DESIGN task: documents only (docs/ARCHITECTURE.md, a new ADR in docs/decisions/, area CLAUDE.md files, as the issue asks). No code in core/, server/, net/, client/ or voice/. Tables where they fit; each choice names the failure it prevents; rejected alternatives go in the ADR. Verify each Godot API you name against tools/out/godot-api/4.7.2/extension_api.json. Decide nothing reserved for the engineer: each such choice is options with a recommendation, marked "Needs the engineer", and the design proceeds with the recommendation where it can be reverted.',
    'If the issue asks for a split into later issues, return it in proposed_issues (each: title, goal, acceptance criteria, depends on, files); do not open issues.',
  ].join('\n\n')
  : `Plan, then implement every acceptance criterion. ${TESTS} If a file you need comes from a PR that is not merged yet (the notes say so), build and test with fixtures first, and before you finish \`git fetch\` and check whether it reached origin/${BASE}; if it did, rebase on it inside your worktree and use it.`

// The compact result's helpers come before the agents: the reviewers' digest (#470) uses them too.
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

// #470: the reviewers and the test reviewer get a digest of the implementer's report, not the whole of it (6.9k
// characters at the median of 26 reviewers since 2026-10-05, 7.9k to 9.3k a run in the token audit of 2026-10-06):
// its summary, whether it is complete and what it left on purpose (else a reviewer reports each deferred acceptance
// criterion as a blocker), the changed paths, the content it marked provisional, and each decision and item for the
// engineer cut to a line. They review the diff; the publisher still gets the whole report (the PR and the handoff
// carry its rationale, what is left, the verify tail).
const clip = (s, max) => {
  const t = s === undefined || s === null ? '' : String(s).trim()
  return t.length > max ? `${t.slice(0, max - 1).trimEnd()}…` : t
}
const digest = r => ({
  summary: clip(r.summary, SUMMARY_MAX),
  complete: r.complete,
  changed_paths: r.changed_paths || [],
  ...(items(r.provisional_content).length ? { provisional_content: items(r.provisional_content) } : {}),
  ...(items(r.decisions).length ? { decisions: lines(items(r.decisions)) } : {}),
  ...(items(r.needs_engineer).length ? { needs_engineer: lines(items(r.needs_engineer)) } : {}),
  ...(items(r.left).length ? { left: lines(items(r.left)) } : {}),
})
const REPORT = 'The implementer\'s report, as a digest (its summary, whether it is complete and what it left, the changed paths, the content it marked provisional, and each decision and item for the engineer cut to a line; the diff is the change):'

// #469: a plan over PLAN_MAX characters of JSON is cut before the critique and the implementer read it (the whole plan
// is the agent's comment on the issue): the summary to its cap, each list item and each file_map fact to a line, then
// the last item of the longest plan list, and only then file_map entries (a dropped one's file is read as usual),
// until it fits.
const size = o => JSON.stringify(o).length
const capPlan = p => {
  if (size(p) <= PLAN_MAX) return p
  const out = { ...p, summary: clip(p.summary, PLAN_SUMMARY_MAX) }
  for (const k of PLAN_LISTS) if (Array.isArray(out[k])) out[k] = lines(out[k], 240)
  const map = p.file_map && Array.isArray(p.file_map.files) ? p.file_map : null
  if (map) out.file_map = { ...map, files: map.files.map(f => ({ ...f, facts: lines(f && f.facts, 240) })) }
  out.clipped = `cut from ${size(p)} characters of JSON; the whole plan: ${p.comment_url || 'the plan agent\'s comment on the issue'}`
  // The plan's lists go first (the comment has them whole); file_map entries only when no list is left, since a
  // dropped entry is a file the implementer reads again.
  for (;;) {
    const lists = PLAN_LISTS.map(k => out[k]).filter(a => Array.isArray(a) && a.length)
    if (!lists.length && map && out.file_map.files.length) lists.push(out.file_map.files)
    if (size(out) <= PLAN_MAX || !lists.length) return out
    lists.reduce((a, b) => (size(b) > size(a) ? b : a)).pop()
  }
}
// #469: the implementer trusts the file map for each file unchanged since its base_sha (a rebase, or an earlier
// attempt's commit, since the plan can change a file the map describes): one `git diff --name-only` tells which.
const mapRule = m => {
  const sha = m && typeof m.base_sha === 'string' && /^[0-9a-f]{7,40}$/i.test(m.base_sha.trim()) ? m.base_sha.trim() : null
  const paths = m && Array.isArray(m.files) ? m.files.filter(f => f && typeof f.path === 'string' && f.path).map(f => f.path) : []
  if (!sha || !paths.length) return '\n\nThe plan has no usable file map (file_map): read the files as usual.'
  return `\n\nThe file map (file_map): the plan agent read these files at ${sha}. Trust it while a file is unchanged since that sha: first run in the Bash tool \`cd ${WTB} && git diff --name-only ${sha} -- ${paths.map(p => `'${p.replace(/'/g, `'\\''`)}'`).join(' ')}\` once (again after a rebase). For each path it does not list, take the map's line ranges and facts instead of reading the file again for them: read only what the map lacks, and before an Edit only the range you change (the Edit tool needs a Read of the file first). A path it lists changed since the plan: read it as usual. A file whose facts the critique disputes: read it as usual too. If the command fails (the sha unknown), the map does not hold: read every file as usual.`
}

// #606: the review tier, by the change's risk. The diff-path rule is quick-task.js's (#608; test_workflows.py compares
// the copies): a mistake under these paths can become a cheat, a desync or a hidden-information leak. client/ui/ (the
// screens) is carved out: the engineer's answer 2b on #302 (comment 6085059719); the rest of client/ stays reviewed.
const REVIEWED = /^(?:(?:core|server|net|voice|tests\/harness)\/|client\/(?!ui\/))/
// Before the implementer no diff exists, so plan_review follows the branch's area (`start`'s <area>/ prefix, from the
// issue's area label): only these areas are light; any other, a design task or a forced full tier plans.
const LIGHT_AREAS = ['content', 'level', 'tooling']
const PLAN_SKIPPED = PLAN_REVIEW && !DESIGN && !FORCED_FULL && LIGHT_AREAS.includes(AREA)
if (PLAN_SKIPPED) log(`#${N}: plan_review skipped: the branch's area ${AREA} is the light review tier (#606)`)
// The tier of the implementer's changed paths, the worst one winning: [tier, why]. A path no rule lists is light (the
// manager's notes for #606; the ADR amendment says why and that the engineer may turn it around).
const tierOf = paths => {
  if (FORCED_FULL) return ['full', 'forced by the launch (tier: full)']
  if (DESIGN) return ['full', 'a design task']
  if (!paths.length) return ['full', 'no changed paths returned']
  const hit = paths.filter(p => REVIEWED.test(p))
  return hit.length
    ? ['full', `the diff touches ${hit.slice(0, 3).join(', ')}${hit.length > 3 ? ', ...' : ''}`]
    : ['light', 'no path under core/ server/ net/ voice/ tests/harness/ or client/ outside client/ui/']
}

phase('Implement')
// plan_review: a plan agent, then a fresh critique of its plan; the implementer builds with both.
let planned = null
if (PLAN_REVIEW && !PLAN_SKIPPED) {
  const plan = await agent([
    RULES,
    `Task: plan GitHub issue #${N} (${A.title}) before it is built (plan_review). Effort: ${PLAN_EFFORT}. Budget: at most about 80 tool calls. Plan only: create, edit or commit nothing (no plan file in the repo: the plan is one comment on the issue and your structured result) and run no verify. A fresh reviewer critiques your plan next, then an implementer builds from both.`,
    `An earlier attempt may have got part of the way: run \`git log --oneline origin/${BASE}..HEAD\` and \`git status\` in the worktree, and plan from that state.`,
    `Read: \`gh issue view ${N} --comments\`; ${READING}.`,
    `Task notes from the manager:\n${A.notes}`,
    A.coord ? `Parallel work:\n${A.coord}` : '',
    DESIGN ? 'This is a DESIGN task (documents only): plan the documents, their sections, the options each choice needs and the proposed issue split if the issue asks for one.' : `The tests the task needs: ${TESTS}`,
    'The plan: how the change meets each acceptance criterion (criteria); each file to create or change and what changes in it (files); the classes, functions, signals, wire rows and args it adds or changes (interfaces); each test, what it asserts and which one fails first (tests); the docs and ARCHITECTURE rows to update (docs); what could go wrong and what the change must not break (risks); open questions, each with the recommended answer (questions); the commits in order (steps).',
    `The whole plan goes in ONE comment on the issue; the structured result is its short form (#469: plan results of 23 to 28 KB did not parse and were sent again). Write the full plan (each file's change in detail, each test's assertions, the reasoning) to ${SCRATCH}/plan.md in your scratchpad, its first line \`Plan of #${N} (issue-task plan_review, branch ${A.branch})\`, and post it with \`gh issue comment ${N} --body-file <that file>\`. An earlier attempt may have posted one: first list your own comments on the issue in the Bash tool (\`gh api user --jq .login\` gives your login) with \`gh issue view ${N} --json comments --jq '.comments[] | select(.author.login == "<your login>") | .url + " " + (.body | split("\\n") | .[0])'\`. If the last of them starts with that first line, replace it with \`gh issue comment ${N} --edit-last --body-file <that file>\` (it edits your last comment on the issue) and return its URL; if only an earlier one does, post a new comment whose second line is \`Supersedes <that comment's URL>\`. Never \`gh api -X PATCH\` (it asks, and nobody answers). Return its URL in comment_url. The structured result is at most about ${PLAN_MAX} characters of JSON in all: summary at most ${PLAN_SUMMARY_MAX} characters, each list item one line, and the details stay in the comment.`,
    'file_map: what the implementer may trust instead of reading the files again (it re-read most of what planners had read). base_sha: `git rev-parse HEAD` in the worktree, the commit whose files you read. files: one entry per file the plan rests on, with its path (relative to the worktree), the line ranges that matter (lines, e.g. "120-180, 300-340") and the facts read there that the build needs (signatures, field and signal names, call sites, the test helpers to use), each fact one line. Only what you read in that file; a fact you inferred is not in the map.',
    'Return the structured result.',
  ].filter(Boolean).join('\n\n'), withModel({ label: `plan:#${N}`, phase: 'Implement', effort: PLAN_EFFORT, schema: PLAN_SCHEMA }, 'plan'))
  if (!plan) throw new Error(`#${N}: the plan agent returned nothing; resume this run with the same args`)
  const short = capPlan(plan)
  if (short !== plan) log(`#${N}: the plan's result was ${size(plan)} characters of JSON; cut to ${size(short)} for the critique and the implementer`)
  const critique = await agent([
    `Issue #${N} (${A.title}). Branch ${A.branch} in the worktree ${WT}; its PR base is origin/${BASE}. D:/prime-game is main: read the branch's files under ${WT}.`,
    READ_RULE,
    `Critique read-only a PLAN written before anything was built (plan_review); an implementer builds from it next, with your critique. Read the issue and its comments (\`gh issue view ${N} --comments\`), the ADRs and handoffs it links, the area CLAUDE.md files, the code the plan names and ${arch('the plan')}. Budget: at most about 40 tool calls. Edit nothing.`,
    A.coord ? `Context: other issues are built in parallel on other branches; a missing piece that another issue owns is not a finding. ${A.coord}` : '',
    `The plan, in short (the whole plan is the plan agent's comment on the issue, comment_url; its file_map holds the facts the implementer will trust without reading the files again): ${JSON.stringify(short)}`,
    'Find what would make the built change wrong or need rework: a file_map fact that the file at base_sha does not bear out (the implementer trusts it); an acceptance criterion missed or misread; an invariant broken (host authority, per-peer filtering, pure core/, mechanics as data); information reaching a peer that is not entitled to it (events, snapshots, view_of, what a client renders); an interface that clashes with the code on the base or with the parallel work; tests that would pass whatever the code does, or no test that fails first; a doc, ARCHITECTURE row or ADR the change needs; a choice reserved for the engineer that the plan makes. Report findings with severity (blocker, major, minor, nit), the file or plan item, the problem and a concrete change to the plan. Blocker or major: building the plan as written would be wrong or need rework. No findings is a valid answer.',
  ].filter(Boolean).join('\n\n'), asReviewer({ label: `review:plan:#${N}`, phase: 'Implement', agentType: 'code-reviewer', schema: REVIEW }, 'plan_review'))
  if (!critique) throw new Error(`#${N}: the plan's reviewer returned nothing; resume this run with the same args`)
  planned = { plan: short, critique }
  log(`#${N}: planned; the critique found ${(critique.findings || []).length} finding(s)`)
}

// checkpoint (#559): the context at which an implementer hands over, read from the harness's `<total_tokens>` reminder
// (its budget, 15,000,000 on 2026-10-08, less N is the context of the call before it), the tool-call backstop where
// no reminder shows, and the most handoffs per task. Implementer k (0 first) is labelled implement:#N, then
// implement:#N#2 and #3 (metrics.role_of reads both as the implementer; never :2). Off, implement(0, null) is today's
// agent call byte for byte; on, only the rule paragraph and the schema's handoff key are added to it.
const HANDOFF_AT = 150000
const HANDOFF_BUDGET = 15000000
const HANDOFF_CALLS = 60
const HANDOFF_MAX = 2
const thousands = x => String(x).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
const HANDOFF_SCHEMA = { ...IMPL_SCHEMA, properties: { ...IMPL_SCHEMA.properties, handoff: { type: 'string' } } }
const handoffRule = k => `Checkpoint (checkpoint, #559): keep your context under ${thousands(HANDOFF_AT)} tokens. After each tool result a system reminder \`<total_tokens>N tokens left</total_tokens>\` shows N. Your context is B minus N, exactly, where B is the budget, ${thousands(HANDOFF_BUDGET)} on these runs (your first reading is B less your first call's context, so it lies within 100,000 below B; if your first reading does not, take B = your first N plus 30,000). Once N is at or below B minus ${thousands(HANDOFF_AT)} (at or below ${thousands(HANDOFF_BUDGET - HANDOFF_AT)} with that B), or after ${HANDOFF_CALLS} tool calls if you see no such reminder, hand over: finish the step in hand; leave no background job (verify, mutants) running: wait for it and keep its log path and result; commit (a WIP commit is fine); start nothing new; write a note to ${SCRATCH}/handoff-${k + 1}.md in your scratchpad with done (each commit, a line), left (the acceptance criteria not met yet, then the next step), decisions (each with its why, and how each critique finding was settled), gotchas (what cost you time, what to avoid) and verify state (the last verify's result and log path, and whether the tree changed since). Then return the structured result with complete false, verify_green and verify_tail as they stand, and handoff: the note's absolute path${VISUAL ? ', and playcheck {available: false, pngs: [], notes: "handed over"} (only the implementer that finishes runs playcheck)' : ''}. If only the final verify and the return are left, finish instead. A fresh implementer of the same kind continues from your note and the worktree (at most ${HANDOFF_MAX} handoffs per task).`
const continuation = (k, note) => `Continuation ${k} of ${HANDOFF_MAX} (checkpoint, #559): an earlier implementer of this task reached its context limit and handed over. Its note is ${note}: read it first, then \`git log --oneline origin/${BASE}..HEAD\` and \`git status\` in the worktree, and continue from them; do not redo or re-read what the note lists as done. A missing or unreadable note: say so under left and continue from git. Your result covers the whole branch since origin/${BASE}, not only your part: summary, changed_paths, complete, left and the verify state (the note and git log say what came before); decisions, needs_engineer, proposed_issues, provisional_content and commits only your own (the script keeps the earlier ones).${k === HANDOFF_MAX ? ' You are the last one: do not hand over; if the budget runs out, stop at a green, committed state and list what is left.' : ''}`
const implement = (k, note) => agent([
  RULES,
  `Task: GitHub issue #${N} (${A.title}). Effort: ${IMPL_EFFORT}. Budget: at most about 250 tool calls; if it runs out, stop at a green, committed state and list what is left.`,
  k ? continuation(k, note) : '',
  `An earlier attempt may have got part of the way (a resumed run): first run \`git log --oneline origin/${BASE}..HEAD\` and \`git status\` in the worktree, and continue from that state; uncommitted files there are that attempt's work.`,
  `Read: \`gh issue view ${N} --comments\`; ${READING}.`,
  `Task notes from the manager:\n${A.notes}`,
  A.coord ? `Parallel work:\n${A.coord}` : '',
  WORK,
  planned ? `Plan review (plan_review): a plan agent planned this task and a fresh reviewer critiqued the plan; neither changed the worktree. Build from the plan, changed where the critique is right: settle each blocker and major point before you build, and say in decisions how you settled each critique finding, or why it is wrong.\n\nThe plan, in short (the whole plan is the plan agent's comment on the issue, comment_url, which \`gh issue view ${N} --comments\` shows): ${JSON.stringify(planned.plan)}\n\nThe critique: ${JSON.stringify(planned.critique)}${mapRule(planned.plan.file_map)}` : '',
  'Update docs/ARCHITECTURE.md (the rows and "Built in"/"Tests" lines your work completes, and anything it makes stale) and other durable docs in the same branch. Commit as you go.',
  '`tools\\run.cmd verify` in the worktree until green: the fast verify (#605: doctor, lint and check, a minute or two). Every test runs on GitHub CI once the publisher pushes, so never run `verify --full` or the whole `test` suite here; while you build and debug, run the tests your change touches by path (`tools\\run.cmd test <path>`).',
  BOUNDED ? waits(false, true) : '',
  VISUAL ? `Visual check (visual): once verify is green, run \`tools\\run.cmd playcheck <scenario>\` in the worktree for each of ${SCENES}, one call per scenario (off-screen windows like \`shot\`; the PNGs land under tools/out/playcheck/<scenario>/). Read each PNG (Read shows images) and fix what is wrong before you finish. Return in playcheck the scenarios, the exit codes and each PNG's absolute path. If the command is missing on this branch (P9, #186, not merged into its base yet), return playcheck.available false with that in notes: the run goes on without screenshots.` : '',
  CHECKPOINT && k < HANDOFF_MAX ? handoffRule(k) : '',
  'Do NOT publish, push, open a PR or comment on GitHub: fresh reviewers check the branch next.',
  `Return the structured result. changed_paths: \`git diff --name-only origin/${BASE}...HEAD\`. verify_tail: the lines from "verify summary" to the end. summary: at most ${SUMMARY_MAX} characters, a few lines on what changed and why (the reviewers and the PR read it); the why of each choice goes in decisions, one line each, and the commits and the diff carry the rest.`,
].filter(Boolean).join('\n\n'), withModel({ label: k ? `implement:#${N}#${k + 1}` : `implement:#${N}`, phase: 'Implement', effort: IMPL_EFFORT, schema: CHECKPOINT && k < HANDOFF_MAX ? HANDOFF_SCHEMA : IMPL_SCHEMA }, 'implement'))
// A handoff's own verify_green is never read: the last implementer's result is the one the run goes on with (a red
// one stops below), with the earlier ones' lists joined, since each continuation returns only its own.
const HANDOFF_LISTS = ['decisions', 'needs_engineer', 'proposed_issues', 'provisional_content', 'commits']
const noteOf = r => (CHECKPOINT && r && typeof r.handoff === 'string' && r.handoff.trim() ? r.handoff.trim() : '')
const handedOver = []
let impl = await implement(0, null)
while (noteOf(impl) && handedOver.length < HANDOFF_MAX) {
  handedOver.push(impl)
  log(`#${N}: handoff ${handedOver.length} of ${HANDOFF_MAX}: the implementer stopped at its context limit (verify ${impl.verify_green ? 'green' : 'red'}); a fresh one continues from ${noteOf(impl)}`)
  impl = await implement(handedOver.length, noteOf(impl))
}
if (noteOf(impl)) log(`#${N}: handoff ignored: the last implementer may not hand over (at most ${HANDOFF_MAX}); its result stands`)
if (impl && handedOver.length) {
  const { handoff, ...last } = impl
  const all = [...handedOver, impl]
  impl = { ...last, handoffs: handedOver.map(noteOf) }
  for (const key of HANDOFF_LISTS) {
    const joined = [...new Set(all.flatMap(r => items(r[key])))]
    if (joined.length) impl[key] = joined
  }
}

if (!impl) throw new Error(`#${N}: the implementer returned nothing (died or was skipped); resume this run with the same args`)
log(`#${N}: implemented, verify ${impl.verify_green ? 'green' : 'RED'}, ${(impl.changed_paths || []).length} paths`)
const [TIER, TIER_WHY] = tierOf(impl.changed_paths || [])
const LIGHT = TIER === 'light'
// The agents the launch passed that this run's tier dropped (#606). Light removes the skeptic and plan_review; on a
// client/ui/ diff it removes the netcode review (the `!LIGHT` guard below) and test_review too, which every other
// light diff never routed (no netcode path, no production code). test_review and second_review are listed so the
// result says why.
const TIER_SKIPPED = [
  PLAN_SKIPPED && 'plan_review', LIGHT && TEST_REVIEW && 'test_review', LIGHT && SECOND_REVIEW && 'second_review',
  LIGHT && SKEPTICS > 0 && 'skeptic',
].filter(Boolean)
log(`#${N}: review tier ${TIER} (${TIER_WHY})${TIER_SKIPPED.length ? `; skipped: ${TIER_SKIPPED.join(', ')}` : ''}${PLAN_SKIPPED && !LIGHT ? '; the plan was skipped by the branch\'s area, but the diff is full: the full review runs' : ''}`)
const SKEPTIC_LIMIT = LIGHT ? 0 : SKEPTICS
// visual: what the implementer's playcheck run gave; a missing command or a missing report is reported, not fatal.
const shots = VISUAL ? (impl.playcheck || { available: false, pngs: [], notes: 'the implementer reported no playcheck run' }) : null

let reviews = []
let labels = []
let testReview = null
let testReviewSkipped = ''
let skeptic = null
let judge = null
let judging = null
// The blocker and major findings still open before the publisher (publish_clean): a skeptic's refutation closes one.
let openSerious = 0
if (impl.verify_green) {
  // Only a green implementer is reviewed; a red one stops below.
  phase('Review')
  const paths = impl.changed_paths || []
  // tests/harness/ holds the information-leak test: #115 touched only tests/ and tools/, and a netcode review run by
  // hand found a major there. client/ renders public data, and a rendering leak is an information leak (#158: the M4
  // manager ran this review by hand on #154 twice, and both runs found real problems).
  // The light tier (#606) has no netcode review: only a client/ui/ diff gets here with a client path.
  const netcode = !LIGHT && (DESIGN || !paths.length || paths.some(p => /^(core|server|net|client|tests\/harness)\//.test(p)))
  const godot = paths.some(p => /\.(gd|tscn|tres)$/.test(p)) || (!DESIGN && !paths.length)
  const base = [
    `Issue #${N} (${A.title}). Branch ${A.branch} in the worktree ${WT}; its PR base is origin/${BASE}. D:/prime-game is main: read the branch's files under ${WT}.`,
    READ_RULE,
    `Review read-only${DESIGN ? ', adversarially, a DESIGN (documents only)' : ''}: \`git -C ${WTB} diff origin/${BASE}...HEAD\` and the files in ${WT}, against the issue and its comments (\`gh issue view ${N} --comments\`), the ADRs the issue links, the area CLAUDE.md files and ${arch(DESIGN ? 'the design' : 'the change')}. Budget: at most about 60 tool calls. ${DESIGN ? 'Edit nothing.' : 'You may run `tools\\run.cmd test <path>` in the worktree to confirm a finding; do not edit anything.'}`,
    A.coord ? `Context: other issues are built in parallel on other branches; a missing piece that another issue owns is not a finding. ${A.coord}` : '',
    `${REPORT} ${JSON.stringify(digest(impl))}`,
    `Report findings with severity (blocker, major, minor, nit), file, line, the problem and a concrete fix. ${DESIGN ? 'A design that would let information reach a peer that is not entitled to it, trust a client field, leave an intent unvalidated, or contradict an accepted ADR or the code on main is a blocker or major.' : 'Blocker: wrong behaviour against an acceptance criterion or an invariant, a leak, a broken test.'} No findings is a valid answer.`,
  ].filter(Boolean).join('\n\n')
  const codeFocus = DESIGN
    ? '\n\nFocus: consistency with the code on main (real payloads, public APIs, tables), with the accepted ADRs and with ARCHITECTURE elsewhere; Godot 4.7.2 APIs named exist (tools/out/godot-api/4.7.2/extension_api.json); a proposed issue split is complete and ordered; every engineer decision is marked as such.'
    : ''
  const visualFocus = !VISUAL ? ''
    : shots.available && (shots.pngs || []).length
      ? `\n\nVisual check (visual): the implementer's \`tools\\run.cmd playcheck\` screenshots: ${shots.pngs.join(', ')}. Read each PNG (Read shows images) and compare it with what the issue asks for: the wrong camera or player, a HUD or menu that is missing, misplaced or shows another player's state, text cut off or overlapping. Each such problem is a finding, with the PNG's path as its file.`
      : `\n\nVisual check (visual): no playcheck screenshots (${shots.notes || 'none returned'}). That is not a finding of yours: the publisher reports it.`
  labels = ['code-reviewer']
  const thunks = [() => agent(base + codeFocus + visualFocus, asReviewer({ label: `review:code:#${N}`, phase: 'Review', agentType: 'code-reviewer', schema: REVIEW }, 'code'))]
  // ab_review (#535): the control, the same prompt on the review model, second in the list (the judge reads 0 and 1).
  if (AB_REVIEW) {
    labels.push('code-reviewer (control)')
    thunks.push(() => agent(base + codeFocus + visualFocus, asReviewer({ label: `review:code-control:#${N}`, phase: 'Review', agentType: 'code-reviewer', schema: REVIEW }, 'review')))
  }
  if (netcode) {
    labels.push('netcode-security-reviewer')
    thunks.push(() => agent(base + '\n\nFocus: information leaks through events, audiences, snapshots, view_of, recorded recipients and rejection reasons (the ARCHITECTURE §5 invariants); intents the rules do not validate; host-trust assumptions; floods and rate limits; determinism and replay. ' + NETCODE_SECTIONS, asReviewer({ label: `review:netcode:#${N}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }, 'netcode')))
  }
  if (godot) {
    labels.push('godot-api-checker')
    thunks.push(() => agent(base, asReviewer({ label: `review:godot-api:#${N}`, phase: 'Review', agentType: 'godot-api-checker', schema: REVIEW }, 'godot')))
  }
  // second_review: a second netcode review where leaks matter, with another lens (and, per launch, another model).
  if (netcode && SECOND_REVIEW && !LIGHT) {
    labels.push('second netcode-security-reviewer')
    thunks.push(() => agent(base + '\n\nFocus: you are a second, independent netcode review (second_review); another reviewer covers events, audiences, snapshots, view_of and rejection reasons. Take the attacker\'s side instead: (1) a modified client: for each intent, field and message the change adds or reads, what a client could send that the host accepts (out-of-range or non-finite values, the wrong phase, another peer\'s ids, replays, floods past the budgets); (2) a curious player: follow each new or changed piece of state from core/ to every peer\'s wire, logs, audio and screen, the host\'s own client included (it gets the same filtered view), and the debug-only paths in a release build; (3) the tests: would the information-leak test (tests/harness/) or a unit test fail if this change leaked or trusted the client? A gap there is a finding. ' + NETCODE_SECTIONS, asReviewer({ label: `review:netcode-second:#${N}`, phase: 'Review', agentType: 'netcode-security-reviewer', schema: REVIEW }, 'second_review')))
  }
  const results = await parallel(thunks)
  // Every routed reviewer must answer: a dropped netcode review on a core/ change is not a clean review. A resume
  // replays the reviewers that did answer, so throwing costs nothing.
  const missing = labels.filter((l, i) => !results[i])
  if (missing.length) throw new Error(`#${N}: reviewer(s) ${missing.join(', ')} returned nothing; resume this run with the same args`)
  reviews = results
  log(`#${N}: ${reviews.length} reviews, ${reviews.reduce((s, r) => s + (r.findings || []).length, 0)} findings`)

  // ab_review (#535): a blind judge of both code reviews. It changes nothing in the run: the publisher never sees it, so
  // it runs beside the rest of the review and the publisher and is awaited only before the result is written.
  if (AB_REVIEW) {
    const [trial, control] = [reviews[0].findings || [], reviews[1].findings || []]
    if (!trial.length && !control.length) {
      judge = { skipped: 'neither code reviewer found anything' }
    } else {
      judging = agent([
        `Issue #${N} (${A.title}). Branch ${A.branch} in the worktree ${WT}; its PR base is origin/${BASE}. D:/prime-game is main: read the branch's files under ${WT}.`,
        READ_RULE,
        'A read-only judge of two independent code reviews of the same diff. Budget: at most about 40 tool calls. Edit nothing; you may run `tools\\run.cmd test <path>` in the worktree.',
        `Read \`git -C ${WTB} diff origin/${BASE}...HEAD\`, the issue and its comments (\`gh issue view ${N} --comments\`), and the code, tests and docs each finding names.`,
        `Reviewer 1 found: ${JSON.stringify(trial)}`,
        `Reviewer 2 found: ${JSON.stringify(control)}`,
        'Both reviewers had the same prompt; judge each finding on its own, whoever raised it. valid: the defect or gap is real in this diff and the change should fix it (an acceptance criterion missed, an invariant broken, a wrong behaviour, a missing or weak test, a doc the change makes stale). invalid: the code already handles it, it misreads the code or the issue, it contradicts an accepted ADR or the engineer\'s answers, or it asks for something outside the issue. unsure: you cannot settle it within the budget. Give each the severity you would give it on the reviewers\' scale (blocker: wrong behaviour against an acceptance criterion or an invariant, a leak, a broken test; major: building on it as written would need rework; minor; nit), whatever the reviewer said.',
        'Then match the two lists: a finding of reviewer 1 and one of reviewer 2 match when they name the same defect (the same root cause), whatever their wording, line or severity; a finding matches at most one of the other list.',
        'Return verdicts, one per finding of both lists (reviewer 1 or 2, its 0-based index in that reviewer\'s list, the verdict, your severity and a one-line reason), and matches, the pairs {first: an index in reviewer 1\'s list, second: an index in reviewer 2\'s}.',
      ].join('\n\n'), asReviewer({ label: `ab-judge:#${N}`, phase: 'Review', agentType: 'code-reviewer', schema: AB_JUDGE_SCHEMA }, 'review'))
    }
  }

  // test_review: planted faults the branch's tests must catch, each in a scratch worktree (never the task's tree).
  // The mutants go only into production code: a diff with none of it (tooling, content, docs) gets no test review.
  // The light tier (#606) has no test review either: a light diff with production code has it only under client/ui/.
  if (TEST_REVIEW && paths.length && !paths.some(p => /^(core|server|net|client|voice)\//.test(p))) {
    testReviewSkipped = 'no changed path is production code (core/, server/, net/, client/, voice/)'
    log(`#${N}: test_review skipped: ${testReviewSkipped}`)
  } else if (TEST_REVIEW && LIGHT) {
    testReviewSkipped = "the light review tier (#606): the diff's only production code is under client/ui/"
    log(`#${N}: test_review skipped: ${testReviewSkipped}`)
  } else if (TEST_REVIEW) {
    testReview = await agent([
      RULES,
      `Task: the test review of issue #${N} (${A.title}) (test_review): show whether the branch's tests fail when its production code is wrong. Effort: ${TEST_EFFORT}. Budget: at most about 60 tool calls. Edit, commit or revert nothing in the worktree: \`tools\\run.cmd mutants\` plants each fault in its own scratch worktree under tools/out/mutants/, never in yours.`,
      [
        'Steps:',
        '1. `tools\\run.cmd mutants --help` in the worktree. If the command does not exist on this branch (P7, #184, not merged into its base yet), return at once: available false, exit_2 false, no findings, the reason in notes. The run goes on without a test review.',
        `2. Read \`git -C ${WTB} diff origin/${BASE}...HEAD\` and the reviews below. Pick 3 to 5 mutants on lines the diff adds or changes in production code (core/, server/, net/, client/, voice/; never tests/, tools/, docs/, content/ or levels/): each a small fault a real bug could make (a flipped condition, an off-by-one, a dropped check or filter, a wrong recipient, a skipped event), with the test paths that should catch it. No production code in the diff: return available true, no mutants, the reason in notes.`,
        `3. Write each spec (its format: \`tools\\run.cmd mutants --help\`) under ${SCRATCH}/ of your scratchpad. The rules \`mutants\` enforces: a mutant may not touch a \`class_name\` or \`extends\` line (the scratch tree is imported once, before the mutants), and its \`original\` must start exactly once on its 1-based \`line\`. ${MUTANTS_RUN} Each test run (the baseline's and the mutant's) times out after \`--seconds\` (default 300), and a timeout makes the mutant error. Exit 0: the run completed, whatever the results; 1: an invalid spec or a run that could not start or finish (a dirty worktree, another mutants run in the same checkout, a failed import, a crash): fix the spec, else report the FAIL lines in notes; 2: its scratch worktree could not be removed, or the task's \`git status\` changed during the run: run no more mutants, set exit_2 true and put what \`git worktree list\` and \`git status\` show in notes.`,
        '4. Each survived mutant is a finding: major when the fault breaks an acceptance criterion or an invariant (a leak, an unvalidated intent, a wrong rule) and no test caught it, else minor; the file and line of the mutant, the problem, and as the fix the test that would kill it. A mutant that changes no behaviour is equivalent, not a finding. At the end confirm that `git status` in the worktree is unchanged.',
      ].join('\n'),
      ...(BOUNDED ? [waits(false)] : []),
      `${REPORT} ${JSON.stringify(digest(impl))}`,
      `Fresh reviewers found: ${JSON.stringify(reviews)}`,
      'Return the structured result: every mutant you ran in mutants, each with its result (killed, survived, error or equivalent) and exit code. A mutant that a stopped run lists as `not run` is reported as error, with why in notes.',
    ].join('\n\n'), withModel({ label: `test-review:#${N}`, phase: 'Review', effort: TEST_EFFORT, schema: TEST_REVIEW_SCHEMA }, 'test_review'))
    if (!testReview) throw new Error(`#${N}: the test reviewer returned nothing; resume this run with the same args`)
    log(`#${N}: test review ${testReview.available ? `${(testReview.mutants || []).length} mutants, ${(testReview.findings || []).length} findings` : 'not run: `mutants` is missing on the branch'}${testReview.exit_2 ? '; mutants EXITED 2' : ''}`)
  }

  // The blocker and major findings: the reviews' in their order, then the test review's.
  const serious = []
  reviews.forEach((r, i) => (r.findings || []).forEach(f => { if (SERIOUS.test(f.severity)) serious.push({ from: labels[i], finding: f }) }))
  if (testReview) (testReview.findings || []).forEach(f => { if (SERIOUS.test(f.severity)) serious.push({ from: 'test review', finding: f }) })
  // skeptic: one read-only agent per blocker or major finding tries to refute it before the publisher fixes it.
  if (SKEPTIC_LIMIT) {
    const checked = serious.slice(0, SKEPTIC_LIMIT)
    skeptic = { refuted: [], stood: [], unchecked: serious.slice(SKEPTIC_LIMIT) }
    if (skeptic.unchecked.length) log(`#${N}: ${skeptic.unchecked.length} blocker or major finding(s) over the skeptic limit of ${SKEPTIC_LIMIT} go to the publisher unchecked`)
    if (checked.length) {
      const verdicts = await parallel(checked.map(s => () => agent([
        `Issue #${N} (${A.title}). Branch ${A.branch} in the worktree ${WT}; its PR base is origin/${BASE}. D:/prime-game is main: read the branch's files under ${WT}.`,
        READ_RULE,
        'A skeptic\'s read-only check of ONE review finding (skeptic), before the publisher fixes it. Budget: at most about 30 tool calls. Edit nothing; you may run `tools\\run.cmd test <path>` in the worktree.',
        `The finding, from the ${s.from}: ${JSON.stringify(s.finding)}`,
        `Try to refute it: read the code, the tests and the docs it names, the issue and its comments (\`gh issue view ${N} --comments\`), and decide whether it is wrong: the code already handles it, it misreads the code or the issue, it contradicts an accepted ADR or the engineer's answers, or the fault cannot happen. refuted true only with evidence (file:line, or a command and its output); uncertain, or right in part: refuted false. A finding about an acceptance criterion, an invariant or a leak is refuted only when the code is shown to meet it.`,
      ].join('\n\n'), asReviewer({ label: `skeptic:#${N}`, phase: 'Review', agentType: 'code-reviewer', schema: SKEPTIC_SCHEMA }, 'skeptic'))))
      if (verdicts.some(v => !v)) throw new Error(`#${N}: a skeptic returned nothing; resume this run with the same args`)
      checked.forEach((s, k) => (verdicts[k].refuted ? skeptic.refuted : skeptic.stood).push({ ...s, reason: verdicts[k].reason, evidence: verdicts[k].evidence || '' }))
    }
    log(`#${N}: skeptics refuted ${skeptic.refuted.length} of ${checked.length} blocker or major finding(s)`)
  }
  openSerious = SKEPTIC_LIMIT ? skeptic.stood.length + skeptic.unchecked.length : serious.length
}

// issue-task's own result: the implementer's verdict, the reviews' counts, the publisher's fields and each v2 option's.
const brief = (stopped, pub, extra) => {
  const out = { n: N }
  if (stopped) out.stopped = stopped
  if (pub) {
    Object.assign(out, pick({ pr: pub.pr_number, ...pub }, ['pr', 'pr_url', 'published', 'ci_green', 'closes_issue']))
    // Only when not as usual: a missing handoff or board move is the manager's to do.
    if (pub.handoff_posted === false) out.handoff_posted = false
    if (pub.board_in_review === false) out.board_in_review = false
    if (pub.stopped_by_mutants === true) out.stopped_by_mutants = true
  }
  Object.assign(out, pick(impl, ['verify_green', 'complete']))
  out.summary = line(impl.summary)
  if (handedOver.length) out.handoffs = handedOver.length
  // Where no publisher ran, the relaunch's notes need the red verify tail and what is left, both in full (only a stop
  // carries them); after a publisher, the PR ("Part of") and not_fixed say what is left.
  if (!pub) {
    if (!impl.verify_green && impl.verify_tail) out.verify_tail = impl.verify_tail
    if (items(impl.left).length) out.left = items(impl.left)
  }
  // In full: the manager explains each one to the engineer, and copies each step's command as is. The publisher's
  // list carries the implementer's into the PR, so the implementer's counts only where the publisher's has no item
  // (none returned, or an empty list: its schema does not ask it to repeat the implementer's).
  const pubNeeds = pub ? items(pub.needs_engineer) : []
  out.needs_engineer = pubNeeds.length ? pubNeeds : items(impl.needs_engineer)
  if (pub) {
    out.human_steps = pub.human_steps || []
    out.not_fixed = lines(items(pub.not_fixed))
    out.fixed = items(pub.fixed).length
    if (pub.merge_notes) out.merge_notes = line(pub.merge_notes)
  }
  if (items(impl.proposed_issues).length) out.proposed_issues = lines(items(impl.proposed_issues), 100)
  if (items(impl.provisional_content).length) out.provisional_content = lines(items(impl.provisional_content), 120)
  out.reviews = briefReviews(labels, reviews)
  // #606: the review tier and the agents the launch passed that it dropped.
  out.tier = TIER
  if (TIER_SKIPPED.length) out.tier_skipped = TIER_SKIPPED
  // #469: the plan's comment, whether its result was cut, and the planner's model when the launch set one (the
  // manager's models.plan, orchestrate-stage §3), so the before and after of #469 read from the results.
  if (planned) {
    out.plan = { summary: line(planned.plan.summary), critique: tally(planned.critique.findings, 'severity', SEVERITIES) }
    if (typeof planned.plan.comment_url === 'string' && planned.plan.comment_url) out.plan.comment = planned.plan.comment_url
    if (planned.plan.clipped) out.plan.clipped = true
    if (set(MODELS, 'plan') !== undefined) out.plan.model = set(MODELS, 'plan')
  }
  if (testReviewSkipped) out.test_review = { skipped: testReviewSkipped }
  else if (testReview) {
    out.test_review = { available: testReview.available, exit_2: testReview.exit_2, mutants: tally(testReview.mutants, 'result', ['killed', 'survived', 'error', 'equivalent']), findings: tally(testReview.findings, 'severity', SEVERITIES), ...(testReview.notes ? { notes: line(testReview.notes) } : {}) }
  }
  if (SKEPTIC_LIMIT && skeptic) out.skeptic = { refuted: skeptic.refuted.length, stood: skeptic.stood.length, unchecked: skeptic.unchecked.length }
  // ab_review (#535): the two models and the judge's counts; `metrics` scores the runs from the journal.
  if (AB_REVIEW && reviews.length) {
    out.ab_review = {
      model: set(MODELS, 'code'), control_model: set(MODELS, 'review') || null,
      judge: !judge ? 'returned nothing' : judge.skipped || { verdicts: tally(judge.verdicts, 'verdict', ['valid', 'invalid', 'unsure']), matches: (judge.matches || []).length },
    }
  }
  if (VISUAL) out.visual = { ...shots, ...(shots.notes ? { notes: line(shots.notes) } : {}) }
  Object.assign(out, extra)
  if (!LEAN) out.lean_off = { general: GENERAL, reason: line(A.lean_reason) }
  out.full = FULL
  return out
}

// A red implementer stops the run here: no fresh agent has read the final code, so nothing may be published
// (definition of done, step 2). The manager relaunches a fresh run with the failure in notes (a resume would replay
// the cached red result); the implementer continues from the worktree's commits.
if (!impl.verify_green) {
  log(`#${N}: verify RED after the implementer; nothing reviewed or published`)
  return brief('verify red after the implementer: nothing reviewed or published; relaunch issue-task (not a resume) with the failure in notes', null, {})
}

phase('Publish')
// test_review: a `mutants` run that exited 2 left its scratch worktree behind; the publisher stops and reports it.
const MUTANTS_STOP = `If a \`tools\\run.cmd mutants\` run exits 2 (its scratch worktree could not be removed), stop: publish nothing, fix nothing more, post a comment on #${N} (\`gh issue comment ${N} --body-file <file under ${SCRATCH}/>\`: Done / Stopped: mutants exited 2, with the leftover worktree's path from \`git worktree list\` / Needs the engineer: remove it), and return published false and stopped_by_mutants true with that step under human_steps.`
const stoppedByMutants = testReview && testReview.exit_2 === true
// The publisher's schema gains stopped_by_mutants only where its prompt can stop on mutants, so a default run's
// schema stays byte-identical.
const PUB_SCHEMA = testReview && testReview.available ? { ...PUB, properties: { ...PUB.properties, stopped_by_mutants: { type: 'boolean' } } } : PUB
// publish_clean (#308): the full publisher of a clean run takes its own role, which falls back to publish, so with
// neither models nor efforts naming it the publisher's options and prompt stay byte-identical.
const PUB_ROLE = !DESIGN && !stoppedByMutants && openSerious === 0 ? 'publish_clean' : 'publish'
const FULL_PUB_EFFORT = set(EFFORTS, PUB_ROLE) || 'high'
const TRIAL = MODELS.publish_clean !== undefined || EFFORTS.publish_clean !== undefined
const TRIAL_WHY = DESIGN ? 'a design task' : stoppedByMutants ? 'mutants exited 2' : openSerious ? `${openSerious} blocker or major finding(s) open` : 'no blocker or major open'
// #606: the tier in the publisher's prompt, for the PR and for `metrics` (a run's return value is not journaled, so
// metrics.REVIEW_TIER reads this line from the publisher's transcript); the publisher stopped by mutants gets it too.
const TIER_FACT = `Review tier (#606): ${TIER} (${TIER_WHY})${LIGHT ? `: the light chain ran, ${labels.join(', ')}, then you` : ''}${TIER_SKIPPED.length ? `; dropped although the launch passed them: ${TIER_SKIPPED.join(', ')}` : ''}.`
const TIER_LINE = `${TIER_FACT} Say the tier and why in one line of the PR's verification section.`
if (TRIAL) log(`#${N}: publish_clean ${PUB_ROLE === 'publish_clean' ? 'applied' : 'not applied'}: ${TRIAL_WHY}; the publisher runs with model ${set(MODELS, PUB_ROLE) || '(the session default)'}, effort ${FULL_PUB_EFFORT}`)
const pub = stoppedByMutants
  ? await agent([
    RULES,
    `Task: report a stopped run of issue #${N} (${A.title}) from the worktree ${WT}, PR base ${BASE}. Effort: ${PUB_EFFORT}. Budget: at most about 30 tool calls.`,
    `The test review (test_review) reported: ${JSON.stringify(testReview)}`,
    `${MUTANTS_STOP} Check \`git status\` in the worktree first: it must show no planted fault.`,
    `${TIER_FACT} Say the tier and why in one line of the comment.`,
    HUMAN_STEPS,
    'Return the structured result.',
  ].join('\n\n'), withModel({ label: `publish:#${N}`, phase: 'Publish', effort: PUB_EFFORT, schema: PUB_SCHEMA }, 'publish'))
  : await agent([
    RULES,
    `Task: publish issue #${N} (${A.title}) from the worktree ${WT}, PR base ${BASE}. Effort: ${FULL_PUB_EFFORT}. Budget: at most about 150 tool calls.`,
    `An earlier attempt may have got part of the way (a resumed run): check \`gh pr list --head ${A.branch} --state all\`, the issue's latest comments and \`git status\` before doing anything twice.`,
    `The implementer reported: ${JSON.stringify(impl)}`,
    `Fresh reviewers found: ${JSON.stringify(reviews)}\n\nFix every blocker and major finding and the cheap minor ones, each in its own commit, with a test where it is a behaviour; a finding you think is wrong gets the reason in the PR. List the rest. After the fixes, run the tests they touch and \`tools\\run.cmd check\`, then publish (below) with no standalone \`verify\` before it: \`publish\` verifies, unless an identical tree was just verified green, and a red verify inside it pushes nothing. Red: fix and publish again (never weaken, skip or delete a test); if it stays red, publish nothing: post a comment on #${N} (Done / Red and why / Needs the engineer) and return published false.`,
    TIER_LINE,
    AB_REVIEW ? 'Two code reviewers reviewed the same diff (ab_review, #535: an A/B of their models; the first two results above): a finding both raised is one finding, fixed once and one row in the PR\'s findings table.' : '',
    planned ? `The plan's summary and its critique (plan_review; the whole plan is the plan agent's comment on the issue, plan_comment, and stays in the run's journal): ${JSON.stringify({ plan_summary: planned.plan.summary, ...(planned.plan.comment_url ? { plan_comment: planned.plan.comment_url } : {}), critique: planned.critique })}\n\nIn the PR, under "Plan review": the plan in a few lines (from its summary) with a link to its comment, then each critique finding and what the build did with it (the implementer's decisions say how it settled each).` : '',
    testReviewSkipped ? `The test review (test_review) was skipped: ${testReviewSkipped}. Say so in the PR's verification section.`
      : !testReview ? ''
      : testReview.available
        ? `The test review (test_review; \`tools\\run.cmd mutants\` planted each fault in a scratch worktree): ${JSON.stringify(testReview)}\n\nIts findings count like the reviewers': fix each survived mutant with a test that kills it, ${MUTANTS_RERUN}. In the PR, a table of the mutants: file:line, the fault, killed / survived / equivalent, and the test that kills it now. ${MUTANTS_STOP}`
        : `The test review did not run: \`tools\\run.cmd mutants\` is missing on this branch (P7, #184, not merged into its base yet): ${testReview.notes || 'no notes'}. Say so in the PR's verification section and in the handoff.`,
    skeptic && skeptic.refuted.length + skeptic.stood.length + skeptic.unchecked.length
      ? `Skeptics tried to refute each blocker and major finding (skeptic): ${JSON.stringify(skeptic)}\n\nA refuted finding is not fixed unless you find the skeptic wrong: the PR's findings table lists it as refuted, with the skeptic's reason. The findings that stood, and those over the limit (unchecked), are fixed as usual.`
      : '',
    !VISUAL ? ''
      : shots.available && (shots.pngs || []).length
        ? `Visual check (visual): the implementer's playcheck run: ${JSON.stringify(shots)}\n\nIf a fix changes what a scenario shows, run \`tools\\run.cmd playcheck <scenario>\` again. In the PR's Screenshots section list each PNG's path for the engineer to drag in (gh cannot upload images), and add that under human_steps.`
        : `Visual check (visual): no screenshots: ${shots.notes || 'the implementer returned none'} (\`tools\\run.cmd playcheck\` is P9, #186). Say so in the PR's Screenshots and verification sections.`,
    [
      'Then, in this order (the definition of done; the reviews above were its review step):',
      '- Docs: durable knowledge that the change or your fixes alter goes into the doc that owns it (docs/ARCHITECTURE.md, docs/AGENT_WORKFLOW.md, an area CLAUDE.md, an ADR) on this branch. A human\'s correction of how the agents work that the notes or the issue\'s comments record: a docs/interventions/ entry by .claude/skills/log-intervention/SKILL.md (read it only then). A third-party asset: docs/credits/<asset>.md, then `tools\\run.cmd credits`. Commit these too.',
      `- \`${PUBLISH}\`. Known traps: it can fail right after a rebase that changed tools/runner (verify ran with the old runner modules): run it again; "Could not resolve hostname github.com" is transient: check with \`git ls-remote origin\` and run it again. If it stops on a rebase conflict, rebase by hand inside your worktree (\`git rebase origin/${BASE}\`, resolve keeping both sides' intent, \`git rebase --continue\`, the tests the conflicts touched and \`check\`), then publish again (it verifies the new tree)${BASE === 'main' ? '' : ` after \`git config branch.${A.branch}.primeBaseTip $(git merge-base HEAD origin/${BASE})\` (redundant since #113: publish does this itself; harmless)`}. If it stops on remote commits the branch never had, or with "cannot confirm that the parent … was merged", push nothing by hand: return published false with what it said, and the engineer's check under human_steps.`,
      `- PR: \`gh pr create --base ${BASE} --title "<conventional title>" --body-file <file under ${SCRATCH}/>\` from .github/pull_request_template.md (if \`gh pr view ${A.branch}\` already finds a PR for the branch, update its body with \`gh pr edit <pr> --body-file <file>\` instead of creating a second one): \`Closes #${N}\` when every acceptance criterion is met (else \`Part of #${N}\` and what is left); the summary and the why, from the implementer's summary and decisions (not rebuilt from \`git log\`); the verification commands and the verify tail; screenshots "none" unless visual; docs updated; under Cross-area, for a change in the content area (content/ levels/ docs/GDD.md docs/design/ and the skills .claude/skills/new-mechanic/ and .claude/skills/new-level-piece/), the engineer's word it was made on, with its link, and the content/ and levels/ files as provisional under the MVP content ADR, for the engineer's approval, with no tag (docs/AGENT_WORKFLOW.md §9; the "Approved by the engineer: <link>" line that lets the gate merge it is the manager's, once he approves); the other owner's paths (.github/CODEOWNERS) also get \`--reviewer <their handle>\`; a table of every reviewer finding and what happened to it; "Needs the engineer" with options and a recommendation for each; "Merge order" (which open PRs this depends on or will conflict with, from the notes below; a stacked PR says "merge only after its parent, into the parent's base").${DESIGN ? ' The proposed issues as titles, one line each.' : ''}`,
      `- \`gh pr checks <pr> --watch\`: CI's full suite is the test gate (the local verify ran lint and check only), so watch it to the end. Red: fix, run the touched tests and \`check\`, publish again (it verifies); at most two rounds, then report what is still red.`,
      `- The handoff comment on #${N} (\`gh issue comment ${N} --body-file <file>\`): "## Handoff", the PR link, then Done / Left / Decisions / Gotchas / Needs the engineer${DESIGN ? ', and the proposed issues in full' : ''}.`,
      `- \`tools\\run.cmd board move ${N} in-review\`.`,
    ].join('\n'),
    BOUNDED ? waits(true) : '',
    `Task notes from the manager (for the PR's merge order and the handoff):\n${A.notes}${A.coord ? '\n\n' + A.coord : ''}`,
    HUMAN_STEPS,
    'Return the structured result.',
  ].filter(Boolean).join('\n\n'), withModel({ label: `publish:#${N}`, phase: 'Publish', effort: FULL_PUB_EFFORT, schema: PUB_SCHEMA }, PUB_ROLE))

if (!pub) throw new Error(`#${N}: the publisher returned nothing; resume this run with the same args`)
// ab_review (#535): the judge ran beside the publisher; a measurement, not a gate: one that died leaves the run unjudged.
if (judging) {
  judge = await judging.catch(() => null)
  if (!judge) log(`#${N}: the ab_review judge returned nothing; the run goes on unjudged`)
}
if (AB_REVIEW && reviews.length) log(`#${N}: ab_review ${judge ? (judge.skipped || `judged ${(judge.verdicts || []).length} finding(s), ${(judge.matches || []).length} pair(s)`) : 'unjudged'}`)
if (pub.published && !reviews.length) throw new Error(`#${N}: published with no fresh review; review PR ${pub.pr_url || ''} before a merge`)
// A resume replays the cached exit 2 (the test review's or the publisher's own rerun), so it would stop again.
return brief(stoppedByMutants || pub.stopped_by_mutants === true
  ? `tools\\run.cmd mutants exited 2 ${stoppedByMutants ? 'in the test review' : 'in a rerun by the publisher'}: its scratch worktree could not be removed; nothing published (see the comment on the issue). Once the engineer removes the leftover worktree, relaunch issue-task (not a resume: a resume replays the cached exit 2) with the stop in notes`
  : null, pub, TRIAL ? { publish_clean: { applied: PUB_ROLE === 'publish_clean', why: TRIAL_WHY, open: openSerious, model: set(MODELS, PUB_ROLE) || null, effort: FULL_PUB_EFFORT } } : {})
