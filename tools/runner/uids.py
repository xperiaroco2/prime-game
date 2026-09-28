"""Static UID lint for Godot text files (no engine needed).

Godot resolves an ext_resource by its uid first and silently ignores `path=` when the uid belongs to
another file, so a copied uid quietly points a scene at the wrong resource. This lint catches that and
the other UID mistakes an agent can make while hand-writing .tscn/.tres files.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

HEADER_RE = re.compile(r'^\[gd_(?:scene|resource)\b[^\]]*\buid="(uid://[a-z0-9]+)"', re.MULTILINE)
EXT_RE = re.compile(r"^\[ext_resource\b([^\]]*)\]", re.MULTILINE)
ATTR_RE = re.compile(r'\b(uid|path)="([^"]*)"')
IMPORT_UID_RE = re.compile(r'^uid="(uid://[a-z0-9]+)"', re.MULTILINE)
SIDECAR_RE = re.compile(r"^uid://[a-z0-9]+$")
SKIP_DIRS = {".git", ".godot", ".idea"}


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    uids: dict[str, str] = field(default_factory=dict)


def _res(root: Path, path: Path) -> str:
    return "res://" + path.relative_to(root).as_posix()


def project_files(root: Path) -> list[Path]:
    """Every file Godot sees: skips .git/.godot and any directory holding a .gdignore."""
    found: list[Path] = []

    def walk(folder: Path) -> None:
        if (folder / ".gdignore").exists() and folder != root:
            return
        for entry in sorted(folder.iterdir()):
            if entry.is_dir():
                if entry.name not in SKIP_DIRS:
                    walk(entry)
            else:
                found.append(entry)

    walk(root)
    return found


def lint(root: Path) -> Report:
    report = Report()
    files = project_files(root)
    owners: dict[str, list[str]] = {}

    def own(uid: str, res_path: str) -> None:
        owners.setdefault(uid, []).append(res_path)

    texts: dict[Path, str] = {}
    for path in files:
        suffix = path.suffix
        if suffix in (".tscn", ".tres"):
            text = path.read_text(encoding="utf-8", errors="replace")
            texts[path] = text
            match = HEADER_RE.search(text)
            if match:
                own(match.group(1), _res(root, path))
        elif suffix == ".uid":
            target = path.with_suffix("")
            value = path.read_text(encoding="utf-8", errors="replace").strip()
            if not SIDECAR_RE.match(value):
                report.errors.append(f"{_res(root, path)}: malformed uid sidecar '{value}'")
                continue
            if not target.exists():
                report.errors.append(f"{_res(root, path)}: sidecar without its file {_res(root, target)}")
                continue
            own(value, _res(root, target))
        elif suffix == ".import":
            text = path.read_text(encoding="utf-8", errors="replace")
            match = IMPORT_UID_RE.search(text)
            if match:
                own(match.group(1), _res(root, path.with_suffix("")))
        elif suffix in (".gd", ".gdshader"):
            sidecar = path.with_name(path.name + ".uid")
            if not sidecar.exists():
                report.errors.append(
                    f"{_res(root, path)}: missing {sidecar.name} (run `check` once, then commit the new .uid file)"
                )

    for uid, paths in sorted(owners.items()):
        if len(paths) > 1:
            report.errors.append(f"duplicate {uid}: {', '.join(sorted(paths))} (never copy a uid or a .uid file)")
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
