# Setting up a stage (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it for a new milestone or stage, a design handoff to
open issues from, or tasks that share files (steps 3 to 5, 7 and 8 of the skill's §2; steps 1, 2 and 6 are in the
skill itself).

## 2. Before the first launch (continued from the skill's §2)
3. **The design gate.** Code tasks wait until the stage's design PR has the engineer's review. If the design task
   has no PR yet: when another session runs it, your first wave is empty (post a plan-issue comment saying you wait
   for it, and stop); otherwise the first wave is that design task alone (`design: true`). Offer fillers that do not
   depend on the design meanwhile.
4. **Opening the stage's issues** from a design handoff (its `proposed_issues`) and the engineer's review: create
   them without waiting for a "yes" and report the list and the order (an accepted design; the trust ADR). For
   each, a body file under `<scratchpad>/manager/` with Goal, Acceptance criteria (a checklist), Out of scope, Verification, `Depends on #…`
   and `Tracking: #<plan>`, and `gh issue create --title "<area>: <what>" --label area:<x> --milestone M<k>
   --body-file <file>` (one `area:` label, which `start` needs for the branch prefix). Put the new numbers in a
   plan-issue comment.
5. **The release branch** (a milestone only, once, after the yes): from the main checkout, without leaving your
   shell anywhere else, `git fetch origin && git branch release/m<k> origin/main && git push -u origin release/m<k>
   && git worktree add D:/prime-game/.claude/worktrees/release-m<k> release/m<k>`. That worktree is yours (§5); say
   both in the first wave comment.
7. Find the files that tasks running in parallel will all touch (mode `.tres` files, `docs/ARCHITECTURE.md`,
   registries, event folders) and split ownership **up front**: who owns which class, which task creates which
   shared class (same path and class name if two may create it), whose deal places what. Otherwise add/add
   conflicts and duplicate work follow.
8. **Files shared across tracks** (the engineer's answer N5 (c); AGENT_WORKFLOW §7.1 "Parallel tracks"):
   `.claude/workflows/` and this skill change only through the tooling track (#170): an issue there, landing between
   the other managers' waves, since a change in the middle of a wave breaks their resumes (§7). A task of yours may
   change `tools/runner/` or `docs/AGENT_WORKFLOW.md`, merged between waves after `merge-check`. `merge-check` also
   pairs your PRs with every open PR into another base when both change a shared file (`tools/`, `.claude/`,
   `.github/`, `docs/AGENT_WORKFLOW.md`; its table "across bases", #207). A flagged pair: name it on that track's
   plan issue; the PR into `main` merges first (through the gate, §5), the milestone takes `main` in
   (`merge --sync-main`, §5) and its PR is rebased on that before it merges (what you do meanwhile: §5).
