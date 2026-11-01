class_name ShipEngineHologram
extends Node3D
## The engine console's hologram made readable (#1500; GDD §8 "The spin-up, made readable",
## ARCHITECTURE §9.5.27 "The client"), as stand-ins until the art ship (#1499) draws it: a child of
## ShipEngineViews, built with the engine's console, drawn from the own ClientModel (the console's
## Station and its ClientEngineBook), the bar's share the strips show and the estimated host tick;
## nothing is predicted. Round the hologram's centre:
## - the call: while the engine is off (never pressed, its bar empty and still, no problem), the two
##   turbines pulse orange and the start button under the hologram glows; the beep is #1501's;
## - the charge: started, the turbines spin, slower while a problem is open; the same bar the stage
##   strips fill runs as a ring of segments round the hologram's central disc;
## - the wiring: every site station (the sockets, the boards, the gill sets) is a point at its place
##   in the ship, scaled down like the mimic board, with a line of light to the nearer turbine; a
##   station an open problem holds blinks red, its line dark, the problem that blows first blinking
##   fastest; fixed (not blasted away), its line flashes back. Every point looks the same: it shows
##   where, not what;
## - the countdown: over the hologram, the seconds to the nearest problem's own deadline, digits
##   only, while one is open.
## Every part is depth-tested and tells only public places and states; none names a player. The
## looks, sizes and timings are placeholders, "not a decision" (#1500's Taste).

## The turbines: their offset left and right of the centre, the size of a blade, their spin.
const TURBINE_OFFSET_M := 0.15
const TURBINE_BLADE := Vector3(0.22, 0.03, 0.05)
const SPIN_RAD_PER_SECOND := 6.0
## The turbines' share of their spin while a problem is open.
const SLOW_FACTOR := 0.25
## One pulse of the call, dim to orange and back.
const PULSE_SECONDS := 1.5
## The start button: its size, how far under the centre and toward the console's use spot.
const BUTTON := Vector3(0.12, 0.04, 0.12)
const BUTTON_DROP_M := 0.5
const BUTTON_TOWARD_M := 0.3
## The central disc and the ring of the bar round it.
const DISC_RADIUS_M := 0.8
const RING_RADIUS_M := 0.9
const RING_SEGMENTS := 48
const RING_SEGMENT := Vector3(0.1, 0.08, 0.03)
const RING_DROP_M := 0.04
## A station's point (one look for every kind), its lift over the mimic board, and its line.
const POINT_M := 0.07
const POINT_LIFT_M := 0.06
const LINE_M := 0.012
const LINE_MIN_M := 0.01
## A fixed station's line: its flash, and how much thicker it is meanwhile.
const FLASH_SECONDS := 0.5
const FLASH_THICKER := 3.0
## A blinking point's half period: the problem that blows first, and any other.
const BLINK_FAST_SECONDS := 0.2
const BLINK_SLOW_SECONDS := 0.5
## The countdown: its height over the centre, its font size and pixel size.
const COUNTDOWN_LIFT_M := 0.7
const COUNTDOWN_FONT := 96
const COUNTDOWN_PIXEL_M := 0.004
const ORANGE := Color(1.0, 0.5, 0.1)
const ORANGE_DIM := Color(0.3, 0.13, 0.03)
const LINE := Color(0.75, 0.8, 0.85)
const DISC := Color(0.2, 0.9, 0.95, 0.2)

var _model: ClientModel
var _console := -1
var _centre := Vector3.ZERO
## The sites by station id, each with its point, its line and where its line starts and ends.
var _points: Dictionary[int, MeshInstance3D] = {}
var _lines: Dictionary[int, MeshInstance3D] = {}
var _line_from: Dictionary[int, Vector3] = {}
var _line_to: Dictionary[int, Vector3] = {}
## Whether an open problem held the site last frame, and its line's flash left in seconds.
var _held: Dictionary[int, bool] = {}
var _flash: Dictionary[int, float] = {}
var _turbines: Array[MeshInstance3D] = []
var _turbine_look := StandardMaterial3D.new()
var _button: MeshInstance3D
var _ring: Array[MeshInstance3D] = []
var _countdown: Label3D
var _materials: Dictionary[Color, StandardMaterial3D] = {}


