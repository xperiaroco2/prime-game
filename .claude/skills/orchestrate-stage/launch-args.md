# Launch args (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it when you compose a launch's `args` (the skill's
§3, steps 1 and 2, come first).

## 3. Launching a task (continued from the skill's §3): the args
| arg | what |
|---|---|
| `n`, `title`, `wt`, `branch` | the issue, its title, the worktree path, the task branch (required) |
| `base` | the PR base: `"main"`, or the parent's branch for a stacked task; a non-`main` base reaches `gh pr create --base`, a release branch's also `publish --base` (a parent's branch does not: publish follows the PR's live base) |
| `notes` | the task's specifics, the engineer's answers that apply, ownership splits, merge order (required) |
| `coord` | what runs in parallel now and which shared files to touch minimally |
| `decisions` | the engineer's standing decisions, each with where it is recorded (every task that they touch) |
| `reading` | overrides the default reading list (the issue's links, handoffs and ADRs, the ARCHITECTURE sections it names by section, the code; area CLAUDE.md files and rules load by path, #339) |
| `testing` | overrides the default test expectations, which follow the branch's area: `core` a seeded Match and `view_of`; `net`/`server` loopback-transport tests plus the ENet runs (on CI); `tooling` runner tests (CI runs `selftest`); others generic |
| `design` | `true` for a docs-only design task: options for the engineer, a proposed issue split, the netcode reviewer, effort xhigh |
| `effort`, `plan`, `manager` | implementer effort (default high), the plan issue (default 30: set it), your name in prompts ("the M3 manager session") |
| `tier` | `"full"` only (#606), and rarely: forces the full review chain on a change the diff would rate light (see "Review tier" below); `light` cannot be forced |
| `update` | `true` (#856) on every relaunch of an issue whose PR is published (an engineer's answer, a plan change, a finding to fix), with every engineer answer since its last update in `notes` (below); never on a first launch or a resume (a resume takes its launch's args). The implementer records the PR's published head and returns the delta since it; the reviewers, routed by the delta's paths, review only the delta (the rest of the PR as context), and `plan_review`, `test_review` and `skeptic` are dropped even when passed: 3 to 5 agents (implementer, 1 to 3 reviewers, publisher), `second_review` as usual. The full chain (`plan_review` still dropped) when no published head comes back (a rebase or reset since), with `tier: "full"`, or when the delta touches any path under `core/ server/ net/ client/` (but `client/ui/`) `voice/ tests/harness/`, whatever its size. The result's `update` says which: `path` `update` (with `head`, `files`, `lines`) or `full` (with `why`), and `skipped` |

**Pipeline v2 args** (AGENT_WORKFLOW §7.1), off by default (bounded waits, #411, and the lean agent types, #458, are always on: #883 removed `bounded_waits`, `lean` and `lean_reason`, which now only log); the agents each adds count toward the number per workflow the kickoff approved:

| arg | when | adds (tool calls each) |
|---|---|---|
| `plan_review: true` | the issue's Files line touches `core/ server/ net/ tests/harness/`, or its Size is M or more | 2: a plan agent (80) and a fresh critique (40) |
| `test_review: true` | the same paths | 1 (60); none for a design task, a diff without `core/ server/ net/ client/ voice/` code, or one whose only production code is under `client/ui/` (the light tier, #606) |
| `second_review: true` | PRs on the netcode-review paths (root `CLAUDE.md` Routing), where the kickoff asks for it; with `models.second_review` where it allows a model beyond the shared list there | 1 (60) where the netcode review is routed |
| `skeptic: <n>` or `true` | design tasks and audits (publishers judged only 8 of 441 findings wrong) | 1 per blocker or major checked (30) |
| `visual: true`, a scenario or a list | `client/` UI and camera tasks; the notes name the scenarios | 0 |
| `efforts: {role: level}` | try `{godot: "medium"}` and compare its majors with `metrics` | 0 |
| `models: {role: model}` | only where the kickoff allows a model beyond the shared list: `implement` of a stage design or of a task red twice (§4), `second_review`; `publish_clean: "sonnet"` on every non-design `issue-task` launch (budget.md, N5; not `pr-rebase`: it has no clean-run publisher and rejects the role); `pr-rebase`'s `publish: "sonnet"` (its rebase and fix agents) on every launch, #835's trial (budget.md; only `sonnet` passes its whitelist); and `plan: "sonnet"` on every launch with `plan_review` (budget.md, #469). Ended 2026-10-13 (budget.md): `implement: "sonnet"`, `publish_findings`, `code` | 0 |
| `ab_review: true` | never: #535's A/B ended 2026-10-13 (budget.md) | a control reviewer and a judge (so do not pass it) |
| `checkpoint` (on by default; `false` turns it off) | #559, `issue-task` only, the default since #920 (the engineer's answer 6A on #302, comment 6145513919, after #759 measured implementer calls over 200k fall from 27% to 1%): an implementer past 150k context hands over to a fresh one (a note in `a<n>/handoff-<k>.md`, then `implement:#<n>#2` and `#3`), at most twice. It triggers mechanically (#597): the implementer runs `tools/run.sh ctx` (its own transcript's context; HANDOFF NOW at 150k, and past 200k even with only the final verify left) every ~15 tool calls and after each verify, and hands over after 60 tool calls in any case. Pass nothing (design tasks too); `checkpoint: false` only on the engineer's word. A resume takes its launch's args but the script as merged: a run launched before #920 merged without the arg runs with it on a resume after the merge. The up to 2 extra implementers count toward the approved agents per workflow: where they would exceed it (the kickoffs approve up to 7, with `plan_review` 5 + 2 + 2), say so in the launch's estimate. After each wave check each result's `handoffs` key and `metrics`' handoff table. The result shows `checkpoint: true` and `handoffs` (0 too) when on, and neither when a launch or resume ran with `checkpoint: false`; `wave` treats a handoff as a run still going | 0; up to 2 more implementers (250 each) |

- **`models`** follows the script's fallbacks: set only `implement`, `second_review`, `publish_clean`, `plan` or
  `pr-rebase`'s `publish`, never `review` or `netcode` (`review` also covers `code`, `plan_review`, `netcode`,
  `skeptic`, `second_review`; `netcode` covers `second_review`). `plan` follows `implement` when unset: every
  `plan_review` launch sets `models.plan: "sonnet"` (#469). `publish_clean` falls back to `publish` and applies only
  to the full publisher of a run with no blocker or major left open (a refuted one is closed), never a design task;
  leave `efforts.publish_clean` unset, so only the model varies. `pr-rebase`'s `publish` covers its rebase and fix
  agents. Other models never as a habit or for yourself.
- **Staying within the approved count A.** An `issue-task` launch runs at most 5 agents (the implementer, up to three
  reviewers, the publisher) plus what each option you pass adds. For a design task or an audit pass `skeptic: A −
  that sum` when it is at least 1, else leave `skeptic` out; `true` (a skeptic on every blocker or major) only when
  the kickoff set no cap (the manager's decision on PR #193). `pr-rebase` the same way, from at most 4 (§5).

The workflow: (with `plan_review` a plan agent and a fresh critique of its plan first) implementer (commits, verify
green, never publishes) → fresh reviewers in parallel, chosen from the changed paths (`code-reviewer` always;
`netcode-security-reviewer` for the Routing paths of root `CLAUDE.md` (`client/ui/` excluded) or a design task; `godot-api-checker`
for `.gd .tscn .tres`; then, when passed, the second netcode review, the test review with `mutants` and a skeptic per
blocker or major) → publisher (fixes blocker, major and cheap minor findings, `publish` (`--base` for a release
branch), PR with a findings table, "Needs the engineer" and "Merge order", CI watch with at most two fix rounds,
handoff, board In review). It throws when any routed agent returns nothing, and stops unpublished when the
implementer ends red. Every agent writes temporary files only under the scratchpad subfolder `a<n>/`.

**Review tier** (#606, the engineer's answer on #302: the full chain only where a mistake becomes a cheat, a desync or
a leak). After the implementer its changed paths choose, the worst one winning: `full` for a path under `core/ server/
net/ client/ voice/ tests/harness/` (but `client/ui/`), no changed paths, a design task or `tier: "full"` (the chain
above, unchanged); `light` for any other diff (docs, content, levels, tooling, and the screens under `client/ui/`: the
engineer's answer 2b on #302, comment 6085059719; the rest of `client/` stays full, #158): the code reviewer (plus
`godot-api-checker` on `.gd .tscn .tres`), then the publisher; the netcode review,
`test_review`, `second_review` and `skeptic` are dropped even when passed. For a `client/ui/` task whose kickoff asks
for the netcode review (a screen that shows a role, a vote or another player's state), pass `tier: "full"`.
`plan_review` runs before any diff, so the branch's area decides it: `content`, `level` and `tooling` skip it. Pass the
options as the table says: the script drops them where the tier does. The result's `tier` and `tier_skipped` say what
ran; `metrics` groups cost and wall time per tier.

Notes that worked: say which PR a needed file comes from if it is unmerged ("build with fixtures, fetch and rebase
once it lands"); repeat rules that force fixture updates in every later PR (neutral class defaults with the numbers
in the data); name a task's merge order relative to the other open PRs; name every rename in both tasks' notes (§9).

An update run of a published PR (`update: true`, #856; a design PR too): before launching, collect every engineer
answer posted since its last update, also those on sibling design PRs that apply to it (#695's GD7 greybox answer
covered four chains), and put them all in `notes`: a second update minutes after the first costs its reviewers and
publisher again (#682: $9.6, #833). Runs after an issue's first launch were 28% of the spend (`metrics --since
2026-10-08T12:25:00Z`, "Issues launched 2 or more times": $279 of $992 by 2026-10-11T16:19Z), each update $7.6 to
$14, about half of it reviewers, skeptic and publisher; `update` cuts the planner, the test reviewer and the
skeptics and shrinks the reviews to the delta (an estimate until `metrics` measures the first update runs).

## quick-task (#608)
A task whose issue says `Size: XS` or `S`, one logical change and no design (a rename, a text or value change, a docs
fix) goes to `quick-task` (`.claude/workflows/quick-task.js`) instead of `issue-task`, after `start` as usual. Args:
`{n, title, wt, branch, base, notes}`, and `models: {quick: "opus"}` only for a harder one (default Sonnet). One
`task-publisher` agent makes the change, runs `lint` and `check`, pushes, opens the PR and waits for CI (at most two fix
rounds); only a diff on the netcode-review paths (root `CLAUDE.md` Routing) adds `code-reviewer` and
`netcode-security-reviewer` (`code-reviewer` alone when the diff is only under `client/ui/`, #606) and, on a blocker
or major, one fix agent (1 to 4 agents). When the result says
`ready_to_merge` (CI green, no blocker or major open, nothing for the engineer), merge at once: `tools/run.sh merge <pr>
--base <base>`; otherwise act on `needs_engineer` and `stopped`. Not for a design task, Size M or larger, or a new
mechanic.
