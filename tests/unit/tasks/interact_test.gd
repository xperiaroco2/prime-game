extends GdUnitTestSuite
## Interact (the Generator ADR's GE1 to GE4, §2.2; ARCHITECTURE §4.1, §9.2): the named station's
## kind owns the rule, tried before the mode's and never the hand item's; an id that names no
## placed station is refused `nothing_to_do` before any owner; the refusals come in the order
## not_accepted, nothing_to_do, two_handed, out_of_reach, blocked, unavailable; an applied use stops
## its actor's raise. Driven by commands on a seeded match whose deal placed two panels
## (FixtureStationModes: station 1 at (0, 0, 20), station 2 at (6, 0, 20); task 1).

const P1 := 1
const P2 := 2
const P3 := 3
const AT := Vector3(0, 0, 20)
const NORTH := Vector3(0, 0, 1)
## Inside station 1's cylinder (radius 1 m), 0.9 m short of its marker.
const NEAR := Vector3(0, 0, 19.1)
const FAR := Vector3(0, 0, 10)
## A wall across the line from NEAR (and FAR) to station 1's marker.
const WALL := AABB(Vector3(-1, 0, 19.3), Vector3(2, 3, 0.1))
const UNPLACED := 99


func test_a_use_at_a_station_reaches_its_type_with_its_task() -> void:
	var game := FixtureStationModes.in_round(FixtureStationModes.basic(), [P1])
	assert_array(game.state.stations.keys()).is_equal([1, 2])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(_uses(game)).is_equal(["used 1 task 1"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_station_kind_comes_before_the_mode_and_the_mode_after_a_kind_with_none() -> void:
	var mode := FixtureStationModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.INTERACT, [], [FixtureNote.of("mode")]))
	var game := FixtureStationModes.in_round(mode, [P1])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(_uses(game)).is_equal(["used 1 task 1"])
	FixtureStationModes.type_of(mode).panel.actions = []
	FixtureStationModes.interact(game, P1, 1, 1)
	assert_array(_uses(game)).is_equal(["used 1 task 1", "mode"])


func test_a_knife_in_hand_changes_nothing() -> void:
	# An item kind's Interact rule is never tried, not even when the station's kind has none and
	# the mode none either. ModeCheck refuses such a rule, so a match would not start with it:
	# it goes in after the start, as a Match that skipped the check would see it.
	var mode := FixtureStationModes.basic()
	var game := FixtureStationModes.in_round(mode, [P1])
	var knife := mode.find_item_kind(&"knife")
	knife.actions.append(FixtureModes.rule(Intents.INTERACT, [], [FixtureNote.of("knife")]))
	FixtureCombatModes.arm(game, P1, NEAR)
	assert_int(game.state.player(P1).held_item).is_not_equal(-1)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(_uses(game)).is_equal(["used 1 task 1"])
	FixtureStationModes.type_of(mode).panel.actions = []
	FixtureStationModes.interact(game, P1, 1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_array(_uses(game)).is_equal(["used 1 task 1"])


func test_an_unplaced_id_is_nothing_to_do_before_the_modes_rule() -> void:
	var mode := FixtureStationModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.INTERACT, [], [FixtureNote.of("mode")]))
	var game := FixtureStationModes.in_round(mode, [P1])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, UNPLACED)
	FixtureStationModes.interact(game, P1, -1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do", &"nothing_to_do"])
	assert_array(_uses(game)).is_empty()


func test_a_package_carrier_naming_an_unknown_station_hears_nothing_to_do() -> void:
	var game := FixtureStationModes.in_round(FixtureStationModes.basic(), [P1])
	_carry_package(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, UNPLACED, 1)
	FixtureStationModes.interact(game, P1, 1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do", &"two_handed"])
	assert_array(_uses(game)).is_empty()


func test_the_refusals_come_in_their_order() -> void:
	# Each step clears the first refusal while every later one still holds.
	var world := FlatWorldQuery.new()
	var mode := FixtureStationModes.basic()
	var type := FixtureStationModes.type_of(mode)
	var game := FixtureStationModes.in_round(mode, [P1], world)
	var player := game.state.player(P1)
	_carry_package(game, P1, FAR)
	world.add_wall(WALL)
	type.problem = StationUsable.UNAVAILABLE
	player.life = PlayerState.Life.DEAD
	FixtureStationModes.interact(game, P1, UNPLACED, 1)
	player.life = PlayerState.Life.DOWNED
	FixtureStationModes.interact(game, P1, UNPLACED, 2)
	player.life = PlayerState.Life.ALIVE
	FixtureStationModes.interact(game, P1, UNPLACED, 3)
	FixtureStationModes.interact(game, P1, 1, 4)
	FixtureItemModes.put_down(game, P1, -NORTH, 5)
	assert_int(player.held_item).is_equal(-1)
	FixtureStationModes.interact(game, P1, 1, 6)
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1, 7)
	world.walls.clear()
	FixtureStationModes.interact(game, P1, 1, 8)
	(
		assert_array(FixtureModes.rejections(game, P1))
		. is_equal(
			[
				&"not_accepted",
				&"not_accepted",
				&"nothing_to_do",
				&"two_handed",
				&"out_of_reach",
				&"blocked",
				&"unavailable",
			]
		)
	)
	assert_array(_uses(game)).is_empty()
	type.problem = &""
	FixtureStationModes.interact(game, P1, 1, 9)
	assert_array(_uses(game)).is_equal(["used 1 task 1"])


func test_the_cylinder_is_the_reach_and_the_other_station_is_out_of_it() -> void:
	var game := FixtureStationModes.in_round(FixtureStationModes.basic(), [P1])
	FixtureItemModes.stand(game, P1, AT + Vector3(1.01, 0, 0))
	FixtureStationModes.interact(game, P1, 1)
	FixtureItemModes.stand(game, P1, AT + Vector3(0, 2.01, 0))
	FixtureStationModes.interact(game, P1, 1, 1)
	FixtureItemModes.stand(game, P1, AT)
	FixtureStationModes.interact(game, P1, 2, 2)
	FixtureStationModes.interact(game, P1, 1, 3)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"out_of_reach", &"out_of_reach", &"out_of_reach"]
	)
	assert_array(_uses(game)).is_equal(["used 1 task 1"])


