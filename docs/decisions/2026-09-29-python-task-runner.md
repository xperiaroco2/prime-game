# A Python task runner behind `.cmd` and `.sh` wrappers

- **Status:** Accepted
- **Date:** 2026-09-29 (decided 2026-09-28, Phase A tier 3 item T4; recorded at the end of M0)
- **Deciders:** the agent (a Phase A tier 3 choice open to the engineer's veto; no veto recorded)

## Context
KICKOFF §4 asks for one cross-platform task runner, "for example one GDScript or Python entry point with thin `.ps1`
and `.sh` wrappers". A `.ps1` file stops on machines where the PowerShell execution policy forbids scripts. A GDScript
runner needs Godot to start before it can report that Godot is missing or the wrong version, and it cannot run git,
`gh` or gdtoolkit with a hard timeout and a process-tree kill as easily.

## Decision
- The core is `tools/run.py` and the `tools/runner/` package: Python 3.11 or newer, standard library only. gdtoolkit
  already needs Python, so no new dependency.
- Wrappers: `tools\run.cmd` (PowerShell and cmd; `.cmd` ignores the execution policy) and `tools/run.sh` (Git Bash and
  CI). Both use `PYTHON_BIN` when set, else the Python launchers of their shell.
- Godot, Python and gdtoolkit run without a permission prompt only through the runner; every Godot call has a hard
  timeout and kills the process tree.
- The runner tests itself (`selftest`, part of `verify`), so its logic, including the Claude Code hooks, runs in CI.

## Alternatives
- `.ps1` wrappers (KICKOFF's example): blocked by the execution policy on a default Windows install.
- A GDScript runner: no useful message when Godot is absent; awkward process control.

## Consequences
Deviates from KICKOFF §4's `.ps1` example. Root `CLAUDE.md` names the exact spellings: `tools\run.cmd <command>` in
PowerShell, `tools/run.sh <command>` in Bash. Research: `docs/history/2026-09-28-phase-a/AGENT_WORKFLOW-proposal.md`
§8.2.
