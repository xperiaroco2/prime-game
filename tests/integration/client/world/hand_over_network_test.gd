extends GdUnitTestSuite
## E aimed at a living player hands the hand item over (#1411; ARCHITECTURE §4.1 `HandOver`,
## §4.7.10): in the lobby a joined Game's player holds a handable `gift`, walks at the host's
## player aiming at its eye, and the moment its HandOverUse names the host it stops and presses E,
## as a player would. The host accepts the HandOver (no Rejected) and the gift is in the host
## player's hand on both Games. The prompt shows only with a handable item in the hand and a living
## player in reach under the crosshair, with nothing else E would do there (a raise wins) and the
## line from eye to eye clear of the level.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## The most physics frames a walk takes.
const WALK_FRAMES := 600
## The most physics frames the host's answer takes to arrive.
const ANSWER_FRAMES := 30

var _pair: NetPair
var _rejected: Array[StringName] = []


func before_test() -> void:
	_pair = NetPair.new()
	# FixtureBar's lobby: the tap (#1408) is the station E has other business with.
	_pair.with_tap()
	var mode := _pair.mode
	mode.item_kinds.append(_gift())
	mode.actions.append(FixtureHandOverModes.hand_over_rule(FixtureHandOverModes.conditions()))
	mode.find_phase(&"lobby").accepts.append(
		AcceptSpec.of(Intents.HAND_OVER, AcceptSpec.From.LIVING)
	)
	add_child(_pair)
	_rejected.clear()


func after_test() -> void:
	Input.action_release(&"interact")
	_pair.free()


func test_e_aimed_at_a_living_player_in_the_lobby_hands_the_gift_over() -> void:
	assert_bool(await _pair.start()).is_true()
	var session := _pair.client.client()
	session.event_received.connect(_on_event)
	var joiner := _pair.peer_of(_pair.client)
	var host := _pair.peer_of(_pair.host)
	var gift := await _give_gift(joiner)
	var player := _pair.client.player()
	var keys := _pair.client.items().hand_over
	assert_bool(await _walk_in(player, keys, host)).is_true()
	assert_str(keys.cue()).is_not_empty()
	# E from the device, as in the game: the joiner's Game reads the devices for the press (NetPair's
	# read none; Game._process hands the flag on to its keys each frame).
	_pair.client.device_input = true
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_press(&"interact")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(&"interact")
	_pair.client.device_input = false
	for i: int in ANSWER_FRAMES:
		if _held_on_both(host, gift) or not _rejected.is_empty():
			break
		await _pair.frames(1)
	assert_array(_rejected).is_empty()
	for game: Game in [_pair.host, _pair.client]:
		assert_int(game.client().model.hand_item(host)).is_equal(gift)
		assert_int(game.client().model.hand_item(joiner)).is_equal(-1)
	# The hand is empty: nothing more to hand over, no prompt.
	await _pair.frames(2)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	await _pair.stop()


