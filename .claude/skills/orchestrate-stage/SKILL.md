---
name: orchestrate-stage
description: Run a whole prime-game stage or list of issues as the manager session - one issue-task workflow per task, at most three at a time, while the engineer merges and answers. Use for an "ultracode" kickoff that names a stage or a list of issues, "оркеструй етап", "run stage N", or "продовжуй" in a session that already manages a stage.
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(gh issue view *)
  - PowerShell(gh issue view *)
  - Bash(gh issue list *)
  - PowerShell(gh issue list *)
  - Bash(gh pr list *)
  - PowerShell(gh pr list *)
  - Bash(gh pr view *)
  - PowerShell(gh pr view *)
  - Bash(gh pr checks *)
  - PowerShell(gh pr checks *)
---

# Orchestrate a stage (docs/AGENT_WORKFLOW.md §7.1)

You are the **manager**: you plan, launch and watch workflows, relay questions and report. Substantive work (code,
docs, reviews, publishing) runs inside workflows; your own inline work is `start`, trivial rebases, posting answers
and issues. Talk to the human in their chat language, in plain words; everything on GitHub and in the repo is
English. Commands use `tools\run.cmd`; in Git Bash `tools/run.sh`. The method and its history:
[ADR](../../../docs/decisions/2026-09-30-orchestrator-session.md).

## 1. The kickoff
One message from the human with `ultracode` in it (template in §10). It must state:
- the scope (issue numbers, fillers) and the plan issue to report on;
- the order and dependencies: which task stacks on which (`start --base`), which waits for a merge;
- the concurrency cap (default three tasks at once) and "one task = one workflow" with per-agent bounds
  (implementer about 250 tool calls, reviewers about 60, publisher about 150);
- explicit approval to exceed the size guideline (`issue-task` runs up to 5 agents; `small` means fewer than 5)
  and the cost for the whole stage, so you do not ask before each workflow;
- the rules: only humans merge; no agent closes issues; each agent only in its worktree; temporary files in the
  scratchpad or `tests/scratch/`; Godot windows only through `shot`; a game rule no ADR settles becomes options
  under "Needs the engineer"; `content/` and `levels/` files are provisional;
- the engineer's standing decisions to honour, with where each is recorded; known traps; what to drop first;
- reporting: a comment on the plan issue after each wave; stop with a comment when nothing more can run without
  merges; "продовжуй" resumes after a check of the live state.
Something missing: ask once, batched, with a recommendation for each item. Never launch before the approval.

## 2. Before the first launch
1. `tools\run.cmd doctor --quick`. Read the plan issue, every issue in scope with its comments, the handoffs they
   build on, and the ARCHITECTURE sections and ADRs they name.
2. Write a state file in your session scratchpad, e.g. `manager/state.md`: running runs (runId, issue, worktree,
   the exact args file), the queue, ownership splits, merge order, open questions. Keep it current: it survives
   compaction and is what you resume from. Keep each task's args in its own JSON file next to it.
3. Find the files that tasks running in parallel will all touch (mode `.tres` files, `docs/ARCHITECTURE.md`,
   registries, event folders) and split ownership **up front**: who owns which class, which task creates which
   shared class (same path and class name if two may create it), whose deal places what. Otherwise add/add
   conflicts and duplicate work follow.

## 3. Launching a task
1. `tools\run.cmd start <n>` (with `--base <parent branch>` for a stacked task) in **your** session, never in an
   agent. Take the `WORKTREE <path>` line.
2. Launch the saved workflow `issue-task` (`.claude/workflows/issue-task.js`; the Workflow tool with
   `name: "issue-task"`, or `scriptPath` to that file in the main checkout) with `args` as a JSON object:

| arg | what |
|---|---|
| `n`, `title`, `wt`, `branch` | the issue, its title, the worktree path, the task branch (required) |
| `base` | the PR base: `main`, or the parent's branch for a stacked task |
| `notes` | the task's specifics, the engineer's answers that apply, ownership splits, merge order (required) |
| `coord` | what runs in parallel now and which shared files to touch minimally |
| `decisions` | the engineer's standing decisions, each with where it is recorded (every task that they touch) |
| `reading`, `testing` | override the default reading list and test expectations |
| `design` | `true` for a docs-only design task: options for the engineer, a proposed issue split, the netcode reviewer, effort xhigh |
| `effort`, `plan`, `manager` | implementer effort (default high), the plan issue (default 30), your name in prompts ("the M3 manager session") |

