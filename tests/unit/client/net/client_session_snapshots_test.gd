extends GdUnitTestSuite
## What ClientSession hands to the views of M4-7 (ARCHITECTURE §4.7, Movement on the network):
## every decoded snapshot through `snapshot_received`, older ones included (SnapshotBuffer sorts
## them by host tick), and the count of Corrections it adopted, for the debug overlay: a refused
## claim's apart from a placement's or a knockdown's.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

var _harness: Harness
var _received: Array[Array] = []


func before_test() -> void:
	_harness = Harness.new()
	_received.clear()
	_harness.session.snapshot_received.connect(_on_snapshot)


func after_test() -> void:
	_harness.close()


func test_every_snapshot_is_handed_on_with_its_tick_and_avatars() -> void:
	_harness.welcome(&"lobby", 1)
	_snapshot(7, Vector3(1, 0, 2))
	_snapshot(9, Vector3(2, 0, 2))
	# A late one is handed on too, though the model keeps the newest.
	_snapshot(8, Vector3(3, 0, 2))
	assert_int(_received.size()).is_equal(3)
	assert_array(_received.map(func(entry: Array) -> int: return entry[0])).is_equal([7, 9, 8])
	var late: Dictionary = _received[2][1]
	assert_vector((late[1] as Dictionary)["position"] as Vector3).is_equal(Vector3(3, 0, 2))
	assert_int(_harness.session.model.snapshot_tick).is_equal(9)


func test_corrections_are_counted_and_welcome_is_not_one() -> void:
	_harness.welcome(&"lobby", 1)
	assert_int(_harness.session.corrections).is_equal(0)
	_harness.send(CorrectionEvent.new(_harness.peer, 2, Vector3(4, 0, 4), Vector3.ZERO))
	_harness.pump()
	_harness.send(CorrectionEvent.new(_harness.peer, 3, Vector3(5, 0, 4), Vector3.ZERO))
	_harness.pump()
	assert_int(_harness.session.corrections).is_equal(2)


func test_a_placement_or_a_knockdown_is_not_a_correction() -> void:
	_harness.welcome(&"lobby", 1)
	var session := _harness.session
	var spots: Dictionary[int, Vector3] = {_harness.peer: Vector3(6, 0, 6), 99: Vector3(7, 0, 6)}
	_harness.send(PlayersPlacedEvent.new(spots))
	_harness.send(CorrectionEvent.new(_harness.peer, 2, Vector3(6, 0, 6), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(0)
	assert_int(session.placements).is_equal(1)
	_harness.send(KnockedDownEvent.new(_harness.peer, Vector3(6, 0, 7)))
	_harness.send(CorrectionEvent.new(_harness.peer, 3, Vector3(6, 0, 7), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(0)
	assert_int(session.placements).is_equal(2)
	# A bare Correction after them is a refused claim again, and so is one after a death, which
	# sends no Correction of its own.
	_harness.send(CorrectionEvent.new(_harness.peer, 4, Vector3(6, 0, 8), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(1)
	assert_int(session.placements).is_equal(2)
	_harness.send(DiedEvent.new(_harness.peer, Vector3(6, 0, 8)))
	_harness.send(CorrectionEvent.new(_harness.peer, 5, Vector3(6, 0, 8), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(2)
	assert_int(session.placements).is_equal(2)


func test_a_respawn_is_a_placement_and_a_revive_is_not() -> void:
	# M4-3's respawn sends Respawned, then the respawned player's Correction at the marker; M4-4's
	# revive sends no Correction (the raise held the player in place), so one after it is a
	# refused claim.
	_harness.welcome(&"round", 1)
	var session := _harness.session
	_harness.send(DiedEvent.new(_harness.peer, Vector3(6, 0, 8)))
	_harness.send(RespawnedEvent.new(_harness.peer, Vector3(14, 0, -5)))
	_harness.send(CorrectionEvent.new(_harness.peer, 2, Vector3(14, 0, -5), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(0)
	assert_int(session.placements).is_equal(1)
	_harness.send(RevivedEvent.new(_harness.peer))
	_harness.send(CorrectionEvent.new(_harness.peer, 3, Vector3(14, 0, -4), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(1)
	assert_int(session.placements).is_equal(1)
	# Someone else's respawn leaves the next Correction counted.
	_harness.send(RespawnedEvent.new(99, Vector3(-14, 0, 5)))
	_harness.send(CorrectionEvent.new(_harness.peer, 4, Vector3(14, 0, -4), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(2)


func test_someone_else_placed_or_knocked_down_leaves_the_next_correction_counted() -> void:
	_harness.welcome(&"lobby", 1)
	var session := _harness.session
	var spots: Dictionary[int, Vector3] = {99: Vector3(7, 0, 6)}
	_harness.send(PlayersPlacedEvent.new(spots))
	_harness.send(KnockedDownEvent.new(99, Vector3(7, 0, 6)))
	_harness.send(CorrectionEvent.new(_harness.peer, 2, Vector3(4, 0, 4), Vector3.ZERO))
	_harness.pump()
	assert_int(session.corrections).is_equal(1)
	assert_int(session.placements).is_equal(0)


func _snapshot(tick: int, at: Vector3) -> void:
	var avatar := {
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"downed": false,
		"invulnerable": false,
		"held_item": -1,
	}
	_harness.send_message(WireMessage.new(&"Snapshot", {"tick": tick, "avatars": {1: avatar}}))
	_harness.pump()


func _on_snapshot(tick: int, avatars: Dictionary) -> void:
	_received.append([tick, avatars])
