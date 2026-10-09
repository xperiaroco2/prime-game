# Workflow scripts: notes for agents without the Skill tool

Checked against Claude Code 2.1.284 on 2026-10-08 (#557). Claude Code's own reference is the bundled skill
`workflow-authoring`: it has no file in the repo, and the lean agent types (`task-implementer`, `task-publisher`)
have no Skill tool, so a task that edits `.claude/workflows/` reads this page instead
([lean agent types ADR](decisions/2026-10-04-lean-workflow-agent-types.md), amendment 2026-10-08). When the CLI
changes, a session with the Skill tool (a manager's) rechecks these notes against that skill and updates the line
above.

## The script
- Plain JavaScript, not TypeScript: a type annotation is a parse error. The body runs as an async function: `await`
  at the top level, and a `return` gives the run's result.
- It opens with `export const meta = {...}`, a pure literal (no variable, call, spread or template). `name` and
  `description` are required; `whenToUse` and `phases` (`{title, detail}`) are optional. A `phase('X')` call groups
  the agents that follow under the `meta.phases` entry with the same title.
- Standard built-ins work, but `Date.now()`, `Math.random()` and `new Date()` without an argument throw: a resume
  must replay the same calls. Timestamps come in through `args`.
- No filesystem, no Node API, no imports: a script cannot read a file or check that one exists. Helpers shared by
  two scripts are copied (`test_workflows.py` compares the copies).

## The hooks
- `agent(prompt, opts)`: one subagent. `opts`: `label`, `phase`, `schema`, `model`, `effort`
  (`low` to `max`), `isolation: 'worktree'`, `agentType`. With a `schema` (a JSON Schema whose root is an object and
  whose `required` names only keys of `properties`) the agent must return a matching object; without one it returns
  its final text. It returns `null` when the agent was skipped or died after retries.
- `agentType` is resolved like the Agent tool's types, from `.claude/agents/` of the checkout the session runs in
  (the manager's). A name with no agent file throws: `agent type 'x' not found`. With no `agentType` the agent is
  the general workflow agent (`workflow-subagent` in its `agent-*.meta.json`), with every tool of the session.
- `parallel([() => agent(...), ...])` waits for all; a thunk that throws gives `null`. `pipeline(items, stage, ...)`
  runs each item through the stages without a barrier. At most min(16, CPUs - 2) agents run at once.
- `args` is the launch's `args`, as given (pass objects and lists as JSON values, not as a string). `log(text)` shows
  a progress line. `workflow(name or {scriptPath}, args)` runs another workflow inline, one level deep.
- Agents get the `CLAUDE.md` files as any session does; a prompt names the rule a step needs instead of repeating
  them.

## Resume
A run resumes with `resumeFromRunId` and the same args. Agent calls replay from the cache while each call's prompt
and options equal the earlier run's; the first call that differs, and every call after it, runs live. So an edit to
an early prompt makes a resumed run pay again for every later agent, and a new arg must leave the prompts and options
of a launch without it unchanged. The run's transcript folder holds `journal.jsonl` (each agent's result) and, per
agent, `agent-*.jsonl` and `agent-*.meta.json` (its `agentType`); `tools\run.cmd metrics` reads them.

## This repo's scripts
- `issue-task.js` and `pr-rebase.js`, launched by the orchestrate-stage skill (`docs/AGENT_WORKFLOW.md` §7.1). Each
  arg has a row `//   <arg>  ...` in the header comment and `<arg>?` in `meta.whenToUse`; `KNOWN` lists them; a
  wrong value throws before any agent runs, an unknown arg only logs.
- Every agent's options are built in `withModel` (via `asReviewer` for a reviewer): models, efforts and, under
  `lean`, the agent type are appended last, so options of a launch without them stay as they were.
- `tools/runner/tests/test_workflows.py` runs both scripts under Node with stub agents (`selftest`, part of
  `verify`). The snapshots in `tools/runner/tests/workflow_snapshots/` pin every agent's prompt and options: each
  case as launched, and under `unbounded/` with `bounded_waits: false` and `lean: false`, the text a resume of an
  older run replays. A deliberate change regenerates them: run the tests once with `PRIME_WORKFLOW_SNAPSHOTS=update`,
  read the diff (only the intended lines may change), commit it with the change, then run them again without it.
  Never edit a snapshot by hand; after a rebase that touched the scripts, regenerate them.
- The compact result (#386) stays small: `CompactResultTest` bounds it.
- `issue-task.js`'s review tier (#606): the implementer's changed paths choose, the worst winning. `full` (a path
  under `core/ server/ net/ client/ voice/ tests/harness/` but `client/ui/`, quick-task's `REVIEWED` copied; no paths;
  a design task; the arg `tier: 'full'`) runs the whole chain; `light` drops `skeptic`, `plan_review` by the branch's
  area, and the netcode review and `test_review` on a `client/ui/` diff (the `!LIGHT` guards; any other light diff
  was never routed to them). It lists `test_review` and `second_review` as dropped whenever passed: compare tiers in
  `metrics` by the skeptic and the plan. `ReviewTierTest` covers it.
- `tools\run.cmd metrics` and `wave` read each agent's role from its label (`metrics.role_of`): `implement:#<n>`,
  `review:code:#<n>` and the like, with a suffix `#<k>` for a later agent of the same role (issue-task's checkpoint
  continuations, `implement:#<n>#2`; pr-rebase's `fix:#<n>#2`). A suffix `:<k>` makes the label unknown ("other").
- `quick-task.js` (#608, launch-args.md): one `task-publisher` agent takes an XS/S task through `lint`, `check`, a
  PR and CI; only a diff under `core/ server/ net/ client/ voice/ tests/harness/` (but `client/ui/`) adds the two
  reviewers and, on a
  blocker or major, a fix agent. `QuickTaskTest` covers it, with no snapshots.
