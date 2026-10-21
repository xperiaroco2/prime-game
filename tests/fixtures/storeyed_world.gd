extends FlatWorldQuery
## The bot scenarios' fake world for a map with storeys (the House, #1209; ARCHITECTURE §9.7):
## FlatWorldQuery's arithmetic with several floors, joined by flights of stairs, on that map's
## level; on any other level (the lobby, which Match tells it of with use_level) FlatWorldQuery's
## one floor at y = 0. Each storey is an infinite floor at its height; each flight a straight ramp
## between two points (its bottom and its top, or a landing's two ends at one height) and a width,
## its floor rising evenly along it. Over a flight, a storey's floor above the flight's lower end
## and no higher than its upper end is cut out (the stairwell), so a walk down from the upper storey
## follows the slope. floor_below() answers the highest floor at or below the point;
## stand_floor_below() the same one ray (no footprint, as FlatWorldQuery). Like the flat fake it has
## no walls: the bots walk straight and see everything, which the wire checks do not depend on; a
## walk changes storey only over a flight (ScenarioPlay fails a walk that would fall).

## A flight's ends lie this close to a storey's height to count as reaching it (float noise).
const LEVEL_EPSILON_M := 0.001

## The level the storeys are; any other is one flat floor.
var map_path := ""
## The storeys' heights.
var storeys: Array[float] = []
## Each flight: its two ends (`from`, `to`) and its width.
var flights: Array[Flight] = []

## Whether the level Match asks about is `map_path`'s; until it says, it is.
var _on_map := true


class Flight:
	extends RefCounted
	var from: Vector3
	var to: Vector3
	var width: float

	func _init(bottom: Vector3, top: Vector3, flight_width: float) -> void:
		from = bottom
		to = top
		width = flight_width

	## The flight's floor height over (point.x, point.z), or NAN when the point is not over it:
	## within half its width of the segment between its ends, between them along it.
	func height_at(point: Vector3) -> float:
		var a := Vector2(from.x, from.z)
		var ab := Vector2(to.x, to.z) - a
		var p := Vector2(point.x, point.z)
		if ab.is_zero_approx():
			return NAN
		var t := (p - a).dot(ab) / ab.length_squared()
		if t < 0.0 or t > 1.0:
			return NAN
		if (p - (a + ab * t)).length() > width / 2.0:
			return NAN
		return lerpf(from.y, to.y, t)

	## Whether the flight cuts the storey at `height` out over itself: above its lower end, and no
	## higher than its upper end.
	func cuts(height: float) -> bool:
		var low := minf(from.y, to.y)
		var high := maxf(from.y, to.y)
		return height > low + LEVEL_EPSILON_M and height <= high + LEVEL_EPSILON_M


## `map`: the level with the storeys; `storey_heights`: its storeys' floors; `flight_ends`: each
## flight's two ends in turn (an even count); `flight_width`: every flight's width.
func _init(
	map: String, storey_heights: Array[float], flight_ends: Array[Vector3], flight_width: float
) -> void:
	super(0.0)
	map_path = map
	storeys = storey_heights.duplicate()
	for i in range(0, flight_ends.size() - 1, 2):
		flights.append(Flight.new(flight_ends[i], flight_ends[i + 1], flight_width))


## The storeys on `map_path`'s level, one flat floor on any other (§4.5, E9: Match tells it the
## level of the phase it enters).
func use_level(path: String) -> void:
	_on_map = path == map_path


## The highest floor at or below `point`: a flight's slope where the point lies over it, or a
## storey's floor not cut out there; NO_FLOOR below every one. Off the map, the flat floor's.
func floor_below(point: Vector3) -> Vector3:
	if not _on_map:
		return super.floor_below(point)
	var best := -INF
	for height: float in storeys:
		if height <= point.y and height > best and not _cut(point, height):
			best = height
	for flight: Flight in flights:
		var height := flight.height_at(point)
		if not is_nan(height) and height <= point.y and height > best:
			best = height
	if best == -INF:
		return NO_FLOOR
	return Vector3(point.x, best, point.z)


## The same one ray as floor_below(), as FlatWorldQuery's.
func stand_floor_below(point: Vector3) -> Vector3:
	return floor_below(point)


## FlatWorldQuery's sweep against the floor below `from` (the one a thrown item starts above), then
## the walls. Off the map, the flat floor's.
func sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
	if not _on_map:
		return super.sweep(from, to, radius)
	var below := floor_below(from)
	var floor_height := below.y if below != NO_FLOOR else -INF
	if from.y - radius <= floor_height:
		return from
	var stop := to
	if to.y - radius < floor_height:
		var t := (from.y - radius - floor_height) / (from.y - to.y)
		stop = from.lerp(to, t)
	return sweep_boxes(from, stop, radius, walls)


func _cut(point: Vector3, height: float) -> bool:
	for flight: Flight in flights:
		if flight.cuts(height) and not is_nan(flight.height_at(point)):
			return true
	return false
