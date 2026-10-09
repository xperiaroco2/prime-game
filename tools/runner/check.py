"""`check`: headless import, warnings policy, UID lint, credits and the project-wide parse/load check."""

from __future__ import annotations

import os
import re
import time
from dataclasses import dataclass
from pathlib import Path

from . import common, credits, lfs, uids
from .common import ROOT, Failure, Result, bad, ensure_out, git_status, godot, ok, quiet, say, skip, warn

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
# An access violation: Windows' STATUS_ACCESS_VIOLATION (0xC0000005) and a POSIX SIGSEGV as subprocess reports it.
# Godot 4.7.2 sometimes dies with it while it shuts down after the project check printed a clean summary (#442): both
# such crashes in the 326 check steps of the agents' verify and publish logs printed `CHECK summary ... errors=0` as
# their last line and none of the lines every run's engine shutdown prints after it ("ObjectDB instances were leaked
# at exit", "resources still in use at exit"). EXIT_CRASH_LOG keeps such a run's whole output.
ACCESS_VIOLATION = (0xC0000005, -11)
EXIT_CRASH_LOG = "check-exit-crash"
SUMMARY_ERRORS = re.compile(r"\berrors=(\d+)\b")
# How many such crashes project_check passed in this process since take_exit_crashes last read them (#449): verify's
# lane takes them into the step's history record (`exit_crash`), and its summary names them.
_exit_crashes = 0


def section_values(text: str, section: str) -> dict[str, str]:
    """The one-line `key=value` entries of one section of a Godot config file such as project.godot.

    Not configparser: Godot writes some values over several lines (input actions end with lines
    that are just "]" and "}"), which configparser rejects. Continuation lines have no "=" before
    any quote or bracket, so they are skipped; a section header is a line of the form [name].
    """
    values: dict[str, str] = {}
    inside = False
    for line in text.splitlines():
        if re.fullmatch(r"\[[A-Za-z0-9_./-]+\]", line.strip()):
            inside = line.strip() == f"[{section}]"
        elif inside and re.match(r"[A-Za-z0-9_./-]+=", line):
            key, _, value = line.partition("=")
            values[key] = value.strip()
    return values


def warnings_policy() -> list[str]:
    """Problems with the [debug] warning levels in project.godot."""
    debug = section_values((ROOT / "project.godot").read_text(encoding="utf-8"), "debug")
    problems = []
    for name in REQUIRED_WARNINGS:
        value = debug.get(f"gdscript/warnings/{name}")
        if value != "2":
            problems.append(
                f"project.godot [debug] gdscript/warnings/{name} is {value or 'unset'}; it must be 2 (Error)"
            )
    return problems


# A worktree's override.cfg (common.ensure_user_dir) sets these; ProjectSettings.save(), which the editor's Project
# Settings dialog calls, writes them into project.godot (probed on 4.7.2, #182). Committed, they would move every
# checkout's user://, the engineer's game data included, and every export's.
USER_DIR_KEYS = ("config/use_custom_user_dir", "config/custom_user_dir_name")


def user_dir_policy() -> list[str]:
    """Problems with the [application] user:// settings in project.godot: it must keep Godot's default folder."""
    application = section_values((ROOT / "project.godot").read_text(encoding="utf-8"), "application")
    return [
        f"project.godot [application] {key}={application[key]}: the editor copied it from a worktree's override.cfg"
        " when it saved project settings; delete the line (every checkout and export would use that user://)"
        for key in USER_DIR_KEYS
        if key in application
    ]


# --- is the import current? (#174) -----------------------------------------------------------------
# Godot rebuilds its global class cache (.godot/global_script_class_cache.cfg), the uid cache and the imported assets
# only in an import; a game started without one after `git switch` brought a new class_name script printed
# `Identifier "MousePointer" not declared`. So every import through the runner records when it started, and the
# commands that start the game (`host`, `join`, `run`, `playcheck`, `perf`, `bots`, `shot`, verify's `game` step)
# import first when a file Godot sees changed after that (ensure_import below). git writes every file a switch, pull
# or rebase changes, so its modification time is the moment it arrived (HEAD's commit time adds nothing); a deleted
# script goes with an edit of what used it.
STAMP = ".godot/runner_import.stamp"
CLASS_CACHE = ".godot/global_script_class_cache.cfg"
# Files Godot neither imports nor loads as a resource: a change to them never needs an import. Anything else counts,
# so an unknown kind of file costs at most one import more than needed.
NOT_IMPORTED = frozenset((".md", ".py", ".pyc", ".cmd", ".sh", ".ps1", ".txt", ".log", ".yml", ".yaml", ".html"))
# What an import itself writes into the project: the .uid file of a new script or shader, the .import file of a new
# asset. Written during the import, they would otherwise make the next launch import again.
WRITTEN_BY_IMPORT = (".uid", ".import")


