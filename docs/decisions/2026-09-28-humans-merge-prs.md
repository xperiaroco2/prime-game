# Only humans merge pull requests

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)
- **Amended 2026-10-01:** in a stage the manager session merges task PRs into the milestone's `release/m<k>`
  branch, and humans merge that branch into `main`
  ([release branch per milestone](2026-10-01-release-branch-per-milestone.md)). `gh pr merge` stays denied.
- **Amended 2026-10-01 (issue #128):** a PR in the designer's area that says "agreed with the designer, relayed by
  the engineer" is merged without the designer's approval (by the engineer, or in a stage by the manager into
  `release/m<k>`); the designer looks later, and an objection is reverted by a follow-up PR
  (`docs/AGENT_WORKFLOW.md` §9).

## Decision
Humans click Merge on GitHub or in the Desktop PR pane after CI is green. A cross-area PR is approved by the other
owner first. Agents are denied `gh pr merge` and `mcp__ccd_pr__set_auto_merge`. The designer reviews through `shot`
screenshots and a playtest, never the diff.

## Alternatives
The author says "merge" and the agent runs `tools\run.cmd merge`, which checks CI and approval. Kept as an open
question in case manual merging becomes friction.

## Consequences
One click per PR for a human. Verified 2026-09-28: `gh pr merge 999` is denied by the shared settings.
