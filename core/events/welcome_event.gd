class_name WelcomeEvent
extends MatchEvent
## A joiner's accepted Hello (ARCHITECTURE §3.5, §4.2): its peer id, spawn point and epoch, and
## the public facts of the lobby it arrives in: the roster with names and ready flags, the
## settings and the map, the phase, the other players' positions and the lobby's name (#214). It
## holds nothing hidden (§5): in Lobby and Countdown nobody has a role, and everyone is alive.
## Audience: only the joiner.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
var spot: Vector3
var epoch: int
## Per player, in peer-id order: {"peer", "name", "ready"}.
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


func _init(joiner: int, at: Vector3, joiner_epoch: int) -> void:
	peer = joiner
	spot = at
	epoch = joiner_epoch


func event_name() -> StringName:
	return &"Welcome"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {
		"peer": peer,
		"spot": spot,
		"epoch": epoch,
		"roster": roster.duplicate(true),
		"settings": settings.duplicate(),
		"map": map,
		"phase": phase,
		"positions": positions.duplicate(),
		"lobby_name": lobby_name,
	}
