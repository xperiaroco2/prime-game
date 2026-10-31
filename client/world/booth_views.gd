class_name BoothViews
extends Node3D
## The photo booth's session as the players see it (#1397, ARCHITECTURE §4.7.62; GDD §3 "The photo
## booth"), driven only by the host's public BoothStep events (§9.5.29) as the BoothBook folded
## them, and the estimated host tick, never by a local timer of its own:
## - the lamp: a small glowing bulb and an OmniLight3D (shadowed, short range, so it never lights
##   through a wall, as PhotoFlashes') above the booth's marker while a session runs; it blinks
##   with each countdown beep and flares at each flash;
## - the countdown: a beep a second before the first flash (the STARTED countdown) and before each
##   next one (the gap), on the host's ticks (`tick_to`), sent through `sound_due` so WorldSounds
##   cuts and muffles it like every world sound; a FLASH, PRINTED or STOPPED ends the beeps due;
## - the flash on the screen: a short white fade over the whole view, only for the own player when
##   the FLASH record names it (the players in the frame are the ones inside); everyone else sees
##   the lamp and hears the shutter at distance (SoundChooser);
## - the print: a strip prop sliding down out of the booth's slot. It is a decoration only: the
##   strips themselves are ItemViews' (in a hand, on a belt or at the feet, where GiveItem put
##   them); this node never moves or hides an ItemView (SightHider alone sets their `visible`).
## It holds no Camera3D, SubViewport or ViewportTexture: nothing renders the inside of the booth
## before a strip exists (a source test holds it); the strip's frames are StripPictures', drawn
## from the records after PRINTED. Every look here is a placeholder in the Toy style, "not a
## decision", until the engineer picks.

## A countdown beep is due at booth `station`: an event for WorldSounds.on_event.
signal sound_due(event_name: StringName, fields: Dictionary)

## The synthetic event of a countdown beep (SoundChooser plays it at the lamp).
const BEEP_EVENT := &"BoothBeep"
## The lamp above the booth's marker, in metres. Placeholder, "not a decision".
const LAMP_LIFT_M := 2.2
## How far the lamp lights. Placeholder, "not a decision".
const LAMP_RANGE_M := 2.5
const LAMP_RADIUS_M := 0.06
const LAMP_COLOUR := Color(1.0, 0.86, 0.6)
## The lamp's energy on, at a beep's blink and at a flash. Placeholders, "not a decision".
const LAMP_ENERGY := 0.4
const BEEP_ENERGY := 1.5
const FLASH_ENERGY := 6.0
## How long a beep's blink and a flash's flare last, in seconds. Placeholders, "not a decision".
const BEEP_SECONDS := 0.15
const FLASH_SECONDS := 0.35
## The white on the screen of a player in the frame: its alpha at the flash, fading out over
## FLASH_SECONDS. Kept mild until the engineer picks. Placeholder, "not a decision".
const OVERLAY_ALPHA := 0.6
## The overlay's canvas layer: under GameUi's (1), as the viewfinder's mask.
const OVERLAY_LAYER := 0
## The print's slot above the booth's marker, how far the prop slides down out of it and how
## long. Placeholders, "not a decision".
const SLOT_LIFT_M := 0.9
const PRINT_DROP_M := 0.2
const PRINT_SECONDS := 1.2

var model: ClientModel
var book: BoothBook
## The estimated host tick (AvatarViews.host_tick): the beeps are due on it. Unset: no beeps.
var host_tick := Callable()
## The white flash over the view (a ColorRect on its own canvas layer), hidden but at a flash.
var overlay := CanvasLayer.new()

var _white := ColorRect.new()
var _flash_left := 0.0
## Lamps by station id.
var _lamps: Dictionary[int, Lamp] = {}
## The beeps due by station id: host ticks, ascending.
var _beeps: Dictionary[int, PackedInt32Array] = {}
var _prints: Array[Print] = []


