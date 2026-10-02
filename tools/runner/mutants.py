"""`mutants <spec.json>`: plant one fault at a time in a scratch worktree of HEAD and run the named tests there.

The tool of `issue-task`'s test review (#184; item 4 (b) of the AI productivity ADR,
docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md): a change's tests must fail when its code is
wrong. A planted fault never touches the task's own tree, so a run killed half-way (a Bash call's 600 s limit, a
stopped workflow, a crash: no `finally` runs then) cannot leave one behind for the publisher to commit:

- The task's worktree must be clean, because the mutants run its HEAD commit.
- One run at a time per checkout: a lock file in `tools/out/mutants/`, held through the OS (msvcrt or flock), so a
  killed run releases it.
- The scratch tree is `tools/out/mutants/tree-<checkout folder>` (gitignored, and Godot skips `tools/out/`), made
  with `git worktree add --detach <tree> <HEAD sha>`. A start first removes any worktree or `tree-*` folder left
  there by a killed run.
- The task's `.godot` import cache and its files' modification times are copied in before the one import of the
  scratch tree, so Godot rechecks nothing it already knows; each test run after it skips the import (a mutant
  changes a script's body, not the class cache).
- A baseline runs every named test once without a mutant: a test that already fails would make every mutant look
  killed.
- For each mutant: plant it, run its tests in the scratch tree (`test <paths>` there), record killed (a named test
  failed), survived (they passed: a finding, not a failure of the run) or error (the tests could not judge it: a
  parse error, a timeout, a red baseline), restore the file.
- The scratch worktree is removed at the end, also after an exception, and the task's `git status` is confirmed
  unchanged. Exit 0: the run completed; 1: an invalid spec, or a run that could not start or finish; 2: the scratch
  worktree could not be removed, or the task's tree changed.

The table is printed and written to `tools/out/mutants/<spec name>.md` after every mutant, so a background run
shows its progress. Each test run's output is kept next to it as `<spec name>-<step>.log`.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from .common import IS_WINDOWS, ROOT, Failure, bad, ok, run, say, warn

# Where mutants may go: production code only (never tests/, tools/, docs/, content/ or levels/).
PRODUCTION = ("core", "server", "net", "client", "voice")
TESTS = "tests"
MUTANTS_DIR = "tools/out/mutants"
TREE_PREFIX = "tree-"
KEYS = ("file", "line", "original", "replacement", "tests")
DONE, INVALID, LEFTOVER = 0, 1, 2
TEST_SECONDS = 300
IMPORT_SECONDS = 600
GIT_SECONDS = 300
# Results of a mutant.
KILLED, SURVIVED, ERROR, NOT_RUN = "killed", "survived", "error", "not run"
# Godot's lines for a script that does not compile (the mutant's own fault, not a test's verdict).
PARSE_RE = re.compile(r"Parse Error|Failed to load script|Compile Error", re.IGNORECASE)
# What the global class cache holds: the mutants import once, so a mutant there would run against the old cache.
CLASS_RE = re.compile(r"\b(class_name|extends)\b")

HELP = """\
spec: a JSON file (UTF-8) with one object:
  {"mutants": [
    {"file": "core/combat/cooldown.gd", "line": 37,
     "original": ">= Ticks.from_seconds(seconds)",
     "replacement": "> Ticks.from_seconds(seconds)",
     "tests": ["tests/unit/combat/cooldown_test.gd"]}
  ]}
  file         a tracked file under core/ server/ net/ client/ voice/ (repo-relative or res://)
  line         the 1-based line on which original starts
  original     the exact text; it must start on that line exactly once (\\n continues it on the next lines);
               never on a class_name or extends line (the scratch tree is imported once, before the mutants)
  replacement  the text put in its place ("" deletes it); never equal to original
  tests        test files or folders under tests/ (repo-relative or res://) that should catch the fault

The worktree must be clean: the mutants run its HEAD commit. The run makes a scratch detached worktree of HEAD
under tools/out/mutants/ (removing one a killed run left first), copies this checkout's .godot import cache and
file times into it and imports it once, runs every named test once without a mutant (the baseline), then for each
mutant plants it, runs its tests there and restores the file. The task's own tree is never written; its git
status is checked at the end.
  killed    a named test failed (the failing tests are listed)
  survived  the tests passed: a finding (the run still exits 0)
  error     the tests could not judge it: the mutant does not compile, a timeout, a red baseline (reason and log)
The table is printed and written to tools/out/mutants/<spec name>.md after every mutant; each test run's output
goes to tools/out/mutants/<spec name>-<step>.log.

exit codes:
  0  the run completed, whatever the results
  1  an invalid spec, or the run could not start or finish (a dirty worktree, another mutants run in this
     checkout, a failed import); nothing is left behind
  2  the scratch worktree could not be removed, or the task's git status changed: run no more mutants and tell
     the human (git worktree list shows the leftover; a later run removes it first)

A foreground shell call dies at 600 s: run one mutant per call (about 20 s with small suites), or several in
the background and read the report file."""

# Runs in the scratch tree with its own runner (HEAD's code), so its ROOT, logs and reports are the scratch tree's.
STEP = """\
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from runner import check, common, gdunit
try:
    if sys.argv[2] == "import":
        for line in check.run_import("mutants-import"):
            common.warn("import: " + line)
        sys.exit(0)
    sys.exit(gdunit.main(paths=sys.argv[3:], run_import=False))
except common.Failure as exc:
    common.bad(str(exc))
    sys.exit(1)
"""


class SpecError(Exception):
    def __init__(self, problems: list[str]) -> None:
        super().__init__(f"{len(problems)} problem(s) in the spec")
        self.problems = problems


@dataclass
class Mutant:
    index: int
    file: str
    line: int
    original: str
    replacement: str
    tests: list[str]
    result: str = NOT_RUN
    failing: list[str] = field(default_factory=list)
    reason: str = ""
    seconds: float = 0.0


@dataclass
class Outcome:
    """One test run in the scratch tree: the child's exit code and output, and what its results.xml says."""

    rc: int
    out: str = ""  # the scratch tree runner's lines
    timed_out: bool = False
    tests: int = -1  # test cases in results.xml; -1: none was written
    failing: list[str] = field(default_factory=list)
    godot: str = ""  # Godot's own output (the scratch tree's tools/out/logs/test.log), which goes with the tree


# --- the spec -----------------------------------------------------------------------------------------------------


def _repo_path(value: object) -> str | None:
    """A repo-relative path with forward slashes (res:// and .\\ allowed), or None when it is not one."""
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip().replace("\\", "/").removeprefix("res://")
    while text.startswith("./"):
        text = text[2:]
    if text.startswith("/") or re.match(r"^[A-Za-z]:", text):
        return None
    parts = text.rstrip("/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        return None
    return "/".join(parts)


def _tracked(root: Path, path: str) -> bool:
    """path is a tracked file of HEAD's checkout, or a folder that holds one."""
    res = run(["git", "ls-files", "--", path], timeout=GIT_SECONDS, cwd=root)
    return res.rc == 0 and bool(res.out.strip())


def line_count(text: str) -> int:
    return text.count("\n") + (0 if text.endswith("\n") or not text else 1)


def locate(text: str, line: int, original: str) -> list[int]:
    """Offsets where original starts on the 1-based line of text."""
    if line < 1 or line > line_count(text):
        return []
    starts = [0] + [i + 1 for i, char in enumerate(text) if char == "\n"]
    begin = starts[line - 1]
    end = starts[line] if line < len(starts) else len(text)
    found = []
    at = text.find(original, begin)
    while at != -1 and at < end:
        found.append(at)
        at = text.find(original, at + 1)
    return found


def load_spec(path: Path, root: Path) -> list[Mutant]:
    """The mutants of a spec file, checked against the (clean) checkout at root; SpecError lists every problem."""
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except OSError as exc:
        raise SpecError([f"cannot read {path}: {exc.strerror or exc}"]) from exc
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise SpecError([f"{path} is not JSON: {exc}"]) from exc
    if not isinstance(data, dict) or set(data) != {"mutants"}:
        raise SpecError(['the spec is one object with one key, "mutants" (a list): see mutants --help'])
    entries = data["mutants"]
    if not isinstance(entries, list) or not entries:
        raise SpecError(['"mutants" is a list of at least one mutant'])
    problems: list[str] = []
    mutants: list[Mutant] = []
    for index, entry in enumerate(entries, start=1):
        found = _check_entry(index, entry, root)
        if isinstance(found, Mutant):
            mutants.append(found)
        else:
            problems += found
    if problems:
        raise SpecError(problems)
    return mutants


def _check_entry(index: int, entry: object, root: Path) -> Mutant | list[str]:
    where = f"mutant {index}"
    if not isinstance(entry, dict):
        return [f"{where}: an object with {', '.join(KEYS)}"]
    problems = [f"{where}: unknown key {key!r} (the keys: {', '.join(KEYS)})" for key in entry if key not in KEYS]
    problems += [f"{where}: no {key!r}" for key in KEYS if key not in entry]
    if problems:
        return problems
    file = _repo_path(entry["file"])
    line = entry["line"]
    original, replacement, tests = entry["original"], entry["replacement"], entry["tests"]
    if file is None:
        problems.append(f"{where}: file {entry['file']!r} is not a repo-relative path")
    elif file.split("/")[0] not in PRODUCTION:
        problems.append(f"{where}: {file} is outside {', '.join(d + '/' for d in PRODUCTION)} (production code only)")
    elif not (root / file).is_file() or not _tracked(root, file):
        problems.append(f"{where}: {file} is not a tracked file of HEAD")
    if not isinstance(line, int) or isinstance(line, bool) or line < 1:
        problems.append(f"{where}: line must be a whole number from 1")
    if not isinstance(original, str) or not original:
        problems.append(f"{where}: original must be non-empty text")
    if not isinstance(replacement, str):
        problems.append(f"{where}: replacement must be text (\"\" deletes the original)")
    elif replacement == original:
        problems.append(f"{where}: replacement equals original, so nothing would change")
    paths: list[str] = []
    if not isinstance(tests, list) or not tests:
        problems.append(f"{where}: tests must be a list of at least one test file or folder")
    else:
        for item in tests:
            test = _repo_path(item)
            if test is None or test.split("/")[0] != TESTS:
                problems.append(f"{where}: test {item!r} is not a path under {TESTS}/")
            elif not _tracked(root, test):
                problems.append(f"{where}: test {test} is not tracked in HEAD (a probe in tests/scratch/ is not)")
            elif test not in paths:
                paths.append(test)
    if problems:
        return problems
    assert file is not None and isinstance(line, int) and isinstance(original, str) and isinstance(replacement, str)
    try:
        text = (root / file).read_bytes().decode("utf-8")
    except UnicodeDecodeError:
        return [f"{where}: {file} is not UTF-8 text"]
    if line > line_count(text):
        return [f"{where}: {file} has {line_count(text)} lines, not {line}"]
    hits = locate(text, line, original)
    if len(hits) != 1:
        actual = text.split("\n")[line - 1]
        count = "is not" if not hits else f"starts {len(hits)} times"
        return [
            f"{where}: original {original!r} {count} on line {line} of {file}, which reads {actual!r}"
            + (" (make it longer, so it starts there once)" if hits else "")
        ]
    touched = "\n".join(text.split("\n")[line - 1 : line + original.count("\n")])
    if CLASS_RE.search(touched) or CLASS_RE.search(replacement):
        return [
            f"{where}: it touches a class_name or extends line, which the global class cache holds; the scratch tree "
            "is imported once, so the tests would run against the old cache (mutate a function body instead)"
        ]
    return Mutant(index, file, line, original, replacement, paths)


# --- git, the lock and the scratch tree ---------------------------------------------------------------------------


def _git(root: Path, *args: str) -> str:
    res = run(["git", *args], timeout=GIT_SECONDS, cwd=root)
    if res.rc != 0 or res.timed_out:
        raise Failure(f"git {' '.join(args)} failed in {root}: {res.out.strip()[-400:]}")
    return res.out


def status(root: Path) -> set[str]:
    """The checkout's `git status` lines, untracked files included (ignored ones such as tools/out/ never show)."""
    return {line for line in _git(root, "status", "--porcelain", "--untracked-files=all").splitlines() if line.strip()}


class Lock:
    """One mutants run per checkout. The OS releases the lock when its process ends, even when it is killed."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.fd: int | None = None

    def acquire(self) -> None:
        """Take the lock, or raise Failure when another process holds it."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_RDWR | os.O_CREAT)
        try:
            if IS_WINDOWS:
                import msvcrt

                msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            os.close(fd)
            raise Failure(
                f"another mutants run is active in this checkout (it holds {self.path.as_posix()}); wait for it to "
                "end, then run this one"
            ) from exc
        self.fd = fd

    def release(self) -> None:
        if self.fd is None:
            return
        if IS_WINDOWS:
            import msvcrt

            os.lseek(self.fd, 0, os.SEEK_SET)
            try:
                msvcrt.locking(self.fd, msvcrt.LK_UNLCK, 1)
            except OSError:
                pass  # closing the file releases it too
        os.close(self.fd)
        self.fd = None


def _norm(path: Path | str) -> str:
    return os.path.normcase(os.path.realpath(str(path)))


def _inside(path: Path | str, folder: Path) -> bool:
    child, parent = _norm(path), _norm(folder)
    return child.startswith(parent.rstrip("\\/") + os.sep)


def registered(root: Path, folder: Path) -> list[str]:
    """The worktrees git knows of inside folder (a removed folder's entry included until it is removed)."""
    found = []
    for line in _git(root, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree ") and _inside(line.removeprefix("worktree "), folder):
            found.append(line.removeprefix("worktree "))
    return found


def _rmtree(path: Path) -> None:
    """Git makes its object files read-only; Windows refuses to delete those without a chmod."""

    def retry(func, target, _exc):  # type: ignore[no-untyped-def]
        os.chmod(target, stat.S_IWRITE)
        func(target)

    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=retry)
    else:
        shutil.rmtree(path, onerror=retry)


def remove_trees(root: Path) -> list[str]:
    """Remove every scratch worktree in tools/out/mutants/ (registered, or a `tree-*` folder); return what is left."""
    folder = root / MUTANTS_DIR
    for path in registered(root, folder):
        run(["git", "worktree", "remove", "--force", path], timeout=GIT_SECONDS, cwd=root)
    if folder.is_dir():
        for path in sorted(folder.glob(TREE_PREFIX + "*")):
            if path.is_dir():
                try:
                    _rmtree(path)
                except OSError as exc:
                    warn(f"cannot delete {path.as_posix()}: {exc.strerror or exc} (a program may hold a file in it)")
    # A folder deleted by hand leaves git's entry: `worktree remove` drops it once the folder is gone.
    for path in registered(root, folder):
        if not Path(path).exists():
            run(["git", "worktree", "remove", "--force", path], timeout=GIT_SECONDS, cwd=root)
    left = {_norm(p): p for p in registered(root, folder)}
    if folder.is_dir():  # folders only: the report of a spec named tree-x.json is the file tree-x.md
        left.update({_norm(p): p.as_posix() for p in folder.glob(TREE_PREFIX + "*") if p.is_dir()})
    return sorted(left.values())


def seed_cache(root: Path, tree: Path) -> str:
    """Copy the checkout's .godot import cache into the scratch tree, and the modification times of its tracked
    files: Godot rechecks a file whose time differs from its cache entry, and a fresh checkout gives every file a new
    time. Both trees hold HEAD's content, so the cache entries stay as true as they are in the checkout (measured:
    the import took 10 to 11 s afresh, 7.2 to 9.6 s with the cache alone, 7.4 s with the times too, 7.2 s warm)."""
    source = root / ".godot"
    if not source.is_dir():
        return "no .godot to copy (a fresh import)"
    try:
        shutil.copytree(source, tree / ".godot")
    except (OSError, shutil.Error) as exc:
        shutil.rmtree(tree / ".godot", ignore_errors=True)
        warn(f"could not copy .godot, so the scratch tree imports afresh: {exc}")
        return "no .godot copied (a fresh import)"
    for name in _git(root, "ls-files", "-z").split("\0"):
        if name:
            try:
                times = (root / name).stat()
                os.utime(tree / name, ns=(times.st_atime_ns, times.st_mtime_ns))
            except OSError:
                pass  # a file Godot then rechecks: slower, never wrong
    return ".godot and file times copied"


# --- the steps that start Godot (stubbed in the runner tests) ----------------------------------------------------


def _step(tree: Path, args: list[str], seconds: float) -> tuple[int, str, bool]:
    res = run([sys.executable, "-c", STEP, str(tree / "tools"), *args], timeout=seconds, cwd=tree)
    return res.rc, res.out, res.timed_out


def import_step(tree: Path) -> str:
    """The scratch tree's one import (its class cache and .uid files). Returns its output; Failure if it broke."""
    rc, out, timed_out = _step(tree, ["import"], IMPORT_SECONDS)
    if timed_out or rc != 0:
        why = "timed out" if timed_out else f"exit {rc}"
        raise Failure(f"the import of the scratch tree failed ({why}):\n{out[-600:]}")
    return out


def test_step(tree: Path, paths: list[str], seconds: float) -> Outcome:
    """`test <paths>` in the scratch tree without its import, judged by the child's exit code and results.xml."""
    log = tree / "tools" / "out" / "logs" / "test.log"
    gdunit = tree / "tools" / "out" / "gdunit"
    # The previous step's log and results must never be read as this one's (a child that stops before it clears them).
    log.unlink(missing_ok=True)
    shutil.rmtree(gdunit, ignore_errors=True)
    rc, out, timed_out = _step(tree, ["test", *paths], seconds)
    godot = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
    reports = sorted(gdunit.glob("report_*/results.xml"))
    if not reports or timed_out:
        return Outcome(rc, out, timed_out, godot=godot)
    tests, failing = read_results(reports[-1])
    return Outcome(rc, out, timed_out, tests, failing, godot)


def read_results(path: Path) -> tuple[int, list[str]]:
    """(test cases, the names of those that failed or erred as `suite::test`) of a GdUnit4 results.xml."""
    try:
        cases = list(ET.parse(path).getroot().iter("testcase"))
    except ET.ParseError:
        return -1, []
    failing = []
    for case in cases:
        if case.find("failure") is not None or case.find("error") is not None:
            name = f"{case.get('classname', '?')}::{case.get('name', '?')}"
            if name not in failing:
                failing.append(name)
    return len(cases), failing


def judge(outcome: Outcome, file: str, seconds: float) -> tuple[str, list[str], str]:
    """(result, failing tests, reason) of one mutant's test run."""
    if outcome.timed_out:
        return ERROR, [], f"timed out after {seconds:.0f} s (an endless loop is caught only by the timeout)"
    lines = (outcome.out + "\n" + outcome.godot).splitlines()
    # Godot names the script res://<file>; a bare suffix would also match res://score/a.gd for core/a.gd.
    script = f"res://{file}"
    parse = [line.strip() for line in lines if PARSE_RE.search(line) and script in line]
    if parse:
        return ERROR, [], f"the mutant does not compile: {parse[0][:200]}"
    if outcome.failing:
        return KILLED, outcome.failing, ""
    if outcome.rc == 0 and outcome.tests > 0:
        return SURVIVED, [], ""
    return ERROR, [], _reason(outcome)


def _reason(outcome: Outcome) -> str:
    lines = [line.strip() for line in outcome.out.splitlines()]
    fails = [line.removeprefix("FAIL").strip() for line in lines if line.startswith("FAIL")]
    if fails:
        return "; ".join(fails[:3])[:300]
    if outcome.tests == 0:
        return "no tests ran"
    tail = [line for line in lines if line][-2:]
    return f"exit {outcome.rc} without a failed test" + (f": {' | '.join(tail)[:300]}" if tail else "")


# --- the report ---------------------------------------------------------------------------------------------------


def _code(text: str, limit: int = 60) -> str:
    if not text:
        return "(nothing)"
    shown = text.replace("\n", "\\n")
    if len(shown) > limit:
        shown = shown[: limit - 3] + "..."
    shown = shown.replace("|", "\\|")  # a table cell ends at a bare pipe, even inside code
    return f"`` {shown} ``" if "`" in shown else f"`{shown}`"


def table(mutants: list[Mutant]) -> list[str]:
    lines = ["| # | mutant | result | failing tests, or why | s |", "|---|---|---|---|---|"]
    for m in mutants:
        if m.failing:
            why = ", ".join(m.failing[:3]) + (f" and {len(m.failing) - 3} more" if len(m.failing) > 3 else "")
        else:
            why = m.reason.replace("|", "\\|")
        fault = f"`{m.file}:{m.line}` {_code(m.original)} -> {_code(m.replacement)}"
        lines.append(f"| {m.index} | {fault} | {m.result} | {why} | {m.seconds:.1f} |")
    return lines


def summary(mutants: list[Mutant]) -> str:
    counts = [(name, sum(1 for m in mutants if m.result == name)) for name in (KILLED, SURVIVED, ERROR, NOT_RUN)]
    return ", ".join(f"{count} {name}" for name, count in counts if count or name != NOT_RUN)


def write_report(path: Path, head: list[str], mutants: list[Mutant], tail: list[str]) -> None:
    path.write_text("\n".join([*head, "", *table(mutants), "", *tail]) + "\n", encoding="utf-8", newline="\n")


# --- the command --------------------------------------------------------------------------------------------------


def main(spec: str, seconds: float = TEST_SECONDS, root: Path = ROOT) -> int:
    say("mutants")
    started = time.monotonic()
    if seconds <= 0:
        bad("--seconds must be above 0")
        return INVALID
    spec_path = Path(spec)
    before = status(root)
    if before:
        lines = sorted(before)
        bad(
            "the worktree has uncommitted changes; the mutants run HEAD, so commit them first (a spec goes in your "
            "scratchpad or tests/scratch/):",
            "\n".join(lines[:10]) + (f"\n... and {len(lines) - 10} more" if len(lines) > 10 else ""),
        )
        return INVALID
    try:
        mutants = load_spec(spec_path, root)
    except SpecError as exc:
        for problem in exc.problems:
            bad(problem)
        bad("invalid spec: nothing ran (format: tools\\run.cmd mutants --help)")
        return INVALID
    lock = Lock(root / MUTANTS_DIR / "lock")
    try:
        lock.acquire()
    except Failure as exc:
        bad(str(exc))
        return INVALID
    try:
        return _run(root, mutants, spec_path, seconds, before, started)
    finally:
        lock.release()


def _run(root: Path, mutants: list[Mutant], spec_path: Path, seconds: float, before: set[str], started: float) -> int:
    folder = root / MUTANTS_DIR
    gdignore = root / "tools" / "out" / ".gdignore"
    if not gdignore.exists():  # Godot must never import the scratch tree as part of this checkout
        gdignore.write_text("", encoding="ascii")
    left = remove_trees(root)
    if left:
        bad("a scratch worktree left by an earlier run cannot be removed:", "\n".join(left))
        bad("close what holds it (a Godot or an editor), then run mutants again; or ask the human")
        return LEFTOVER
    sha = _git(root, "rev-parse", "HEAD").strip()
    tree = folder / f"{TREE_PREFIX}{root.name}"
    report = folder / f"{spec_path.stem}.md"
    head = [
        f"mutants of {sha[:10]} ({spec_path.name}), in the scratch worktree {tree.relative_to(root).as_posix()}",
    ]
    tail: list[str] = []
    say(f"        report: {report.relative_to(root).as_posix()} (rewritten after every mutant)")
    error: BaseException | None = None
    try:
        t0 = time.monotonic()
        _git(root, "worktree", "add", "--detach", str(tree), sha)
        t1 = time.monotonic()
        cache = seed_cache(root, tree)
        t2 = time.monotonic()
        import_step(tree)
        t3 = time.monotonic()
        head.append(
            f"setup {t3 - t0:.1f} s: worktree {t1 - t0:.1f} s, {cache} {t2 - t1:.1f} s, one import {t3 - t2:.1f} s"
        )
        ok(head[-1])
        write_report(report, head, mutants, tail)
        _baseline(root, tree, mutants, seconds, spec_path.stem, head)
        for mutant in mutants:
            if mutant.result == NOT_RUN:
                _one(root, tree, mutant, seconds, spec_path.stem)
            write_report(report, head, mutants, tail)
    except BaseException as exc:  # noqa: BLE001 - a crash or Ctrl+C still gets the status check, report and exit code
        error = exc
    finally:
        # Only a killed process skips this, and the next start removes what it left.
        t0 = time.monotonic()
        try:
            left = remove_trees(root)
        except Failure as exc:
            left = [f"{tree.as_posix()} ({exc})"]
        removal = time.monotonic() - t0
        if left:
            bad("the scratch worktree could not be removed (exit 2):", "\n".join(left))
            bad("run no more mutants; the human closes what holds it, or a later mutants run removes it first")
    after = status(root)
    for line in table(mutants):
        say(line)
    if left:
        tail.append(f"EXIT 2: the scratch worktree could not be removed: {', '.join(left)}")
    else:
        ok(f"removed the scratch worktree in {removal:.1f} s")
    if after != before:
        changed = sorted(after ^ before)
        bad("the task's git status changed during the run (exit 2):", "\n".join(changed[:10]))
        tail.append(f"EXIT 2: the task's git status changed: {', '.join(changed[:10])}")
    else:
        ok("the task's tree is unchanged (git status)")
    if error is not None:
        why = _stopped(error)
        bad(why)
        tail.append(f"stopped: {why.splitlines()[0] if why else type(error).__name__}")
    tail.append(f"mutants: {summary(mutants)} in {time.monotonic() - started:.1f} s")
    write_report(report, head, mutants, tail)
    say(tail[-1])
    if left or after != before:
        return LEFTOVER
    if error is not None and not isinstance(error, Exception):
        raise error  # Ctrl+C or a SystemExit: nothing is left behind, so its own exit code stands
    return INVALID if error is not None else DONE


def _stopped(error: BaseException) -> str:
    """Why the run stopped: a Failure's own words; any other exception's type too (a crash, Ctrl+C)."""
    if isinstance(error, Failure):
        return str(error)
    text = str(error)
    return f"{type(error).__name__}: {text}" if text else type(error).__name__


def _baseline(root: Path, tree: Path, mutants: list[Mutant], seconds: float, stem: str, head: list[str]) -> None:
    """Every named test once without a mutant: a red one would make every mutant look killed."""
    paths = list(dict.fromkeys(path for m in mutants for path in m.tests))
    t0 = time.monotonic()
    outcome = test_step(tree, paths, seconds)
    log = _log(root, stem, "baseline", outcome)
    took = time.monotonic() - t0
    if outcome.rc == 0 and not outcome.failing and outcome.tests > 0 and not outcome.timed_out:
        head.append(f"baseline {took:.1f} s: {outcome.tests} tests passed without a mutant")
        ok(head[-1])
        return
    if outcome.timed_out:
        why = f"timed out after {seconds:.0f} s"
    elif outcome.failing:
        why = f"failing without a mutant: {', '.join(outcome.failing[:3])}"
    else:
        why = _reason(outcome)
    why = _with_log(why, log)
    bad(f"the baseline is red, so no mutant ran: {why}")
    head.append(f"baseline RED {took:.1f} s: {why}")
    for mutant in mutants:
        mutant.result, mutant.reason = ERROR, f"red baseline: {why}"


def _one(root: Path, tree: Path, mutant: Mutant, seconds: float, stem: str) -> None:
    """Plant one mutant in the scratch tree, run its tests there, record the result, restore the file."""
    target = tree / mutant.file
    raw = target.read_bytes()
    text = raw.decode("utf-8")
    hits = locate(text, mutant.line, mutant.original)
    if len(hits) != 1:  # the scratch tree is HEAD, like the clean checkout the spec was checked against
        mutant.result, mutant.reason = ERROR, f"the original is not on line {mutant.line} of the scratch tree's copy"
        return
    at = hits[0]
    t0 = time.monotonic()
    try:
        target.write_bytes((text[:at] + mutant.replacement + text[at + len(mutant.original) :]).encode("utf-8"))
        outcome = test_step(tree, mutant.tests, seconds)
    finally:
        target.write_bytes(raw)
    mutant.seconds = time.monotonic() - t0
    log = _log(root, stem, str(mutant.index), outcome)
    mutant.result, mutant.failing, mutant.reason = judge(outcome, mutant.file, seconds)
    if mutant.result == ERROR:
        mutant.reason = _with_log(mutant.reason, log)
    shown = ", ".join(mutant.failing[:3]) or mutant.reason
    where = f"{mutant.index} {mutant.file}:{mutant.line} ({mutant.seconds:.1f} s)"
    say(f"  {mutant.result:<8}  {where}" + (f": {shown}" if shown else ""))


def _log(root: Path, stem: str, step: str, outcome: Outcome) -> str:
    """Keep a test run's output and Godot's log beside the report (the scratch tree goes); return its path."""
    path = f"{MUTANTS_DIR}/{stem}-{step}.log"
    text = outcome.out + "\n--- Godot's log (tools/out/logs/test.log of the scratch tree) ---\n" + outcome.godot
    (root / path).write_text(text, encoding="utf-8", newline="\n")
    return path


def _with_log(reason: str, log: str) -> str:
    """The scratch tree's runner names its own log, which goes with the tree: point at the kept copy."""
    reason = reason.replace("tools/out/logs/test.log", log)
    return reason if log in reason else f"{reason} (log: {log})"
