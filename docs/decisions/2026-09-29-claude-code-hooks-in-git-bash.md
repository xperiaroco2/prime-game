# Claude Code hooks run in Git Bash, with their logic in the runner

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** the engineer (Phase B, M0 stage 4; delegated to the agent)

## Context
M0 adds two Claude Code hooks: the thin guard (PreToolUse on every shell command) and the `.gd` post-edit hook
(`docs/AGENT_WORKFLOW.md` §8.2 and §8.4). The guard must be fail-closed: a crash or a missing Python blocks the call.
Facts checked on 2026-09-29 against `code.claude.com/docs/en/hooks` and on the engineer's machine (Claude Code
2.1.284, Windows 11):
- A hook that cannot start, and a hook that times out, do not block: the call goes on. Fail-closed is only possible
  from inside a process that did start.
- Exec form (`args` set) needs `command` to be a real executable on PATH. `bash` on this PATH is the WSL launcher,
  and only `${CLAUDE_PROJECT_DIR}`-style placeholders are substituted, so `PYTHON_BIN` cannot be the command.
- Shell form runs in Git Bash on Windows (PowerShell only when Git Bash is missing); `"shell": "bash"` makes it
  explicit. Git Bash starts in about 65 ms, `powershell.exe -NoProfile` in about 220 ms. There is no `pwsh` here.
- `python3` in Git Bash can be the Microsoft Store stub. The `py` launcher and `PYTHON_BIN` both work.
- A `permissionDecision: "ask"` from a hook prompts even in auto mode; the docs do not say whether it prompts in
  `bypassPermissions` mode, so that is checked live (see Consequences).

## Decision
- Every hook is a shell-form command with `"shell": "bash"`: `bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/run-hook.sh"
  <name>`. The wrapper finds Python (`PYTHON_BIN`, else `py -3`, else a `python3` that runs) and runs
  `tools/run.py hook <name>`. No Python, a missing `PYTHON_BIN`, or any exit code other than 0 and 2 becomes exit 2.
- The logic lives in the runner (`tools/runner/guard.py`, `tools/runner/hooks.py`), stdlib only, so `selftest`
  runs it in CI, where Claude Code is not installed. `run.py hook` skips the CLI imports: the guard adds about 0.2 s
  to each shell command.
- The guard protects the project's own paths, like the `Edit(**/...)` ask rules it complements: it resolves targets
  against the working directory, `cd` and the variables a command assigns. A target it cannot resolve asks when its
  text names a protected path.

## Alternatives
- Exec form with `py`: no shell, but a missing launcher fails open and `PYTHON_BIN` cannot be used.
- `powershell.exe -File hook.ps1`: always present, but 150 ms slower per call, and PowerShell 5.1 re-encodes piped
  stdin, which mangles non-ASCII paths (Phase A research, hooks.md m8).
- A bash script with `jq`: `jq` is not installed, and the logic could not be unit-tested in CI.
- A guard that matches path text only (no resolution): replayed over the 1,605 distinct shell commands of the Phase A
  and B transcripts it asked seven times, five of them for scratch copies under the temp folder and one for an
  index-only `git rm --cached`; an unattended agent would stop each time. The resolving guard asks once there, for the
  real install of GdUnit4 into `addons/`.

## Consequences
- Git for Windows is required on both machines; without Git Bash every hook fails open, so `doctor` is red.
- A hook that times out fails open. The guard's timeout is generous (30 s) for a check that takes 0.2 s.
- **Verified live on 2026-09-29** in the engineer's session, in `bypassPermissions` mode, right after wiring:
  - A guard "ask" shows the permission prompt even in bypass mode.
  - Choosing "don't ask again" in that prompt silenced the guard's later asks for the rest of the session: the hook
    still returned "ask", but no prompt appeared. Nothing was written to `settings.local.json`. So a human answers a
    guard prompt with a one-time "Yes" or "No", never "don't ask again".
  - A guard that raised an exception blocked the next PowerShell call and showed its traceback.
  - A Write of a `.gd` with an unknown identifier returned `core/…:5: Parse Error: …` to Claude after the
    reformat.