The workflow: implementer (commits, verify green, never publishes) → fresh reviewers in parallel, chosen from the
changed paths (`code-reviewer` always; `netcode-security-reviewer` for `core/ server/ net/` or a design task;
`godot-api-checker` for `.gd .tscn .tres`) → publisher (fixes blocker, major and cheap minor findings, `publish`,
PR with a findings table, "Needs the engineer" and "Merge order", CI watch with at most two fix rounds, handoff,
board In review). Every agent writes temporary files only under the scratchpad subfolder `a<n>/`.

Notes that worked: say which PR a needed file comes from if it is unmerged ("build with fixtures, fetch and rebase
once it lands"); repeat rules that force fixture updates in every later PR (neutral class defaults with the numbers
in the data); name a task's merge order relative to the other open PRs.

## 4. On each completion
Read the result (`pub.pr_url`, `ci_green`, `needs_engineer`, `human_steps`, `not_fixed`). Tell the human what is
ready to merge and in which order, and explain each "Needs the engineer" item in plain words: a concrete scenario of
what goes wrong, the options, your recommendation, numbered so they can answer "1A, 2B". Then fill the free slot.

**Answers.** Post them in English on the PR and the issue ("The engineer's answers (chat with the manager session,
<date>)"). Carry an answer that belongs to a later task to that issue as a comment; open a new issue for a decision
that changes shared design. An answer with two readings that build different things is read back in one sentence
(AskUserQuestion) before it is recorded; if the human dismisses the question and explains, read back again. An
answer that changes a published PR: a trivial one inline in its worktree (then `publish`); otherwise `issue-task`
again for that issue with the answers in `notes` (its agents find the branch and the PR and continue).

## 5. Merges and rebases
- Only humans merge. Tell them the order; for stacked PRs say "merge the parent first, and only into main" (a child
  merged into its parent's branch gets linearised by the next rebase).
- After each merge: `gh pr list --state open --json number,headRefName,baseRefName,mergeStateStatus` (`UNKNOWN` just
  after a merge: ask again). A child still based on the merged parent: `gh pr edit <child> --base main`.
- Never touch a worktree whose workflow is still running.
- A docs or test-list conflict: resolve inline in that task's worktree (`git fetch`, `git rebase origin/main`, keep
  both sides, `verify`, `tools\run.cmd publish`), then a PR comment listing the conflicts.
- A semantic conflict (two PRs creating the same classes, a changed interface): the saved workflow `pr-rebase`
  with args `{n, pr, wt, branch, base, why, steps, focus}`: rebase agent → fresh reviewer(s) → a fix agent only
  for a blocker or major. `why` names what merged and the PRs and handoffs to read; `steps` says which side's
  files and payloads to keep.

## 6. Reporting and keeping slots busy
- After each wave, a comment on the plan issue: merged PRs, decisions recorded (with links), in progress, order from
  here, batched questions (numbered, recommendations), housekeeping for a human. Never edit the plan issue's body.
- Keep every slot busy: when the next task waits for a merge, start what does not depend on it (a task's
  independent part with a "fetch and check whether X is on origin/main" step, fillers, the next milestone's design
  task). When nothing more can run without merges, say so in a plan-issue comment and stop.
- Tasks that edit `.claude/settings*.json` hit an ask rule in every mode: run them only while the human is present.

## 7. Resume after a crash, a restart or a plan limit
- A workflow throws when an agent returns nothing. Relaunch it the same way (name or `scriptPath`) with
  `resumeFromRunId` and the **same args** (from the args file): finished agents return their saved results.
- After a PC restart or a crashed session: reopen the same session (`claude --resume`, or the app) and resume each
  run as above. In a new session there is no run to resume ("nothing to resume"): launch `issue-task` afresh with
  the same args; the implementer finds earlier commits and uncommitted files through `git status`, the publisher an
  existing PR through `gh pr list`.