@dataclass
class Freshness:
    """Why the project needs an import ('' when its import is current), the newest change seen and its file."""

    why: str
    newest: float
    newest_path: str
    files: int


def newest_change(root: Path, kinds: tuple[str, ...] = ()) -> tuple[float, str, int]:
    """(the newest modification time, its repo-relative path, the number of files looked at) over the files Godot
    sees: hidden files and folders (.git, .godot, .claude) and folders with a .gdignore (tools/out) are skipped, as
    Godot skips them, and so are the kinds of NOT_IMPORTED. With `kinds` (suffixes), only files of those kinds."""
    newest, where, count = 0.0, "", 0
    folders = [root]
    while folders:
        folder = folders.pop()
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        if any(entry.name == ".gdignore" for entry in entries):
            continue
        for entry in entries:
            if entry.name.startswith("."):
                continue
            try:
                if entry.is_dir(follow_symlinks=False):
                    folders.append(Path(entry.path))
                    continue
                kind = os.path.splitext(entry.name)[1].lower()
                if kind in NOT_IMPORTED or (kinds and kind not in kinds):
                    continue
                mtime = entry.stat().st_mtime
            except OSError:
                continue
            count += 1
            if mtime > newest:
                newest, where = mtime, Path(entry.path).relative_to(root).as_posix()
    return newest, where, count


def stamp_time(root: Path) -> float | None:
    """When the last import through the runner started (None: no import through the runner yet)."""
    try:
        return float((root / STAMP).read_text(encoding="ascii").split()[0])
    except (OSError, ValueError, IndexError):
        return None


def write_stamp(root: Path, when: float) -> None:
    """Record `when` exactly (repr round-trips a float): a rounded value could fall just below the time of a file the
    import wrote, and the next launch would import again."""
    path = root / STAMP
    if path.parent.is_dir():
        path.write_text(f"{when!r}\n", encoding="ascii", newline="\n")


def freshness(root: Path | None = None) -> Freshness:
    """Whether the project's import is current: its class cache exists, the runner recorded an import, and no file
    Godot sees changed after that import started."""
    root = root or common.ROOT
    newest, where, count = newest_change(root)
    if not (root / ".godot").is_dir():
        return Freshness("no .godot/ yet (a fresh checkout or worktree)", newest, where, count)
    if not (root / CLASS_CACHE).is_file():
        return Freshness(f"no {CLASS_CACHE}", newest, where, count)
    stamp = stamp_time(root)
    if stamp is None:
        return Freshness(f"no {STAMP} (the last import was not the runner's)", newest, where, count)
    ahead = newest - time.time()
    if ahead > 0:
        # Clock skew, or a file copied or extracted with its original time: the stamp never takes a future time
        # (run_import), so this file makes every launch import, loudly, until it is touched.
        return Freshness(
            f"res://{where} is dated {ahead:.0f}s in the future, so every launch imports until it is touched"
            f" (touch {where})",
            newest,
            where,
            count,
        )
    if newest > stamp:
        return Freshness(f"res://{where} changed after the last import", newest, where, count)
    return Freshness("", newest, where, count)


def run_import(label: str = "import") -> list[str]:
    """Headless import: builds the class cache and .uid files. Exits 0 even on script errors.

    Returns the UID problems it printed; raises Failure only when the import itself broke. Records in STAMP when it
    started, or the newest file the import wrote itself (WRITTEN_BY_IMPORT) if that is later, but never a time after
    the import ended: a stamp in the future would report every real change before that time as `current`. In CI the
    import never sees an LFS pointer file (lfs.aside, #515): an import of one fails and rewrites its .import file, so
    Godot imports a stand-in of its type in its place, or, for a type without one, nothing.
    """
    started = time.time()
    with lfs.aside(lfs.ci_pointers()):  # in CI, no LFS pointer file reaches the import (#515)
        for attempt in (1, 2):
            res = godot(["--headless", "--import"], timeout=IMPORT_TIMEOUT, log=label)
            if res.timed_out:
                raise Failure(f"godot --import timed out after {IMPORT_TIMEOUT}s (log: tools/out/logs/{label}.log)")
            if res.rc == 0:
                break
            if attempt == 2:
                raise Failure(f"godot --import exited {res.rc} twice (log: tools/out/logs/{label}.log)")
            warn(f"godot --import exited {res.rc}; retrying once")
    record_import(started)
    return [line.strip() for line in res.lines if IMPORT_UID_PATTERNS.search(line)]


