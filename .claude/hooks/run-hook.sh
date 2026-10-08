#!/usr/bin/env bash
# Runs a Claude Code hook of the task runner: run-hook.sh <guard|gd-edit>, hook input as JSON on stdin.
# Claude Code starts it in Git Bash (.claude/settings.json). Fail-closed: no Python, or a Python that crashes,
# exits 2, which blocks a PreToolUse call and shows the message to Claude after a PostToolUse call. A hook that
# cannot start at all fails open, so `doctor` is red without Git Bash. See docs/AGENT_WORKFLOW.md §8.
# Python: PYTHON_BIN, else the py launcher, else a python3 that really runs (on Windows `python3` can be the
# Microsoft Store stub).
hook="${1:-}"
here="${0%/*}"
root="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"

fail() {
  printf 'hook %s (fails closed): %s\n' "$hook" "$1" >&2
  exit 2
}

if [ -n "${PYTHON_BIN:-}" ]; then
  [ -f "$PYTHON_BIN" ] || fail "PYTHON_BIN points to a missing file: $PYTHON_BIN. Fix the env in ~/.claude/settings.json."
  set -- "$PYTHON_BIN"
elif command -v py >/dev/null 2>&1; then
  set -- py -3
elif command -v python3 >/dev/null 2>&1 && python3 -c "import sys" >/dev/null 2>&1; then
  set -- python3
else
  fail "no Python found. Install Python 3.11+ and set PYTHON_BIN in the env of ~/.claude/settings.json."
fi
# The guard runs before every shell command and needs only the standard library: -S skips the site module (its
# site-packages and .pth files), about 15 ms a call (#568).
if [ "$hook" = guard ]; then
  set -- "$@" -S
fi

"$@" "$root/tools/run.py" hook "$hook"
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  fail "Python exited with code $rc (see the message above)."
fi
exit "$rc"
