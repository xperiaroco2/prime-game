extends RefCounted
## Samples of every wire row for the codec's suites: core/'s own events (so a round trip compares
## with to_dict()), intents as MatchCommand args, the debug command, the snapshot and the voice
## frames. Also the strict comparison the suites use: `==` ignores Variant types (a String equals
## a StringName, a typed Dictionary an untyped one), so same() checks the types as well.

const ID_32 := "abcdefghijklmnopqrstuvwxyz_01234"
## The Hello sample's content hash (§4.3): any 64-bit number; this one needs all 8 bytes.
const CONTENT_HASH := -0x123456789ABCDEF


## One event of every class core/ sends to a peer, keyed by class name (ItemSpawned twice: a knife
## and a package, whose station and colour exist only then).
static func events() -> Dictionary[String, Array]:
	var found: Dictionary[String, Array] = {}
	found["RejectedEvent"] = [RejectedEvent.new(3, 0xFFFFFFFF, &"wrong_version")]
	var welcome := WelcomeEvent.new(3, Vector3(1.5, 0.0, -2.25), 7)
	(
		welcome
		. roster
		. assign(
			[
				{"peer": 1, "name": "Player1", "ready": true},
				{"peer": 3, "name": "Player2", "ready": false},
			]
		)
	)
	welcome.settings = {&"tasks": 2, &"knives": 1, &"match_duration": 600}
	welcome.map = "res://levels/maps/test_map.tscn"
	welcome.phase = &"lobby"
	welcome.positions = {1: Vector3(0.1, 0.2, 0.3)}
	found["WelcomeEvent"] = [welcome]
	found["PlayerJoinedEvent"] = [PlayerJoinedEvent.new(0x7FFFFFFF, "Player12", Vector3.ONE)]
	found["PlayerLeftEvent"] = [PlayerLeftEvent.new(5)]
	found["ReadyChangedEvent"] = [ReadyChangedEvent.new(5, true)]
	found["SettingsChangedEvent"] = [_settings_changed()]
	found["PhaseChangedEvent"] = [
		PhaseChangedEvent.new(&"countdown", 4096), PhaseChangedEvent.new(&"end", -1)
	]
	found["CountdownCancelledEvent"] = [CountdownCancelledEvent.new(CountdownCancelledEvent.JOIN)]
	var spots: Dictionary[int, Vector3] = {9: Vector3(1, 2, 3), 2: Vector3(-1, 0, 4)}
	found["PlayersPlacedEvent"] = [PlayersPlacedEvent.new(spots)]
	var numbers: Dictionary[StringName, int] = {&"tasks": 3, &"knives": -2}
	found["LoadMatchEvent"] = [
		LoadMatchEvent.new(0xFFFFFFFF, "res://levels/maps/a-b.c.tscn", numbers)
	]
	found["PlayerLoadedEvent"] = [PlayerLoadedEvent.new(2)]
	found["RoundStartedEvent"] = [RoundStartedEvent.new(1234)]
	found["RoleAssignedEvent"] = [RoleAssignedEvent.new(2, &"dissident")]
	found["TeammatesEvent"] = [TeammatesEvent.new(&"dissident", PackedInt32Array([4, 2]))]
	found["StationPlacedEvent"] = [
		StationPlacedEvent.new(0, &"circle", Color(0.9, 0.1, 0.2, 1.0), Vector3(3, 0, 3))
	]
	found["ItemSpawnedEvent"] = [
		ItemSpawnedEvent.new(1, &"knife", Vector3(0, 1, 0)),
		ItemSpawnedEvent.new(0xFFFE, &"package", Vector3(2, 1, 0), 0xFFFE, Color.RED),
	]
	found["ItemPickedUpEvent"] = [ItemPickedUpEvent.new(2, 1)]
	found["ItemPlacedEvent"] = [ItemPlacedEvent.new(1, Vector3(0.5, 0.05, 0.5), &"put_down")]
	found["PackageDeliveredEvent"] = [PackageDeliveredEvent.new(3, 1)]
	found["TaskProgressEvent"] = [TaskProgressEvent.new(2, 0xFFFF)]
	found["SwungEvent"] = [SwungEvent.new(2, Vector3(0.6, 0, -0.8))]
	found["DamagedEvent"] = [DamagedEvent.new(2, 250, -0x80000000)]
	found["SelfStatusEvent"] = [SelfStatusEvent.new(2, 1000, 0x7FFFFFFF, false)]
	found["DiedEvent"] = [DiedEvent.new(2, Vector3(4, 0, 4))]
	found["KnockedDownEvent"] = [KnockedDownEvent.new(0xFFFE, Vector3(-2, 0.5, 3))]
	found["CorrectionEvent"] = [CorrectionEvent.new(2, 3, Vector3(1, 0, 1), Vector3(-0.0, 0, 5))]
	found["MatchEndedEvent"] = [MatchEndedEvent.new(&"crew")]
	found["DisconnectingEvent"] = [DisconnectingEvent.new(2, DisconnectingEvent.LOAD_DEADLINE)]
	return found


