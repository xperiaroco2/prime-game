class_name StripLooks
extends RefCounted
## The booth strip's look (#1397, ARCHITECTURE §4.7.62): a thin paper card whose +Y face holds the
## picture slot, named as the photo's (PhotoLooks.PICTURE), so ItemView.set_picture and
## FirstPersonHand.set_picture show the strip's image (StripPictures) unchanged. Frame 0 sits at
## the card's -Z end. Sizes, colour and the close-up's scale are placeholders in the Toy style,
## "not a decision". The kind id is the base mode's StartBooth strip (BoothUse; a test pins it).

const STRIP := &"strip"
## The card: as wide and long as StripLayout's image at 4 frames is. Placeholder.
const SIZE := Vector3(0.065, 0.004, 0.2)
## The picture covers the card's top face, a hair inside it.
const PICTURE_SIZE := Vector2(0.063, 0.197)
## Held up close (FirstPersonHand.set_close) this many times larger: the strip is long, so less
## than the photo's 2.2. Placeholder.
const CLOSE_SCALE := 1.5


static func has(kind: StringName) -> bool:
	return kind == STRIP


static func size_of(_kind: StringName) -> Vector3:
	return SIZE


static func build(_kind: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Strip"
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	var paper := StandardMaterial3D.new()
	paper.albedo_color = StripLayout.PAPER
	mesh.material = paper
	var card := MeshInstance3D.new()
	card.name = "Card"
	card.mesh = mesh
	card.position = Vector3.UP * SIZE.y * 0.5
	root.add_child(card)
	var quad := QuadMesh.new()
	quad.size = PICTURE_SIZE
	# A QuadMesh faces +Z: turned to face up, its top edge (frame 0) towards -Z.
	quad.orientation = PlaneMesh.FACE_Y
	var material := StandardMaterial3D.new()
	material.albedo_color = PhotoLooks.BLANK_COLOUR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var picture := MeshInstance3D.new()
	picture.name = PhotoLooks.PICTURE
	picture.mesh = quad
	picture.material_override = material
	picture.position = Vector3.UP * (SIZE.y + 0.0005)
	root.add_child(picture)
	return root
