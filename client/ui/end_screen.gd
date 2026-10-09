class_name EndScreen
extends Control
## The post game screen (ARCHITECTURE §4.7.30, §3.2): the black outro of about 3 s, built node for
## node as the UI track drew it (prime-game-ui `docs/handoff/s10-post-game.md` at ui-0.4.0, #498).
## Night fades in when End starts; on it `V`: "End of the round", the winning team (on the title
## plate when the own team won, plain text when it lost), why the round ended, and the seconds
## until everyone is back in the lobby (#212). The same for every player: no names, no roles, no
## button, no input, no word about voice (#213).

## Emitted each time End starts, for the one sound of both outcomes (the handoff: one sound for a
## win and a loss). No sound asset exists yet: nothing is connected, so the outro is silent.
signal outro_began

## The fade of Night when End starts (the handoff's 0.4 s); a cut under UiPrefs.reduced_motion.
const FADE_SECONDS := 0.4
## The deck's keys (§4.7.26).
const TITLE_KEY := "end.title"
const BACK_KEY := "end.back_to_lobby"
## The winning side's line, by the side's id in the mode (the base mode's `crew` and
## `dissidents`); a side not named here hides both winner lines (no deck key for it).
const SIDE_KEYS: Dictionary[StringName, String] = {
	&"crew": "end.won_engineers",
	&"dissidents": "end.won_dissidents",
}
## Why the round ended, by the host's reason id (#208 b, #548); any other id hides the line.
## `all_tasks` takes the round's time as {time} (m:ss).
const REASON_KEYS: Dictionary[StringName, String] = {
	&"all_tasks": "end.reason.all_tasks",
	&"time_up": "end.reason.time_up",
}

## The opaque black (P2), faded in when End starts.
var night := Panel.new()
## The centred column of 1440 px.
var column := VBoxContainer.new()
var title_label := Label.new()
## The winning team on the title plate, shown when the own team won; `winner_plate` is its
## ToyRaised wrapper, which takes the visibility.
var winner_label := Label.new()
var winner_plate: ToyRaised
## The winning team in plain text, shown when the own team lost.
var loser_label := Label.new()
var result := VBoxContainer.new()
## Why the round ended; hidden while the reason id is unknown.
var reason_label := Label.new()
var gap := Control.new()
## "Back to the lobby in 3…": End's end tick from PhaseChanged; hidden when End has none.
var countdown_label := Label.new()
## Night's fade while it runs; null otherwise.
var fade: Tween
## The host's reason id and the round's length in seconds (show_reason); &"" and -1 until known.
## MatchEnded carries no reason yet (#548 adds it), so in a game the line stays hidden.
var reason: StringName = &""
var round_seconds := -1
## The seconds the countdown shows; -1 when End has none.
var _count := -1
## Whether this End has begun (the fade and the sound ran): cleared when the screen is hidden.
var _playing := false


func _init() -> void:
	name = "EndScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	night.name = "Night"
	night.theme_type_variation = &"ToyBackdropNight"
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(night)
	column.name = "V"
	column.theme_type_variation = &"ToyColumnThirtyTwo"
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(1440, 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)
	_label(title_label, "Title", &"ToyTextMutedOnDark", TITLE_KEY)
	column.add_child(title_label)
	_label(winner_label, "Winner", &"ToyTitlePlate")
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	winner_plate = UiParts.raised(winner_label)
	winner_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(winner_plate)
	_label(loser_label, "WinnerLoss", &"ToyTextOnDark")
	column.add_child(loser_label)
	result.name = "Result"
	result.theme_type_variation = &"ToyColumnEight"
	column.add_child(result)
	_label(reason_label, "Reason", &"ToyTextMutedOnDark")
	reason_label.custom_minimum_size = Vector2(1152, 0)
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	result.add_child(reason_label)
	gap.name = "Gap"
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)
	_label(countdown_label, "Back", &"ToyTextOnDark")
	countdown_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(countdown_label)
	for control: Control in find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	_show_winner(&"", false)
	_retext()


## `host_tick`: the newest host tick known (-1: none yet).
func refresh(model: ClientModel, mode: GameMode, host_tick: int) -> void:
	_show_winner(model.winner, own_team_won(model, mode))
	var count := count_shown(model, host_tick)
	if count != _count:
		_count = count
		_retext()


## Why the round ended: the host's reason id and the round's length in seconds (-1: unknown).
## #548 brings both in MatchEnded; until then only the previews and the tests call it.
func show_reason(reason_id: StringName, seconds: int) -> void:
	reason = reason_id
	round_seconds = seconds
	_retext()


## The winner line shown now: the plate's face when the own team won, else the plain one.
func winner_shown() -> Label:
	return winner_label if winner_plate.visible else loser_label


## Whether the own role's side is the winning one; false before MatchEnded or without a role.
static func own_team_won(model: ClientModel, mode: GameMode) -> bool:
	if model.winner.is_empty() or model.role.is_empty():
		return false
	var role := mode.find_role(model.role)
	return role != null and role.side == model.winner


## The seconds the countdown shows: End's end tick less the host tick, 3, 2, 1 (at the end tick
## the lobby takes over, so never 0), or -1 when End has none (a mode without `seconds`).
static func count_shown(model: ClientModel, host_tick: int) -> int:
	var left := GameFlow.seconds_left(model.end_tick, host_tick)
	return maxi(left, 1) if left >= 0 else -1


## `seconds` as the deck's {time}: m:ss.
static func round_time(seconds: int) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), seconds % 60]


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_retext()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			# A parent shown again while End is up is not a new End: no second fade, no second sound.
			if not _playing:
				_playing = true
				_begin()
		else:
			if fade != null:
				fade.kill()
				fade = null
				night.modulate.a = 1.0
			if not visible:
				_end_over()


## End is over (the screen itself is hidden): the next End starts with no reason and no countdown
## until the host gives them, never the last round's.
func _end_over() -> void:
	_playing = false
	reason = &""
	round_seconds = -1
	_count = -1
	_retext()


## End started: Night fades in (a cut under reduced motion) and the outro's sound is due.
func _begin() -> void:
	if fade != null:
		fade.kill()
		fade = null
	if UiPrefs.reduced_motion:
		night.modulate.a = 1.0
	else:
		night.modulate.a = 0.0
		fade = create_tween()
		fade.tween_property(night, ^"modulate:a", 1.0, FADE_SECONDS)
	outro_began.emit()


func _show_winner(side: StringName, won: bool) -> void:
	var key: String = SIDE_KEYS.get(side, "")
	winner_label.text = key
	loser_label.text = key
	winner_plate.visible = won and not key.is_empty()
	loser_label.visible = not won and not key.is_empty()


## The texts built from a key with data: the reason and the countdown, in the current language.
func _retext() -> void:
	var reason_key: String = REASON_KEYS.get(reason, "")
	reason_label.visible = not reason_key.is_empty()
	# Without the line the Result box would still count as a child and add a gap of its own.
	result.visible = not reason_key.is_empty()
	if reason_key.is_empty():
		reason_label.text = ""
	else:
		var time := round_time(round_seconds) if round_seconds >= 0 else ""
		reason_label.text = tr(reason_key).format({"time": time})
	countdown_label.visible = _count >= 0
	countdown_label.text = tr(BACK_KEY).format({"count": _count}) if _count >= 0 else ""


static func _label(label: Label, node_name: String, variation: StringName, key := "") -> void:
	label.name = node_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = key
