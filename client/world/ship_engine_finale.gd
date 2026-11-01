class_name ShipEngineFinale
extends Node3D
## The ship engine's finish (GDD §8, #1502; ARCHITECTURE §9.5.27): when the engine's last stage
## passes (ShipEngineViews' `finished`, the roar's moment, on every peer alike from the filtered
## ZoneProgress), the art ship's nozzles throw a flame and a light show plays over the hologram,
## for as long as the round lingers before End (§3.4). It only draws: nothing reads it, so it never
## delays or changes the End, whose black screen covers whatever is left of it.
## - Flames: per nozzle pod of the level (a Node3D named `nozzle_pod_*`, the art ship's, #1499), an
##   orange cone and a pale core from the pod's mouth along its exhaust axis, with an orange light;
##   they grow, flicker (a sum of sines of the time: no randomness) and fade. A level with no pods
##   (the greybox, a test) shows the light show alone.
## - The light show: SHOW_LIGHTS coloured lights, each with a small glowing ball, circling over the
##   hologram's centre, pulsing, after a white flash.
## Every size, colour, count and rate is a placeholder, "not a decision" (the engineer sizes it in a
## playtest; taken under the standing word of #507).

## The finish's seconds when the mode's Round gives no linger (not a decision).
const DEFAULT_SECONDS := 4.0
## The pod's local axis the exhaust leaves along (the art's pods face the ship's stern on +Z).
const EXHAUST_AXIS := Vector3(0, 0, 1)
## The flame's length and its width at the mouth, in metres (not a decision).
const FLAME_M := 6.0
const FLAME_RADIUS_M := 0.55
## The core's share of the flame's length and width.
const CORE_SHARE := 0.6
const GROW_SECONDS := 0.4
const FADE_SECONDS := 0.6
const FLAME := Color(1.0, 0.45, 0.1, 0.75)
const CORE := Color(1.0, 0.93, 0.6, 0.9)
const FLAME_LIGHT_ENERGY := 4.0
const FLAME_LIGHT_RANGE_M := 8.0
## The show: its lights, their circle's radius and height over the hologram's centre, one turn's
## seconds, the pulse's rate and the white flash's seconds (not a decision).
const SHOW_LIGHTS := 4
const SHOW_RADIUS_M := 3.0
const SHOW_HEIGHT_M := 2.5
const TURN_SECONDS := 2.0
const PULSE_HZ := 4.0
const FLASH_SECONDS := 0.15
const SHOW_ENERGY := 3.0
const SHOW_RANGE_M := 10.0
const BALL_M := 0.25
const PALETTE: Array[Color] = [
	Color(0.2, 0.6, 1.0), Color(1.0, 0.25, 0.7), Color(0.3, 1.0, 0.4), Color(1.0, 0.85, 0.2)
]

var _playing := false
var _elapsed := 0.0
var _seconds := DEFAULT_SECONDS
var _centre := Vector3.ZERO
## Per nozzle: its mouth and exhaust direction (global), its flame, core and light.
var _mouths: Array[Transform3D] = []
var _flames: Array[MeshInstance3D] = []
var _cores: Array[MeshInstance3D] = []
var _flame_lights: Array[OmniLight3D] = []
var _show: Array[OmniLight3D] = []


## The mouth of each nozzle pod under `level`, in name order: origin the far end of the pod (its
## `pod_bell`'s box, else the pod's own meshes) along its exhaust axis, basis.z that axis (global).
static func nozzles_of(level: Node) -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	if level == null or not is_instance_valid(level):
		return found
	var pods: Array[Node3D] = []
	for child: Node in level.find_children("nozzle_pod_*", "Node3D", true, false):
		pods.append(child as Node3D)
	pods.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	for pod: Node3D in pods:
		var axis := (pod.global_basis * EXHAUST_AXIS).normalized()
		var reach := 0.0
		var bell := pod.find_child("pod_bell", true, false)
		var root: Node = bell if bell != null else pod
		for node: Node in [root] + root.find_children("*", "MeshInstance3D", true, false):
			if node is MeshInstance3D:
				reach = maxf(reach, _reach(node as MeshInstance3D, pod.global_position, axis))
		var mouth := pod.global_position + axis * reach
		found.append(Transform3D(_basis_along(axis), mouth))
	return found


## The finish's seconds: the Round's linger in the client's copy of the mode (RoundPhase), so one
## number drives both; DEFAULT_SECONDS when it gives none.
static func seconds_of(mode: GameMode) -> float:
	if mode != null:
		for spec: PhaseSpec in mode.phases:
			if spec.phase_class == RoundPhase:
				var seconds := RoundPhase.linger_seconds_of(spec)
				if seconds > 0.0:
					return seconds
	return DEFAULT_SECONDS


