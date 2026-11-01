class_name WelcomeEvent
extends MatchEvent
## A joiner's accepted Hello (ARCHITECTURE §3.5, §4.2): its peer id, spawn point, facing (#1522)
## and epoch, and the public facts of the lobby it arrives in: the roster with names, ready flags
## and colours, the settings and the map, the phase, the other players' positions, the lobby's
## name (#214) and the items already in the hall (#1404). It holds nothing hidden (§5): in Lobby
## and Countdown nobody has a role and everyone is alive, and every item fact in it was an
## everyone-event already.
## Audience: only the joiner.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY
## The most item rows a Welcome carries (#1404; not a decision): 16 players' three places (48) and
## as many lying again. The lobby's own kinds bound what lies in the hall (their `max_items`: the
## mug's 21 and the empty mug's 12 today); JoinRules leaves the rows past it out on purpose and
## records an error, and the joiner never learns of those items. WireSchema.MAX_WELCOME_ITEMS is
## its copy on the wire (a test pins the two).
const MAX_ITEMS := 96

var peer: int
var spot: Vector3
## The facing of the joiner's lobby marker (#1522), a level unit vector its client turns to;
## Vector3.ZERO when the marker has none or there is no marker (a Hello at Level.NONE): keep the
## look. Its own facing only: the others' come in the snapshots.
var facing: Vector3
var epoch: int
## Per player, in peer-id order: {"peer", "name", "ready", "colour"} (the colour an index into
## PlayerColours, #551).
var roster: Array[Dictionary] = []
var settings: Dictionary[StringName, int] = {}
var map: String
var phase: StringName
## Every other present player's last accepted position.
var positions: Dictionary[int, Vector3] = {}
## The lobby's name (MatchState.lobby_name, #214): "" while it is the default. It is in the host's
## answer itself, so the client knows it the moment it is welcomed (the SettingsChanged that
## follows carries it too).
var lobby_name := ""
## The items in the hall (#1404), each {"item", "kind", "where", "holder", "place", "position"}:
## the item id, its ItemKind id, its rest state (ItemState.Where as int: GROUND on the floor, HAND
## or BELT carried, LOCKED at a station), its carrier's peer id (0 for none), its place among the
## carrier's three (0..2; 0 when nobody carries it) and its position (a carried item's last one,
## which no client reads). The carried items come first, by peer id and then place, then the
## others in item-id order; at most MAX_ITEMS. A row carries no station-specific fact (a plate,
## the grill, a board slot, fitted, delivered): no part of Lobby or Countdown locks an item, so a
## part that does must extend the row. Nobody's selected place is in it: a carrier's HAND row
## names it, and only the own player's is ever read (a joiner carries nothing).
var items: Array[Dictionary] = []


func _init(joiner: int, at: Vector3, joiner_epoch: int, looking := Vector3.ZERO) -> void:
	peer = joiner
	spot = at
	epoch = joiner_epoch
	facing = looking


func event_name() -> StringName:
	return &"Welcome"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {
		"peer": peer,
		"spot": spot,
		"facing": facing,
		"epoch": epoch,
		"roster": roster.duplicate(true),
		"settings": settings.duplicate(),
		"map": map,
		"phase": phase,
		"positions": positions.duplicate(),
		"lobby_name": lobby_name,
		"items": items.duplicate(true),
	}