def record_import(started: float) -> None:
    """Record in STAMP an import that started at `started` (time.time()) and has just succeeded: that time, or the
    newest file the import wrote itself (WRITTEN_BY_IMPORT) if later, never after now. run_import and the post-edit
    hook's own import (hooks.engine_check) call it."""
    written = newest_change(common.ROOT, WRITTEN_BY_IMPORT)[0]
    write_stamp(common.ROOT, min(max(started, written), time.time()))


def ensure_import() -> None:
    """Import the project first when its import is not current (check.freshness, #174), and say so in one line.

    Without it a fresh checkout resolves no resource, and a checkout that `git switch` moved to a commit with a new
    class_name script fails with `Identifier "…" not declared`. The test costs a walk over the project's files (0.03
    to 0.04 s over about 1,500 files); an import about 10 s even when nothing changed (both measured for #174 on the
    engineer's PC), so it runs only when needed. A linked worktree's
    override.cfg (#182) is written first, as require_godot does before every Godot start: the walk sees it, and the
    import runs with the worktree's own user://.
    """
    common.ensure_user_dir()
    started = time.monotonic()
    state = freshness()
    looked = time.monotonic() - started
    if not state.why:
        say(f"        import: current ({state.files} project files unchanged since the last import, {looked:.2f}s)")
        return
    if state.newest > time.time():
        warn(f"import: {state.why}; importing the project first")
    else:
        say(f"        import: {state.why}; importing the project first")
    run_import("run-import")
    say(f"        import: done in {time.monotonic() - started:.1f}s")


# A script warning of the project check: the full run prints dozens (39 on 2026-10-09), which a quiet success counts.
SCRIPT_WARNING = re.compile(r"^  warn  res://")


def changed_scripts() -> list[str]:
    """The .gd files this branch changes against origin/main or has uncommitted, sorted; none when git cannot tell
    (a shallow CI checkout)."""
    paths: set[str] = set()
    diff = common.git("-c", "core.quotePath=false", "diff", "--name-only", "origin/main...HEAD", timeout=30)
    if diff.rc == 0:
        paths.update(line.strip() for line in diff.lines)
    for line in git_status():
        path = line[3:].strip().strip('"')
        paths.add(path.split(" -> ")[-1])
    return sorted(path for path in paths if path.endswith(".gd"))


def script_warnings(changed: list[str]) -> re.Pattern[str]:
    """The script warnings a quiet check counts: every one but those in a changed file, which an agent just edited
    and the API checker reads (#590 review), so they always print."""
    if not changed:
        return SCRIPT_WARNING
    return re.compile(r"^  warn  res://(?!(?:" + "|".join(re.escape(path) for path in changed) + r"):)")


def main(files: list[str] | None = None, lfs_content: bool = False, verbose: bool = False) -> int:
    """Quiet unless `verbose` (#590): a summary on success (script warnings counted, not listed, but for the files
    this branch changes), a capped excerpt and the log's path on failure."""
    if lfs_content:
        return require_lfs_content()
    bulk = SCRIPT_WARNING if verbose else script_warnings(changed_scripts())
    return quiet("check", lambda: check_all(files), verbose, bulk=bulk)


def check_all(files: list[str] | None) -> int:
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

    user_dir = user_dir_policy()
    if user_dir:
        failed = True
        for line in user_dir:
            bad(line)
    else:
        ok("project.godot keeps the default user://")

    if not (common.IS_CI or common.IS_CLOUD):  # there lfs.ci_pointers() skips them (#515)
        hint = lfs.local_hint()
        if hint:
            warn(hint)
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

    if not project_check(files, lfs.ci_pointers()):
        failed = True

    say("check: FAILED" if failed else "check: passed")
    return 1 if failed else 0


