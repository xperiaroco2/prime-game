extends GdUnitTestSuite
## No flat top on the estate outside the swept roofs holds a thrown item out of every player's
## reach (#1374; the throwing ADR, TD5 (a); estate_roof_throw_test.gd sweeps the roofs). Each flat
## box top of the level's host collision (the fences, the gate's posts, the creek's banks, the
## camera posts, every piece a later change adds) is one of:
## - a floor: no standable floor beside it;
## - a step: at most the mode's jump (PlayerRules.jump_height_m) over the floor beside it, so a
##   player gets onto it;
## - in reach: its middle, half its side and a player's capsule radius out from the feet on the
##   floor beside it, is within the PickUp rule's InReach;
## - over every throw: higher than the arc's top (the eye over the highest floor within
##   PERCH_SPAN_M of its long sides, plus the Throw rule's speed squared over twice its gravity);
## - covered: another body of the level's collision lies on it, over every point of a
##   COVER_STEP_M grid COVER_PROBE_M above it, so no item rests there (the hidden passages' walls
##   reach into the ground and the basement slab, #1373);
## - or left to another guard: in a footprint of EstateThrows.TOPS grown by its eave, at any
##   height (the roof sweep), or in the House's lot piece, as the roof sweep leaves it out.
## Anything else is a top a throw can reach and no player can: red, by body and piece.
## Not read: a shape that is not a box, which must lie in a swept footprint or the House's lot (the
## art ship's hull and floors, #1499; a test says so); a ceiling over a top with a
## gap under it (a throw under it is taken as unbounded, so the check errs red).

const EstateThrows := preload("res://tests/integration/levels/estate_throws.gd")
const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
## How far out from a top's narrow side a perch counts, and the step between samples.
const PERCH_SPAN_M := 2.0
const PERCH_STEP_M := 0.5
## A floor whose height under a player's footprint varies more than this is no place to stand.
const STAND_STEP_M := 0.3
## A covered top: the step of the grid on it, how far above it each point is asked, and how far in
## from its edges the grid starts.
const COVER_STEP_M := 0.5
const COVER_PROBE_M := 0.05
const COVER_INSET_M := 0.05

var _world: HostWorldQuery
var _level: LevelWorld
var _rules: PlayerRules
var _throw: ThrowItem
var _reach_m := 0.0
var _tops: Array[Dictionary] = []
var _others: Array[Dictionary] = []


func before() -> void:
	var mode := load(BASE_MODE) as GameMode
	_rules = mode.player_rules
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			for effect: RuleEffect in rule.effects:
				if effect is ThrowItem:
					_throw = effect as ThrowItem
		var picks := false
		var reach := 0.0
		for condition: Condition in rule.conditions:
			if condition is ItemOnGround:
				picks = true
			if condition is InReach:
				reach = (condition as InReach).reach_m
		if picks and reach > 0.0:
			_reach_m = reach
	var root := (load(EstateDoc.MAP) as PackedScene).instantiate()
	_tops = EstateThrows.box_tops(root)
	_others = EstateThrows.other_shapes(root)
	_world = HostWorldQuery.new(_rules.capsule_radius_m)
	_level = LevelWorld.from_scene(root, EstateDoc.MAP)
	_world.add_level(_level)
	_world.use_level(EstateDoc.MAP)
	root.free()


func after() -> void:
	_world = null
	_level = null
	_rules = null
	_throw = null
	_tops.clear()


func test_the_numbers_and_the_tops_are_read() -> void:
	assert_object(_throw).is_not_null()
	assert_float(_reach_m).is_greater(0.0)
	var pieces: Array[String] = []
	for top: Dictionary in _tops:
		if not pieces.has(top["piece"]):
			pieces.append(top["piece"])
	assert_array(pieces).contains(["Plot", "Creek", "Gate", "Bonfire", "Well"])


func test_every_top_outside_the_swept_roofs_is_a_floor_a_step_in_reach_or_over_every_throw(
) -> void:
	var swept := EstateThrows.tops(_world)
	var red: Array[String] = []
	for top: Dictionary in _tops:
		var centre: Vector3 = top["centre"]
		var plan := Vector2(centre.x, centre.z)
		if top["piece"] == "House" or _in_a_swept_footprint(swept, plan) or _covered(top):
			continue
		var why := _why_out_of_reach(top)
		if why != "":
			red.append("%s (%s): %s" % [top["body"], top["piece"], why])
	assert_array(red).override_failure_message("\n".join(red)).is_empty()


func test_a_fence_a_throw_reaches_and_no_player_does_is_red() -> void:
	# A 0.2 m wall 2.2 m high on the open ground east of the bonfire: in reach of no feet (2.3 m
	# to its middle), under a
	# throw's arc, so the check is not blind.
	var top := {
		"piece": "Probe",
		"body": "Probe",
		"centre": Vector3(75.0, 2.2, 45.0),
		"narrow": 0.2,
		"long": 4.0,
		"across": Vector3.RIGHT,
		"along": Vector3.BACK,
	}
	assert_str(_why_out_of_reach(top)).is_not_empty()
	assert_bool(_covered(top)).is_false()


func test_a_passage_wall_under_the_ground_is_covered_and_a_top_half_out_of_it_is_not() -> void:
	# The tunnel's wall reaches into the ground box (#1373): covered. The same top lifted out of
	# the ground's top by half a metre is open, so the rule is not blind.
	var wall := {}
	for top: Dictionary in _tops:
		if top["body"] == "Passages/TunnelWall01":
			wall = top
	assert_bool(wall.is_empty()).is_false()
	assert_bool(_covered(wall)).is_true()
	var lifted := wall.duplicate()
	lifted["centre"] = (wall["centre"] as Vector3) + Vector3.UP * 1.4
	assert_bool(_covered(lifted)).is_false()


