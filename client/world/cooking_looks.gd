class_name CookingLooks
extends RefCounted
## The looks of Cooking's 22 item kinds and its five icons (ARCHITECTURE §4.7.55, #776), after the
## cooking ADR's §5.1 drafts the engineer took: the buns told apart by colour and seeds, the patties
## by hue (raw, fried under a striped crust, one burnt), the herbs by silhouette, the boxes by what
## they give, the icons (a sun, a moon, a star, a drop, a heart) by shape alone, white on a disc of
## their own colour. Built in code from primitives as placeholders until the art track: the sizes
## and colours are looks, never game numbers. Keyed on the base mode's kind ids (C6, #775); any
## other kind (a fixture's) gets ItemView's labelled box. Every look's origin is its resting point,
## the bottom of its look. The outline of an ingredient on a plate is an inverted hull: a
## `material_overlay` grown outward with its front faces culled, depth-tested like the level, one
## neutral colour that says only that the slot is filled, never right or wrong (#1101: a burger is
## checked when it is served). The plated burger (#1101) is its three parts stacked as on the plate.

## The icons' count, in the order of OrderPosted's icon index.
const ICON_COUNT := 5
## The side of an icon's texture in pixels.
const ICON_PIXELS := 64
## How far an outline's hull grows past its item, in metres.
const OUTLINE_GROW_M := 0.012
## The filled slot's outline colour (#1101): neither the old right green nor the wrong red. A
## look, "not a decision".
const FILLED_COLOUR := Color(0.96, 0.92, 0.72)
## The top of a bun's dome above its bottom: its base is 0.4 and its dome 1.2 of BUN_SIZE.y. A part
## stacked on a bun sits this high, so the bun never hides it (#1101: the cook reads the burger's
## parts by eye).
const BUN_TOP_M := 0.112
## How tall a patty is (PATTY_SIZE.y): the herb sits this high above it.
const PATTY_TALL_M := 0.03
## The plated burger's kind id (the base mode's, #1101) and how high each part sits in it (bun,
## patty, herb, each on the one below; the plate's stack, CookingViews.STACK_M, from the bun's
## bottom).
const BURGER := &"burger"
const BURGER_STACK_M: Array[float] = [0.0, BUN_TOP_M, BUN_TOP_M + PATTY_TALL_M]
const BURGER_SIZE := Vector3(0.12, 0.35, 0.12)
## The parts a burger is drawn with before BurgerPlated names its own, or for a part with no look.
const BURGER_PARTS: Array[StringName] = [&"bun_white", &"patty_light", &"basil"]
const BUN_SIZE := Vector3(0.12, 0.07, 0.12)
const PATTY_SIZE := Vector3(0.11, 0.03, 0.11)
const HERB_SIZE := Vector3(0.1, 0.2, 0.1)
## The radius of a herb's stem and of its thin leaves (dill, rosemary, chives): thick enough to read
## on the herb board (CD13's code) at play distance. A look, "not a decision".
const HERB_STROKE_M := 0.009
const BOX_SIZE := Vector3(0.42, 0.26, 0.32)
## Each bun's top, base and dot (seeds, flour) colours.
const BUNS: Dictionary[StringName, Array] = {
	&"bun_white": [Color(0.93, 0.76, 0.46), Color(0.97, 0.91, 0.8), Color(0, 0, 0, 0)],
	&"bun_sesame": [Color(0.76, 0.5, 0.24), Color(0.95, 0.86, 0.7), Color(0.98, 0.95, 0.84)],
	&"bun_dark": [Color(0.3, 0.2, 0.13), Color(0.36, 0.25, 0.17), Color(0.86, 0.83, 0.77)],
}
## Each patty's colour: raw, fried (under its crust's stripes) and burnt.
const PATTIES: Dictionary[StringName, Color] = {
	&"patty_light_raw": Color(0.93, 0.74, 0.68),
	&"patty_red_raw": Color(0.86, 0.42, 0.42),
	&"patty_deep_red_raw": Color(0.66, 0.16, 0.2),
	&"patty_light": Color(0.66, 0.42, 0.2),
	&"patty_red": Color(0.55, 0.24, 0.16),
	&"patty_deep_red": Color(0.34, 0.12, 0.09),
	&"patty_burnt": Color(0.06, 0.05, 0.05),
}
const FRIED: Array[StringName] = [&"patty_light", &"patty_red", &"patty_deep_red"]
const STRIPE_COLOUR := Color(0.14, 0.07, 0.04)
const CRACK_COLOUR := Color(0.28, 0.24, 0.22)
## Each herb's leaf colour.
const HERBS: Dictionary[StringName, Color] = {
	&"basil": Color(0.24, 0.68, 0.2),
	&"dill": Color(0.62, 0.76, 0.25),
	&"rosemary": Color(0.15, 0.37, 0.2),
	&"chives": Color(0.3, 0.6, 0.24),
	&"mint": Color(0.56, 0.86, 0.5),
}
const STEM_COLOUR := Color(0.45, 0.33, 0.2)
const CHIVE_FLOWER := Color(0.66, 0.42, 0.82)
## Each box and the kind it gives.
const BOXES: Dictionary[StringName, StringName] = {
	&"box_bun_white": &"bun_white",
	&"box_bun_sesame": &"bun_sesame",
	&"box_bun_dark": &"bun_dark",
	&"box_patty_light": &"patty_light_raw",
	&"box_patty_red": &"patty_red_raw",
	&"box_patty_deep_red": &"patty_deep_red_raw",
}
const CRATE_COLOUR := Color(0.62, 0.45, 0.27)
const COOL_BOX_COLOUR := Color(0.95, 0.95, 0.93)
## Each icon's disc colour: the sun, the moon, the star, the drop, the heart.
const ICON_COLOURS: Array[Color] = [
	Color(0.95, 0.66, 0.1),
	Color(0.24, 0.3, 0.7),
	Color(0.55, 0.3, 0.75),
	Color(0.12, 0.58, 0.8),
	Color(0.86, 0.2, 0.3),
]

