class_name PeerView
extends RefCounted
## Everything an honest client of one peer can know (ARCHITECTURE §5): its events in order, its
## snapshot for every tick that sent one, and the speakers it may hear per tick. The M3 leak test
## compares what each bot decoded with this; unit tests assert on it.

var peer: int
var events: Array[MatchEvent] = []
## Tick -> the snapshot this peer was entitled to on that tick.
var snapshots: Dictionary[int, Dictionary] = {}
## Tick -> the speakers this peer could hear on that tick, in peer-id order.
var speakers: Dictionary[int, PackedInt32Array] = {}


func _init(peer_id: int) -> void:
	peer = peer_id


## The names of its events, in order.
func event_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for event: MatchEvent in events:
		names.append(event.event_name())
	return names


## Its events of one name, in order.
func events_named(name: StringName) -> Array[MatchEvent]:
	var found: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.event_name() == name:
			found.append(event)
	return found