## Builds the hologram round `centre` for console station `console` and the site stations `sites`;
## a site an open problem already holds is taken as held (a view built late flashes nothing).
func setup(model: ClientModel, console: int, centre: Vector3, sites: Array[int]) -> void:
	_model = model
	_console = console
	_centre = centre
	var spot := model.stations[console].position
	_turbine_look.emission_enabled = true
	for side: float in [-1.0, 1.0]:
		var blade := _box(TURBINE_BLADE, ORANGE)
		blade.material_override = _turbine_look
		blade.position = centre + Vector3(side * TURBINE_OFFSET_M, POINT_LIFT_M, 0.0)
		_turbines.append(blade)
	var toward := Vector3(spot.x - centre.x, 0.0, spot.z - centre.z)
	toward = toward.normalized() * BUTTON_TOWARD_M if toward.length() > LINE_MIN_M else Vector3.ZERO
	_button = _box(BUTTON, ORANGE)
	_button.position = centre + Vector3.DOWN * BUTTON_DROP_M + toward
	_build_disc()
	for site: int in sites:
		_build_site(site)
	_countdown = Label3D.new()
	_countdown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_countdown.font_size = COUNTDOWN_FONT
	_countdown.pixel_size = COUNTDOWN_PIXEL_M
	_countdown.modulate = ShipEngineViews.RED
	_countdown.position = centre + Vector3.UP * COUNTDOWN_LIFT_M
	_countdown.visible = false
	add_child(_countdown)


## Draws it at host tick `now`: `share` is the bar's (ZoneViews.fill), `delta` the frame's seconds,
## `blasted` whether an EngineBlast came since the last frame (its problems gone, none fixed).
func update(now: int, share: float, delta: float, blasted: bool) -> void:
	var calling := called()
	var pulse := 0.5 - 0.5 * cos(TAU * maxf(0.0, float(now)) / Ticks.RATE / PULSE_SECONDS)
	var look := ORANGE_DIM.lerp(ORANGE, pulse) if calling else ShipEngineViews.CYAN
	_turbine_look.albedo_color = look
	_turbine_look.emission = look
	var speed := turbine_speed()
	for blade: MeshInstance3D in _turbines:
		blade.rotation.y = wrapf(blade.rotation.y + speed * delta, 0.0, TAU)
	_button.visible = calling
	var lit := ring_lit_for(share)
	for i in _ring.size():
		_ring[i].material_override = _material(
			ShipEngineViews.CYAN if i < lit else ShipEngineViews.DARK
		)
	var nearest := _nearest_deadline()
	for site: int in _points:
		_draw_site(site, now, nearest, delta, blasted)
	_countdown.visible = nearest >= 0
	if nearest >= 0:
		_countdown.text = str(ceili(maxf(0.0, float(nearest - now)) / Ticks.RATE))


## Whether the ship calls: the engine off (its console never pressed here, the bar empty, still and
## not done) and no problem open, so a client joining a started engine does not call.
func called() -> bool:
	var console: ClientModel.Station = _model.stations.get(_console)
	if console == null:
		return false
	var idle := console.presses == 0 and not console.done and not console.counting
	return idle and console.ticks == 0 and _model.engine.problems.is_empty()


## The turbines' spin now in radians a second: none while the ship calls, slower with a problem.
func turbine_speed() -> float:
	if called():
		return 0.0
	var console: ClientModel.Station = _model.stations.get(_console)
	if console != null and not console.done and not _model.engine.problems.is_empty():
		return SPIN_RAD_PER_SECOND * SLOW_FACTOR
	return SPIN_RAD_PER_SECOND


## Turbine `index` (0 or 1), or null.
func turbine(index: int) -> MeshInstance3D:
	return _turbines[index] if index < _turbines.size() else null


## The start button's stand-in.
func button() -> MeshInstance3D:
	return _button


## Site `id`'s point, or null.
func point_of(id: int) -> MeshInstance3D:
	return _points.get(id)


## Site `id`'s line of light, or null.
func line_of(id: int) -> MeshInstance3D:
	return _lines.get(id)


## How many of the ring's segments are lit now.
func ring_lit() -> int:
	var lit := 0
	for segment: MeshInstance3D in _ring:
		if ShipEngineViews.colour_of(segment) == ShipEngineViews.CYAN:
			lit += 1
	return lit


## The segments lit for bar share `share` (0 to 1).
static func ring_lit_for(share: float) -> int:
	return clampi(floori(clampf(share, 0.0, 1.0) * RING_SEGMENTS + 1e-6), 0, RING_SEGMENTS)


