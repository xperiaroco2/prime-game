"""Git LFS pointer files: what `check` does when a checkout has no LFS content (#515).

CI checks out without LFS content (`lfs: false`, the LFS ADR), so each file `.gitattributes` routes through LFS is a
pointer file there: a few lines of text that start with the spec's version line. Godot imports it by its extension and
fails (`Not a PNG file`, `Not a WAV file`, a glTF parse error), and rewrites its `.import` file as it does; every
resource that uses it then fails to load. The LFS ADR's amendment of 2026-10-07 (option 2) settles it: in CI only
(common.IS_CI), the import never sees a pointer file (aside() moves it and its `.import` file behind tools/out's
`.gdignore` and puts both back), and the project check drops the lines that name one (drop_lines()). Locally, with
LFS content, ci_pointers() is empty and nothing changes. The credits check needs only the paths, so it still covers
pointer files. A build (release.yml, with LFS content) runs `check --lfs-content`, which fails on any pointer file.
"""

from __future__ import annotations

import os
import re
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from . import common, credits
from .common import Failure

# The first line of every pointer file (https://github.com/git-lfs/git-lfs/blob/main/docs/spec.md); the spec keeps
# pointer files under 1024 bytes, so a larger file is content even if it starts the same way.
HEADER = b"version https://git-lfs.github.com/spec/v1\n"
MAX_SIZE = 1024
# Where aside() keeps the pointer files during an import: a .gdignore in it makes Godot's scan skip it (as tools/out's
# own does, common.ensure_out), and tools/out is gitignored, so `git status` sees nothing once the files are back.
ASIDE = "tools/out/lfs-aside"
# A res:// path in a project check line, and one followed by `:<line>`: the file the line is about.
RES_PATH = re.compile(r"res://[^\s\"'()\[\],:;]+")
LOCATION = re.compile(r"(res://[^\s\"'()\[\],:;]+):\d+")
CHECK_LINE = ("CHECK error ", "CHECK warning ")
SUMMARY = re.compile(r"\berrors=\d+ warnings=\d+")


def is_pointer(path: Path) -> bool:
    """Whether the file is a Git LFS pointer file rather than its content."""
    try:
        if path.stat().st_size >= MAX_SIZE:
            return False
        with path.open("rb") as file:
            return file.read(len(HEADER)) == HEADER
    except OSError:
        return False


def pointers(root: Path | None = None) -> list[str]:
    """The repo-relative paths of the files .gitattributes routes through LFS that are pointer files here (addons/
    is outside LFS). None in a folder whose .gitattributes routes nothing through LFS, or that is not a git work tree
    (a runner test's temp project): git cannot list its files, and it has no LFS files."""
    root = root or common.ROOT
    try:
        if "filter=lfs" not in (root / ".gitattributes").read_text(encoding="utf-8"):
            return []
    except (OSError, UnicodeDecodeError):
        return []
    try:
        assets = credits.lfs_assets(root, credits.repo_files(root))
    except Failure:
        return []
    return [name for name in assets if is_pointer(root / name)]


def ci_pointers(root: Path | None = None) -> list[str]:
    """pointers() in CI, where the checkout has no LFS content; locally none, so nothing changes there."""
    return pointers(root) if common.IS_CI else []


@contextmanager
def aside(names: list[str], root: Path | None = None) -> Iterator[None]:
    """Keep the pointer files `names` (repo-relative) and their `.import` files out of Godot's sight for an import:
    moved under ASIDE, and back afterwards, even when the import failed. A file that cannot go back is a Failure
    that names it (the checkout would otherwise lose it)."""
    root = root or common.ROOT
    moved: list[tuple[Path, Path]] = []
    try:
        if names:
            (root / ASIDE).mkdir(parents=True, exist_ok=True)
            (root / ASIDE / ".gdignore").touch()  # Godot's scan skips the folder, whoever made tools/out
        for name in names:
            for rel in (name, name + ".import"):
                source = root / rel
                if not source.is_file():
                    continue
                target = root / ASIDE / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                os.replace(source, target)
                moved.append((source, target))
        yield
    finally:
        lost = []
        for source, target in reversed(moved):
            try:
                os.replace(target, source)
            except OSError as exc:
                lost.append(f"{source.relative_to(root).as_posix()} ({exc})")
        if lost:
            raise Failure(f"could not put the LFS pointer files back from {ASIDE}/: " + ", ".join(lost))


