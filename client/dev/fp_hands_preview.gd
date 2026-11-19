extends Node3D
## A preview of the first-person hands (#1587, ARCHITECTURE §4.7.69) for `tools\run.cmd shot`: the
## eye in the ship's hall (the estate's ship room, read only) on the engine console's use spot,
## looking at the console, with FpHands under a live camera and FpView over the view, as the
## controller puts them, in body colour `colour` (BodyColours; -1: the package's default,
## FpHands.DEFAULT_TINT). `state` picks the frame: "idle",
## "run" (a quarter into its cycle), "punch" (at its contact, 0.15 s), "crystal" (a charged crystal
## held, a second into Crystal_Idle) or "crystal_hit" (at its contact, 0.18 s). Each clip is
## seeked and paused, so the still does not depend on the frame rate. Dev only.

const ROOM := "res://levels/estate/rooms/ship.tscn"
const CONSOLE := "StartConsole01"
## The eye: this far in front of the console, at this height over its deck.
const EYE_OUT_M := 1.1
const EYE_UP_M := 1.62
## The point looked at, over the console's foot.
const LOOK_UP_M := 1.0
## The player camera's own field of view (client/player/player.tscn: Camera3D's default).
const FOV_DEG := 75.0
## Each state: [clip, seconds into it].
const STATES := {
	"idle": [&"Idle", 1.0],
	"run": [&"Run", 0.23],
	"punch": [&"Punch", 0.15],
	"crystal": [&"Crystal_Idle", 1.0],
	"crystal_hit": [&"Crystal_Hit", 0.18],
}

@export var state := "idle"
@export var colour := 1


func _ready() -> void:
	var room := (load(ROOM) as PackedScene).instantiate() as Node3D
	room.name = "Level"
	add_child(room)
	FpView.light_level(room)
	_build_sky()
	var console := room.find_child(CONSOLE, true, false) as Node3D
	var at := console.global_position if console != null else Vector3.ZERO
	var out := console.global_basis.z if console != null else Vector3.BACK
	var camera := Camera3D.new()
	camera.fov = FOV_DEG
	camera.cull_mask = PhotoLayers.LIVE_VIEW
	add_child(camera)
	camera.look_at_from_position(
		at + out * EYE_OUT_M + Vector3.UP * EYE_UP_M, at + Vector3.UP * LOOK_UP_M
	)
	camera.current = true
	var hand := FirstPersonHand.new()
	camera.add_child(hand)
	var hands := FpHands.new()
	hands.attach(self, camera, hand)
	if colour >= 0:
		hands.set_tint(BodyColours.of(colour))
	if state.begins_with("crystal"):
		hands.set_held(&"crystal_charged")
	if hands.player == null:
		return
	var pose: Array = STATES.get(state, STATES["idle"])
	hands.player.play(pose[0] as StringName)
	hands.player.seek(pose[1] as float, true)
	hands.player.pause()


func _build_sky() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.09, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.3, 0.3, 0.34)
	environment.environment.glow_enabled = true
	add_child(environment)