## One booth's lamp: the bulb, its light, and the flare running.
class Lamp:
	extends RefCounted
	var root: Node3D
	var light: OmniLight3D
	var flare := 0.0
	var flare_left := 0.0
	var flare_seconds := 0.0
	## The session is over: the lamp goes once its flare ends.
	var done := false


## One print prop sliding out of a slot.
class Print:
	extends RefCounted
	var prop: Node3D
	var from: Vector3
	var age := 0.0


func _init() -> void:
	name = "BoothViews"
	overlay.name = "BoothFlash"
	overlay.layer = OVERLAY_LAYER
	overlay.visible = false
	_white.name = "White"
	_white.color = Color.WHITE
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(_white)
	add_child(overlay)


## An event the BoothBook folded already (ItemWorld forwards it after the book).
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name != BoothBook.STEP_EVENT or model == null or book == null:
		return
	var station := fields.get("station", -1) as int
	var now := _now()
	match fields.get("step", -1) as int:
		BoothStepEvent.STARTED:
			var session := book.running_at(station)
			if session != null:
				session.started_at = now
			_lamp_on(station)
			_plan_beeps(station, now, fields.get("countdown", 0) as int)
		BoothStepEvent.FLASH:
			_lamp_on(station)
			_flare(station, FLASH_ENERGY, FLASH_SECONDS)
			_beeps.erase(station)
			if _names_own(fields.get("record", []) as Array):
				_flash_left = FLASH_SECONDS
				_show_overlay()
			var session := book.running_at(station)
			var frame := fields.get("frame", 0) as int
			if session != null and frame + 1 < session.frames:
				_plan_beeps(station, now, session.gap)
		BoothStepEvent.PRINTED:
			_end(station)
			_print(station)
		BoothStepEvent.STOPPED:
			_end(station)


## Plays the beeps due by host tick `now` (_process passes the estimated host tick).
func tick_to(now: int) -> void:
	for station: int in _beeps.keys():
		var due := _beeps[station]
		while not due.is_empty() and due[0] <= now:
			due.remove_at(0)
			_flare(station, BEEP_ENERGY, BEEP_SECONDS)
			sound_due.emit(BEEP_EVENT, {"station": station})
		if due.is_empty():
			_beeps.erase(station)
		else:
			_beeps[station] = due


## Ages the flares, the overlay and the print props by `seconds`.
func advance(seconds: float) -> void:
	_flash_left = maxf(_flash_left - seconds, 0.0)
	_show_overlay()
	for station: int in _lamps.keys():
		var lamp := _lamps[station]
		lamp.flare_left = maxf(lamp.flare_left - seconds, 0.0)
		var flare := lamp.flare * lamp.flare_left / maxf(lamp.flare_seconds, 0.001)
		lamp.light.light_energy = maxf(LAMP_ENERGY, flare)
		if lamp.done and lamp.flare_left <= 0.0:
			lamp.root.queue_free()
			_lamps.erase(station)
	for each: Print in _prints.duplicate():
		each.age += seconds
		var left := clampf(1.0 - each.age / PRINT_SECONDS, 0.0, 1.0)
		each.prop.position = each.from + Vector3.DOWN * PRINT_DROP_M * (1.0 - left * left)
		if each.age >= PRINT_SECONDS:
			each.prop.queue_free()
			_prints.erase(each)


## The beeps still due at `station` (host ticks).
func beeps_due(station: int) -> PackedInt32Array:
	return _beeps.get(station, PackedInt32Array())


## The lamp's light at `station`, or null.
func lamp_of(station: int) -> OmniLight3D:
	var lamp: Lamp = _lamps.get(station)
	return lamp.light if lamp != null else null


## The white's alpha now (0: none).
func overlay_alpha() -> float:
	return _white.color.a if overlay.visible else 0.0


## The print props sliding now.
func prints() -> Array[Node3D]:
	var props: Array[Node3D] = []
	for each: Print in _prints:
		props.append(each.prop)
	return props


