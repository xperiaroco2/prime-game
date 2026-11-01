class_name ShipBoardLook
extends RefCounted
## The breaker board's look (#1550), ported from the art package's `board.gd` (prime-game-art
## `assets/prop/breaker_board/export/`, main 06a42b8e; ARCHITECTURE §11.1): the bronze, panel,
## graphite, enamel, cyan, core, lamp and beacon materials on an imported breaker_board.glb by its
## glTF material names (each core and lamp its own), the four shells, and the beacon's red spot
## light. The values: a shell's trip (0 closed .. 1 tripped, TRIP forward and down round its hinge),
## a lamp (0 dark, 1 yellow, 2 green), the beacon (the problem) and a core's glow. Values only:
## ShipStationLooks drives them from the filtered model. The sparks and smoke at a tripped core are
## the game's and not drawn yet.

const METAL := preload("res://assets/environment/ship/console_metal.gdshader")
const CORE := preload("res://assets/environment/breaker_board/board_core.gdshader")

## The shells left to right as you face the board (its local +X).
const COLOURS: Array[String] = ["red", "yellow", "green", "blue"]
const TRIP := deg_to_rad(110.0)
const ENAMEL: Dictionary[String, Color] = {
	"red": Color(0.78, 0.09, 0.07),
	"yellow": Color(0.93, 0.68, 0.08),
	"green": Color(0.13, 0.55, 0.22),
	"blue": Color(0.12, 0.25, 0.75),
}
const CYAN := Color(0.0, 0.62, 1.0)
const CYAN_ENERGY := 2.5
const BRONZE := Color(0.5, 0.38, 0.24)
const BRONZE_EDGE := Color(1.0, 0.9, 0.7)
const PANEL := Color(0.3, 0.22, 0.14)
const PANEL_EDGE := Color(0.78, 0.64, 0.46)
const LAMP: Array[Color] = [Color(0.02, 0.02, 0.02), Color(1.0, 0.55, 0.0), Color(0.0, 1.0, 0.12)]
const LAMP_ENERGY := 1.8
const BEACON := Color(1.0, 0.02, 0.0)
const BEACON_ENERGY := 1.3
const BEACON_LIGHT := 1.2
const BEACON_RANGE := 0.9
const BEACON_ANGLE := 55.0
const DARK := 0
const YELLOW := 1
const GREEN := 2

var _shells: Array[Node3D] = []
var _cores: Array[ShaderMaterial] = []
var _lamps: Array[StandardMaterial3D] = []
var _open: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _lamp: Array[int] = [-1, -1, -1, -1]
var _beacon: StandardMaterial3D
var _beacon_light: SpotLight3D
var _problem := false


## Puts the board's materials on every surface under `root`; null when it lacks a shell, core or
## lamp of a colour (not a board).
static func apply(root: Node3D) -> ShipBoardLook:
	var look := ShipBoardLook.new()
	var parts: Array[Array] = []
	for c: String in COLOURS:
		var shell := root.find_child("shell_" + c, true, false) as Node3D
		var core := root.find_child("core_" + c, true, false) as MeshInstance3D
		var lamp := root.find_child("lamp_" + c, true, false) as MeshInstance3D
		if shell == null or core == null or lamp == null:
			return null
		parts.append([shell, core, lamp])
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
			elif key != "board_core" and key != "board_lamp":
				push_warning("ShipBoardLook: no look for surface material '%s'" % key)
	for part: Array in parts:
		var cm := ShaderMaterial.new()
		cm.shader = CORE
		(part[1] as MeshInstance3D).set_surface_override_material(0, cm)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.03, 0.03, 0.03)
		lm.roughness = 0.12
		lm.emission_enabled = true
		(part[2] as MeshInstance3D).set_surface_override_material(0, lm)
		look._shells.append(part[0] as Node3D)
		look._cores.append(cm)
		look._lamps.append(lm)
	# A spot out of the wall and down: it reddens the shells, lamps and floor in front, never the
	# wall above (the art's board-3).
	look._beacon_light = SpotLight3D.new()
	look._beacon_light.name = "BoardBeaconLight"
	look._beacon_light.light_color = BEACON
	look._beacon_light.spot_range = BEACON_RANGE
	look._beacon_light.spot_angle = BEACON_ANGLE
	look._beacon_light.spot_attenuation = 1.5
	look._beacon_light.light_specular = 0.2
	look._beacon_light.shadow_enabled = false
	look._beacon_light.light_energy = BEACON_LIGHT
	look._beacon_light.position = Vector3(0.0, 1.37, 0.2)
	look._beacon_light.rotation = Vector3(deg_to_rad(-25.0), PI, 0.0)
	root.add_child(look._beacon_light)
	for i: int in COLOURS.size():
		look._open[i] = -1.0
		look.set_shell(i, 0.0)
		look.set_lamp(i, GREEN)
	look._problem = true
	look.set_problem(false)
	return look


