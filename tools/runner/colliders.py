"""`colliders`: the art's collision as text resources outside Git LFS (#523, the engineer's CI option B).

The art's GLBs under assets/environment/ (Git LFS) carry their collision as import-hint meshes: `-convcolonly` and
`-colonly` (a collider alone) and `-convcol` and `-col` (a mesh with a collider of its own). A checkout without LFS
content (CI checks out with `lfs: false`, the LFS ADR) imports each GLB as an empty stand-in (lfs.py), so a level
built from them would have no floors, walls or stairs. This step moves each hint collider out of its GLB:

- levels/kit/<pack>/<stem>.tscn, the GLB's wrapper: a scene that instances the GLB (the look only) and holds one
  StaticBody3D per hint collider at its root, named as Godot's importer names it (a `-col` mesh's body:
  `<mesh>_col`), placed where the importer places it (its ancestors' transforms folded in);
- levels/kit/<pack>/<stem>.<body>.tres, each body's shape: a ConvexPolygonShape3D (`convcol`: the mesh's vertices
  snapped as Godot's convex hull snaps them, hull_points(); physics builds the importer's single convex shape from
  them) or a ConcavePolygonShape3D (`col`: the mesh's triangles in Godot's winding, as the importer's trimesh);
- the GLB's .import skips the importer's own bodies (`_subresources`, the Advanced Import Settings' Skip Import), so a
  checkout with LFS content holds each collider once;
- every scene of the project (SCENE_SKIP: not under addons/, tools/out/, levels/kit/ or a dot folder, #1256) that
  instanced such a GLB instances its wrapper instead (the ext_resource's path).

`colliders` writes all four from the GLBs' content; a pointer file (no LFS content) is skipped with a line. `check`
runs problems(): no such scene instances a wrapped GLB directly, and each GLB with content has exactly the
files `colliders` would write. An override in a scene that reached into a GLB's collider (a door leaf's layer, a
ground's surface tag) now names the wrapper's body: no step rewrites those. Each such override needs its instance's
`[editable path]` entry, or a re-save drops it: `colliders` ends by adding the missing ones (editables.py, #1056).

`colliders` owns every Skip Import entry (`nodes`) in the .import of an art GLB: it sets exactly the hint colliders'
and drops any other, so a node skipped by hand in Advanced Import Settings does not last. A wrapper whose GLB lost
its hint colliders is deleted with its shapes, and the scenes instance the GLB again.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import struct
import zlib
from array import array
from dataclasses import dataclass, field
from pathlib import Path

from . import editables, lfs
from .common import ROOT, bad, ok, say

ASSETS = "assets/environment"
KIT = "levels/kit"
# The folders _scenes never walks (#1256): third-party scenes, the runner's output, the wrappers themselves; and every
# folder whose name starts with a dot (.godot/, .git/, .claude/ with the other worktrees).
SCENE_SKIP: tuple[str, ...] = ("addons", "tools/out", KIT)
# The importer's hints in the order its _pre_fix_node tests them (Godot 4.7.2, resource_importer_scene.cpp): the
# collider-only pair first, then the pair that keeps the mesh. Each: (hint, convex, mesh kept).
HINTS = (("colonly", False, False), ("convcolonly", True, False), ("col", False, True), ("convcol", True, True))
SKIP = {"import/skip_import": True}
# String::invalid_node_name_characters: GLTFDocument names a node after validate_node_name(), each one an underscore.
INVALID_NAME = re.compile(r'[.:@/"%]')
# ResourceUID's text form: base 34 ('z' and '9' unused, GH-83843), most significant digit first.
UID_CHARS = "abcdefghijklmnopqrstuvwxy012345678"
COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
EXT_RE = re.compile(r'^\[ext_resource\b[^\]]*\bpath="(res://[^"]+\.glb)"[^\]]*\]$', re.MULTILINE)
WRAPPER_RE = re.compile(r'^\[ext_resource\b[^\]]*\bpath="(res://levels/kit/[^"]+\.tscn)"[^\]]*\]$', re.MULTILINE)
UID_ATTR = re.compile(r' uid="uid://[a-z0-9]+"')
# The _subresources value: up to the next key line (a Godot dictionary spans lines), a section or the end.
SUBRESOURCES = re.compile(r"^_subresources=(.*?)\n(?=[A-Za-z_][\w/]*=|\[|\Z)", re.MULTILINE | re.DOTALL)
IMPORT_UID = re.compile(r'^uid="(uid://[a-z0-9]+)"', re.MULTILINE)

Matrix = tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]
Vec = tuple[float, float, float]
IDENTITY: tuple[Matrix, Vec] = (((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)), (0.0, 0.0, 0.0))


class GlbError(Exception):
    """A GLB this step cannot read or does not support (the message names it)."""


@dataclass(frozen=True)
class Body:
    """One hint collider: its body's name in the wrapper, the importer's import id of its own body (skipped), its
    place in the GLB's root frame (basis rows and origin), and its shape's points (convex) or faces (concave)."""

    name: str
    skip: str
    place: tuple[Matrix, Vec]
    convex: bool
    points: tuple[Vec, ...]


@dataclass
class Plan:
    """What `colliders` writes, repo-relative path to text; and the GLBs it skipped (pointer files)."""

    files: dict[str, str] = field(default_factory=dict)
    wrappers: dict[str, str] = field(default_factory=dict)  # res:// GLB -> res:// wrapper
    pointers: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def _tail(name: str) -> str:
    """The name without the trailing digits, underscores and spaces a duplicate gets (the importer's _teststr)."""
    end = len(name)
    while end and ("0" <= name[end - 1] <= "9" or ord(name[end - 1]) <= 32 or name[end - 1] == "_"):
        end -= 1
    return name[:end]


def has_hint(name: str, hint: str) -> bool:
    """Whether the importer reads `hint` in the node name `name` (its _teststr)."""
    what = _tail(name).lower()
    return f"${hint}" in what or what.endswith(f"-{hint}") or what.endswith(f"_{hint}")


def without_hint(name: str, hint: str) -> str:
    """The name the importer gives the node once it has read `hint` (its _fixstr)."""
    what = _tail(name)
    end = name[len(what) :]
    if f"${hint}" in what.lower():
        return what.replace(f"${hint}", "") + end
    if what.lower().endswith((f"-{hint}", f"_{hint}")):
        return what[: -(len(hint) + 1)] + end
    return name


def hint_of(name: str) -> tuple[str, bool, bool] | None:
    """The collision hint the importer acts on for `name`, or None."""
    for hint in HINTS[:2]:
        if has_hint(name, hint[0]):
            return hint
    for hint in HINTS[2:]:
        if has_hint(name, hint[0]):
            return hint
    return None


def read_glb(data: bytes) -> tuple[dict, bytes]:
    """A binary glTF's JSON and its BIN chunk."""
    if len(data) < 20 or data[:4] != b"glTF":
        raise GlbError("not a binary glTF")
    offset, chunks = 12, {}
    while offset + 8 <= len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        chunks.setdefault(kind, data[offset + 8 : offset + 8 + size])
        offset += 8 + size
    if 0x4E4F534A not in chunks:
        raise GlbError("no JSON chunk")
    return json.loads(chunks[0x4E4F534A]), chunks.get(0x004E4942, b"")


def _accessor(gltf: dict, blob: bytes, index: int) -> list[tuple]:
    accessor = gltf["accessors"][index]
    if "sparse" in accessor or "bufferView" not in accessor or accessor.get("normalized"):
        raise GlbError(f"accessor {index}: sparse, normalized or without a buffer view")
    view = gltf["bufferViews"][accessor["bufferView"]]
    if view.get("buffer", 0) != 0 or "uri" in gltf["buffers"][view.get("buffer", 0)]:
        raise GlbError(f"accessor {index}: data outside the GLB's BIN chunk")
    code = COMPONENTS[accessor["componentType"]]
    width = WIDTHS[accessor["type"]]
    item = struct.calcsize("<" + code) * width
    stride = view.get("byteStride") or item
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    count = accessor["count"]
    if stride == item:
        values = array(code, blob[start : start + item * count])
        if struct.pack("=H", 1) != struct.pack("<H", 1):
            values.byteswap()
        return [tuple(values[i * width : i * width + width]) for i in range(count)]
    return [struct.unpack_from("<" + code * width, blob, start + i * stride) for i in range(count)]


def _triangles(gltf: dict, blob: bytes, mesh: int) -> list[tuple[Vec, Vec, Vec]]:
    """The mesh's triangles in Godot's winding: its glTF importer swaps each triangle's last two corners."""
    faces = []
    for primitive in gltf["meshes"][mesh]["primitives"]:
        if primitive.get("mode", 4) != 4:
            raise GlbError(f"mesh {mesh}: a primitive that is not triangles")
        points = _accessor(gltf, blob, primitive["attributes"]["POSITION"])
        if "indices" in primitive:
            order = [i[0] for i in _accessor(gltf, blob, primitive["indices"])]
        else:
            order = list(range(len(points)))
        for i in range(0, len(order) - 2, 3):
            faces.append((points[order[i]], points[order[i + 2]], points[order[i + 1]]))
    return faces


def _f32(value: float) -> float:
    """`value` rounded to float32 (Godot's real_t): one float32 operation is the double result rounded once."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def _positions(gltf: dict, blob: bytes, mesh: int) -> list[Vec]:
    """Every vertex of the mesh in the order the importer's ImporterMesh holds them (each primitive's POSITION
    accessor in turn: an indexed primitive keeps its vertex order through SurfaceTool)."""
    points: list[Vec] = []
    for primitive in gltf["meshes"][mesh]["primitives"]:
        points.extend(_accessor(gltf, blob, primitive["attributes"]["POSITION"]))  # type: ignore[arg-type]
    return points


def hull_points(points: list[Vec]) -> tuple[Vec, ...]:
    """The points as Godot's convex hull (core/math/convex_hull.cpp, the importer's single convex shape) gives them
    back, each distinct one once: snapped toward the AABB's first corner to 1/10216 of each side, all in float32. The
    importer keeps only the hull's corners; physics builds the same hull from these. Exact snapping matters: a hull
    0.3 mm larger than the import's touches a capsule the import's does not."""
    if not points:
        return ()
    corner, size = list(points[0]), [0.0, 0.0, 0.0]
    for point in points[1:]:  # AABB::expand_to, its end recomputed from position + size each time
        begin, end = corner[:], [_f32(corner[i] + size[i]) for i in range(3)]
        for i in range(3):
            begin[i] = point[i] if point[i] < begin[i] else begin[i]
            end[i] = point[i] if point[i] > end[i] else end[i]
        corner, size = begin, [_f32(end[i] - begin[i]) for i in range(3)]
    x, y, z = size
    longest = (2 if y < z else 1) if x < y else (2 if x < z else 0)
    shortest = (0 if x < z else 2) if x < y else (1 if y < z else 2)
    if shortest == longest:
        shortest = (longest + 1) % 3
    middle = 3 - longest - shortest
    scaling = [_f32(side / 10216) for side in size]
    if (middle + 1) % 3 != longest:
        scaling = [-step for step in scaling]
    inverse = [_f32(1 / step) if step != 0 else 0.0 for step in scaling]
    snapped: dict[Vec, None] = {}
    for point in points:
        steps = [int(_f32(_f32(point[i] - corner[i]) * inverse[i])) for i in range(3)]  # (int32_t): toward zero
        snapped.setdefault(tuple(_f32(_f32(steps[i] * scaling[i]) + corner[i]) for i in range(3)), None)  # type: ignore[arg-type]
    return tuple(snapped)


def _local(node: dict) -> tuple[Matrix, Vec]:
    if "matrix" in node:
        m = node["matrix"]  # column-major
        rows = tuple(tuple(float(m[col * 4 + row]) for col in range(3)) for row in range(3))
        return rows, (float(m[12]), float(m[13]), float(m[14]))  # type: ignore[return-value]
    x, y, z, w = node.get("rotation", (0.0, 0.0, 0.0, 1.0))
    sx, sy, sz = node.get("scale", (1.0, 1.0, 1.0))
    rotation = (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )
    rows = tuple((r[0] * sx, r[1] * sy, r[2] * sz) for r in rotation)
    tx, ty, tz = node.get("translation", (0.0, 0.0, 0.0))
    return rows, (float(tx), float(ty), float(tz))  # type: ignore[return-value]


def _compose(parent: tuple[Matrix, Vec], child: tuple[Matrix, Vec]) -> tuple[Matrix, Vec]:
    (a, at), (b, bt) = parent, child
    rows = tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))
    origin = tuple(sum(a[i][k] * bt[k] for k in range(3)) + at[i] for i in range(3))
    return rows, origin  # type: ignore[return-value]


def bodies(data: bytes) -> tuple[list[Body], set[str]]:
    """The hint colliders of a GLB's default scene, and the names of its root's children once imported."""
    gltf, blob = read_glb(data)
    nodes = gltf.get("nodes", [])
    scene = gltf["scenes"][gltf.get("scene", 0)] if gltf.get("scenes") else {"nodes": []}
    found: list[Body] = []
    top: set[str] = set()

    def visit(index: int, path: list[str], place: tuple[Matrix, Vec], depth: int) -> None:
        node = nodes[index]
        name = INVALID_NAME.sub("_", node.get("name", ""))
        if not name:
            raise GlbError(f"node {index} has no name")
        here = _compose(place, _local(node))
        hint = hint_of(name)
        if hint is None:
            if depth == 0:
                top.add(name)
            for child in node.get("children", []):
                visit(child, path + [name], here, depth + 1)
            return
        word, convex, kept = hint
        if "mesh" not in node or node.get("children"):
            raise GlbError(f"{name}: a collision hint on a node without a mesh, or with children")
        faces = _triangles(gltf, blob, node["mesh"])
        fixed = without_hint(name, word)
        if kept:
            if depth == 0:
                top.add(fixed)
            skip, body = "/".join(path + [fixed, "StaticBody3D"]), f"{fixed}_col"
        else:
            skip, body = "/".join(path + [fixed]), fixed
        points = hull_points(_positions(gltf, blob, node["mesh"])) if convex else tuple(p for face in faces for p in face)
        found.append(Body(body, "PATH:" + skip, here, convex, points))

    for index in scene.get("nodes", []):
        visit(index, [], IDENTITY, 0)
    names = [body.name for body in found]
    for name in sorted({n for n in names if names.count(n) > 1 or n in top}):
        raise GlbError(f"body name {name} is taken (another collider or a node of the GLB's root)")
    return found, top


def number(value: float) -> str:
    """A float32 value in the shortest text that reads back as the same float32 (Godot's real_t)."""
    single = struct.unpack("<f", struct.pack("<f", value))[0]
    if single == 0 or not math.isfinite(single):
        return "0" if single == 0 else str(single)
    for digits in range(1, 10):
        text = f"{single:.{digits}g}"
        if struct.unpack("<f", struct.pack("<f", float(text)))[0] == single:
            return text
    return repr(single)


def uid(rel: str) -> str:
    """A stable uid for the generated file `rel`: its id from a hash of the path, in ResourceUID's text form."""
    value = int.from_bytes(hashlib.sha256(f"prime-game colliders:{rel}".encode()).digest()[:8], "big")
    value &= 0x7FFF_FFFF_FFFF_FFFF
    digits = ""
    while True:
        value, rest = divmod(value, len(UID_CHARS))
        digits = UID_CHARS[rest] + digits
        if not value:
            return "uid://" + digits


def _unique_id(rel: str, node: str) -> int:
    return zlib.crc32(f"{rel}:{node}".encode()) & 0x7FFF_FFFF or 1


def shape_text(rel: str, body: Body) -> str:
    kind, key = ("ConvexPolygonShape3D", "points") if body.convex else ("ConcavePolygonShape3D", "data")
    values = ", ".join(number(c) for point in body.points for c in point)
    return f'[gd_resource type="{kind}" format=3 uid="{uid(rel)}"]\n\n[resource]\n{key} = PackedVector3Array({values})\n'


def _transform(place: tuple[Matrix, Vec]) -> str:
    rows, origin = place
    # A rotation's float noise (cos 90 degrees) reads as 0, as Godot's float32 basis would hold it.
    values = [0.0 if abs(v) < 1e-7 else v for v in [*rows[0], *rows[1], *rows[2], *origin]]
    return "Transform3D(" + ", ".join(number(v) for v in values) + ")"


def wrapper_text(rel: str, glb: str, glb_uid: str | None, stem: str, shapes: list[tuple[Body, str]]) -> str:
    """The wrapper scene `rel`: the GLB `glb` (res://) at its root, then each body with its shape (res://)."""
    look = f' uid="{glb_uid}"' if glb_uid else ""
    parts = [f'[gd_scene format=3 uid="{uid(rel)}"]', f'[ext_resource type="PackedScene"{look} path="{glb}" id="1"]']
    for number_, (body, shape) in enumerate(shapes, start=2):
        kind = "ConvexPolygonShape3D" if body.convex else "ConcavePolygonShape3D"
        parts.append(f'[ext_resource type="{kind}" uid="{uid(shape[6:])}" path="{shape}" id="{number_}"]')
    parts.append(f'[node name="{stem}" unique_id={_unique_id(rel, ".")} instance=ExtResource("1")]')
    for number_, (body, _shape) in enumerate(shapes, start=2):
        node = f'[node name="{body.name}" type="StaticBody3D" parent="." unique_id={_unique_id(rel, body.name)}]'
        parts.append(node if body.place == IDENTITY else f"{node}\ntransform = {_transform(body.place)}")
        child = f"{body.name}/CollisionShape3D"
        parts.append(
            f'[node name="CollisionShape3D" type="CollisionShape3D" parent="{body.name}" '
            f'unique_id={_unique_id(rel, child)}]\nshape = ExtResource("{number_}")'
        )
    return "\n\n".join(parts) + "\n"


def _godot_value(value: object) -> str:
    if value is True or value is False:
        return "true" if value else "false"
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = [f"{json.dumps(key)}: {_godot_value(value[key])}" for key in sorted(value)]
        return "{\n" + ",\n".join(items) + "\n}"
    return json.dumps(value)


def import_text(text: str, skips: list[str]) -> str:
    """The GLB's .import text with exactly `skips` as its skipped nodes (other subresources kept)."""
    match = SUBRESOURCES.search(text)
    if match is None:
        raise GlbError("no _subresources line in its .import")
    try:
        current = json.loads(match.group(1))
    except json.JSONDecodeError as error:
        raise GlbError(f"its .import's _subresources is not plain data: {error}") from error
    nodes = {key: value for key, value in current.get("nodes", {}).items() if value != SKIP}
    nodes.update({skip: dict(SKIP) for skip in skips})
    if nodes:
        current["nodes"] = nodes
    else:
        current.pop("nodes", None)
    return text[: match.start()] + "_subresources=" + _godot_value(current) + "\n" + text[match.end() :]


def _glbs(root: Path) -> list[Path]:
    return sorted((root / ASSETS).glob("*/*.glb"))


def _rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def plan(root: Path = ROOT) -> Plan:
    """Every file `colliders` writes, from each GLB with LFS content."""
    result = Plan()
    for glb in _glbs(root):
        rel = _rel(root, glb)
        if lfs.is_pointer(glb):
            result.pointers.append(rel)
            continue
        try:
            found, _top = bodies(glb.read_bytes())
            import_path = glb.with_name(glb.name + ".import")
            import_old = import_path.read_text(encoding="utf-8") if import_path.exists() else ""
            import_new = import_text(import_old, [body.skip for body in found]) if import_old else ""
        except (GlbError, KeyError, IndexError, ValueError, struct.error) as error:
            result.errors.append(f"{rel}: {error}")
            continue
        if import_old and import_new != import_old:
            result.files[_rel(root, import_path)] = import_new
        if not found:
            continue
        if not import_old:
            result.errors.append(f"{rel}: no .import beside it (let Godot import it first)")
            continue
        pack, stem = glb.parent.name, glb.stem
        wrapper = f"{KIT}/{pack}/{stem}.tscn"
        shapes = []
        for body in found:
            shape = f"{KIT}/{pack}/{stem}.{body.name}.tres"
            result.files[shape] = shape_text(shape, body)
            shapes.append((body, "res://" + shape))
        match = IMPORT_UID.search(import_old)
        result.files[wrapper] = wrapper_text(wrapper, "res://" + rel, match.group(1) if match else None, stem, shapes)
        result.wrappers["res://" + rel] = "res://" + wrapper
    return result


def known_wrappers(root: Path = ROOT) -> dict[str, str]:
    """res:// GLB -> res:// wrapper for each wrapper on disk (no LFS content needed): its first ext_resource."""
    found = {}
    for wrapper in sorted((root / KIT).glob("*/*.tscn")):
        match = EXT_RE.search(wrapper.read_text(encoding="utf-8"))
        if match and match.group(1).startswith(f"res://{ASSETS}/"):
            found[match.group(1)] = "res://" + _rel(root, wrapper)
    return found


def _scenes(root: Path) -> list[Path]:
    """Every .tscn of the project but those under SCENE_SKIP or a dot folder, sorted (#1256: not only levels/, so a
    scene under client/, tests/ or content/ that instances a wrapped GLB is caught too)."""
    found = []
    for folder, dirs, files in os.walk(root):
        rel = Path(folder).relative_to(root)
        dirs[:] = [d for d in dirs if not d.startswith(".") and (rel / d).as_posix() not in SCENE_SKIP]
        found += [Path(folder) / name for name in files if name.endswith(".tscn")]
    return sorted(found)


def retarget(text: str, wrappers: dict[str, str], pattern: re.Pattern[str] = EXT_RE) -> str:
    """A scene's text with each ext_resource of a wrapped GLB pointing at its wrapper (a uid attribute dropped);
    `pattern` finds the ext_resources (group 1 is the path)."""

    def swap(match: re.Match[str]) -> str:
        target = wrappers.get(match.group(1))
        if target is None:
            return match.group(0)
        return UID_ATTR.sub("", match.group(0)).replace(f'path="{match.group(1)}"', f'path="{target}"')

    return pattern.sub(swap, text)


def _stale_shapes(root: Path, files: dict[str, str], stems: set[tuple[str, str]]) -> list[str]:
    """Shape files of a planned wrapper that the plan no longer writes."""
    stale = []
    for pack, stem in sorted(stems):
        for path in sorted((root / KIT / pack).glob(f"{stem}.*.tres")):
            if _rel(root, path) not in files:
                stale.append(_rel(root, path))
    return stale


def problems(root: Path = ROOT) -> list[str]:
    """What `check` reports: a scene that instances a wrapped GLB directly; with LFS content, a generated file that
    is missing, stale or left over."""
    found = []
    fix = "run tools/run.sh colliders"
    wrappers = known_wrappers(root)
    for scene in _scenes(root):
        for match in EXT_RE.finditer(scene.read_text(encoding="utf-8")):
            if match.group(1) in wrappers:
                found.append(
                    f"{_rel(root, scene)}: instances {match.group(1)}, whose colliders its import skips; instance "
                    f"{wrappers[match.group(1)]} ({fix})"
                )
    planned = plan(root)
    found.extend(planned.errors)
    for rel, text in sorted(planned.files.items()):
        path = root / rel
        if not path.exists():
            found.append(f"{rel}: missing ({fix})")
        elif path.read_text(encoding="utf-8") != text:
            found.append(f"{rel}: stale, not what its GLB gives ({fix})")
    stems = {(rel.split("/")[2], Path(rel).stem) for rel in planned.files if rel.endswith(".tscn")}
    found.extend(f"{rel}: left over ({fix})" for rel in _stale_shapes(root, planned.files, stems))
    for glb, wrapper in sorted(_left_over(root, planned).items()):
        found.append(f"{wrapper[len('res://') :]}: left over, {glb} has no hint collider ({fix})")
    return found


def _left_over(root: Path, planned: Plan) -> dict[str, str]:
    """GLB -> wrapper for each wrapper whose GLB has content but no hint collider any more."""
    return {
        glb: wrapper
        for glb, wrapper in known_wrappers(root).items()
        if glb not in planned.wrappers
        and (root / glb[len("res://") :]).exists()
        and not lfs.is_pointer(root / glb[len("res://") :])
    }


def _drop_left_over(root: Path, planned: Plan) -> None:
    """Point the scenes back at the GLB of each left-over wrapper, then delete the wrapper and its shapes."""
    gone = _left_over(root, planned)
    if not gone:
        return
    back = {wrapper: glb for glb, wrapper in gone.items()}
    for scene in _scenes(root):
        text = scene.read_text(encoding="utf-8")
        new = retarget(text, back, WRAPPER_RE)
        if new != text:
            scene.write_bytes(new.encode("utf-8"))
    for wrapper in gone.values():
        path = root / wrapper[len("res://") :]
        for shape in path.parent.glob(f"{path.stem}.*.tres"):
            shape.unlink()
        path.unlink()


def write(root: Path = ROOT) -> Plan:
    """Write every planned file that differs, drop the planned wrappers' left-over shapes, retarget the scenes."""
    planned = plan(root)
    if planned.errors:
        return planned
    for rel, text in planned.files.items():
        path = root / rel
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(text.encode("utf-8"))
    stems = {(rel.split("/")[2], Path(rel).stem) for rel in planned.files if rel.endswith(".tscn")}
    for rel in _stale_shapes(root, planned.files, stems):
        (root / rel).unlink()
    _drop_left_over(root, planned)
    wrappers = known_wrappers(root)
    for scene in _scenes(root):
        text = scene.read_text(encoding="utf-8")
        new = retarget(text, wrappers)
        if new != text:
            scene.write_bytes(new.encode("utf-8"))
    return planned


def main(check_only: bool = False) -> int:
    if check_only:
        found = problems()
        for line in found:
            bad(line)
        if not found:
            ok("colliders: every wrapped GLB's files are current, no scene instances a wrapped GLB")
        return 1 if found else 0
    planned = write()
    for line in planned.errors:
        bad(line)
    for rel in planned.pointers:
        say(f"  skipped {rel}: an LFS pointer file (git lfs pull for its content)")
    if planned.errors:
        say("colliders: FAILED")
        return 1
    ok(f"colliders: {len(planned.wrappers)} wrappers in {KIT}/ (git status shows what changed)")
    for rel in editables.write():
        ok(f"{rel}: added the [editable path] entries its overrides need (#1056)")
    return 0
