class_name OrderPostedEvent
extends MatchEvent
## One order of Cooking (ARCHITECTURE §4.2, §9.5; the cooking ADR's CE8, CE9, #772), posted by the
## deal: its place's station id (StationPlaced's), the bun's item kind id, the fried patty's item
## kind id and the index of the herb's icon (0 to the herbs less one). It carries exactly what the
## order board shows and never the herb itself: the icon's herb is HerbsDealt's `code`, which an
## honest client draws only on the herb board (CE9 (a)), so a fold that draws the order board holds
## no herb to show by mistake. It names no player (the ADR's §3, "Who did it"), held apart from
## this declaration by a unit test. Audience: everyone (as the Generator's GE6 (a)).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The order's place: its station id.
var station: int
## The bun's item kind id.
var bun: StringName
## The fried patty's item kind id: what the place takes, and the look the board shows.
var patty: StringName
## The index of the herb's icon.
var icon: int


func _init(station_id: int, bun_id: StringName, patty_id: StringName, icon_index: int) -> void:
	station = station_id
	bun = bun_id
	patty = patty_id
	icon = icon_index


func event_name() -> StringName:
	return &"OrderPosted"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "bun": bun, "patty": patty, "icon": icon}
