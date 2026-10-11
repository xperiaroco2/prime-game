"""`lint`: gdformat --check and gdlint over project GDScript (never addons/); with no paths, also the instruction
files and the docs' § references.

`--changed` (#859, the agents' local lint): gdformat and gdlint only on the project GDScript changed against the base
(changed_targets), the instruction files and the § references still whole. The whole lint instead, and the output says
why, where the base cannot be resolved, where the lint's own configuration or tool changed (LINT_CONFIG), and on CI
(common.IS_CI: CI's `verify --full` lints every file however it is called). The scope of the last run is take_scope's,
for verify's history record and summary row."""

from __future__ import annotations

import re
from pathlib import Path

from . import instructions, pins, refs
from . import common
from .common import GD_DIRS, ROOT, Failure, Result, bad, gd_files, gdtoolkit_exe, ok, quiet, rel, run, say

TIMEOUT = 300
# Keep each command line well under the Windows limit of 32k characters.
BATCH = 100
# --changed lints every file when one of these changed: the lint rules, the formatter's settings, the gdtoolkit pin
# and this file (#859). A problem they bring into a file the change did not touch is found here, not on CI.
LINT_CONFIG = ("gdlintrc", "gdformatrc", "tools/runner/pins.py", "tools/runner/lint.py")
# The base a task branch is compared with when `start --base` recorded none (publish.base_key: the same git key).
DEFAULT_BASE = "main"
GIT_TIMEOUT = 60
SHA_RE = re.compile(r"\b[0-9a-f]{40}\b")
# The scope of the last lint_all in this process (take_scope), for verify's history record (#859).
_SCOPE: dict[str, object] = {}


def exe(name: str) -> str:
    path = gdtoolkit_exe(name)
    if not path:
        raise Failure(f"{name} not found: python -m pip install gdtoolkit=={pins.GDTOOLKIT}, set GDTOOLKIT_DIR")
    return path


def _batched(cmd: list[str], names: list[str], log: str) -> Result:
    rc, out, seconds = 0, [], 0.0
    for start in range(0, len(names), BATCH):
        res = run([*cmd, *names[start : start + BATCH]], timeout=TIMEOUT, log=log)
        if res.timed_out:
            raise Failure(f"{Path(cmd[0]).stem} timed out after {TIMEOUT}s")
        rc = rc or res.rc
        out.append(res.out)
        seconds += res.seconds
    return Result(rc, "".join(out), False, seconds)


PROBLEM_RE = re.compile(r"^(would reformat .+|.+\.gd:\d+: .+|.+\.gd:$|.*Unexpected (token|character).*)$")


def condense(lines: list[str]) -> list[str]:
    """Keep only file:line problems from gdtoolkit output (parse errors list every expected token)."""
    kept = []
    for line in lines:
        text = line.strip()
        if PROBLEM_RE.match(text):
            head, sep, tail = text.partition(": ")
            kept.append(head.replace("\\", "/") + sep + tail)
    return kept


def strip_cr(path: Path) -> bool:
    """gdformat writes CRLF on Windows; the repo is LF. Returns True if the file changed."""
    data = path.read_bytes()
    if b"\r\n" not in data:
        return False
    path.write_bytes(data.replace(b"\r\n", b"\n"))
    return True


def targets_of(files: list[str], root: Path | None = None) -> list[Path]:
    """Repo-relative file and directory arguments -> the .gd files to lint, in order and without duplicates.

    A directory stands for the project GDScript below it: files under `GD_DIRS`, never under a folder whose name
    starts with "." (`.claude/worktrees/` holds other sessions' checkouts, `.godot/` the import cache). A file named
    on its own is linted wherever it is. addons/ and tools/out/ are never linted, and nothing outside the project.
    """
    base = root or ROOT
    root = base.resolve()
    found: list[tuple[Path, bool]] = []
    for name in files:
        path = (root / name).resolve()
        if not path.is_relative_to(root):
            raise Failure(f"{name}: outside the project")
        if path.is_dir():
            found += [(p, True) for p in sorted(path.rglob("*.gd"))]
        elif path.is_file():
            found.append((path, False))
        else:
            raise Failure(f"{name}: no such file or directory")
    kept: list[Path] = []
    for path, from_folder in found:
        parts = path.relative_to(root).parts
        text = "/".join(parts)
        if text.startswith(("addons/", "tools/out/")) or base / text in kept:
            continue
        if from_folder and (parts[0] not in GD_DIRS or any(part.startswith(".") for part in parts)):
            continue
        kept.append(base / text)
    return kept


def main(fix: bool = False, files: list[str] | None = None, verbose: bool = False, changed: bool = False) -> int:
    """Quiet unless `verbose` (#590): a summary on success, a capped excerpt and the log's path on failure.
    `changed`: `lint --changed` (#859, the module docstring)."""
    if changed and files:
        raise Failure("lint --changed picks the files itself (those changed against the base): drop the paths")
    return quiet("lint", lambda: lint_all(fix, files, changed), verbose)


