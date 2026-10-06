---
name: night-audit
description: One read-only audit lens a night for prime-game (docs drift; coverage, flaky tests, dead code by weekday), every finding re-checked by a skeptic before it becomes an issue, and a summary on the "Night jobs" issue. Use as the prompt of the engineer's nightly Desktop scheduled task, or when a human says "night audit" or runs /night-audit with a lens.
argument-hint: "[docs-drift | coverage | flaky | dead-code]"
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(git fetch origin)
  - PowerShell(git fetch origin)
  - Bash(git switch --detach origin/main)
  - PowerShell(git switch --detach origin/main)
  - Bash(git status*)
  - PowerShell(git status*)
  - Bash(git rev-parse *)
  - PowerShell(git rev-parse *)
  - Bash(git worktree list*)
  - PowerShell(git worktree list*)
  - Bash(git log *)
  - PowerShell(git log *)
  - Bash(git show *)
  - PowerShell(git show *)
  - Bash(gh issue list *)
  - PowerShell(gh issue list *)
  - Bash(gh issue view *)
  - PowerShell(gh issue view *)
  - Bash(gh issue create *)
  - PowerShell(gh issue create *)
  - Bash(gh issue comment *)
  - PowerShell(gh issue comment *)
  - Bash(gh run list *)
  - PowerShell(gh run list *)
  - Bash(gh run view *)
  - PowerShell(gh run view *)
---

# Night audit (docs/AGENT_WORKFLOW.md §15)

Unattended: nobody answers at night, so never ask in chat and never wait for a reply. Lens: $ARGUMENTS (empty: by
weekday below). Work in English. Root `CLAUDE.md` applies in full.

## Bounds (state them in the summary)
- **One lens** a run. **At most 2 agents**: you (the auditor) and one skeptic subagent. **About 100 tool calls**
  together: you about 70, the skeptic about 30. About $10 list a night.
- **Read-only on the repo:** never Edit or Write a tracked file, never commit, push, open a PR, run `publish` or
  `start`, and never close, reopen or edit an issue. The only writes: `gh issue create` (confirmed findings, at most
  5 a night) and `gh issue comment` on the "Night jobs" issue. Issue bodies go in the gitignored `tests/scratch/`
  of your worktree (`tests/scratch/night-audit/`), nowhere else.
- **Out of budget** (about 70 of your calls used): stop collecting; re-check the strongest 8 candidates at most; the
  rest go in the summary as "not re-checked", never as issues.
- Lenses beyond docs drift are the first thing to drop: the engineer drops them by setting every weekday below to
  `docs-drift`.

