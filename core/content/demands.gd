class_name Demands
extends RefCounted
## What a match needs of a map (ARCHITECTURE §9.4): markers per spawn tag, and colours per station
## kind. Every placing action and every task type adds its own; the lobby's `all_ready` (2b)
## compares the sums with the chosen map's LevelLayout, and SettingsChanged shows them.

## Spawn tag -> markers needed.
var markers: Dictionary[StringName, int] = {}
## Station kind id -> colours needed (colours never repeat within a station kind).
var colours: Dictionary[StringName, int] = {}
## Station kind id -> colours its palette has.
var palettes: Dictionary[StringName, int] = {}


func add_markers(tag: StringName, count: int) -> void:
	markers[tag] = markers.get(tag, 0) + count


func add_colours(station: StationKind, count: int) -> void:
	colours[station.id] = colours.get(station.id, 0) + count
	palettes[station.id] = station.palette.size()


## Every shortfall against `layout`, in a stable order; empty when the map fits.
func shortfalls(layout: LevelLayout) -> PackedStringArray:
	var found := PackedStringArray()
	var tags: Array[StringName] = []
	tags.assign(markers.keys())
	tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for tag: StringName in tags:
		var have := layout.count(tag)
		if have < markers[tag]:
			found.append("%d %s marker(s) needed, the map has %d" % [markers[tag], tag, have])
	var stations: Array[StringName] = []
	stations.assign(colours.keys())
	stations.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for station: StringName in stations:
		if palettes[station] < colours[station]:
			found.append(
				(
					"%d %s colour(s) needed, the palette has %d"
					% [colours[station], station, palettes[station]]
				)
			)
	return found
