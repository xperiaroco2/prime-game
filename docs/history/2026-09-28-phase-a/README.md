# Phase A archive: research, reviews and evidence (2026-09-28)

This archive holds everything the engineer's agent produced for KICKOFF Phase A steps 1–4. It keeps the
`docs/AGENT_WORKFLOW.md` proposal auditable, and it gives future **agent-productivity reviews** real data.

## Contents

| Path | What it is |
|---|---|
| `session-log.md` | Chronology of steps 1–4, correction rates by model, disclosed side effects |
| `research/<topic>.md` (10) | Per-topic research **merged with its adversarial verification**. Each fact carries a verdict (confirmed / corrected / refuted / unverifiable) and the correction. Also: missed facts, options, recommendation, the verifier's critique, config corrections |
| `research/gaps.md` | The completeness critic's 6 gaps and their answers: GitHub Free enforcement, `gh` board mechanics, Godot UID handling, Fable billing, env in worktrees, `merge=union` on GitHub |
| `reviews/draft-review-findings.md` | 66 findings from the 4-lens adversarial review of draft 1 (facts, KICKOFF compliance, humans, config security) |
| `reviews/final-verification.md` | Fresh-agent check of draft 2, and the fixes applied afterwards |
| `workflows/*.js` | The two workflow scripts, re-runnable with the Workflow tool (they need `args`: `today`, `scratch` / `research`) |
| `raw/*.result.json` | Complete structured workflow outputs: every agent's return value |
| `agent-metrics.csv` / `.json` | Per agent: workflow, label, phase, agent type, **model actually used**, turns, tool calls, output / input / cache-read tokens, minutes |
| `local-tests/` | Scripts and small projects the agents wrote to test claims on this machine. Examples: `uidlab/` (Godot UID behaviour), `union-test/` (`merge=union`), `hooktest/` (pre-push hook), `cfgreview/` (permission-rule bypasses), `gproj/` / `fc/` / `zz_mcpfc_9q7/` (Godot CLI checks), `_loose/` (single scripts and logs) |

## Headline numbers

| Workflow | Agents | Wall time | Tool calls | Output tokens | Input + cache-write | Cache reads |
|---|---|---|---|---|---|---|
| phase-a-research | 27 | 66 min | 1,602 | 1.23 M | 3.9 M | 192 M |
| draft-review | 4 | 15 min | 144 | 0.27 M | 1.15 M | 32 M |

Also in the session, not listed in the table:
- the fresh final verifier: about 175k tokens;
- the main (author) session.

## Lessons for improving agent productivity

1. **Model choice matters for research.** Topics researched by the built-in `claude-code-guide` agent type (Haiku 4.5)
   had **46.5%** of claims corrected or rejected by Opus verifiers. Opus-researched topics had **20.6%**. For
   fact-sensitive research, use Opus or Sonnet researchers, or always pair Haiku with an adversarial verifier.
2. **Per-claim adversarial verification pays off.** It caught renamed settings, wrong syntax, version-gated features
   and, above all, the **Desktop 2.1.281 vs PATH CLI 2.1.195 skew**. That was the most pervasive source of error.
3. **A completeness critic found the biggest risks.** Items such as "private GitHub Free has no branch protection"
   and "the `gh` token lacks `project` scope" came from gap-finding, not from the planned topics.
4. **Test configs, don't just read docs.** Both blockers in the permission design were found only by running
   commands locally: `git log --output=` and `git fetch --upload-pack=`.
5. **The author's own draft had 66 issues.** Separate verification by a fresh agent (KICKOFF §10) is essential; a
   second verification round still found about 10 contradictions.
6. **Cost shape:** most tokens are cache reads by long-running verifier and researcher agents (100+ tool calls). If
   budget matters, cap turns per agent or split large topics.

## Not included here

- **Third-party copies:** Claude Code docs and changelogs, gh / GSD / Superpowers sources, and Godot engine source.
  Re-fetch them from the URLs in `research/`.
- **Regenerable engine dumps:** `extension_api.json` (12 MB) and the `--doctool` XML (6.6 MB). `doctor` regenerates
  them in M0.
- **Full subagent transcripts** (about 31 MB of JSONL). They stay machine-local, under
  `~/.claude/projects/D--prime-game/40c5c58a-0dc5-4821-beca-a406804c7d8a/subagents/workflows/`. Ask the agent to
  archive them (e.g. a zip via Git LFS) if needed.

## Privacy note (review before any push, especially if D1 = public)

These files contain no secrets or tokens (scanned). They do contain:
- the engineer's GitHub handle;
- the name, plan and seat count of the GitHub organization the engineer administers;
- the Claude plan tier;
- local paths with the Windows user name.

Decide whether to redact these before this folder is committed to a public repo.
