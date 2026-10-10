class_name LobbyPresets
extends RefCounted
## The Lobby tab's preset cards (#491; prime-game-ui handoff s05 `lobby-host`), pure: each preset's
## values for the client's own mode, and which preset the match's settings are now. A preset is the
## mode's number settings, each at its default unless the preset names it, and no task type banned.
## The values are placeholders ("not a decision", #491's "Needs the engineer"): Quick is a 5 minute
## match, No knives has no knives; everything else is the mode's default.
## The card shown pressed is derived from the model, never remembered: equal values are that
## preset, anything else none ("Custom" for a player), so a guest reads it too and any other change
## deselects every card.

const STANDARD := &"standard"
const QUICK := &"quick"
const NO_KNIVES := &"no_knives"
## The player's own preset (Save your own).
const OWN := &"own"
## The cards in their order, with what each changes from the mode's defaults (placeholders).
const CHANGES: Dictionary[StringName, Dictionary] = {
	STANDARD: {},
	QUICK: {&"match_duration": 5},
	NO_KNIVES: {&"knives": 0},
}
## Each card's name key; the own one is preset.custom.
const NAME_KEYS: Dictionary[StringName, String] = {
	STANDARD: "preset.standard",
	QUICK: "preset.quick",
	NO_KNIVES: "preset.no_knives",
	OWN: "preset.custom",
}
const DURATION := &"match_duration"


## The settings `preset` sets in `mode`: every number setting the mode declares, at the preset's
## value kept within its bounds; and every id set (the banned task types) empty. A preset that
## names a setting the mode lacks leaves it out. `own` is the own preset's saved values (OWN).
static func values_of(preset: StringName, mode: GameMode, own: Dictionary = {}) -> Dictionary:
	var changes: Dictionary = own if preset == OWN else CHANGES.get(preset, {})
	var values := {}
	for spec: SettingSpec in mode.settings:
		if spec.is_number():
			var wanted: Variant = changes.get(spec.id, spec.default_value)
			var number := spec.default_value
			if wanted is int or wanted is float:
				number = roundi(wanted as float)
			values[spec.id] = clampi(number, spec.min_value, spec.max_value)
		else:
			var banned: Variant = changes.get(spec.id, PackedStringArray())
			values[spec.id] = (
				banned as PackedStringArray if banned is PackedStringArray else PackedStringArray()
			)
	return values


## The presets whose card shows: one changing a setting the mode lacks has no card.
static func shown(mode: GameMode) -> Array[StringName]:
	var cards: Array[StringName] = []
	for preset: StringName in CHANGES:
		var fits := true
		for id: Variant in CHANGES[preset]:
			fits = fits and mode.find_setting(id as StringName) != null
		if fits:
			cards.append(preset)
	return cards


## The preset the match is set to now (`settings` and `id_sets` as ClientModel holds them), or &""
## for none; the own preset counts when `own` is given.
static func applied(
	settings: Dictionary, id_sets: Dictionary, mode: GameMode, own: Dictionary = {}
) -> StringName:
	var candidates: Array[StringName] = shown(mode)
	if not own.is_empty():
		candidates.append(OWN)
	for preset: StringName in candidates:
		if _matches(values_of(preset, mode, own), settings, id_sets):
			return preset
	return &""


## Only the values that differ from `settings` and `id_sets`: what one ChangeSettings sends.
static func changes_from(
	values: Dictionary, settings: Dictionary, id_sets: Dictionary
) -> Dictionary:
	var differ := {}
	for id: Variant in values:
		var now: Variant = settings.get(id)
		if values[id] is PackedStringArray:
			now = id_sets.get(id, PackedStringArray())
		if now != values[id]:
			differ[id] = values[id]
	return differ


## The match duration a card notes, in minutes; -1 when the mode has none.
static func duration_of(values: Dictionary) -> int:
	return values.get(DURATION, -1) as int


static func _matches(values: Dictionary, settings: Dictionary, id_sets: Dictionary) -> bool:
	return changes_from(values, settings, id_sets).is_empty()
