class_name FixturePhotoClient
extends RefCounted
## A client's view of a dealt photo task (#786, photo P7), for the client's tests: a ClientModel of
## FixturePhotoModes.basic() fed the events a client receives (StationPlaced for the five stations,
## ItemSpawned, ItemPickedUp, FilmLoaded, ShotTaken, TaskState), never `core/` state. Station ids
## CAMERA, SPOT, BOX, PRINTER and BOARD in the deal's order; where they stand is the caller's
## (`at`, by default FixturePhotoModes' markers). Kind ids are the fixture's (`camera`,
## `film`, ...).

const CAMERA := 30
const SPOT := 31
const BOX := 32
const PRINTER := 33
const BOARD := 34
const OWN := 1
const OTHER := 2
## The photo task's id in TaskState.
const TASK := 0


## A model of FixturePhotoModes.basic() in its round, the own peer OWN, with the five stations
## placed: `at` gives each station id its floor point (FixturePhotoModes' markers where it has
## none).
static func dealt(at: Dictionary[int, Vector3] = {}) -> ClientModel:
	var model := ClientModel.new(FixturePhotoModes.basic())
	model.own_peer = OWN
	fold(model, PhaseChangedEvent.new(&"round", 1000))
	var kinds: Array[StringName] = [&"camera", &"photo_spot", &"film_box", &"printer", &"board"]
	var spots: Array[Vector3] = [
		FixturePhotoModes.CAMERA_AT,
		FixturePhotoModes.SPOT_AT,
		FixturePhotoModes.BOX_AT,
		FixturePhotoModes.PRINTER_AT,
		FixturePhotoModes.BOARD_AT,
	]
	for i in kinds.size():
		var id := CAMERA + i
		var point: Vector3 = at.get(id, spots[i])
		fold(model, StationPlacedEvent.new(id, kinds[i], Color.WHITE, point))
	fold(model, TaskStateEvent.new(TASK, &"photo", 0, 2))
	return model


## Folds `event` into `model`, as the session does with what it decodes.
static func fold(model: ClientModel, event: MatchEvent) -> void:
	model.fold(event.event_name(), event.to_dict())


## Item `id` of kind `kind` spawned at `at` and picked up by `peer` (OWN by default).
static func hold(
	model: ClientModel, id: int, kind: StringName, peer: int = OWN, at := Vector3(0, 0, 25)
) -> void:
	fold(model, ItemSpawnedEvent.new(id, kind, at))
	# Into its selected place, as a take with that place empty goes (GDD §6).
	fold(model, ItemPickedUpEvent.new(peer, id, -1, model.selected_place(peer)))


## Film `id` held by the own player and loaded into the camera.
static func load_film(model: ClientModel, id: int) -> void:
	hold(model, id, &"film")
	fold(model, FilmLoadedEvent.new(CAMERA, id))


## A shot on film `id` at the camera, shot id `shot`, with the record `record` (#787).
static func shoot(
	model: ClientModel, id: int, shot: int = 0, record: Array[Dictionary] = []
) -> void:
	fold(model, ShotTakenEvent.new(CAMERA, id, shot, record))


## Photo `photo_id` printed from shot `shot` (#787): spawned at `at` (the tray), bound to the shot
## by PhotoPrinted; then film `film` vanishes when `film_goes` (every shot of it printed).
static func printed(
	model: ClientModel,
	film: int,
	photo_id: int,
	shot: int,
	film_goes := true,
	at := FixturePhotoModes.PRINTER_AT,
) -> void:
	fold(model, ItemSpawnedEvent.new(photo_id, &"photo", at))
	fold(model, PhotoPrintedEvent.new(photo_id, shot))
	if film_goes:
		fold(model, ItemVanishedEvent.new(film))


## Photo `photo_id`, held by the own player, hung on the board (#787): PhotoHung, `counted` or not.
static func hang(model: ClientModel, photo_id: int, counted: bool) -> void:
	fold(model, PhotoHungEvent.new(photo_id, BOARD, counted))


## A record row for peer `peer` standing at `at` facing `facing` (#787).
static func row(
	peer: int, at: Vector3, facing := Vector3.FORWARD, downed := false, held := -1
) -> Dictionary:
	return {
		"peer": peer,
		"position": at,
		"facing": facing,
		"downed": downed,
		"crouched": false,
		"held_item": held,
		"belt_item": -1,
		"belt_item2": -1,
	}