def require_lfs_content() -> int:
    """`check --lfs-content`: fail on every LFS pointer file, for a build that must ship the real assets (release.yml
    before its export; #515). No Godot, no import."""
    say("check --lfs-content")
    problems = lfs.require_content()
    for line in problems:
        bad(line)
    if not problems:
        ok("every file .gitattributes routes through Git LFS has its content (no pointer file)")
    say("check --lfs-content: FAILED" if problems else "check --lfs-content: passed")
    return 1 if problems else 0


def crashed_after_clean_run(res: Result) -> str | None:
    """The summary line when Godot died of an access violation (ACCESS_VIOLATION) only after check_project.gd had
    finished cleanly: it printed its summary with errors=0 as its last CHECK line and no `CHECK error` line. None
    for any other run: another exit code, no summary (a crash mid-run) or errors reported."""
    if res.rc not in ACCESS_VIOLATION:
        return None
    checks = [line for line in res.lines if line.startswith("CHECK ")]
    if not checks or not checks[-1].startswith("CHECK summary"):
        return None
    errors = SUMMARY_ERRORS.search(checks[-1])
    if errors is None or errors.group(1) != "0" or any(line.startswith("CHECK error ") for line in checks):
        return None
    return checks[-1]


def take_exit_crashes() -> int:
    """How many access violations at exit after a clean run project_check passed in this process since the last
    call (#449); the count starts again from zero."""
    global _exit_crashes
    count, _exit_crashes = _exit_crashes, 0
    return count


def exit_text(rc: int) -> str:
    """`exit 3221225477, 0xC0000005` for a Windows status, `signal 11` for a POSIX signal."""
    return f"signal {-rc}" if rc < 0 else f"exit {rc}, 0x{rc:08X}"


def project_check(files: list[str] | None = None, pointers: list[str] | None = None) -> bool:
    """Run check_project.gd over the project (or `files`) and report its lines; True when it passed.

    `pointers` (check.main passes lfs.ci_pointers(): in CI the LFS pointer files, locally none): the lines they cause
    are dropped (lfs.drop_lines), and one line says how many (#515).

    Raises Failure on a timeout or a crash, except Godot's access violation at exit after a clean run (#442,
    crashed_after_clean_run): every file was checked and none failed, so it passes with a warning that names the
    crash, and its output is kept in tools/out/logs/check-exit-crash.log."""
    args = ["--headless", "-d", "--ignore-error-breaks", "-s", "res://tools/check/check_project.gd"]
    if files:
        args += ["--", *files]
    res = godot(args, timeout=CHECK_TIMEOUT, log="check")
    if res.timed_out:
        raise Failure(
            f"project check timed out after {CHECK_TIMEOUT}s: usually a runtime error in an autoload "
            "or a tool script (log: tools/out/logs/check.log)"
        )
    output, dropped = res.out, ""
    if pointers:
        kept, errors, warnings = lfs.drop_lines(res.lines, pointers, common.ROOT)
        # Godot exits 1 on any error: with only the dropped ones, the check passed.
        clean = res.rc == 1 and not any(line.startswith("CHECK error ") for line in kept)
        res = Result(0 if clean else res.rc, "\n".join(kept) + "\n", res.timed_out, res.seconds, res.restarted)
        dropped = lfs.summary(pointers, errors, warnings)
    summary = next((line for line in res.lines if line.startswith("CHECK summary")), None)
    exit_crash = crashed_after_clean_run(res)
    if summary is None or (res.rc not in NORMAL_EXIT and exit_crash is None):
        tail = "\n".join(res.lines[-15:])
        raise Failure(f"project check crashed (exit {res.rc}). Last lines:\n{tail}")
    for line in res.lines:
        if line.startswith("CHECK warning "):
            warn(line.removeprefix("CHECK warning "))
        elif line.startswith("CHECK error "):
            bad(line.removeprefix("CHECK error "))
    if exit_crash is not None:
        global _exit_crashes
        _exit_crashes += 1
        ensure_out()
        (common.LOGS / f"{EXIT_CRASH_LOG}.log").write_text(output, encoding="utf-8")
        warn(
            f"GODOT CRASHED AT EXIT: access violation ({exit_text(res.rc)}) after the project"
            f" check finished cleanly ({exit_crash.removeprefix('CHECK summary ')}); counted as passed, since every"
            f" file was checked (#442). Log: tools/out/logs/{EXIT_CRASH_LOG}.log"
        )
    if dropped:
        skip(dropped)
    if res.rc == 1:
        return False
    ok(summary.removeprefix("CHECK summary "))
    return True