## "" when the top is a floor, a step, in reach or over every throw; else what it is. The feet
## stand on a floor out from each of its four sides (half the side across it and the capsule
## radius from its centre); the perches on every floor within PERCH_SPAN_M out from either long
## side. A floor counts only where a player stands: one height under the whole capsule
## footprint (_stand), so a fence's or a post's own top beside it is no floor.
func _why_out_of_reach(top: Dictionary) -> String:
	var centre: Vector3 = top["centre"]
	var across: Vector3 = top["across"]
	var along: Vector3 = top["along"]
	var half: float = (top["narrow"] as float) / 2.0
	var half_long: float = (top["long"] as float) / 2.0
	var cap := _rules.capsule_radius_m
	var nearest := INF
	var lowest_rise := INF
	for side: Array in [
		[across, half + cap],
		[-across, half + cap],
		[along, half_long + cap],
		[-along, half_long + cap]
	]:
		var feet := _stand(centre + (side[0] as Vector3) * (side[1] as float), centre.y)
		if feet == -INF:
			continue
		var rise := centre.y - feet
		lowest_rise = minf(lowest_rise, rise)
		nearest = minf(
			nearest, Vector2(side[1] as float, rise + Items.SURFACE_CLEARANCE_M).length()
		)
	if lowest_rise == INF or lowest_rise <= _rules.jump_height_m or nearest <= _reach_m:
		return ""
	var perch := -INF
	var out := half + cap
	while out <= half + PERCH_SPAN_M + 0.001:
		for side_sign: float in [1.0, -1.0]:
			perch = maxf(perch, _stand(centre + across * side_sign * out, centre.y))
		out += PERCH_STEP_M
	var arc_top := (
		perch
		+ _rules.eye_height_m
		+ _throw.speed_mps * _throw.speed_mps / (2.0 * _throw.gravity_mps2)
		+ Items.SURFACE_CLEARANCE_M
	)
	if centre.y > arc_top:
		return ""
	var why := "top %.2f m, %.2f m over the floor beside it, " % [centre.y, lowest_rise]
	why += "%.2f m from the nearest feet (reach %.1f), " % [nearest, _reach_m]
	return why + "under a throw's top %.2f m" % arc_top


## Whether a body of the level's collision holds every point of a COVER_STEP_M grid COVER_PROBE_M
## over the top: points, not rays, as a ray does not hit from inside a box.
func _covered(top: Dictionary) -> bool:
	var centre: Vector3 = top["centre"]
	var across: Vector3 = top["across"]
	var along: Vector3 = top["along"]
	var half := maxf((top["narrow"] as float) / 2.0 - COVER_INSET_M, 0.0)
	var half_long := maxf((top["long"] as float) / 2.0 - COVER_INSET_M, 0.0)
	var space := _level.space_state()
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = HostWorldQuery.WORLD_MASK
	for a: float in _offsets(half):
		for b: float in _offsets(half_long):
			query.position = centre + Vector3.UP * COVER_PROBE_M + across * a + along * b
			if space.intersect_point(query, 1).is_empty():
				return false
	return true


## Offsets from -half to half, both ends included, at most COVER_STEP_M apart.
func _offsets(half: float) -> Array[float]:
	var count := maxi(ceili(2.0 * half / COVER_STEP_M), 1)
	var offsets: Array[float] = []
	for i: int in count + 1:
		offsets.append(-half + 2.0 * half * i / count)
	return offsets


## The floor a player stands on at `at` (x, z) under `under_y`: the height of the floor straight
## down, when the floor under each edge of the capsule footprint is within STAND_STEP_M of it; else
## -INF.
func _stand(at: Vector3, under_y: float) -> float:
	var found := _world.floor_below(Vector3(at.x, under_y - 0.05, at.z))
	if found == WorldQuery.NO_FLOOR:
		return -INF
	var r := _rules.capsule_radius_m
	for offset: Vector3 in [
		Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)
	]:
		var edge := _world.floor_below(Vector3(at.x, under_y - 0.05, at.z) + offset)
		if edge == WorldQuery.NO_FLOOR or absf(edge.y - found.y) > STAND_STEP_M:
			return -INF
	return found.y


## Whether `plan` (x, z) lies in a swept roof's footprint grown by its eave, at any height: the
## roof sweep throws from under and around it (estate_throws.gd).
func _in_a_swept_footprint(swept: Dictionary[String, Dictionary], plan: Vector2) -> bool:
	for top_name: String in swept:
		var rect: Rect2 = swept[top_name]["rect"]
		if rect.grow(EstateThrows.EAVE_M).has_point(plan):
			return true
	return false


## A shape this test does not read (not a box) is left to the roof sweep: it lies whole in a swept
## footprint grown by its eave, or in the House's lot (#1499: the art ship's hull, wider than the
## doc's rect, was out of both guards).
func test_every_shape_that_is_not_a_box_lies_in_a_swept_footprint() -> void:
	var swept := EstateThrows.tops(_world)
	var outside: Array[String] = []
	for other: Dictionary in _others:
		var plan: Rect2 = other["plan"]
		if other["piece"] == "House" or _in_a_swept_footprint(swept, plan.position):
			if other["piece"] == "House" or _in_a_swept_footprint(swept, plan.end):
				continue
		outside.append("%s (%s): %s" % [other["body"], other["piece"], plan])
	assert_array(_others).is_not_empty()
	assert_array(outside).override_failure_message("\n".join(outside)).is_empty()
