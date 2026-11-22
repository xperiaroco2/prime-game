class_name ItemView
extends Node3D
## One item as the client draws it (ARCHITECTURE §4.7, M4-8; the M4 ADR's D7 (a)): a greybox look
## chosen by the item kind's id, with a labelled box for a kind the client has no look for, so a
## new item kind still shows up (Delivery by meaning's kinds until the art, DE11 and #830: a box
## labelled with the kind's name). Placeholders until the art pass: the sizes and colours here are
## looks, never game numbers. The origin is the item's resting point, the bottom of its look.
##
## ItemViews places it and shows or hides its look (`show_look`); LifeView then hides the looks of
## a spectated living target's hand and belt items, seen from its eyes (#168); the root's own
## `visible` is left to whatever hides views out of sight (the downed camera's sight hiding,
## M4-9), which reads `sight_point()`. A label over an unknown kind is drawn in the world and
## hidden by the level like the item (no `no_depth_test`, the M4 ADR's §3 item 5).

## The look's sizes in metres, by kind id; Cooking's kinds take CookingLooks' (#776); any other
## kind gets UNKNOWN_SIZE and its name as a label. The photo task's film and photo take
## PhotoLooks' (#787), the booth's strip StripLooks' (#1397), the bar's mugs MugLooks' (#1678).
const SIZES: Dictionary[StringName, Vector3] = {
	&"knife": Vector3(0.05, 0.04, 0.32),
	&"package": Vector3(0.45, 0.45, 0.45),
}
const UNKNOWN_SIZE := Vector3(0.3, 0.3, 0.3)
## The energy crystal's kinds and their charge (#1672): drawn as the crystal's own model
## (ShipCrystalLook, #1556), charged lit and spent grey, its bottom on the resting point as the
## model's origin is; without the model (CI's Git LFS stand-in) the labelled box.
const CRYSTAL_CHARGE: Dictionary[StringName, float] = {
	&"crystal_charged": 1.0,
	&"crystal_spent": 0.0,
}
## The crystal model's bounds (energy_crystal.glb: 0.136 m wide, 0.349 m from its origin up).
const CRYSTAL_SIZE := Vector3(0.14, 0.35, 0.14)
const KNIFE_COLOUR := Color(0.7, 0.72, 0.75)
const UNKNOWN_COLOUR := Color(0.85, 0.3, 0.85)
## How far above the box an unknown kind's label floats, in metres.
const LABEL_ABOVE := 0.15

var item_id := -1
var kind: StringName
## A plated burger's part kind ids (ClientModel.Item.parts, #1101); empty for any other item.
var parts := PackedStringArray()

var _look: Node3D
var _layer := PhotoLayers.GROUND
var _crystal: ShipCrystalLook


## A view of item `id` of `kind`; `colour` is a package's circle colour (white for other items),
## which only the `package` look takes: a labelled box is never tinted by it (DE11 of the
## delivery-by-meaning ADR). The label is the kind's name through ContentNames: its deck key's
## text, else `game_mode`'s display name for it, else its id. `burger_parts`: a plated burger's
## parts (#1101), drawn by CookingLooks.burger.
static func make(
	id: int,
	item_kind: StringName,
	colour: Color,
	game_mode: GameMode = null,
	burger_parts := PackedStringArray()
) -> ItemView:
	var view := ItemView.new()
	view.name = "Item%d" % id
	view.item_id = id
	view.kind = item_kind
	view.parts = burger_parts
	view._build(colour, ContentNames.text(ContentNames.item(item_kind, game_mode)))
	return view


## The look's size in metres for `item_kind`.
static func size_of(item_kind: StringName) -> Vector3:
	if StripLooks.has(item_kind):
		return StripLooks.size_of(item_kind)
	if PhotoLooks.has(item_kind):
		return PhotoLooks.size_of(item_kind)
	if MugLooks.has(item_kind):
		return MugLooks.size_of(item_kind)
	if CookingLooks.has(item_kind):
		return CookingLooks.size_of(item_kind)
	if CRYSTAL_CHARGE.has(item_kind):
		return CRYSTAL_SIZE
	return SIZES.get(item_kind, UNKNOWN_SIZE)