## As a workflow
A manager may run one lens as a workflow instead, each `agent()` call with its lean type (AGENT_WORKFLOW §5, #466).
Bounds: 3 agents, about 100 tool calls split among them (auditor about 60, skeptic about 30, filer about 10), the
rest of the bounds above. Steps 1 and 2 are the script's or the manager's, not an agent's: a workflow agent starts in
the manager's checkout, where step 1's own-worktree test would skip the run and a lean type may not switch
branches. The manager makes a detached worktree at origin/main, finds the Night jobs issue and the lens (and stops
when today's summary exists), and puts the worktree's `cd`, the origin/main sha, the lens and the issue number in
every prompt. Then: the auditor (step 3) `{agentType: 'lean-reader'}`, on Sonnet; the skeptic (step 4) `{agentType:
'night-skeptic'}`, as above; the filer (steps 5 and 6) `{agentType: 'lean-writer', model: 'sonnet'}`. Lean agents
have no Skill tool: each prompt names this file and the steps that agent follows.

## Steps
1. **Where you are.** Find the Night jobs issue first: `gh issue list --state open --search "\"Night jobs\"
   in:title" --json number,title`, the one titled exactly "Night jobs" (none: create it as in step 6 when you first
   need it). `git rev-parse --git-dir` and `git rev-parse --git-common-dir` must differ (a linked worktree: the
   scheduled task's worktree toggle). If they are equal, or `git status --porcelain` shows changes, comment
   "night-audit skipped: not in a clean worktree of its own" on the Night jobs issue and stop. Otherwise
   `git fetch origin` and `git switch --detach origin/main`: you audit what is on `main`.
2. **The lens.** An argument names it; else the local weekday: Monday, Thursday, Saturday `docs-drift`; Tuesday
   `coverage`; Wednesday, Sunday `flaky`; Friday `dead-code`. If today's summary comment ("night-audit <lens>,
   <today's date>") is already on the Night jobs issue (a catch-up run after a missed one), stop.
3. **Candidates.** Follow the lens below. Each candidate: one claim, the file and line, and the evidence (what the
   doc or code says, and the command or file that shows otherwise). Mechanical evidence first (a missing path, an
   empty search); judgement second. Skip anything an open or closed issue already reports: `gh issue list --state
   all --search "<file or name> in:body"`.
4. **Skeptic.** One subagent of type `night-skeptic` (read-only by its frontmatter; it may run `git log/show`,
   `gh run list/view` and `gh issue list/view`), all candidates numbered in one prompt with the lens, the
   origin/main sha and "about 30 tool calls". Paste the evidence verbatim into each candidate (the command and its
   output lines), so a log the skeptic cannot fetch again is still judged. It answers CONFIRMED, REFUTED or UNSURE
   per candidate. Only CONFIRMED becomes an issue; UNSURE and REFUTED go in the summary.
5. **Issues.** One per confirmed finding, `gh issue create --title "<area>: <lens>: <what>" --label area:<x>
   --body-file tests/scratch/night-audit/<k>.md` (add `--label documentation` for docs drift). The area is the
   owner of the path to fix: `core/` core, `server/` server, `net/` net, `client/` client, `voice/` voice, `content/`
   `docs/GDD.md` `docs/design/` content, `levels/` level, and `tools/ .github/ .claude/ CLAUDE.md
   docs/AGENT_WORKFLOW.md` tooling; `tests/<x>/` and an `ARCHITECTURE.md` section take the area of the code they
   cover. Body: `## Finding` (one sentence), `## Evidence` (file:line, commands and their output), `## Suggested fix`
   (one or two sentences; a designer-owned path says "for the designer"), the skeptic's verdict line, and last
   `Found by: night-audit <lens> (<date>, origin/main <short sha>)`.
6. **Summary** on the Night jobs issue (`gh issue comment <n> --body-file ...`); if no issue has that exact title,
   create it once with `--label area:tooling` and the body the nightly workflow uses. First line
   `night-audit <lens>, <date>, origin/main <short sha>`, then: candidates, confirmed (issue links), refuted,
   unsure and not re-checked (one line each), inputs that were missing, tool calls used by you and the skeptic.

## Lenses
Not findings in any lens: history (`docs/history/`, `docs/interventions/` entries, an ADR's Context and
Alternatives), items marked as later or open (`[M0]`, "later", open questions, 👤 steps), style, and `addons/`.

**docs-drift** (first; the default). Docs that say something the code or the repo no longer does. Start from what
changed: `git log --since=7.days --name-only --format= origin/main`, then the docs that name those files, commands
or classes: root and nested `CLAUDE.md`, `.claude/rules/`, `.claude/skills/`, `.claude/agents/`,
`docs/AGENT_WORKFLOW.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`. Checks: a path in backticks that does not exist;
a runner command or flag missing from `tools/run.sh <command> --help`; a class, function, signal or constant the
code no longer has (Grep); a number (timeout, port, budget, count) that differs from the code's constant; a link
to a missing file; a "Built in" or "Tests" line naming a test that does not exist.

**coverage.** Behaviour with no test, in files changed in the last 14 days (`git log --since=14.days`): a public
class or method in `core/ server/ net/ client/ voice/` that no test under `tests/` names, a runner command or rule
in `tools/runner/` with no test in `tools/runner/tests/`, a "Tests" line in `ARCHITECTURE.md` that claims more than
the tests do. A finding names the behaviour and the test to add, never a percentage.

**flaky.** Tests or steps that failed and then passed on the same content, last 14 days. Sources: the nightly runs
(`gh run list --workflow nightly.yml --limit 14 --json databaseId,conclusion,createdAt,headSha,url`; for a failed
one, `gh run view <id> --log` lines with `flaky:` or `failed in every run:` from `test --repeat`); CI reruns that
turned green on the same `headSha` (`gh run list --workflow ci.yml --limit 50 --json
databaseId,attempt,conclusion,headSha,url`); and the verify history `tools/out/logs/verify-history.jsonl` of the
main checkout and every worktree (`git worktree list`): one JSON line per `verify` with `start`, `worktree`,
`branch`, `head`, `tree` (only with a clean tree), `status` and `steps` (`name`, `lane`, `status`, `seconds`). A
step FAILED and then passed with the same `tree` is evidence. A missing history file goes in the summary.

**dead-code.** A class, function, signal, constant, scene or resource that nothing references outside its own
file (Grep the name across the repo, without `addons/` and `docs/history/`), or a runner function with no caller.
Content API classes and anything loaded by name from `.tres`, `.tscn` or a string path are alive when such a
reference exists. A finding shows the definition and the empty search.
