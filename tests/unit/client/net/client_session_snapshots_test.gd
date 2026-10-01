extends GdUnitTestSuite
## What ClientSession hands to the views of M4-7 (ARCHITECTURE §4.7, Movement on the network):
## every decoded snapshot through `snapshot_received`, older ones included (SnapshotBuffer sorts
## them by host tick), and the count of Corrections it adopted, for the debug overlay.

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


func _snapshot(tick: int, at: Vector3) -> void:
	var avatar := {
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"ghost": false,
		"held_item": -1,
	}
	_harness.send_message(WireMessage.new(&"Snapshot", {"tick": tick, "avatars": {1: avatar}}))
	_harness.pump()


func _on_snapshot(tick: int, avatars: Dictionary) -> void:
	_received.append([tick, avatars])
