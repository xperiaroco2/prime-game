class_name ItemSpawnedEvent
extends MatchEvent
## An item was placed by the deal (ARCHITECTURE §3.3, §4.2): a package (Delivery) or a knife
## (SpawnItems). Emitted in item-id order, and ids follow spawn-point order, so an id follows the
## level, not the draw. A package also names its station (its circle) and that station's
## colour, which is what players see. Items on the ground are public. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var item: int
## The ItemKind's id.
var kind: StringName
var position: Vector3
## The station the item is bound to (a package's circle), or -1.
var station := -1
## That station's colour; unused without a station.
var colour := Color.WHITE


func _init(
	item_id: int,
	kind_id: StringName,
	at: Vector3,
	station_id: int = -1,
	station_colour: Color = Color.WHITE
) -> void:
	item = item_id
	kind = kind_id
	position = at
	station = station_id
	colour = station_colour


func event_name() -> StringName:
	return &"ItemSpawned"


func audience() -> Audience:
	return Audience.everyone()


## A package's station and colour are in the payload only when it has a station.
func to_dict() -> Dictionary:
	var fields := {"item": item, "kind": kind, "position": position}
	if station >= 0:
		fields["station"] = station
		fields["colour"] = colour
	return fields
