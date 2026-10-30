extends GdUnitTestSuite
## The lobby's tap on the network (#1408; ARCHITECTURE §4.7.54, §7.1.20, §9.5.26): a joined Game's
## player in FixtureBar's lobby walks to the tap that StationTicks placed (no task type holds it),
## aims at its use spot and is offered it (StationUse.usable): the lobby HUD's Aim names it. E
## sends Interact and the host pours a mug into the hand; the left button's Use answers
## nothing_to_do (#1437 takes it), the right button sends UseSecondary (#1438) and the host
## drinks it: ItemChanged turns it into mug_empty and the own drunk value (SelfStatus) rises. No
## other Rejected on the way.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## The most physics frames an answer of the host takes to arrive.
const ANSWER_FRAMES := 60

var _pair: NetPair
var _rejected: Array[StringName] = []


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_tap()
	add_child(_pair)
	_rejected.clear()


func after_test() -> void:
	_pair.free()


func test_e_at_the_tap_pours_a_mug_and_the_right_button_drinks_it() -> void:
	assert_bool(await _pair.start()).is_true()
	var session := _pair.client.client()
	session.event_received.connect(_on_event)
	var model := session.model
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var keys := _pair.client.items().interactions
	var tap := _tap_of(model)
	assert_int(tap).is_greater_equal(0)
	assert_vector(model.stations[tap].position).is_equal(NetPair.BAR_TAP)
	# The joiner stands at (0, 0, -2): a metre short of the tap, inside its 1.5 m less the margin.
	assert_bool(await _pair.walk_to(player, NetPair.BAR_TAP + Vector3(-1.0, 0, 0))).is_true()
	# The walk coasts to a stop: aim at the use spot every frame until the hint is offered.
	for i: int in ANSWER_FRAMES:
		_pair.aim(player, TargetChoice.aim_point(model.stations[tap]))
		await _pair.frames(1)
		if keys.station_target() == tap:
			break
	assert_int(keys.station_target()).is_equal(tap)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := _pair.client.ui.lobby_hud
	assert_bool(hud.aim.visible).is_true()
	# No deck key for the tap yet: its id (ContentNames.station).
	assert_str(hud.aim_label.text).is_equal(ContentNames.station(&"tap"))
	assert_int(keys.interact()).is_greater(0)
	for i: int in ANSWER_FRAMES:
		if model.hand_item(joiner) >= 0 or not _rejected.is_empty():
			break
		await _pair.frames(1)
	assert_array(_rejected).is_empty()
	var mug := model.hand_item(joiner)
	assert_int(mug).is_greater_equal(0)
	assert_str(String(model.items[mug].kind)).is_equal("mug")
	assert_int(model.drunk).is_equal(0)
	# The left button's Use is free for the hit (#1437): with a full mug the host answers
	# nothing_to_do and the mug stays full.
	assert_int(keys.use()).is_greater(0)
	for i: int in ANSWER_FRAMES:
		if not _rejected.is_empty():
			break
		await _pair.frames(1)
	assert_array(_rejected).contains_exactly([RejectReasons.NOTHING_TO_DO])
	assert_str(String(model.items[mug].kind)).is_equal("mug")
	_rejected.clear()
	# The right button's UseSecondary drinks it (#1438).
	assert_int(keys.use_secondary()).is_greater(0)
	for i: int in ANSWER_FRAMES:
		if (model.items[mug].kind == &"mug_empty" and model.drunk > 0) or not _rejected.is_empty():
			break
		await _pair.frames(1)
	assert_array(_rejected).is_empty()
	assert_int(model.hand_item(joiner)).is_equal(mug)
	assert_str(String(model.items[mug].kind)).is_equal("mug_empty")
	# DrunkTicks takes a point a second (FixtureBar.POINT_S): within the wait, at most one went.
	assert_int(model.drunk).is_between(FixtureBar.AMOUNT - 1, FixtureBar.AMOUNT)
	await _pair.stop()


## The tap's station id in `model`, or -1.
func _tap_of(model: ClientModel) -> int:
	for id: int in model.stations:
		if model.stations[id].kind == &"tap":
			return id
	return -1


func _on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"Rejected":
		_rejected.append(fields.get("reason", &"") as StringName)
