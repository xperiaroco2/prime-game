# The kickoff's content and template (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it at a stage's or track's first kickoff, to check
it, when a human asks for a kickoff, and when writing a handover's ready kickoff (not at a successor's own start).

## 1. The kickoff (continued from the skill's §1): what it must state
The kickoff must state:
- the scope (issue numbers, or the design handoff to open them from, and fillers) and the plan issue to report on.
  A new milestone gets its own plan issue (`M<k>: plan and order`, opened by you after the yes, its body written
  once and never edited); if the kickoff names none, recommend that;
- the git flow: the release branch `release/m<k>` every task PR targets (or, on the tooling track, PRs into `main`),
  and the order and dependencies: which task stacks on which (`start --base`), which waits for a merge;
- the concurrency cap (default three tasks at once, fewer where budget.md's PC share is lower: meta by day 1)
  and "one task = one issue-task workflow" with per-agent bounds (implementer about 250 tool calls, reviewers
  about 60, publisher about 150; with the v2 args of §3 the plan agent about 80, its critique about 40, the test reviewer
  about 60, each skeptic about 30, a publisher that only reports a stop about 30);
- explicit approval to exceed the size guideline, with the agent count it approves per workflow (`issue-task` runs
  3 to 5 agents plus those of the v2 args the kickoff names, §3; `small` means fewer than 5), and the `Track:` line,
  whose weekly budget (budget.md) covers the stage: you do not ask before each workflow (root `CLAUDE.md`);
- where a model beyond the shared list may run, if anywhere (the model-guard ADR's amendment A: stage designs,
  second reviews of PRs that touch `core/ server/ net/ tests/harness/`, audits, a task red twice), and its share of
  that model's own weekly window (at most half across all tracks). You stay on the shared models;
- the rules: you merge into `release/m<k>` and, through the gate, into `main` (§5); you close issues, workflow
  agents never; each agent only in its worktree; no `git stash`; temporary files in the scratchpad or `tests/scratch/`; Godot
  windows only through `shot`; a game rule no ADR settles becomes options under "Needs the engineer"; `content/`
  and `levels/` files are provisional;
- the engineer's standing decisions to honour, with where each is recorded; known traps; what to drop first;
- reporting: a comment on the plan issue after each wave; stop with a comment when nothing more can run without
  the human (answers, a design review, the milestone's go); "продовжуй" resumes after a check of the live state.

## 10. Kickoff template
The human copies it, fills the placeholders and sends it, in English or in their own language; the `Track:` line stays
English (`metrics --track` reads it). Moving state (which issues, which PRs) goes only in the message, never here.

```text
Orchestrate stage <k> (<milestone>, <theme>) with the skill orchestrate-stage. You are the manager: one task = one
issue-task workflow, up to <A> agents each, at most <n> at once (your track's PC share in budget.md).

Start from: <my review of the design PR #<pr> and its handoff on #<design issue> | the issues below>.
<If from a design: open the stage's issues from that handoff with my review's changes and report the list and the
order.>

<After a handover: the handover comment's notes end with this kickoff, these lines replaced by its "Continue from" line
(docs/MANAGERS.md §6); I paste it as it is.>
Track: <game | ui | art | meta>. Scope: <issues, or "the issues from the handoff">; fillers: <issues>.
Plan and reports: a comment on #<plan issue> after each wave; never edit its body.
Git flow: <release/m<k> from main; every task PR targets it (start --base release/m<k>); you merge task PRs into it
with tools\run.cmd merge after green CI on a head up to date with release/m<k>, fresh reviews with no open blocker or
major, and merge-check (no local verify: CI tests the push); you merge it into main through one PR at the end, through the gate, after my go | every PR straight
into main (the tooling track); you merge each with merge <pr> --base main after merge-check>.
Order: <order, or "as in the handoff">; stack with start --base <parent> only where a task depends on an unmerged
PR.
Pipeline v2: <plan_review for core/server/net/tests-harness and size M or more; test_review once mutants is on the
base; skeptic for design tasks; ...>; approved agents per workflow: issue-task up to <A>, pr-rebase up to <B>.
Bounds: implementer ≤ 250 tool calls, reviewers ≤ 60, publisher ≤ 150; plan ≤ 80, its critique ≤ 40, test review
≤ 60, each skeptic ≤ 30. I approve exceeding the size guideline (up to <A> agents per workflow); do not ask before
each workflow. Hand over at §7's turn-end verdict, even mid-wave: the handover comment's notes end with the ready
kickoff, which your last For-you carries too and I paste into a new session (handover.md); route C only if I ask for it.
Budget: this track's <T>% of the week from the reset <date> 10:00 UTC (budget.md; metrics --track reads it); within
it your restatement is a report; budget.md's rules at 80% and 100%, the 93% stop, the PC cap and the args apply.
Models beyond the shared list: <none | <model> for <stage designs, second reviews of core/server/net/tests-harness
PRs, tasks red twice>, at most <Q>% of its own weekly window>; you stay on the shared models.
Rules: into main only through the gate; you close issues, workflow agents never; each agent only in its worktree;
no git stash; you never leave your shell inside a worktree; temporary files in scratchpad/a<n>/ or tests/scratch/; Godot
windows only through shot; a game rule no ADR settles becomes options with a recommendation under "Needs the
engineer"; content/ and levels/ files are provisional, I approve them in the PR.
My decisions: the ADRs and my answers in the comments of <issues> (newer ones win).
Traps: <known traps>; tasks that edit .claude/ run only while I am around; <decisions reserved for me>.
Drop first if the budget runs out: <fillers>, then the per-wave metrics report, then <lowest-priority task>.
When nothing more can run without me: a comment on #<plan issue> and stop. "продовжуй": check the live
state and continue.
```
