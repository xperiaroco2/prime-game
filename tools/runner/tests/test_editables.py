"""editables (#1056): an override inside an instance needs its instance's [editable path] entry, or a re-save drops it;
`check` names the scenes that lack one, `colliders` adds them."""

import tempfile
import unittest
from pathlib import Path

from runner import editables

ROOM = """[gd_scene format=3]

[ext_resource type="PackedScene" path="res://levels/kit/house_kit/wall.tscn" id="1"]

[node name="Room" type="Node3D" unique_id=1]

[node name="Label" type="Label3D" parent="."]
text = "Room"

[node name="Shell" type="Node3D" parent="."]

[node name="wall_1" parent="Shell" instance=ExtResource("1")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2, 0, 0)

[node name="wall" parent="Shell/wall_1" index="0"]
surface_material_override/0 = ExtResource("2")

[node name="wall_col0" parent="Shell/wall_1/wall"]
collision_layer = 0

[node name="wall_2" parent="Shell" instance=ExtResource("1")]

[node name="wall_3" parent="Shell" instance=ExtResource("1")]

[node name="wall" parent="Shell/wall_3"]
surface_material_override/0 = ExtResource("2")
"""


class MissingTest(unittest.TestCase):
    def test_each_instance_with_an_override_is_named_once_in_file_order(self) -> None:
        self.assertEqual(editables.missing(ROOM), ["Shell/wall_1", "Shell/wall_3"])

    def test_an_entry_keeps_its_instance(self) -> None:
        text = ROOM + '\n[editable path="Shell/wall_3"]\n'
        self.assertEqual(editables.missing(text), ["Shell/wall_1"])

    def test_an_instance_without_overrides_and_own_nodes_need_none(self) -> None:
        self.assertNotIn("Shell/wall_2", editables.missing(ROOM))
        self.assertNotIn("Shell", editables.missing(ROOM))

    def test_an_inherited_root_needs_no_entry(self) -> None:
        text = (
            '[gd_scene format=3]\n\n[node name="Wrapper" instance=ExtResource("1")]\n\n'
            '[node name="mesh" parent="."]\nvisible = false\n'
        )
        self.assertEqual(editables.missing(text), [])


class AddTest(unittest.TestCase):
    def test_entries_follow_the_last_section_as_godot_writes_them(self) -> None:
        added = editables.add(ROOM)
        tail = 'ExtResource("2")\n\n[editable path="Shell/wall_1"]\n[editable path="Shell/wall_3"]\n'
        self.assertTrue(added.endswith(tail))
        self.assertEqual(editables.missing(added), [])
        self.assertEqual(editables.add(added), added)

    def test_new_entries_join_the_existing_ones(self) -> None:
        text = ROOM + '\n[editable path="Shell/wall_3"]\n'
        tail = '\n\n[editable path="Shell/wall_3"]\n[editable path="Shell/wall_1"]\n'
        self.assertTrue(editables.add(text).endswith(tail))


class SceneTest(unittest.TestCase):
    def test_problems_name_the_scene_and_write_fixes_it_outside_the_kit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            room = root / "levels/house/rooms/room.tscn"
            wrapper = root / "levels/kit/house_kit/wall.tscn"
            for path in (room, wrapper):
                path.parent.mkdir(parents=True)
                path.write_text(ROOM, encoding="utf-8")
            found = editables.problems(root)
            self.assertEqual(len(found), 1)
            self.assertIn("levels/house/rooms/room.tscn: an override inside Shell/wall_1, Shell/wall_3 ", found[0])
            self.assertEqual(editables.write(root), ["levels/house/rooms/room.tscn"])
            self.assertEqual(editables.problems(root), [])
            self.assertEqual(wrapper.read_text(encoding="utf-8"), ROOM)
            self.assertEqual(editables.write(root), [])


if __name__ == "__main__":
    unittest.main()
