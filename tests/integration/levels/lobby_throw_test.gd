extends GdUnitTestSuite
## No throw at the base mode's numbers rests out of reach on the lobby's mirror (#1708; the throwing
## ADR, TD5 (a); levels/CLAUDE.md "Thrown items and launched bodies"): its top stood 2.67 m up,
## over every standing eye and beyond the pick-up's 2 m, so a mug thrown at it stayed there. The
## mirror's box now runs up the wall past any throw's apex (a jump's included), invisible
## against the wall, so a throw above the frame meets its face and drops to the floor. Read in the
## host's collision world of the lobby with the Throw rule's own ThrowItem numbers and the mode's
## PlayerRules; flights as FlightTicks flies them (HouseThrows.rest_of).

const HouseThrows := preload("res://tests/integration/levels/house_throws.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
const LOBBY := "res://levels/lobby/lobby.tscn"
## The floor spots a thrower stands on in front of the mirror (x, z): by its places and a step back.
const SPOTS: Array[Vector2] = [
	Vector2(-19.3, 6.6),
	Vector2(-19.3, 8.0),
	Vector2(-19.3, 9.4),
	Vector2(-18.0, 7.0),
	Vector2(-18.0, 9.0),
	Vector2(-16.5, 8.0),
]
## A rest this high, over the mirror's footprint (x under MIRROR_FRONT_X), is out of reach.
const OUT_OF_REACH_M := 2.0
const MIRROR_FRONT_X := -19.6

var _world: HostWorldQuery
var _rules: PlayerRules
var _throw: ThrowItem


func before() -> void:
	var mode := load(BASE_MODE) as GameMode
	_rules = mode.player_rules
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			for effect: RuleEffect in rule.effects:
				if effect is ThrowItem:
					_throw = effect as ThrowItem
	_world = HostWorldQuery.new(_rules.capsule_radius_m)
	_world.add_level(LevelWorld.build(LOBBY))
	_world.use_level(LOBBY)


func after() -> void:
	_world = null
	_rules = null
	_throw = null


func test_no_throw_rests_on_the_mirror() -> void:
	assert_object(_throw).is_not_null()
	var found: Array[Vector3] = []
	for spot: Vector2 in SPOTS:
		# Standing, and at the top of a jump.
		for lift: float in [0.0, _rules.jump_height_m]:
			found.append_array(_mirror_rests(spot, lift))
	(
		assert_int(found.size())
		. override_failure_message(
			(
				"%d throws rest on the mirror, the first at %s"
				% [found.size(), found[0] if not found.is_empty() else Vector3.ZERO]
			)
		)
		. is_equal(0)
	)


## The rests on the mirror of a fan of throws toward the wall from `spot`, the eye `lift` higher.
func _mirror_rests(spot: Vector2, lift: float) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var feet := Vector3(spot.x, 0.0, spot.y)
	var eye := feet + Vector3.UP * (_rules.eye_height_m + lift)
	var down := Vector3(0.0, -_throw.gravity_mps2, 0.0)
	var ticks := maxi(1, Ticks.from_seconds(_throw.longest_flight_s))
	# Toward the wall (-x): yaw -90 degrees, 60 either side.
	for yaw_deg in range(-150, -29, HouseThrows.YAW_STEP_DEG):
		for pitch_deg in range(0, HouseThrows.PITCH_TOP_DEG + 1, HouseThrows.PITCH_STEP_DEG):
			var yaw := deg_to_rad(yaw_deg)
			var pitch := deg_to_rad(pitch_deg)
			var facing := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			var rest := HouseThrows.rest_of(
				_world, eye, facing * _throw.speed_mps, down, _throw.radius_m, ticks, feet
			)
			if rest.y > OUT_OF_REACH_M and rest.x < MIRROR_FRONT_X:
				found.append(rest)
	return found
