# LENS facts

OVERALL:
I checked the draft against the corrected research notes and, for claims that carry weight, against the primary sources today (2026-09-28). Most of it matches the corrected notes. I confirmed these local claims:
- Claude Code: the running build is 2.1.281 (%APPDATA%/Claude/claude-code/2.1.281/claude.exe); the PATH CLI is 2.1.195.
- Shell: every PowerShell execution-policy scope is Undefined, and the agent process runs with Bypass. `tools\run.cmd` resolves from PowerShell.
- Git ignore: the global excludes line has a backslash (`**/.claude\settings.local.json`).
- Tools: gh 2.88.1 without the project scope, git 2.49, Node 20.19.5. There is no pwsh and no global filter.lfs.
- Disk: C: has 9.8 GB free.
- Versions: Godot 4.7.2.stable.official.ed1daf0bf, gdformat 4.5.0, GdUnit4 6.2.1.
- Transcripts: claude-code-guide agents ran on Haiku, workflow agents on Opus 5.5.
- Issue #90077 is open with the 'has repro' label. Discussion #9288 is open with no answer.
- The Superpowers MIT line reads 'Copyright (c) 2025 Jesse Vincent'.

Four load-bearing problems:
1. **Protected paths.** The draft says writes to `.claude/` 'always prompt'. The docs say Auto mode routes them to the classifier, Bypass allows them, and a session-wide 'allow .claude edits' option exists. The guard-hook and git-hook tamper protection therefore holds only in Manual and Accept edits.
2. **The two guard layers are overstated.** The runner is allowlisted and `tools/` is editable without a prompt, so git or gh calls made inside scripts get past both the guard hook and the pre-push hook. That matters most for D22 option D.
3. **Effort policy.** The per-prompt `ultracode` keyword keeps the session effort (medium on Opus 5.5). It does not give KICKOFF's xhigh. Also, 2.1.284, released today, made ultracode a toggle that no longer forces xhigh.
4. **D11 rationale contradicts §5.2.** §5.3 says an `Agent(model:*)` deny would block workflow stage models. §5.2 and the research say Agent(model:...) rules cannot see workflow stages.

The remaining findings are smaller:
- Version drift since 2.1.284: `sonnet` now resolves to Sonnet 5.5.
- The GitHub merge=union claim is tagged [doc] but rests only on a community discussion.
- The tested pre-push hook blocks the force-with-lease push that `run publish` needs.
- The checker caveats (it starts autoloads; a hang can end in fail-open) are missing.
- The #117362 'Unrecognized UID' false-fail is missing.
- The .worktreeinclude and LFS caveats do not apply to manual `git worktree add`.
- Small errors in the alternatives (Spec Kit, the Superpowers version, GSD).
- Fable billing is stated without the default usage-credits-off condition.
- Wrong: '/code-review has no project rules'.
- `s` in `/workflows` is not confirmed in Desktop.
- The gh security update is marked 'optional'.

I edited no project files. The scratch files I wrote are under scratchpad/review_fact.

## [facts-1] MAJOR — §7 intro, §7.2, §8.1, D16/§8.3
QUOTE: `.claude/` is a protected path, so writes there always prompt, even for agents.  /  Writes to `.claude/`, `.git/` and `.idea/` always prompt (protected paths). That is intended.  /  committed under `.claude/githooks/` (a protected path)
PROBLEM: This is false as stated. Protected-path writes prompt only in Manual and Accept edits. Auto mode routes them to the classifier, and bypassPermissions allows them. The prompt also offers 'Yes, and allow Claude to edit files in this project's .claude folder for this session', which lifts protection for the whole session after one click. The draft uses this protection as the tamper guard for guard.py, the PostToolUse hook and the git pre-push hook, and §8.3 says 'Auto mode is fine later'. In Auto mode, an agent edit that disables the guard is judged by the classifier, not by a human.
EVIDENCE: https://code.claude.com/docs/en/permission-modes#protected-paths. The table reads 'default, acceptEdits: Prompted; auto: Routed to the classifier; dontAsk: Denied; bypassPermissions: Allowed', and the page documents the session-scoped '.claude folder' option. Research permissions.md mf-04 says the same.
FIX: 1. Reword the three passages to: 'prompted in Manual/Accept edits; classifier-reviewed in Auto; allowed in Bypass; one prompt can allow all .claude edits for the session.'
2. In D16/§8.3, state that moving to Auto removes human review of edits to `.claude/hooks` and `.claude/githooks`.
3. Add a mitigation, for example:
   - a guard-hook rule that returns `ask` (never allow) for Edit/Write under `.claude/hooks/**`, `.claude/githooks/**` and `.claude/settings*.json`;
   - a `doctor` check that hashes these files against `origin/main`;
   - never picking the session-wide '.claude folder' option.

## [facts-2] MAJOR — §7.2 Guard layers, §8.1/§8.2 runner allow rules, §13.1 option D
QUOTE: Real enforcement therefore needs two layers.  /  It covers git pushes from **any** tool ... It is bypassed by `--no-verify` and by overriding `core.hooksPath`, which is why the guard hook denies both.  /  D Private, Free | $0 | **None** server-side; only §7.2 guards, for agent actions
PROBLEM: This overstates what the two layers enforce, even for agent actions.
- The PreToolUse guard sees only the command text of a Bash/PowerShell tool call.
- `tools\run.cmd *` / `tools/run.sh *` are allowlisted. `tools/run.py` and the test and bot scripts are ordinary files under `tools/` and `tests/`, which Accept edits auto-approves without a prompt.
- So an agent can edit the runner or a test and have it run `git -c core.hooksPath=/dev/null push origin main`, `git push --no-verify`, `gh pr merge --admin` or `gh api -X DELETE`. The guard hook sees only `tools\run.cmd publish`, and the pre-push hook is bypassed from inside the script.

The draft calls `Bash(python *)` arbitrary code execution. An allow rule on an agent-editable runner is the same thing, so 'Godot, Python and gdtoolkit are allowed only through the runner' is not a boundary. The 'Remaining gaps' list leaves this out, and D22 option D is presented as enforcing rules for agent actions.
EVIDENCE: - Research permissions.md mf-10: Read/Edit rules 'do NOT cover arbitrary subprocesses such as a Python task runner'.
- gaps.md gap1 (a)/(b) and gap1-19/20: `--no-verify` and `-c core.hooksPath=/dev/null` bypass the pre-push hook.
- gap1-22: rules match the text as written.
- permission-modes.md: acceptEdits auto-approves file edits in the working directory except protected paths.
- The draft's own §8.1 says interpreter wildcards are arbitrary code execution.
FIX: 1. Add this bypass to §7.2 'Remaining gaps' and to the D22 option D row: on private Free, nothing reliably stops an agent-authored script from pushing to main or admin-merging.
2. Mitigations to list as options:
   - the runner itself refuses `--no-verify`, `-c core.hooksPath` and `--admin`, and uses an absolute hooks path;
   - the guard hook returns `ask` for Edit/Write to `tools/run*` and `tools/githooks`, or these files move under `.claude/`;
   - `doctor` verifies `git config core.hooksPath` each session.
3. Say plainly that only options A–C (server-side rulesets) close this gap.

## [facts-3] MAJOR — §10 Effort and orchestration policy (D21), §12 size words
QUOTE: | Foundation work with no mid-task human input ... | **`ultracode` keyword in that one prompt** (per task, not the session-wide `/effort ultracode`) | Opus 5.5 |  /  Ultracode disables the large-workflow warning and the concurrency cap.  /  `workflowSizeGuideline` stays at the default (medium).
PROBLEM: 1. KICKOFF §10 defines ultracode work as 'multi-agent, xhigh'. The per-prompt keyword starts a workflow 'without changing the session's effort level'. Opus 5.5 defaults to medium, so as written, foundation work runs at medium unless the human also raises effort. The table never says to.
2. The warning and cap exemptions apply only 'while [the ultracode setting] is on'. They do not apply to the keyword the policy recommends. The concurrency cap they lift is the Agent-tool subagent limit, not the workflow runtime's 16-agent limit.
3. The size-guideline default is `small` on Pro (v2.1.271+), not medium. The designer's plan is unknown.
4. Claude Code 2.1.284 (released 2026-09-28 18:02Z) 'Changed Ultracode into its own toggle in /effort ... it no longer forces xhigh effort and stays on at any effort level', so 'ultracode = xhigh' no longer holds even for the setting.
EVIDENCE: - https://code.claude.com/docs/en/workflows 'Ask for a workflow in your prompt': 'To run a single task as a workflow without changing the session's effort level, include the keyword ultracode'.
- Same page, 'Let Claude decide with ultracode': 'these checks don't apply while it's on'.
- Same page, 'Set a size guideline': 'The default is medium, or small when you're signed in on a Pro plan with Claude Code v2.1.271 or later'.
- CHANGELOG.md 2.1.284 (raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md; release published 2026-09-28T18:02:03Z).
- Research operations.md effort-01/mf-04.
FIX: 1. Write the foundation row as: 'set effort to xhigh (Ctrl+Shift+E), then use the `ultracode:` keyword for that one prompt; return to high/medium afterwards'.
2. Drop the exemptions bullet, or scope it to the session-wide setting.
3. Change the size default to 'medium (small on Pro)'. Consider pinning `workflowSizeGuideline` explicitly if both humans should behave the same.
4. Add a version note: on 2.1.284 and later, ultracode no longer implies xhigh, so the effort must be set separately.

## [facts-4] MAJOR — §5.3 Routing verification (D11) vs §5.2
QUOTE: Adding an `Agent(model:*)` deny would stop per-call model overrides, but also stop workflows from choosing cheaper stage models. Not recommended.
PROBLEM: This contradicts the draft's own §5.2, which says an `Agent(model:...)` deny 'misses frontmatter, full IDs, inheritance and workflow stages'. It also contradicts the research: the Workflow tool's input has no model field, and stage models live inside the script's `agent({model})` calls, which no `Agent(model:...)` permission rule can see (inferred in the research, and consistent with workflows.md). The only stated reason for rejecting the deny option is therefore unsupported. If the deny does not touch workflows, it has no downside for workflows. It would still leave workflow-stage routing unverified, which `agents-check` must cover.
EVIDENCE: - Research gaps.md gap4-23 and gap4-24.
- subagents.md mf-03 (the older claim), superseded by gap4.
- https://code.claude.com/docs/en/workflows: a stage model 'counts as the per-invocation model'. The spawn is a runtime `agent()` call, not an Agent tool call.
- Draft §5.2 bullet 2.
FIX: 1. Pick one statement and tag it [inferred], e.g. 'An Agent(model:*) deny blocks per-call overrides by the main agent. It does not appear to affect workflow stage models (undocumented).'
2. Re-evaluate D11 on that basis. Adding the deny may now be the better option, with `agents-check` covering workflow agents.
3. Test it on M0 before relying on it.

## [facts-5] MINOR — §0.1, §5.1 roster, §5.3 agents-check, §15
QUOTE: The `claude` on PATH is **2.1.195** (June 2026, about 88 releases behind the latest 2.1.283).  /  **sonnet** (Sonnet 5)  /  Use the `haiku` alias, which Claude Code re-points, never the dated ID.
PROBLEM: The model facts are now out of date:
- 2.1.284 was released 2026-09-28 18:02Z. It 'Added Claude Sonnet 5.5 (claude-sonnet-5-5), now the default Sonnet model on the Anthropic API', and model-config.md now maps `sonnet` to Sonnet 5.5.
- When Desktop picks up 2.1.284, `godot-api-checker` silently moves to Sonnet 5.5.
- An `agents-check` that asserts exact model IDs (e.g. claude-sonnet-5) will fail.
- Sonnet 5.5's cybersecurity fallback is Sonnet 5, not Opus 4.8.
- Separately, 'Claude Code re-points' the haiku alias is not documented. model-config.md only says `haiku` 'Uses the fast and efficient Haiku model', and Haiku 4.5's retirement date is 'not sooner than 2026-10-15'.
EVIDENCE: - CHANGELOG.md 2.1.284.
- https://code.claude.com/docs/en/model-config (aliases table: Anthropic API `sonnet` = Sonnet 5.5; safety fallback list).
- `gh release view v2.1.284 --repo anthropics/claude-code` gives publishedAt 2026-09-28T18:02:03Z.
FIX: 1. Update 'latest' to 2.1.284.
2. Write the roster as `sonnet` (Sonnet 5 on ≤2.1.283, Sonnet 5.5 on ≥2.1.284).
3. Make `agents-check` assert the model family (the claude-sonnet-*/claude-haiku-*/claude-opus-* prefix), not exact IDs.
4. Mark the haiku re-pointing as [inferred], and add a `doctor`/`agents-check` alarm if a haiku agent is served by another family after 2026-10-15.

