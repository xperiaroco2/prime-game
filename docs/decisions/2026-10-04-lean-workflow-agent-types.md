# Lean workflow agent types for the implementer and the publisher

- **Status:** Accepted for an opt-in trial (default off); the default is the engineer's call after the A/B below.
  Amended 2026-10-05 (below): on in every launch from the reset of 2026-10-06 10:00 UTC; the default flips with P3b
- **Date:** 2026-10-04
- **Deciders:** the engineer: build the token efficiency research's proposals, lean agent types once the cache-read
  probe has a result (#302 comment 5974021004); the probe found cache reads count at about 0.5-1 of list (#302
  comment 5976799046), which meets the report's condition (#302 comment 5973758335: an opt-in arg, default off, then
  an A/B on 3-4 tasks)
- **Tracking:** #302, #332; the instruction diet design #313 (PR #325, option O5 and N3: lean agent types first,
  role packs later)

## Context
A general workflow agent (agent type `workflow-subagent`) gets every tool of the session: the desktop tools (Artifact,
the browser, the session and window tools), every MCP server's tools and the skill listing. Its first call reads about
57k tokens (medians of the first call's input, cache writes and cache reads over the workflow transcripts of the 7
days to 2026-10-04: `implement` 57.0k over 128 runs, `publish` 63.7k over 139), most of it tool schemas it never
calls (2 Artifact calls in 27,899). The project's reviewer types (`.claude/agents/*.md` with a `tools:` allowlist)
start at about 19k under the same sessions: `code-reviewer` 19.3k over 139 runs, `netcode-security-reviewer` 19.5k
over 64, `godot-api-checker` 19.4k over 72. Every later call of an agent
re-reads that prefix from the cache, which counts against the limits at about 0.5-1 of list.

