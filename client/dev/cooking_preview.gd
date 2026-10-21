extends Node3D
## A preview of Cooking's client view (#776, the cooking ADR's §8 C7) for `tools\run.cmd shot`: the
## level's real station scenes (`levels/stations/`) driven by CookingViews and ItemViews from a fake
## ClientModel: the order board with two numbered rows, the herb board's dealt pairs, the five beds'
## plants, a full plate (three ingredients) beside a plate with a bun and a herb, each with the one
## filled-slot outline (#1101: nothing says right or wrong before a serve), a third place unused
## (bare counter) with a plated burger lying in front of it (#1101: its three parts), and the
## grill with a patty on it and its ring part filled. With `wall`, a wall stands between the
## camera and the counters: no outline, ring, row or plant may show through it (the M4 render
## checklist). The Cooking is built here with C6's kind ids (#775: `content/` has
## none yet) and preview-only fry and burn seconds; dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const Kit := preload("res://client/dev/preview_kit.gd")
const SCENES := "res://levels/stations/%s.tscn"
const OWN := 1
const ORDER_BOARD := 10
const HERB_BOARD := 11
const GRILL := 12
const FIRST_BED := 13
const FIRST_PLACE := 20
## Where each scene stands (each faces +z, its use spot in front of it).
const AT: Dictionary[StringName, Vector3] = {
	&"order_board": Vector3(-2.4, 0, 0),
	&"herb_board": Vector3(-0.8, 0, 0),
	&"grill": Vector3(0.6, 0, 0),
	&"herb_beds": Vector3(0, 0, -3.5),
}
const PLACES: Array[Vector3] = [Vector3(1.7, 0, 0), Vector3(2.7, 0, 0), Vector3(3.7, 0, 0)]
const BUNS: Array[StringName] = [&"bun_white", &"bun_sesame", &"bun_dark"]
const RAW: Array[StringName] = [&"patty_light_raw", &"patty_red_raw", &"patty_deep_red_raw"]
const FRIED: Array[StringName] = [&"patty_light", &"patty_red", &"patty_deep_red"]
const HERBS: Array[StringName] = [&"basil", &"dill", &"rosemary", &"chives", &"mint"]
const NOW := 2000

@export var wall := false

var _level := Node3D.new()


func _ready() -> void:
	var mode := _mode()
	var model := ClientModel.new(mode)
	model.own_peer = OWN
	model.fold(&"PhaseChanged", {"phase": &"round", "ends_at_tick": NOW + 2000})
	_level.name = "Level"
	add_child(_level)
	_build_room()
	for kind: StringName in [&"order_board", &"herb_board", &"grill"]:
		_add(kind, AT[kind])
	for at: Vector3 in PLACES:
		_add(&"place", at)
	var beds := _add(&"herb_beds", AT[&"herb_beds"])
	Kit.place(model, ORDER_BOARD, &"order_board", _spot(_level.get_child(0)))
	Kit.place(model, HERB_BOARD, &"herb_board", _spot(_level.get_child(1)))
	Kit.place(model, GRILL, &"grill", _spot(_level.get_child(2)))
	for k: int in 5:
		Kit.place(model, FIRST_BED + k, &"herb_bed", _spot(beds.get_node("Bed%d" % (k + 1))))
	for i: int in 2:
		Kit.place(model, FIRST_PLACE + i, &"place", _spot(_level.get_child(3 + i)))
		model.fold(
			&"OrderPosted",
			{"station": FIRST_PLACE + i, "bun": BUNS[i], "patty": FRIED[i + 1], "icon": i * 2}
		)
	var code := PackedStringArray(HERBS)
	var dealt := PackedStringArray([&"mint", &"basil", &"chives", &"dill", &"rosemary"])
	model.fold(&"HerbsDealt", {"code": code, "beds": dealt})
	_fill(model, mode)
	var cooking := CookingViews.new()
	cooking.model = model
	cooking.mode = mode
	cooking.host_tick = func() -> int: return NOW
	add_child(cooking)
	cooking.level = _level
	var items := ItemViews.new()
	items.model = model
	items.mode = mode
	items.station_point = cooking.point_of
	add_child(items)
	var camera := Camera3D.new()
	camera.transform = Transform3D(Basis.from_euler(Vector3(-0.4, 0, 0)), Vector3(0.6, 2.3, 3.0))
	add_child(camera)
	camera.current = true


