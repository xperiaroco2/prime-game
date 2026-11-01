class_name ShipSocketLook
extends RefCounted
## The crystal socket's look (#1550), ported from the art package's `socket.gd` (prime-game-art
## `assets/prop/crystal_socket/export/`, main 06a42b8e; ARCHITECTURE §11.1): the metal, strip,
## amber, lamp and bay materials on an imported crystal_socket.glb by its glTF material names, the
## red problem lamp's light at the dome, and the claws. One state drives the lamp and the bay's
## glow: "charged" (lamp off, bay lit), "spent" and "empty" (lamp lit red, bay dark); the claws open
## 0..1 round their hinges. Values only: ShipStationLooks drives them from the filtered model.
## Left out: the render layer 20 the art gives the meshes (it is PhotoLayers.PHOTO here, which every
## live camera skips) and seat_crystal (no crystal model is drawn in a socket).

const METAL := preload("res://assets/environment/ship/console_metal.gdshader")
const BAY := preload("res://assets/environment/crystal_socket/socket_bay.gdshader")

const CYAN := Color(0.0, 0.62, 1.0)
const AMBER := Color(1.0, 0.5, 0.0)
const RED := Color(1.0, 0.05, 0.02)
const BRONZE := Color(0.5, 0.38, 0.24)
const BRONZE_EDGE := Color(1.0, 0.9, 0.7)
## The stations' bronze finish on the shared metal shader (the board and the charger match it).
const BRONZE_FINISH: Dictionary[String, float] = {
	"metallic": 0.75,
	"roughness": 0.3,
	"wear": 1.4,
	"lift": 0.08,
	"mottle": 0.3,
	"grain": 0.06,
	"rough_grain": 0.06,
	"rough_mottle": 0.15,
	"edge_polish": 0.25,
	"shade": 0.3,
	"dent": 0.0,
	"dent_scale": 45.0,
	"wave": 0.3,
	"wave_scale": 8.0,
}
const CYAN_ENERGY := 5.0
const AMBER_ENERGY := 0.9
const BAY_ENERGY := 1.6
## The claws' turn when open, degrees (the package's build).
const CLAW_OPEN_DEG := 25.0
const LAMP_ENERGY := 3.2
const LAMP_LIGHT := 0.9
const LAMP_RANGE := 1.6
const STATES: Array[String] = ["charged", "spent", "empty"]

var _lamp: StandardMaterial3D
var _lamp_light: OmniLight3D
var _bay: ShaderMaterial
var _claw_r: Node3D
var _claw_l: Node3D
var _state := ""
var _claws := -1.0


## Puts the socket's materials on every surface under `root`; null when none is the socket's.
static func apply(root: Node3D) -> ShipSocketLook:
	var look := ShipSocketLook.new()
	var by_name := look._materials()
	var matched := 0
	var lamp_at := Vector3.ZERO
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		if mesh.mesh == null or mesh.get_parent() is CollisionObject3D:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i: int in mesh.mesh.get_surface_count():
			var src: Material = mesh.mesh.surface_get_material(i)
			var key: String = src.resource_name if src != null else ""
			if by_name.has(key):
				mesh.set_surface_override_material(i, by_name[key])
				matched += 1
			else:
				push_warning("ShipSocketLook: no look for surface material '%s'" % key)
			if key == "socket_lamp":
				var v: PackedVector3Array = mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				var sum := Vector3.ZERO
				for p: Vector3 in v:
					sum += p
				lamp_at = ShipStationLooks.relative(mesh, root) * (sum / maxf(1.0, v.size()))
	if matched == 0:
		return null
	look._lamp_light = OmniLight3D.new()
	look._lamp_light.name = "SocketLampLight"
	look._lamp_light.light_color = RED
	look._lamp_light.omni_range = LAMP_RANGE
	look._lamp_light.omni_attenuation = 1.6
	look._lamp_light.shadow_enabled = false
	look._lamp_light.position = lamp_at + Vector3(0.0, 0.0, 0.03)
	root.add_child(look._lamp_light)
	var anchor := root.find_child("crystal_anchor", true, false) as Node3D
	if anchor != null:
		look._bay.set_shader_parameter("centre", anchor.position + Vector3(0.0, 0.1745, 0.0))
	look._claw_r = root.find_child("claw_r", true, false) as Node3D
	look._claw_l = root.find_child("claw_l", true, false) as Node3D
	look.set_claws(0.0)
	look.set_state("charged")
	return look


## The claws: 0 closed, 1 open (CLAW_OPEN_DEG round their hinges; claw_r +Z, claw_l -Z).
func set_claws(open01: float) -> void:
	var k := clampf(open01, 0.0, 1.0)
	if k == _claws:
		return
	_claws = k
	var a := deg_to_rad(CLAW_OPEN_DEG) * k
	if _claw_r != null:
		_claw_r.rotation = Vector3(0.0, 0.0, a)
	if _claw_l != null:
		_claw_l.rotation = Vector3(0.0, 0.0, -a)


func claws() -> float:
	return _claws


## "charged" (a charged crystal in it: the lamp off, the bay lit), "spent" (a spent one: the lamp
## lit) or "empty" (none: the lamp lit). Another name is refused with a warning.
func set_state(state: String) -> void:
	if state == _state:
		return
	if not state in STATES:
		push_warning("ShipSocketLook: no state '%s'" % state)
		return
	_state = state
	var on := state != "charged"
	_lamp.emission_energy_multiplier = LAMP_ENERGY if on else 0.0
	_lamp_light.light_energy = LAMP_LIGHT if on else 0.0
	_lamp_light.visible = on
	_bay.set_shader_parameter("energy", 0.0 if on else BAY_ENERGY)


func state() -> String:
	return _state


## Whether the red problem lamp is lit now.
func lamp_lit() -> bool:
	return _lamp_light.visible


func _materials() -> Dictionary[String, Material]:
	var bronze := ShaderMaterial.new()
	bronze.shader = METAL
	bronze.set_shader_parameter("base_color", BRONZE)
	bronze.set_shader_parameter("worn_color", BRONZE_EDGE)
	for p: String in BRONZE_FINISH:
		bronze.set_shader_parameter(p, BRONZE_FINISH[p])
	var graphite := ShaderMaterial.new()
	graphite.shader = METAL
	graphite.set_shader_parameter("base_color", Color(0.272, 0.276, 0.293))
	graphite.set_shader_parameter("worn_color", Color(0.634, 0.626, 0.618))
	graphite.set_shader_parameter("metallic", 0.75)
	graphite.set_shader_parameter("roughness", 0.38)
	_lamp = StandardMaterial3D.new()
	_lamp.albedo_color = Color(0.55, 0.03, 0.02)
	_lamp.roughness = 0.12
	_lamp.clearcoat_enabled = true
	_lamp.clearcoat = 1.0
	_lamp.rim_enabled = true
	_lamp.rim = 0.3
	_lamp.emission_enabled = true
	_lamp.emission = RED
	_bay = ShaderMaterial.new()
	_bay.shader = BAY
	return {
		"socket_bronze": bronze,
		"socket_graphite": graphite,
		"socket_cyan": _glow(CYAN, CYAN_ENERGY),
		"socket_amber": _glow(AMBER, AMBER_ENERGY),
		"socket_lamp": _lamp,
		"socket_bay": _bay,
	}


static func _glow(colour: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.04, 0.05)
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	return m
