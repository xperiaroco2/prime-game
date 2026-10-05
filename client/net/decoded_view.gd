class_name DecodedView
extends RefCounted
## Everything one client decoded (ARCHITECTURE §4.6), shaped like core/'s PeerView so the leak test
## can compare the two: the events in order as (name, fields), each fields Dictionary equal to the
## event's to_dict(); the snapshots by tick (a second one of a tick kept apart, never overwriting
## the first); the voice frames and their seqs by speaker and tick, each frame of a VoiceBatch as
## the VoiceDown it stands for (voice_downs()). A record only: ClientModel folds the same messages
## into what the client knows now.

const SNAPSHOT := &"Snapshot"
## The wire's batched voice row (M5-4b), and the name of each frame in it once decoded: no row
## carries a VoiceDown since protocol 8.
const VOICE_BATCH := &"VoiceBatch"
const VOICE_DOWN := &"VoiceDown"

## The client's peer id once it was welcomed; 0 before.
var peer := 0
## The events in the order they arrived: each a WireMessage whose name is the event's and whose
## fields equal its to_dict().
var events: Array[WireMessage] = []
## Tick -> the first decoded snapshot of that tick, {tick, avatars} (§4.4).
var snapshots: Dictionary[int, Dictionary] = {}
## Every later snapshot of a tick already in `snapshots`, in arrival order: the host sends one per
## tick, so the leak test fails on any (none overwrites the first).
var repeated_snapshots: Array[Dictionary] = []
## Vector2i(speaker, tick) -> the Opus bytes of that speaker's frames relayed under that tick, in
## the order they arrived.
var voice: Dictionary[Vector2i, Array] = {}
## Vector2i(speaker, tick) -> the seq of each of those frames, in the same order.
var voice_seqs: Dictionary[Vector2i, PackedInt32Array] = {}
## VoiceBatch messages decoded, and those that held no frame (the host never sends one: the leak
## test fails on any).
var voice_batches := 0
var empty_batches := 0


## The frames of a decoded VoiceBatch, in its order, each as a VoiceDown of its speaker, seq, the
## batch's tick and the bytes.
static func voice_downs(batch: WireMessage) -> Array[WireMessage]:
	var found: Array[WireMessage] = []
	var at_tick := batch.fields["tick"] as int
	for frame: Dictionary in batch.fields["frames"] as Array:
		var fields := {
			"speaker": frame["speaker"] as int,
			"seq": frame["seq"] as int,
			"tick": at_tick,
			"opus": frame["opus"] as PackedByteArray,
		}
		found.append(WireMessage.new(VOICE_DOWN, fields))
	return found


func record(message: WireMessage) -> void:
	if message.name == SNAPSHOT:
		var at_tick := message.fields["tick"] as int
		if snapshots.has(at_tick):
			repeated_snapshots.append(message.fields)
		else:
			snapshots[at_tick] = message.fields
	elif message.name == VOICE_BATCH:
		voice_batches += 1
		var downs := voice_downs(message)
		if downs.is_empty():
			empty_batches += 1
		for down: WireMessage in downs:
			record(down)
	elif message.name == VOICE_DOWN:
		var key := Vector2i(message.fields["speaker"] as int, message.fields["tick"] as int)
		if not voice.has(key):
			voice[key] = []
		voice[key].append(message.fields["opus"])
		# A packed array is a value: append to a copy and store it back.
		var seqs: PackedInt32Array = voice_seqs.get(key, PackedInt32Array())
		seqs.append(message.fields["seq"] as int)
		voice_seqs[key] = seqs
	else:
		events.append(message)


## The names of its events, in order.
func event_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for event: WireMessage in events:
		names.append(event.name)
	return names


## Its events of one name, in order.
func events_named(event_name: StringName) -> Array[WireMessage]:
	var found: Array[WireMessage] = []
	for event: WireMessage in events:
		if event.name == event_name:
			found.append(event)
	return found


## Tick -> the speakers it decoded a frame of under that tick, in peer-id order: the shape of
## PeerView.speakers, which the leak test compares it with as a subset.
func speakers() -> Dictionary[int, PackedInt32Array]:
	var found: Dictionary[int, PackedInt32Array] = {}
	for key: Vector2i in voice:
		var of_tick: PackedInt32Array = found.get(key.y, PackedInt32Array())
		of_tick.append(key.x)
		of_tick.sort()
		found[key.y] = of_tick
	return found


## The Opus bytes of one speaker's frames under one tick, in arrival order.
func frames(speaker: int, tick: int) -> Array[PackedByteArray]:
	var found: Array[PackedByteArray] = []
	found.assign(voice.get(Vector2i(speaker, tick), []) as Array)
	return found