def lint_all(fix: bool, files: list[str] | None, changed: bool = False) -> int:
    say("lint" + (" --fix" if fix else "") + (" --changed" if changed else ""))
    _SCOPE.clear()
    scope = ""
    if files:
        targets = targets_of(files)
    else:
        targets = gd_files()
        if changed:
            picked, why = changed_targets(ROOT, targets)
            if picked is None:
                say(f"lint: every file: {why}")
                _SCOPE["changed_fallback"] = why
            else:
                scope = f"changed files only ({len(picked)} of {len(targets)})"
                say(f"lint: {scope}: {why}; the repo-wide checks run whole")
                _SCOPE["changed_only"] = [len(picked), len(targets)]
                targets = picked
    failed = gdscript(targets, fix) if targets else False
    if not targets:
        ok("no GDScript files to lint")
    if not files:
        failed = instruction_files() or failed
        failed = section_refs() or failed
    say(("lint: FAILED" if failed else "lint: passed") + (f", {scope}" if scope else ""))
    return 1 if failed else 0


def take_scope() -> dict[str, object]:
    """The last lint_all's scope fields for verify's record, then forgets them: `changed_only` [linted, of] when
    --changed linted the changed files only, `changed_fallback` (why) when it linted every file."""
    scope = dict(_SCOPE)
    _SCOPE.clear()
    return scope


def _git(root: Path, *args: str) -> tuple[bool, str]:
    res = run(["git", *args], timeout=GIT_TIMEOUT, cwd=root)
    return (not res.timed_out and res.rc == 0), res.out


def base_of(root: Path) -> str:
    """The branch the task branch is compared with: the parent `start --base` recorded, else DEFAULT_BASE. No `gh`
    call (publish asks the PR first): a lint stays offline and fast, and a wrong guess only lints more files."""
    good, branch = _git(root, "branch", "--show-current")
    if good and branch.strip():
        good, parent = _git(root, "config", "--get", f"branch.{branch.strip()}.primeBase")
        if good and parent.strip():
            return parent.strip()
    return DEFAULT_BASE


def changed_targets(root: Path, every: list[Path]) -> tuple[list[Path] | None, str]:
    """The files of `every` (the whole lint's targets, under root) changed against origin/<base>: committed since the
    merge base, staged, unstaged or untracked; deleted ones are gone from `every` anyway. (None, why) when the whole
    lint must run instead: no merge base with origin/<base>, a git command failed, or a LINT_CONFIG file changed. On
    CI always None (CI's lint is whole, #859). The second value says what was compared."""
    if common.IS_CI:
        return None, "on CI the lint is whole (--changed is for an agent's local run)"
    base = base_of(root)
    good, out = _git(root, "merge-base", "HEAD", f"origin/{base}")
    found = SHA_RE.search(out) if good else None  # git's output has stderr in it: a warning is no commit
    if found is None:
        return None, f"no merge base with origin/{base} (git fetch?), so the changed files are unknown"
    merge_base = found.group(0)
    good, diffed = _git(root, "diff", "--name-only", "--no-renames", "--diff-filter=d", merge_base)
    good_new, untracked = _git(root, "ls-files", "--others", "--exclude-standard")
    if not good or not good_new:
        return None, "git could not list the changed files"
    names = {line.strip().replace("\\", "/") for line in (diffed + untracked).splitlines() if line.strip()}
    config = sorted(names.intersection(LINT_CONFIG))
    if config:
        return None, f"the lint's configuration or tool changed ({', '.join(config)})"
    root = root.resolve()
    picked = [path for path in every if path.resolve().relative_to(root).as_posix() in names]
    return picked, f"the .gd files changed against origin/{base} (merge base {merge_base[:9]})"


def instruction_files() -> bool:
    """CLAUDE.md budgets, rule/agent/skill frontmatter and skill links. Returns True when something failed."""
    report = instructions.check(ROOT)
    for line in report.errors:
        bad(line)
    # A budget error ends ", budget <n>"; a link to budget.md or a budget ADR is no budget problem (#415).
    if any(", budget " in line for line in report.errors):
        bad("instruction files over budget", instructions.OVER_BUDGET_FIX)
    if report.errors:
        return True
    for line in report.notes:
        ok(line)
    return False


def section_refs() -> bool:
    """Duplicate § in a doc, unnumbered headings under numbered ones in ARCHITECTURE and AGENT_WORKFLOW, and §
    references to those two that resolve to nothing (#338). Returns True when something failed."""
    report = refs.check(ROOT)
    for line in report.errors:
        bad(line)
    if report.errors:
        bad(
            "a § is duplicated or missing, or a § reference does not resolve",
            "Point each at the section it means (tools\\run.cmd section <doc> prints the outline), or name its doc\n"
            "where the scope rules in tools/runner/refs.py pick the wrong one; a new heading takes the next free\n"
            "number under its parent (#### 9.5.<n> ...); never renumber a section.",
        )
        return True
    for line in report.notes:
        ok(line)
    return False


def gdscript(targets: list[Path], fix: bool) -> bool:
    """gdformat (--check unless fix) and gdlint. Returns True when something failed."""
    names = [rel(p) for p in targets]
    failed = False

    # gdformat and gdlint must run one after the other (gdtoolkit #428: concurrent runs race).
    res = _batched([exe("gdformat"), *([] if fix else ["--check"])], names, "gdformat")
    if fix:
        for path in targets:
            strip_cr(path)
    if res.rc != 0:
        failed = True
        for line in condense(res.lines):
            bad(line)
        if not fix:
            bad("formatting differs", "Run: tools\\run.cmd lint --fix (or tools/run.sh lint --fix)")
    else:
        ok(f"gdformat ({len(names)} files)" + (", reformatted where needed" if fix else ""))

    res = _batched([exe("gdlint")], names, "gdlint")
    if res.rc != 0:
        failed = True
        for line in condense(res.lines):
            bad(line)
    else:
        ok(f"gdlint ({len(names)} files)")
    return failed