## Forgets every session (the session ended, a match loads).
func clear() -> void:
	for lamp: Lamp in _lamps.values():
		lamp.root.queue_free()
	_lamps.clear()
	_beeps.clear()
	for each: Print in _prints:
		each.prop.queue_free()
	_prints.clear()
	_flash_left = 0.0
	_show_overlay()


func _process(delta: float) -> void:
	advance(delta)
	if not _beeps.is_empty() and host_tick.is_valid():
		tick_to(host_tick.call() as int)


func _now() -> int:
	return host_tick.call() as int if host_tick.is_valid() else 0


## A beep each second before the flash `span` ticks after `now`: 3, 2, 1 for a 3 s countdown.
func _plan_beeps(station: int, now: int, span: int) -> void:
	var due := PackedInt32Array()
	for k: int in range(floori(span / float(Ticks.RATE)), 0, -1):
		due.append(now + span - k * Ticks.RATE)
	if due.is_empty():
		_beeps.erase(station)
	else:
		_beeps[station] = due


func _names_own(rows: Array) -> bool:
	for row: Variant in rows:
		if row is Dictionary and ((row as Dictionary).get("peer", -1) as int) == model.own_peer:
			return true
	return false


func _show_overlay() -> void:
	var alpha := OVERLAY_ALPHA * _flash_left / FLASH_SECONDS
	_white.color = Color(Color.WHITE, alpha)
	overlay.visible = alpha > 0.0


func _lamp_on(station: int) -> void:
	var booth: ClientModel.Station = model.stations.get(station)
	if booth == null:
		return
	var lamp: Lamp = _lamps.get(station)
	if lamp != null:
		lamp.done = false
		return
	lamp = Lamp.new()
	lamp.root = Node3D.new()
	lamp.root.name = "Lamp%d" % station
	lamp.root.position = booth.position + Vector3.UP * LAMP_LIFT_M
	var bulb := MeshInstance3D.new()
	bulb.name = "Bulb"
	var sphere := SphereMesh.new()
	sphere.radius = LAMP_RADIUS_M
	sphere.height = LAMP_RADIUS_M * 2.0
	var glow := StandardMaterial3D.new()
	glow.albedo_color = LAMP_COLOUR
	glow.emission_enabled = true
	glow.emission = LAMP_COLOUR
	sphere.material = glow
	bulb.mesh = sphere
	lamp.root.add_child(bulb)
	lamp.light = OmniLight3D.new()
	lamp.light.name = "Light"
	lamp.light.light_color = LAMP_COLOUR
	lamp.light.light_energy = LAMP_ENERGY
	lamp.light.omni_range = LAMP_RANGE_M
	lamp.light.shadow_enabled = true
	lamp.root.add_child(lamp.light)
	add_child(lamp.root)
	_lamps[station] = lamp


func _flare(station: int, energy: float, seconds: float) -> void:
	var lamp: Lamp = _lamps.get(station)
	if lamp == null:
		return
	lamp.flare = energy
	lamp.flare_left = seconds
	lamp.flare_seconds = seconds
	lamp.light.light_energy = energy


func _end(station: int) -> void:
	_beeps.erase(station)
	var lamp: Lamp = _lamps.get(station)
	if lamp != null:
		lamp.done = true


func _print(station: int) -> void:
	var booth: ClientModel.Station = model.stations.get(station)
	if booth == null:
		return
	var each := Print.new()
	each.prop = StripLooks.build(StripLooks.STRIP)
	each.prop.name = "Print%d" % station
	# Upright, its picture face out of the slot (+Z), frame 0 at the top.
	each.prop.basis = Basis(Vector3.RIGHT, PI * 0.5)
	each.from = booth.position + Vector3.UP * SLOT_LIFT_M
	each.prop.position = each.from
	add_child(each.prop)
	_prints.append(each)