## The plates and the grill: place 1 full (a bun, a fried patty and a herb), place 2 with a bun
## and a herb, the grill's patty a third of the way to fried.
func _fill(model: ClientModel, mode: GameMode) -> void:
	var type := CookingUse.types_of(mode)[0]
	var puts := [
		[50, BUNS[0], 0],
		[51, FRIED[1], 0],
		[52, &"mint", 0],
		[53, BUNS[1], 1],
		[54, &"dill", 1],
	]
	for put: Array in puts:
		_hold(model, put[0] as int, put[1] as StringName)
		var fields := {"item": put[0], "station": FIRST_PLACE + (put[2] as int)}
		model.fold(&"IngredientPlaced", fields)
	_hold(model, 60, RAW[2])
	var fried := NOW + roundi(type.fried_ticks() * 2 / 3.0)
	var burnt := fried + type.burnt_ticks() - type.fried_ticks()
	model.fold(&"GrillLoaded", {"station": GRILL, "item": 60, "fried": fried, "burnt": burnt})
	var burger := {"item": 70, "kind": &"burger", "position": PLACES[2] + Vector3(0, 0, 0.6)}
	model.fold(&"ItemSpawned", burger)
	var parts := {"bun": BUNS[2], "patty": FRIED[0], "herb": &"basil"}
	parts.merge({"item": 70, "station": FIRST_PLACE})
	model.fold(&"BurgerPlated", parts)


func _hold(model: ClientModel, id: int, kind: StringName) -> void:
	model.fold(&"ItemSpawned", {"item": id, "kind": kind, "position": Vector3(0, 0, 9)})
	model.fold(&"ItemPickedUp", {"peer": OWN, "item": id})


func _add(scene: StringName, at: Vector3) -> Node3D:
	var made := (load(SCENES % scene) as PackedScene).instantiate() as Node3D
	made.position = at
	_level.add_child(made)
	return made


func _spot(root: Node) -> Vector3:
	return (root.get_node("UseSpot") as Node3D).global_position


## A Cooking with C6's kind ids (#775), on a copy of the base mode; its fry and burn seconds are
## the preview's, "not a decision".
func _mode() -> GameMode:
	var base := load(Preview.MODE) as GameMode
	var mode := base.duplicate() as GameMode
	var type := Cooking.new()
	type.id = &"cooking"
	type.order_board = _station(&"order_board", false)
	type.herb_board = _station(&"herb_board", true)
	type.grill = _station(&"grill", false)
	type.herb_bed = _station(&"herb_bed", false)
	type.place = _station(&"place", false)
	type.buns = _items(BUNS)
	type.raw_patties = _items(RAW)
	type.fried_patties = _items(FRIED)
	type.burnt = _items([&"patty_burnt"])[0]
	type.herbs = _items(HERBS)
	type.fry_seconds = 6.0
	type.burn_seconds = 6.0
	var types: Array[TaskType] = mode.task_types.duplicate()
	types.append(type)
	mode.task_types = types
	return mode


func _station(id: StringName, display: bool) -> StationKind:
	var kind := StationKind.new()
	kind.id = id
	kind.display = display
	kind.spawn_tag = id
	return kind


func _items(ids: Array[StringName]) -> Array[ItemKind]:
	var kinds: Array[ItemKind] = []
	for id: StringName in ids:
		var kind := ItemKind.new()
		kind.id = id
		kinds.append(kind)
	return kinds


func _build_room() -> void:
	Kit.box(self, Vector3(0, -0.05, 0), Vector3(16, 0.1, 16), Color(0.45, 0.45, 0.47))
	if wall:
		Kit.box(self, Vector3(2.6, 0.9, 1.5), Vector3(5.2, 1.8, 0.2), Color(0.6, 0.58, 0.55))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