static var _icons: Array[Texture2D] = []
static var _outline: StandardMaterial3D


## Whether `kind` has a cooking look.
static func has(kind: StringName) -> bool:
	return (
		BUNS.has(kind) or PATTIES.has(kind) or HERBS.has(kind) or BOXES.has(kind) or kind == BURGER
	)


## The look's size in metres for a cooking kind; Vector3.ZERO for any other.
static func size_of(kind: StringName) -> Vector3:
	if BUNS.has(kind):
		return BUN_SIZE
	if PATTIES.has(kind):
		return PATTY_SIZE
	if HERBS.has(kind):
		return HERB_SIZE
	if BOXES.has(kind):
		return BOX_SIZE
	if kind == BURGER:
		return BURGER_SIZE
	return Vector3.ZERO


## A new look of cooking kind `kind`, its origin at the bottom; null for any other kind.
static func build(kind: StringName) -> Node3D:
	if BUNS.has(kind):
		return _bun(kind)
	if PATTIES.has(kind):
		return _patty(kind)
	if HERBS.has(kind):
		return _herb(kind)
	if BOXES.has(kind):
		return _box(kind)
	if kind == BURGER:
		return burger(PackedStringArray())
	return null


## A new look of a plated burger of `parts` (BurgerPlated's bun, patty and herb kind ids): each
## part's look stacked as on the plate, a part with no look (or none given) drawn as BURGER_PARTS'.
static func burger(parts: PackedStringArray) -> Node3D:
	var root := _root(BURGER)
	for slot in BURGER_PARTS.size():
		var part := StringName(parts[slot]) if slot < parts.size() else &""
		var look := build(part) if has(part) and part != BURGER else null
		if look == null:
			look = build(BURGER_PARTS[slot])
		look.position = Vector3.UP * BURGER_STACK_M[slot]
		root.add_child(look)
	return root


## Icon `index`'s texture (0 the sun to 4 the heart), made once; null out of range.
static func icon(index: int) -> Texture2D:
	if index < 0 or index >= ICON_COUNT:
		return null
	if _icons.is_empty():
		for i in ICON_COUNT:
			_icons.append(_icon_texture(i))
	return _icons[index]


## The filled slot's outline material (#1101), the same for every ingredient on a plate: an
## inverted hull, unshaded, depth-tested, at the level's render priority.
static func outline() -> StandardMaterial3D:
	if _outline == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_FRONT
		material.grow = true
		material.grow_amount = OUTLINE_GROW_M
		material.albedo_color = FILLED_COLOUR
		_outline = material
	return _outline


