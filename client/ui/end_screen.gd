class_name EndScreen
extends Control
## The end screen (ARCHITECTURE §4.7, §3.2): black, "The <side's display name> won" from the
## client's own mode, and the seconds until everyone is back in the lobby (#212), the same for
## every player; nothing else (no names, no roles, no button).

var winner_label := Label.new()
## "Back to the lobby in 3": End's end tick from PhaseChanged; hidden when End has none.
var countdown_label := Label.new()


func _init() -> void:
	name = "EndScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiParts.backdrop(self, &"EndBackdrop")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"EndColumn"
	center.add_child(column)
	for label: Label in [winner_label, countdown_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	winner_label.theme_type_variation = &"EndTitle"


## `host_tick`: the newest host tick known (-1: none yet).
func refresh(model: ClientModel, mode: GameMode, host_tick: int) -> void:
	winner_label.text = winner_text(model.winner, mode)
	countdown_label.text = countdown_text(model, host_tick)
	countdown_label.visible = not countdown_label.text.is_empty()


static func winner_text(winner: StringName, mode: GameMode) -> String:
	if winner.is_empty():
		return "The match is over"
	var side := mode.find_side(winner)
	return "The %s won" % (side.display_name if side != null else String(winner))


## The seconds until End's end tick in words, or "" when End has none (a mode without `seconds`).
static func countdown_text(model: ClientModel, host_tick: int) -> String:
	var left := GameFlow.seconds_left(model.end_tick, host_tick)
	return "Back to the lobby in %d" % left if left >= 0 else ""
