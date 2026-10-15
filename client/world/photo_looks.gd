class_name PhotoLooks
extends RefCounted
## The greybox looks of the photo task's items (#787, photo P8; ARCHITECTURE §4.7), as
## CookingLooks is Cooking's: ItemView asks it first for the base mode's `film` and `photo` kinds.
## The film is a small dark canister with a light label band; the photo a thin white card lying
## flat with its picture on the top face (`Picture`, its texture set through ItemView.set_picture:
## a grey card until the shot's picture is there). Every material is depth-tested (the M4 ADR's §3
## items 1, 3 and 5: no `no_depth_test`, nothing seen through a wall). Sizes and colours are looks,
## placeholders until the art pass, "not a decision".

const FILM := &"film"
const PHOTO := &"photo"
const FILM_SIZE := Vector3(0.05, 0.07, 0.05)
## The card: as wide and deep as the picture's 4:3 plus a border, a few millimetres thick.
const PHOTO_SIZE := Vector3(0.16, 0.006, 0.12)
## The picture on the card, 4:3 (the base mode's photo aspect), inside a 1 cm white border.
const PICTURE_SIZE := Vector2(0.14, 0.105)
const FILM_COLOUR := Color(0.12, 0.12, 0.14)
const BAND_COLOUR := Color(0.95, 0.75, 0.2)
const CARD_COLOUR := Color(0.96, 0.96, 0.94)
## The picture's colour while it has no texture (headless, or not rendered yet).
const BLANK_COLOUR := Color(0.55, 0.55, 0.58)
## The picture's node, under the card.
const PICTURE := &"Picture"


static func has(kind: StringName) -> bool:
	return kind == FILM or kind == PHOTO


static func size_of(kind: StringName) -> Vector3:
	return PHOTO_SIZE if kind == PHOTO else FILM_SIZE


## A new look of `kind` (has(kind) is true), its origin the resting point at the bottom.
static func build(kind: StringName) -> Node3D:
	return _photo() if kind == PHOTO else _film()


## The picture of a photo look `look` (built by build(PHOTO), or a node above it), or null.
static func picture_of(look: Node) -> MeshInstance3D:
	if look == null:
		return null
	return look.find_child(PICTURE, true, false) as MeshInstance3D


## Shows `texture` on photo look `look`'s picture; null shows the grey blank.
static func set_picture(look: Node, texture: Texture2D) -> void:
	var picture := picture_of(look)
	if picture == null:
		return
	var material := picture.material_override as StandardMaterial3D
	if material.albedo_texture == texture:
		return
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE if texture != null else BLANK_COLOUR


static func _film() -> Node3D:
	var root := Node3D.new()
	root.name = "Film"
	root.add_child(_box("Canister", FILM_SIZE, FILM_COLOUR, FILM_SIZE.y * 0.5))
	var band := FILM_SIZE * Vector3(1.04, 0.35, 1.04)
	root.add_child(_box("Band", band, BAND_COLOUR, FILM_SIZE.y * 0.5))
	return root


static func _photo() -> Node3D:
	var root := Node3D.new()
	root.name = "Photo"
	root.add_child(_box("Card", PHOTO_SIZE, CARD_COLOUR, PHOTO_SIZE.y * 0.5))
	var quad := QuadMesh.new()
	quad.size = PICTURE_SIZE
	# A QuadMesh faces +Z: turned to face up, its top edge towards -Z (away from the viewer).
	quad.orientation = PlaneMesh.FACE_Y
	var material := StandardMaterial3D.new()
	material.albedo_color = BLANK_COLOUR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var picture := MeshInstance3D.new()
	picture.name = PICTURE
	picture.mesh = quad
	picture.material_override = material
	picture.position = Vector3.UP * (PHOTO_SIZE.y + 0.0005)
	root.add_child(picture)
	return root


static func _box(
	node_name: String, size: Vector3, colour: Color, centre_y: float
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	var box := MeshInstance3D.new()
	box.name = node_name
	box.mesh = mesh
	box.position = Vector3.UP * centre_y
	return box
