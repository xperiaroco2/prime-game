# Final verifier report on draft 2

This is the fresh verifier agent's report on draft 2 of `docs/AGENT_WORKFLOW.md`. The fixes that followed are listed
in `final-verification.md`.

## Result

I checked all 66 findings against the revised doc: 58 are RESOLVED, 8 are PARTIAL and none are UNRESOLVED. The
consistency pass found no dangling IDs or cross-references, but it did find about ten real contradictions. The most
serious one would stop the designer's onboarding on a fresh clone.

## (a) Finding status

| Lens | RESOLVED |
|---|---|
| facts | 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 |
| kickoff | 1, 2, 3, 5, 6, 9, 10, 11, 13, 14, 15, 16, 18, 19 |
| humans | 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16 |
| config | 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 |

| ID | Status | What is missing |
|---|---|---|
| facts-4 | PARTIAL | The contradiction is gone. But §6.2 now says the deny "adds nothing" and "misses … workflow stages" as untagged fact. The research had that part as [inferred], and the deny does still block the main agent's per-call overrides. |
| kickoff-4 | PARTIAL | §11 moves `tools/` work to high effort. KICKOFF §10 puts small tooling changes at medium, and S8's ⚠ text doesn't mention this. |
| kickoff-7 | PARTIAL | The §3.3 flow ("writes the entry and promotes") doesn't cover D5-C, where only the engineer's agent writes. |
| kickoff-8 | PARTIAL | `ownership.json` is "roles → globs", yet "CODEOWNERS is generated from the same map". The role → GitHub-handle mapping is never defined. |
| kickoff-12 | PARTIAL | §6.1 says the runner commands "write only to `tools/out/` and `.godot/`". But the allowlisted `check` runs `--import`, which creates `.uid` sidecars in the tree (gap3-17; §12.4 admits this). |
| kickoff-17 | PARTIAL | The runtime-MCP fallback's repo side effects are not noted: it edits `project.godot` and `.gitignore` and handles one process at a time. |
| config-6 | PARTIAL | No guard rule asks for shell commands that write to ask-protected paths (e.g. `Copy-Item x tools/run.py`). The `Edit(...)` ask rules only cover file tools. |
| humans-9 | PARTIAL | "Archiving the session removes the worktree". The EnterWorktree tool says a worktree entered by `path` is not removed by ExitWorktree, so cleanup of runner-made worktrees is undefined. Entering by `path` does work. |

## (b) Consistency problems

1. **The designer's onboarding cannot run.** §12.1 has the `onboard` skill run `doctor` and edit her user settings.
   On a fresh clone `PYTHON_BIN` is unset, so the fail-closed guard exits 2 on every Bash, PowerShell, Edit and Write
   call. The role is also unset, so §8.3 denies edits "outside `docs/`". Appendix A then pushes the fix onto the
   human, which breaks the zero-code rule.
2. **§12.1 vs §8.5.** §12.1 says "without Git Bash every hook fails", while §8.5 calls the guard "fail-closed". Per
   gap1-26, hooks fall back to PowerShell without Git Bash, where the bash wrapper errors with a non-2 exit. The guard
   then fails **open**.
3. **The D2-B merge gate needs network calls the guard may not make.** §9.2 says "a merge that the guard gates:
   `gh pr checks` must be green…". §15 says the guard makes "no network, no `gh` calls".
4. **The D1 claim about merges is wrong.** The D1 row says "A–C: GitHub itself blocks force pushes and unreviewed
   merges to main". But §9.1 keeps code-owner review off, and authors cannot approve their own PRs, so required
   approvals must be 0. Under that ruleset, unreviewed merges are **not** blocked.
5. **The ruleset can block M0.** §14 step 6 has the humans create the ruleset "with required status checks" (§9.1).
   But CI is only the 7th M0 PR, so the earlier PRs would wait forever on a check that never reports.
6. **Appendix C vs §8.3.** Appendix C denies designer edits "outside the role's paths". §8.3 denies only "the other
   owner's paths", with shared paths "no prompt" and unlisted paths "ask". Read literally, Appendix C denies her
   `docs/interventions/` and `.claude/rules/`, which §3.3 lets her promote into.
7. **"Only through the runner" is overstated.** S6 says "go only through the runner", §8.1 says "the only push
   path", and Appendix C agrees. Appendix A actually makes raw `git push *`, `git switch`, `git checkout` and
   `git rebase` **ask**, so they are possible after a prompt. The same gap undercuts §12.3 ("any branch switch or
   rebase refuse"), because the guard never checks for an open editor.
8. **§5.1** says "does four things" but lists five bullets.
9. **S11 vs §7.** S11 says new-mechanic writes "only the issue, GDD open questions and engine-requests". The §7
   new-mechanic row still produces a content-data PR with no timing qualifier.
10. **Minor:**
    - D3 option C is not described in §6.2.
    - T6's "no SessionStart hook" is not stated in §5.1.
    - The PostToolUse wrapper lacks `|| exit 2`, so if the post-edit hook crashes Claude never sees the format or
      lint results.
    - `**/tools/run*` does not protect runner helper modules in subfolders.

**Cross-references.** Every D1–D10, S1–S12 and T1–T6 exists in §1 and matches its body section, apart from the gaps
above. Every "§n.m" and Appendix A–F reference resolves to the right heading.

**Shadowing.** No allow rule is fully shadowed; the partial ones are intended (e.g. `gh issue comment *` vs
`--delete-last`). `gh auth status --active --json hosts` does not hit the `*-t*` deny. I confirmed locally that gh
2.88.1 supports `--active` and `--json hosts`. Two harmless false positives:
- `git * --output*` also denies a commit whose message contains `--output`;
- `gh * --repo*` also matches `--report`.

The D2-A merge deny is consistent across §9.2, §8.5, Appendix A and Appendix C.

## (c) Top 5 fixes still needed

1. **Unblock onboarding.** Before `PYTHON_BIN` and the role are set, the guard should allow only
   `tools\run.cmd doctor|onboard` and the edit to `~/.claude/settings.json`. Alternatively, `run.cmd` finds Python
   itself (`py -3`). Also have `doctor` go red when Git Bash is missing, and reword §12.1 to "fails open".
2. **Move the D2-B gated merge into the runner.** Add a `run merge` command that runs `gh pr checks` and the approval
   check. Keep raw `gh pr merge` denied, so the guard never needs network access.
3. **Correct the D1 row and the bootstrap order.** A–C block direct pushes, force pushes and deletions, not
   unreviewed merges. Add required status checks only after the CI PR merges (§14 step 6/7).
4. **Align Appendix C with §8.3,** using "other owner's paths" plus the shared and unlisted rules. Also:
   - add the role → handle map to `ownership.json`;
   - list `.claude/rules/`, `.claude/workflows/` and `CREDITS.md`;
   - state what the guard does when `origin/main` has no `ownership.json` yet (fail-closed would block everything
     during M0).
5. **Fix the factual slips:**
   - §6.1: say `check` can create `.uid` files;
   - §4.3: worktree cleanup via a `run` command, since archive and ExitWorktree won't remove path-entered worktrees;
   - S6/§8.1: say "without a prompt only via the runner";
   - §5.1: "five things";
   - tag §6.2's workflow-stage claim [inferred].