## The middle of the look above the resting point `at`: where the crosshair aims at it.
static func centre_of(item_kind: StringName, at: Vector3) -> Vector3:
	return at + Vector3.UP * size_of(item_kind).y * 0.5


## Where the sight hiding looks at it (M4-9's SightHider).
func sight_point() -> Vector3:
	return centre_of(kind, global_position)


## Shows or hides the look (held by the own player, or by a player with no body drawn, or by a
## spectated target seen from its eyes, #168).
func show_look(on: bool) -> void:
	_look.visible = on


func is_look_shown() -> bool:
	return _look.visible


## The look's materials and labels, for the tests (no `no_depth_test` anywhere).
func look() -> Node3D:
	return _look


func _build(colour: Color, label_text: String) -> void:
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	if StripLooks.has(kind):
		_look.add_child(StripLooks.build(kind))
		return
	if PhotoLooks.has(kind):
		_look.add_child(PhotoLooks.build(kind))
		return
	if MugLooks.has(kind):
		_look.add_child(MugLooks.build(kind))
		return
	if not parts.is_empty():
		_look.add_child(CookingLooks.burger(parts))
		return
	if CookingLooks.has(kind):
		_look.add_child(CookingLooks.build(kind))
		return
	if CRYSTAL_CHARGE.has(kind) and _build_crystal():
		return
	var size := size_of(kind)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	match kind:
		&"knife":
			material.albedo_color = KNIFE_COLOUR
			material.metallic = 0.6
		&"package":
			material.albedo_color = colour
		_:
			material.albedo_color = UNKNOWN_COLOUR
	mesh.material = material
	var box := MeshInstance3D.new()
	box.name = "Box"
	box.mesh = mesh
	box.position = Vector3.UP * size.y * 0.5
	_look.add_child(box)
	if not SIZES.has(kind):
		var label := Label3D.new()
		label.name = "Label"
		label.text = label_text
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3.UP * (size.y + LABEL_ABOVE)
		_look.add_child(label)


## The crystal's model in the look, at its charge; false without the model (CI's Git LFS
## stand-in), so the labelled box stands in. Its own light keeps the seated crystal's rules: it
## skips the stations' meshes (ShipCrystalLook.seat) and the first-person hands (#1587), so a
## crystal near either never burns them white. Unlike a seated crystal's (its station is public)
## it casts shadows, as the photo flash does (P6): a light without them passes through walls, and
## its glow would show a carrier or a crystal the wall hides. Its own meshes cast none (the light
## sits in the shell), and no baked or global light takes it past its cull mask.
func _build_crystal() -> bool:
	var crystal := ShipCrystalLook.apply()
	if crystal == null:
		return false
	_crystal = crystal
	crystal.set_charge(CRYSTAL_CHARGE[kind])
	var omni := crystal.omni()
	omni.light_cull_mask = omni.light_cull_mask & ~(PhotoLayers.STATION | PhotoLayers.HANDS)
	omni.shadow_enabled = true
	omni.light_bake_mode = Light3D.BAKE_DISABLED
	for node: Node in crystal.node().find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_look.add_child(crystal.node())
	return true


## The crystal's look when this view draws a crystal with its model, else null.
func crystal() -> ShipCrystalLook:
	return _crystal


## Puts the look on visual layer `value` (PhotoLayers: GROUND lying or in flight, LIVE_AVATAR
## carried by a player, so a shot's picture draws the record's puppet holding it instead;
## #787). Walks the look only when the layer changes.
func set_layer(value: int) -> void:
	if value == _layer:
		return
	_layer = value
	PhotoLayers.assign(self, value)


func layer() -> int:
	return _layer


## Shows `texture`, a shot's picture, on a photo's look (#787); null shows the grey blank. Nothing
## for any other kind.
func set_picture(texture: Texture2D) -> void:
	PhotoLooks.set_picture(_look, texture)


## The texture a photo's look shows, or null.
func picture() -> Texture2D:
	var mesh := PhotoLooks.picture_of(_look)
	return (mesh.material_override as StandardMaterial3D).albedo_texture if mesh != null else null
