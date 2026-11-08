class_name ClientShotBook
extends RefCounted
## The bookkeeping of the shots a ClientModel keeps (#787, photo P8), split out of the model to keep
## it a manageable size (gdlint's max-file-lines): the model's `shots` and `film_pictures` stay
## where they are, these functions only work on them. No state of their own.


## A ShotTaken's record: the shot's picture is rendered from it, and stays while a film lists the
## shot or a photo shows it. A shot id seen again is a new shot.
static func record(
	shots: Dictionary[int, ClientModel.Shot],
	film_pictures: Dictionary[int, PackedInt32Array],
	fields: Dictionary
) -> void:
	var shot_id: int = fields["shot"]
	var film_id: int = fields["film"]
	var shot := ClientModel.Shot.new()
	shot.station = fields["station"]
	shot.film = film_id
	for row: Dictionary in fields.get("record", []) as Array:
		shot.record.append(row.duplicate(true))
	unlist(film_pictures, shot_id)
	shots[shot_id] = shot
	var listed: PackedInt32Array = film_pictures.get(film_id, PackedInt32Array())
	listed.append(shot_id)
	film_pictures[film_id] = listed


## Takes `shot_id` off every film's list.
static func unlist(film_pictures: Dictionary[int, PackedInt32Array], shot_id: int) -> void:
	for film_id: int in film_pictures.keys():
		var listed := film_pictures[film_id]
		var at := listed.find(shot_id)
		if at < 0:
			continue
		listed.remove_at(at)
		if listed.is_empty():
			film_pictures.erase(film_id)
		else:
			film_pictures[film_id] = listed


## A printed photo shows its shot (PhotoPrinted), which leaves its film's list; a hung photo
## (PhotoHung) leaves the hand or belt for the board's next free slot: locked there when counted,
## else lying on it for a PickUp to take down. The host sends no ItemPlaced for a hang.
static func fold_photo(
	items: Dictionary[int, ClientModel.Item],
	stations: Dictionary[int, ClientModel.Station],
	film_pictures: Dictionary[int, PackedInt32Array],
	event_name: StringName,
	fields: Dictionary
) -> void:
	var photo: ClientModel.Item = items.get(fields["item"] as int)
	if event_name == &"PhotoPrinted":
		var shot_id: int = fields["shot"]
		unlist(film_pictures, shot_id)
		if photo != null:
			photo.shot = shot_id
		return
	var board: ClientModel.Station = stations.get(fields["station"] as int)
	if photo == null:
		return
	photo.holder = ClientModel.NO_HOLDER
	photo.belted = false
	photo.carry_place = -1
	photo.flying = false
	photo.on_station = fields["station"]
	photo.locked = fields["counted"]
	if board == null:
		return
	photo.position = board.position
	# The lowest free slot (a photo taken down), else a new one: counted photos never move.
	var slot := board.hung.find(-1)
	if slot < 0:
		board.hung.append(fields["item"] as int)
	else:
		board.hung[slot] = fields["item"]


## Drops every shot no film lists and no photo shows (the host's PhotoTask._prune, mirrored).
static func prune(
	shots: Dictionary[int, ClientModel.Shot],
	film_pictures: Dictionary[int, PackedInt32Array],
	items: Dictionary[int, ClientModel.Item]
) -> void:
	if shots.is_empty():
		return
	var kept := {}
	for listed: PackedInt32Array in film_pictures.values():
		for shot_id: int in listed:
			kept[shot_id] = true
	for item: ClientModel.Item in items.values():
		if item.shot >= 0:
			kept[item.shot] = true
	for shot_id: int in shots.keys():
		if not kept.has(shot_id):
			shots.erase(shot_id)
