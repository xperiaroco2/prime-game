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
	fold(model, ItemPickedUpEvent.new(peer, id))


## Film `id` held by the own player and loaded into the camera.
static func load_film(model: ClientModel, id: int) -> void:
	hold(model, id, &"film")
	fold(model, FilmLoadedEvent.new(CAMERA, id))


## A shot on film `id` at the camera, shot id `shot`.
static func shoot(model: ClientModel, id: int, shot: int = 0) -> void:
	fold(model, ShotTakenEvent.new(CAMERA, id, shot))
