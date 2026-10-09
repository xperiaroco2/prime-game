extends GdUnitTestSuite
## The tutorial's stand-ins (client/tutorial/stand_ins.gd, docs/design/tutorial.md §2.2, #601) on
## a HostNode of the tutorial mode over a LoopbackHub, beside an own client, on a simulated clock:
## what the host receives from each stand-in is its Hello with no name, one SetReady, one LoadAck
## and claims standing still where it was placed, and nothing else; leaving the tree leaves.

const MODE := "res://content/modes/tutorial_mode.tres"
const PORT := 7310
## The simulated clock moves this much per physics frame (five host ticks), as in game_loop_test.
const STEP_USEC := 250000
const MAX_FRAMES := 600
const HOLD_FRAMES := 30
## What a stand-in may send.
const ALLOWED: Array[StringName] = [
	&"Hello", &"SetReady", &"LoadAck", &"MoveClaim", WireSchema.RELIABLE_CLAIM
]

var _now := 1000000
var _schema := WireSchema.game(OS.is_debug_build())
var _own: ClientSession
## Per peer, every message name the host received from it, in order.
var _sent: Dictionary[int, Array] = {}
## Per peer, the Hello it sent.
var _hellos: Dictionary[int, WireMessage] = {}
## Per peer, the claims it sent once the own client was in a lesson phase.
var _claims: Dictionary[int, Array] = {}
var _left: Array[int] = []


func before_test() -> void:
	_now = 1000000
	_sent.clear()
	_hellos.clear()
	_claims.clear()
	_left.clear()


func test_each_stand_in_joins_readies_acknowledges_and_stands_and_sends_nothing_else() -> void:
	var mode := load(MODE) as GameMode
	var hub := LoopbackHub.new()
	var transport := LoopbackTransport.new(_schema.kind_table(), hub)
	transport.packet_received.connect(_on_packet)
	transport.peer_left.connect(func(peer: int) -> void: _left.append(peer))
	var host := HostNode.host(transport, mode, PORT, _clock)
	assert_bool(host.is_running()).is_true()
	host.skip_replay()
	add_child(host)
	auto_free(host)
	_own = ClientSession.new(host.own_client, mode, _schema)
	_own.load_levels = false
	_own.welcomed.connect(func(_peer: int) -> void: _own.send_intent(&"SetReady", {"ready": true}))
	var own_node := SessionNode.new(_own)
	own_node.real_clock = _clock
	add_child(own_node)
	auto_free(own_node)
	var stand_ins := StandIns.new(hub, mode, PORT, _clock, _schema)
	add_child(stand_ins)
	auto_free(stand_ins)
	assert_int(stand_ins.count()).is_equal(2)
	# As GameTutorial does: they join once the own player is in, and a second call does nothing.
	assert_bool(await _until(func() -> bool: return _own.is_welcomed())).is_true()
	stand_ins.join_host()
	stand_ins.join_host()
	assert_bool(await _until(func() -> bool: return _own.model.phase == &"lessons")).is_true()
	for i in HOLD_FRAMES:
		_now += STEP_USEC
		await get_tree().physics_frame
	assert_int(stand_ins.welcomed()).is_equal(2)
	assert_int(_own.model.own_peer).is_equal(NetTransport.HOST_ID)
	assert_array(_sent.keys()).contains_exactly_in_any_order([1, 2, 3])
	var names := PackedStringArray()
	for peer: int in [2, 3]:
		var sent: Array = _sent[peer]
		for name: StringName in sent:
			var said := "%d sent %s" % [peer, name]
			assert_bool(ALLOWED.has(name)).override_failure_message(said).is_true()
		assert_int(sent.count(&"Hello")).is_equal(1)
		assert_int(sent.count(&"SetReady")).is_equal(1)
		assert_int(sent.count(&"LoadAck")).is_equal(1)
		# #550's "no name": the host's default for a joiner applies (D35 (a)).
		assert_str(str(_hellos[peer].fields.get("name", ""))).is_empty()
		var member: ClientModel.Member = _own.model.roster.get(peer)
		assert_object(member).is_not_null()
		assert_str(member.name).is_not_empty()
		names.append(member.name)
		# Standing still where it was placed: claims in the lesson, all at one spot, at rest.
		var claims: Array = _claims[peer]
		assert_int(claims.size()).is_greater(3)
		for claim: Dictionary in claims:
			assert_vector(claim["position"] as Vector3).is_equal(claims[0]["position"] as Vector3)
			assert_vector(claim["velocity"] as Vector3).is_equal(Vector3.ZERO)
			assert_bool(claim["moving"] as bool).is_false()
			assert_bool(claim["on_floor"] as bool).is_true()
	# The host's join count names them after the own player (design §2.2, #550's fallback).
	assert_array(names).contains_exactly(["Player2", "Player3"])
	assert_int(stand_ins.corrections()).is_equal(0)
	# The first stage downs the first stand-in; it goes on standing, and nobody is refused.
	_own.send_intent(&"NextStage")
	assert_bool(await _until(func() -> bool: return _own.model.phase == &"raise_stage")).is_true()
	assert_int(_own.model.life_of(2)).is_equal(ClientModel.Life.DOWNED)
	for i in HOLD_FRAMES:
		_now += STEP_USEC
		await get_tree().physics_frame
	assert_int(stand_ins.corrections()).is_equal(0)
	assert_int(_sent[2].count(&"SetReady") + _sent[3].count(&"SetReady")).is_equal(2)
	# Leaving the tree leaves both sessions: the host sees them go.
	remove_child(stand_ins)
	assert_int(stand_ins.welcomed()).is_equal(0)
	assert_bool(await _until(func() -> bool: return _left.size() == 2)).is_true()
	assert_array(_left).contains_exactly_in_any_order([2, 3])


func _on_packet(from_peer: int, kind: int, payload: PackedByteArray) -> void:
	var message := _schema.decode(kind, payload)
	if message == null:
		return
	if not _sent.has(from_peer):
		_sent[from_peer] = []
		_claims[from_peer] = []
	_sent[from_peer].append(message.name)
	if message.name == &"Hello":
		_hellos[from_peer] = message
	var claim := message.name == &"MoveClaim" or message.name == WireSchema.RELIABLE_CLAIM
	if claim and _own != null and _own.model.phase == &"lessons":
		_claims[from_peer].append(message.fields)


func _clock() -> int:
	return _now


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()
