# The skill listing and the account's connectors in our sessions

- **Status:** Proposed in #562; accepted when the engineer merges its PR (it changes `.claude/settings.json`, a gate
  exception of the trust ADR)
- **Date:** 2026-10-08
- **Deciders:** the engineer (the merge); the options under "Left to the engineer" are his
- **Tracking:** #562, #302 (token efficiency), #170 (AI productivity)

## Context
Every session in this repository loads two fixed blocks no agent of ours uses: the skill listing's account and bundled
skills, and the instructions of the account's MCP connectors. The setting names below were read on 2026-10-08 in the
docs and in the installed Claude Code 2.1.293 (the desktop app's `claude.exe`, whose strings hold each name):

- [`skillOverrides`](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings), per skill name:
  `"on"` (name and description), `"name-only"`, `"user-invocable-only"` (hidden from Claude, still in the `/` menu),
  `"off"` (hidden from both); absent is `"on"`. "In user, project, and local settings, Claude Code matches entries
  against skill names only." "Plugin skills are not affected by `skillOverrides`."
- [`disableBundledSkills`](https://code.claude.com/docs/en/settings-reference#disablebundledskills): "Turn off the
  skills and workflows included with Claude Code" (any settings file). The 2.1.293 binary keeps a bundled skill hidden
  from the model under it even when `skillOverrides` says `"on"`, so it would take `workflow-authoring` too.
- [`disableClaudeAiConnectors`](https://code.claude.com/docs/en/mcp#disable-claude-ai-connectors) (or
  `ENABLE_CLAUDEAI_MCP_SERVERS=false`): "Claude Code applies `disableClaudeAiConnectors` only to the connectors it
  fetches itself, not to the connectors a cloud host or the desktop app delivers." `true` in any source wins, so a
  project `true` also turns them off in the humans' own terminal sessions of this repository.
- [How connectors reach Claude Code](https://code.claude.com/docs/en/mcp#how-connectors-reach-claude-code): in "the
  desktop app's local and SSH sessions", "the desktop app registers the connectors as in-process `type: "sdk"`
  servers, and no MCP setting or `managed-mcp.json` reaches them. A user keeps a connector out of their own sessions
  by disconnecting it at claude.ai/customize/connectors."
- [`syncClaudeAiSkills`](https://code.claude.com/docs/en/settings-reference#syncclaudeaiskills): scope "User, local,
  or managed", so not the project's `.claude/settings.json`; it governs the skills Claude Code syncs into
  `~/.claude/skills/synced`, which this laptop does not have.

What our sessions load (the laptop's transcripts of 2026-10-07 and 2026-10-08; the manager sessions run in the
desktop app, which launches `claude.exe` with `--setting-sources=user,project,local`):

| Block | Who loads it | Size |
|---|---|---|
| Skill listing | each manager session (two measured, first call 67.7k and 67.4k tokens) and each general workflow agent (`lean: false`, since #557 only with a `lean_reason`); not the lean types, which have no Skill tool | 22,924 and 22,055 characters, 45 and 44 skills |
| of which: our skills and workflows | | 9 skills 3,204, 2 workflows 1,749 |
| of which: the desktop app's `anthropic-skills` plugin (17 skills: docx, pdf, chrome-browser, ...) | | 10,211 |
| of which: bundled skills (`code-review`, `simplify`, `loop`, `dataviz`, `artifact-*`, ...) | | 16 skills 7,508 (`code-review` about 1.0k of it), plus `workflow-authoring` 253 |
| MCP server instructions | every session and subagent | the Claude Docs connector 1,914 characters (every workflow agent and subagent: `task-implementer` first call 24.0-24.2k tokens, `lean-reader` 15.4k, `code-reviewer` 16.1k); a manager also `claude-in-chrome`, 2,936 in all |

The Claude Docs connector reaches the sessions under a UUID name: the desktop app delivers it in-process, so the
second row of the docs' table applies. The `anthropic-skills` plugin comes from the desktop app
(`%APPDATA%\Claude\local-agent-mode-sessions\skills-plugin\...`, "Anthropic-managed skills for Claude Desktop").

## Decision
1. `.claude/settings.json` sets 15 of the 16 bundled skills seen in the listing to `"user-invocable-only"`: out of
   the model's listing in every session of this repository, still typable as `/name` by a human. About 6.5k of the
   manager's 22.9k listing characters (7,508 less `code-review`'s entry, computed from the measured listing, see
   below).
2. Our nine skills, our two workflows and two bundled skills our instructions send the model to stay listed:
   `workflow-authoring` (a manager loads it to write a workflow script; since #557 a task agent reads
   `docs/workflow-scripts.md` instead) and `code-review` (finish-task step 2 and AGENT_WORKFLOW §4.2 route a
   docs-only or content-data diff to it; the PR's review kept it). `disableBundledSkills` stays unset. The
   instruction lint (`lint`, so `verify`) fails an entry that hides one of them, a value outside the four, and
   `disableBundledSkills: true`.
3. No connector setting in the project: `disableClaudeAiConnectors` has no effect where our managers and workflow
   agents run (desktop sessions) and would remove the humans' connectors from their terminal sessions.
4. The `anthropic-skills` plugin stays: plugin skills are out of `skillOverrides`' reach and the desktop app
   delivers it.

## Left to the engineer
- **The Claude Docs connector** (about 1.9k characters in every agent): (a) disconnect it at
  claude.ai/customize/connectors if no session of his uses it; it then leaves every surface of his account
  (recommended if unused); (b) `"disableClaudeAiConnectors": true` in the project settings: terminal and IDE
  sessions only, his included, no effect in the desktop app; (c) keep it.
- **The `anthropic-skills` plugin** (about 10.2k characters per manager session): (a) turn the unused ones off for
  his claude.ai account ("turn the skill off for your claude.ai account", the skills doc), which removes them from
  every session of his; (b) keep them. `"enabledPlugins": {"anthropic-skills@inline": false}` is not documented
  for a plugin the desktop app passes in and was not tried.

## Consequences
- A Claude Code update that adds a bundled skill lists it until it gets an entry here: `metrics`' instruction table
  shows the listing's size per role, and its growth is the sign.
- `/doctor prompt-audit` hands off to the bundled `claude-api` skill, which the model can no longer invoke.
- Measuring the effect: the settings load when a session starts in the main checkout, so the after side is a new
  manager session after the merge: `metrics --since <merge>` (its instruction table's skill listing and MCP rows) and
  the first call of that session and of its first workflow agents, against the numbers above.