## Sets `material` (null clears it) as the overlay of every mesh under `look`.
static func set_outline(look: Node, material: Material) -> void:
	for child: Node in look.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).material_overlay = material


static func _bun(kind: StringName) -> Node3D:
	var colours: Array = BUNS[kind]
	var root := _root(kind)
	var r := BUN_SIZE.x * 0.5
	_add(root, "Base", _cylinder(r, BUN_SIZE.y * 0.4), colours[1] as Color, Vector3.UP * 0.014)
	var top := SphereMesh.new()
	top.radius = r
	top.height = BUN_SIZE.y * 1.2
	top.is_hemisphere = true
	_add(root, "Top", top, colours[0] as Color, Vector3.UP * BUN_SIZE.y * 0.4)
	var dots := colours[2] as Color
	if dots.a > 0.0:
		for i in 7:
			var angle := TAU * i / 7.0
			var at := Vector3(cos(angle) * r * 0.55, BUN_SIZE.y * 0.88, sin(angle) * r * 0.55)
			var seed_mesh := SphereMesh.new()
			seed_mesh.radius = 0.006
			seed_mesh.height = 0.008
			_add(root, "Dot%d" % i, seed_mesh, dots, at)
	return root


static func _patty(kind: StringName) -> Node3D:
	var root := _root(kind)
	var mesh := _cylinder(PATTY_SIZE.x * 0.5, PATTY_SIZE.y)
	_add(root, "Patty", mesh, PATTIES[kind], Vector3.UP * PATTY_SIZE.y * 0.5)
	var marked := FRIED.has(kind) or kind == &"patty_burnt"
	if marked:
		var colour := STRIPE_COLOUR if FRIED.has(kind) else CRACK_COLOUR
		for i in 3:
			var stripe := BoxMesh.new()
			stripe.size = Vector3(PATTY_SIZE.x * 0.8, 0.002, 0.008)
			var z := (i - 1) * PATTY_SIZE.z * 0.25
			var mark := _add(root, "Mark%d" % i, stripe, colour, Vector3(0, PATTY_SIZE.y, z))
			if kind == &"patty_burnt":
				mark.rotation.y = 0.5 * (i - 1) + 0.3
	return root


static func _herb(kind: StringName) -> Node3D:
	var root := _root(kind)
	var leaf_colour: Color = HERBS[kind]
	var stem_colour := STEM_COLOUR if kind == &"rosemary" else leaf_colour.darkened(0.3)
	var stem_high := HERB_SIZE.y * (0.8 if kind == &"rosemary" else 0.5)
	_add(
		root, "Stem", _cylinder(HERB_STROKE_M, stem_high), stem_colour, Vector3.UP * stem_high * 0.5
	)
	for i in 5:
		var angle := TAU * i / 5.0
		var out := Vector3(cos(angle), 0, sin(angle))
		var leaf: Mesh
		var at := Vector3.UP * HERB_SIZE.y * 0.55 + out * 0.025
		match kind:
			&"basil":
				leaf = _sphere(0.028, 0.012)
			&"mint":
				leaf = _sphere(0.022, 0.014)
			&"dill":
				leaf = _cylinder(HERB_STROKE_M, HERB_SIZE.y * 0.6)
				at = Vector3.UP * HERB_SIZE.y * 0.6 + out * 0.02
			&"rosemary":
				leaf = BoxMesh.new()
				(leaf as BoxMesh).size = Vector3(HERB_STROKE_M * 2.0, HERB_STROKE_M * 2.0, 0.05)
				at = Vector3.UP * HERB_SIZE.y * (0.3 + 0.1 * i)
			_:
				leaf = _cylinder(HERB_STROKE_M, HERB_SIZE.y * 0.9)
				at = Vector3.UP * HERB_SIZE.y * 0.45 + out * 0.012
		var part := _add(root, "Leaf%d" % i, leaf, leaf_colour, at)
		part.rotation.y = angle
		if kind == &"dill":
			part.rotation.z = 0.35
	if kind == &"chives":
		_add(root, "Flower", _sphere(0.016, 0.02), CHIVE_FLOWER, Vector3.UP * HERB_SIZE.y * 0.92)
	return root


