# Phase A session log (2026-09-28)

This is the engineer's Claude session (Desktop Code tab, Claude Code 2.1.281, model Opus 5.5). The log is written for
later agent-productivity reviews.

## Step 1: machine audit (single agent, no subagents)

**Found:**
- Windows 11 Pro 26200; PowerShell 5.1 plus Git Bash.
- Godot 4.7.2-stable official at `D:\Godot_v4.7.2-stable_win64.exe\`: a folder whose name ends in `.exe`, holding the
  console and GUI exes.
- git 2.49, git-lfs 3.6.1.
- gh 2.88.1, authenticated, but without the `project` scope.
- Python 3.14 available only through the `py` launcher. `python` on PATH is the Microsoft Store stub.
- Node 20.19.5. No pwsh.
- C: had about 10 GB free.

**Installed:**
- gdtoolkit 4.5.0 via pip into Python 3.14.
- GdUnit4 v6.2.1 into `addons/gdUnit4`, from the GitHub tag tarball via `gh api`. Its compatibility table lists Godot
  4.7 and 4.7.1.

**Verified:**
- Headless `--import`: exit 0, no `ERROR` lines.
- A throwaway GdUnit4 test ran through `runtest.cmd`: 1 passed, exit 0. The test and its reports were deleted.
- gdformat and gdlint passed on the same file.

## Step 2: environment

- Wrote `.claude/settings.local.json` with `GODOT_BIN`, `GODOT_GUI_BIN`, `PYTHON_BIN` and `GDTOOLKIT_DIR`.
- Verified that new PowerShell and Bash tool calls see them.

## Interlude: project moved to D:

- The human asked for the move.
- Copied `C:\Users\xperi\Documents\prime-game` to `D:\prime-game` with robocopy: 634 files; hashes and sizes
  identical; headless import OK.
- The session was switched to `D:\prime-game`.
- The C: copy was **not** deleted. Deletion was left to the human.

## Step 3: research (workflow `phase-a-research`, 27 agents, 66 min)

Script: `workflows/phase-a-research.js`. Raw output: `raw/phase-a-research.result.json`. Notes: `research/`.

**Shape:**
1. 10 topic researchers ran in parallel. Six Claude Code topics used the `claude-code-guide` agent type, which ran on
   **Haiku 4.5**; the other four ran on Opus 5.5.
2. Each researcher was followed by an adversarial verifier on Opus that tried to refute every claim.
3. A completeness critic found 6 gaps, and 6 gap researchers answered them.

**Verdicts per topic** (confirmed / corrected / refuted / unverifiable):

| Topic | Researcher model | Facts | Corrected + refuted + unverifiable |
|---|---|---|---|
| memory | Haiku | 30 | 13 |
| subagents | Haiku | 30 | 13 |
| skills | Haiku | 20 | 7 |
| hooks | Haiku | 28 | 13 |
| permissions | Haiku | 28 | 17 |
| operations | Haiku | 36 | 17 |
| superpowers | Opus | 44 | 8 |
| gsd | Opus | 41 | 10 |
| godot_mcp | Opus | 43 | 9 |
| godot_toolchain | Opus | 42 | 8 |

**Result:** Haiku-researched topics had **80 of 172 (46.5%)** claims corrected or rejected; Opus-researched topics
**35 of 170 (20.6%)**.

## Step 4: proposal (author plus workflow `draft-review`, 4 agents, 15 min, plus 1 fresh verifier)

1. The author read every research note and wrote draft 1 of `docs/AGENT_WORKFLOW.md` (24 decisions).
2. The adversarial review ran four lenses: facts, KICKOFF compliance, the two humans, and config security. It
   produced **66 findings: 2 blockers, 28 majors**. The two blockers were found only by **local testing**:
   `git log --output=` overwrote a guard script, and `git fetch --upload-pack=` executed a command. See
   `reviews/draft-review-findings.md`.
3. Full rewrite into draft 2: a three-tier decision register (10 human questions, 12 standing defaults, 6 agent
   calls), strict-JSON settings, and a fail-closed guard spec.
4. A fresh verifier found 58 findings resolved, 8 partial, 0 unresolved, and about 10 contradictions. All were fixed
   (see `reviews/final-verification.md`).
5. The user asked to archive all materials here.

## Side effects outside the repo (disclosed)

- Headless Godot runs by research agents rewrote `%APPDATA%\Godot\editor_settings-4.7.tres` and regenerated
  `%LOCALAPPDATA%\Godot\editor_doc_cache-4.7.res`.
- Brief Godot windows opened during screenshot tests.
- Read-only GitHub API probes ran on the account and org (branch-protection and ruleset endpoints; plan).
- Plan-tier keys were read from `~/.claude.json`.
- A `sed` temp file was created briefly in `D:\prime-game` and removed.
- `project.godot` got a new timestamp from a headless import. Its content is identical.
- No files in `D:\prime-game` changed apart from `.claude/settings.local.json`, `addons/gdUnit4/`, `docs/` and the
  `project.godot` timestamp.
