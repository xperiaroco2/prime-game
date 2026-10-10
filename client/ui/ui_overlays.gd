class_name UiOverlays
extends RefCounted
## The overlays Esc closes, one per press, the topmost first (#488 rule 2, the UI handoffs'
## «Layers and input», ARCHITECTURE §4.7.35): a how-to card over the map, the map; the Esc menu's
## question to the host over the menu. Esc opens the Esc menu only when none is open (Game._input).
## Each overlay registers what tells whether it is open and what closes it; `is_open` is asked on
## every press, so an overlay needs no signal. An overlay whose object was freed counts as closed:
## a freed card never holds Esc.
##
## Two things are not here: a key capture in Settings > Controls takes Esc in its own _input,
## which runs before the game's (ControlsPanel), and the black screens' Esc is their Cancel or Back
## (screens, not overlays: Game._input asks them first).

## The main menu's open page (no session: no Esc menu under it).
const MENU_PANEL := 10
## The tutorial's invite (#492; layer 2 of the handoffs, s1): Esc is its Skip.
const INVITE := 20
## The map and tasks screen (layer 3 of the handoffs).
const MAP := 30
## A how-to card over the map (#254; layer 3, above the map).
const CARD := 35
## The Esc menu (layer 4).
const ESC_MENU := 40
## The Esc menu's question to the host before Leave or Quit (layer 5).
const ESC_DIALOG := 50


## One registered overlay.
class Entry:
	var id: StringName
	var layer: int
	var is_open: Callable
	var close: Callable
	## The map key closes it too (a card over the map, rule 3).
	var closes_on_map_key: bool

	func open() -> bool:
		return is_open.is_valid() and is_open.call() as bool


var _entries: Array[Entry] = []


## Registers the overlay `id` on `layer` (a higher layer is above); one already under `id` is
## replaced. At one layer the one added later is above.
func add(
	id: StringName, layer: int, is_open: Callable, close: Callable, closes_on_map_key := false
) -> void:
	remove(id)
	var entry := Entry.new()
	entry.id = id
	entry.layer = layer
	entry.is_open = is_open
	entry.close = close
	entry.closes_on_map_key = closes_on_map_key
	_entries.append(entry)


func remove(id: StringName) -> void:
	for i in range(_entries.size() - 1, -1, -1):
		if _entries[i].id == id:
			_entries.remove_at(i)


func has(id: StringName) -> bool:
	return _entry(id) != null


## The open overlay on top, or &"" when none is open.
func top() -> StringName:
	var entry := _top()
	return entry.id if entry != null else &""


func is_any_open() -> bool:
	return _top() != null


## Esc: closes the open overlay on top, only that one, and returns its id; &"" when none was open.
func close_top() -> StringName:
	var entry := _top()
	if entry == null:
		return &""
	if entry.close.is_valid():
		entry.close.call()
	return entry.id


## The map key: closes the open overlay on top if the map key closes it (a card), and says whether
## it did; else the key is the map's.
func close_top_for_map_key() -> bool:
	var entry := _top()
	if entry == null or not entry.closes_on_map_key:
		return false
	if entry.close.is_valid():
		entry.close.call()
	return true


func _top() -> Entry:
	var best: Entry = null
	for entry: Entry in _entries:
		if (best == null or entry.layer >= best.layer) and entry.open():
			best = entry
	return best


func _entry(id: StringName) -> Entry:
	for entry: Entry in _entries:
		if entry.id == id:
			return entry
	return null