static func _box(kind: StringName) -> Node3D:
	var root := _root(kind)
	var gives: StringName = BOXES[kind]
	var is_bun_box := BUNS.has(gives)
	var body := BoxMesh.new()
	body.size = Vector3(BOX_SIZE.x, BOX_SIZE.y * (0.8 if is_bun_box else 0.86), BOX_SIZE.z)
	var body_colour := CRATE_COLOUR if is_bun_box else COOL_BOX_COLOUR
	_add(root, "Body", body, body_colour, Vector3.UP * body.size.y * 0.5)
	var front := Vector3(0, BOX_SIZE.y * 0.42, BOX_SIZE.z * 0.5 + 0.004)
	if is_bun_box:
		for i in 3:
			var bun := _bun(gives)
			bun.name = "Bun%d" % i
			bun.position = Vector3((i - 1) * BUN_SIZE.x * 1.1, body.size.y, 0)
			root.add_child(bun)
		var top_colour := (BUNS[gives] as Array)[0] as Color
		_front_picture(root, top_colour, front)
		return root
	var lid := BoxMesh.new()
	lid.size = Vector3(BOX_SIZE.x * 1.02, BOX_SIZE.y * 0.14, BOX_SIZE.z * 1.02)
	_add(root, "Lid", lid, PATTIES[gives], Vector3.UP * (body.size.y + lid.size.y * 0.5))
	_front_picture(root, PATTIES[gives], front)
	return root


## The picture on a box's front: a disc of what it gives, facing out.
static func _front_picture(root: Node3D, colour: Color, at: Vector3) -> void:
	var picture := _add(root, "Picture", _cylinder(0.07, 0.004), colour, at)
	picture.rotation.x = PI * 0.5


static func _root(kind: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = String(kind).to_pascal_case()
	return root


static func _add(root: Node3D, part: String, mesh: Mesh, colour: Color, at: Vector3) -> Node3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	var instance := MeshInstance3D.new()
	instance.name = part
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	root.add_child(instance)
	return instance


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
	return mesh


static func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


static func _icon_texture(index: int) -> Texture2D:
	var image := Image.create_empty(ICON_PIXELS, ICON_PIXELS, false, Image.FORMAT_RGBA8)
	var star := PackedVector2Array()
	for i in 10:
		var angle := PI * 0.5 + TAU * i / 10.0
		var radius := 0.62 if i % 2 == 0 else 0.26
		star.append(Vector2(cos(angle), sin(angle)) * radius)
	var drop_tip := PackedVector2Array(
		[Vector2(0, 0.66), Vector2(-0.34, -0.06), Vector2(0.34, -0.06)]
	)
	for y in ICON_PIXELS:
		for x in ICON_PIXELS:
			var p := Vector2(x + 0.5, ICON_PIXELS - y - 0.5) / ICON_PIXELS * 2.0 - Vector2.ONE
			var colour := Color(0, 0, 0, 0)
			if p.length() <= 0.95:
				colour = ICON_COLOURS[index]
				if _in_shape(index, p, star, drop_tip):
					colour = Color.WHITE
			image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)


## Whether the point `p` (-1 to 1, y up) lies in icon `index`'s white silhouette.
static func _in_shape(
	index: int, p: Vector2, star: PackedVector2Array, drop_tip: PackedVector2Array
) -> bool:
	match index:
		0:
			var ray := fposmod(atan2(p.y, p.x), TAU / 8.0)
			var on_ray := ray < 0.2 or ray > TAU / 8.0 - 0.2
			return p.length() < 0.3 or (on_ray and p.length() > 0.38 and p.length() < 0.66)
		1:
			return p.length() < 0.55 and p.distance_to(Vector2(0.24, 0.14)) > 0.45
		2:
			return Geometry2D.is_point_in_polygon(p, star)
		3:
			var in_bulb := p.distance_to(Vector2(0, -0.18)) < 0.36
			return in_bulb or Geometry2D.is_point_in_polygon(p, drop_tip)
		_:
			var h := (p + Vector2(0, 0.08)) / 0.6
			return pow(h.x * h.x + h.y * h.y - 1.0, 3.0) - h.x * h.x * pow(h.y, 3.0) <= 0.0
