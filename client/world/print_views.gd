class_name PrintViews
extends Node3D
## The print of a respawn on this client (#1489; the plainest placeholder, no art exists yet): a
## PrintStarted puts a grey box over the marker, the drone, and the printed player's own avatar
## grows from the feet up over print_ms. Respawned, the printed player's leaving, the print's time
## running out or any change of phase (a match ending during a print sends no Respawned) ends it.
## No sound and no UI.

## How high over the marker the drone hovers, and its size (a placeholder, "not a decision").
const DRONE_HEIGHT_M := 2.6
const DRONE_SIZE := Vector3(0.6, 0.15, 0.6)
const DRONE_COLOUR := Color(0.55, 0.55, 0.6)
## The smallest height of an avatar being printed, so that its mesh stays a valid transform.
const FIRST_HEIGHT := 0.02

## The avatars the print grows, or null (the print is then the drone alone).
var avatars: AvatarViews

var _runs: Dictionary[int, Run] = {}


## One print under way.
class Run:
	var drone: MeshInstance3D
	var left_s := 0.0
	var total_s := 0.0


## The session's events (ClientSession.event_received, after the model folded each).
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"PrintStarted":
		_start(fields["peer"] as int, fields["position"] as Vector3, fields["print_ms"] as int)
	elif event_name == &"Respawned" or event_name == &"PlayerLeft":
		_end(fields["peer"] as int)
	elif event_name == &"PhaseChanged":
		clear()


func count() -> int:
	return _runs.size()


func clear() -> void:
	for peer: int in _runs.keys():
		_end(peer)


func _start(peer: int, at: Vector3, print_ms: int) -> void:
	_end(peer)
	var run := Run.new()
	run.total_s = maxf(print_ms / 1000.0, 0.001)
	run.left_s = run.total_s
	run.drone = _make_drone(at)
	add_child(run.drone)
	_runs[peer] = run


func _end(peer: int) -> void:
	if not _runs.has(peer):
		return
	_runs[peer].drone.queue_free()
	_runs.erase(peer)
	_scale_avatar(peer, 1.0)


func _process(delta: float) -> void:
	for peer: int in _runs.keys():
		var run := _runs[peer]
		run.left_s = maxf(run.left_s - delta, 0.0)
		if run.left_s <= 0.0:
			_end(peer)
		else:
			_scale_avatar(peer, maxf(1.0 - run.left_s / run.total_s, FIRST_HEIGHT))


func _scale_avatar(peer: int, height: float) -> void:
	var body := avatars.body_of(peer) if avatars != null else null
	if body != null:
		body.set_print_height(height)


static func _make_drone(at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = DRONE_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = DRONE_COLOUR
	mesh.material = material
	var drone := MeshInstance3D.new()
	drone.mesh = mesh
	drone.position = at + Vector3.UP * DRONE_HEIGHT_M
	return drone
