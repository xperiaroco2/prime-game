class_name SettingsChangedEvent
extends MatchEvent
## The settings and what they demand of the map (ARCHITECTURE §3.2, §4.2, §9.4): an accepted
## ChangeSettings, and a join or a leave in Lobby or Countdown (the player count changes the
## demands). It carries the demands per spawn tag against the map's markers (the package count
## among them), the colours per station kind against its palette, and every reason the settings
## do not fit, so the lobby can show why `all_ready` cannot fire. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var settings: Dictionary[StringName, int] = {}
var map: String
var players: int
## Spawn tag -> markers needed.
var needed_markers: Dictionary[StringName, int] = {}
## Spawn tag -> markers the map has, for every needed tag.
var map_markers: Dictionary[StringName, int] = {}
## Station kind -> colours needed.
var needed_colours: Dictionary[StringName, int] = {}
## Station kind -> colours its palette has.
var palettes: Dictionary[StringName, int] = {}
## Why the settings do not fit (the player count, a missing marker or colour); empty when they do.
var shortfalls := PackedStringArray()


func _init(
	values: Dictionary[StringName, int],
	map_path: String,
	player_count: int,
	demands: Demands,
	layout: LevelLayout,
	problems: PackedStringArray
) -> void:
	settings = values.duplicate()
	map = map_path
	players = player_count
	needed_markers = demands.markers.duplicate()
	for tag: StringName in needed_markers:
		map_markers[tag] = layout.count(tag) if layout != null else 0
	needed_colours = demands.colours.duplicate()
	palettes = demands.palettes.duplicate()
	shortfalls = problems.duplicate()


func event_name() -> StringName:
	return &"SettingsChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {
		"settings": settings.duplicate(),
		"map": map,
		"players": players,
		"needed_markers": needed_markers.duplicate(),
		"map_markers": map_markers.duplicate(),
		"needed_colours": needed_colours.duplicate(),
		"palettes": palettes.duplicate(),
		"shortfalls": shortfalls.duplicate(),
	}