- A plan limit: with `autoContinueAtUsageLimit` on, a workflow's agents wait for the reset and continue on their
  own; otherwise they fail and you resume after the reset. While you wait (a limit, a long run, a merge), set a
  timer with a background `sleep <seconds>` (Bash, `run_in_background`); it wakes you when it exits. A finished
  workflow wakes you anyway.
- "продовжуй" after any break: re-read the live state first (`gh pr list`, the plan issue's latest comments, each
  running run), then the state file, then continue.

## 8. Notifications and housekeeping
- When the human is needed (a PR to merge, questions, a stop), end your turn with a short summary and send a
  PushNotification. It is suppressed while the human is active in the session, and the desktop app only flashes its
  icon while its window is in use; a PowerShell toast tests whether Windows notifications work at all.
- Merged tasks' worktrees: list `tools\run.cmd worktree-done <n>` (from `D:\prime-game`) for the human in the
  wave comment; a worktree whose branch never reached main but whose work did (merged into a parent) says so.

## 9. Gotchas from 2026-09-30
- The scratchpad is shared by all agents of all workflows: one overwrote another's `pr_body.md`. Hence `a<n>/`.
- `publish` can fail right after a rebase that changed `tools/runner` (verify ran the old modules): run it again.
  "Could not resolve hostname github.com" is transient: `git ls-remote origin`, then again.
- Intermediate commits after a rebase may not compile (the fix lands at the tip): bisect by PR; merge commits keep
  PRs as units.
- Two verify runs at once in different worktrees can collide (GdUnit4 files under `user://`, a busy port): the
  agents rerun once before debugging.
- Agents see the human's mid-turn messages relayed; they ignore requests outside their task. Tell the human that a
  message meant for you should go to your session, not to a running workflow.
- Numbers: about 20 workflows in one day; 25 to 60 minutes and 450k to 900k subagent tokens per task workflow.

## 10. Kickoff template
The human copies it, edits the lists and sends it. Example filled in for M3:

```text
ultracode: оркеструй етап 3 (M3, мережа) за скілом orchestrate-stage. Ти менеджер: одна задача = один
workflow issue-task, не більше трьох одночасно.

Звідки починаємо: моє рев'ю дизайну #89 (PR і handoff на #89) — прочитай мої відповіді там. Спочатку відкрий
M3-задачі з handoff #89 (3c host session, 3d бот-харнес і тест на витік інформації, 3e команди host і join,
і решту з handoff) з моїми правками з рев'ю, покажи мені список і порядок, і чекай мого "так".

Обсяг: задачі з handoff #89; філери: #64 (PR #90, якщо ще не змерджений), #66 2j повний матч — після #64.
План і звіти: коментар на #30 після кожної хвилі; тіло #30 не чіпай.
Порядок: як у handoff #89; стек через start --base лише там, де handoff каже "depends on" на незмерджений PR.
Межі: implementer ≤ 250 викликів, рев'юери ≤ 60, publisher ≤ 150. Дозволяю перевищити size guideline
(до 5 агентів на workflow) і витрати на весь етап — не питай перед кожним workflow.
Правила: мерджу тільки я; issues не закривати; кожен агент лише у своєму worktree; тимчасові файли —
scratchpad/a<n>/ або tests/scratch/; вікна Godot лише через shot; правило гри, якого нема в ADR, —
варіанти з рекомендацією в "Needs the engineer"; файли content/ і levels/ — попередні, я затверджую їх у PR.
Мої рішення: ті, що в ADR, і мої відповіді в коментарях #89, #30, #58, #60, #79 (новіші важать більше).
Пастки: publish після rebase, що змінив tools/runner, — ще раз; задачі, що правлять .claude/settings*.json, —
лише коли я поруч; рендерер Windows (d3d12 чи vulkan) — моє рішення, не вирішуй.
Що відкинути першим, якщо скінчиться бюджет: філери, потім 3e.
Коли без моїх мерджів далі нічого не піде — коментар на #30 і стоп. "продовжуй" — перевір живий стан і далі.
```

Before launching the first workflow, restate in the human's language: the waves, the ownership splits, the merge
order, the agent count per workflow and the rough cost (§9 numbers), and wait for their yes if the kickoff says so.
