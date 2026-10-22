"""colliders (#523, CI option B): the importer's hint names, a GLB's bodies, the files `colliders` writes, and what
`check` reports (a scene that instances a wrapped GLB directly; a stale, missing or left-over file)."""

import json
import math
import struct
import tempfile
import unittest
from pathlib import Path

from runner import colliders

IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"
uid="uid://bgate"
path="res://.godot/imported/gate.glb-0.scn"

[params]

nodes/root_type=""
import_script/path=""
_subresources={}
gltf/naming_version=2
"""
SCENE = """[gd_scene format=3]

[ext_resource type="PackedScene" uid="uid://bgate" path="res://assets/environment/pack/gate.glb" id="1"]

[ext_resource type="PackedScene" path="res://assets/environment/pack/plain.glb" id="2"]

[node name="Room" type="Node3D"]

[node name="gate_1" parent="." instance=ExtResource("1")]
"""
TETRA = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]


def glb(nodes: list[dict], scene: list[int], meshes: list[tuple[list[tuple[float, float, float]], list[int]]]) -> bytes:
    """A binary glTF with `meshes` (positions, triangle indices) as float32 and uint16 accessors."""
    blob, views, accessors, out_meshes = b"", [], [], []
    for points, indices in meshes:
        position = struct.pack(f"<{3 * len(points)}f", *[c for p in points for c in p])
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(position)})
        accessors.append({"bufferView": len(views) - 1, "componentType": 5126, "count": len(points), "type": "VEC3"})
        blob += position
        index = struct.pack(f"<{len(indices)}H", *indices)
        index += b"\0" * (-len(index) % 4)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": 2 * len(indices)})
        accessors.append({"bufferView": len(views) - 1, "componentType": 5123, "count": len(indices), "type": "SCALAR"})
        blob += index
        out_meshes.append({"primitives": [{"attributes": {"POSITION": len(accessors) - 2}, "indices": len(accessors) - 1}]})
    gltf = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": scene}],
        "nodes": nodes,
        "meshes": out_meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    text = json.dumps(gltf).encode()
    text += b" " * (-len(text) % 4)
    body = struct.pack("<II", len(text), 0x4E4F534A) + text + struct.pack("<II", len(blob), 0x004E4942) + blob
    return b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body


# A gate: a post with a convex collider at the root, a leaf turned a quarter about +Y and moved 2 m along +X whose
# collider sits 1 m up inside it, and a ground mesh with a trimesh collider of its own (`-col`).
QUARTER = [0.0, math.sin(math.pi / 4), 0.0, math.cos(math.pi / 4)]
GATE = glb(
    [
        {"name": "gate", "mesh": 0},
        {"name": "gate_col0-convcolonly", "mesh": 0, "translation": [0.5, 0, 0]},
        {"name": "gate_leaf", "mesh": 0, "translation": [2, 0, 0], "rotation": QUARTER, "children": [3]},
        {"name": "gate_col1-convcolonly", "mesh": 0, "translation": [0, 1, 0]},
        {"name": "ground-col", "mesh": 1},
    ],
    [0, 1, 2, 4],
    [(TETRA, [0, 1, 2, 0, 2, 3, 0, 3, 1, 1, 3, 2]), ([(0, 0, 0), (1, 0, 0), (0, 0, 1)], [0, 1, 2])],
)
PLAIN = glb([{"name": "plain", "mesh": 0}], [0], [(TETRA, [0, 1, 2])])


class HintTest(unittest.TestCase):
    def test_the_importer_s_suffixes_and_its_duplicate_tails(self) -> None:
        self.assertEqual(colliders.hint_of("wall-convcolonly"), ("convcolonly", True, False))
        self.assertEqual(colliders.hint_of("floor_colonly"), ("colonly", False, False))
        self.assertEqual(colliders.hint_of("ground-col"), ("col", False, True))
        self.assertEqual(colliders.hint_of("rock$convcol"), ("convcol", True, True))
        self.assertEqual(colliders.hint_of("wall-convcolonly_001"), ("convcolonly", True, False))
        # The importer drops a name's trailing digits before it tests: "fence_col1" is a `-col` mesh to it too.
        self.assertEqual(colliders.hint_of("fence_col1"), ("col", False, True))
        self.assertIsNone(colliders.hint_of("collar"))
        self.assertIsNone(colliders.hint_of("column"))
        self.assertEqual(colliders.without_hint("wall-convcolonly_001", "convcolonly"), "wall_001")
        self.assertEqual(colliders.without_hint("gate_col1-convcolonly", "convcolonly"), "gate_col1")
        self.assertEqual(colliders.without_hint("rock$convcol", "convcol"), "rock")


class BodiesTest(unittest.TestCase):
    def test_each_hint_collider_with_its_place_and_its_shape(self) -> None:
        found, top = colliders.bodies(GATE)
        by_name = {body.name: body for body in found}
        self.assertEqual(list(by_name), ["gate_col0", "gate_col1", "ground_col"])
        self.assertEqual(top, {"gate", "gate_leaf", "ground"})
        self.assertEqual(by_name["gate_col0"].skip, "PATH:gate_col0")
        self.assertEqual(by_name["gate_col1"].skip, "PATH:gate_leaf/gate_col1")
        self.assertEqual(by_name["ground_col"].skip, "PATH:ground/StaticBody3D")
        # The leaf's quarter turn and offset are folded into its collider's place: 1 m up stays 1 m up.
        rows, origin = by_name["gate_col1"].place
        self.assertEqual(colliders._transform((rows, origin)), "Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, 2, 1, 0)")
        self.assertTrue(by_name["gate_col0"].convex)
        self.assertEqual(sorted(by_name["gate_col0"].points), sorted(TETRA))
        # A trimesh keeps every triangle, in Godot's winding (the importer swaps each one's last two corners).
        ground = by_name["ground_col"]
        self.assertFalse(ground.convex)
        self.assertEqual(ground.points, ((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0)))

    def test_a_body_name_the_glb_s_root_already_holds_is_refused(self) -> None:
        clash = glb(
            [{"name": "post", "mesh": 0}, {"name": "leaf", "children": [2]}, {"name": "post-convcolonly", "mesh": 0}],
            [0, 1],
            [(TETRA, [0, 1, 2])],
        )
        with self.assertRaisesRegex(colliders.GlbError, "post is taken"):
            colliders.bodies(clash)


class TextTest(unittest.TestCase):
    def test_numbers_are_the_shortest_float32_text(self) -> None:
        self.assertEqual(colliders.number(1.0), "1")
        self.assertEqual(colliders.number(-0.0), "0")
        self.assertEqual(colliders.number(0.1), "0.1")
        self.assertEqual(colliders.number(math.sqrt(0.5)), "0.70710677")

    def test_a_uid_is_stable_and_godot_reads_it_as_a_63_bit_id(self) -> None:
        text = colliders.uid("levels/kit/pack/gate.tscn")
        self.assertEqual(text, colliders.uid("levels/kit/pack/gate.tscn"))
        self.assertNotEqual(text, colliders.uid("levels/kit/pack/gate.gate_col0.tres"))
        value = 0
        for char in text[len("uid://") :]:  # ResourceUID::text_to_id
            value = value * 34 + (ord(char) - 97 if char.isalpha() else ord(char) - 48 + 25)
        self.assertLess(value, 2**63)
        self.assertNotIn("z", text[6:])
        self.assertNotIn("9", text[6:])

    def test_the_import_skips_exactly_the_bodies_and_keeps_its_other_subresources(self) -> None:
        text = colliders.import_text(IMPORT, ["PATH:b", "PATH:a/c"])
        self.assertIn(
            '_subresources={\n"nodes": {\n"PATH:a/c": {\n"import/skip_import": true\n},\n'
            '"PATH:b": {\n"import/skip_import": true\n}\n}\n}\ngltf/naming_version=2\n',
            text,
        )
        self.assertEqual(colliders.import_text(text, ["PATH:b", "PATH:a/c"]), text)
        self.assertEqual(colliders.import_text(text, []), IMPORT)
        kept = IMPORT.replace("_subresources={}", '_subresources={\n"materials": {\n"m": {\n"use_external/enabled": true\n}\n}\n}')
        self.assertIn('"materials"', colliders.import_text(kept, ["PATH:b"]))


class WriteAndCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        pack = self.root / "assets/environment/pack"
        pack.mkdir(parents=True)
        (pack / "gate.glb").write_bytes(GATE)
        (pack / "gate.glb.import").write_bytes(IMPORT.encode())
        (pack / "plain.glb").write_bytes(PLAIN)
        (pack / "plain.glb.import").write_bytes(IMPORT.replace("bgate", "bplain").encode())
        (self.root / "levels/rooms").mkdir(parents=True)
        self.scene = self.root / "levels/rooms/room.tscn"
        self.scene.write_bytes(SCENE.encode())

    def tearDown(self) -> None:
        self.dir.cleanup()

    def test_write_makes_the_wrapper_its_shapes_the_import_and_the_scene_agree(self) -> None:
        self.assertEqual(colliders.write(self.root).errors, [])
        kit = self.root / "levels/kit/pack"
        self.assertEqual(
            sorted(path.name for path in kit.iterdir()),
            ["gate.gate_col0.tres", "gate.gate_col1.tres", "gate.ground_col.tres", "gate.tscn"],
        )
        wrapper = (kit / "gate.tscn").read_text(encoding="utf-8")
        self.assertIn('[ext_resource type="PackedScene" uid="uid://bgate" path="res://assets/environment/pack/gate.glb"', wrapper)
        self.assertIn('[node name="gate" unique_id=', wrapper)
        self.assertIn('[node name="gate_col1" type="StaticBody3D" parent="."', wrapper)
        self.assertIn("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.5, 0, 0)", wrapper)
        self.assertIn('type="ConcavePolygonShape3D"', wrapper)
        shape = (kit / "gate.ground_col.tres").read_text(encoding="utf-8")
        self.assertIn("data = PackedVector3Array(0, 0, 0, 0, 0, 1, 1, 0, 0)", shape)
        imported = (self.root / "assets/environment/pack/gate.glb.import").read_text(encoding="utf-8")
        self.assertIn('"PATH:gate_leaf/gate_col1": {\n"import/skip_import": true\n}', imported)
        scene = self.scene.read_text(encoding="utf-8")
        self.assertIn('[ext_resource type="PackedScene" path="res://levels/kit/pack/gate.tscn" id="1"]', scene)
        self.assertIn('path="res://assets/environment/pack/plain.glb" id="2"', scene)
        self.assertEqual(colliders.problems(self.root), [])
        self.assertEqual(colliders.write(self.root).files, colliders.plan(self.root).files)

    def test_check_reports_a_scene_that_instances_a_wrapped_glb_directly(self) -> None:
        colliders.write(self.root)
        self.scene.write_bytes(SCENE.encode())
        found = colliders.problems(self.root)
        self.assertEqual(len(found), 1)
        self.assertIn("levels/rooms/room.tscn: instances res://assets/environment/pack/gate.glb", found[0])

    def test_check_reports_a_scene_outside_levels_and_skips_addons_tools_out_and_dot_folders(self) -> None:
        # #1256: every scene of the project is walked, not only levels/.
        colliders.write(self.root)
        for rel in ("client/hud/hud.tscn", "addons/x/x.tscn", "tools/out/x.tscn", ".godot/x.tscn", ".claude/w/x.tscn"):
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.root / rel).write_bytes(SCENE.encode())
        found = colliders.problems(self.root)
        self.assertEqual(len(found), 1, found)
        self.assertIn("client/hud/hud.tscn: instances res://assets/environment/pack/gate.glb", found[0])

    def test_check_reports_a_stale_a_missing_and_a_left_over_file(self) -> None:
        colliders.write(self.root)
        kit = self.root / "levels/kit/pack"
        (kit / "gate.gate_col0.tres").write_bytes(b"[gd_resource]\n")
        (kit / "gate.ground_col.tres").unlink()
        (kit / "gate.old_col.tres").write_bytes(b"[gd_resource]\n")
        found = "\n".join(colliders.problems(self.root))
        self.assertIn("levels/kit/pack/gate.gate_col0.tres: stale", found)
        self.assertIn("levels/kit/pack/gate.ground_col.tres: missing", found)
        self.assertIn("levels/kit/pack/gate.old_col.tres: left over", found)

    def test_a_glb_that_lost_its_colliders_loses_its_wrapper_and_the_scene_points_back(self) -> None:
        colliders.write(self.root)
        (self.root / "assets/environment/pack/gate.glb").write_bytes(PLAIN)
        found = "\n".join(colliders.problems(self.root))
        self.assertIn("levels/kit/pack/gate.tscn: left over, res://assets/environment/pack/gate.glb has no hint", found)
        colliders.write(self.root)
        self.assertEqual(list((self.root / "levels/kit/pack").iterdir()), [])
        self.assertIn('path="res://assets/environment/pack/gate.glb"', self.scene.read_text(encoding="utf-8"))
        imported = (self.root / "assets/environment/pack/gate.glb.import").read_text(encoding="utf-8")
        self.assertNotIn("skip_import", imported)
        self.assertEqual(colliders.problems(self.root), [])

    def test_without_lfs_content_check_still_guards_the_scenes(self) -> None:
        colliders.write(self.root)
        pointer = b"version https://git-lfs.github.com/spec/v1\noid sha256:00\nsize 1\n"
        (self.root / "assets/environment/pack/gate.glb").write_bytes(pointer)
        self.assertEqual(colliders.problems(self.root), [])
        self.assertEqual(colliders.plan(self.root).pointers, ["assets/environment/pack/gate.glb"])
        self.scene.write_bytes(SCENE.encode())
        self.assertEqual(len(colliders.problems(self.root)), 1)


if __name__ == "__main__":
    unittest.main()
