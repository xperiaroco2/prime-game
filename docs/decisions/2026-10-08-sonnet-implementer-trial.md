# A Sonnet implementer trial on small tooling and docs tasks

- **Status:** Accepted (#560). The trial is the engineer's decision 2 of 2026-10-08; the qualifying tasks, the scoring
  and the stop rule below are the issue's acceptance criteria, written by the meta manager under his delegation of
  technical choices (#134). Its numbers are proposals he may change on the PR ("Needs the engineer" there).
- **Date:** 2026-10-08
- **Deciders:** the engineer. Approved by the engineer:
  https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6056243207 (item 2: "a trial of a Sonnet
  implementer on small tooling and docs tasks, run like #535's A/B and scored with `metrics`")
- **Tracking:** #560, #302 (Token efficiency)
- **Builds on:** the [model-guard ADR](2026-09-28-model-guard-no-fable-in-shared-config.md) (no script default names a
  model; its amendment of 2026-10-08 covers this trial), the shape of the
  [code reviewer's A/B](2026-10-07-code-reviewer-model-ab.md) and the quality scorecard of `metrics` (#314).

## Context
The scouting of 2026-10-08 on #302 (window 2026-10-06T10:00Z to 2026-10-08 about 09:00Z): implementers are the largest
cost, 37 agents and $143 of about $226 (63%): cache reads $83, cache writes $54, output $7. Sonnet's cache writes and
output cost half of Opus's; cache reads cost the same, so the saving is the write and output part: about $15 in that
window, about $54 per week, about 2.3% of a week, if quality holds.

The code reviewer's A/B dropped Sonnet as the reviewer (#302 comment 6059840904: 66% of the control's valid findings),
so a cheaper implementer is measured, not assumed. Unlike a review, an implementer's quality shows in the run itself:
red verify runs, the reviewers' blockers and majors on its diff, the publisher's fix rounds and red CI rounds. The
reviewers stay on Opus, so a weaker diff is still reviewed as today before its PR.

## Decision
1. **Qualifying tasks.** Size S (an XS counts as S) by the issue's `Size:` line, `area:tooling` or docs-only, no change
   under `core/ server/ net/ client/ voice/`, not a design task and not an edit of `.claude/workflows/` (the Files line
   says so). The manager judges it from the issue before the launch; any doubt is no trial task.
2. **The launch.** From the merge of #560, the manager passes `models: {implement: "sonnet", publish_clean: "sonnet"}`
   on every qualifying `issue-task` launch (orchestrate-stage §3, budget.md), until `metrics` gives advice other than
   "continue". The plan (a qualifying task has no `plan_review`), the reviewers and the publisher's rules are
   unchanged. No script, default or agent file names the model; the workflow tests still assert it. Red once: the
   fresh relaunch of orchestrate-stage §4 stays on Sonnet. Red twice: the manager relaunches it once more without
   `models.implement` (on Opus, as a task's model today) instead of stopping; red again, §4 as today. After the first
   trial launch `tools\run.cmd agents-check` confirms Sonnet served its implementer.
3. **Scoring** (`metrics`' "Sonnet implementer trial (#560)" table, `sonnet_trial` in `metrics.json`). A trial task is
   an issue with a run whose implementer was Sonnet; its relaunch on Opus counts with it. The baseline is the
   Opus-implemented, non-design tasks of the window whose issue says Size S or XS (read from GitHub, so not with
   `--no-gh`). Per task: runs and red runs (a run the manager must relaunch), verify runs and reds, the reviewers'
   blockers and majors, the publisher's fix rounds, the PR's red CI rounds, tool calls and API list $; per side the
   per-task means. Read it with `--since 2026-09-30T00:00:00Z` (the A/B's window), so the baseline holds the Opus
   tasks before and beside the trial: only an issue with a `Size:` line can be in it (on 2026-10-08, 24 of the 157
   `area:tooling` issues since 2026-09-28 said S or XS; most said no size), and the manager gives every qualifying
   issue one.
4. **Stop rule** (`metrics`' `TRIAL_*` constants, its advice line).
   - **Drop early** after **2** trial tasks red twice, or once **4** or more trial tasks have **1 or more** blockers
     and majors per task over the baseline's.
   - **After 6 trial tasks**, keep Sonnet when red runs, verify reds, publisher fix rounds and CI fix rounds per task
     are each no worse than the baseline's and its $ per task is lower; otherwise drop it.
   - The verdict is advice. The manager posts it on #302 with the table, and the engineer decides. A keep becomes a
     standing launch habit only by a further amendment of the model-guard ADR after his yes; a drop ends the
     `models.implement` launches and changes nothing else.
5. **Cost.** No agent more: a trial launch costs less when it holds. A red run costs a relaunch (about 0.6% of the
   week at the meta track's cost per task), which the early stop bounds at a few runs.

## Alternatives
- **A paired A/B (an Opus and a Sonnet implementer on each task):** doubles the largest cost, and two diffs of one task
  cannot both be published; the reviewer A/B could pair because both reviewed one diff.
- **Sonnet for every implementer:** engine code and the information-leak invariant are where a weaker diff costs most;
  out of scope until small tasks show the quality.
- **A default in `issue-task`:** the model-guard ADR forbids a script default that names a model.
- **A blind judge of the diffs:** the run's own signals (reds, findings, fix rounds) already score an implementer, and
  a judge would add an Opus agent per run.

## Consequences
- The runs are not paired (different tasks), and six tasks are few: the advice is a signal for the engineer, as the
  publisher's scorecard was.
- The baseline mixes areas (the game track's Size S tasks with the meta track's), so its findings and fix rounds may
  differ from tooling alone; the per-task table lets the engineer compare like with like. It is small: most issues
  carry no `Size:` line, and a task without one is left out rather than guessed.
- `models.implement: "sonnet"` stays possible after the trial only where the kickoff allows it (orchestrate-stage §3).
