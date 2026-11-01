class_name ShipStationLooks
extends RefCounted
## The ship's station devices' looks driven by the engine (#1550, ARCHITECTURE §9.5.27): binds the
## level's start console, crystal sockets, breaker boards and crystal chargers (found by the scene
## they are instances of, DEVICES) to the engine's stations, puts each package's look on (the
## ports ShipConsoleLook, ShipSocketLook, ShipBoardLook, ShipChargerLook) and sets every look value
## each frame from the own filtered ClientModel and the estimated host tick, as ShipEngineViews
## draws the rest, so every peer shows the same. Nothing is predicted; no look names a player.
## - Binding: a station takes the nearest free device of its kind within BIND_M on the floor; a
##   breaker takes the nearest bound board, and its shell by its rank along the board's local +X
##   (red, yellow, green, blue as you face it; the 0.5 m markers are 0.34 m shells apart, so only
##   the rank holds). A station with no device keeps ShipEngineViews' stand-in lamp.
## - The console: its clock is the host tick's; the bar is the console's ZoneProgress share (passed
##   0); the call while ShipEngineHologram.called(), pulsing every PULSE_SECONDS from half a period,
##   so its onset is the beep's tick (ShipEngineSounds); the fans at SPIN_RAD_PER_SECOND while not
##   calling, each broken station halving them (the art's rule); a wiring point per site station
##   (site_slot: its side and, for a socket, front or back in the console's own frame): "off" while
##   calling, "broken" while a problem holds it (blinking as the stand-in's: the nearest deadline
##   fastest), "fixed" on its release (none at a blast), else "ok"; the countdown to the nearest
##   deadline; the order lamp of the breaker the order plays on now (its wing and its shell's
##   colour, so the lamp's colour is the shell's).
## - A socket: "charged" with no problem, "empty" while its crystal is out (an item), else "spent";
##   the claws open while it is empty, eased over the drawing's 0.25 s and closed over 0.15 s.
## - A board: per bound breaker of the open chain, tripped (shell open, lamp dark), the last one on
##   during its ramp (lamp yellow) or on (green); the beacon while any of its shells is tripped.
## - A charger: by the phase of the crystal it holds: "charging" (the carrier rising and turning,
##   the ring turning, the button in), "charged" (waiting) or "idle".
## The timings HANDOFF leaves to the game are placeholders, "not a decision".

## The device scenes a level instances, by what they are.
const DEVICES: Dictionary[String, StringName] = {
	"res://assets/environment/start_console/start_console.glb": &"console",
	"res://levels/kit/crystal_socket/crystal_socket.tscn": &"socket",
	"res://levels/kit/breaker_board/breaker_board.tscn": &"board",
	"res://levels/kit/crystal_charger/crystal_charger.tscn": &"charger",
}
## How far a device may stand from its station's use spot on the floor, in metres (the chargers'
## stand 1.4 m off).
const BIND_M := 2.5
## The claws' open and close, the shells' trip and close, seconds (the claws the drawing's; the
## shells "not a decision").
const CLAWS_OPEN_SECONDS := 0.25
const CLAWS_CLOSE_SECONDS := 0.15
const SHELL_TRIP_SECONDS := 0.25
const SHELL_CLOSE_SECONDS := 0.4
## The charger while charging: the carrier's and the ring's turns a second and the carrier's rise's
## seconds from the charge's start ("not a decision").
const CARRIER_TURNS_PER_SECOND := 0.5
const RING_TURNS_PER_SECOND := -0.25
const CARRIER_RISE_SECONDS := 0.5

var _model: ClientModel
var _console_id := -1
var _console: ShipConsoleLook
var _console_node: Node3D
var _sockets: Dictionary[int, ShipSocketLook] = {}
var _boards: Dictionary[int, ShipBoardLook] = {}
var _chargers: Dictionary[int, ShipChargerLook] = {}
## Per bound breaker station: its board station, its shell and the console's lamp for it.
var _board_of: Dictionary[int, int] = {}
var _shell: Dictionary[int, int] = {}
var _lamp: Dictionary[int, int] = {}
## Per site station: its wiring point on the console.
var _slot: Dictionary[int, String] = {}
## The wiring points some site station took (set once at bind, read each frame).
var _taken: Dictionary[String, bool] = {}
## Per site station: what it is on the wiring ("socket", "breaker", "vent").
var _site_what: Dictionary[int, String] = {}
var _held: Dictionary[int, bool] = {}
var _claws: Dictionary[int, float] = {}
var _open: Dictionary[int, float] = {}
var _breakers: BreakersProblem
var _crystals: CrystalProblem
var _fresh := true


