extends GdUnitTestSuite
## What each peer receives when a player sends what a modified client can (ARCHITECTURE invariant
## 1; the chaos bots' classes 2, 5 and 6, #188), over a LoopbackHub with a fake clock: replayed and
## out-of-order seqs each get the rule's own Rejected echoing them (§4.3: seq is only echoed); a
## hostile MoveClaim gets a Correction to its sender alone, never a Rejected, and one of another
## epoch nothing (§7.1, E15); messages over the intents budget get no reply and no disconnect
## (§4.5). The whole run of every class together: tools\run.cmd bots --chaos.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const SEQ := 77
## A burst past the intents bucket (PeerBudget.INTENTS) in one frame.
const BURST := 130

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_replayed_and_out_of_order_seqs_each_get_their_own_rejected() -> void:
	_h = Harness.new()
	var chaos := _player()
	var seqs: Array[int] = [SEQ, SEQ, SEQ - 1, SEQ, 3]
	for seq: int in seqs:
		var put_down := WireMessage.new(&"PutDown", {"facing": Vector3.FORWARD}, seq)
		assert_int(chaos.send(put_down)).is_equal(OK)
	_h.pump_frames(4)
	var rejected := chaos.named(&"Rejected")
	var echoed: Array[int] = []
	for message: WireMessage in rejected:
		echoed.append(message.fields["seq"] as int)
		# The lobby takes no PutDown (§3.2): the same answer for every copy.
		assert_str(str(message.fields["reason"])).is_equal("not_accepted")
	assert_array(echoed).is_equal(seqs)
	assert_int(_h.own.view.events_named(&"Rejected").size()).is_equal(0)
	assert_int(_h.transport.rejects.total()).is_equal(0)


func test_a_hostile_claim_is_corrected_to_its_sender_alone_and_never_rejected() -> void:
	_h = Harness.new()
	var chaos := _player()
	var welcome := chaos.named(&"Welcome")[0]
	var epoch := welcome.fields["epoch"] as int
	var spot := welcome.fields["spot"] as Vector3
	var own_before := _h.own.view.events.size()
	assert_int(chaos.send(_teleport(epoch, spot))).is_equal(OK)
	_h.pump_frames(4)
	var corrections := chaos.named(&"Correction")
	assert_int(corrections.size()).is_equal(1)
	assert_int(corrections[0].fields["epoch"] as int).is_equal(epoch + 1)
	assert_vector(corrections[0].fields["position"] as Vector3).is_equal(spot)
	assert_int(chaos.named(&"Rejected").size()).is_equal(0)
	assert_vector(_h.session.game.state.player(chaos.peer).position).is_equal(spot)
	# A claim of the old epoch is dropped: no Correction, no Rejected (§7.1).
	assert_int(chaos.send(_teleport(epoch, spot))).is_equal(OK)
	_h.pump_frames(4)
	assert_int(chaos.named(&"Correction").size()).is_equal(1)
	assert_int(chaos.named(&"Rejected").size()).is_equal(0)
	assert_array(_h.own.view.events.slice(own_before)).is_empty()


func test_intents_over_the_budget_get_no_reply_and_no_disconnect() -> void:
	_h = Harness.new()
	var chaos := _player()
	_h.pump_seconds(PeerBudget.INTENTS / PeerBudget.INTENTS_PER_SECOND)
	var over_before := _h.session.over_budget
	for seq in range(1, BURST + 1):
		chaos.send(WireMessage.new(&"ReturnToLobby", {}, ChaosFrames.CHAOS_SEQ + seq))
	_h.pump_frames(4)
	var answered: Array[int] = []
	for message: WireMessage in chaos.named(&"Rejected"):
		answered.append((message.fields["seq"] as int) - ChaosFrames.CHAOS_SEQ)
	var within := int(PeerBudget.INTENTS)
	var expected: Array[int] = []
	for seq in range(1, within + 1):
		expected.append(seq)
	assert_array(answered).is_equal(expected)
	assert_int(_h.session.over_budget - over_before).is_equal(BURST - within)
	assert_bool(chaos.lost).is_false()
	assert_int(_h.session.malformed_disconnects).is_equal(0)


## A raw client that is a player of the lobby, its Welcome decoded.
func _player() -> Harness.RawClient:
	var chaos := _h.raw()
	_h.pump_frames(2)
	assert_int(chaos.hello(_h.session.content_hash)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(chaos.named(&"Welcome").size()).is_equal(1)
	return chaos


func _teleport(epoch: int, spot: Vector3) -> WireMessage:
	var fields := {
		"epoch": epoch,
		"client_tick": 1,
		"position": spot + Vector3(ChaosFrames.TELEPORT_M, 0.0, 0.0),
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": true,
		"on_floor": true,
		"jumps": 0,
		"sprint_ticks": 0,
		"moved_ticks": ChaosFrames.HONEST_MOVED_TICKS,
	}
	return WireMessage.new(&"MoveClaim", fields)