## Starts the finish over the hologram's `centre`, from `nozzles` (nozzles_of()), for `seconds`.
func start(centre: Vector3, nozzles: Array[Transform3D], seconds: float) -> void:
	stop()
	_playing = true
	_elapsed = 0.0
	_seconds = maxf(seconds, GROW_SECONDS + FADE_SECONDS)
	_centre = centre
	_mouths = nozzles.duplicate()
	for mouth: Transform3D in _mouths:
		_flames.append(_cone(FLAME, FLAME_RADIUS_M))
		_cores.append(_cone(CORE, FLAME_RADIUS_M * CORE_SHARE))
		var light := OmniLight3D.new()
		light.light_color = FLAME
		light.omni_range = FLAME_LIGHT_RANGE_M
		light.position = mouth.origin + mouth.basis.z * 1.0
		add_child(light)
		_flame_lights.append(light)
	for i in SHOW_LIGHTS:
		var light := OmniLight3D.new()
		light.omni_range = SHOW_RANGE_M
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = BALL_M
		sphere.height = BALL_M * 2.0
		ball.mesh = sphere
		ball.material_override = _material(Color.WHITE)
		light.add_child(ball)
		add_child(light)
		_show.append(light)
	update(0.0)


## Advances the finish by the frame's `delta`; frees it all once its seconds have run.
func update(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if _elapsed >= _seconds:
		stop()
		return
	var strength := clampf(_elapsed / GROW_SECONDS, 0.0, 1.0)
	strength *= clampf((_seconds - _elapsed) / FADE_SECONDS, 0.0, 1.0)
	for i in _mouths.size():
		var flicker := 1.0 + 0.12 * sin(_elapsed * 31.0 + i * 2.1) + 0.08 * sin(_elapsed * 53.0 + i)
		var length := FLAME_M * strength * flicker
		_place_cone(_flames[i], _mouths[i], length)
		_place_cone(_cores[i], _mouths[i], length * CORE_SHARE)
		_flame_lights[i].light_energy = FLAME_LIGHT_ENERGY * strength * flicker
	var flash := _elapsed < FLASH_SECONDS
	for i in _show.size():
		var light := _show[i]
		var angle := TAU * (_elapsed / TURN_SECONDS + float(i) / _show.size())
		light.position = (
			_centre
			+ Vector3(cos(angle), 0.0, sin(angle)) * SHOW_RADIUS_M
			+ Vector3.UP * SHOW_HEIGHT_M
		)
		var colour := Color.WHITE if flash else PALETTE[(i + floori(_elapsed)) % PALETTE.size()]
		var pulse := 0.6 + 0.4 * sin(TAU * PULSE_HZ * _elapsed + i)
		light.light_color = colour
		light.light_energy = SHOW_ENERGY * pulse * (2.0 if flash else 1.0) * maxf(strength, 0.2)
		var ball := light.get_child(0) as MeshInstance3D
		(ball.material_override as StandardMaterial3D).albedo_color = colour


## Ends the finish at once and frees its parts.
func stop() -> void:
	_playing = false
	for child: Node in get_children():
		child.queue_free()
	_mouths.clear()
	_flames.clear()
	_cores.clear()
	_flame_lights.clear()
	_show.clear()


func playing() -> bool:
	return _playing


func elapsed() -> float:
	return _elapsed


func seconds() -> float:
	return _seconds


## The outer flame of each nozzle, in nozzles_of() order.
func flames() -> Array[MeshInstance3D]:
	return _flames


## The show's lights.
func lights() -> Array[OmniLight3D]:
	return _show


## How far along `axis` from `from` the farthest corner of `mesh`'s box lies (0 at least).
static func _reach(mesh: MeshInstance3D, from: Vector3, axis: Vector3) -> float:
	if mesh.mesh == null:
		return 0.0
	# Each corner of the mesh's own box, turned with it: a global box would grow on a turned pod.
	var box := mesh.get_aabb()
	var far := 0.0
	for i in 8:
		far = maxf(far, (mesh.global_transform * box.get_endpoint(i) - from).dot(axis))
	return far


## A basis whose z is `axis` (a unit vector).
static func _basis_along(axis: Vector3) -> Basis:
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(axis).normalized()
	return Basis(x, axis.cross(x), axis)


func _cone(colour: Color, radius: float) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = 1.0
	var made := MeshInstance3D.new()
	made.mesh = cone
	made.material_override = _material(colour)
	made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(made)
	return made


## A cone of `length` from `mouth` along its z: the cylinder's y (its tip at +y) turned onto it.
func _place_cone(cone: MeshInstance3D, mouth: Transform3D, length: float) -> void:
	var along := mouth.basis.z
	var turned := Basis(mouth.basis.x, along, -mouth.basis.y)
	cone.visible = length > 0.01
	cone.transform = Transform3D(
		turned.scaled_local(Vector3(1.0, maxf(length, 0.01), 1.0)),
		mouth.origin + along * length * 0.5
	)


func _material(colour: Color) -> StandardMaterial3D:
	var made := StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	made.albedo_color = colour
	return made