## Binds the devices under `level` (null: none) to the stations of the engine `type` in `model`.
func bind(model: ClientModel, type: ShipEngine, level: Node, console_id: int) -> void:
	_model = model
	_console_id = console_id
	var found: Dictionary[StringName, Array] = {
		&"console": [], &"socket": [], &"board": [], &"charger": []
	}
	if level != null:
		for node: Node in level.find_children("*", "Node3D", true, false):
			var what: StringName = DEVICES.get(node.scene_file_path, &"")
			if what != &"":
				found[what].append(node)
	var console_at := _nearest(found[&"console"], console_id)
	if console_at != null:
		_console = ShipConsoleLook.apply(console_at, ShipEngineHologram.PULSE_SECONDS)
		if _console != null:
			_console_node = console_at
			_console.set_passed(0)
	var sites: Array[int] = []
	for kind: ProblemKind in type.kinds:
		var site_ids := _ids_of(kind.site)
		sites.append_array(site_ids)
		for id: int in site_ids:
			_site_what[id] = _what(kind)
		if kind is CrystalProblem:
			_crystals = kind as CrystalProblem
			for id: int in site_ids:
				var node := _take(found[&"socket"], id)
				var socket := ShipSocketLook.apply(node) if node != null else null
				if socket != null:
					_sockets[id] = socket
			for fixture: StationKind in kind.fixtures:
				for id: int in _ids_of(fixture):
					var node := _take(found[&"charger"], id)
					var charger := ShipChargerLook.apply(node) if node != null else null
					if charger != null:
						_chargers[id] = charger
		elif kind is BreakersProblem:
			_breakers = kind as BreakersProblem
			_bind_boards(kind, site_ids, found[&"board"])
	if _console != null:
		for site: int in sites:
			var slot := _slot_of(site)
			if slot != "" and not _taken.has(slot):
				_slot[site] = slot
				_taken[slot] = true
		for breaker: int in _shell:
			var board_side := _slot_of(_board_of[breaker])
			var wing := 4 if board_side.ends_with("_e") else 0
			_lamp[breaker] = wing + _shell[breaker]


## Sets every look at host tick `now`: `share` the console's bar, `hologram` the engine's state
## readers, `order_lit` the breaker station the order plays on now (-1 none) and `blasted` whether
## a blast took the problems this frame.
func update(
	now: int,
	delta: float,
	hologram: ShipEngineHologram,
	share: float,
	order_lit: int,
	blasted: bool,
) -> void:
	if _console != null:
		_update_console(now, hologram, share, order_lit, blasted)
	for id: int in _sockets:
		_update_socket(id, delta)
	_update_boards(now, delta)
	for id: int in _chargers:
		_update_charger(id, now)
	for site: int in _slot:
		_held[site] = _model.engine.problem_at(site) != null
	_fresh = false


## The console's look, or null with no console device bound.
func console() -> ShipConsoleLook:
	return _console


## The socket station `id`'s look, or null.
func socket_of(id: int) -> ShipSocketLook:
	return _sockets.get(id)


## The board station `id`'s look, or null.
func board_of(id: int) -> ShipBoardLook:
	return _boards.get(id)


## The charger station `id`'s look, or null.
func charger_of(id: int) -> ShipChargerLook:
	return _chargers.get(id)


## The shell (ShipBoardLook.COLOURS' index) breaker station `id` is bound to, or -1.
func shell_of(id: int) -> int:
	return _shell.get(id, -1)


## The board station breaker `id` is bound to, or -1.
func board_station_of(id: int) -> int:
	return _board_of.get(id, -1)


## The console's order lamp for breaker station `id`, or -1.
func lamp_of(id: int) -> int:
	return _lamp.get(id, -1)


## The console's wiring point of site station `id`, or "".
func slot_of(id: int) -> String:
	return _slot.get(id, "")


## Whether station `id`'s device draws it (no stand-in lamp is needed over it).
func has_art(id: int) -> bool:
	return _sockets.has(id) or _boards.has(id) or _chargers.has(id) or _shell.has(id)