## Every intent as a client sends it: the args of its MatchCommand, and its seq.
static func intents() -> Array[WireMessage]:
	var settings := {&"tasks": 3, &"banned_task_types": PackedStringArray(["delivery"])}
	return [
		WireMessage.new(&"Hello", {"version": WireSchema.VERSION, "content": CONTENT_HASH}),
		WireMessage.new(&"SetReady", {"ready": true}, 7),
		WireMessage.new(&"ChangeSettings", {"settings": settings}, 8),
		WireMessage.new(
			&"ChangeSettings", {"settings": {}, "map": "res://levels/maps/test_map.tscn"}, 9
		),
		WireMessage.new(&"LoadAck", {"match_id": 2}, 10),
		WireMessage.new(&"MoveClaim", _claim()),
		WireMessage.new(&"PickUp", {"item": 0}, 11),
		WireMessage.new(&"PutDown", {"facing": Vector3(0, 0, -1)}, 12),
		WireMessage.new(&"Use", {"facing": Vector3.ZERO}, 0xFFFFFFFF),
		WireMessage.new(&"ReturnToLobby", {}, 13),
	]


## ForceRole and ForceClock, which only a debug build's table has: set, then cleared.
static func debug_commands() -> Array[WireMessage]:
	return [
		WireMessage.new(&"ForceRole", {"role": "dissident"}, 1, 3),
		WireMessage.new(&"ForceRole", {"role": ""}, 2, 3),
		WireMessage.new(&"ForceClock", {"seconds": 40}, 3, 1),
		WireMessage.new(&"ForceClock", {"seconds": 0}, 0xFFFFFFFF, 0x7FFFFFFF),
	]


## A snapshot in the shape of Snapshots.for_peer's avatars, and the two voice frames.
static func state_and_voice() -> Array[WireMessage]:
	var avatars := {
		2: _avatar(Vector3(1, 0, 1), false, false, -1),
		5: _avatar(Vector3(-3, 1.5, 0), true, false, 0xFFFE),
		7: _avatar(Vector3(4, 0, -4), false, true, 3),
	}
	var frame := PackedByteArray()
	frame.resize(WireSchema.MAX_OPUS)
	frame.fill(0xFC)
	return [
		WireMessage.new(&"Snapshot", {"tick": 99, "avatars": avatars}),
		WireMessage.new(&"Snapshot", {"tick": 0, "avatars": {}}),
		WireMessage.new(&"VoiceUp", {"seq": 0xFFFF, "opus": PackedByteArray([1])}),
		WireMessage.new(&"VoiceDown", {"speaker": 4, "seq": 0, "tick": 7, "opus": frame}),
	]


## Every sample as a message: the events by their name and to_dict().
static func all_messages() -> Array[WireMessage]:
	var found: Array[WireMessage] = []
	for samples: Array in events().values():
		for event: MatchEvent in samples:
			found.append(WireMessage.new(event.event_name(), event.to_dict()))
	found.append_array(intents())
	found.append_array(debug_commands())
	found.append_array(state_and_voice())
	return found


## Equal, with the same Variant types all the way down, typed containers typed alike.
static func same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			return _same_dictionaries(a as Dictionary, b as Dictionary)
		TYPE_ARRAY:
			return _same_arrays(a as Array, b as Array)
	return a == b


static func _same_dictionaries(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	if a.get_typed_key_builtin() != b.get_typed_key_builtin():
		return false
	if a.get_typed_value_builtin() != b.get_typed_value_builtin():
		return false
	for key: Variant in a:
		var match_key: Variant = null
		for other: Variant in b:
			if same(key, other):
				match_key = other
		if match_key == null or not same(a[key], b[match_key]):
			return false
	return true


static func _same_arrays(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.get_typed_builtin() != b.get_typed_builtin():
		return false
	for i: int in a.size():
		if not same(a[i], b[i]):
			return false
	return true


static func _settings_changed() -> SettingsChangedEvent:
	var demands := Demands.new(null)
	demands.add_markers(&"circle", 3)
	demands.add_markers(&"player", 10)
	demands.markers[&"package"] = 3
	demands.colours[&"circle"] = 3
	demands.palettes[&"circle"] = 8
	var layout := LevelLayout.new("res://levels/maps/test_map.tscn")
	layout.add_marker(&"circle", Vector3.ZERO)
	var numbers: Dictionary[StringName, int] = {&"tasks": 1, &"knives": 2}
	var sets: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["delivery", ID_32])
	}
	var problems := PackedStringArray(
		["3 circle marker(s) needed, the map has 1", "11 player(s), the mode plays with 4 to 10"]
	)
	return SettingsChangedEvent.new(
		numbers, "res://levels/maps/test_map.tscn", 11, demands, layout, problems, sets
	)


static func _claim() -> Dictionary:
	return {
		"epoch": 4,
		"client_tick": 0xFFFFFFFF,
		"position": Vector3(1.25, 0, -7),
		"velocity": Vector3(0, -9.8, 0),
		"facing": Vector3(0, 0, -1),
		"sprint": true,
		"moving": false,
		"on_floor": true,
		"jumps": 0xFFFF,
	}


static func _avatar(at: Vector3, downed: bool, held: int) -> Dictionary:
	return {
		"position": at,
		"velocity": Vector3(0.5, 0, 0),
		"facing": Vector3(1, 0, 0),
		"downed": downed,
		"held_item": held,
	}
