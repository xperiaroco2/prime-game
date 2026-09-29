"""`check`: headless import, warnings policy, UID lint, credits and the project-wide parse/load check."""

from __future__ import annotations

import configparser
import re

from . import credits, uids
from .common import ROOT, Failure, bad, ensure_out, git_status, godot, ok, say, warn

# Warnings that must stay at Error (2). Others keep Godot's defaults: Warn is reported, not failed.
REQUIRED_WARNINGS = (
    "untyped_declaration",
    "unsafe_property_access",
    "unsafe_method_access",
    "unsafe_call_argument",
)
# Lines in `--import` output that mean a UID problem (the import itself still exits 0).
IMPORT_UID_PATTERNS = re.compile(
    r"UID duplicate detected|Duplicate UID detected|Missing \.uid file|invalid UID|Unrecognized UID"
)
IMPORT_TIMEOUT = 300
CHECK_TIMEOUT = 180
# Exit codes of a finished Godot process that still count as "ran normally".
NORMAL_EXIT = (0, 1)


def warnings_policy() -> list[str]:
    """Problems with the [debug] warning levels in project.godot."""
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str  # type: ignore[assignment,method-assign]
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    # project.godot starts with keys outside any section; give them one so configparser accepts it.
    parser.read_string("[_top]\n" + text)
    problems = []
    for name in REQUIRED_WARNINGS:
        value = parser.get("debug", f"gdscript/warnings/{name}", fallback=None)
        if value != "2":
            problems.append(
                f"project.godot [debug] gdscript/warnings/{name} is {value or 'unset'}; it must be 2 (Error)"
            )
    return problems


def run_import(label: str = "import") -> list[str]:
    """Headless import: builds the class cache and .uid files. Exits 0 even on script errors.

    Returns the UID problems it printed; raises Failure only when the import itself broke.
    """
    for attempt in (1, 2):
        res = godot(["--headless", "--import"], timeout=IMPORT_TIMEOUT, log=label)
        if res.timed_out:
            raise Failure(f"godot --import timed out after {IMPORT_TIMEOUT}s (log: tools/out/logs/{label}.log)")
        if res.rc == 0:
            break
        if attempt == 2:
            raise Failure(f"godot --import exited {res.rc} twice (log: tools/out/logs/{label}.log)")
        warn(f"godot --import exited {res.rc}; retrying once")
    return [line.strip() for line in res.lines if IMPORT_UID_PATTERNS.search(line)]


def main(files: list[str] | None = None) -> int:
    say("check")
    ensure_out()
    failed = False

    policy = warnings_policy()
    if policy:
        failed = True
        for line in policy:
            bad(line)
    else:
        ok("warnings policy (" + ", ".join(REQUIRED_WARNINGS) + " = Error)")

    before = git_status()
    uid_problems = run_import()
    if uid_problems:
        failed = True
        for line in uid_problems:
            bad(f"import: {line}")
    created = sorted(git_status() - before)
    if created:
        failed = True
        bad(
            "the import created or changed files:",
            "\n".join(created)
            + "\nNew *.uid files belong in the same commit as their script: git add them."
            "\nChanged files mean something was committed that the editor would rewrite.",
        )
    else:
        ok("import left the working tree unchanged")

    report = uids.lint(ROOT)
    if report.errors:
        failed = True
        for line in report.errors:
            bad(line)
    else:
        ok(f"UID lint ({len(report.uids)} uids)")

    credit_report = credits.check(ROOT)
    if credit_report.errors:
        failed = True
        for line in credit_report.errors:
            bad(line)
    else:
        ok(f"credits ({credits.count(credit_report.entries)}; every LFS asset outside addons/ credited)")

    args = ["--headless", "-d", "--ignore-error-breaks", "-s", "res://tools/check/check_project.gd"]
    if files:
        args += ["--", *files]
    res = godot(args, timeout=CHECK_TIMEOUT, log="check")
    if res.timed_out:
        raise Failure(
            f"project check timed out after {CHECK_TIMEOUT}s: usually a runtime error in an autoload "
            "or a tool script (log: tools/out/logs/check.log)"
        )
    summary = next((line for line in res.lines if line.startswith("CHECK summary")), None)
    if summary is None or res.rc not in NORMAL_EXIT:
        tail = "\n".join(res.lines[-15:])
        raise Failure(f"project check crashed (exit {res.rc}). Last lines:\n{tail}")
    for line in res.lines:
        if line.startswith("CHECK warning "):
            warn(line.removeprefix("CHECK warning "))
        elif line.startswith("CHECK error "):
            bad(line.removeprefix("CHECK error "))
    if res.rc != 0:
        failed = True
    else:
        ok(summary.removeprefix("CHECK summary "))

    say("check: FAILED" if failed else "check: passed")
    return 1 if failed else 0
