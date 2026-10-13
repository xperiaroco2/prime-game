extends GdUnitTestSuite
## The crouch over the real wire, without bots (#790; the crouch ADR, KE1, KE10, KD7 (a); the
## engineer's answer (a) on #790: no greybox, the harness on a fixture mode instead; ARCHITECTURE
## §4.6): ClientSessions and a raw client against a HostSession over a LoopbackHub, the codec in
## between, on the harness's fixture mode with PlayerRules.crouch_maps listing Harness.MAP alone.
## A crouched claim on MAP is kept and every other client sees the avatar crouched; a downed
## claim's bit, the bit on SMALL_MAP (a map of the mode crouch_maps does not list) and the bit in
## the lobby are each ignored, the claim itself still taken (never a Rejected). What each client
## decoded equals its Match.view_of. A raw client's hand-built crouched claim (a modified client)
## gets the same answers.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## Long enough for a few claims and a snapshot after them to cross the wire.
const SETTLE_S := 0.4

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_crouched_avatar_reaches_every_other_client_and_a_downed_claims_bit_is_ignored() -> void:
	var second := _in_round(Harness.MAP)
	var game := _h.session.game
	var peer := _h.peer_of(second)
	assert_bool(game.crouch_plays()).is_true()
	_pose(second, true)
	assert_bool(game.state.player(peer).crouched).is_true()
	assert_bool(_h.own.model.is_crouched(peer)).is_true()
	_pose(second, false)
	assert_bool(game.state.player(peer).crouched).is_false()
	assert_bool(_h.own.model.is_crouched(peer)).is_false()
	_pose(second, true)
	assert_bool(_h.own.model.is_crouched(peer)).is_true()
	_knock_down(peer)
	var claims_before: int = _h.claims_in.get(&"round", 0)
	# The downed client goes on claiming crouched: the host takes the claim, never the bit.
	_pose(second, true)
	assert_int(game.state.player(peer).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(_h.claims_in.get(&"round", 0)).is_greater(claims_before)
	assert_bool(game.state.player(peer).crouched).is_false()
	assert_bool(_h.own.model.is_crouched(peer)).is_false()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
		assert_array(client.view.events_named(&"Rejected")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_on_a_map_crouch_maps_does_not_list_the_bit_is_ignored() -> void:
	var second := _in_round(Harness.SMALL_MAP)
	var game := _h.session.game
	var peer := _h.peer_of(second)
	assert_str(game.state.map).is_equal(Harness.SMALL_MAP)
	assert_bool(game.crouch_plays()).is_false()
	var claims_before: int = _h.claims_in.get(&"round", 0)
	_pose(second, true)
	assert_int(_h.claims_in.get(&"round", 0)).is_greater(claims_before)
	assert_bool(game.state.player(peer).crouched).is_false()
	assert_bool(_h.own.model.is_crouched(peer)).is_false()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
		assert_array(client.view.events_named(&"Rejected")).is_empty()


func test_in_the_lobby_the_bit_is_ignored_though_the_next_map_plays_it() -> void:
	_h = Harness.new(_mode())
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(SETTLE_S)
	var game := _h.session.game
	var peer := _h.peer_of(second)
	assert_str(str(game.phase_id())).is_equal("lobby")
	assert_bool(game.state.player_rules.crouch_plays_on(game.state.map)).is_true()
	assert_bool(game.crouch_plays()).is_false()
	_pose(second, true)
	assert_int(_h.claims_in.get(&"lobby", 0)).is_greater(0)
	assert_bool(game.state.player(peer).crouched).is_false()
	assert_bool(_h.own.model.is_crouched(peer)).is_false()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()


func test_a_hostile_crouch_bit_is_kept_only_where_the_crouch_plays() -> void:
	_h = Harness.new(_mode())
	var game := _h.session.game
	var hostile := _h.raw()
	_h.pump_frames(2)
	assert_int(hostile.hello(_h.session.content_hash)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(hostile.named(&"Welcome").size()).is_equal(1)
	var welcome := hostile.named(&"Welcome")[0]
	# The lobby: the claim is taken, its bit ignored, no answer.
	var heard := hostile.received.size()
	var lobby_claim := _claim(welcome.fields["epoch"] as int, 1, welcome.fields["spot"] as Vector3)
	assert_int(hostile.send(lobby_claim)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(_h.claims_in.get(&"lobby", 0)).is_greater(0)
	assert_bool(game.state.player(hostile.peer).crouched).is_false()
	assert_array(_answers(hostile, heard)).is_empty()
	# The round on MAP: a crouched claim is a pose like any other, kept and shown.
	assert_int(hostile.send(WireMessage.new(&"SetReady", {"ready": true}, 1))).is_equal(OK)
	_h.own.send_intent(Intents.SET_READY, {"ready": true})
	var loading := func() -> bool: return not hostile.named(&"LoadMatch").is_empty()
	assert_bool(_h.pump_until(loading, 900)).is_true()
	var match_id := hostile.named(&"LoadMatch")[0].fields["match_id"] as int
	assert_int(hostile.send(WireMessage.new(&"LoadAck", {"match_id": match_id}, 2))).is_equal(OK)
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.pump_seconds(SETTLE_S)
	assert_bool(game.crouch_plays()).is_true()
	var placed: WireMessage = hostile.named(&"Correction").back()
	heard = hostile.received.size()
	var round_claim := _claim(
		placed.fields["epoch"] as int, 1, placed.fields["position"] as Vector3
	)
	assert_int(hostile.send(round_claim)).is_equal(OK)
	_h.pump_seconds(SETTLE_S)
	assert_bool(game.state.player(hostile.peer).crouched).is_true()
	assert_bool(_h.own.model.is_crouched(hostile.peer)).is_true()
	assert_array(_answers(hostile, heard)).is_empty()
	# Downed: the bit is ignored.
	_knock_down(hostile.peer)
	_h.pump_seconds(SETTLE_S)
	var downed: WireMessage = hostile.named(&"Correction").back()
	heard = hostile.received.size()
	var downed_claim := _claim(
		downed.fields["epoch"] as int, 1, downed.fields["position"] as Vector3
	)
	assert_int(hostile.send(downed_claim)).is_equal(OK)
	_h.pump_seconds(SETTLE_S)
	assert_int(game.state.player(hostile.peer).life).is_equal(PlayerState.Life.DOWNED)
	assert_bool(game.state.player(hostile.peer).crouched).is_false()
	assert_bool(_h.own.model.is_crouched(hostile.peer)).is_false()
	assert_array(_answers(hostile, heard)).is_empty()
	assert_array(_h.mismatches(_h.own)).is_empty()
	assert_int(_h.session.malformed_disconnects).is_equal(0)


## The harness's fixture mode with the crouch on Harness.MAP alone (the fixture's crouch numbers
## are FixtureModes.player_rules', not the engineer's).
static func _mode() -> GameMode:
	var made := Harness.fixture_mode()
	made.player_rules.crouch_maps = PackedStringArray([Harness.MAP])
	# A body moves only where the crouch plays (KD11): nothing is knocked down here.
	made.player_rules.motion_maps = PackedStringArray([Harness.MAP])
	assert(made.player_rules.check(made).is_empty())
	return made


## The harness on _mode() with a second client, the host's own client choosing `map` in the
## lobby, both in the round: returns the second.
func _in_round(map: String) -> ClientSession:
	_h = Harness.new(_mode())
	assert_array(_h.session.errors).is_empty()
	assert_bool(_h.started).is_true()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	# SMALL_MAP has one knife marker: one knife fits both maps.
	_h.own.send_intent(Intents.CHANGE_SETTINGS, {"map": map, "settings": {&"knives": 1}})
	_h.pump_seconds(SETTLE_S)
	assert_str(_h.session.game.state.map).is_equal(map)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.pump_seconds(SETTLE_S)
	return second


## `client` reports standing still where the host has it, crouched or not, for SETTLE_S.
func _pose(client: ClientSession, crouched: bool) -> void:
	var at := _h.session.game.state.player(_h.peer_of(client)).position
	client.set_motion(at, Vector3.ZERO, Vector3.FORWARD, false, false, true, crouched)
	_h.pump_seconds(SETTLE_S)


## `peer` is downed where it stands, as a hit to zero health would (tests/integration/client/player/
## net_pair.gd's knock_down): the host's Match is reached into, its events go out as a hit's.
func _knock_down(peer: int) -> void:
	var played := _h.session.game
	var ctx := MatchContext.new(played)
	ctx.state = played.state
	ctx.mode = played.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = played.ticked_through()
	played.state.player(peer).health = 0
	LifeRules.knock_down(ctx, peer)
	_h.pump_seconds(SETTLE_S)


## A hand-built claim of `epoch` standing at `at`, crouched.
static func _claim(epoch: int, client_tick: int, at: Vector3) -> WireMessage:
	var fields := {
		"epoch": epoch,
		"client_tick": client_tick,
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": false,
		"on_floor": true,
		"crouched": true,
		"jumps": 0,
		"sprint_ticks": 0,
		"moved_ticks": 0,
	}
	return WireMessage.new(Intents.MOVE_CLAIM, fields)


## The Corrections and Rejecteds `raw` decoded since its `from`th message.
static func _answers(raw: Harness.RawClient, from: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for message: WireMessage in raw.received.slice(from):
		if message.name == &"Correction" or message.name == &"Rejected":
			found.append(message.name)
	return found
