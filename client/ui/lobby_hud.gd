class_name LobbyHud
extends Control
## What shows while the player walks in the lobby (ARCHITECTURE §4.7, #169): the keys' hint, the
## roster with ready flags and the countdown, in a corner, with nothing to click: the pointer stays
## the game's. Ready (the `ready` key, F) and the settings are in the Esc menu's Lobby tab. Until a
## microphone is picked, a hint points to the Esc menu's Voice tab (M5-6). The room's code, to
## whoever knows it (the M6 design §3 item 2); Copy is in the Esc menu's Lobby tab. Styled only
## through the shared theme (HudMargin, HudPanel, HudHint, HudText).

## Greybox wording (#150); F is a placeholder key, "not a decision".
const HINT := "Esc: menu  ·  F: ready"

var hint_label := UiParts.styled_label(HINT, &"HudHint")
var roster_label := UiParts.styled_label("", &"HudText")
var countdown_label := UiParts.styled_label("", &"HudText")
## The code line (show_code(), JoinProgress.code_text); hidden when empty.
var code_label := UiParts.styled_label("", &"HudText")
## The voice hint (show_voice_hint()); hidden when empty.
var voice_label := UiParts.styled_label("", &"HudHint")


func _init() -> void:
	name = "LobbyHud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"HudMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(frame)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	frame.add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voice_label.visible = false
	code_label.visible = false
	for label: Label in [hint_label, code_label, voice_label, roster_label, countdown_label]:
		column.add_child(label)
	panel.add_child(column)


## Shows what `model` knows now; `host_tick` is the newest host tick it knows (-1: none yet).
func refresh(model: ClientModel, host_tick: int) -> void:
	roster_label.text = LobbyPanel.roster_text(model)
	countdown_label.text = LobbyPanel.countdown_text(model, host_tick)


## The code line (JoinProgress.code_text); "" hides it.
func show_code(text: String) -> void:
	code_label.text = text
	code_label.visible = not text.is_empty()


## The voice hint until a microphone is picked; "" hides it.
func show_voice_hint(text: String) -> void:
	voice_label.text = text
	voice_label.visible = not text.is_empty()
