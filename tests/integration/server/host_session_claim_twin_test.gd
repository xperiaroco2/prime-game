extends GdUnitTestSuite
## MoveClaimReliable, MoveClaim's RELIABLE twin (#429; ARCHITECTURE §4.3, §4.5, §7.1), over a
## LoopbackHub with a fake clock. The host hands a twin to core/ as the plain MoveClaim command, so
## it passes exactly a claim's checks: an honest one moves the player, a copy of a claim already
## applied changes nothing, a hostile one gets a Correction to its sender alone and never a
## Rejected, one from a sender no phase takes a claim from is dropped in silence (E15), and twins
## take the reliable-intents budget. End to end: an epoch's first claim, which ClientSession sends
## on the twin, survives a link that loses LATEST, so no honest walker is corrected.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const EAST := Vector3(1, 0, 0)
## Under the walk speed (0.225 m per tick) and its slack: two of them fail a one-tick span.
const WALK_STEP := 0.2

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_twin_reaches_the_match_as_a_plain_move_claim() -> void:
	_h = Harness.new()
	var chaos := _player()
	var spot := _spot(chaos)
	var claims_before := _commands(chaos.peer, Intents.MOVE_CLAIM).size()
	assert_int(chaos.send(_twin(_epoch(chaos), 1, spot + EAST * WALK_STEP))).is_equal(OK)
	_h.pump_frames(4)
	var applied := _commands(chaos.peer, Intents.MOVE_CLAIM)
	assert_int(applied.size()).is_equal(claims_before + 1)
	assert_int(applied[-1].seq).is_equal(0)
	assert_array(_commands(chaos.peer, WireSchema.RELIABLE_CLAIM)).is_empty()
	var player := _h.session.game.state.player(chaos.peer)
	assert_vector(player.position).is_equal_approx(spot + EAST * WALK_STEP, Vector3.ONE * 1e-4)
	assert_int(player.claim_tick).is_equal(1)
	assert_array(chaos.named(&"Rejected")).is_empty()
	assert_array(chaos.named(&"Correction")).is_empty()
	assert_array(_h.session.game.view_of(chaos.peer).events_named(&"Rejected")).is_empty()


