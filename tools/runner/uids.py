"""Static UID lint for Godot text files (no engine needed).

Godot resolves an ext_resource by its uid first and silently ignores `path=` when the uid belongs to
another file, so a copied uid quietly points a scene at the wrong resource. This lint catches that and
the other UID mistakes an agent can make while hand-writing .tscn/.tres files.

The gitignored probe folder tests/scratch/ (common.SCRATCH) is left out as `test` and `lint` leave it out (#264): an
orphan or malformed sidecar, a script without one, or a stale ext_resource uid there is never committed, so it fails
nothing. One thing still counts: Godot imports the folder, and when two files claim one uid the one it scans last owns
it, so every reference by that uid can load the probe's copy. A uid a scratch file shares with a project file therefore
stays a duplicate error. A scratch file owns no uid for the project: a real scene that names one is `unknown`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from .common import SCRATCH

HEADER_RE = re.compile(r'^\[gd_(?:scene|resource)\b[^\]]*\buid="(uid://[a-z0-9]+)"', re.MULTILINE)
EXT_RE = re.compile(r"^\[ext_resource\b([^\]]*)\]", re.MULTILINE)
ATTR_RE = re.compile(r'\b(uid|path)="([^"]*)"')
IMPORT_UID_RE = re.compile(r'^uid="(uid://[a-z0-9]+)"', re.MULTILINE)
SIDECAR_RE = re.compile(r"^uid://[a-z0-9]+$")


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    uids: dict[str, str] = field(default_factory=dict)


def _res(root: Path, path: Path) -> str:
    return "res://" + path.relative_to(root).as_posix()


def project_files(root: Path) -> list[Path]:
    """Every file Godot sees: skips hidden directories (.git, .godot, and .claude with its task worktrees, which are
    whole copies of the project) and any directory holding a .gdignore, as the engine check does. Unlike that check,
    it still covers addons/: a duplicate uid there breaks loading just the same."""
    found: list[Path] = []

    def walk(folder: Path) -> None:
        if (folder / ".gdignore").exists() and folder != root:
            return
        for entry in sorted(folder.iterdir()):
            if entry.is_dir():
                if not entry.name.startswith("."):
                    walk(entry)
            else:
                found.append(entry)

    walk(root)
    return found


def in_scratch(root: Path, path: Path) -> bool:
    """True for a file under the probe folder tests/scratch/ (common.SCRATCH)."""
    return path.relative_to(root).as_posix().startswith(SCRATCH + "/")


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def claims(root: Path, path: Path) -> tuple[list[tuple[str, str]], list[str]]:
    """The uids one file claims, as (uid, res:// path of the owner) the way Godot's import registers them, and the
    errors of the file itself. A sidecar or .import file claims for the file it belongs to; an orphan or malformed
    sidecar claims nothing. One parser for project and scratch files, so a new kind of claim reaches both."""
    suffix = path.suffix
    if suffix in (".tscn", ".tres"):
        match = HEADER_RE.search(_read(path))
        return ([(match.group(1), _res(root, path))] if match else []), []
    if suffix == ".import":
        match = IMPORT_UID_RE.search(_read(path))
        return ([(match.group(1), _res(root, path.with_suffix("")))] if match else []), []
    if suffix == ".uid":
        target = path.with_suffix("")
        value = _read(path).strip()
        if not SIDECAR_RE.match(value):
            return [], [f"{_res(root, path)}: malformed uid sidecar '{value}'"]
        if not target.exists():
            return [], [f"{_res(root, path)}: sidecar without its file {_res(root, target)}"]
        return [(value, _res(root, target))], []
    if suffix in (".gd", ".gdshader"):
        sidecar = path.with_name(path.name + ".uid")
        if not sidecar.exists():
            return [], [f"{_res(root, path)}: missing {sidecar.name} (run `check` once, then commit the new .uid file)"]
    return [], []


def lint(root: Path) -> Report:
    report = Report()
    files = project_files(root)
    owners: dict[str, list[str]] = {}
    in_probes: dict[str, list[str]] = {}

    texts: dict[Path, str] = {}
    for path in files:
        claimed, errors = claims(root, path)
        if in_scratch(root, path):
            # A probe's own errors fail nothing; its claims still count against project uids (module docstring).
            for uid, owner in claimed:
                in_probes.setdefault(uid, []).append(owner)
            continue
        report.errors.extend(errors)
        for uid, owner in claimed:
            owners.setdefault(uid, []).append(owner)
        if path.suffix in (".tscn", ".tres"):
            texts[path] = _read(path)

    for uid, paths in sorted(owners.items()):
        claimed = paths + in_probes.get(uid, [])
        if len(claimed) > 1:
            report.errors.append(f"duplicate {uid}: {', '.join(sorted(claimed))} (never copy a uid or a .uid file)")
        report.uids[uid] = paths[0]

    for path, text in texts.items():
        line_starts = [m.start() for m in re.finditer(r"^", text, re.MULTILINE)]
        for match in EXT_RE.finditer(text):
            attrs = dict(ATTR_RE.findall(match.group(1)))
            uid, target = attrs.get("uid"), attrs.get("path")
            if not uid or not target:
                continue
            line = sum(1 for start in line_starts if start <= match.start())
            where = f"{_res(root, path)}:{line}"
            owner = report.uids.get(uid)
            if owner is None:
                report.errors.append(f"{where}: ext_resource uid {uid} is unknown (path {target}); delete the uid= attribute and keep path=")
            elif owner != target:
                report.errors.append(
                    f"{where}: ext_resource uid {uid} belongs to {owner}, but path= says {target}; Godot would load {owner}"
                )
    return report
