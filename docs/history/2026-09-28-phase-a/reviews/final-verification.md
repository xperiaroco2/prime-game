# Final verification of the revised proposal

A fresh agent, not the author, checked the revised `docs/AGENT_WORKFLOW.md` against:
- the 66 findings in `draft-review-findings.md`;
- internal consistency.

## Result

| Status | Count |
|---|---|
| RESOLVED | 58 |
| PARTIAL | 8 |
| UNRESOLVED | 0 |

The PARTIAL findings were facts-4, kickoff-4, kickoff-7, kickoff-8, kickoff-12, kickoff-17, config-6 and humans-9.

**Consistency problems found, all fixed afterwards by the author:**
1. **Designer onboarding was blocked.** On a fresh clone (no `PYTHON_BIN`, no role), the fail-closed guard blocked
   everything. Fixed with a Python fallback (`PYTHON_BIN`, else `py -3`), a guard bootstrap mode (only
   `run doctor|onboard` while the role is unset), and settings written through the runner.
2. **The Git Bash claim was backwards.** Without Git Bash, hooks fall back to PowerShell and fail **open**, not
   closed. `doctor` now treats missing Git Bash as red, and it is the first onboarding item.
3. **The D2-B merge gate needed network calls inside the guard.** Moved into a `run merge` runner command. Raw
   `gh pr merge` stays denied.
4. **The D1 row overclaimed.** It said options A–C block unreviewed merges, but code-owner review is off. Reworded:
   they block direct pushes, force pushes and deletions, and require CI.
5. **Required status checks before CI exists would block M0.** They are now added only after the CI PR has merged.
6. **Appendix C and §8.3 disagreed on ownership.** Aligned: other owner's paths → deny (designer) or ask (engineer);
   shared paths → no prompt; unlisted paths → ask; role → handle map in `ownership.json`; ask until the map exists on
   `origin/main`.
7. **"Only through the runner" was overstated.** Reworded to "without a prompt only through the runner". The guard
   now denies raw branch operations while the editor is open.
8. **§5.1 step count.** "Four things" corrected to "five things".
9. **S11 vs the new-mechanic row.** Content data is now produced only once the content API exists (M2+).
10. **Minor items:**
    - D3 options B and C are now described;
    - T6 is stated in §5.1;
    - the PostToolUse wrapper now ends with `|| exit 2`;
    - `Edit(**/tools/runner/**)` was added to ask;
    - worktree cleanup now goes through `run worktree-done`;
    - `check` can create `.uid` files, and this is now stated;
    - the `Agent(model:*)` workflow claim is tagged [inferred];
    - a shell-write guard row was added for ask-protected paths;
    - the side effects of the runtime-MCP fallback are noted.

**Known false positives, left as they are:**
- `Bash(git * --output*)` also denies a commit message that contains `--output`.
- `Bash(gh * --repo*)` also prompts on `--report`.
