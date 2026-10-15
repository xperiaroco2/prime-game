"""An override inside an instance keeps its `[editable path]` entry (#1056).

A level scene may set a property on a node of a scene it instances (the art's rooms: a kit wrapper's mesh material
and its `plan_at` shader parameter, a door body's `collision_layer`). The text loader applies such an override
section by its path, but a re-save (the editor's, `normalize`'s) packs a node inside an instance only when that
instance is editable (`[editable path="<instance>"]`, the editor's Editable Children): without it every override
inside the instance is dropped without a word.

problems() is what `check` reports: each scene under levels/ (the generated kit wrappers aside) with an override whose
nearest instance in the same file has no entry. write() adds the missing entries; `colliders`, the step after an art
import, runs it. Text alone cannot see an instance nested inside the instanced scene, so the House rooms' GdUnit test
(tests/integration/levels/house_overrides_test.gd) packs each room as a re-save does.
"""

from __future__ import annotations

import re
from pathlib import Path

from .common import ROOT

LEVELS = "levels"
KIT = "levels/kit"
HEADER_RE = re.compile(r"^\[node (.*)\]$")
ATTR_RE = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"|[^\s\]]+)')
EDITABLE_RE = re.compile(r'^\[editable path="([^"]+)"\]$')


def _path(name: str, parent: str) -> str:
    return name if parent == "." else f"{parent}/{name}"


def missing(text: str) -> list[str]:
    """The instances (node paths, in file order) that hold an override but have no [editable path] entry."""
    instances: set[str] = set()
    editables: set[str] = set()
    needed: list[str] = []
    for line in text.splitlines():
        entry = EDITABLE_RE.match(line)
        if entry:
            editables.add(entry.group(1))
            continue
        header = HEADER_RE.match(line)
        if not header:
            continue
        attrs = dict(ATTR_RE.findall(header.group(1)))
        parent = attrs["parent"].strip('"') if "parent" in attrs else None
        if parent is None:
            continue  # the root: an instance there is an inherited scene, whose nodes need no entry
        path = _path(attrs.get("name", "").strip('"'), parent)
        if "instance" in attrs:
            instances.add(path)
        if "type" in attrs or "instance" in attrs:
            continue
        owner = parent
        while owner not in instances and "/" in owner:
            owner = owner.rsplit("/", 1)[0]
        if owner in instances and owner not in needed:
            needed.append(owner)
    return [path for path in needed if path not in editables]


def add(text: str) -> str:
    """`text` with an entry for each instance missing() names, after the scene's last section as Godot writes them."""
    paths = missing(text)
    if not paths:
        return text
    lines = text.rstrip("\n").split("\n")
    if not EDITABLE_RE.match(lines[-1]):
        lines.append("")
    lines.extend(f'[editable path="{path}"]' for path in paths)
    return "\n".join(lines) + "\n"


def scenes(root: Path = ROOT) -> list[Path]:
    kit = root / KIT
    return [path for path in sorted((root / LEVELS).rglob("*.tscn")) if kit not in path.parents]


def problems(root: Path = ROOT) -> list[str]:
    found = []
    for scene in scenes(root):
        paths = missing(scene.read_text(encoding="utf-8"))
        if paths:
            shown = ", ".join(paths[:3]) + (f" and {len(paths) - 3} more" if len(paths) > 3 else "")
            found.append(
                f"{scene.relative_to(root).as_posix()}: an override inside {shown} with no [editable path] entry, "
                "which a re-save drops (run tools/run.sh colliders: it adds them)"
            )
    return found


def write(root: Path = ROOT) -> list[str]:
    """Add the missing entries; returns the scenes changed (repo-relative)."""
    changed = []
    for scene in scenes(root):
        text = scene.read_text(encoding="utf-8")
        new = add(text)
        if new != text:
            scene.write_bytes(new.encode("utf-8"))
            changed.append(scene.relative_to(root).as_posix())
    return changed
