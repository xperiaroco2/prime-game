# An A/B of Sonnet against Opus for the code reviewer, the publisher and the art critic

- **Status:** Accepted (#535). The A/B itself is the engineer's decision 3 of 2026-10-07; the design below (which
  launches, the judge, the sample size and the stop rule) is the task's, under his delegation of technical choices
  (#134). Its numbers are proposals he may change on the PR ("Needs the engineer" there).
- **Date:** 2026-10-07
- **Deciders:** the engineer ([#302 comment 6038401263](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6038401263),
  item 3: "A Sonnet A/B on code-reviewer, the publisher and the art critic, with the findings' quality checked")
- **Tracking:** #535, #302 (Token efficiency)
- **Builds on:** the [model-guard ADR](2026-09-28-model-guard-no-fable-in-shared-config.md) (no script default names a
  model; its amendment of 2026-10-07 covers this A/B), the [weekly budget ADR](2026-10-05-weekly-budget-across-four-tracks.md)'s
  N5 (a) (the Sonnet publisher on clean runs) and the quality scorecard of `metrics` (#314).

## Context
The token audit of 2026-10-06 (the comment above): Sonnet made 890 of about 17,000 API calls of the week, Opus the
rest; Sonnet's cache writes and output cost half of Opus's (cache reads the same); about 3.5% of the week is the most
a move to Sonnet could save, and its quality is unmeasured.

`tools\run.cmd metrics --since 2026-09-30T00:00:00Z` on 2026-10-07 (185 finished `issue-task` runs):
- **The code reviewer** (always Opus, effort high): 183 reviews, median API list $0.87 per review, 4 blockers, 63
  majors, 335 minors and 354 nits; 10 reviews found nothing. At Sonnet's price a review would cost about half.
- **The publisher on clean runs** (Sonnet since #308's trial and N5 (a)): see "The publisher's half" below.

Two facts of `issue-task` shaped the design. `models.review` is the fallback of the plan critique, both netcode
reviews and the skeptics, so a launch could not move the code reviewer alone. And the reviews a launch gets are its
only check before the PR: a trial must not leave a run reviewed worse than today's.

## Decision

### The code reviewer's half
1. **A role for the code reviewer alone.** `issue-task` takes `models.code` and `efforts.code` (falling back to
   `review`): the diff's `code-reviewer` only, never the plan critique, the netcode reviews, the skeptics or
   `godot-api-checker`. No default names a model; the workflow tests assert it.
2. **Which launches.** From the merge of #535, the manager passes `models: {code: "sonnet", publish_clean: "sonnet"}`
   and `ab_review: true` on every non-design `issue-task` launch of this repo (orchestrate-stage §3), until `metrics`
   shows a verdict other than "continue" for the pair (Sonnet, Opus). Not on a design task (its code reviewer reviews
   a design: another population) and not on `pr-rebase` (no `code` role; its reviews follow a rebase). `models.review`
   stays unset, so the control runs on the model in `.claude/agents/code-reviewer.md` (Opus); `models.code` must
   differ from it
   (the script names no model, so it cannot check that itself). Each such launch runs two agents more than without
   the arg (the control and the judge; one when neither reviewer found anything): the kickoff's agent count covers them.
3. **How quality is judged: a control and a blind judge.** With `ab_review` a control `code-reviewer` runs beside the
   trial one, with the same prompt on the review model, and both reviews go on to the skeptics and the publisher as
   usual: the publisher fixes the union, so a trial run is reviewed at least as well as an all-Opus one. Then one
   read-only judge (`code-reviewer` type, the review model, about 40 tool calls) reads the diff and both lists as
   "reviewer 1" (the trial) and "reviewer 2" (the control), told neither model, and returns for each finding valid,
   invalid or unsure with the severity it would give, plus the pairs of findings that name the same defect. The judge
   changes nothing in the run; `metrics` scores the runs from the journal, and the result's `ab_review` gives the
   counts.
4. **What `metrics` reports** ("The code reviewer's A/B (#535)", `ab_review` in `metrics.json`): per run, each side's
   findings, valid ones (blockers and majors by the judge's severity) and invalid ones, the valid findings each side
   missed (the other side's without a pair), and the $ of the trial reviewer, the control and the judge; per pair of
   models the totals and the stop rule's advice.
5. **Sample size and stop rule** (`metrics`' `AB_*` constants). The unit is a judged run. At today's rate (0.37
   blockers and majors per review) ten runs hold about four serious findings per side: enough to see a model that
   misses majors, not to prove two models equal.
   - **Stop early**, and drop Sonnet for the code reviewer, once Sonnet missed **two more** valid blockers or majors
     than the control missed of Sonnet's (the misses are counted both ways, so the noise between two Opus reviews
     does not count against Sonnet alone).
   - **After ten judged runs**, keep Sonnet when it missed at most one more valid blocker or major than the control,
     found at least **80%** as many valid findings, and its invalid share is at most **15 points** over the control's;
     otherwise drop it.
   - The verdict is advice. The manager reports it on #302 with the tables, and the engineer decides. A keep becomes
     a standing launch habit (`models.code: "sonnet"` without `ab_review`, as N5's publisher) only by a further
     amendment of the model-guard ADR; a drop changes nothing.
6. **Cost of the trial.** Per launch: the Sonnet reviewer (about $0.45) and the judge (about $1, an estimate: a judge
   reads what a reviewer reads, with fewer tool calls), about $1.5 more than today, $15 for ten runs: about 0.65% of
   the week at $23 per 1%. The saving if kept: about $0.4 per review, about $75 (3 points of the week) at the 183
   reviews of 2026-09-30 to 2026-10-07, the audit's ceiling of about 3.5%.

### The publisher's half
It already runs: since #308 and N5 (a) the manager passes `models.publish_clean: "sonnet"` on every non-design
launch, and `metrics`' quality scorecard compares the publishers by role setting. No new arg; it is judged at the next
weekly reset, as N5 says. The scorecard on 2026-10-07 (clean runs; the same window: Opus's clean runs since Sonnet's
first, 2026-10-04 10:45 UTC):

| publisher on a clean run | runs | API list $ per publisher (median) | publisher fix rounds (mean) | green on the first CI round (per run) | Found-by follow-ups |
|---|---|---|---|---|---|
| Opus, since 2026-09-30 | 101 | $2.27 | 0.65 | 98 of 99 | 15 |
| Opus, the same window as Sonnet | 16 | - | 0.56 | 16 of 16 | 1 |
| Sonnet | 32 | $0.64 | 0.88 | 28 of 30 | 2 |

A quarter of the price; one or two more CI reds in 30 and about a third more `publish` reruns per run. The runs are
not paired (different tasks), so these are signals for the engineer's judgement at the reset, not a verdict.
During the code reviewer's A/B a run counts as clean only if neither code reviewer's blockers or majors stay open (the
control's findings count like any reviewer's), so clean runs are fewer than before: compare the publishers' scorecards
inside the A/B window, not against the earlier one.

### The art critic's half
The art critic is a role of `prime-game-art`'s own workflows, run by that repo's manager. A request issue there
([prime-game-art#46](https://github.com/xperiaroco2/prime-game-art/issues/46)) asks for the same method: a control
critic on Opus beside a Sonnet critic on the same assets for a fixed number of
batches, a blind judge (or the human art review) ruling each remark valid or not and pairing the shared ones, a stop
rule like the one above, and the result reported on prime-game #302. Its manager decides the details.

## Alternatives
- **`models.review: "sonnet"`**: moves the plan critique, the netcode reviews and the skeptics too: not the asked
  scope, and the netcode review guards the information-leak invariant.
- **The skeptic as the judge**: it checks only the blockers and majors one reviewer raised, so it cannot see what a
  reviewer missed, and it runs one agent per finding.
- **The publisher as the judge**: it fixes as it judges, runs on Sonnet on clean runs (it would judge its own model),
  and its fixed and not-fixed lists are prose.
- **Half the launches Sonnet-only, half Opus-only**: no pairs (different diffs), so ten runs per side say little, and
  the Sonnet half would go without an Opus review.
- **Count findings without a judge**: more findings is not better findings; nits and wrong findings would count.

## Consequences
- During the trial each non-design launch runs two agents more and costs about $1.5 more; its code findings may be
  doubled (both reviewers raise one defect), so its blockers and majors in the scorecard count both, as the skeptics
  and `publish_clean` do.
- The judge is Opus judging Opus against Sonnet; the prompts hide which is which, and the reviewers' order is fixed
  (reviewer 1 is always the trial), so a position bias, if any, is the same in every run.
- `models.code` stays after the trial: with no default it changes nothing unless a launch passes it.