def res_paths(names: list[str], root: Path | None = None) -> set[str]:
    """The res:// paths by which the project check's lines name the pointer files `names`: each file's own, and the
    imported files its committed `.import` file names (`path=` and `dest_files`, under res://.godot/imported/), which
    the import never wrote in CI (`Unable to open file: res://.godot/imported/a.png-<hash>.ctex`)."""
    root = root or common.ROOT
    paths = set()
    for name in names:
        paths.add(f"res://{name}")
        try:
            text = (root / (name + ".import")).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        paths.update(path for path in RES_PATH.findall(text) if path.startswith("res://.godot/imported/"))
    return paths


def drop_lines(lines: list[str], names: list[str], root: Path | None = None) -> tuple[list[str], int, int]:
    """The project check's output without the lines a pointer file causes, and how many errors and warnings it
    dropped.

    A CHECK error or warning line is dropped when it names a pointer file or its imported file (res_paths:
    `Failed loading resource: res://a.png`, `referenced non-existent resource at: res://a.png`, an `invalid UID ...
    using text path instead: res://a.png`, `Unable to open file: res://.godot/imported/a.png-<hash>.ctex`) or a file
    such a line was about (a script that preloads one fails to compile: `res://p.gd:3: Parse Error: Could not preload
    resource file "res://a.png"`, then `Failed to load script "res://p.gd"`). So in CI, a problem in a file that uses
    an LFS asset is left to the local check, which has the content. The summary line gets the counts of the lines
    kept; with no pointer files the output is unchanged.
    """
    if not names:
        return lines, 0, 0
    checks = [line for line in lines if line.startswith(CHECK_LINE)]
    skipped = res_paths(names, root)
    grown = True
    while grown:  # a file a dropped line was about makes the lines that name it dropped too
        grown = False
        for line in checks:
            if _names(line, skipped):
                for where in LOCATION.findall(line):
                    if where not in skipped:
                        skipped.add(where)
                        grown = True
    kept: list[str] = []
    errors = warnings = dropped_errors = dropped_warnings = 0
    for line in lines:
        if line.startswith(CHECK_LINE):
            error = line.startswith("CHECK error ")
            if _names(line, skipped):
                dropped_errors += error
                dropped_warnings += not error
                continue
            errors += error
            warnings += not error
        kept.append(line)
    summary = f"errors={errors} warnings={warnings}"
    kept = [SUMMARY.sub(summary, line) if line.startswith("CHECK summary") else line for line in kept]
    return kept, dropped_errors, dropped_warnings


def _names(line: str, paths: set[str]) -> bool:
    return any(path.rstrip(".") in paths for path in RES_PATH.findall(line))


def summary(names: list[str], errors: int, warnings: int) -> str:
    """check's one line in CI about the pointer files it skipped."""
    files = f"{len(names)} LFS pointer file{'' if len(names) == 1 else 's'}"
    return (
        f"{files} skipped (CI checks out without LFS content): kept out of the import; {errors} error and {warnings}"
        " warning lines of the project check about them dropped; credits still checked"
    )


def require_content(root: Path | None = None) -> list[str]:
    """`check --lfs-content`: a problem line for each pointer file, for a build that must ship the real assets."""
    return [
        f"{name}: a Git LFS pointer file, not its content: this checkout has no LFS content (actions/checkout with"
        " `lfs: true`, or `git lfs pull`)"
        for name in pointers(root)
    ]
