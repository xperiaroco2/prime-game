class_name ShotTakenEvent
extends MatchEvent
## The photo camera took a shot (ARCHITECTURE §4.2, §9.5; the photo ADR §2.3, §3.3, #781) by an
## accepted Interact: the camera's station id, the film's item id, the shot's id (which a later
## PhotoPrinted names, so a client binds a printed photo to its picture) and the record, the poses
## a client renders the picture from: one row per player with an avatar (alive or knocked down)
## within the camera's range plus PhotoTask.RECORD_MARGIN_M of the lens, its feet outside the
## camera's cylinder, in peer order, at most PhotoTask.MAX_RECORD rows. A row is the snapshot's
## avatar row without its velocity and invulnerability, plus its peer: `peer`, `position`,
## `facing`, `downed`, `crouched` (the crouch ADR, KE2), `held_item`, `belt_item`, `belt_item2`
## (-1: none).
##
## Audience: everyone. The record holds what every player receives in the snapshots anyway, taken
## at the shot's command; the one addition is the recipient's own pose, which it knows (§3.3). It
## names no shooter (everyone in the cylinder is left out alike, PD13) and never says whether the
## shot has a person (PE5: the hang tells that).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The camera's station id.
var station: int
## The film's item id.
var film: int
## The shot's id (PhotoTask's, wrapping at 0x10000).
var shot: int
var record: Array[Dictionary] = []


func _init(station_id: int, film_id: int, shot_id: int, rows: Array[Dictionary] = []) -> void:
	station = station_id
	film = film_id
	shot = shot_id
	record = rows


func event_name() -> StringName:
	return &"ShotTaken"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "film": film, "shot": shot, "record": record.duplicate(true)}
