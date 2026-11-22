extends GdUnitTestSuite
## The Generator's hum (#801, G6; StationHums): a counting, not yet full generator station hums
## while the round plays and the ears are within the hearing range, on a looping placeholder with
## the range as max_distance; it stops when the charge stops, fills or the round ends, and never
## starts beyond the range; a zone held (counting too) never hums; a wall between the ears and the
## generator muffles it (one ray every MUFFLE_EVERY_S).

const G := preload("res://tests/fixtures/client/fixture_generator_client.gd")
const NEAR := FixtureGeneratorModes.GENERATOR_AT + Vector3(0, 1.5, -5)
const FAR := FixtureGeneratorModes.GENERATOR_AT + Vector3(0, 1.5, -SoundChooser.HEARING_RANGE_M - 1)

var _world: Node3D
var _hums: StationHums
var _ears := NEAR


func before_test() -> void:
	AudioBuses.ensure()
	_ears = NEAR
	_world = Node3D.new()
	add_child(_world)
	_hums = StationHums.new()
	_hums.ears = func() -> Variant: return _ears
	_world.add_child(_hums)


func after_test() -> void:
	_world.free()


func test_a_charging_generator_hums_until_its_charge_stops() -> void:
	var model := _generator()
	await _frames()
	assert_int(_hums.hums()).is_equal(0)
	G.charge(model, 5, true, 1000)
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	var hum := _hums.hum_of(G.GENERATOR)
	assert_bool(hum.playing).is_true()
	assert_float(hum.max_distance).is_equal(SoundChooser.HEARING_RANGE_M)
	assert_that(hum.position).is_equal(FixtureGeneratorModes.GENERATOR_AT)
	var stream := hum.stream as AudioStreamWAV
	assert_int(stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	# A switch turned off stops the charge.
	G.charge(model, 7, false, 1010)
	await _frames()
	assert_int(_hums.hums()).is_equal(0)


func test_a_full_charge_stops_the_hum() -> void:
	var model := _generator()
	G.charge(model, 5, true, 1000)
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	G.charge(model, FixtureGeneratorModes.NEEDED, true, 1040)
	await _frames()
	assert_int(_hums.hums()).is_equal(0)


func test_the_round_ending_stops_the_hum() -> void:
	var model := _generator()
	G.charge(model, 5, true, 1000)
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	model.fold(&"MatchEnded", {"side": &"crew"})
	await _frames()
	assert_int(_hums.hums()).is_equal(0)


func test_beyond_the_hearing_range_no_hum_starts() -> void:
	_ears = FAR
	var model := _generator()
	G.charge(model, 5, true, 1000)
	await _frames()
	assert_int(_hums.started()).is_equal(0)
	_ears = NEAR
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	_ears = FAR
	await _frames()
	assert_int(_hums.hums()).is_equal(0)


func test_a_zone_held_counts_and_never_hums() -> void:
	var mode := FixtureZoneModes.basic()
	var model := ClientModel.new(mode)
	model.own_peer = G.OWN
	G.fold(model, PhaseChangedEvent.new(&"round", 1000))
	var at: Vector3 = FixtureZoneModes.SPOTS[0]
	G.fold(model, StationPlacedEvent.new(9, &"zone", Color.WHITE, at))
	G.fold(model, ZoneProgressEvent.new(9, 3, FixtureZoneModes.NEEDED, true, 1000))
	assert_bool((model.stations[9] as ClientModel.Station).counting).is_true()
	_ears = at + Vector3(0, 1.5, -2)
	_hums.model = model
	_hums.mode = mode
	await _frames()
	assert_int(_hums.started()).is_equal(0)


func test_a_wall_between_muffles_the_hum() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = FixtureGeneratorModes.GENERATOR_AT + Vector3(0, 1.5, -2)
	_world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var model := _generator()
	G.charge(model, 5, true, 1000)
	await _frames()
	var hum := _hums.hum_of(G.GENERATOR)
	assert_int(_hums.rays()).is_greater_equal(1)
	assert_float(hum.volume_db).is_equal(StationHums.HUM_DB + Muffle.QUIET_DB)
	assert_str(String(hum.bus)).is_equal(String(AudioBuses.EFFECTS_MUFFLED))


func _generator() -> ClientModel:
	var mode := FixtureGeneratorModes.basic()
	var model := G.dealt(FixtureGeneratorModes.SWITCHES, mode)
	_hums.model = model
	_hums.mode = mode
	return model


func _frames() -> void:
	for i: int in 3:
		await get_tree().process_frame


## The charger's loop (#1674): the engineer's SfxSet.ENGINE_CHARGING at the charger while a crystal
## of the own ClientEngineBook charges in it, before its `tick`; it stops at the charge's end.
func test_a_charging_crystal_plays_the_chargers_loop_until_its_charge_ends() -> void:
	var mode := load("res://content/modes/base_mode.tres") as GameMode
	var model := ClientModel.new(mode)
	model.fold(&"PhaseChanged", PhaseChangedEvent.new(&"round", 100000).to_dict())
	var charger_at := NEAR + Vector3(0, -1.5, 3)
	model.fold(
		&"StationPlaced",
		{"station": 9, "kind": &"cartridge_charger", "colour": Color.WHITE, "position": charger_at}
	)
	var now := [0]
	_hums.model = model
	_hums.mode = mode
	_hums.host_tick = func() -> int: return now[0]
	var charging := {"station": 4, "charger": 9, "phase": CrystalProblem.CHARGING, "item": 40}
	charging["tick"] = 300
	model.fold(&"CrystalChanged", charging)
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	var hum := _hums.hum_of(9)
	assert_str(String(hum.name)).is_equal("Charging9")
	var stream := hum.stream as AudioStreamWAV
	assert_str(stream.resource_path).is_equal(SfxSet.M8 + "engine_charging.wav")
	assert_int(stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_float(hum.volume_db).is_equal(StationHums.CHARGING_DB)
	# The charge's end tick passes: the loop stops (its CrystalChanged WAITING follows).
	now[0] = 300
	await _frames()
	assert_int(_hums.hums()).is_equal(0)
