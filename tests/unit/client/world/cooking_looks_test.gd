extends GdUnitTestSuite
## Cooking's looks (ARCHITECTURE §4.7.55, #776; the cooking ADR's §5.1): the 22 kinds of the base
## mode (C6's ids, the burger of #1101) each get a look of their own through ItemView, with no label
## and nothing drawn over the level; a plated burger shows its parts; the five icons are distinct
## white silhouettes on discs; the plate's outline is one neutral filled-slot colour (#1101), an
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
	&"burger",
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
	var material := CookingLooks.outline()
	assert_bool(material.grow).is_true()
	assert_float(material.grow_amount).is_greater(0.0)
	assert_float(material.grow_amount).is_less(0.05)
	assert_int(material.cull_mode).is_equal(BaseMaterial3D.CULL_FRONT)
	assert_int(material.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_bool(material.no_depth_test).is_false()
	assert_int(material.render_priority).is_equal(0)
	assert_object(CookingLooks.outline()).is_same(material)
	var look := CookingLooks.build(&"bun_dark")
	CookingLooks.set_outline(look, material)
	for node: Node in look.find_children("*", "GeometryInstance3D", true, false):
		assert_object((node as GeometryInstance3D).material_overlay).is_same(material)
	CookingLooks.set_outline(look, null)
	for node: Node in look.find_children("*", "GeometryInstance3D", true, false):
		assert_object((node as GeometryInstance3D).material_overlay).is_null()
	look.free()


func test_the_filled_outline_is_neither_the_old_green_nor_red() -> void:
	# #1101: the outline says only that a slot is filled. The old right green had g > 0.5 with low
	# red, the wrong red r > 0.5 with low green; the filled colour is pale, all channels high.
	var colour := CookingLooks.outline().albedo_color
	assert_float(minf(colour.r, minf(colour.g, colour.b))).is_greater(0.5)


func test_a_plated_burger_shows_its_parts_stacked() -> void:
	var parts := PackedStringArray(["bun_dark", "patty_red", "mint"])
	var view: ItemView = auto_free(ItemView.make(1, &"burger", Color.WHITE, null, parts))
	var burger := view.look().get_child(0)
	var names: Array[String] = []
	var heights: Array[float] = []
	for child: Node in burger.get_children():
		names.append(String(child.name))
		heights.append((child as Node3D).position.y)
	assert_array(names).contains_exactly(["BunDark", "PattyRed", "Mint"])
	assert_bool(heights[0] < heights[1] and heights[1] < heights[2]).is_true()
	# A part with no look (a fixture's kind) or none given is drawn as BURGER_PARTS'.
	var plain := CookingLooks.burger(PackedStringArray(["bun_a"]))
	assert_str(String(plain.get_child(0).name)).is_equal("BunWhite")
	assert_str(String(plain.get_child(2).name)).is_equal("Basil")
	plain.free()


## The bun never hides the patty (#1101: the cook reads a burger's parts by eye): in a plated
## burger and on a plate, the patty sits on top of every bun's dome and the herb on the patty.
func test_no_bun_hides_the_patty_on_a_burger_or_a_plate() -> void:
	for bun: StringName in CookingLooks.BUNS:
		var look := CookingLooks.build(bun)
		var top := _top_of(look)
		look.free()
		assert_float(top).is_less_equal(CookingLooks.BUN_TOP_M + 0.001)
	var patty := CookingLooks.build(&"patty_red")
	var patty_top := _top_of(patty)
	patty.free()
	assert_float(patty_top).is_less_equal(CookingLooks.PATTY_TALL_M + 0.001)
	var stack := CookingLooks.BURGER_STACK_M
	assert_float(stack[1] - stack[0]).is_greater_equal(CookingLooks.BUN_TOP_M)
	assert_float(stack[2] - stack[1]).is_greater_equal(CookingLooks.PATTY_TALL_M)
	var plate := CookingViews.STACK_M
	assert_float(plate[1] - plate[0]).is_greater_equal(CookingLooks.BUN_TOP_M)
	assert_float(plate[2] - plate[1]).is_greater_equal(CookingLooks.PATTY_TALL_M)


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
		kinds.append(type.burger)
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


## The highest point of any mesh under `look`, in `look`'s own space (the looks are built in
## code, so each child's transform is its local one, not yet in a tree).
func _top_of(look: Node3D) -> float:
	var top := -INF
	for child: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var to_look := Transform3D.IDENTITY
		var node: Node = mesh
		while node != look:
			to_look = (node as Node3D).transform * to_look
			node = node.get_parent()
		var box := to_look * mesh.get_aabb()
		top = maxf(top, box.end.y)
	return top
