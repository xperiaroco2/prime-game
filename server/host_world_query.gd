class_name HostWorldQuery
extends WorldQuery
## The host's WorldQuery (ARCHITECTURE §4.5, §7.1; E8 to E10): core/'s geometric questions answered
## by rays in the host's own collision world of the level Match names (use_level), one LevelWorld
## per level of the mode, built when the session starts. Never the client's scene.
##
## Rays see layer 1 (`world`) only, bodies not areas. The conventions are FlatWorldQuery's: a floor
## answer keeps the point's x and z; no floor is NO_FLOOR. With no level (a phase with none, or a
## path it was not given) it answers like an empty world: sight is clear and there is no floor.
## A ray that starts exactly on a surface may miss it: core/ asks the floor from a little above
## the point (Items.lifted, MovementRule.FLOOR_PROBE_M, MarkerReader.FLOOR_PROBE_M).

## The query mask: the level's static colliders (LevelWorld.WORLD_LAYER).
const WORLD_MASK := LevelWorld.WORLD_LAYER
## A placed item stops this far before the first thing its ray hits (§4.5: a placeholder, "not a
## decision").
const WALL_STOP_M := 0.2
## How far down a floor ray looks: deeper than any level.
const FLOOR_RAY_M := 1000.0

## The capsule's radius for stand_floor_below(): the mode's PlayerRules.capsule_radius_m.
var footprint_radius := 0.0
## Every level world's read errors, in the order the levels were first added.
var errors := PackedStringArray()

var _levels: Dictionary[String, LevelWorld] = {}
var _current: LevelWorld = null


func _init(capsule_radius: float = 0.0) -> void:
	footprint_radius = capsule_radius


## The worlds of every level of `mode` (its lobby and its maps: MarkerReader.level_paths_of), with
## the mode's capsule radius. Check `errors` before hosting: a level with errors is refused.
static func for_mode(mode: GameMode) -> HostWorldQuery:
	var radius := mode.player_rules.capsule_radius_m if mode.player_rules != null else 0.0
	var query := HostWorldQuery.new(radius)
	for path: String in MarkerReader.level_paths_of(mode):
		query.add_level(LevelWorld.build(path))
	return query


## Adds `level` under its path, replacing a level of the same path (and its errors).
func add_level(level: LevelWorld) -> void:
	_levels[level.path] = level
	errors = PackedStringArray()
	for added: LevelWorld in _levels.values():
		errors.append_array(added.errors)


## Whether a level of `path` was added.
func has_level(path: String) -> bool:
	return _levels.has(path)


## The level the questions are about now; empty with none.
func level_path() -> String:
	return _current.path if _current != null else ""


## Switches to the level of `path` (E9). An empty path (a phase with no level) leaves no level; a
## path with no world is logged, and then there is no level either.
func use_level(path: String) -> void:
	_current = _levels.get(path) as LevelWorld
	if _current == null and not path.is_empty():
		push_error("host world: no collision world for the level %s" % path)


## Whether the segment from `from` to `to` hits nothing (§4.5).
func line_of_sight(from: Vector3, to: Vector3) -> bool:
	return _ray(from, to).is_empty()


## One downward ray at `point`, for an item or a body (E10).
func floor_below(point: Vector3) -> Vector3:
	var hit := _ray(point, point + Vector3.DOWN * FLOOR_RAY_M)
	if hit.is_empty():
		return NO_FLOOR
	var at: Vector3 = hit["position"]
	return Vector3(point.x, at.y, point.z)


## The highest floor under five downward rays: at `point` and at four points footprint_radius
## from it (+x, -x, +z, -z), at `point`'s x and z (E10 (b)): a player on a ledge's edge stands on
## the ledge.
func stand_floor_below(point: Vector3) -> Vector3:
	var found := floor_below(point)
	var r := footprint_radius
	for offset: Vector3 in [
		Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)
	]:
		var under := floor_below(point + offset)
		if under != NO_FLOOR and (found == NO_FLOOR or under.y > found.y):
			found = Vector3(point.x, under.y, point.z)
	return found


## A ray from `from` to `towards`, stopped WALL_STOP_M before the first hit, then floor_below()
## there; with no floor, the stop itself.
func rest_position(from: Vector3, towards: Vector3) -> Vector3:
	var stop := towards
	var hit := _ray(from, towards)
	if not hit.is_empty():
		var at: Vector3 = hit["position"]
		var distance := from.distance_to(at)
		stop = from + (towards - from).normalized() * maxf(0.0, distance - WALL_STOP_M)
	var floor_point := floor_below(stop)
	return floor_point if floor_point != NO_FLOOR else stop


## A sphere of `radius` (TE2): `from` when it already overlaps a collider there (intersect_shape;
## cast_motion ignores what the shape already overlaps), else moved along the segment by
## cast_motion's safe fraction, which stops it short of contact. With no level, `to`. A radius of
## 0 or less is a point: the ray's hit, or `to`.
func sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
	if _current == null:
		return to
	if radius <= 0.0:
		var hit := _ray(from, to)
		if hit.is_empty():
			return to
		var at: Vector3 = hit["position"]
		return at
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.collision_mask = WORLD_MASK
	var space := _current.space_state()
	if not space.intersect_shape(query, 1).is_empty():
		return from
	if from == to:
		return to
	query.motion = to - from
	var fractions := space.cast_motion(query)
	return from + (to - from) * fractions[0]


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	if _current == null or from == to:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return _current.space_state().intersect_ray(query)