func test_a_use_stops_its_actors_raise() -> void:
	var game := FixtureStationModes.in_round(FixtureStationModes.basic(), [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, AT + Vector3(1, 0, -1))
	FixtureItemModes.stand(game, P2, AT + Vector3(1, 0, 0))
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureItemModes.stand(game, P3, AT)
	FixtureCombatModes.raise(game, P3, P2)
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	FixtureStationModes.interact(game, P3, 1, 1)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	var stopped := FixtureCombatModes.received(game, P1, &"RaiseStopped")
	assert_array(stopped).has_size(1)
	assert_dict(stopped[0].to_dict()).is_equal({"raiser": P3, "target": P2})
	assert_array(_uses(game)).is_equal(["used 1 task 1"])


func test_a_refused_use_stops_no_raise() -> void:
	var game := FixtureStationModes.in_round(FixtureStationModes.basic(), [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, AT + Vector3(1, 0, -1))
	FixtureItemModes.stand(game, P2, AT + Vector3(1, 0, 0))
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureItemModes.stand(game, P3, AT)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureStationModes.interact(game, P3, 2, 1)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"out_of_reach"])
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	assert_array(FixtureCombatModes.received(game, P1, &"RaiseStopped")).is_empty()


func test_a_dead_host_never_interacts_even_under_host() -> void:
	var living_or_host := AcceptSpec.From.LIVING | AcceptSpec.From.HOST
	var game := FixtureStationModes.in_round(FixtureStationModes.basic(living_or_host), [P1, P2])
	FixtureItemModes.stand(game, P1, NEAR)
	game.state.player(P1).life = PlayerState.Life.DEAD
	FixtureStationModes.interact(game, P1, 1, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_array(_uses(game)).is_empty()
	# The control: the same phase takes it from the living host.
	game.state.player(P1).life = PlayerState.Life.ALIVE
	FixtureStationModes.interact(game, P1, 1, 6)
	assert_array(_uses(game)).is_equal(["used 1 task 1"])


## `peer` stands at `at` and picks up a package laid at its feet.
func _carry_package(game: Match, peer: int, at: Vector3) -> void:
	FixtureItemModes.stand(game, peer, at)
	FixtureItemModes.pick_up(game, peer, FixtureItemModes.lay(game, &"package", at))
	assert_int(game.state.player(peer).held_item).is_not_equal(-1)


## The notes of uses and of the mode's rule, without the item fixture's "rested" notes.
func _uses(game: Match) -> Array[String]:
	var found: Array[String] = []
	for note: String in FixtureModes.notes(game):
		if not note.begins_with("rested"):
			found.append(note)
	return found
