extends GdUnitTestSuite
## Cooking's looks (ARCHITECTURE §4.7.55, #776; the cooking ADR's §5.1): the 21 kinds of the base
## mode (C6's ids) each get a look of their own through ItemView, with no label and nothing drawn
## over the level; the five icons are distinct white silhouettes on discs; the plate's outline is an
## inverted hull, depth-tested at the level's render priority.

const KINDS: Array[StringName] = [
	&"bun_white",
	&"bun_sesame",
	&"bun_dark",
	&"patty_light_raw",
	&"patty_red_raw",
	&"patty_deep_red_raw",
	&"patty_light",
	&"patty_red",
	&"patty_deep_red",
	&"patty_burnt",
	&"basil",
	&"dill",
	&"rosemary",
	&"chives",
	&"mint",
	&"box_bun_white",
	&"box_bun_sesame",
	&"box_bun_dark",
	&"box_patty_light",
	&"box_patty_red",
	&"box_patty_deep_red",
]
const MODE := "res://content/modes/base_mode.tres"


func test_every_cooking_kind_gets_its_own_look_through_item_view() -> void:
	for kind: StringName in KINDS:
		assert_bool(CookingLooks.has(kind)).override_failure_message(String(kind)).is_true()
		var size := ItemView.size_of(kind)
		assert_bool(size.x > 0.0 and size.y > 0.0 and size.z > 0.0).is_true()
		var view: ItemView = auto_free(ItemView.make(1, kind, Color.WHITE))
		assert_object(view.look().find_child("Label", true, false)).is_null()
		var meshes := view.look().find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).override_failure_message(String(kind)).is_greater(0)
		for node: Node in meshes:
			var material := (node as MeshInstance3D).material_override as BaseMaterial3D
			assert_bool(material.no_depth_test).is_false()
			assert_int(material.render_priority).is_equal(0)


func test_a_fixture_kind_keeps_the_labelled_box() -> void:
	assert_bool(CookingLooks.has(&"bun_a")).is_false()
	assert_bool(ItemView.size_of(&"bun_a").is_equal_approx(ItemView.UNKNOWN_SIZE)).is_true()
	var view: ItemView = auto_free(ItemView.make(1, &"bun_a", Color.WHITE))
	assert_object(view.look().find_child("Label", true, false)).is_not_null()
	assert_object(CookingLooks.build(&"bun_a")).is_null()


func test_the_looks_tell_the_buns_and_the_patties_apart() -> void:
	var colours: Array[Color] = []
	for kind: StringName in CookingLooks.PATTIES:
		assert_bool(colours.has(CookingLooks.PATTIES[kind])).is_false()
		colours.append(CookingLooks.PATTIES[kind])
	var sesame := CookingLooks.build(&"bun_sesame")
	var white := CookingLooks.build(&"bun_white")
	assert_object(sesame.find_child("Dot0", true, false)).is_not_null()
	assert_object(white.find_child("Dot0", true, false)).is_null()
	var fried := CookingLooks.build(&"patty_red")
	var raw := CookingLooks.build(&"patty_red_raw")
	assert_object(fried.find_child("Mark0", true, false)).is_not_null()
	assert_object(raw.find_child("Mark0", true, false)).is_null()
	for node: Node3D in [sesame, white, fried, raw]:
		node.free()


func test_the_five_icons_are_white_silhouettes_on_discs_of_their_own() -> void:
	var images: Array[Image] = []
	for i in CookingLooks.ICON_COUNT:
		var texture := CookingLooks.icon(i)
		assert_object(texture).is_not_null()
		assert_object(CookingLooks.icon(i)).is_same(texture)
		var image := texture.get_image()
		assert_int(image.get_width()).is_equal(CookingLooks.ICON_PIXELS)
		assert_float(image.get_pixel(0, 0).a).is_equal(0.0)
		assert_bool(_counts(image, Color.WHITE) > 100).is_true()
		assert_bool(_counts(image, CookingLooks.ICON_COLOURS[i]) > 100).is_true()
		for other: Image in images:
			assert_bool(other.get_data() == image.get_data()).is_false()
		images.append(image)
	assert_object(CookingLooks.icon(-1)).is_null()
	assert_object(CookingLooks.icon(CookingLooks.ICON_COUNT)).is_null()


func test_the_outline_is_a_depth_tested_inverted_hull() -> void:
	for right: bool in [true, false]:
		var material := CookingLooks.outline(right)
		assert_bool(material.grow).is_true()
		assert_float(material.grow_amount).is_greater(0.0)
		assert_float(material.grow_amount).is_less(0.05)
		assert_int(material.cull_mode).is_equal(BaseMaterial3D.CULL_FRONT)
		assert_int(material.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
		assert_bool(material.no_depth_test).is_false()
		assert_int(material.render_priority).is_equal(0)
	assert_bool(CookingLooks.outline(true).albedo_color.g > 0.5).is_true()
	assert_bool(CookingLooks.outline(false).albedo_color.r > 0.5).is_true()
	var look := CookingLooks.build(&"bun_dark")
	CookingLooks.set_outline(look, CookingLooks.outline(false))
	for node: Node in look.find_children("*", "GeometryInstance3D", true, false):
		assert_object((node as GeometryInstance3D).material_overlay).is_same(
			CookingLooks.outline(false)
		)
	CookingLooks.set_outline(look, null)
	for node: Node in look.find_children("*", "GeometryInstance3D", true, false):
		assert_object((node as GeometryInstance3D).material_overlay).is_null()
	look.free()


## Every item kind of a Cooking in the base mode has a look (vacuous until C6, #775, lands).
func test_every_kind_of_the_base_modes_cooking_has_a_look() -> void:
	for type: Cooking in CookingUse.types_of(load(MODE) as GameMode):
		var kinds: Array[ItemKind] = []
		kinds.append_array(type.buns)
		kinds.append_array(type.raw_patties)
		kinds.append_array(type.fried_patties)
		kinds.append_array(type.herbs)
		kinds.append_array(type.boxes)
		kinds.append(type.burnt)
		for kind: ItemKind in kinds:
			(
				assert_bool(CookingLooks.has(kind.id))
				. override_failure_message(String(kind.id))
				. is_true()
			)


## The pixels of `image` that are `colour`, opaque, within its 8-bit rounding.
func _counts(image: Image, colour: Color) -> int:
	var found := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var off := absf(c.r - colour.r) + absf(c.g - colour.g) + absf(c.b - colour.b)
			if c.a > 0.99 and off < 0.02:
				found += 1
	return found
