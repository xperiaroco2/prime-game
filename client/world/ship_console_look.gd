class_name ShipConsoleLook
extends RefCounted
## The start console's look (#1550), ported from the art package's `console.gd` (prime-game-art
## `assets/prop/start_console/export/`, main 06a42b8e; ARCHITECTURE §11.1: no GDScript in
## assets/): the metal, signal, hologram and light materials on the imported start_console.glb by
## its glTF material names, and the hologram's and the button's small lights. It holds values only:
## ShipStationLooks sets them each frame from the filtered ClientModel and the host tick, so every
## peer shows the same. Left out of the port: the review states, the tween clock (the clock is the
## host tick's, set_clock), set_fill and set_ring_style (the art's picks FILL and RING_STYLE stand).
## The values: the stage strips' `passed` and the bar's `charge`, the order lamp `lit` (-1 none;
## 0..3 the west wing from the hall outward, red, yellow, green, blue; 4..7 the east), the call,
## the turbines' spin, a state per wiring station (STATIONS) and the countdown.

const METAL := preload("res://assets/environment/ship/console_metal.gdshader")
const SIGNAL := preload("res://assets/environment/start_console/console_signal.gdshader")
const HOLO := preload("res://assets/environment/start_console/console_holo.gdshader")

const CYAN := Color(0.0, 0.62, 1.0)
const ORANGE := Color(1.0, 0.2, 0.0)
const CYAN_ENERGY := 2.4
const BUTTON_ENERGY := 0.8
const HOLO_ENERGY := 2.6
## The wiring's stations in the build's order (UV0 v; the ninth value is the manifold's).
const STATIONS: Array[String] = [
	"socket_w", "socket_e", "socket_fw", "socket_fe", "breaker_w", "breaker_e", "vent_w", "vent_e"
]
const STATION_STATES: Dictionary[String, float] = {
	"off": 0.0, "ok": 1.0, "broken": 2.0, "fixed": 1.0
}
const CALL_GLOW := 4.0
const CALLING_ENERGY := 1.4
## Each broken station multiplies the turbines' spin by this (the art's rule).
const SLOW := 0.5
const BLINK_MIN := 0.5
const FILL_GREEN := Color(0.02, 1.0, 0.1)
## The art's RING_STYLE "both": the band's share drawn, its lit gain, the deck ring on.
const RING_BAND_TOP := 1.0
const RING_BAND_GAIN := 1.6
const RING_DECK := 1.0
const FAN_CENTRES: Array[Vector3] = [
	Vector3(0.18365, 1.55792, -0.62014),
	Vector3(-0.18365, 1.55792, -0.62014),
	Vector3(0.0, 1.59086, -0.61314),
]
const FAN_AXIS := Vector3(0.0, -0.20791, 0.97815)
const BUTTON_LIGHT_ENERGY := 0.08
const FAR_PAST := -1.0e6

var _strips: ShaderMaterial
var _lamps: ShaderMaterial
var _shell: ShaderMaterial
var _turbine: ShaderMaterial
var _wire: ShaderMaterial
var _ring: ShaderMaterial
var _digit: ShaderMaterial
var _button: StandardMaterial3D
var _button_light: OmniLight3D
var _glow: OmniLight3D
var _call_period := 3.0
var _clock := 0.0
var _calling := false
var _call_t0 := 0.0
var _spin := 0.0
var _spin_phase := 0.0
var _spin_t0 := 0.0
var _spin_rate := 0.0
var _passed := 1
var _lit := -1
var _charge := -1.0
var _countdown := -2.0
var _state: Dictionary[String, String] = {}
var _blink: Dictionary[String, float] = {}
var _fixed_at: Dictionary[String, float] = {}


## Puts the console's materials on every surface under `root` and adds its two lights; the call
## pulses every `call_period` seconds. Null when no surface of `root` is the console's.
static func apply(root: Node3D, call_period: float) -> ShipConsoleLook:
	var look := ShipConsoleLook.new()
	look._call_period = maxf(call_period, 0.01)
	var by_name := look._materials()
	var matched := 0
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
				matched += 1
			else:
				push_warning("ShipConsoleLook: no look for surface material '%s'" % key)
	if matched == 0:
		return null
	look._glow = OmniLight3D.new()
	look._glow.name = "ConsoleGlow"
	look._glow.light_color = Color(0.3, 0.75, 1.0)
	look._glow.light_energy = 0.9
	look._glow.omni_range = 2.2
	look._glow.omni_attenuation = 1.4
	look._glow.shadow_enabled = false
	look._glow.position = Vector3(0.0, 1.3, 0.0)
	root.add_child(look._glow)
	look._button_light = OmniLight3D.new()
	look._button_light.name = "ConsoleButtonLight"
	look._button_light.light_color = ORANGE
	look._button_light.light_energy = BUTTON_LIGHT_ENERGY
	look._button_light.omni_range = 0.7
	look._button_light.shadow_enabled = false
	look._button_light.position = Vector3(0.0, 0.814, 0.58)
	root.add_child(look._button_light)
	for id: String in STATIONS:
		look._state[id] = "off"
		look._blink[id] = 1.0
		look._fixed_at[id] = FAR_PAST
	look.set_passed(1)
	look.set_lit(-1)
	look._tick()
	look.set_charge(0.0)
	look.set_countdown(-1.0)
	look._stations()
	look._respin()
	return look


