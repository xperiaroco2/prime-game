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
## The mode whose rows add their demands, given by whoever sums them (LayoutCheck): DealTasks
## forwards its demand to this mode's task types (§9.4). Null only where no row deals tasks.
var mode: GameMode
## The set settings the demands are for (MatchState.id_sets: the host's bans of task types, which
## DealTasks leaves out of its demand). Empty: every set at its default, the empty set.
var id_sets: Dictionary[StringName, PackedStringArray] = {}


## `for_mode` is required so that no caller summing demands can forget it; null only in tests
## whose rows deal no tasks.
func _init(for_mode: GameMode) -> void:
	mode = for_mode


func add_markers(tag: StringName, count: int) -> void:
	markers[tag] = markers.get(tag, 0) + count


func add_colours(station: StationKind, count: int) -> void:
	colours[station.id] = colours.get(station.id, 0) + count
	palettes[station.id] = station.palette.size()


## The value of a set setting, empty when absent.
func id_set(id: StringName) -> PackedStringArray:
	return id_sets.get(id, PackedStringArray())


## Every shortfall against `layout`, in a stable order (tags by name, then station kinds by name),
## as HostTexts (#548): `markers` and `colours`, each with its subject and `need` and `have`.
## Empty when the map fits.
func shortfalls(layout: LevelLayout) -> Array[HostText]:
	var found: Array[HostText] = []
	var tags: Array[StringName] = []
	tags.assign(markers.keys())
	tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for tag: StringName in tags:
		var have := layout.count(tag)
		if have < markers[tag]:
			found.append(_short(HostText.MARKERS, tag, markers[tag], have))
	var stations: Array[StringName] = []
	stations.assign(colours.keys())
	stations.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for station: StringName in stations:
		if palettes[station] < colours[station]:
			found.append(_short(HostText.COLOURS, station, colours[station], palettes[station]))
	return found


static func _short(text_id: StringName, subject: StringName, need: int, have: int) -> HostText:
	return HostText.of(text_id, PackedStringArray([subject]), {&"need": need, &"have": have})
