class_name PhotoFrame
extends RefCounted
## The photo camera's frame (the photo ADR §2.3): the pyramid a shot sees, from the lens (the
## camera station's spot at eye height) toward the aim (the photo spot's at eye height), with the
## mode's vertical field of view, aspect (width over height) and range. A point is in the frame
## when it lies between NEAR_M and the range in front of the lens and inside the four edges. Pure
## geometry; the line of sight is the shot's own check (WorldQuery).

## How near the lens a point may lie and still count: a head pressed against the lens is not a
## photo of it.
const NEAR_M := 0.3

var lens := Vector3.ZERO
## The lens's orientation: -Z looks at the aim, +Y is up in the picture.
var basis := Basis.IDENTITY
var range_m := 0.0
## tan of half the vertical field of view, and of half the horizontal one.
var _tan_v := 0.0
var _tan_h := 0.0


## The frame of a lens at `from` looking at `aim`, `fov_deg` the vertical field of view in
## degrees, `aspect` width over height, `far` the farthest distance that counts. An aim straight
## above or below the lens (the fit check refuses such a layout) takes the world's forward as the
## picture's up.
static func between(
	from: Vector3, aim: Vector3, fov_deg: float, aspect: float, far: float
) -> PhotoFrame:
	var frame := PhotoFrame.new()
	frame.lens = from
	var direction := aim - from
	var up := Vector3.UP
	if Vector2(direction.x, direction.z).length() < 1e-4:
		up = Vector3.FORWARD
	if direction.length() < 1e-4:
		direction = Vector3.FORWARD
	frame.basis = Basis.looking_at(direction, up)
	frame.range_m = far
	frame._tan_v = tan(deg_to_rad(fov_deg) / 2.0)
	frame._tan_h = frame._tan_v * aspect
	return frame


## Whether `point` lies in the frame: between NEAR_M and the range in front of the lens, and
## within the four edges (an edge itself counts).
func contains(point: Vector3) -> bool:
	var local := basis.transposed() * (point - lens)
	var depth := -local.z
	if depth < NEAR_M or depth > range_m:
		return false
	return absf(local.x) <= depth * _tan_h and absf(local.y) <= depth * _tan_v