## The stage strips lit by stages passed (0..3); the strips show max(passed / 3, charge).
func set_passed(n: int) -> void:
	_passed = clampi(n, 0, 3)
	_strips.set_shader_parameter("passed", float(_passed))


func passed() -> int:
	return _passed


## The order lamp lit bright (-1 none; 0..3 west from the hall outward, 4..7 east); the others dim
## while one is lit.
func set_lit(index: int) -> void:
	_lit = clampi(index, -1, 7)
	_lamps.set_shader_parameter("lit", float(_lit))
	_lamps.set_shader_parameter("order", 1.0 if _lit >= 0 else 0.0)


func lit() -> int:
	return _lit


## The spin-up shaders' clock in seconds (the host tick's).
func set_clock(seconds: float) -> void:
	if seconds == _clock:
		return
	_clock = seconds
	_tick()


func clock() -> float:
	return _clock


## The call: the turbines pulse orange every call period and the button glows; `t0` is the clock
## a pulse starts on (the same on every peer).
func set_calling(on: bool, t0: float) -> void:
	if on == _calling and t0 == _call_t0:
		return
	_calling = on
	_call_t0 = t0
	for m: ShaderMaterial in [_turbine, _shell]:
		m.set_shader_parameter("calling", 1.0 if on else 0.0)
		m.set_shader_parameter("call_t0", t0)
		m.set_shader_parameter("call_period", _call_period)
	_tick()


func calling() -> bool:
	return _calling


## Where the call is in its period, 0..1 (0 the pulse's onset); -1 when not calling.
func call_phase() -> float:
	if not _calling:
		return -1.0
	return fposmod((_clock - _call_t0) / _call_period, 1.0)


## The call's light at a phase (the shader's call_pulse): up fast, gone by under half the period.
static func call_pulse(phase: float) -> float:
	if phase < 0.0:
		return 0.0
	return smoothstep(0.0, 0.05, phase) * (1.0 - smoothstep(0.05, 0.45, phase))


## The bar 0..1: the three strips fill one after another and the ring round the hall with them.
func set_charge(value: float) -> void:
	var c := clampf(value, 0.0, 1.0)
	if c == _charge:
		return
	_charge = c
	_strips.set_shader_parameter("charge", c)
	_ring.set_shader_parameter("charge", c)


func charge() -> float:
	return _charge


## The turbines' spin in turns a second before the broken stations slow it (0 still).
func set_spin(turns_per_second: float) -> void:
	var s := maxf(turns_per_second, 0.0)
	if s == _spin:
		return
	_spin = s
	_respin()


## The fans' rate now, after the broken stations' slowing, turns a second.
func spin_rate() -> float:
	return _spin_rate


## A wiring station's state: "off", "ok", "broken" (blinking `blink_hz` a second) or "fixed" (its
## line flashes back, then reads ok). Unknown names are refused with a warning.
func set_station(id: String, state: String, blink_hz: float = 1.0) -> void:
	if not id in STATIONS or not STATION_STATES.has(state):
		push_warning("ShipConsoleLook: no station '%s' or state '%s'" % [id, state])
		return
	_state[id] = "ok" if state == "fixed" else state
	_blink[id] = maxf(blink_hz, BLINK_MIN)
	if state == "fixed":
		_fixed_at[id] = _clock
	_stations()
	_respin()


func station_state(id: String) -> String:
	return _state.get(id, "")


func station_blink(id: String) -> float:
	return _blink.get(id, 0.0)


## The clock a station was last fixed at (FAR_PAST never).
func fixed_at(id: String) -> float:
	return _fixed_at.get(id, FAR_PAST)


## The nearest failure's seconds over the hologram (shown rounded up); below 0 hidden.
func set_countdown(seconds: float) -> void:
	if seconds == _countdown:
		return
	_countdown = seconds
	_digit.set_shader_parameter("countdown", seconds)


func countdown() -> float:
	return _countdown