What the implementer and publisher roles called this week (counted by #332's plan from the same transcripts): Bash,
Edit, Write, Read and PowerShell almost always; ToolSearch (only ever to load Monitor, TaskStop, WebFetch or
WebSearch); Monitor, TaskStop, WebFetch, Grep; and a handful of single calls (Skill 4 times in 265 runs, SendUserFile
5, mark_chapter, spawn_task, dismiss_task, Artifact).

## Decision
- Two agent types, the only writable project subagents:
  - `task-implementer`: `tools: Bash, PowerShell, Read, Edit, Write, Grep, Glob, Monitor, TaskStop, WebFetch,
    WebSearch`;
  - `task-publisher`: the same plus `SendUserFile` (the screenshots of a visual PR).
  Both: `model: opus`, `disallowedTools: NotebookEdit, Agent, Skill`, no `effort`, no `permissionMode`, no `memory`.
  Their bodies hold only the shell facts and how to follow a skill without the Skill tool (read its `SKILL.md`):
  a typed workflow agent already gets the environment block with the scratchpad, `CLAUDE.md`, the git status and
  the attribution lines (checked in a `review:plan` transcript of #332's own run and in the probe below).
- A workflow arg `lean` (boolean, default off) in `issue-task` and `pr-rebase`. When true it appends `agentType` as the
  last option key: `task-implementer` for the implementer, the plan agent and the test reviewer; `task-publisher` for
  the publisher (both kinds) and `pr-rebase`'s rebase and fix agents. It changes no prompt, label, phase, schema,
  effort or model; a reviewer's own `agentType` wins. Without it every agent call stays byte-identical
  (`tools/runner/tests/workflow_snapshots/`).
- ToolSearch is not on the allowlists: an agent type loads its allowlisted tools directly (`godot-api-checker`
  called WebFetch 19 times this week with no ToolSearch).
- The Skill tool is disallowed explicitly. A `tools:` allowlist without `Skill` already leaves it out (the listing's
  saving comes from the allowlist); the `disallowedTools` entry is a guard that keeps it out if someone adds it.

### The exception to "every project subagent is read-only"
`docs/AGENT_WORKFLOW.md` §5 kept every project subagent read-only. These two names are the exception, and only
they: `tools/runner/instructions.py` (`WRITERS`) holds each to its own allowlist, requires NotebookEdit, Agent and
Skill in `disallowedTools` and rejects an `effort:` (the workflow sets it per role); every other agent keeps the
read-only check word for word. A third writable type needs a new ADR.

### Permissions: no widening
The types are a strict subset of what a general workflow agent can do today. No agent file may set
`permissionMode` (`instructions.py` rejects it for every agent): a subagent then runs in the session's mode, and the
shared permission rules, the thin guard and the `.gd` post-edit hook apply as before
([permissions ADR](2026-09-28-permissions-and-thin-guard.md)). This rule is this ADR's own.

### Model guard
`opus` is in the shared `availableModels` ([model-guard ADR](2026-09-28-model-guard-no-fable-in-shared-config.md));
a launch's `models` still wins per call. A general workflow agent inherits the session's model, so a lean agent
under a session on another model changes model; `agents-check` judges a lean agent by its file's `model:`, as it
does the reviewers.

## What an agent type changes (code.claude.com/docs/en/sub-agents and /workflows, read 2026-10-04, CLI 2.1.284)
- System prompt: the agent file's body plus the environment details Claude Code appends, not the Claude Code system
  prompt. `CLAUDE.md` files and the git status still load (no `omitClaudeMd`).
- Model: the call's `model`, then the file's `model:`, then the session's. Effort: the call's `effort` (the
  workflow's per-role effort), else the file's (none here), else the session's.
- Permission mode: under bypass, acceptEdits or auto the subagent runs in the session's mode whatever it sets; under
  default the file's would apply, hence none.
- MCP tools: none unless the allowlist names them.
- Prompt cache: agents share a cached prefix only with the same model, effort, agent type, tools, schema and working
  directory, so a lean agent never reads a general agent's prefix (they run one after another anyway).
- A new file in an existing `.claude/agents/` is seen within seconds. The manager's session resolves `agentType`
  from its own checkout (`D:/prime-game`): `lean` works only once both files are on its branch.

## The probe (#332's run)
One `claude -p` session (CLI 2.1.284, in #332's worktree, session `40b3fffd`) ran a two-agent workflow, one after the
other, on the same trivial prompt (list your tools, mark deferred ones; scratchpad, Co-Authored-By line, root
CLAUDE.md's first hard rule, a skill listing), both `effort: 'low'`:

| agent | `agentType` (meta.json) | first call: input + cache write + cache read |
|---|---|---|
| `probe:lean` | `task-implementer` | 20.6k |
| `probe:general` | `workflow-subagent` | 37.3k |

- The lean agent had exactly its 11 tools, none deferred: Monitor, TaskStop, WebFetch and WebSearch need no
  ToolSearch. The general one listed 36, 21 of them deferred.
- Both saw a scratchpad directory, a Co-Authored-By line and root CLAUDE.md's first hard rule; only the general one
  had a skill listing.
- Both requests carry `"effort":"low"` (the per-call effort applies to a typed agent) and served on opus.
- A plain CLI session has fewer tools than the desktop app's (no browser, session or window tools), so its general
  agent is smaller than the managers' (about 57k); the lean agent's tools do not depend on the session, so about
  20k plus the task prompt is what a lean agent of a desktop manager should read too. The A/B confirms it.

## The A/B (the manager's, after the merge)
3-4 real tasks launched with `lean: true`, results on #302, then the engineer decides default on or off:
- first-call context under 30k (the issue's figure); because the task prompt is part of it (RULES, notes, under
  `plan_review` the plan and its critique), each lean agent is also compared with the same role's general agents
  of the week (the medians above), and the fixed overhead (first call minus the prompt) is reported;
- no task fails for a missing tool;
- the run's effort args still apply (the transcripts' requests carry the per-role effort).

## Amendment 2026-10-05: on in every launch
The engineer's answer N4 (a) to the [weekly budget ADR](2026-10-05-weekly-budget-across-four-tracks.md)
([PR #403 comment 5992271562](https://github.com/xperiaroco2/prime-game/pull/403#issuecomment-5992271562)): the
manager passes `lean: true` on every launch from the weekly reset of 2026-10-06 10:00 UTC; the default flips after a
clean week, with P3b of that ADR.

## Alternatives
- Role packs with `omitClaudeMd` and per-role instructions (#325 O5, N3 (b)): a larger change; later, after this
  trial.
- Lean for every general agent, or on by default: not before the A/B shows no task fails for a missing tool.
- Keeping ToolSearch or the Skill tool: each costs schema or listing tokens on every call for a handful of uses a
  week; a task whose agents need a skill through the Skill tool (editing `.claude/workflows/` used
  `workflow-authoring`) stays off `lean`.
