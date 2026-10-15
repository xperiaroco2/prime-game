"""The design-only fast path (#1123): a change whose every path is on the design-only list proves nothing in Godot.

The list is .github/design-only-paths.txt (PATHS), one fnmatch pattern a line; CI's `changes` job reads the same file
in plain bash and skips the Godot parts of `verify --full` for a pull request whose every changed path matches
(.github/workflows/ci.yml). Here a fast `verify` (and so `publish`'s) asks `check()`: for such a change it runs doctor
and lint (the instruction files and the docs' § references, refs.py) and leaves `check` out.

Fail safe: a path on no line, a change to the list itself (on no line), no change at all, a base that cannot be
resolved, a git command that fails or a missing list each count as not design-only, so everything runs. Never on CI,
whose parts the `changes` job picks.
"""

from __future__ import annotations

import fnmatch
import subprocess
from collections.abc import Iterable
from pathlib import Path

from . import common, lint
from .common import ROOT

# The one place the list is written; a path relative to the repository root.
LIST = ".github/design-only-paths.txt"
PATHS = ROOT / LIST
GIT_TIMEOUT = 60


def patterns(path: Path | None = None) -> tuple[str, ...]:
    """The list's patterns: its lines without blank ones and `#` comments. Empty when the file cannot be read."""
    try:
        text = (path or PATHS).read_text(encoding="utf-8")
    except OSError:
        return ()
    return tuple(line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#"))


def on_list(name: str, pats: Iterable[str]) -> bool:
    """name (a repo-relative path with `/`) matches a pattern; every `*` matches any characters, `/` included."""
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in pats)


def off_list(names: Iterable[str], pats: Iterable[str]) -> list[str]:
    """The names that match no pattern, in their order."""
    kept = tuple(pats)
    return [name for name in names if not on_list(name, kept)]


def _git(root: Path, *args: str) -> str | None:
    """git's stdout, or None when it failed or timed out. stderr apart: a warning (git's "LF will be replaced by CRLF"
    on Windows) is no path."""
    try:
        res = subprocess.run(
            ["git", *lint.PLAIN_PATHS, *args], cwd=root, capture_output=True, timeout=GIT_TIMEOUT,
            stdin=subprocess.DEVNULL,
        )  # fmt: skip
    except (OSError, subprocess.TimeoutExpired):
        return None
    return res.stdout.decode("utf-8", "replace") if res.returncode == 0 else None


def changed_paths(root: Path) -> tuple[list[str] | None, str]:
    """Every path changed against origin/<base> (lint.base_of): committed since the merge base, staged, unstaged,
    deleted or untracked, each side of a rename apart. (None, why) when the base or a git command fails; else the sorted
    paths and what was compared."""
    base = lint.base_of(root)
    merge_base = (_git(root, "merge-base", "HEAD", f"origin/{base}") or "").strip()
    if not lint.SHA_RE.fullmatch(merge_base):
        return None, f"no merge base with origin/{base} (git fetch?), so the changed files are unknown"
    diffed = _git(root, "diff", "--name-only", "--no-renames", merge_base)
    untracked = _git(root, "ls-files", "--others", "--exclude-standard")
    if diffed is None or untracked is None:
        return None, "git could not list the changed files"
    names = {line.strip().replace("\\", "/") for line in (diffed + untracked).splitlines() if line.strip()}
    return sorted(names), f"against origin/{base} (merge base {merge_base[:9]})"


def check(root: Path | None = None) -> tuple[bool, str]:
    """(True, why) when the checkout's change against its base is design-only, else (False, why)."""
    if common.IS_CI:
        return False, "on CI the `changes` job of ci.yml picks the parts"
    where = root or ROOT
    names, compared = changed_paths(where)
    if names is None:
        return False, compared
    if not names:
        return False, f"no change {compared}"
    pats = patterns(where / LIST)
    if not pats:
        return False, f"{LIST} has no pattern"
    off = off_list(names, pats)
    if off:
        more = f" and {len(off) - 1} more" if len(off) > 1 else ""
        return False, f"{off[0]}{more} not on {LIST}"
    return True, f"{len(names)} changed {'file' if len(names) == 1 else 'files'} {compared}, all on {LIST}"