func _materials() -> Dictionary[String, Material]:
	var bronze := _metal(Color(-1, -1, -1), Color(-1, -1, -1), 0.35, 0.42)
	bronze.set_shader_parameter("wear", 1.0)
	bronze.set_shader_parameter("lift", 0.12)
	var graphite := _metal(Color(0.272, 0.276, 0.293), Color(0.634, 0.626, 0.618), 0.75, 0.38)
	var cyan := StandardMaterial3D.new()
	cyan.albedo_color = Color(0.02, 0.05, 0.06)
	cyan.roughness = 0.2
	cyan.emission_enabled = true
	cyan.emission = CYAN
	cyan.emission_energy_multiplier = CYAN_ENERGY
	_button = StandardMaterial3D.new()
	_button.albedo_color = Color(0.95, 0.32, 0.04)
	_button.roughness = 0.18
	_button.clearcoat_enabled = true
	_button.clearcoat = 1.0
	_button.emission_enabled = true
	_button.emission = ORANGE
	_button.emission_energy_multiplier = BUTTON_ENERGY
	_button.rim_enabled = true
	_button.rim = 0.4
	_strips = ShaderMaterial.new()
	_strips.shader = SIGNAL
	_strips.set_shader_parameter("mode", 0)
	# The art's "green" fill goes raw to the strips (its note of 2026-10-26), to the ring as is.
	_strips.set_shader_parameter("fill_colour", FILL_GREEN)
	_strips.set_shader_parameter("head", 1.0)
	_lamps = ShaderMaterial.new()
	_lamps.shader = SIGNAL
	_lamps.set_shader_parameter("mode", 1)
	var holo := _holo(0, Color(-1, -1, -1), HOLO_ENERGY)
	_shell = _holo(1, Color(0.12, 0.5, 1.0), 0.45)
	_shell.set_shader_parameter("call_period", _call_period)
	var beam := _holo(2, Color(0.3, 0.78, 1.0), 0.5)
	_turbine = _holo(3, Color(0.06, 0.42, 1.0), HOLO_ENERGY)
	_turbine.set_shader_parameter("fan_centre", PackedVector3Array(FAN_CENTRES))
	_turbine.set_shader_parameter("fan_axis", FAN_AXIS)
	_turbine.set_shader_parameter("call_period", _call_period)
	_wire = _holo(4, Color(0.06, 0.42, 1.0), 1.5)
	_ring = _holo(5, Color(0.06, 0.5, 1.0), 2.2)
	_ring.set_shader_parameter("fill", FILL_GREEN)
	_ring.set_shader_parameter("band_top", RING_BAND_TOP)
	_ring.set_shader_parameter("band_gain", RING_BAND_GAIN)
	_ring.set_shader_parameter("deck", RING_DECK)
	_digit = _holo(6, Color(0.2, 0.7, 1.0), 2.6)
	return {
		"console_bronze": bronze,
		"console_graphite": graphite,
		"console_cyan": cyan,
		"console_button": _button,
		"console_stage": _strips,
		"console_lamp": _lamps,
		"console_holo_line": holo,
		"console_holo_shell": _shell,
		"console_beam": beam,
		"console_holo_turbine": _turbine,
		"console_holo_wire": _wire,
		"console_holo_ring": _ring,
		"console_holo_digit": _digit,
	}


## A metal material; a negative colour keeps the shader's default.
static func _metal(base: Color, worn: Color, metallic: float, roughness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = METAL
	if base.r >= 0.0:
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("worn_color", worn)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness", roughness)
	return m


## A hologram material of `mode`; a negative colour keeps the shader's default.
static func _holo(mode: int, colour: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HOLO
	m.set_shader_parameter("mode", mode)
	if colour.r >= 0.0:
		m.set_shader_parameter("colour", colour)
	m.set_shader_parameter("energy", energy)
	return m


func _tick() -> void:
	for m: ShaderMaterial in [_turbine, _wire, _ring, _digit, _shell]:
		m.set_shader_parameter("clock", _clock)
	if _calling:
		var p := call_pulse(call_phase())
		_button.emission_energy_multiplier = CALLING_ENERGY + BUTTON_ENERGY * CALL_GLOW * p
		_button_light.light_energy = BUTTON_LIGHT_ENERGY * (1.0 + 4.0 * p)
	else:
		_button.emission_energy_multiplier = BUTTON_ENERGY
		_button_light.light_energy = BUTTON_LIGHT_ENERGY


func _respin() -> void:
	var turns := _spin_phase + (_clock - _spin_t0) * _spin_rate
	var broken := 0
	for id: String in STATIONS:
		broken += 1 if _state[id] == "broken" else 0
	_spin_phase = fposmod(turns, 1.0)
	_spin_t0 = _clock
	_spin_rate = _spin * pow(SLOW, broken)
	_turbine.set_shader_parameter("spin_phase", _spin_phase)
	_turbine.set_shader_parameter("spin_t0", _spin_t0)
	_turbine.set_shader_parameter("spin_rate", _spin_rate)
	_wire.set_shader_parameter("flow", 1.0 if _spin > 0.0 else 0.0)


func _stations() -> void:
	var st := PackedFloat32Array()
	var blink := PackedFloat32Array()
	var fixed := PackedFloat32Array()
	var on := 0
	var ok := 0
	for id: String in STATIONS:
		st.append(STATION_STATES[_state[id]])
		blink.append(_blink[id])
		fixed.append(_fixed_at[id])
		on += 0 if _state[id] == "off" else 1
		ok += 1 if _state[id] == "ok" else 0
	st.append(1.0 if on == 0 else float(ok) / on)
	blink.append(0.0)
	fixed.append(FAR_PAST)
	_wire.set_shader_parameter("st_state", st)
	_wire.set_shader_parameter("st_blink", blink)
	_wire.set_shader_parameter("st_fixed_at", fixed)