## The countdown's label.
func countdown() -> Label3D:
	return _countdown


func _build_disc() -> void:
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = DISC_RADIUS_M
	disc_mesh.bottom_radius = DISC_RADIUS_M
	disc_mesh.height = 0.01
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = _material(DISC)
	disc.position = _centre + Vector3.DOWN * RING_DROP_M
	add_child(disc)
	for i in RING_SEGMENTS:
		# From the side of the console's use spot round, each segment along the ring's tangent.
		var angle := TAU * i / RING_SEGMENTS
		var segment := _box(RING_SEGMENT, ShipEngineViews.DARK)
		segment.basis = Basis(Vector3.UP, -angle)
		var round_at := Vector3(sin(angle), 0.0, -cos(angle)) * RING_RADIUS_M
		segment.position = _centre + Vector3.DOWN * RING_DROP_M + round_at
		_ring.append(segment)


func _build_site(site: int) -> void:
	var at := _model.stations[site].position - _model.stations[_console].position
	var point := _box(Vector3.ONE * POINT_M, ShipEngineViews.WHITE)
	var lift := Vector3.UP * POINT_LIFT_M
	point.position = _centre + Vector3(at.x, 0.0, at.z) * ShipEngineViews.MIMIC_SCALE + lift
	_points[site] = point
	var side := 1.0 if at.x >= 0.0 else -1.0
	var to := _centre + Vector3(side * TURBINE_OFFSET_M, POINT_LIFT_M, 0.0)
	if point.position.distance_to(to) >= LINE_MIN_M:
		var line := _box(Vector3(LINE_M, LINE_M, 1.0), LINE)
		_lines[site] = line
		_line_from[site] = point.position
		_line_to[site] = to
		_place_line(site, 1.0)
	_held[site] = _model.engine.problem_at(site) != null
	_flash[site] = 0.0


## Line `site` from its point to its turbine, `thicker` times its width.
func _place_line(site: int, thicker: float) -> void:
	var from := _line_from[site]
	var along := _line_to[site] - from
	var z := along.normalized()
	var x := Vector3.UP.cross(z)
	x = x.normalized() if x.length() > 1e-4 else Vector3.RIGHT
	var y := z.cross(x)
	_lines[site].transform = Transform3D(
		Basis(x * thicker, y * thicker, z * along.length()), from + along / 2.0
	)


func _draw_site(site: int, now: int, nearest: int, delta: float, blasted: bool) -> void:
	var problem := _model.engine.problem_at(site)
	var held := problem != null
	if held:
		_flash[site] = 0.0
	elif _held[site] and not blasted:
		_flash[site] = FLASH_SECONDS
	else:
		_flash[site] = maxf(0.0, _flash[site] - delta)
	_held[site] = held
	var colour := ShipEngineViews.WHITE
	if held:
		var step := BLINK_FAST_SECONDS if problem.deadline == nearest else BLINK_SLOW_SECONDS
		var step_ticks := maxi(1, Ticks.from_seconds(step))
		@warning_ignore("integer_division")
		var on := (maxi(now, 0) / step_ticks) % 2 == 0
		colour = ShipEngineViews.RED if on else ShipEngineViews.DARK
	_points[site].material_override = _material(colour)
	var line: MeshInstance3D = _lines.get(site)
	if line == null:
		return
	var flashing := _flash[site] > 0.0
	line.material_override = _material(
		ShipEngineViews.DARK if held else (ShipEngineViews.WHITE if flashing else LINE)
	)
	_place_line(site, FLASH_THICKER if flashing else 1.0)


## The deadline of the open problem that blows first, or -1 with none open.
func _nearest_deadline() -> int:
	var nearest := -1
	for problem: ClientEngineBook.Problem in _model.engine.problems.values():
		if nearest < 0 or problem.deadline < nearest:
			nearest = problem.deadline
	return nearest


func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material(colour)
	add_child(part)
	return part


## A material per colour, shared: only fixed colours come here (the turbines' pulse has its own).
func _material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var made := StandardMaterial3D.new()
		made.albedo_color = colour
		made.emission_enabled = true
		made.emission = colour
		if colour.a < 1.0:
			made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			made.cull_mode = BaseMaterial3D.CULL_DISABLED
			made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[colour] = made
	return _materials[colour]
