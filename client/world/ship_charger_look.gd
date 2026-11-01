class_name ShipChargerLook
extends RefCounted
## The crystal charger's look (#1550), ported from the art package's `charger.gd` (prime-game-art
## `assets/prop/crystal_charger/export/`, main 06a42b8e; ARCHITECTURE §11.1): the bronze, graphite,
## steel, cyan, amber and lens materials on an imported crystal_charger.glb by its glTF material
## names, its soft cyan glow, and the moving parts: the carrier (up RISE and round its Y axis), the
## track ring (round its Y axis) and the button (pressed TRAVEL in). The states: "idle", "charging",
## "charged". Values only: ShipStationLooks drives them from the filtered model. Left out: the
## render layer 20 the art gives the meshes (PhotoLayers.PHOTO here, which every live camera skips)
## and seat_crystal (no crystal model is drawn on a charger); the lightning is the game's, not yet.

const METAL := preload("res://assets/environment/ship/console_metal.gdshader")

## The carrier's travel up and the button's in, metres.
const RISE := 0.06
const TRAVEL := 0.01
const CYAN := Color(0.0, 0.45, 1.0)
const AMBER := Color(1.0, 0.42, 0.0)
## Per state: the cyan's, the amber's and the lens's energy, and the glow light's.
const STATES: Dictionary[String, Array] = {
	"idle": [2.4, 2.2, 2.2, 0.0],
	"charging": [3.2, 2.4, 1.2, 0.5],
	"charged": [3.0, 1.6, 2.6, 0.25],
}
const BRONZE := Color(0.5, 0.38, 0.24)
const BRONZE_EDGE := Color(1.0, 0.9, 0.7)
const BRONZE2 := Color(0.42, 0.31, 0.2)
## The pedestal's darker, rougher bronze: these over the socket's finish.
const BRONZE2_FINISH: Dictionary[String, float] = {
	"metallic": 0.72,
	"roughness": 0.4,
	"wear": 1.0,
	"lift": 0.04,
	"mottle": 0.1,
	"rough_mottle": 0.06,
	"wave": 0.15,
}

var _cyan: StandardMaterial3D
var _amber: StandardMaterial3D
var _lens: StandardMaterial3D
var _glow: OmniLight3D
var _carrier: Node3D
var _ring: Node3D
var _button: Node3D
var _carrier_rest := Vector3.ZERO
var _button_rest := Vector3.ZERO
var _state := ""
var _rise := 0.0
var _turn := 0.0
var _ring_turn := 0.0
var _pressed := false


## Puts the charger's materials on every surface under `root`; null when it has no carrier (not a
## charger).
static func apply(root: Node3D) -> ShipChargerLook:
	var look := ShipChargerLook.new()
	look._carrier = root.find_child("carrier", true, false) as Node3D
	if look._carrier == null:
		return null
	look._ring = root.find_child("track_ring", true, false) as Node3D
	look._button = root.find_child("button", true, false) as Node3D
	look._carrier_rest = look._carrier.position
	look._button_rest = look._button.position if look._button != null else Vector3.ZERO
	var by_name := look._materials()
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		if mesh.mesh == null:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i: int in mesh.mesh.get_surface_count():
			var src: Material = mesh.mesh.surface_get_material(i)
			var key: String = src.resource_name if src != null else ""
			if by_name.has(key):
				mesh.set_surface_override_material(i, by_name[key])
			else:
				push_warning("ShipChargerLook: no look for surface material '%s'" % key)
	look._glow = OmniLight3D.new()
	look._glow.name = "ChargerGlow"
	look._glow.light_color = Color(0.3, 0.78, 1.0)
	look._glow.omni_range = 1.6
	look._glow.omni_attenuation = 1.6
	look._glow.shadow_enabled = false
	look._glow.position = Vector3(0.0, 1.13, 0.38)
	root.add_child(look._glow)
	look.set_state("idle")
	return look


## "idle" (no crystal or not charging), "charging" or "charged"; out of "charging" the carrier
## goes back down. Another name is refused with a warning.
func set_state(to: String) -> void:
	if to == _state:
		return
	if not STATES.has(to):
		push_warning("ShipChargerLook: no state '%s'" % to)
		return
	_state = to
	var s: Array = STATES[to]
	_cyan.emission_energy_multiplier = s[0]
	_amber.emission_energy_multiplier = s[1]
	_lens.emission_energy_multiplier = s[2]
	_glow.light_energy = s[3]
	_glow.visible = _glow.light_energy > 0.0
	if to != "charging":
		set_carrier(0.0, 0.0)
		set_ring(0.0)
		set_pressed(false)


func state() -> String:
	return _state


## The carrier risen `rise01` of RISE and turned `angle` radians round its Y axis.
func set_carrier(rise01: float, angle: float) -> void:
	_rise = clampf(rise01, 0.0, 1.0)
	_turn = angle
	_carrier.position = _carrier_rest + Vector3(0.0, RISE * _rise, 0.0)
	_carrier.rotation = Vector3(0.0, angle, 0.0)


func carrier_rise() -> float:
	return _rise


func carrier_turn() -> float:
	return _turn


## The track ring turned `angle` radians round its Y axis (0: the inner prongs left and right).
func set_ring(angle: float) -> void:
	_ring_turn = angle
	if _ring != null:
		_ring.rotation = Vector3(0.0, angle, 0.0)


func ring_turn() -> float:
	return _ring_turn


## The button pressed in TRAVEL, or out.
func set_pressed(on: bool) -> void:
	_pressed = on
	if _button != null:
		_button.position = _button_rest - Vector3(0.0, 0.0, TRAVEL if on else 0.0)


func pressed() -> bool:
	return _pressed


func _materials() -> Dictionary[String, Material]:
	var bronze := _metal(BRONZE, BRONZE_EDGE)
	var bronze2 := _metal(BRONZE2, BRONZE_EDGE)
	for p: String in ShipSocketLook.BRONZE_FINISH:
		bronze.set_shader_parameter(p, ShipSocketLook.BRONZE_FINISH[p])
		bronze2.set_shader_parameter(p, BRONZE2_FINISH.get(p, ShipSocketLook.BRONZE_FINISH[p]))
	var graphite := _metal(Color(0.272, 0.276, 0.293), Color(0.634, 0.626, 0.618))
	graphite.set_shader_parameter("metallic", 0.75)
	graphite.set_shader_parameter("roughness", 0.38)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.52, 0.56)
	steel.metallic = 0.85
	steel.roughness = 0.2
	_cyan = _light(CYAN)
	_amber = _light(AMBER)
	_lens = _light(Color(0.05, 0.75, 1.0))
	_lens.albedo_color = Color(0.05, 0.4, 0.6)
	_lens.clearcoat_enabled = true
	_lens.clearcoat = 1.0
	return {
		"charger_bronze": bronze,
		"charger_bronze2": bronze2,
		"charger_graphite": graphite,
		"charger_cyan": _cyan,
		"charger_amber": _amber,
		"charger_lens": _lens,
		"charger_steel": steel,
	}


static func _metal(base: Color, worn: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = METAL
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("worn_color", worn)
	return m


static func _light(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.035)
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = colour
	return m