## [facts-6] MINOR — §3.3 Interventions (D4)
QUOTE: **Tested [local] and checked [doc]:** ... `merge=union` helps only local git. GitHub's mergeability check and merge button ignore `.gitattributes` (open community discussion #9288).
PROBLEM: This is an overclaim. The local test covers only the git side. No GitHub doc states that the mergeability check ignores merge drivers: the research says 'GitHub's docs never say this outright'. The evidence is an open feature-request discussion, a quoted 2017 support reply and one third-party issue. The research also notes that confirming it needs a real GitHub test, which has not been run.
EVIDENCE: - Research gaps.md gap6 (short answer, gap6-03/04/05/19).
- GraphQL check today: community/community discussion 9288 is `closed:false`, `answer:null` (a feature request, not documentation).
FIX: Retag the GitHub half as [inferred: community reports #9288, felix-run/felix#313; untested], and keep [local] for the git conflict result. The D4 recommendation does not depend on it, since one file per entry avoids the question.

## [facts-7] MINOR — §7.2 Git pre-push hook; §4.5 step 4
QUOTE: **Tested [local], git 2.49:** it blocked a push to main, `+main`, `--force`, `--force-with-lease` and `--delete` from both shells ... It covers git pushes from **any** tool, including Rider and a human terminal.  /  pushes the feature branch (force-with-lease is allowed only on the task's own branch)
PROBLEM: 1. The tested hook blocked `--force-with-lease` on a feature branch (feat/1). `run publish` needs exactly that push after a rebase, and the git hook cannot tell a runner-initiated push from any other. The test result supports a different hook than the one the design needs. The research flagged this as an open policy choice.
2. Only `push origin main` and `--delete` were run from PowerShell; `+main`, `--force` and `--force-with-lease` were tested from Git Bash only. This is harmless technically but overstated.
3. Rider coverage is inferred, not tested.
EVIDENCE: Research gaps.md gap1-20 (the exact commands and shells) and gap1 (a): 'cannot tell a force-with-lease rebase of your own branch from a destructive force ... Policy choice', and '(Rider is inferred)'.
FIX: 1. State the hook policy needed: allow non-fast-forward pushes only to refs matching `<area>/<n>-*` and never to main, or require a fresh branch name after a rebase.
2. Say the M0 test must re-prove this policy.
3. Reword the test claim to list which cases ran in which shell, and mark Rider as [inferred].

## [facts-8] MINOR — §7.1 PostToolUse `.gd` hook, step 3
QUOTE: **Engine parse check** through the project checker script in single-file mode. It runs in `_initialize()`, so autoload references resolve; `--check-only` is not used.
PROBLEM: The claim is correct but leaves out two verified caveats.
1. The `-s` checker instantiates every autoload, so their `_init`/`_ready` run on every `.gd` edit. Future network, mic or voice autoloads would start inside the hook.
2. The draft's own §0.8 says a runtime error inside `_initialize()` hangs forever. A throwing autoload `_ready` or loaded tool script would stall each edit until the 120 s hook timeout, which the hooks docs treat as a non-blocking error, so the hook fails open.

The 'about 1.7–2.0 s' figure was also measured on the bash `--check-only` prototype, not on this design.
EVIDENCE: - Research godot_toolchain.md mf-01 ('The -s checker also INSTANTIATES the autoloads (their _init runs before _initialize and their _ready after)').
- Config corrections, Section 3 ('It instantiates autoloads').
- godot_toolchain-10 (a runtime error in `_initialize` hangs, rc 124).
- godot_toolchain-27 (timing of the bash prototype).
- https://code.claude.com/docs/en/hooks: a hook that cannot finish is non-blocking.
FIX: 1. Add a rule that autoloads must be side-effect-free when a CHECK_MODE user argument is present (or the checker guards against it).
2. Give the checker an inner timeout well below the hook timeout, which exits 2 with 'engine check timed out'.
3. Label the timing as the prototype's.

## [facts-9] MINOR — §11.2 `.tscn`/`.tres` authoring (D19)
QUOTE: `check` then fails on any `UID duplicate`, `invalid UID`, `Missing .uid` or `Unrecognized UID` line.  /  A missing script `.uid` on a fresh clone gets a **new random** uid, which breaks every reference to the old one.
PROBLEM: 1. The research flagged known noise: Godot #117362 prints 'Unrecognized UID' at startup for `uid://` references in project.godot (main_scene, default_bus_layout). The fix was merged for 4.8 only, after 4.7.2. Once the editor sets a main scene by uid, the proposed `check` fails on every run. The draft omits the mitigation.
2. 'Breaks every reference' overstates it. The tested behaviour is an 'invalid UID ... using text path instead' warning, with the reference still loading by path.
EVIDENCE: - Research gaps.md gap3 B (check policy, 'Known noise: issue #117362').
- gap3-35 (PR #123024 merged 2026-09-07, milestone 4.8).
- gap3-17 ('every .tres referencing the old uid printed invalid UID ... using text path instead').
FIX: 1. Add: reference main_scene and bus layout by `res://` path in project.godot, or allowlist those specific lines, until Godot 4.8.
2. Reword to: 'references then warn invalid UID and fall back to their path (check fails on it)'.

## [facts-10] MINOR — §4.2 D7 option A, §4.3 worktree costs
QUOTE: A `settings.local.json` (KICKOFF §6) + `.worktreeinclude` + a repo `.gitignore` entry  /  LFS content may be missing: if Git LFS was installed only for this repo (`git lfs install --local`), worktrees get pointer files until `git lfs pull` is run.
PROBLEM: Both mechanisms apply only to worktrees Claude Code creates (`--worktree`, subagent isolation, Desktop). D8-A instead has the engineer's agent run `git worktree add .claude/worktrees/<n> -b ...` itself.
- For those worktrees, `.worktreeinclude` is not processed, so D7 option A would not deliver settings.local.json even with the .gitignore fix.
- The LFS pointer problem does not occur, because plain git runs the repo-local filter.

The cost and option comparison is therefore off for the recommended worktree method.
EVIDENCE: https://code.claude.com/docs/en/worktrees:
- '.worktreeinclude ... applies to every worktree Claude Code creates with git: --worktree worktrees, subagent worktrees, and parallel sessions in the desktop app'.
- The LFS section is titled 'Git LFS files are pointer files in a worktree Claude Code created'.
- Research gaps.md gap5-05.
FIX: 1. In D7 option A's 'Against' column, add: 'not copied into worktrees made with `git worktree add` (D8-A)'.
2. Scope the LFS bullet to Claude-created worktrees (Desktop or `--worktree`).
3. Note that D7-B has neither problem.

## [facts-11] MINOR — §2 Framework table (options C, E) and the alternatives paragraph
QUOTE: Spec Kit and BMAD were also checked. Both need `uv` and keep their own planning store.  /  **C** Superpowers plugin (v6.4.2, 15 skills), project-wide | `superpowers@claude-plugins-official` enabled  /  `.planning/ROADMAP.md` and `STATE.md` are by design "the single source of truth"
PROBLEM: The draft repeats three uncorrected claims:
1. Spec Kit does not need uv. The verifier corrected this: uv is only recommended, and pipx or `pip install specify-cli` also work, so this machine's Python 3.14 could install it. BMAD does need uv.
2. Installing from `claude-plugins-official` gives v6.4.1, not v6.4.2. The official marketplace pins sha 5bf4e78, whose plugin.json says version 6.4.1.
3. Only ROADMAP.md is called 'the single source of truth'. STATE.md is a 'living position tracker'.
EVIDENCE: - Research gsd.md alt-01 (CORRECTED).
- superpowers.md superpowers-04.
- Local check today: `gh api` on the claude-plugins-official marketplace.json shows sha 5bf4e78011075bcfc0dc295f0724994cd123ee71; plugin.json at that sha has version 6.4.1, and at tag v6.4.2 has 6.4.2.
- gsd.md gsd-09.
FIX: 1. 'BMAD needs uv; Spec Kit needs Python 3.11+ (uv optional)'.
2. Option C: 'v6.4.1 via the official marketplace (pinned; upstream is at 6.4.2)'.
3. 'ROADMAP.md is "the single source of truth" and STATE.md a live tracker'.

## [facts-12] MINOR — §5.2 D10 option B, §0.11, §15
QUOTE: **B** No guard. On Pro, `model: fable` in a shared file bills money from the designer's first review.  /  plan (Pro would make any Fable use cost money)
PROBLEM: Fable on Pro bills usage credits, but usage credits are off by default. With the default setting no money is charged. Instead:
- an interactive consent prompt appears;
- a dismissed prompt mid-session continues on the default model (a silent downgrade);
- for subagent and workflow requests the behaviour is undocumented.

The real money risk is conditional: credits are on, and someone clicked 'continue on Fable' once, after which the prompt never appears again. It is also unconditional under `-p`/SDK. The draft's own account-level bullet ('keep usage credits off ... the only hard stop on money') is correct, which makes these two sentences inconsistent with it.
EVIDENCE: - https://code.claude.com/docs/en/model-config (consent prompt; 'Mid-session, Claude Code continues the turn on your default model'; -p/SDK bills without asking).
- Research gaps.md gap4-04 ('Usage credits are disabled by default'), gap4-05 and gap4-12.
FIX: Reword to: 'On Pro, a Fable subagent either bills usage credits (if credits are enabled and consent was given once), silently runs on another model, or behaves in undocumented ways. Either way, cost or the "strongest model" claim is at risk.' Apply the same condition in §15.

## [facts-13] MINOR — §5.1 roster table, code-reviewer alternatives
QUOTE: or replace it with the built-in `/code-review`, which has no project rules and needs no maintenance
PROBLEM: This is incorrect. The local `/code-review` follows CLAUDE.md like any session. It does not read REVIEW.md, and it cannot take this project's ARCHITECTURE.md or content-API instructions unless they are in CLAUDE.md. The stated disadvantage of the alternative is wrong.
EVIDENCE: https://code.claude.com/docs/en/code-review ('What the review reads and edits'): 'The review follows your CLAUDE.md like any Claude Code session, but it doesn't read REVIEW.md.' Research operations.md codereview-01 note.
FIX: Replace with: '`/code-review` (bundled; follows CLAUDE.md but has no agent-specific prompt or ARCHITECTURE.md checklist, and cannot be model-pinned in frontmatter)'.

## [facts-14] MINOR — §10 workflow rules, §4.6, §5.3 (Desktop is the canonical surface per D6)
QUOTE: Workflow scripts worth reusing are saved to `.claude/workflows/` (press `s` in `/workflows`), so they are committed and reviewable.
PROBLEM: `s` is a key in the terminal `/workflows` progress view. The docs say that in the Desktop app the approval card is 'Once/Always/Deny' and 'The progress view appears in the Background tasks side pane'. Desktop terminal-dialog commands without an argument form reply 'isn't available in this environment'. Whether the save action exists in Desktop is unverified, yet D6 makes Desktop the only surface. The draft already flags `/tasks` as terminal-only but applies no such caution here.
EVIDENCE: - https://code.claude.com/docs/en/workflows ('Save the workflow for reuse'; the Desktop approval card and Background tasks pane).
- https://code.claude.com/docs/en/desktop ('Terminal-dialog commands').
- Research operations.md mf-05/mf-06.
FIX: Add '(terminal UI; unverified in Desktop). Fallback: ask Claude to copy the run's script from ~/.claude/projects/<session>/ into .claude/workflows/<name>.js in a PR.' Verify this in M0.

## [facts-15] MINOR — §13.2 Board and issues (D23), item 3; §4.4 doctor
QUOTE: gh ≥2.97 adds name-based edits plus four security fixes (upgrade optional, 👤)
PROBLEM: The v2.97.0 release notes say 'Users are advised to update gh to version v2.97.0 as soon as possible'. One of the fixes (GHSA-cg6r-mpgc-h9mm) is that `gh auth status` could print part of the token in plaintext for `github_pat_*`, `ghs_*` and `ghu_*` tokens. The draft has `doctor` run `gh auth status` at every session start, and that output lands in agent context and transcripts. The designer's token type is unknown. Calling the upgrade 'optional' understates this.
EVIDENCE: `gh release view v2.97.0 --repo cli/cli` release body (Security section). Research gaps.md gap2-17.
FIX: Recommend upgrading to gh ≥2.97 (still a 👤 action), or have `doctor` parse only `gh auth status --json hosts` scope fields and never echo raw `gh auth status` output until both machines are upgraded.

# LENS kickoff

OVERALL:
Coverage of KICKOFF §8 step 4 is nearly complete. Every required bullet has a section:
- framework (§2), CLAUDE.md hierarchy, budget and interventions (§3);
- session protocol and /clear rules (§4), subagents with models and tools (§5);
- hooks and permission lists (§7, §8, App. A), MCP (§9), effort policy and reviewability (§10);
- designer's agent (§11), phrasing (§12).

Nothing has been applied; `D:\prime-game\.claude` holds only `settings.local.json` and there is no git repo. D4 and D7 are correctly marked ⚠. Plan-mode files staying in `~/.claude/plans` keeps GitHub Issues as the only moving state (KICKOFF §6).

The real problems are in four areas:
1. **Unflagged deviations.** Several departures from the KICKOFF are not marked ⚠: D9, D11, D15/§8.1, D21 and D24.
2. **Decisions made outside the register.** Two choices never appear in §1, so approving "all recommendations" would approve them without the reviewer ever seeing them. One is an architecture/content-API boundary: bot scenarios as data under `content/`. The other is skill invocation control.
3. **One serious contradiction.** The tested pre-push hook blocks the force-with-lease push that `run publish` needs after every rebase. Four smaller contradictions follow: `.github/workflows` condition vs the ask rule, `board move` vs the raw `item-edit` allow, "read-only" subagents that write files, and D6 vs §14.
4. **Missing Phase A→B boundary pieces.**
   - There is no bootstrap sequence for an empty repo. The first commit must carry a fixed `.gitignore` (the global exclude is broken) and LFS rules (`addons/gdUnit4` has 9 PNGs), and it has to reach `main` before any guard exists.
   - The document never says how it becomes the lean, as-decided doc that KICKOFF §5.2 says both agents read. Left as a 966-line options document, it would compete with the ADRs.

Smaller completeness gaps:
- rule promotion across ownership lines, and what happens when the line budget overflows;
- the incomplete CODEOWNERS map that D14-B depends on;
- the "no editing scenes with an open PR" check;
- explicit reviewer requests on private Free;
- a new CI dependency on Claude Code;
- protected-path pauses in an ultracode M0 run;
- the M4 alternative to MCP from the corrected research;
- designer sign-off on the decisions that bind her;
- the evidence-tagging promise, which is kept only in §0.

Files reviewed:
- `D:\prime-game\docs\AGENT_WORKFLOW.md`
- `D:\prime-game\KICKOFF.md`
- the research notes under `C:\Users\xperi\AppData\Local\Temp\claude\D--prime-game\40c5c58a-0dc5-4821-beca-a406804c7d8a\scratchpad\research\`, mainly `gaps.md`, `skills.md`, `subagents.md`, `operations.md`, `godot_mcp.md`, `memory.md`, `permissions.md` and `superpowers.md`.

## [kickoff-1] MAJOR — §4.5 step 4 vs §7.2 (D13) and D15
QUOTE: Runs `tools\run.cmd publish`, which rebases on `origin/main`, re-runs verify, and pushes the feature branch (force-with-lease is allowed only on the task's own branch)" vs "Tested [local], git 2.49: it blocked a push to main, `+main`, `--force`, `--force-with-lease` and `--delete` from both shells
PROBLEM: The committed pre-push hook runs for every git push, including the one inside `run publish`. As tested, it blocks `--force-with-lease` on feature branches. Once a branch has been pushed, every rebase-then-publish (KICKOFF §5.4 requires rebasing before the PR, and again after review changes) will fail. The only workaround is `--no-verify` inside the runner, which is exactly the bypass §7.2 forbids. The guard hook's exception for `run publish` does not help, because the guard sees only the tool-call text. The research marked this as a human policy choice, but the draft never surfaces it.
EVIDENCE: gaps.md gap1-20 (local test): pre-push BLOCKED `git push --force-with-lease origin feat/1`. The gap1 answer says the hook "cannot tell a force-with-lease rebase of your own branch from a destructive force... Policy choice: allow non-ff on your own `<area>/<issue>-*` branches, or require a fresh branch name after a rebase". KICKOFF.md lines 369-370.
FIX: Add a sub-decision under D13 with three options:
- (a) The pre-push hook allows non-fast-forward updates only to `refs/heads/<area>/<issue>-*`. It still blocks main, `+main`, deletes and pushes to any other ref.
- (b) Never force-push. After a rebase, publish to a new branch name (`...-r2`) and re-target the PR.
- (c) Merge `origin/main` into the branch instead of rebasing. This deviates ⚠ from KICKOFF §5.4.

State that `run publish` never passes `--no-verify`. Change the §7.2 test table to include 'force-with-lease on own task branch → allowed' (a) or 'blocked' (b/c).

## [kickoff-2] MAJOR — §14 (Phase A step 5 → M0 boundary)
QUOTE: Not yet: no git repo, no GitHub repo... 3. M0 (Phase B). The artifacts land as focused PRs, each with verification output: repo hygiene (`.gitignore`, including `settings.local.json`, `.gitattributes`/LFS, templates, CODEOWNERS)
PROBLEM: The draft has no bootstrap sequence.
- Step 5 writes ADRs before any git repo exists.
- A PR needs a base commit on `main`. KICKOFF §9.4 explicitly allows a direct commit to `main` for an empty repo, but the draft only mentions PRs.
- Hygiene lands in a PR, which means it arrives after that initial commit. But the initial commit must already carry the repo `.gitignore` entry and the LFS rules:
  - The global exclude line is broken (backslash), so `git add -A` would commit `.claude/settings.local.json`.
  - `addons/gdUnit4` contains 9 `.png` files that KICKOFF §2 routes through LFS. Fixing that later means rewriting history, a §0 stop-and-ask.
- Once installed, the guard hook and pre-push hook both block the push to `main` that the bootstrap needs.
- A D22 ruleset (require PR plus code-owner review) must be created after the first commit, and authors cannot approve their own M0 PRs.
EVIDENCE: Local checks:
- `D:\prime-game` is not a git repo.
- `.gitignore` has only `.godot/` and `/android/`.
- `.gitattributes` has only `* text=auto eol=lf`.
- `find addons -type f` shows 9 png files.
- `~/.config/git/ignore` contains `**/.claude\settings.local.json`, confirmed with `od -c`.

Research: gaps.md gap5-06 (backslash line not honoured) and gap1-13 (authors cannot self-approve). KICKOFF.md lines 143-147 and 569-571.
FIX: Insert an explicit 'M0 bootstrap' step between step 5 and the first PR:
1. A human creates the empty GitHub repo (D22), with no ruleset yet.
2. The agent runs `git init` and writes `.gitignore`: `.claude/settings.local.json`, `.claude/worktrees/`, `tools/out/`, `.idea/` except shared files.
3. The agent writes `.gitattributes` with the LFS patterns.
4. The agent verifies that `git check-ignore -q .claude/settings.local.json` returns 0 and that `git lfs ls-files` lists the addon PNGs.
5. One initial commit (KICKOFF.md, project files, `addons/gdUnit4`, the step-5 ADRs, the approved workflow doc) goes directly to `main`, stated as the KICKOFF §9.4 path, before any guard or pre-push hook is installed.
6. Only then do the humans create the ruleset.
7. The remaining M0 lands as PRs, with the self-approval/bypass setting decided up front.

## [kickoff-3] MAJOR — Header (Owner/Next step) and §14; KICKOFF §5.2 and §6
QUOTE: Owner | Engineer (this file). Both humans' agents read it once approved.
PROBLEM: KICKOFF §5.2 makes `docs/AGENT_WORKFLOW.md` the durable how-agents-work document read by both agents. The draft says agents will read this very file once approved, but never says it will be rewritten into the decided state. As written, it is a 966-line options document. It holds Rec. columns, rejected alternatives, research facts and appendix drafts marked 'PROPOSAL; not applied'.

After an amendment such as 'D4 → C', the body text for D4 would still describe option A and its flow. Agents following the root CLAUDE.md pointer ('Session protocol pointer', App. E item 7) into this file would then find instructions that contradict the ADRs, CLAUDE.md and the skills. That creates the kind of competing source of truth KICKOFF §6 warns against.
EVIDENCE: AGENT_WORKFLOW.md lines 8-9 and 938-948. `wc -l` gives 966 lines. KICKOFF.md lines 325-327 and 453-455.
FIX: Add a step-5 deliverable: rewrite `AGENT_WORKFLOW.md` into an 'as-decided' document.
- Keep only the chosen options, stated as imperative rules, with a line budget.
- Link each rule to its ADR.
- Move alternatives, evidence and rationale into the ADRs.
- Drop the §1 register and the §0 research facts, or move them to `docs/history/`.
- Keep this proposal only in git history.

State that CLAUDE.md, the skills and the `doctor` checks cite the as-decided sections, not this proposal.

## [kickoff-4] MAJOR — §1 Decision register (⚠ markers): D9, D11, D15/§8.1, D21, D24
QUOTE: Decisions marked ⚠ deviate from KICKOFF.md wording." (only D4 and D7 carry ⚠)
PROBLEM: The user required every deviation from the KICKOFF to be clearly flagged. Several unmarked recommendations change KICKOFF prescriptions:
- **D9:** code-reviewer runs on opus. KICKOFF §6 says 'Strongest model', and the draft itself calls fable 'KICKOFF's strongest model'.
- **D15/§8.1:** Godot and gdtoolkit may run only through the runner, although KICKOFF §6's allowlist names 'the Godot console exe' and 'gdtoolkit'. D15 also allows push and gh writes (issue create/comment/edit, pr create, project item-add/edit), beyond KICKOFF's 'read-only gh commands'.
- **D21:** ultracode becomes a per-prompt keyword. M0 is split into staged runs with human review between them, whereas KICKOFF §10 describes a single foundation run 'with no mid-task human input'. `tools/` moves to high. D21 also offers no alternatives, although the user asked for options.
- **D11:** KICKOFF §8.4 asks 'how you verified routing'. The draft defers verification of the four custom agents to M0.
- **D24:** KICKOFF §4 says 'thin `.ps1` and `.sh` wrappers'; the draft uses `.cmd`.
EVIDENCE: AGENT_WORKFLOW.md lines 81, 94, 96, 101, 106, 109, 327, 367-368, 496, 506, 583-591 and 830-836. KICKOFF.md lines 233-235, 397, 403, 411-413, 540 and 589-593. subagents.md verifier critique #2: 'It contradicts the brief without saying so'.
FIX: Add ⚠ to D9, D11, D15, D21 and D24.
- Give D21 at least two alternatives: KICKOFF-literal (one M0 run, session `/effort ultracode`) vs staged per-prompt runs.
- Split D15 so that 'direct Godot/gdtoolkit allow (KICKOFF)' vs 'runner-only' is an explicit choice.
- For D11, either run a scratch-project routing probe now or say plainly that Phase A delivers only the method. The probe would use the bundled 2.1.281 `claude.exe` and a throwaway `.claude/agents/` in the scratchpad, on haiku/sonnet only, after the engineer approves the plan usage.

## [kickoff-5] MAJOR — §6 Skills (new-mechanic row) and §11.1
QUOTE: writes a bot scenario as **data under `content/`** (so it stays in the designer's area)
PROBLEM: This settles an architecture and content-API question (the bot-harness scenario format and its location) inside a skill description. It never appears in the register.
- KICKOFF §3 places bot-match under engineer-owned `tests/`.
- §0 requires stopping to ask before 'changing an architecture boundary'.
- §10 assigns the content-API design to a dedicated pre-M2 design run.
- The skills verifier flagged this as needing a human decision.

The bot harness does not exist until M3, so M0's `new-mechanic` would also be written against a format nobody has designed.
EVIDENCE: AGENT_WORKFLOW.md lines 385 and 626. KICKOFF.md lines 41-43, 221, 343-345 and 589-593. skills.md verifier critique #7: "new-mechanic's 'bot scenario' output would land in engineer-owned tests/ unless the scenarios are data files under content/. That needs a decision."
FIX: Add a register row with the options:
- (A) data-defined scenarios under `content/` (designer-owned), and the content API defines the format;
- (B) scenarios in `tests/bot/` (engineer-owned), with the designer's agent filing an issue or a CODEOWNERS-reviewed PR;
- (C) defer to the pre-M2 content-API design run.

Until it is decided, have `new-mechanic` in M0 write only the issue, GDD open questions and engine-requests.

## [kickoff-6] MINOR — §6 Skills rules (invocation control), interacting with D15/D16 and §12
QUOTE: All skills stay model-invocable (the default), so a dictated "заверши задачу" works. Side effects are governed by permissions (§8), not by `disable-model-invocation`.
PROBLEM: This is a human decision that the research explicitly said not to hard-code, and it sits outside the register. Combined with D15 (push, `gh pr create` and issue comment allowed) and D16 (Accept edits), a misrecognised dictation can make the agent invoke finish-task. finish-task then pushes, opens a PR and posts a handoff comment with no prompt at all. KICKOFF §0 asks for a confirmation when a misreading would change outcomes.
EVIDENCE: skills.md verifier critique #5 ('Invocation control needs an explicit decision per skill. finish-task and new-mechanic have side effects') and Config corrections (a): 'Whether finish-task and new-mechanic should be human-only is a decision to put to the humans, not a default to hard-code.' KICKOFF.md lines 71-73.
FIX: Add a register row with the options:
- (A) model-invocable, with finish-task asking one 'publish now? (push + PR)' question before any GitHub write;
- (B) `disable-model-invocation: true` for finish-task and new-mechanic;
- (C) keep them model-invocable but move push and `gh pr create` to ask (the D15 alternative).

## [kickoff-7] MINOR — §3.3 Interventions → rules (flow) and §3.1 budget
QUOTE: Flow, whatever the option... in the **same PR**: ... always needed → root CLAUDE.md
PROBLEM: The flow ignores ownership. Root CLAUDE.md is engineer-owned (KICKOFF §5.3), and the 150-line budget covers root plus all unscoped rules shared by both humans. A designer-originated lesson promoted to root or `.claude/rules` crosses owners, which is a §0 stop-and-ask item and would trigger the D14-B prompt. Nothing says what happens when the `budget` lint fails: which rule gets demoted or retired, and who decides. 'Whatever the option' also contradicts D4-C, where the designer's agent files an issue instead of writing the entry.
EVIDENCE: AGENT_WORKFLOW.md lines 146, 157, 186 and 188-196. KICKOFF.md lines 41-43, 343 and 531-533 (step 4 asks how rules get added and how the budget is kept). gaps.md gap6 option C notes that CLAUDE.md is already engineer-owned.
FIX: Specify the following:
- Designer lessons go to designer-owned files (`content/CLAUDE.md`, `levels/CLAUDE.md`, rules scoped to `content/**` and `levels/**`).
- Root or unscoped promotions need the engineer's CODEOWNER review. Alternatively, choose D4-C for root rules only.
- When the budget lint fails, the same PR must path-scope, move to a skill, or retire a rule, and the intervention entry records which.
- Reword 'whatever the option' so it covers D4-C.

## [kickoff-8] MINOR — §7.3 (D14-B) role-aware guard
QUOTE: The guard hook reads `PRIME_GAME_ROLE` (`engineer`/`designer`...) and the committed `.github/CODEOWNERS`. An Edit/Write outside the role's paths returns `ask`... One committed source of truth.
PROBLEM: D14-B depends on CODEOWNERS, but the KICKOFF list it would copy is incomplete.
- Engine and shared paths are missing: `client/` (player controller, UI, dev console), `project.godot` (which holds the D20 warnings policy), `addons/`, `.claude/**`, `CREDITS.md`, `docs/decisions/`, `docs/interventions/`, `docs/ROADMAP.md` and `docs/AGENT_WORKFLOW.md`.
- Under 'outside the role's paths → ask', the engineer gets prompts for `client/` work.
- Both humans get prompts for routine shared files, such as intervention entries, ADRs and asset credits.
- CODEOWNERS maps paths to GitHub handles, which are placeholders until Phase B, not to roles. So 'one source of truth' still needs a mapping from handle to role.
EVIDENCE: KICKOFF.md lines 203-223 (layout includes `client/`) and 343-345 (CODEOWNERS list omits `client/` and `project.godot`). AGENT_WORKFLOW.md lines 467-471.
FIX: Propose a complete ownership map as part of D14:
- engineer adds `client/`, `project.godot`, `addons/`, `docs/AGENT_WORKFLOW.md` and `docs/ROADMAP.md`;
- decide who owns `.claude/skills/new-mechanic` and `new-level-piece`;
- a 'shared, no prompt' set: `docs/interventions/`, `docs/decisions/` and `CREDITS.md`.

Add a committed mapping from role to handle, and state the guard's behaviour for any path that is not listed.

## [kickoff-9] MINOR — §4.4 start-task and §4.5 finish-task (session protocol)
QUOTE: 3. Reads the documents the issue links, plus the area's CLAUDE.md, and checks ownership against CODEOWNERS.
PROBLEM: Two KICKOFF coordination rules are not implemented anywhere in the protocol.
- KICKOFF §5.3 says 'Never edit a scene someone else has an open PR on', but no step checks open PRs before a `.tscn`/`.tres` edit. The close-first rule (D19) only covers a human and her own agent.
- On private Free (D22-D), CODEOWNERS does not auto-request reviewers. finish-task never adds the other owner as reviewer when the diff crosses areas, so KICKOFF §5.4's cross-area review silently never happens.
EVIDENCE: KICKOFF.md lines 353-355 and 367. gaps.md gap1 answer: 'on private Free, CODEOWNERS will not auto-request reviewers... so the agent must add the reviewer explicitly' (gap1-04).
FIX: - **start-task / new-level-piece:** list open PRs with their files (e.g. `gh pr list --state open --json number,author,files`). Stop if another human's PR touches the target scene.
- **finish-task:** when the diff touches the other owner's paths, pass `--reviewer <handle>` to `gh pr create`.

## [kickoff-10] MINOR — §7.2 guard list vs Appendix A ask rule
QUOTE: edits to `.github/workflows/**` unless the issue plan mentions them (prompts via `ask`)
PROBLEM: This condition cannot take effect.
- Appendix A has an unconditional ask rule, `Edit(/.github/workflows/**)`. Ask rules are still evaluated when a hook returns allow, so every such edit prompts regardless of the plan.
- 'The issue plan' does not exist as an artifact. Plans stay private in `~/.claude/plans` (D1), and start-task never posts the plan to the issue.

The text therefore describes a check that can neither be performed nor change the outcome.
EVIDENCE: gaps.md gap1-23: 'Deny and ask rules are still evaluated even if a hook returns allow.' operations.md correction permissions-01: "A condition like 'without mention in the plan' cannot be expressed as a rule, so use an `ask` rule." AGENT_WORKFLOW.md lines 119, 448 and 850.
FIX: Drop the condition and state that `.github/workflows/**` edits always prompt. The human checks the plan at the prompt. If an automated check is wanted, have start-task post the approved plan to the issue, and document that as a change to D1-A.

## [kickoff-11] MINOR — §13.2 item 3 vs D15 and Appendix A
QUOTE: Moves go through `tools\run.cmd board move <issue> <status>`, which caches project, field and option IDs and refuses Done." vs allow list: "Bash(gh project item-add *)", "Bash(gh project item-edit *)"
PROBLEM: Raw `gh project item-edit` is pre-approved, so the runner's refusal to set Done is only advisory: the agent can set Done directly, with no prompt. Auto-close-on-Done is kept on (§13.2), so an agent's mistaken Done move closes the issue without a merged PR. The research recommended the runner command precisely so that 'the allowlist then only needs the runner'.
EVIDENCE: gaps.md gap2 option C1 ('The allowlist then only needs the runner'), gap2-19 (auto-close on Done) and gap2-39. AGENT_WORKFLOW.md lines 101, 532, 732-735 and 835-836.
FIX: Remove `gh project item-add` and `gh project item-edit` from allow, in both the Bash and PowerShell forms. Put them in ask, or deny item-edit. Keep only `tools\run.cmd board ...` allowed, and update the D15 row accordingly.

## [kickoff-12] MINOR — §5.1 Roster (read-only claim, tools column)
QUOTE: **Read-only is enforced by the `tools` list**... Shell access is limited by a frontmatter PreToolUse hook to an allowlist of read-only commands." / "WebFetch (`docs.godotengine.org` only)
PROBLEM: The listed commands are not read-only.
- `run check` includes `--import`, which creates `.uid` sidecars and writes `.godot/` caches.
- `api-ref` writes `tools/out/`.
- `bots` starts processes and writes logs.

In the designer's main checkout this is the same open-editor cache interference that §15 flags. Separately, nothing enforces 'docs.godotengine.org only': the tools list grants plain WebFetch, and the shared allow list pre-approves `github.com`, `code.claude.com` and other domains for subagents too.
EVIDENCE: gaps.md gap3-17 ('--import also silently created .uid sidecars') and gap3-37 (headless runs write `.godot/` caches). godot_mcp.md verifier: 'WebFetch can be limited to docs.godotengine.org by domain only; the /en/4.7/ path limit is prompt-only.' AGENT_WORKFLOW.md lines 317-325, 799 and 837-839.
FIX: Reword to: 'no Edit/Write; shell limited to the listed runner commands, which write only tools/out/ and .godot/'. Either drop `check` and `api-ref` from the checker's allowlist (the main session supplies their output) or accept the writes explicitly. Enforce the WebFetch domain with the frontmatter PreToolUse hook, or drop the word 'only'.

## [kickoff-13] MINOR — §14 step 1 (ADRs at Phase A step 5)
QUOTE: ADRs for the key choices, dated and slugged: D1 framework; D2/D4 memory and interventions; D9/D10 agents and models; D13/D14 guards; D18 no MCP; D21 effort; D22/D23 GitHub.
PROBLEM: D7 is marked ⚠ as a deviation from KICKOFF §6 and §8.2, yet it has no ADR. Neither do D6 (canonical surface and minimum version), D19 (close-first rule) or D24 (runner entry point), and neither would the newly flagged deviations (D15 and the others above). KICKOFF is archived at the end of M0 with the rule 'make sure nothing important lives only here'. After that, the reasons for departing from it would live only in a proposal document.
EVIDENCE: KICKOFF.md lines 553 and 573. AGENT_WORKFLOW.md lines 92, 753-760.
FIX: Record an ADR for every ⚠ decision, starting with D7. Also cover D6, D19 and D24, or name the durable file each one lives in.

## [kickoff-14] MINOR — §2 Framework (D1) trade-off table
QUOTE: **B** A + adapted Superpowers discipline skills ... | Upstream improvements need a manual diff each milestone; no "1% rule" auto-trigger
PROBLEM: KICKOFF §8.4 asks for trade-offs of discipline against token cost. Token cost is given for A, C and E, but not for the recommended B.
- B adds always-on skill descriptions plus a per-invocation cost for the adapted skills. Upstream sizes are about 2.4k (TDD), 2.3k (debugging) and 0.8k (verification).
- The enforcement B relies on in place of the bootstrap is a fresh-context review on every finish: code-reviewer on Opus at high effort, always, plus up to two more reviewers. That recurring cost is not weighed at all.
- The designer's plan is unknown, possibly Pro with smaller limits.
EVIDENCE: superpowers.md superpowers-09 (measured per-skill sizes) and verifier critique #4 ('The real cost is 2-8k per invoked skill plus the ceremony, and that belongs in the discipline-vs-cost trade-off'). AGENT_WORKFLOW.md lines 120 and 284-287. KICKOFF.md lines 527-529.
FIX: Add the token cost of B to the table, and add a line estimating per-task review cost. Offer a lever, for example: code-reviewer only for code diffs, and the built-in `/code-review` at medium or skipped for docs-only and content-data PRs.

## [kickoff-15] MINOR — §6 Rules (CI skill lint) and D6 vs §14
QUOTE: CI lints skills with `claude plugin validate .claude/skills`, which needs ≥2.1.233." / D6 Rec: "**A** + update PATH CLI" vs §14: "optionally `claude update`
PROBLEM: Running `claude plugin validate` in CI means installing Claude Code in the CI runner, a new dependency (§0: stop and ask). It is not in the register. Locally, any `claude ...` command the agent runs uses the 2.1.195 PATH CLI, which rejects the directory. D6 recommends updating the CLI, but §14 lists the update as optional, so the version the check relies on is left undecided.
EVIDENCE: skills.md mf-validate-skills ('The 2.1.195 PATH CLI rejects the directory with No manifest found') and mf-embedded-version. KICKOFF.md lines 41-43. AGENT_WORKFLOW.md lines 91, 399 and 771.
FIX: Add a register row with the options:
- (A) CI installs a pinned Claude Code, version 2.1.233 or later;
- (B) `verify` runs the lint locally through `$CLAUDE_CODE_EXECPATH`;
- (C) a small frontmatter YAML lint inside the Python runner, with no new dependency.

Make D6 and §14 agree on whether `claude update` is required.

## [kickoff-16] MINOR — §10 (ultracode M0) with §7/§8.1 protected paths
QUOTE: Foundation work with no mid-task human input: M0 execution after approval ... **`ultracode` keyword in that one prompt**" / "`.claude/` is a protected path, so writes there always prompt, even for agents.
PROBLEM: Most M0 artifacts live under `.claude/`: settings, agents, skills, hooks and githooks, plus `.idea/` if shared run configurations are added. Allow rules cannot pre-approve writes there, and in Accept edits (D16) a workflow pauses on every such permission prompt. An ultracode M0 run will therefore stall repeatedly, contradicting 'no mid-task human input'. The draft does not say how M0 handles this.
EVIDENCE: permissions.md mf-04 (protected paths prompt in default/acceptEdits; a session-scoped 'allow edits to this project's .claude folder' option exists). gaps.md gap4-13 ('A run pauses on its own only for agent permission prompts and a usage-limit wait').
FIX: In §10/§14, state the approach. Options:
- approve the session-scoped `.claude` option once at the start of the M0 session, noting that it is unverified for workflow agents;
- land the `.claude/` PRs in interactive, non-workflow runs;
- accept the pauses and budget for them.

## [kickoff-17] MINOR — §9 Godot MCP (D18) alternatives
QUOTE: D a runtime MCP scoped inline to a single `playtest-observer` subagent. D is the M4 candidate if needed.
PROBLEM: The corrected research says a debug-only input and inspection autoload inside the game is the better M4 path: reviewable, CI-runnable and part of the bot harness. It also corrects the runtime MCP premise, since Erodenn edits `project.godot` and `.gitignore` during runs and is single-process. The draft names only the MCP as the M4 candidate, so the MCP question is judged against an incomplete set of options.
EVIDENCE: godot_mcp.md verifier critique: "'Erodenn first choice, no repo footprint' is inaccurate: it edits project.godot and .gitignore during runs and is single-process. For M4 input simulation, a debug-only input/inspection autoload inside the game is reviewable and CI-runnable; it fits the bot harness and 'humans read diffs' better than any MCP."
FIX: Add option E to D18: an in-game debug-only input and inspection autoload plus the bot harness, as the preferred M4 path. Keep D (runtime MCP in one subagent) as a fallback, and note its repo side effects.

## [kickoff-18] MINOR — 'How to review' / Next step (who approves)
QUOTE: Engineer approves or amends the decisions in §1.
PROBLEM: Several decisions bind the designer's own sessions, machine or editor habits:
- D5: her language;
- D16: her permission mode, recommended as 'Start both humans on Accept edits';
- D19: the close-first rule and `save_on_focus_loss` setting in her editor;
- D14: role prompts in her sessions;
- D22: plan and visibility, possibly money;
- D23: her invites and her `gh` scope.

KICKOFF §0 reserves decisions for 'the humans', and she owns her area. Routing every approval through the engineer risks applying rules to her that she never agreed to.
EVIDENCE: KICKOFF.md lines 15, 47-53 and 347-351. AGENT_WORKFLOW.md lines 9-12, 88, 98, 104, 107 and 654-659.
FIX: Mark the decisions that bind the designer, for example with a 'designer sign-off' marker. Get her confirmation, or the engineer's confirmation that he has spoken to her, before step 5 applies anything to her machine or workflow.

## [kickoff-19] MINOR — Evidence paragraph (top) vs §2–§13
QUOTE: Every claim below is either **[doc]** (current official docs, fetched 2026-09-28), **[local]** (tested on this machine), or **[inferred]**.
PROBLEM: The promise is kept only in §0. Tags appear on 22 lines, and 13 of those are in §0. Most claims that drive decisions in §2–§13 carry no tag, for example:
- D10: `availableModels` behaviour;
- D16: `defaultMode` ignored in project settings;
- §9: the August 2026 CVE;
- D14-B mechanics;
- §13 built-in workflow defaults.

The engineer cannot tell doc-backed claims from inferred ones without the uncommitted research notes.
EVIDENCE: A local `grep` over `docs/AGENT_WORKFLOW.md` for tag strings: 11×[doc, 16×[local, 1×[inferred, on lines 17-75, 177, 231, 235, 357, 426, 452, 667 and 799.
FIX: Tag the decision-driving claims in §2–§13, at least those behind each Rec. Otherwise, reword the sentence to say that only §0 is tagged and that the research IDs are available on request.

# LENS humans

OVERALL:
The research behind the proposal is strong. The document itself is built to be read in full, not approved quickly, and several things the two humans must actually do are missing or contradict each other.

**Engineer (the approver).** The register has 24 rows of equal weight, about 32 choice points in total. Eight rows have no lettered options, so the suggested reply format ("D4 → C") does not work for them. Several rows are implementation details a human who writes no code cannot judge: D12's launch form, D19's normalize tool, D20, and D24 (which KICKOFF §4 already left to the agent). D17 duplicates start-task's own `doctor --quick`. D22 comes last and has no default, even though D13–D15 and the whole M0 PR flow depend on it. It can shrink to about 8 real decisions, about 9 defaults that stand unless vetoed, and about 6 agent calls recorded in ADRs.

**Designer.** Her daily loop has no defined steps for:
- **Onboarding:** one bullet in §14.
- **Idea to issue to PR:** new-mechanic and start-task overlap.
- **Review and merge:** nobody is named, and the research's merge gate was dropped.
- **Permission prompts:** no count of how many she will see and no advice on how to answer them.

The close-first rule is contradicted by the skills' own branch switch (start-task) and rebase (finish-task). It is ambiguous for loaded `.tres` files, which is exactly where edits are lost silently. It cannot be enforced as written, even though the editor process is easy to detect.

**Roles.** The role-aware "ask" (D14) and log-intervention put decisions on the wrong human. The designer would approve engine-code edits she cannot judge. The engineer would approve content changes that need the designer's approval.

**Desktop Code tab.** Several instructions only work in the CLI:
- `/voice`, and with it the `language` → dictation claim;
- pressing `s` in `/workflows`;
- `/usage`, `/context` and `/tasks`.

The dictation glossary also contains a Russian form ("тресы").

**After approval.** The proposal should be rewritten as a short decided-state doc. As it stands, both agents would read a 61 KB file that includes the rejected options.

None of these is a blocker for the research itself. The close-first contradiction, D14 and the merge flow need fixing before D8, D14, D15 and D19 are approved as recommended.

Evidence (key sources):
- `D:\prime-game\docs\AGENT_WORKFLOW.md` and `D:\prime-game\KICKOFF.md`
- research notes: gaps.md (gap1 layer (b), gap1-13/32, gap2-26..28, gap3-24..34 and C1, gap5 designer step, gap6-D), operations.md (mf-05..08, desktop-03), memory.md (missed-01), permissions.md (mf-04, mf-09)
- docs: https://code.claude.com/docs/en/voice-dictation, https://code.claude.com/docs/en/desktop, https://code.claude.com/docs/en/workflows
- local: `Get-CimInstance Win32_Process` shows `Godot_v4.7.2-stable_win64.exe --path D:/prime-game --editor` (PID 17248)

## [humans-1] MAJOR — §1 Decision register (and 'How to review', lines 11-12, 79-109)
QUOTE: Reply with something like *"approve all recommendations, except D4 → C and D22 → B"* ... | D5 👤 | Personal prefs (§3.4) | `language` setting + `~/.claude/CLAUDE.md` per human | **yes** |
PROBLEM: The register cannot be approved quickly or safely.

**Size.** 24 rows hold about 32 choice points: D12 has 2 axes, D15 has 3, D19 has 2 and D23 has 4.

**Reply format breaks.** Eight rows have no lettered options (D5, D9, D11, D13, D15, D16, D21, D23), so the suggested "Dn → X" reply does not work for them.

**Rows a human cannot judge.** Several are implementation choices for someone who writes no code:
- D12's launch form (Git Bash shell form vs exec `py -3` vs `powershell.exe -File`);
- D19-A's `-e -s` normalize tool;
- D20's warning levels (the proposal already says it may defer);
- D24's runner language (KICKOFF §4 already delegates it to the agent).

**Rows that are redundant or not choices.**
- D17 duplicates start-task step 1 (`doctor --quick`). The DoD reminder is already re-injected with root CLAUDE.md after compaction (§0.10).
- D11 is a verification method, not a choice.
- D18's recommendation is itself a deferral.

**D22 is last and has no default.** D13–D15 and M0's "reviewable PRs" all depend on it.

**"Approve all" hides the important items.** A blanket approval would pass the items that bind the designer's habits (D16, D19 close-first) or cost money (D10), with no "what changes for you" view.
EVIDENCE: - Register rows 84-109.
- KICKOFF §4: "for example, one GDScript or Python entry point".
- §4.4 step 1 already runs `tools\run.cmd doctor --quick`.
- gaps.md gap1: "whichever of A–D is chosen, ship (a)+(b)", so the guards do not depend on D22.
FIX: Restructure §1 into three tiers and add a column "What changes for you (engineer / designer / money)".

**Tier 1: decide now.** Every row gets letters.
- D22 repo and plan, plus who merges. Move it to the top. Default: start as D (private Free, $0). Upgrading to B or going public later needs no rework, because the §7.2 guards ship in every option.
- D10 (Fable guard; usage credits off)
- D1
- D4, extended to CREDITS.md and to who may promote rules
- D7
- D8
- D14
- D19b close-first working agreement. The designer co-signs it.

**Tier 2: defaults, veto by exception.** One line each:
- D2, D3, D5, D6, D16, D21, D23;
- D9 with D11 folded in;
- D13 merged with D15, split into D15a/b/c.

**Tier 3: agent's call during M0.** Each is recorded in an ADR with test output: D12, D18, D19a, D20, D24. Drop D17 and keep start-task's check.

Rewrite the review line: "Say 'tier 2 OK' to accept the defaults. Answer the 8 tier-1 questions with a letter each, e.g. 'D22 D, D10 A, D1 B, ...'."

## [humans-2] MAJOR — §11.2 Close-first rule vs §4.4 step 4 and §4.5 step 4
QUOTE: The agent never writes, normalizes or pulls a `.tscn`/`.tres` that is open in the editor. The designer saves and closes that tab first; the agent asks.
PROBLEM: **(a) The skills contradict the rule.** start-task switches branches ("Creates `<area>/42-<slug>` from a freshly fetched `origin/main`") and finish-task rebases (`run publish` "rebases on `origin/main`"). Both rewrite every file that differs, not only the file the agent edits. Neither skill has a "save and close Godot" step.
- With a scene open, "Ignore external changes" re-saves the stale copy.
- An unguarded Ctrl+S does the same.
- The designer's next PR then silently reverts the engineer's change.

**(b) "Open" is ambiguous for `.tres`.** A `.tres` that the open level merely uses is reloaded silently, discarding unsaved inspector edits. The research's C1 distinguished these cases; the proposal dropped the distinction.

**(c) The agent cannot know what is open.** "The agent asks" becomes a question before every content write, or gets skipped.

**(d) The editor writes files itself.** Examples: F5 `save_before_running`, `.import`, `.uid`. That leaves a dirty tree, and start-task has no plain-language policy a non-coder can answer.

**(e) The designer carries the untested risk alone.** §15 says headless runs next to an open editor are untested. The designer is the only human with no mitigation.
EVIDENCE: - gaps.md gap3-25..30: dialog buttons; `_save_scene` has no timestamp check; loaded `.tres` is reloaded with no prompt.
- gap3-32: `save_before_running` defaults to true.
- gap3 C1 nuance about "content .tres that the open level only uses".
- Local check: `Get-CimInstance Win32_Process` shows `Godot_v4.7.2-stable_win64.exe --path D:/prime-game --editor` (PID 17248), so an open editor is detectable.
FIX: Replace the rule with one simple habit, enforced by the runner.

**Rule text:** "Before 'start task', 'finish', or asking for level/content changes: in Godot, Save All (Ctrl+Shift+S) and close Godot."

**Runner enforcement.**
- `start`, `publish`, `normalize` and any branch switch or rebase refuse while a process command line contains `--path <this checkout>` and `--editor`.
- The agent relays the refusal in the human's language, e.g. "Збережіть усе в Godot і закрийте його, потім скажіть 'продовжуй'".

**Dirty tree at start-task.** List the files in plain words and offer only two choices:
- "include in this task";
- "set aside (stash)".

Never discard.

**Gate.** Make the §15 "headless run beside an open editor" test pass before the designer is onboarded.

## [humans-3] MAJOR — §14 step 2 (designer setup) and §0 'Owner' line; no designer sign-off anywhere
QUOTE: designer machine setup: Desktop ≥2.1.281, Git + LFS, gh, Python + gdtoolkit, Godot 4.7.2 portable, env per D7;
PROBLEM: A non-coder's whole setup is one bullet. It is missing:

**Who does each step and in what order.** Her agent could do most of it.

**Clicks only she can make:**
- accepting the repo invite and the project invite (§13.2);
- `gh auth login` plus `gh auth refresh -s project`, a browser flow. The proposal does not say where to type it (Desktop terminal panel, Ctrl+`).
- trusting the folder in Desktop;
- the usage-credits setting;
- checking her plan. On Pro, workflows are off until enabled in Settings, the size guideline defaults to small, and Fable bills from the first token.

**Traps from §0 and §4.3 that apply to her machine:**
- Python is the Microsoft Store stub, so she needs a real install.
- `git lfs install` must be global, not `--local`.
- Git for Windows is required. Shell-form hooks run in Git Bash; without it every guard, including the D14 boundary, fails open.

**Chicken-and-egg.** Her agent learns the setup from files that exist only after M0 merges.

**No sign-off from her.** The engineer alone approves rules that change her daily habits (close-first, prompts, merging) and possibly her bill.
EVIDENCE: - gaps.md gap5 "DESIGNER SETUP STEP"; gap2-26..28 (project and repo invites are separate); gap1-26 (hooks run in Git Bash, or PowerShell if Git Bash is absent).
- workflows.md: "On Pro, turn them on from the Dynamic workflows row in `/config`"; size guideline defaults to small on Pro.
- §15: "Hooks fail open if PYTHON_BIN or Git Bash is missing".
- KICKOFF §0: humans write zero code.
FIX: Add a "Designer onboarding" subsection as an M0 deliverable.

**Flow.** After M0 merges, the designer opens the cloned folder in Desktop and says "налаштуй мене" / "set me up". An `onboard` skill (the name collides with nothing bundled) then:
- runs `doctor`;
- fixes what it can after her approval (user settings `env`, `language`, `PRIME_GAME_ROLE`, gdtoolkit via the real Python, global `git lfs install`, `core.hooksPath`);
- prints a numbered checklist of human-only clicks, each with a time estimate.

**Hard stop.** `doctor` red must block start-task, with a plain-language message.

**One-page summary for her to confirm** before D16 and D19b take effect for her:
- what she does differently;
- which prompts she will see;
- what can cost money on her plan.

## [humans-4] MAJOR — §6 new-mechanic vs §4.4 start-task / §12 'Point at an issue'
QUOTE: `new-mechanic` | designer | Turns an idea into a `mechanic` issue; drafts a GDD section ...; builds content Resources ...; writes a bot scenario ...; opens an `engine-request` issue
PROBLEM: The designer's normal starting point is an idea, not an issue number. Yet §12 teaches only "start task 42".

new-mechanic both creates the issue and does the work. start-task needs an existing issue for four things: branch name, assignment, board move and ownership check. The proposal leaves open:
- which branch new-mechanic works on;
- whether it runs start-task and finish-task;
- whether the GDD draft, content Resources, bot scenario and engine-request all land in one PR. That would break KICKOFF §0 "Prefer small, reviewable steps".

The bot-scenario step also cannot run before the bots exist (M3).
EVIDENCE: - AGENT_WORKFLOW.md lines 269-277 (start-task needs an issue number) and line 385.
- KICKOFF §0 small steps; §7 bots in M3.
FIX: Define new-mechanic as a front door that hands off to the task skills:
1. Interview the designer, then create the `mechanic` issue (plus any `engine-request` issues). Stop for her OK.
2. Run start-task N.
3. Do the work.
4. Run finish-task.

Allow at most two PRs: the GDD section (design), then the content data. The bot scenario is added only once `run bots` exists.

Add to §12: "Designer: for a new idea say 'нова механіка: …'; for existing work say 'start task N'."

## [humans-5] MAJOR — §7.3 Ownership enforcement (D14-B)
QUOTE: An Edit/Write outside the role's paths returns `ask`, so the human sees a prompt: *"designer session is editing core/net.gd (engineer-owned) — allow?"*.
PROBLEM: The "ask" prompt puts the decision on the wrong human in both directions.

**(a) Designer's session.** A non-coder is asked to approve an engine-code edit she cannot evaluate. One "Yes", or one "don't ask again", breaks KICKOFF §5.3: the designer's agent "does not modify engine code".

**(b) Engineer's session.** KICKOFF §5.3 requires "the designer's approval" for content changes, but the prompt asks the engineer.

**(c) Role not set.** Behaviour is undefined when `PRIME_GAME_ROLE` is missing, which happens on an unconfigured designer machine.
EVIDENCE: - KICKOFF lines 347-351.
- §3.4 and Appendix B: the role comes from each human's env.
- permissions.md mf-09: "Yes, and don't ask again" approvals are saved per human.
FIX: Make the check asymmetric.

**Designer role → deny** on engineer-owned paths (from CODEOWNERS). The deny message says: "file an `engine-request` issue instead".

**Engineer role → ask** on designer-owned paths. finish-task also requires the PR to link the designer's approval (an issue comment).

**Missing or unknown role → deny** edits outside `docs/`, with "run doctor" as the message. `doctor` fails red when the role is unset.

## [humans-6] MAJOR — §3.3 Interventions → rules, 'Flow, whatever the option'
QUOTE: Promotes the rule to the right mechanism: always needed → root CLAUDE.md; one area → the nested CLAUDE.md or a path rule; a procedure → a skill; must happen at a fixed point → a hook.
PROBLEM: The flow makes no distinction by role.

In the designer's session, log-intervention would:
- edit root CLAUDE.md, which the engineer owns under KICKOFF §5.3 CODEOWNERS;
- write `.claude/` skills and hooks. Hooks are Python tooling, i.e. engine-side code.

`.claude/` is a protected path, so each write prompts. Combined with D14-B, the designer faces prompts she cannot judge, or her agent ends up authoring hooks.

It is also unspecified which PR carries an intervention made outside an active task.
EVIDENCE: - KICKOFF line 343: the engineer owns `CLAUDE.md`, `tools/`, `.github/`.
- permissions.md mf-04: `.claude/` is protected and allow rules cannot pre-approve it.
- §7: "`.claude/` is a protected path, so writes there always prompt".
FIX: Add a role clause to the flow.

**Designer sessions** write the entry and may promote only into:
- `content/CLAUDE.md` and `levels/CLAUDE.md`;
- `.claude/rules/*.md` scoped to `content/**` or `levels/**`. This still prompts; say so.

For anything else, the designer's agent files an `intervention` issue assigned to the engineer and links it from the entry.

**Outside a task:** create the `intervention` issue first, then a short branch and PR for it.

## [humans-7] MAJOR — §8 Permissions (§8.3, §8.4, Appendix A) and §10 ultracode M0
QUOTE: Start both humans on **Accept edits**. ... "PowerShell(Remove-Item *)"
PROBLEM: KICKOFF §6 aims for sessions that "are not interrupted by approval prompts for every run". The proposal never counts or tests the prompts a normal task produces.

Known prompt sources on the recommended path:
- **Every write under `.claude/`.** It cannot be pre-allowed, and it covers all of M0 plus every rule promotion.
- **Every workflow launch** in Manual or Accept edits mode (Desktop card: Once / Always / Deny).
- **Workflow agents pausing mid-run** for permission prompts. The "no mid-task human input" ultracode M0 run (§10) will stop repeatedly on `.claude/` writes.
- **Every `Remove-Item`, even inside `tools/out/`.** The Bash side asks only for recursive `rm`.
- **D14 asks** and **`gh pr merge` asks**.

The designer gets no guidance on answering prompts. "Yes, and don't ask again" permanently widens her local allow list, and on Windows it is saved per worktree.
EVIDENCE: - permissions.md mf-04 (protected paths; session-scoped "allow edits to this project's .claude folder" option) and mf-09.
- workflows.md: "A run pauses on its own only for agent permission prompts"; the Manual/Accept edits row prompts on "Every run"; the Desktop approval card offers "Once, Always, Deny".
- KICKOFF line 413.
FIX: **1. Measure it in M0.** Add an acceptance test: a scripted start-task → finish-task dry run for each role that records every prompt. Target for a normal content task: at most 1 designer prompt (the merge).

**2. Tell the designer what to expect.** Add a table "Prompts you will see and what to answer" to the designer docs, plus two rules:
- "If you don't understand a prompt, answer No and say 'поясни'."
- "Never choose 'don't ask again' unless the engineer said so."

`doctor` lists local allow rules that are not in the shared settings.

**3. Narrow the `Remove-Item` ask** to recursive forms, or route cleanup through `run clean`.

**4. Warn the engineer about M0.** Under ultracode it will stop for `.claude/` prompts. Pick the session-scoped `.claude` allow when offered, or do the `.claude/` PR interactively.

## [humans-8] MAJOR — §8.4 D15 / §7.2 guard list / §13.1 (review and merge flow)
QUOTE: `gh pr merge` by an agent | **ask**; humans merge after review ... Verify on the first real PR: required code-owner review applies to a human's **own** area too, and authors cannot approve their own PRs.
PROBLEM: Nothing says who reviews or merges which PR, or what each human clicks.

**How the designer reviews.** She cannot review `.tres` text diffs. The proposal does not say that her review means screenshots plus a playtest.

**The merge gate was dropped.** The research's guard rule was: deny `gh pr merge` unless `gh pr checks` is green and, for a cross-area PR, the other owner's APPROVED review exists. The proposal's §7.2 list omits it. On private Free, the designer clicking Yes on a `gh pr merge` prompt that does not show CI state is then the only gate.

**Daily consequence under D22 A–C.** With "require code-owner review", every content-only designer PR needs a non-author code-owner approval, i.e. the engineer. That is stricter than KICKOFF §5.4 ("required when a PR touches the other person's area"). It changes both humans' daily flow and belongs in the decision, not in "verify on first PR".
EVIDENCE: - gaps.md gap1 layer (b): "`gh pr merge` unless `gh pr checks` is green and ... APPROVED review ... reproduces KICKOFF 5.4's semantics exactly".
- gap1-13 and gap1-32.
- KICKOFF line 367.
- `grep` finds no merge-gate rule in AGENT_WORKFLOW.md.
FIX: Add a "Review and merge" subsection.
- **Own-area PR:** the author human says "merge it" after green CI. The agent runs a gated `gh pr merge`.
- **Cross-area PR:** the other owner approves on GitHub first, then merge.
- **Designer's review:** `shot` screenshots plus a playtest, never the diff.

Restore the merge gate in the guard hook.

Under A–C, configure the ruleset with "require PR" and "required status checks", but not "require code-owner review". Cross-area approval is then enforced by the guard's gate. Alternatively, state the stricter policy explicitly.

## [humans-9] MAJOR — §4.3 Worktrees (D8-A, engineer)
QUOTE: The **engineer's agent** uses a worktree whenever a second session runs in parallel, or when the agent's Godot runs must not touch the human's open editor's `.godot/`. It creates the worktree with `git worktree add .claude/worktrees/<n> -b <area>/<issue>-<slug>`.
PROBLEM: **(a) Not really occasional.** The second condition holds whenever the engineer's editor is open, which is most of the time. So D8-A behaves like "always" for the engineer while reading as occasional.

**(b) No human steps.**
- The Desktop session stays on `D:\prime-game`, and the proposal does not say how it moves into the worktree.
- Rider shows the main checkout, so the engineer (who reads code in Rider) sees none of the agent's changes unless he opens `.claude\worktrees\<n>` as a second Rider project.
- A playtest must run `host`/`join` from that folder.
- Removing the worktree is not described.

**(c) Permission mode resets.** Desktop remembers the mode "per folder", so every new worktree starts in the default mode. Appendix B does not set `permissions.defaultMode`.

**(d) The trigger is a judgment call.** "Editor open" is not something the agent can decide without detection.
EVIDENCE: - desktop.md: "A mode you pick in the selector is remembered per folder".
- operations.md mf-07 and mf-08; desktop-03 (the worktree option is chosen per session; archive to remove).
- KICKOFF §0: humans read code in Rider.
- Local check: the editor process with `--path D:/prime-game --editor` is detectable.
FIX: **Make the trigger deterministic:** "worktree if and only if the runner detects a GUI Godot editor on the main checkout, or another session is active on this repo".

**Write the engineer's steps:**
- open a new Desktop session on the worktree folder (or have the agent use EnterWorktree; pick one);
- in Rider, File → Open that folder;
- archive the session to remove the worktree.

**Keep the mode across folders:** add `"permissions": {"defaultMode": "acceptEdits"}` to Appendix B.

## [humans-10] MAJOR — Header 'Owner' row and post-approval fate of this file
QUOTE: | Owner | Engineer (this file). Both humans' agents read it once approved. |
PROBLEM: The file is 966 lines, 61 KB, roughly 15k tokens. It contains rejected alternatives (the Superpowers plugin C, GSD E, MCP B–D, Fable options) and engineer-only internals.

If both agents read it:
- the designer's agent pays that cost every time;
- either agent can act on a non-recommended option.

KICKOFF §5.2 wants this file to describe "how agents work here", not the debate that led there.

The local test evidence (union test, UID lab, pre-push test) lives in a temp scratchpad. The proposal says "Research notes are not committed", so that evidence disappears.
EVIDENCE: - `wc -l` gives 966 lines; the file is 61,174 bytes.
- KICKOFF line 325.
- AGENT_WORKFLOW.md line 19: "Research notes are not committed".
FIX: Add a step to §14.

After approval, rewrite AGENT_WORKFLOW.md as the decided state only:
- about 200 lines;
- one section per role;
- no alternatives.

Move the reasoning and alternatives into the Phase A step 5 ADRs, together with the key local test scripts and their outputs. Keep this proposal as `docs/history/AGENT_WORKFLOW-proposal.md`.

Root CLAUDE.md links to specific sections of the rewritten file, not to the whole file.

## [humans-11] MINOR — §3.4 Personal preferences and §12 Dictation
QUOTE: It also sets the `/voice` dictation language, and Ukrainian is supported. ... (e.g. "ґодо / годот" → Godot, "гд скрипт" → GDScript, "тресы" → `.tres`)
PROBLEM: **`/voice` is not a Desktop feature.** It is documented for the CLI, agent view and the VS Code extension. The Desktop page never mentions dictation. So the `language` setting does not control the dictation the engineer actually uses in the Desktop Code tab. The automatic recognition hints (project name, branch) are also CLI-only.

**The glossary is the only real mitigation, and it contains a Russian form.** "тресы" uses the letter "ы", which does not exist in Ukrainian. The engineer's rule is "Never reply in Russian".

**"Spell identifiers and file names" is impractical by voice.**
EVIDENCE: - https://code.claude.com/docs/en/voice-dictation: "Speak your prompts in the Claude Code CLI"; also supported in agent view and the VS Code extension; "your current project name and git branch name are added as recognition hints".
- https://code.claude.com/docs/en/desktop: dictation not mentioned.
- memory.md missed-01.
FIX: **Reword §3.4:** "`language` sets the reply language. It also sets `/voice` dictation, but only in the CLI (e.g. Rider's terminal, after `claude update`). Record which dictation tool the engineer uses in Desktop and test it in M0 with about 10 project terms."

**Fix the glossary.** Replace "тресы" with Ukrainian forms ("треси / трес"). Build the glossary from the engineer's real misrecognitions in the first week, not from guesses.

**Replace "Spell identifiers"** with: "Say the issue number and describe the thing. The agent finds the file and reads its name back before editing."

## [humans-12] MINOR — §4.6 Context hygiene, §5.3, §10 (instructions that only work in the CLI)
QUOTE: Workflow scripts worth reusing are saved to `.claude/workflows/` (press `s` in `/workflows`) ... `/context` shows what is loaded. `/usage` shows plan consumption.
PROBLEM: The humans use the Desktop Code tab, but several instructions describe terminal UIs:
- **`/workflows` + `s`:** a keyboard progress view. Desktop shows an approval card and a Background tasks pane instead.
- **`/context` and `/usage`:** Desktop's documented equivalent is the usage ring.
- **`/btw`:** also available as Ctrl+; in Desktop.
- **`/tasks`:** the proposal itself says it is terminal-only.

The designer will look for keys that do nothing.
EVIDENCE: - workflows.md: "Run `/workflows`, select the run you want to keep, and press `s`"; "In the Desktop app, an approval card shows ... Once, Always, and Deny ... The progress view appears in the Background tasks side pane."
- desktop.md: "Click the usage ring next to the model picker to see your current context window usage and your plan usage"; "Ctrl+; on Windows to open a side chat"; "Terminal-dialog commands ... behave differently in the Code tab".
FIX: Give the Desktop equivalents first:
- usage ring (context and plan usage);
- Views → tasks pane (subagents, workflows, model);
- Ctrl+; for side questions;
- Ctrl+Shift+M / E / I (already listed).

For saving a workflow: "ask Claude to copy this run's script into `.claude/workflows/<name>.js`". Verify in M0 whether `s` works in Desktop.

## [humans-13] MINOR — §4.1 / D6 Surface and version
QUOTE: | D6 👤 | Surface and version (§4.1) | A Desktop canonical, min 2.1.281, `doctor` checks · B also CLI (must update) | **A** + update PATH CLI |
PROBLEM: The recommendation mixes A and B, so the options cannot be told apart.

It also leaves out the practical risk. The engineer reads code in Rider, and anything that launches `claude` there (the terminal, or the JetBrains integration) starts the PATH 2.1.195. That build has no Opus 5.5 and still has the PowerShell permission-check bypass that was fixed in 2.1.214.
EVIDENCE: - operations.md claude-code-version (corrected) and mf-01.
- gaps.md gap5 option C cons: "the `claude` 2.1.195 on PATH in Rider's terminal".
- operations.md plan-mode-01: "Shift+Tab (CLI and JetBrains terminal only)".
FIX: Reword D6 as a single option: "Desktop only. The PATH CLI is updated (`claude update`, human-approved) or removed, so that Rider cannot start 2.1.195. `doctor` fails when `claude --version` < 2.1.281." Drop option B.

## [humans-14] MINOR — §3.3 / §12 'Remember this' routing vs D3-A
QUOTE: "Remember this" / "запам'ятай" means `/log-intervention` (§3.3), never auto memory.
PROBLEM: D3-A keeps auto memory for "personal conveniences". But "запам'ятай …" is exactly how a human states a personal preference (e.g. "відповідай коротше"). Routing every such request to a PR-producing skill creates intervention entries and PRs for personal notes.
EVIDENCE: - AGENT_WORKFLOW.md lines 169-172 (D3-A) and 198, 694.
FIX: Rewrite: "On 'запам'ятай', the agent asks one question: 'Для проєкту (PR) чи тільки для вас?'"
- Project → `/log-intervention`.
- Personal → append to `~/.claude/CLAUDE.md` after the human approves.

## [humans-15] MINOR — §3.3 / D4 (CREDITS.md omitted)
QUOTE: (CREDITS.md appears only in Appendix D, for the Superpowers MIT notice)
PROBLEM: KICKOFF requires every third-party asset to be recorded in CREDITS.md. The designer is the main importer of assets.

The research showed that CREDITS.md has the same GitHub conflict as INTERVENTIONS.md: union works locally, but GitHub still flags the conflict. It also proposed options. The proposal does not address CREDITS.md, so the designer's asset PRs will conflict whenever the engineer's PR lands first.
EVIDENCE: - KICKOFF line 93.
- gaps.md gap6 section D and gap6-14.
FIX: Extend D4 to cover CREDITS.md. Under D4-A:
- one small file per asset, e.g. `docs/credits/<asset-slug>.md`;
- CREDITS.md generated by a runner command;
- `check` verifies that every LFS asset has a credits file.

## [humans-16] MINOR — §11.1 The designer's agent (timeline)
QUOTE: Verification it can run itself: `run check` ...; `run bots` with its data-defined scenario; `run shot <scene>` screenshots ...; then the human playtests with `run host` / `run join`.
PROBLEM: This describes the end state. The content API is designed "before M2", bots arrive in M3 and levels in M4 (KICKOFF §7).

The proposal does not say what the designer's agent can do in M0–M2. Her first weeks are undefined, and her skills cannot be exercised when M0 is "proven".

It also does not say how a non-coder starts a playtest.
EVIDENCE: - KICKOFF §7 milestones.
- KICKOFF §3.4: the content API lives in ARCHITECTURE.md.
FIX: Add a phase table:

| Phase | What the designer's agent does |
|---|---|
| M0–M1 | GDD skeleton open questions; `mechanic` issues; review of the content-API draft |
| M2 | First content `.tres` against the content API, with `check` |
| M3 | Bot scenarios |
| M4 | Level pieces with `shot` |

Add one line on playtesting: "say 'запусти хост і двох клієнтів'; the agent runs `run host` / `run join`".

# LENS config

OVERALL:
I found real problems in Appendix A and in the guard design. The hook JSON shape is valid, and the Git Bash quoting of "$PYTHON_BIN" works on this machine (tested). But the allow list itself undermines the security layers it relies on.

Two allow rules are blockers:
- `git log/diff/show *` pre-approves `--output=<file>`. I used it locally to overwrite a guard script with a no-op.
- `git fetch *` pre-approves `--upload-pack=<cmd>`, which ran a local command.

Major issues:
- The deny rule `git push * :*` ends in the documented `:*` suffix, so it never matches a literal colon. Depending on how it is normalised it either never matches or denies every feature push.
- The guard fails open in five ways: a Python crash (exit 1), a timeout, PYTHON_BIN unset (127), profile output breaking JSON "ask", and an unset role. Its literal patterns miss git abbreviations (`--no-veri` bypassed pre-push), lowercase `core.hookspath`, and `GIT_CONFIG_*` (tested).
- The guard matcher misses the Monitor tool and Desktop's `mcp__ccd_pr__set_auto_merge`.
- "`.claude/` writes always prompt" is false in auto mode and after the session-scoped approval.
- `/`-anchored ask rules and ownership checks do not apply inside `.claude/worktrees/<n>`.
- The pre-push hook would block `run publish`'s force-with-lease.
- The gh wildcards allow token printing, `-R` to any repo, `--body-file` exfiltration, issue-body overwrite, and setting Done directly.
- `git switch -f/-C` and `git worktree add -B/-f` are pre-approved.
- The recursive-rm ask patterns miss common flag orders while Accept edits auto-approves rm.

Minor issues: gaps in the push deny list (main not last, refs/heads/main, -d, --prune, --mirror), jsonc comments that would make the whole settings file a Settings Error, the "unless plan mentions" workflow rule that cannot be implemented, CODEOWNERS being self-editable, an unenforced subagent WebFetch restriction and null `hooks:`, and unstated PowerShell 5.1 rules.

Every fix is concrete and can be checked by the M0 Guard and Permissions tables the draft already plans; I recommend adding each cited command as a row.

Test artifacts are in C:\Users\xperi\AppData\Local\Temp\claude\D--prime-game\40c5c58a-0dc5-4821-beca-a406804c7d8a\scratchpad\cfgreview (docs snapshots, the gt\ scratch git repos, and cmdtest\). No file in D:\prime-game was modified.

## [config-1] BLOCKER — Appendix A allow list; §8.1; §5.1 / Appendix C reviewer shell guard
QUOTE: "Bash(git status *)", "Bash(git diff *)", "Bash(git log *)", "Bash(git show *)"
PROBLEM: These allow rules are redundant (the draft says in §8.1 that built-in read-only commands need no rule), and they also pre-approve `git log/diff --output=<file>`. That flag writes chosen content to any path. Only redirect and `tee` targets are checked against protected paths, not `--output=`. So in every mode, including Accept edits (D16), the agent can overwrite `.claude/hooks/guard.py` or `.claude/githooks/pre-push` without a prompt. That silently disables both D13 layers. The reviewer subagents' shell guard allows `git diff|log|show`, so they are not read-only either.
EVIDENCE: Local test with git 2.49.0.windows.1 in scratchpad\cfgreview\gt\work: `git log -1 --format='tformat:import sys; sys.exit(0)  # neutralized %h' --output=.claude/hooks/guard.py` returned rc=0 and replaced the guard. The replaced guard then exited 0 instead of 2. `git diff HEAD~1 --output=../../outside.txt` wrote outside the repo. On https://code.claude.com/docs/en/permissions#wildcard-patterns, `git log --output=<file> main` is listed as a command that `Bash(git log * main)` matches. The #redirections section checks only >, <, and tee targets.
FIX: Delete the git status/diff/log/show (and rev-parse, branch --list) allow entries and their PowerShell twins, so these commands stay on the built-in read-only path. The guard (§7.2) and the subagents' frontmatter shell allowlist should reject `--output`, `--ext-diff` and `--textconv` on any git command. Add a Guard-table row to M0 that proves `git log --output=.claude/hooks/x` is blocked in both shells.

## [config-2] BLOCKER — Appendix A allow list
QUOTE: "Bash(git fetch *)"
PROBLEM: `git fetch --upload-pack=<cmd> <local path>` runs <cmd> on the local machine. Allowing `git fetch *` (and its PowerShell twin) therefore pre-approves arbitrary command execution in every mode. That undermines the deny list, the guard, and §8.1's own principle that interpreter wildcards are ACE.
EVIDENCE: Local test: `git fetch --upload-pack='echo UPLOADPACK-RAN >&2; false' ../remote.git` printed UPLOADPACK-RAN. git ran the string through a shell. The permissions doc's own example table shows that option-bearing git forms (`-c core.fsmonitor=<script>`) are exactly how ACE slips through wildcards.
FIX: Replace it with exact rules: `Bash(git fetch origin)`, `Bash(git fetch origin main)`, `Bash(git fetch --prune origin)`, plus PowerShell twins. The guard should deny `--upload-pack`, `-u` on fetch/pull/clone, and `--receive-pack`/`--exec` on push.

## [config-3] MAJOR — Appendix A deny list
QUOTE: "Bash(git push * :*)"
PROBLEM: The permissions doc says a pattern ending in `:*` is the legacy trailing-wildcard suffix (`Bash(ls:*)` = `Bash(ls *)`). So the colon is never matched literally, and this rule can never mean 'a refspec starting with :'. Depending on how the remaining `git push * ` is normalised, it either never matches or matches every `git push <remote> <branch>`. In the second case it is a deny, which beats allow, so it would block every feature push D15 wants allowed. Any deny pattern ending in `:*` has the same problem, including `*:*` and `origin :*`.
EVIDENCE: https://code.claude.com/docs/en/permissions#wildcard-patterns: "The `:*` suffix is an equivalent way to write a trailing wildcard ... The `:*` form is only recognized at the end of a pattern."
FIX: Drop this rule and leave colon-refspec deletes to the pre-push hook (it already blocks `:feat/1`, gap1-20) and to the guard. Add an M0 lint that rejects any permission rule ending in `:*` unless the colon form is intended.

## [config-4] MAJOR — §7.2 PreToolUse guard; §7 intro; Appendix A hooks
QUOTE: "command": "\"$PYTHON_BIN\" \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.py\"", "timeout": 10  /  "This layer sees the command text before anything runs."
PROBLEM: The guard fails open in several ways, and its spec matches text naively.
(a) An uncaught Python exception exits 1, which is non-blocking.
(b) A hook that hits its timeout does not block PreToolUse.
(c) If PYTHON_BIN is unset, bash exits 127 (non-blocking). The SessionStart doctor uses the same PYTHON_BIN, so nothing warns.
(d) Git Bash sources the user profile. Any echo in it breaks the JSON `permissionDecision:"ask"` that D14 relies on, silently on exit 0.
(e) If PRIME_GAME_ROLE is unset, the behaviour is undefined.
The listed patterns are also bypassable:
- Git accepts abbreviated long options: `--no-veri` skips pre-push, and `--dele` deletes.
- Config keys are case-insensitive: `-c core.hookspath=`.
- `GIT_CONFIG_COUNT/KEY_0/VALUE_0` in the environment disables hooksPath.
- `git config set|--unset|--local core.hooksPath` gets past `Bash(git config core.hooksPath *)`.
EVIDENCE: hooks.md #other-exit-codes ("exit code 1 ... proceeds"; "A hook that can't start lands in the same non-blocking bucket"); #timeouts ("A timed-out command ... hook doesn't block the tool call"); hooks-guide #hook-json-has-no-effect (Git Bash sources profile; on exit 0 nothing reported). Local tests (git 2.49):
- `git push --no-veri origin feat/1:feat/3` bypassed a blocking pre-push hook (feat/3 created).
- `git push --no-verify origin --dele feat/3` deleted the branch.
- `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hookspath GIT_CONFIG_VALUE_0=/dev/null git push ...` created feat/21 past the hook.
- `git config set core.hooksPath hooks3` worked.
- `env -u PYTHON_BIN bash -c '"$PYTHON_BIN" x.py'` returned rc=127.
FIX: Make the guard fail closed:
- Wrap the command, e.g. `[ -n "$PYTHON_BIN" ] || { echo 'guard: PYTHON_BIN unset' >&2; exit 2; }; "$PYTHON_BIN" "$CLAUDE_PROJECT_DIR/.claude/hooks/guard.py"; rc=$?; [ $rc -eq 0 ] || exit 2`.
- Inside the script, use a top-level try/except that exits 2.
- Use exit 2 (not JSON) for every hard deny.
- Raise the timeout to about 30 s, and make no network or gh calls in the guard.
- Missing role → ask.
- doctor asserts that `bash -c true` prints nothing.

For matching:
- Parse argv with shlex, and handle PowerShell `&`, `--%` and `git.exe`.
- Treat any `--no-veri*` / `--no-verif*` prefix as no-verify, and any `--del*`, `-d`, `--prune`, `--mirr*` or `--all` as delete/force.
- Match `core.hookspath` case-insensitively anywhere in the text, including GIT_CONFIG_* and `$env:GIT_CONFIG*`.
- Return ask on indirection it cannot resolve: iex, Invoke-Expression, Start-Process, cmd /c, bash -c, sh -c, -EncodedCommand.
- Add the git config forms to deny: `Bash(git config * core.hooksPath*)`, `Bash(git config --unset*)`.

## [config-5] MAJOR — §7.2 guard matcher; §7.2 'Remaining gaps'; §8.4 'gh pr merge by an agent: ask'
QUOTE: "PreToolUse guard hook, matcher `Bash|PowerShell|Edit|Write|NotebookEdit`"
PROBLEM: Two tool routes bypass the guard and the `gh pr merge` ask rule.
(1) The `Monitor` tool runs shell commands under the Bash permission rules, but the guard's matcher does not include it. For example, `git push origin HEAD` is allowed by rule and never reaches the guard.
(2) The Desktop Code tab, the canonical surface (D6), exposes `mcp__ccd_pr__set_auto_merge`. Its own description says that in auto mode the app may approve it without asking. That lets an agent land a PR without a human merging, which contradicts D15's 'humans merge after review' and is absent from the Remaining gaps list.
EVIDENCE: https://code.claude.com/docs/en/tools-reference.md#monitor-tool: "When Monitor runs a command, it uses the same permission rules as Bash". This session's own deferred tool list includes mcp__ccd_pr__set_auto_merge. Its schema says: "Enabling lands code without another look, so the user is asked to approve (in auto mode the app may approve without asking...)".
FIX: - Add `Monitor` to the guard's exact-match group, and make the guard read `tool_input.command` for it.
- Add a second matcher group `^mcp__ccd_pr__set_auto_merge$`. A separate group keeps the first one on exact matching. Putting regex characters in the same string would make `Write` match `TodoWrite`.
- Add `"mcp__ccd_pr__set_auto_merge"` to `ask`, or to `deny` if D15 = deny.
- List Desktop MCP PR tools under Remaining gaps.

## [config-6] MAJOR — §7 intro; §8.1; §8.3 (Auto later); §7.2 githooks location
QUOTE: "`.claude/` is a protected path, so writes there always prompt, even for agents." / "Writes to `.claude/`, `.git/` and `.idea/` always prompt (protected paths)."
PROBLEM: This is false in the modes the draft plans to allow. In auto mode, protected-path writes go to the classifier, not a prompt. In default/acceptEdits, the prompt offers a session-wide 'allow Claude to edit files in this project's .claude folder'. Shell writes through non-redirect flags (see the git --output finding) are not checked at all. The integrity of the guard, the githooks and the settings rests on this claim.
EVIDENCE: https://code.claude.com/docs/en/permission-modes#protected-paths table: `auto` → "Routed to the classifier"; the session-scoped option is quoted under the same section. permissions research note mf-04.
FIX: - Add explicit ask rules. Ask rules still prompt in auto mode, and they are checked even when a hook returns allow: `Edit(/.claude/hooks/**)`, `Edit(/.claude/githooks/**)`, `Edit(/.claude/settings.json)`, `Edit(/.claude/settings.local.json)`, `Edit(/.claude/agents/**)`, `Edit(/.claude/skills/**)`, `Edit(/.github/CODEOWNERS)`.
- Have the guard return ask for shell commands that name these paths.
- Reword §7 and §8.1 to 'prompt in Manual/Accept edits; classifier in Auto unless an ask rule matches'.

## [config-7] MAJOR — §4.3 D8 worktrees; Appendix A ask rules; §7.3 D14; §7.2 githooks
QUOTE: "`git worktree add .claude/worktrees/<n> -b <area>/<issue>-<slug>`" with "Edit(/.github/workflows/**)", "Edit(/addons/**)"
PROBLEM: A leading `/` anchors to the session's primary working directory. When the main-checkout session edits `.claude/worktrees/<n>/addons/...` or `.../.github/workflows/...`, these ask rules do not match. `.claude/worktrees` is also exempt from the protected-path check. D14's CODEOWNERS matching fails the same way if paths are made relative to CLAUDE_PROJECT_DIR, which stays at the main checkout. A relative `core.hooksPath` resolves against each worktree's root. So pushes from a worktree run that worktree's copy of `.claude/githooks/pre-push`, which may sit on the exempt path and can be changed on the feature branch.
EVIDENCE: permissions.md #read-and-edit: "/path ... <primary working directory>/path"; permission-modes.md protected dirs: "`.claude`, except for `.claude/worktrees`"; hooks.md: "${CLAUDE_PROJECT_DIR} stays put"; gap1-18 (git-config core.hooksPath: relative to where hooks run).
FIX: - Use depth-independent ask patterns: `Edit(**/.github/workflows/**)`, `Edit(**/addons/**)`, `Edit(**/.claude/hooks/**)`, `Edit(**/.claude/githooks/**)`.
- In the guard, compute repo-relative paths by walking up from `tool_input.file_path` to the worktree root (`.git` file or project.godot), as the §7.1 hook already does.
- Have doctor set `core.hooksPath` to the absolute path of the main checkout's `.claude/githooks`.
- Add an M0 Guard-table row for edits under `.claude/worktrees/<n>/`.

## [config-8] MAJOR — §4.5 step 4 vs §7.2 git pre-push hook (D13)
QUOTE: "`tools\run.cmd publish`, which rebases on `origin/main` ... (force-with-lease is allowed only on the task's own branch)" vs "it blocked a push to main, `+main`, `--force`, `--force-with-lease` and `--delete`"
PROBLEM: The tested pre-push hook blocks every non-fast-forward push. It cannot tell `run publish`'s force-with-lease from any other force. So once a feature branch has been pushed, the second `run publish` (rebase, then push) is always rejected, and the only escapes (`--no-verify`, a hooksPath override) are exactly what the guard denies. The research flagged this as an open policy choice (gap1 note, point (a)), but the draft does not resolve it.
EVIDENCE: gaps.md gap-1 answer: "It cannot tell a force-with-lease rebase of your own branch from a destructive force ... Policy choice: allow non-ff on your own `<area>/<issue>-*` branches, or require a fresh branch name after a rebase." gap1-20 local test.
FIX: Add this as a D13 sub-decision.
- A: pre-push allows non-fast-forward only when the remote ref matches `refs/heads/<area>/<n>-*`, equals the current local branch, and is not main. It still blocks all deletions and main.
- B: publish never force-pushes; after a rebase it pushes to a new suffixed branch and retargets the PR.

Test the chosen rule in the M0 Guard table: publish twice after a rebase.

## [config-9] MAJOR — Appendix A allow list (gh); §8.4 'Routine GitHub writes: allow'
QUOTE: "Bash(gh issue comment *)", "Bash(gh issue create *)", "Bash(gh issue edit *)", "Bash(gh auth status *)", "Bash(gh project item-edit *)"
PROBLEM: These wildcards pre-approve much more than the session protocol needs:
- `gh auth status -t/--show-token` prints the GitHub token into the transcript.
- `-R/--repo` lets the agent comment on or create issues in any public repo under the human's identity.
- `--body-file <any path>` posts any local file. Combined with WebFetch allowed for github.com and raw.githubusercontent.com (a prompt-injection source), this is an exfiltration channel with no prompt.
- `gh issue edit -b/--body/--title/--remove-*` silently overwrites the issue, which KICKOFF makes the only source of truth.
- `gh issue comment --delete-last/--edit-last` removes handoff comments.
- A raw `gh project item-edit` can set Done, which bypasses `run board move`'s 'refuses Done' and auto-closes the issue (gap2-19).
EVIDENCE: Local `gh auth status --help` (gh 2.88.1): "-t, --show-token  Display the auth token". `gh issue comment --help`: "--delete-last", "--edit-last", "-R, --repo". `gh issue edit --help`: "-b, --body", "--remove-assignee", "--remove-project". gaps.md C1: "The allowlist then only needs the runner."
FIX: - Narrow to `gh auth status --active --json *`.
- Drop the direct `gh project item-edit/item-add` allows, because C1 routes board moves through the runner.
- Add ask rules, which beat allow: `Bash(gh * -R *)`, `Bash(gh * --repo*)`, `Bash(gh issue edit * --body*)`, `Bash(gh issue edit * -b *)`, `Bash(gh issue edit * -F *)`, `Bash(gh issue edit * --title*)`, `Bash(gh issue edit * --remove-*)`, `Bash(gh issue comment * --delete-last*)`, `Bash(gh issue comment * --edit-last*)`, `Bash(gh pr review *)`, `Bash(gh pr edit *)`, `Bash(gh repo sync *)`, `Bash(gh secret *)`, `Bash(gh variable *)`, `Bash(gh ruleset *)`, plus PowerShell twins.
- Have the guard check that `--body-file` paths are under the scratchpad or `tools/out`.
- `gh pr review --approve` from the other human's token is the only server-side gate in D22 A–C, so it must never be pre-approved.

## [config-10] MAJOR — Appendix A allow list; §8.4 'Destructive git ... ask'
QUOTE: "Bash(git switch *)", "Bash(git worktree add *)"
PROBLEM: `git switch -f/--discard-changes` throws away uncommitted work, and `git switch -C <existing>` resets a branch. Both are pre-approved, although §8.4 puts restore, reset and checkout -- under ask. For the designer, whose agent works in the main checkout next to the open editor (D8, D19), this can silently wipe hand-made scene edits. `git worktree add -B` resets a branch, `-f` checks out a branch already used elsewhere, and a target path outside the repo writes files outside the working directory without a prompt.
EVIDENCE: git-switch docs: "-f, --force  An alias for --discard-changes"; "-C ... if <new-branch> already exists, it will be reset to <start-point>". git-worktree docs: -B resets, -f overrides safeguards.
FIX: Keep the allows but add ask rules, which beat allow: `Bash(git switch *-f*)`, `Bash(git switch *--discard-changes*)`, `Bash(git switch *-C *)`, `Bash(git switch *--force*)`, `Bash(git worktree add *-B *)`, `Bash(git worktree add *-f*)`, `Bash(git worktree add *--force*)`, plus PowerShell twins. Or narrow the allow to `Bash(git switch -c *)` and `Bash(git worktree add .claude/worktrees/*)`.

## [config-11] MAJOR — Appendix A ask list; §8.3 D16 (Accept edits)
QUOTE: "Bash(rm -r *)", "Bash(rm -R *)", "Bash(rm -rf *)", "Bash(rm -fr *)"
PROBLEM: Under Accept edits, the recommended starting mode, `rm` on in-scope paths is auto-approved. These ask rules then miss common recursive forms: `rm -f -r core/`, `rm -Rf x`, `rm -rfv x`, `rm --recursive x`, `rm -dr x`. The KICKOFF §6 requirement ('rm -rf-style deletes outside tools/out/') then depends entirely on a guard that can fail open (see the guard finding).
EVIDENCE: permission-modes.md line ~228 and the permissions note permission-modes-01: acceptEdits auto-approves mkdir/touch/rm/rmdir/mv/cp/sed on in-scope paths. Bash rules are plain text wildcards; a rule without `*` before the flag only matches that exact flag spelling.
FIX: Use flag-position-independent ask patterns: `Bash(rm *-*r*)`, `Bash(rm *-*R*)`, `Bash(rm *--recursive*)`. False positives such as `rm -f my-report` only cost a prompt. Keep deletes in `tools/out` on the runner's `clean`. In the guard, parse rm/Remove-Item flags properly rather than by substring.

## [config-12] MINOR — Appendix A deny list (push); §8.4 row 'Force/delete/main pushes ... deny'
QUOTE: "Bash(git push * main)", "Bash(git push * HEAD:main)", "Bash(git push * *:main)", "Bash(git push * --delete *)"
PROBLEM: These rules must match the whole command text, so many forms fall through to the allow rule `Bash(git push origin *)`:
- `git push origin main -u` or `main --tags` (main not last);
- `git push origin refs/heads/main` and `HEAD:refs/heads/main`;
- `git push origin HEAD` while on main;
- `git push origin -d feat` (short -d);
- `--prune` and `--mirror` (both delete remote refs; `--mirror` also force-updates);
- abbreviations such as `--dele` and `--mirr`.
The pre-push hook catches these at the git level. But §8.4 presents the deny list as covering them, so humans may approve relaxations on that basis.
EVIDENCE: Local tests: `git push --no-verify origin --dele feat/3` deleted the branch, and `git push --mirr --dry-run origin` showed a "(forced update)". permissions.md: "A rule with no `*` matches one exact command" and `*` placement semantics.
FIX: Add `Bash(git push * main *)`, `Bash(git push *refs/heads/main*)`, `Bash(git push * -d *)`, `Bash(git push *--prune*)`, `Bash(git push *--mirr*)`, `Bash(git push *--dele*)`, `Bash(git push *--all*)`, plus PowerShell twins. In §8.4, state that the deny list is a best-effort first layer and that the pre-push hook is the authoritative git check.

## [config-13] MINOR — Appendix A code block
QUOTE: ```jsonc ... "availableModels": ["opus", "sonnet", "haiku"],            // D10
PROBLEM: Settings files must be strict JSON. The `//` comments (on `availableModels` and on the push allow line) are a Settings Error. Desktop then offers to 'continue without the broken settings', which would silently drop every deny rule and the guard hook. The draft is otherwise valid JSON once the comments are stripped (checked).
EVIDENCE: settings.md line 536: "Settings files are strict JSON: a `//` comment or a trailing comma is a syntax error"; line 607: "continue without the broken settings". Local check: `json.loads` on Appendix A fails at line 4 col 62; after stripping comments it parses (44 allow, 29 ask, 20 deny).
FIX: Move the comments into the proposal prose. In M0, make `verify`/CI and `doctor` parse `.claude/settings.json` with `json.load`, and fail on `/status` Settings Warnings for skipped rules.

## [config-14] MINOR — §7.2 guard bullet; §7.3 D14
QUOTE: "edits to `.github/workflows/**` unless the issue plan mentions them (prompts via `ask`)" / "reads ... the committed `.github/CODEOWNERS`"
PROBLEM: The 'unless the plan mentions them' condition cannot be implemented. Plans live in `~/.claude/plans` or on GitHub, which the guard cannot read cheaply, and the `Edit(/.github/workflows/**)` ask rule prompts anyway, because hooks cannot loosen ask rules. D14 reads the working-tree CODEOWNERS, which the agent can edit itself (it is not protected and not in the ask list), so a designer session could widen its own ownership before editing engine code.
EVIDENCE: permissions.md #extend-permissions-with-hooks: "a matching ask rule still prompts even when the hook returned \"allow\"". permission-modes.md protected list does not include `.github/`.
FIX: Say workflow edits always prompt (this matches KICKOFF's 'confirmation'). In the guard, read ownership from `git show origin/main:.github/CODEOWNERS`, or from a committed role→paths map, and add `Edit(**/.github/CODEOWNERS)` to ask.

## [config-15] MINOR — §5.1 shared rules; Appendix C
QUOTE: "WebFetch (`docs.godotengine.org` only)" / "hooks:   # frontmatter PreToolUse: shell limited to ..."
PROBLEM: Nothing enforces the docs.godotengine.org-only restriction. The tools list can't scope domains, and the shared allow list also pre-approves github.com and raw.githubusercontent.com. The placeholder `hooks:` parses as YAML null, so a literal copy would leave the reviewers with unguarded shells. The frontmatter guard is described only for 'shell' and would also need `Monitor`. Like the settings guard, it needs to fail closed (see the guard finding).
EVIDENCE: hooks.md #hooks-in-skills-and-agents (same schema as settings: `PreToolUse: - matcher: ... hooks: - type: command`); tools-reference Monitor uses Bash rules; subagents note mf-04 (read-only must come from tools list plus guard).
FIX: Draft the real frontmatter: `hooks: { PreToolUse: [ { matcher: "Bash|PowerShell|Monitor|WebFetch", hooks: [ { type: command, command: <fail-closed wrapper>, timeout: 30 } ] } ] }`. The script should allowlist exact argv shapes, reject `--output`/`--ext-diff`, and reject any WebFetch host other than docs.godotengine.org with a /en/4.7/ path. Validate agents with `claude plugin validate .claude/agents` on the Desktop-equivalent version (≥2.1.233).

## [config-16] MINOR — §8.1 / §8.2 (runner and PowerShell twins); root CLAUDE.md commands
QUOTE: "Every `Bash(...)` rule has a verbatim `PowerShell(...)` twin." / "Root CLAUDE.md prescribes exactly `tools\run.cmd <cmd>` in PowerShell"
PROBLEM: The draft never states the PowerShell 5.1 command-writing rules its own permission scheme depends on:
- `&&`/`||` are parse errors in 5.1, and `;` runs the next statement even after a failure (e.g. `run verify; run publish`).
- `.cmd` wrappers must propagate the Python exit code, or a red verify looks green to the agent.
- PS 5.1 strips embedded double quotes in native-exe arguments (gap2-38), which breaks `gh --jq` and `git --format` in skills.
- It is untested whether a `$env:X='...'; <allowed cmd>` statement pair is auto-approved. If it is, `$env:PYTHON_BIN`/`GODOT_BIN` overrides turn the `tools\run.cmd *` allow into arbitrary execution, and `$env:GIT_CONFIG_*` disables pre-push (shown above).
EVIDENCE: permissions.md #powershell: "on PowerShell 7+ the chain operators `&&` and `||` split"; local PS 5.1.26100.9444; gaps.md gap2-38; local GIT_CONFIG_* test above.
FIX: - Add a PowerShell section to root CLAUDE.md: use `if ($?) { ... }` or `; if ($LASTEXITCODE -eq 0) { ... }`, never `&&`.
- run.cmd ends with `exit /b %ERRORLEVEL%`.
- Put structured args in files, not inline JSON/jq.
- Add M0 Permissions-table rows for `$env:FOO='x'; git push origin feat` and `$env:PYTHON_BIN='x'; tools\run.cmd check`. If either is auto-approved, the guard must return ask on `$env:`/`Set-Item env:` assignments to PYTHON_BIN, GODOT_BIN, GDTOOLKIT_DIR, PRIME_GAME_ROLE or GIT_*.