func test_a_twin_of_an_applied_claim_is_dropped_in_silence() -> void:
	_h = Harness.new()
	var chaos := _player()
	var spot := _spot(chaos)
	var claim := _twin(_epoch(chaos), 1, spot + EAST * WALK_STEP)
	assert_int(chaos.send(WireMessage.new(Intents.MOVE_CLAIM, claim.fields))).is_equal(OK)
	_h.pump_frames(4)
	var player := _h.session.game.state.player(chaos.peer)
	var position := player.position
	var stamina := player.stamina
	var epoch := player.epoch
	var events := chaos.received.size()
	assert_int(chaos.send(claim)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(_commands(chaos.peer, Intents.MOVE_CLAIM).size()).is_equal(2)
	assert_vector(player.position).is_equal(position)
	assert_int(player.stamina).is_equal(stamina)
	assert_int(player.claim_tick).is_equal(1)
	assert_int(player.epoch).is_equal(epoch)
	for message: WireMessage in chaos.received.slice(events):
		assert_str(str(message.name)).is_not_equal("Correction").is_not_equal("Rejected")


func test_a_hostile_twin_is_checked_like_any_claim() -> void:
	_h = Harness.new()
	var chaos := _player()
	var spot := _spot(chaos)
	var epoch := _epoch(chaos)
	var own_before := _h.own.view.events.size()
	# A teleport: corrected back to the spot, in a new epoch, to the sender alone.
	assert_int(chaos.send(_twin(epoch, 1, spot + EAST * ChaosFrames.TELEPORT_M))).is_equal(OK)
	_h.pump_frames(4)
	var corrections := chaos.named(&"Correction")
	assert_int(corrections.size()).is_equal(1)
	assert_int(corrections[0].fields["epoch"] as int).is_equal(epoch + 1)
	assert_vector(corrections[0].fields["position"] as Vector3).is_equal(spot)
	# A tick far in the future after an accepted one: past the credit, corrected again.
	assert_int(chaos.send(_twin(epoch + 1, 2, spot))).is_equal(OK)
	_h.pump_frames(4)
	var future := _twin(epoch + 1, 2 + ChaosFrames.FUTURE_TICKS, spot + EAST * WALK_STEP)
	assert_int(chaos.send(future)).is_equal(OK)
	_h.pump_frames(4)
	corrections = chaos.named(&"Correction")
	assert_int(corrections.size()).is_equal(2)
	assert_int(corrections[1].fields["epoch"] as int).is_equal(epoch + 2)
	assert_vector(_h.session.game.state.player(chaos.peer).position).is_equal(spot)
	assert_array(chaos.named(&"Rejected")).is_empty()
	assert_array(_h.own.view.events.slice(own_before)).is_empty()


func test_twins_take_the_reliable_intents_budget_and_are_never_merged() -> void:
	_h = Harness.new()
	var chaos := _player()
	_h.pump_seconds(PeerBudget.INTENTS / PeerBudget.INTENTS_PER_SECOND)
	var spot := _spot(chaos)
	var epoch := _epoch(chaos)
	var over_before := _h.session.over_budget
	var claims_before := _commands(chaos.peer, Intents.MOVE_CLAIM).size()
	var within := int(PeerBudget.INTENTS)
	for tick in range(1, within + 2):
		chaos.send(_twin(epoch, tick, spot))
	_h.pump_frames(4)
	assert_int(_h.session.over_budget - over_before).is_equal(1)
	assert_int(_commands(chaos.peer, Intents.MOVE_CLAIM).size() - claims_before).is_equal(within)
	assert_bool(chaos.lost).is_false()
	assert_int(_h.session.malformed_disconnects).is_equal(0)


func test_a_twin_in_a_phase_that_takes_no_claim_is_dropped_in_silence() -> void:
	_h = Harness.new()
	var chaos := _player()
	assert_int(chaos.send(WireMessage.new(&"SetReady", {"ready": true}, 1))).is_equal(OK)
	_h.own.send_intent(Intents.SET_READY, {"ready": true})
	assert_bool(_h.run_until_phase(&"loading")).is_true()
	var events := chaos.received.size()
	assert_int(chaos.send(_twin(_epoch(chaos), 1, _spot(chaos)))).is_equal(OK)
	_h.pump_frames(4)
	assert_str(str(_h.session.game.phase_id())).is_equal("loading")
	assert_array(_commands(chaos.peer, Intents.MOVE_CLAIM)).is_not_empty()
	for message: WireMessage in chaos.received.slice(events):
		assert_str(str(message.name)).is_not_equal("Correction").is_not_equal("Rejected")
	assert_int(_h.transport.rejects.total()).is_equal(0)


## #429's second behaviour, end to end: the link loses the first LATEST MoveClaim the walker
## sends. The walker moves WALK_STEP per client tick from its very first claim, so a lost first
## claim of the epoch would leave the next one two steps from the spot, counted as one tick. No
## other player is near: the push allowance would cover the second step.
func test_an_epochs_first_claim_survives_a_link_that_loses_latest() -> void:
	_h = Harness.new(null, false)
	var walker := _h.join_lossy()
	_h.lossy.claims_to_lose = 1
	# The Welcome reaches the walker outside its step, as a mover's physics step runs before it.
	for i in 20:
		if walker.is_welcomed():
			break
		_h.now += Harness.FRAME_USEC
		_h.session.step(_h.now)
		_h.lossy.poll()
	assert_bool(walker.is_welcomed()).is_true()
	var spot := walker.view.events_named(&"Welcome")[0].fields["spot"] as Vector3
	var at := spot
	for i in 30:
		var tick := walker.client_tick(_h.now + Harness.FRAME_USEC)
		at = spot + EAST * WALK_STEP * (tick + 1)
		walker.set_motion(at, EAST, Vector3.FORWARD, false, true, true)
		_h.pump()
	_h.pump_frames(3)
	assert_int(_h.lossy.lost).is_equal(1)
	assert_array(walker.view.events_named(&"Correction")).is_empty()
	assert_int(walker.corrections).is_equal(0)
	var accepted := _h.session.game.state.player(_h.peer_of(walker)).position
	assert_vector(accepted).is_equal_approx(at, Vector3.ONE * 1e-4)


## A raw client that is a player of the lobby, its Welcome decoded.
func _player() -> Harness.RawClient:
	var chaos := _h.raw()
	_h.pump_frames(2)
	assert_int(chaos.hello(_h.session.content_hash)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(chaos.named(&"Welcome").size()).is_equal(1)
	return chaos


func _spot(raw: Harness.RawClient) -> Vector3:
	return raw.named(&"Welcome")[0].fields["spot"] as Vector3


func _epoch(raw: Harness.RawClient) -> int:
	return raw.named(&"Welcome")[0].fields["epoch"] as int


## A twin of a claim that walked to `position` by itself, on the floor, without sprint.
func _twin(epoch: int, client_tick: int, position: Vector3) -> WireMessage:
	var fields := {
		"epoch": epoch,
		"client_tick": client_tick,
		"position": position,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": true,
		"on_floor": true,
		"jumps": 0,
		"sprint_ticks": 0,
		"moved_ticks": ChaosFrames.HONEST_MOVED_TICKS,
	}
	return WireMessage.new(WireSchema.RELIABLE_CLAIM, fields)


## The commands of `kind` from `peer` in the match's command log, in order.
func _commands(peer: int, kind: StringName) -> Array[MatchCommand]:
	var found: Array[MatchCommand] = []
	for command: MatchCommand in _h.session.game.command_log.commands:
		if command.kind == kind and command.peer == peer:
			found.append(command)
	return found
