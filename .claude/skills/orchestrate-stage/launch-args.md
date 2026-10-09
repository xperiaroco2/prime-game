# Launch args (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it when you compose a launch's `args` (the skill's
§3, steps 1 and 2, come first).

## 3. Launching a task (continued from the skill's §3): the args
| arg | what |
|---|---|
| `n`, `title`, `wt`, `branch` | the issue, its title, the worktree path, the task branch (required) |
| `base` | the PR base: `"release/m<k>"`, or the parent's branch for a stacked task (`main` outside a stage and on the tooling track); every non-`main` base reaches `gh pr create --base`, a release base also `publish --base` (a parent's branch does not: publish follows the PR's live base) |
| `notes` | the task's specifics, the engineer's answers that apply, ownership splits, merge order (required) |
| `coord` | what runs in parallel now and which shared files to touch minimally |
| `decisions` | the engineer's standing decisions, each with where it is recorded (every task that they touch) |
| `reading` | overrides the default reading list (the issue's links, handoffs and ADRs, the ARCHITECTURE sections it names by section, the code; area CLAUDE.md files and rules load by path, #339) |
| `testing` | overrides the default test expectations, which follow the branch's area: `core` a seeded Match and `view_of`; `net`/`server` loopback-transport tests plus the ENet runs in verify; `tooling` the runner selftest; others generic |
| `design` | `true` for a docs-only design task: options for the engineer, a proposed issue split, the netcode reviewer, effort xhigh |
| `effort`, `plan`, `manager` | implementer effort (default high), the plan issue (default 30: set it), your name in prompts ("the M3 manager session") |

**Pipeline v2 args** (AGENT_WORKFLOW §7.1), off by default but `bounded_waits` and `lean`; the agents each adds count toward the number per workflow the kickoff approved:

| arg | when | adds (tool calls each) |
|---|---|---|
| `plan_review: true` | the issue's Files line touches `core/ server/ net/ tests/harness/`, or its Size is M or more | 2: a plan agent (80) and a fresh critique (40) |
| `test_review: true` | the same paths, once `mutants` (#184) is on the task's base (`git show origin/<base>:tools/runner/mutants.py`) | 1 (60); none for a design task or a diff without `core/ server/ net/ client/ voice/` code |
| `second_review: true` | PRs that touch `core/ server/ net/ tests/harness/`, where the kickoff asks for it; with `models.second_review` where it allows a model beyond the shared list there | 1 (60) where the netcode review is routed |
| `skeptic: <n>` or `true` | design tasks and audits (publishers judged only 8 of 441 findings wrong) | 1 per blocker or major checked (30) |
| `visual: true`, a scenario or a list | `client/` UI and camera tasks, once `playcheck` (#186) is on the base; the notes name the scenarios | 0 |
| `bounded_waits` | the default since #411 (no tool call of `issue-task` or `pr-rebase` blocks over 180 s, so their 5-minute cache stays warm; on a base without `wait`, #303, the agents wait in the foreground): pass nothing; `false` only to resume a run launched before #411 without the arg | 0 |
| `efforts: {role: level}` | try `{godot: "medium"}` and compare its majors with `metrics` | 0 |
| `models: {role: model}` | only where the kickoff allows a model beyond the shared list: `implement` of a stage design or of a task red twice (§4), `second_review`; `implement: "sonnet"` on a qualifying task during #560's trial (budget.md; [trial ADR](../../../docs/decisions/2026-10-08-sonnet-implementer-trial.md); red twice: relaunched once more on Opus without asking, in place of §4's stop); `publish_clean: "sonnet"` on every non-design `issue-task` launch (budget.md, N5; not `pr-rebase`: it has no publisher and rejects the role); and `plan: "sonnet"` on every launch with `plan_review` (budget.md, #469); `code: "sonnet"` with `ab_review` (next row) | 0 |
| `ab_review: true` | #535's A/B ([ADR](../../../docs/decisions/2026-10-07-code-reviewer-model-ab.md)): on every non-design `issue-task` launch, with `models.code: "sonnet"` (the diff's code reviewer alone; other than `code-reviewer.md`'s `model:`, the control's) beside `publish_clean`, until `metrics`' A/B table gives a verdict other than "continue"; then report it on #302 and stop passing both (`issue-task` only) | 2: a control code reviewer (60) and a judge (40); 1 when neither reviewer found anything |
| `checkpoint: true` | #559, `issue-task` only, opt-in: an implementer past 150k context hands over to a fresh one (a note in `a<n>/handoff-<k>.md`, then `implement:#<n>#2` and `#3`), at most twice. Not on by default until the engineer says yes after `metrics`' implementer context table measured about 10 tasks with it; pass it where the kickoff asks for it. The result's `handoffs` counts them; `wave` treats a handoff as a run still going | 0; up to 2 more implementers (250 each) |
| `lean` | the default since #458 (the engineer's N4 (b), 2026-10-06; the implementing and publishing agents run as `task-implementer` and `task-publisher`, whose files must be in your checkout: `agents-check --launch`; a run's `agent-*.meta.json` and `metrics`' agent-type table show the `agentType`): pass nothing, also for a task editing `.claude/workflows/` (its agents read `docs/workflow-scripts.md`, #557). `lean: false` only with `lean_reason` (`lean_reason?` in `whenToUse`; the script throws without it, #557): why the general agent, today only "a resume of <run id>, launched before #458" (budget.md); the result's `lean_off` counts the general agents | 0 |

- **`models`** follows the script's fallbacks: set only `implement`, `second_review`, `publish_clean`, `plan` or
  `code` (only with `ab_review`, next row), never `review` or `netcode` (`review` also covers `code`, `plan_review`,
  `netcode`, `skeptic`, `second_review`; `netcode` covers `second_review`). `plan` follows `implement` when unset:
  every `plan_review` launch sets `models.plan: "sonnet"` (#469). `publish_clean` falls back to `publish` and applies
  only to the full publisher of a run with no blocker or major left open (a refuted one is closed), never a design
  task; leave `efforts.publish_clean` unset, so only the model varies. Other models never as a habit or for yourself.
- **Staying within the approved count A.** An `issue-task` launch runs at most 5 agents (the implementer, up to three
  reviewers, the publisher) plus what each option you pass adds. For a design task or an audit pass `skeptic: A −
  that sum` when it is at least 1, else leave `skeptic` out; `true` (a skeptic on every blocker or major) only when
  the kickoff set no cap (the manager's decision on PR #193). `pr-rebase` the same way, from at most 4 (§5).

The workflow: (with `plan_review` a plan agent and a fresh critique of its plan first) implementer (commits, verify
green, never publishes) → fresh reviewers in parallel, chosen from the changed paths (`code-reviewer` always;
`netcode-security-reviewer` for `core/ server/ net/ client/ tests/harness/` or a design task; `godot-api-checker`
for `.gd .tscn .tres`; then, when passed, the second netcode review, the test review with `mutants` and a skeptic per
blocker or major) → publisher (fixes blocker, major and cheap minor findings, `publish` (`--base` for a release
base), PR with a findings table, "Needs the engineer" and "Merge order", CI watch with at most two fix rounds,
handoff, board In review). It throws when any routed agent returns nothing, and stops unpublished when the
implementer ends red. Every agent writes temporary files only under the scratchpad subfolder `a<n>/`.

Notes that worked: say which PR a needed file comes from if it is unmerged ("build with fixtures, fetch and rebase
once it lands"); repeat rules that force fixture updates in every later PR (neutral class defaults with the numbers
in the data); name a task's merge order relative to the other open PRs; name every rename in both tasks' notes (§9).

## quick-task (#608)
A task whose issue says `Size: XS` or `S`, one logical change and no design (a rename, a text or value change, a docs
fix) goes to `quick-task` (`.claude/workflows/quick-task.js`) instead of `issue-task`, after `start` as usual. Args:
`{n, title, wt, branch, base, notes}`, and `models: {quick: "opus"}` only for a harder one (default Sonnet). One
`task-publisher` agent makes the change, runs `lint` and `check`, pushes, opens the PR and waits for CI (at most two
fix rounds); only a diff under `core/ server/ net/ client/ voice/ tests/harness/` adds `code-reviewer` and
`netcode-security-reviewer` and, on a blocker or major, one fix agent (1 to 4 agents). When the result says
`ready_to_merge` (CI green, no blocker or major open, nothing for the engineer), merge at once:
`tools/run.sh merge <pr> --base <base>`; otherwise act on `needs_engineer` and `stopped`. Not for a design task,
Size M or larger, or a new mechanic.
