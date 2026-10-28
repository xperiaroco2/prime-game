class_name PhotoUse
extends RefCounted
## What E offers at the photo task's stations, and the camera's frame and frames left on the
## client (#786, photo P7; the photo ADR §2, §3.1, §9; ARCHITECTURE §4.7.56), pure: from the own
## ClientModel and the client's own copy of the mode, never `core/` state. It mirrors the host's
## PhotoTask.use_problem() on what the client knows and leaves the rest to the host (§7.1); it
## only decides what to offer:
## - the photo spot: never (a `display` kind with no rule; StationUse already stops it, CE6);
## - the camera holding a film: always (a tap opens the viewfinder, a hold takes the film out with
##   PickUp, which no done task and no two-handed hand item refuses: the photo ADR's §2.4; with a
##   two-handed item in the hand the viewfinder does not open, StationUse.hand_allows_at());
## - the empty camera: the task not done and the own hand or belt carrying a fresh film (no shot
##   yet: the photo ADR's §2.2, `no_film` and `film_exposed`);
## - the film box: always (it gives once the task is done too, PD12; its cap is the host's);
## - the printer: the task not done and a film with a shot carried (`nothing_to_print`);
## - the board: the task not done and a photo carried (`no_photo`).
## The film loaded in the camera is never an item target: it lies on the camera (`on_station`),
## where TargetChoice.aim_at names no point for it.

enum Role { NONE, CAMERA, PHOTO_SPOT, FILM_BOX, PRINTER, BOARD }
## What a carried item must be for an offer (_carries).
enum Film { ANY_ITEM, FRESH, EXPOSED }


## The PhotoTask of `mode` one of whose five station kinds is `kind_id`, or null.
static func type_of(mode: GameMode, kind_id: StringName) -> PhotoTask:
	for photo: PhotoTask in PhotoTaskClient.types_of(mode):
		if role_of(photo, kind_id) != Role.NONE:
			return photo
	return null


## Which of `type`'s station kinds `kind_id` is; NONE for none.
static func role_of(type: PhotoTask, kind_id: StringName) -> Role:
	if type == null or kind_id == &"":
		return Role.NONE
	var kinds: Array[StationKind] = [
		type.camera, type.photo_spot, type.film_box, type.printer, type.board
	]
	var roles: Array[Role] = [Role.CAMERA, Role.PHOTO_SPOT, Role.FILM_BOX, Role.PRINTER, Role.BOARD]
	for i in kinds.size():
		if kinds[i] != null and kinds[i].id == kind_id:
			return roles[i]
	return Role.NONE


## Whether E offers station `id` of `type` to the own player now (see the class doc). The hand rule
## (HandNotTwoHanded) is StationUse's.
static func usable(model: ClientModel, type: PhotoTask, id: int) -> bool:
	var station: ClientModel.Station = model.stations.get(id) if model != null else null
	if station == null:
		return false
	match role_of(type, station.kind):
		Role.CAMERA:
			if station.film >= 0:
				return true
			return not task_done(model, type) and _carries(model, type.film, Film.FRESH)
		Role.FILM_BOX:
			return true
		Role.PRINTER:
			return not task_done(model, type) and _carries(model, type.film, Film.EXPOSED)
		Role.BOARD:
			return not task_done(model, type) and _carries(model, type.photo, Film.ANY_ITEM)
	return false


## Whether station `id` is a photo camera holding a film: E there taps for the viewfinder and holds
## to take the film out (ItemInteractions).
static func is_loaded_camera(model: ClientModel, mode: GameMode, id: int) -> bool:
	var station: ClientModel.Station = model.stations.get(id) if model != null else null
	if station == null or station.film < 0:
		return false
	return role_of(type_of(mode, station.kind), station.kind) == Role.CAMERA


## The frames left on camera `id`'s film: the type's `frames_per_film` less its shots; 0 when it
## holds none or is no camera.
static func frames_left(model: ClientModel, mode: GameMode, id: int) -> int:
	if not is_loaded_camera(model, mode, id):
		return 0
	var station := model.stations[id]
	return maxi(type_of(mode, station.kind).frames_per_film - station.shots, 0)


## Whether `type`'s task is done, as its TaskState told it (every subtask done); false before one.
static func task_done(model: ClientModel, type: PhotoTask) -> bool:
	for task: ClientModel.Task in model.tasks.values():
		if task.type == type.id and task.total > 0 and task.done >= task.total:
			return true
	return false


## Camera `id`'s frame (the photo ADR §3.1, PhotoFrame as the host builds it): the lens the mode's
## eye height above the camera's floor point, looking at the photo spot's the same height up, with
## the type's field of view, aspect and range; null when `id` is no camera or no photo spot is
## placed.
static func frame_of(model: ClientModel, mode: GameMode, id: int) -> PhotoFrame:
	var station: ClientModel.Station = model.stations.get(id) if model != null else null
	if station == null:
		return null
	var type := type_of(mode, station.kind)
	if role_of(type, station.kind) != Role.CAMERA or type.photo_spot == null:
		return null
	for spot: ClientModel.Station in model.stations.values():
		if spot.kind != type.photo_spot.id:
			continue
		var eye := mode.player_rules.eye_height_m if mode.player_rules != null else 0.0
		var lift := Vector3.UP * eye
		return PhotoFrame.between(
			station.position + lift, spot.position + lift, type.fov_deg, type.aspect, type.range_m
		)
	return null


## Whether the own hand or belt holds an item of `kind` in state `film`: ANY_ITEM any, FRESH one
## with no shot (the load's), EXPOSED one with a shot (the printer's).
static func _carries(model: ClientModel, kind: ItemKind, film: Film) -> bool:
	if kind == null:
		return false
	var own := model.own_peer
	for id: int in [model.hand_item(own), model.belt_item(own), model.belt_item2(own)]:
		var item: ClientModel.Item = model.items.get(id)
		if item == null or item.kind != kind.id:
			continue
		var shot := model.film_shots.get(id, 0) as int > 0
		if film == Film.ANY_ITEM or (film == Film.EXPOSED) == shot:
			return true
	return false


## Whether `kind_id` is the photo kind of one of `mode`'s photo tasks (#787: the primary button
## holds a photo up close instead of sending Use).
static func is_photo(mode: GameMode, kind_id: StringName) -> bool:
	if mode == null or kind_id == &"":
		return false
	for photo: PhotoTask in PhotoTaskClient.types_of(mode):
		if photo.photo != null and photo.photo.id == kind_id:
			return true
	return false
