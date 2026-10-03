extends Node3D
## A listener's world for the VoiceViews suites: the base mode's own copy, a hand-folded
## ClientModel (the own peer and two others in the roster, in the lobby), AvatarViews drawing the
## others' RemotePlayerBodies from snapshots fed here, VoiceViews over them with the fake codec,
## and the ears at a point a test moves. A Camera3D far away: Godot mixes a 3D player only while
## the world has a camera, and measures the distance from the current AudioListener3D (the ears),
## which this world adds and makes current at `ears_at`. A suite adds one in `before_test()` and
## frees it in `after_test()`. `add_box()` puts a fixture wall (or a stand-in capsule on another
## layer) in its physics space, for the occlusion ray (M5-7).

const MODE := "res://content/modes/base_mode.tres"
const OWN := 1
const TALKER := 2
const OTHER := 3
const TICK_USEC := 50000

var mode: GameMode
var model: ClientModel
var avatars: AvatarViews
var voices: VoiceViews
var codec := FakeVoiceCodec.new()
var listener := AudioListener3D.new()
## Where the ears are; tests move it.
var ears_at := Vector3.ZERO
## The avatars' clock and the next snapshot's tick.
var avatar_now := 1000000
var next_tick := 1
## The voices' clock, unless a test gives it the real one (`real_clock`).
var voice_now := 1000000
var real_clock := false
## The next seq of each speaker.
var seqs: Dictionary[int, int] = {}


func _ready() -> void:
	mode = load(MODE) as GameMode
	model = ClientModel.new(mode)
	model.own_peer = OWN
	for peer: int in [OWN, TALKER, OTHER]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		model.roster[peer] = member
	model.phase = &"lobby"
	var camera := Camera3D.new()
	camera.name = "FarCamera"
	camera.position = Vector3(0.0, 50.0, 0.0)
	add_child(camera)
	listener.name = "Ears"
	add_child(listener)
	listener.make_current()
	avatars = AvatarViews.new()
	avatars.model = model
	avatars.buffer = SnapshotBuffer.new()
	avatars.rules = mode.player_rules
	avatars.clock = func() -> int: return avatar_now
	add_child(avatars)
	voices = VoiceViews.new()
	voices.model = model
	voices.mode = mode
	voices.avatars = avatars
	voices.codec = codec
	voices.ears = func() -> Variant: return ears_at
	voices.clock = func() -> int: return Time.get_ticks_usec() if real_clock else voice_now
	add_child(voices)
	voices.on_event(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})


func _physics_process(_delta: float) -> void:
	listener.global_position = ears_at


## Snapshots putting the others at `at` (peer -> feet), until the interpolated poses are there.
func place(at: Dictionary[int, Vector3]) -> void:
	for i: int in 3:
		avatar_now += TICK_USEC
		var avatar_fields := {}
		for peer: int in at:
			avatar_fields[peer] = {
				"position": at[peer],
				"velocity": Vector3.ZERO,
				"facing": Vector3.FORWARD,
				"downed": false,
				"held_item": -1,
			}
		model.fold_snapshot({"tick": next_tick, "avatars": avatar_fields})
		avatars.buffer.add(next_tick, avatar_fields, avatar_now)
		voices.on_snapshot(next_tick, avatar_fields)
		next_tick += 1
	avatar_now += TICK_USEC * 10


## A host event: folded into the model, then handed to the voices, as ClientSession does.
func event(event_name: StringName, fields: Dictionary) -> void:
	model.fold(event_name, fields)
	voices.on_event(event_name, fields)


## `count` frames of `peer` stamped at host tick `tick`, each a 20 ms sine of `amplitude`.
func speak(peer: int, count: int, tick: int, amplitude := 0.5) -> void:
	for i: int in count:
		var seq: int = seqs.get(peer, 0)
		seqs[peer] = seq + 1
		voices.on_voice(peer, seq & 0xFFFF, tick, sine(seq, amplitude))


## A box of `size` centred at `at` on physics layer `layer` (the level's by default), in this
## world's space; freed with the world.
func add_box(at: Vector3, size: Vector3, layer := PhysicsLayers.WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Box"
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


## One fake-codec frame (160 µ-law bytes at 8 kHz) of a 400 Hz sine, continuing over seqs.
static func sine(seq: int, amplitude: float) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(FakeVoiceCodec.FRAME_SAMPLES)
	for i: int in FakeVoiceCodec.FRAME_SAMPLES:
		var n := seq * FakeVoiceCodec.FRAME_SAMPLES + i
		frame[i] = FakeMuLaw.encode_sample(amplitude * sin(TAU * 400.0 * n / FakeVoiceCodec.RATE))
	return frame