## A shell's trip: 0 closed (on), 1 tripped (fallen open forward and down).
func set_shell(index: int, open01: float) -> void:
	var t := clampf(open01, 0.0, 1.0)
	if t == _open[index]:
		return
	_open[index] = t
	_shells[index].rotation.x = TRIP * t


func open_of(index: int) -> float:
	return _open[index]


## The lamp over a bay: DARK (tripped), YELLOW (switching on) or GREEN (on).
func set_lamp(index: int, state: int) -> void:
	var s := clampi(state, DARK, GREEN)
	if s == _lamp[index]:
		return
	_lamp[index] = s
	var m := _lamps[index]
	m.emission = LAMP[s]
	m.emission_energy_multiplier = 0.0 if s == DARK else LAMP_ENERGY
	m.albedo_color = Color(0.12, 0.03, 0.02) if s == DARK else LAMP[s].darkened(0.65)


func lamp_of(index: int) -> int:
	return _lamp[index]


## The red beacon: on while any shell is tripped.
func set_problem(on: bool) -> void:
	if on == _problem:
		return
	_problem = on
	_beacon.emission_energy_multiplier = BEACON_ENERGY if on else 0.08
	_beacon_light.visible = on


func problem() -> bool:
	return _problem


## A core's glow: 1 full (the default), 0 dark.
func set_core(index: int, glow: float) -> void:
	_cores[index].set_shader_parameter("glow", maxf(glow, 0.0))


## Shell `index`'s node (its hinge), for tests and placement.
func shell(index: int) -> Node3D:
	return _shells[index]


func _materials() -> Dictionary[String, Material]:
	var bronze := _metal(BRONZE, BRONZE_EDGE)
	var panel := _metal(PANEL, PANEL_EDGE)
	for k: String in ShipSocketLook.BRONZE_FINISH:
		if k == "dent_scale":
			continue
		bronze.set_shader_parameter(k, ShipSocketLook.BRONZE_FINISH[k])
		panel.set_shader_parameter(k, ShipSocketLook.BRONZE_FINISH[k])
	var graphite := _metal(Color(0.272, 0.276, 0.293), Color(0.634, 0.626, 0.618))
	graphite.set_shader_parameter("metallic", 0.75)
	graphite.set_shader_parameter("roughness", 0.38)
	var cyan := StandardMaterial3D.new()
	cyan.albedo_color = Color(0.02, 0.05, 0.06)
	cyan.emission_enabled = true
	cyan.emission = CYAN
	cyan.emission_energy_multiplier = CYAN_ENERGY
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.05, 0.05, 0.055)
	cable.roughness = 0.42
	cable.metallic = 0.2
	_beacon = StandardMaterial3D.new()
	_beacon.albedo_color = Color(0.45, 0.03, 0.02)
	_beacon.roughness = 0.15
	_beacon.emission_enabled = true
	_beacon.emission = BEACON
	var by_name: Dictionary[String, Material] = {
		"board_bronze": bronze,
		"board_panel": panel,
		"board_graphite": graphite,
		"board_cyan": cyan,
		"board_cable": cable,
		"board_beacon": _beacon,
	}
	for c: String in COLOURS:
		var e := StandardMaterial3D.new()
		e.albedo_color = ENAMEL[c]
		e.roughness = 0.24
		e.metallic = 0.15
		e.clearcoat_enabled = true
		e.clearcoat = 0.8
		e.emission_enabled = true
		e.emission = ENAMEL[c]
		e.emission_energy_multiplier = 0.12
		by_name["board_enamel_" + c] = e
	return by_name


static func _metal(base: Color, worn: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = METAL
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("worn_color", worn)
	return m
