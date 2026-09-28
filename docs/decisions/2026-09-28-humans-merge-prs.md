# Only humans merge pull requests

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Decision
Humans click Merge on GitHub or in the Desktop PR pane after CI is green. A cross-area PR is approved by the other
owner first. Agents are denied `gh pr merge` and `mcp__ccd_pr__set_auto_merge`. The designer reviews through `shot`
screenshots and a playtest, never the diff.

## Alternatives
The author says "merge" and the agent runs `tools\run.cmd merge`, which checks CI and approval. Kept as an open
question in case manual merging becomes friction.

## Consequences
One click per PR for a human. Verified 2026-09-28: `gh pr merge 999` is denied by the shared settings.
