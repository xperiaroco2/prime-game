class_name ToyHints
extends RefCounted
## The UI pack's hints that no theme item can hold (#289), which the theme generator writes into
## each theme's metadata `toy_hints` (tools/theme/mapping.json `hints`): the toy base Panel under
## a raised variation, per screen context, and a toggle's selected partner. Both themes carry the
## same hints. Only the pack's own names have hints: a legacy name (EscTab, a thin copy of
## ToyMenuItem) has none, as ToyMenuItem has none.

## A screen's context: the base under a raised face differs on a dark and a light surface.
const DARK := &"dark"
const LIGHT := &"light"
## The pack's context of a base that is the same on both.
const ANY := &"any"
const META := &"toy_hints"
const THEME := preload("res://client/ui/theme/game_theme.tres")


## The base Panel's variation under `variation` on a `context` screen; &"" when it has none.
static func base_for(variation: StringName, context: StringName = DARK) -> StringName:
	var hint: Variant = _lookup(&"bases", variation)
	if not hint is Dictionary:
		return &""
	var by_context: Dictionary = hint
	return StringName(str(by_context.get(String(context), by_context.get(String(ANY), ""))))


## The variation a toggle of `variation` swaps to while it is on; &"" when it has no partner
## (ToyMenuItem and ToyKeyButton draw their own pressed look).
static func selected_for(variation: StringName) -> StringName:
	var hint: Variant = _lookup(&"toggles", variation)
	return StringName(str(hint)) if hint is String else &""


static func _lookup(table: StringName, variation: StringName) -> Variant:
	var hints: Dictionary = THEME.get_meta(META, {})
	var entries: Dictionary = hints.get(String(table), {})
	return entries.get(String(variation))
