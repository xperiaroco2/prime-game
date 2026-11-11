extends "res://client/dev/lobby_hud_preview.gd"
## A preview of the mirror's colour menu for `tools\run.cmd shot` (#1394, §7.1.24): the estate's
## lobby hall (`levels/lobby/lobby.tscn`, read only) seen from its first mirror place towards the
## greybox mirror, the own player (a code joiner, peer 3) holding that place and Taras (2) the
## second, drawn by the game's GameUi from a fake ClientModel as a host would send it: the lobby
## HUD and the mirror's colour menu at the right, the own colour's swatch pressed. With
## `menu_closed` the own player holds no place, so the menu is hidden. Dev only: nothing here
## reaches the game.

const LOBBY := "res://levels/lobby/lobby.tscn"
const PLACE_TAG := &"spawn_mirror"
const OWN := 3

## The own player at no mirror place: the lobby as before the mirror.
@export var menu_closed := false


func _ready() -> void:
	TranslationServer.set_locale(language)
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	var room := (load(LOBBY) as PackedScene).instantiate() as Node3D
	room.name = "Level"
	add_child(room)
	_model = _fake_lobby(mode)
	var places: Array[Vector3] = []
	for node: Node in room.find_children("*", "Marker3D", true, false):
		if node.is_in_group(PLACE_TAG):
			places.append((node as Marker3D).global_position)
	var stations := PackedInt32Array()
	for index: int in places.size():
		var fields := {
			"station": index + 1,
			"kind": &"mirror",
			"colour": Color.WHITE,
			"position": places[index]
		}
		_model.fold(&"StationPlaced", fields)
		stations.append(index + 1)
	var held := PackedInt32Array([OWN, TARAS])
	if menu_closed:
		held = PackedInt32Array([-1, TARAS])
	var shown_stations := PackedInt32Array()
	var shown_peers := PackedInt32Array()
	for index: int in mini(held.size(), stations.size()):
		if held[index] >= 0:
			shown_stations.append(stations[index])
			shown_peers.append(held[index])
	_model.fold(&"MirrorPlaces", MirrorPlacesEvent.new(shown_stations, shown_peers).to_dict())
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = rules
	_avatars.clock = func() -> int: return _now
	add_child(_avatars)
	for tick: int in 6:
		_place_snapshot(tick + 1, places[1])
	var camera := Camera3D.new()
	add_child(camera)
	var eye := places[0] + Vector3(2.4, rules.eye_height_m, -0.8)
	camera.look_at_from_position(eye, places[1] + Vector3(-0.7, 1.2, 0.0))
	camera.make_current()
	var ui := GameUi.new()
	add_child(ui)
	ui.set_large_text(large_text)
	ui.plates.avatars = _avatars
	ui.show_screen(GameFlow.Screen.LOBBY)
	ui.lobby_hud.show_mic(true)
	ui.refresh(_model, mode, NOW, false)


## Taras at the second place `at`, facing the mirror, in the snapshot of `tick`.
func _place_snapshot(tick: int, at: Vector3) -> void:
	var avatars := {TARAS: {"position": at, "velocity": Vector3.ZERO, "facing": Vector3.LEFT}}
	_now += TICK_USEC
	_model.fold_snapshot({"tick": tick, "avatars": avatars})
	_avatars.buffer.add(tick, avatars, _now)
