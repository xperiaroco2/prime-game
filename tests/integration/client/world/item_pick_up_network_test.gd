extends GdUnitTestSuite
## E at the first pick-up hint while walking in (#319; ARCHITECTURE §4.7, Interactions, and §7.1):
## a joined Game's player walks at a knife on the floor, aiming at it, and the moment its
## ItemInteractions offers the knife it stops and presses E, as a player (and playcheck's items
## scenario) would. The host measures InReach from the feet of the last MoveClaim it accepted,
## which trails the feet the hint measures from (claims go at 20 Hz against 60 Hz physics, and a
## claim carries the step before it); the hint's margin (TargetChoice.HINT_MARGIN_S) covers that,
## so the host accepts every such PickUp: the knife reaches the hand, never a Rejected. Three
## knives, each walked at from 3 m, so the first frame of the hint falls on different steps of the
## claim interval; on an even clock and on one that stands still and then jumps (NetPair.uneven).

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## steps_room's knife markers: SpawnItems puts a knife on each.
const KNIVES := 3
## Where the walk in starts: this far from the knife, on its +Z side, walking -Z.
const START_M := 3.0
## The most physics frames a walk takes.
const WALK_FRAMES := 600
## The most physics frames the host's ItemPickedUp takes to arrive.
const ANSWER_FRAMES := 30

var _pair: NetPair
var _rejected: Array[StringName] = []


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_knives(KNIVES)
	add_child(_pair)
	_rejected.clear()


func after_test() -> void:
	_pair.free()


func test_e_at_the_first_hint_while_walking_in_picks_the_knife_up() -> void:
	await _walk_in_at_every_knife()


func test_e_at_the_first_hint_on_an_uneven_clock_picks_the_knife_up() -> void:
	_pair.uneven = true
	await _walk_in_at_every_knife()


func _walk_in_at_every_knife() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var session := _pair.client.client()
	session.event_received.connect(_on_event)
	var model := session.model
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var keys := _pair.client.items().interactions
	var knives: Array[int] = []
	for id: int in model.items:
		knives.append(id)
	knives.sort()
	assert_int(knives.size()).is_equal(KNIVES)
	for knife: int in knives:
		var at := model.items[knife].position
		assert_bool(await _pair.walk_to(player, at + Vector3(0, 0, START_M))).is_true()
		await _pair.frames(10)
		var feet := await _walk_in(player, keys, knife, at)
		var hint := TargetChoice.hint_reach_of(_pair.mode)
		# The hint first showed at its own edge, inside the host's reach by the margin.
		(
			assert_float(Vector2(feet.x - at.x, feet.z - at.z).length())
			. override_failure_message("knife %d: the hint showed %s from it" % [knife, feet])
			. is_between(hint - 0.1, hint)
		)
		_rejected.clear()
		assert_int(keys.pick_up()).is_greater(0)
		for i: int in ANSWER_FRAMES:
			if model.hand_item(joiner) == knife or not _rejected.is_empty():
				break
			await _pair.frames(1)
		(
			assert_array(_rejected)
			. override_failure_message("knife %d: %s" % [knife, _rejected])
			. is_empty()
		)
		assert_int(model.hand_item(joiner)).is_equal(knife)
	assert_int(session.corrections).is_equal(0)
	await _pair.stop()


## Walks `player` at the knife lying at `at`, aiming at its middle every frame, until `keys`
## offers it; then stops and returns where its feet were when the hint showed.
func _walk_in(player: PlayerController, keys: ItemInteractions, knife: int, at: Vector3) -> Vector3:
	for i: int in WALK_FRAMES:
		await _pair.frames(1)
		if keys.target() == knife:
			player.move_input = Vector2.ZERO
			return player.global_position
		_pair.aim(player, ItemView.centre_of(&"knife", at))
		player.move_input = Vector2(0.0, 1.0)
	player.move_input = Vector2.ZERO
	return Vector3.INF


func _on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"Rejected":
		_rejected.append(fields.get("reason", &"") as StringName)
