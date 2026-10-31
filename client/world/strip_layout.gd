class_name StripLayout
extends RefCounted
## The booth strip's layout (#1397, ARCHITECTURE §4.7.62): the frames stacked on one paper image
## (frame 0 on top), and how a frame's record is placed in front of the strip's camera. Each frame
## is drawn in a private world from its record alone, so the camera is canonical: the rows'
## centre at the origin, turned so their mean facing looks at the camera (+Z), no level coordinate
## anywhere. Every size, colour and the camera's place are placeholders in the Toy style,
## "not a decision" (taste: the engineer decides after seeing the shots).

## One frame's picture in pixels (4:3). Placeholder.
const FRAME_PX := Vector2i(160, 120)
## The paper margin around and between the frames, in pixels. Placeholder.
const PAD_PX := 8
## The blank paper below the last frame, in pixels. Placeholder.
const FOOTER_PX := 28
## The most frames a strip shows (StartBooth.MAX_FRAMES).
const MAX_FRAMES := StartBooth.MAX_FRAMES
## The paper and a missed frame's colour. Placeholders.
const PAPER := Color(0.96, 0.93, 0.85)
const MISSED := Color(0.55, 0.55, 0.58)
## The strip camera: this far in front of the group's centre, this high, looking at LOOK_AT_M.
## Placeholders.
const CAMERA_DISTANCE_M := 3.2
const CAMERA_HEIGHT_M := 1.6
const LOOK_AT_M := 1.0
const CAMERA_FOV_DEG := 50.0
## A mean facing shorter than this turns nothing (the rows face every way): the record as it is.
const MIN_FACING := 0.2


## A frame's placement: the rows' centre and the turn that faces them to the camera.
class View:
	extends RefCounted
	var centre := Vector3.ZERO
	var turn := Basis.IDENTITY


## The strip image's size for `frames` frames (at least one, at most MAX_FRAMES).
static func size(frames: int) -> Vector2i:
	var count := clampi(frames, 1, MAX_FRAMES)
	return Vector2i(FRAME_PX.x + 2 * PAD_PX, PAD_PX + count * (FRAME_PX.y + PAD_PX) + FOOTER_PX)


## Frame `index`'s rectangle on the strip image.
static func frame_rect(index: int) -> Rect2i:
	return Rect2i(Vector2i(PAD_PX, PAD_PX + index * (FRAME_PX.y + PAD_PX)), FRAME_PX)


## The placement of a frame of `rows`: their mean position, and the yaw turning their mean
## horizontal facing to +Z (none when it is too short to say).
static func view_of(rows: Array[Dictionary]) -> View:
	var view := View.new()
	if rows.is_empty():
		return view
	var sum := Vector3.ZERO
	var facing := Vector3.ZERO
	for row: Dictionary in rows:
		sum += row.get("position", Vector3.ZERO) as Vector3
		var each := row.get("facing", Vector3.ZERO) as Vector3
		each.y = 0.0
		facing += each.normalized() if each.length() > 0.0001 else Vector3.ZERO
	view.centre = sum / rows.size()
	facing /= rows.size()
	if facing.length() >= MIN_FACING:
		view.turn = Basis(Vector3.UP, -atan2(facing.x, facing.z))
	return view


## Row `row` as drawn in its frame: its position and facing turned about the centre.
static func local_row(row: Dictionary, view: View) -> Dictionary:
	var local := row.duplicate(true)
	var position := row.get("position", Vector3.ZERO) as Vector3
	local["position"] = view.turn * (position - view.centre)
	local["facing"] = view.turn * (row.get("facing", Vector3.ZERO) as Vector3)
	return local


## The strip camera's transform in a frame's world.
static func camera_transform() -> Transform3D:
	var eye := Vector3(0.0, CAMERA_HEIGHT_M, CAMERA_DISTANCE_M)
	return Transform3D(Basis.IDENTITY, eye).looking_at(Vector3(0.0, LOOK_AT_M, 0.0), Vector3.UP)


## The strip image of `frames` frames: the paper, each frame's picture blitted into its rectangle
## (a missing or null picture is a grey blank).
static func compose(frames: int, pictures: Dictionary[int, Image]) -> Image:
	var strip_size := size(frames)
	var image := Image.create_empty(strip_size.x, strip_size.y, false, Image.FORMAT_RGB8)
	image.fill(PAPER)
	for index in clampi(frames, 1, MAX_FRAMES):
		var rect := frame_rect(index)
		var picture: Image = pictures.get(index)
		if picture == null or picture.is_empty():
			image.fill_rect(rect, MISSED)
			continue
		var frame := picture.duplicate() as Image
		frame.convert(Image.FORMAT_RGB8)
		if frame.get_size() != FRAME_PX:
			frame.resize(FRAME_PX.x, FRAME_PX.y, Image.INTERPOLATE_BILINEAR)
		image.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME_PX), rect.position)
	return image