## The wiring point of a site of `what` ("socket", "breaker" or "vent") at `local`, a place in
## the console's own frame: its front (glTF +Z, the button) faces the ship's mouth, so the ship's
## east is the console's -X and its front the console's +Z.
static func site_slot(what: String, local: Vector3) -> String:
	var side := "e" if local.x < 0.0 else "w"
	if what == "socket":
		return "socket_" + ("f" if local.z > 0.0 else "") + side
	return what + "_" + side


## `node`'s transform relative to its ancestor `root` (no tree needed).
static func relative(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			t = (at as Node3D).transform * t
		at = at.get_parent()
	return t


func _update_console(
	now: int, hologram: ShipEngineHologram, share: float, order_lit: int, blasted: bool
) -> void:
	_console.set_clock(float(maxi(now, 0)) / Ticks.RATE)
	_console.set_charge(share)
	var calling := hologram.called()
	_console.set_calling(calling, ShipEngineHologram.PULSE_SECONDS / 2.0)
	_console.set_spin(0.0 if calling else ShipEngineHologram.SPIN_RAD_PER_SECOND / TAU)
	var nearest := hologram.nearest_deadline()
	_console.set_countdown(-1.0 if nearest < 0 else maxf(0.0, float(nearest - now)) / Ticks.RATE)
	for site: int in _slot:
		var problem := _model.engine.problem_at(site)
		var slot := _slot[site]
		if calling:
			_set_station(slot, "off", 1.0)
		elif problem != null:
			var fast := problem.deadline == nearest
			var step := (
				ShipEngineHologram.BLINK_FAST_SECONDS
				if fast
				else ShipEngineHologram.BLINK_SLOW_SECONDS
			)
			_set_station(slot, "broken", 1.0 / (2.0 * step))
		elif _held.get(site, false) and not blasted and not _fresh:
			_console.set_station(slot, "fixed")
		else:
			_set_station(slot, "ok", 1.0)
	# A wiring point with no site station of its own reads as the rest: off while calling, else ok.
	for slot: String in ShipConsoleLook.STATIONS:
		if not _taken.has(slot):
			_set_station(slot, "off" if calling else "ok", 1.0)
	var lit: int = _lamp.get(order_lit, -1)
	_console.set_lit(lit)


func _set_station(slot: String, state: String, blink_hz: float) -> void:
	var blink := maxf(blink_hz, ShipConsoleLook.BLINK_MIN)
	if _console.station_state(slot) != state or _console.station_blink(slot) != blink:
		_console.set_station(slot, state, blink_hz)


func _update_socket(id: int, delta: float) -> void:
	var look := _sockets[id]
	var crystal: ClientEngineBook.Crystal = _model.engine.crystals.get(id)
	var state := "charged"
	if _model.engine.problem_at(id) != null:
		state = "empty" if crystal != null and crystal.item >= 0 else "spent"
	look.set_state(state)
	var target := 1.0 if state == "empty" else 0.0
	var claws: float = _claws.get(id, target)
	if not _fresh:
		var seconds := CLAWS_OPEN_SECONDS if target > claws else CLAWS_CLOSE_SECONDS
		claws = move_toward(claws, target, delta / seconds)
	else:
		claws = target
	_claws[id] = claws
	look.set_claws(claws)


func _update_boards(now: int, delta: float) -> void:
	var tripped: Dictionary[int, bool] = {}
	var lamp: Dictionary[int, int] = {}
	for problem: ClientEngineBook.Problem in _model.engine.problems.values():
		var order := problem.breakers
		for i in order.size():
			if i >= problem.next:
				tripped[order[i]] = true
				lamp[order[i]] = ShipBoardLook.DARK
			elif (
				i == problem.next - 1
				and problem.since >= 0
				and _breakers != null
				and now - problem.since < _breakers.ramp_ticks()
			):
				lamp[order[i]] = ShipBoardLook.YELLOW
	var alarm: Dictionary[int, bool] = {}
	for breaker: int in _shell:
		var board := _boards[_board_of[breaker]]
		var shell := _shell[breaker]
		var target := 1.0 if tripped.has(breaker) else 0.0
		var open: float = _open.get(breaker, target)
		if not _fresh:
			var seconds := SHELL_TRIP_SECONDS if target > open else SHELL_CLOSE_SECONDS
			open = move_toward(open, target, delta / seconds)
		else:
			open = target
		_open[breaker] = open
		board.set_shell(shell, open)
		var shows: int = lamp.get(breaker, ShipBoardLook.GREEN)
		board.set_lamp(shell, shows)
		if tripped.has(breaker):
			alarm[_board_of[breaker]] = true
	for id: int in _boards:
		_boards[id].set_problem(alarm.has(id))


func _update_charger(id: int, now: int) -> void:
	var look := _chargers[id]
	var held: ClientEngineBook.Crystal = null
	for socket: int in _model.engine.crystals:
		var crystal: ClientEngineBook.Crystal = _model.engine.crystals[socket]
		if crystal.charger == id:
			held = crystal
	if held == null or held.phase == CrystalProblem.LOADED or held.phase == CrystalProblem.EMPTY:
		look.set_state("idle")
	elif held.phase == CrystalProblem.WAITING:
		look.set_state("charged")
	else:
		look.set_state("charging")
		var ticks := _crystals.charge_ticks() if _crystals != null else 0
		var seconds := maxf(0.0, float(now - (held.tick - ticks))) / Ticks.RATE
		look.set_carrier(
			clampf(seconds / CARRIER_RISE_SECONDS, 0.0, 1.0),
			fposmod(TAU * CARRIER_TURNS_PER_SECOND * seconds, TAU)
		)
		look.set_ring(fposmod(TAU * RING_TURNS_PER_SECOND * seconds, TAU))
		look.set_pressed(true)


## Binds each board station to its device, and each breaker to its board and shell.
func _bind_boards(kind: ProblemKind, boards: Array[int], devices: Array) -> void:
	var nodes: Dictionary[int, Node3D] = {}
	for id: int in boards:
		var node := _take(devices, id)
		var look := ShipBoardLook.apply(node) if node != null else null
		if look != null:
			_boards[id] = look
			nodes[id] = node
	if nodes.is_empty():
		return
	var on_board: Dictionary[int, Array] = {}
	for fixture: StationKind in kind.fixtures:
		for breaker: int in _ids_of(fixture):
			var at := _model.stations[breaker].position
			var best := -1
			for id: int in nodes:
				if (
					best < 0
					or (
						_floor(nodes[id].global_position, at)
						< _floor(nodes[best].global_position, at)
					)
				):
					best = id
			if _floor(nodes[best].global_position, at) <= BIND_M:
				if not on_board.has(best):
					on_board[best] = []
				on_board[best].append(breaker)
	for board: int in on_board:
		var node := nodes[board]
		var ranked: Array = on_board[board]
		var along := func(id: int) -> float:
			return (_model.stations[id].position - node.global_position).dot(node.global_basis.x)
		ranked.sort_custom(func(a: int, b: int) -> bool: return along.call(a) < along.call(b))
		for rank in mini(ranked.size(), ShipBoardLook.COLOURS.size()):
			var breaker: int = ranked[rank]
			_board_of[breaker] = board
			_shell[breaker] = rank


## Removes and gives the device in `devices` nearest station `id` within BIND_M, or null.
func _take(devices: Array, id: int) -> Node3D:
	var node := _nearest(devices, id)
	if node != null:
		devices.erase(node)
	return node


func _nearest(devices: Array, id: int) -> Node3D:
	var station: ClientModel.Station = _model.stations.get(id)
	if station == null:
		return null
	var best: Node3D = null
	for node: Node3D in devices:
		var d := _floor(node.global_position, station.position)
		if d <= BIND_M and (best == null or d < _floor(best.global_position, station.position)):
			best = node
	return best


## The wiring point of site station `id` on the bound console, or "".
func _slot_of(id: int) -> String:
	var station: ClientModel.Station = _model.stations.get(id)
	if station == null or _console_node == null:
		return ""
	var what: String = _site_what.get(id, "")
	if what == "":
		return ""
	return site_slot(what, _console_node.global_transform.affine_inverse() * station.position)


## What a site of `kind` is on the console's wiring ("socket", "breaker", "vent"), or "".
static func _what(kind: ProblemKind) -> String:
	if kind is CrystalProblem:
		return "socket"
	if kind is BreakersProblem:
		return "breaker"
	if kind is GillsProblem:
		return "vent"
	return ""


func _ids_of(kind: StationKind) -> Array[int]:
	var found: Array[int] = []
	if kind == null:
		return found
	for id: int in _model.stations:
		if _model.stations[id].kind == kind.id:
			found.append(id)
	found.sort()
	return found


static func _floor(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
