"""`lint`: gdformat --check and gdlint over project GDScript (never addons/); with no paths, also the instruction
files and the docs' § references."""

from __future__ import annotations

import re
from pathlib import Path

from . import instructions, pins, refs
from .common import GD_DIRS, ROOT, Failure, Result, bad, gd_files, gdtoolkit_exe, ok, rel, run, say

TIMEOUT = 300
# Keep each command line well under the Windows limit of 32k characters.
BATCH = 100


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


def main(fix: bool = False, files: list[str] | None = None) -> int:
    say("lint" + (" --fix" if fix else ""))
    targets = targets_of(files) if files else gd_files()
    failed = gdscript(targets, fix) if targets else False
    if not targets:
        ok("no GDScript files to lint")
    if not files:
        failed = instruction_files() or failed
        failed = section_refs() or failed
    say("lint: FAILED" if failed else "lint: passed")
    return 1 if failed else 0


def instruction_files() -> bool:
    """CLAUDE.md budgets and rule/agent frontmatter. Returns True when something failed."""
    report = instructions.check(ROOT)
    for line in report.errors:
        bad(line)
    if any("budget" in line for line in report.errors):
        bad("instruction files over budget", instructions.OVER_BUDGET_FIX)
    if report.errors:
        return True
    for line in report.notes:
        ok(line)
    return False


def section_refs() -> bool:
    """Duplicate § in a doc and § references to ARCHITECTURE and AGENT_WORKFLOW that resolve to nothing (#338).
    Returns True when something failed."""
    report = refs.check(ROOT)
    for line in report.errors:
        bad(line)
    if report.errors:
        bad(
            "a § is duplicated or a § reference does not resolve",
            "Point each at the section it means (tools\\run.cmd section <doc> prints the outline), or name its doc\n"
            "where the scope rules in tools/runner/refs.py pick the wrong one; never renumber a section.",
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
