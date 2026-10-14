extends GdUnitTestSuite
## The sneak over the real wire (#990): ClientSessions and a raw client against a HostSession over
## a LoopbackHub, the codec in between, on the harness's fixture mode, as the crouch's
## (host_session_crouch_test.gd). A sneaking claim is kept and every other client decodes the
## avatar sneaking, in the round and in the lobby; a downed claim's bit is ignored, the claim itself
## still taken. A raw client's hand-built claim of both bits (a modified client) is relayed crouched
## only (the crouch wins). What each client decoded equals its Match.view_of.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## Long enough for a few claims and a snapshot after them to cross the wire.
const SETTLE_S := 0.4

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_sneaking_avatar_reaches_the_other_client_and_a_downed_claims_bit_is_ignored() -> void:
	var second := _in_round()
	var game := _h.session.game
	var peer := _h.peer_of(second)
	_pose(second, true)
	assert_bool(game.state.player(peer).sneaking).is_true()
	assert_bool(_h.own.model.is_sneaking(peer)).is_true()
	_pose(second, false)
	assert_bool(game.state.player(peer).sneaking).is_false()
	assert_bool(_h.own.model.is_sneaking(peer)).is_false()
	_pose(second, true)
	assert_bool(_h.own.model.is_sneaking(peer)).is_true()
	_knock_down(peer)
	var claims_before: int = _h.claims_in.get(&"round", 0)
	# The downed client goes on claiming the sneak: the host takes the claim, never the bit.
	_pose(second, true)
	assert_int(game.state.player(peer).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(_h.claims_in.get(&"round", 0)).is_greater(claims_before)
	assert_bool(game.state.player(peer).sneaking).is_false()
	assert_bool(_h.own.model.is_sneaking(peer)).is_false()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
		assert_array(client.view.events_named(&"Rejected")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_in_the_lobby_the_bit_is_kept_and_a_hostile_claim_of_both_bits_is_relayed_crouched(
) -> void:
	_h = Harness.new(_mode())
	var game := _h.session.game
	var second := _h.join()
	var hostile := _h.raw()
	_h.pump_frames(2)
	assert_int(hostile.hello(_h.session.content_hash)).is_equal(OK)
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(SETTLE_S)
	assert_str(str(game.phase_id())).is_equal("lobby")
	var peer := _h.peer_of(second)
	_pose(second, true)
	assert_int(_h.claims_in.get(&"lobby", 0)).is_greater(0)
	assert_bool(game.state.player(peer).sneaking).is_true()
	assert_bool(_h.own.model.is_sneaking(peer)).is_true()
	assert_int(hostile.named(&"Welcome").size()).is_equal(1)
	var welcome := hostile.named(&"Welcome")[0]
	var both := _claim(welcome.fields["epoch"] as int, 1, welcome.fields["spot"] as Vector3)
	assert_int(hostile.send(both)).is_equal(OK)
	_h.pump_seconds(SETTLE_S)
	assert_bool(game.state.player(hostile.peer).crouched).is_true()
	assert_bool(game.state.player(hostile.peer).sneaking).is_false()
	assert_bool(_h.own.model.is_crouched(hostile.peer)).is_true()
	assert_bool(_h.own.model.is_sneaking(hostile.peer)).is_false()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
	assert_int(_h.session.malformed_disconnects).is_equal(0)


## The harness's fixture mode with the knockdown's motion on Harness.MAP alone.
static func _mode() -> GameMode:
	var made := Harness.fixture_mode()
	made.player_rules.motion_maps = PackedStringArray([Harness.MAP])
	assert(made.player_rules.check(made).is_empty())
	return made


## The harness on _mode() with a second client, both in the round on Harness.MAP: returns the
## second.
func _in_round() -> ClientSession:
	_h = Harness.new(_mode())
	assert_array(_h.session.errors).is_empty()
	assert_bool(_h.started).is_true()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.own.send_intent(Intents.CHANGE_SETTINGS, {"map": Harness.MAP})
	_h.pump_seconds(SETTLE_S)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.pump_seconds(SETTLE_S)
	return second


## `client` reports standing still where the host has it, sneaking or not, for SETTLE_S.
func _pose(client: ClientSession, sneaking: bool) -> void:
	var at := _h.session.game.state.player(_h.peer_of(client)).position
	client.set_motion(at, Vector3.ZERO, Vector3.FORWARD, false, false, true, false, sneaking)
	_h.pump_seconds(SETTLE_S)


## `peer` is downed where it stands, as host_session_crouch_test.gd's _knock_down.
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


## A hand-built claim of `epoch` standing at `at`, crouched and sneaking (a modified client).
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
		"sneaking": true,
		"jumps": 0,
		"sprint_ticks": 0,
		"moved_ticks": 0,
	}
	return WireMessage.new(Intents.MOVE_CLAIM, fields)
