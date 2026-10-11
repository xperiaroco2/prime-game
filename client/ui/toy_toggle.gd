class_name ToyToggle
extends Node
## A toggle's selected look (#289; prime-game-ui spec §6): on `toggled(true)` the button's
## `theme_type_variation` becomes the pack's `toggle.selected` partner (ToyTab > ToyTabSelected,
## ToyChipToggleOnDark > ToyChipToggleOnDarkSelected, ToyRadio, ToyPresetCard), and back on
## `toggled(false)`. A Button has one font for every state, so the bold selected tab and chips
## need the swap. A variation with no partner (ToyMenuItem, ToyKeyButton: they draw their own
## `pressed` look) is left alone. Content labels inside the button (a preset card's note) swap
## with it through companion(). A caller that sets `set_pressed_no_signal` calls sync() after.

## The toggle.
var button: BaseButton
## Its variation while off, and while on (&"" when it has no partner).
var idle: StringName
var selected: StringName

## [Label, its idle variation, its selected one] per companion.
var _companions: Array[Array] = []


## Attaches the swap to `toggle` (as an internal child), from its present variation and state.
static func attach(toggle: BaseButton) -> ToyToggle:
	var made := ToyToggle.new()
	made.name = "ToyToggle"
	made.button = toggle
	made.idle = toggle.theme_type_variation
	made.selected = ToyHints.selected_for(made.idle)
	toggle.add_child(made, false, Node.INTERNAL_MODE_FRONT)
	toggle.toggled.connect(made.on_toggled)
	made.sync()
	return made


func on_toggled(on: bool) -> void:
	if selected.is_empty():
		return
	button.theme_type_variation = selected if on else idle
	for each: Array in _companions:
		var label: Label = each[0]
		label.theme_type_variation = each[2] if on else each[1]


## Draws the button's present state (after `set_pressed_no_signal`).
func sync() -> void:
	on_toggled(button.button_pressed)


## `label` swaps from `label_idle` to `label_selected` with the button.
func companion(label: Label, label_idle: StringName, label_selected: StringName) -> void:
	_companions.append([label, label_idle, label_selected])
	sync()
