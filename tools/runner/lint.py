"""`lint`: gdformat --check and gdlint over project GDScript (never addons/)."""

from __future__ import annotations

import re
from pathlib import Path

from . import instructions, pins
from .common import ROOT, Failure, Result, bad, gd_files, gdtoolkit_exe, ok, rel, run, say

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


def main(fix: bool = False, files: list[str] | None = None) -> int:
    say("lint" + (" --fix" if fix else ""))
    targets = [ROOT / f for f in files] if files else gd_files()
    targets = [p for p in targets if not rel(p).startswith("addons/")]
    failed = gdscript(targets, fix) if targets else False
    if not targets:
        ok("no GDScript files to lint")
    if not files:
        failed = instruction_files() or failed
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