func test_the_prompt_shows_only_for_a_handable_hand_item_and_a_player_in_reach() -> void:
	assert_bool(await _pair.start()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var host := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var keys := _pair.client.items().hand_over
	# An empty hand, the host in reach under the crosshair: nothing to hand over.
	assert_bool(await _pair.walk_to(player, Vector3(0, 0, -1.2))).is_true()
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	assert_int(keys.hand_over()).is_equal(-1)
	await _give_gift(joiner)
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(host)
	assert_str(keys.cue()).is_not_empty()
	# Aimed past the host: no player under the crosshair.
	_pair.aim(player, _eye_of(_pair.host.player()) + Vector3(2, 0, 0))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	# Aimed at the host from out of reach.
	assert_bool(await _pair.walk_to(player, Vector3(0, 0, -3.5))).is_true()
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	await _pair.stop()


func test_another_target_of_e_wins_over_the_hand_over() -> void:
	assert_bool(await _pair.start()).is_true()
	var host := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var keys := _pair.client.items().hand_over
	await _give_gift(_pair.peer_of(_pair.client))
	assert_bool(await _pair.walk_to(player, Vector3(0, 0, -1.2))).is_true()
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(host)
	# A downed player E would raise (LifeView.raise_target, stood in for here): E raises, so no
	# hand-over target, no prompt and nothing sent.
	var raise := keys.raise_target
	keys.raise_target = func() -> int: return host
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	assert_int(keys.hand_over()).is_equal(-1)
	keys.raise_target = raise
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(host)
	await _pair.stop()


func test_the_tap_wins_over_a_player_under_the_crosshair() -> void:
	assert_bool(await _pair.start()).is_true()
	var model := _pair.client.client().model
	var host := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var keys := _pair.client.items().hand_over
	var taps := _pair.client.items().interactions
	await _give_gift(_pair.peer_of(_pair.client))
	var tap := -1
	for id: int in model.stations:
		if model.stations[id].kind == &"tap":
			tap = id
	assert_int(tap).is_greater_equal(0)
	var spot := TargetChoice.aim_point(model.stations[tap])
	# The host stands between the joiner and the tap, on the line of the crosshair: both the tap
	# (ItemInteractions) and the host (the camera's ray) are in reach under it.
	var at := NetPair.BAR_TAP
	assert_bool(await _pair.walk_to(_pair.host.player(), at + Vector3(-0.5, 0, 0))).is_true()
	assert_bool(await _pair.walk_to(player, at + Vector3(-1.0, 0, 0))).is_true()
	# Closer, aiming at the tap's use spot every frame, until the tap is offered.
	for i: int in WALK_FRAMES:
		_pair.aim(player, spot)
		player.move_input = Vector2(0.0, 1.0)
		await _pair.frames(1)
		if taps.station_target() == tap:
			break
	player.move_input = Vector2.ZERO
	await _pair.frames(3)
	assert_int(taps.station_target()).is_equal(tap)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	assert_int(keys.hand_over()).is_equal(-1)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := _pair.client.ui.lobby_hud
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal(ContentNames.station(&"tap"))
	# Off the tap, the host under the crosshair is the hand-over's again, and its cue takes Aim.
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(taps.station_target()).is_equal(-1)
	assert_int(keys.target()).is_equal(host)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(hud.aim_label.text).is_equal(HudText.hand_over_cue(keys.cue()))
	await _pair.stop()


func test_a_wall_between_the_eyes_hides_the_prompt() -> void:
	assert_bool(await _pair.start()).is_true()
	var host := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var keys := _pair.client.items().hand_over
	await _give_gift(_pair.peer_of(_pair.client))
	assert_bool(await _pair.walk_to(player, Vector3(0, 0, -1.2))).is_true()
	# The crosshair on the host's chest: the camera's ray hits the body below the eyes' line.
	var chest := _eye_of(_pair.host.player()) + Vector3.DOWN * 0.7
	_pair.aim(player, chest)
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(host)
	# A thin bar of the level across the line from eye to eye, above the camera's ray to the chest
	# (the host's TargetInSight `at_eye` refuses): no target, no prompt.
	var eye := player.get_camera().global_position
	var bar := _bar((eye + _eye_of(_pair.host.player())) * 0.5)
	_pair.client.get_parent().add_child(bar)
	_pair.aim(player, chest)
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	bar.get_parent().remove_child(bar)
	bar.free()
	_pair.aim(player, chest)
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(host)
	await _pair.stop()


## A 1 m wide bar of the level, 0.2 m high and 0.05 m deep, centred at `center`.
func _bar(center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.2, 0.05)
	shape.shape = box
	body.add_child(shape)
	body.position = center
	return body


## A one-handed, handable kind, as the full mug is.
func _gift() -> ItemKind:
	var kind := FixtureItemModes.item_kind(&"gift", [])
	kind.handable = true
	return kind


## Puts a new gift in `peer`'s hand on the host (reaching into its Match as NetPair.knock_down
## does: the lobby of the fixture has no bar), announced as a deal announces an item; waits until
## the joiner's Game sees it in that hand and returns its id.
func _give_gift(peer: int) -> int:
	var node := _pair.host.get_node("HostNode") as HostNode
	var played := (node.get("_session") as HostSession).game
	var ctx := MatchContext.new(played)
	ctx.state = played.state
	ctx.mode = played.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = played.ticked_through()
	var feet := played.state.player(peer).position
	var item := Items.spawn(ctx, played.mode.find_item_kind(&"gift"), feet)
	ctx.emit(ItemSpawnedEvent.new(item.id, item.kind.id, item.position))
	Items.give(ctx, peer, item)
	var model := _pair.client.client().model
	for i: int in ANSWER_FRAMES:
		if model.hand_item(peer) == item.id:
			break
		await _pair.frames(1)
	assert_int(model.hand_item(peer)).is_equal(item.id)
	return item.id


## Walks `player` at `peer`'s player, aiming at its eye every frame, until `keys` names it; then
## stops. False when it never did.
func _walk_in(player: PlayerController, keys: HandOverUse, peer: int) -> bool:
	var other := _pair.host.player()
	for i: int in WALK_FRAMES:
		await _pair.frames(1)
		if keys.target() == peer:
			player.move_input = Vector2.ZERO
			return true
		_pair.aim(player, _eye_of(other))
		player.move_input = Vector2(0.0, 1.0)
	player.move_input = Vector2.ZERO
	return false


func _eye_of(body: PlayerController) -> Vector3:
	return body.global_position + Vector3.UP * _pair.mode.player_rules.eye_height_of(false)


func _held_on_both(peer: int, item: int) -> bool:
	for game: Game in [_pair.host, _pair.client]:
		if game.client().model.hand_item(peer) != item:
			return false
	return true


func _on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"Rejected":
		_rejected.append(fields.get("reason", &"") as StringName)
