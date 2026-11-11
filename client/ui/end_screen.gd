class_name EndScreen
extends Control
## The post game screen (ARCHITECTURE §4.7.31, §3.2): the outro of about 3 s, built node for node
## as the UI track drew it (prime-game-ui `docs/handoff/s10-post-game.md` at ui-2.5.4, #498, #1572).
## `Night` (ToyBackdropFullScreen) fades in when End starts and holds the texts: `Band` across the
## whole width, 300 to 615 px down (ToyBand, ToyBandAlert when a side in ALERT_SIDES won) with
## `Title`, how the round ended at the hero size ("Great party!", "Time's up", or "End of the
## round" for a reason with no title); `Lines` 672 px down: `Won`, the winning side, and `Reason`,
## why; `Back`, 72 px over the bottom: the seconds until everyone is back on the ship, the lobby
## (#212). The same for every player: no names, no roles, no button, no input, no word about voice
## (#213). The cops' end (ToyBackdropAlert, "Busted!") waits for a mode that ends on the anger
## (#1312): no reason id names it yet.

## Emitted each time End starts, for the one sound of both outcomes (the handoff: one sound for a
## win and a loss): the screen plays it on the UI bus (UiSounds.outro, #657).
signal outro_began

## The fade of Night when End starts (the handoff's 0.4 s); a cut under UiPrefs.reduced_motion.
const FADE_SECONDS := 0.4
# The deck's keys (§4.7.26).
## The title for a reason with no key of its own (the deck's plain "End of the round").
const TITLE_KEY := "end.title"
const BACK_KEY := "end.back_to_ship"
## The winning side's line, by the side's id in the mode (the base mode's `crew` and
## `dissidents`); a side not named here hides both winner lines (no deck key for it).
const SIDE_KEYS: Dictionary[StringName, String] = {
	&"crew": "end.won_engineers",
	&"dissidents": "end.won_dissidents",
}
## Why the round ended, by the host's reason id: the id of the win condition that ended it
## (MatchEnded, #208 b, #548); any other id hides the line. `every_task_done` takes the round's
## time as {time} (m:ss). The deck has no key for `no_crew_present` (ui-0.4.0): hidden, a gap.
const REASON_KEYS: Dictionary[StringName, String] = {
	&"every_task_done": "end.reason.all_tasks",
	&"time_up": "end.reason.time_up",
}
## How the round ended, by the host's reason id, drawn above the reason (prime-game-ui
## s10-post-game.md at ui-2.5.4: the party's title for all tasks done, the time's for time up;
## #1559): any other id keeps TITLE_KEY.
const TITLE_KEYS: Dictionary[StringName, String] = {
	&"every_task_done": "end.title.party",
	&"time_up": "end.title.time_up",
}

## The sides whose win draws the danger band (the handoff's humans: the side that spoils the
## party, as the pre-game's); any other on the accent band.
const ALERT_SIDES: Array[StringName] = [&"dissidents"]
## The handoff's places, px from the top or the bottom at the 1920x1080 base.
const BAND_TOP := 300.0
const BAND_BOTTOM := 615.0
const LINES_TOP := 672.0
const BACK_BOTTOM := -72.0

## The opaque ground (P2), faded in when End starts; the texts are its children.
var night := Panel.new()
## The loud band and how the round ended on it.
var band := PanelContainer.new()
var title_label := Label.new()
## Who won, then why.
var lines := VBoxContainer.new()
## The winning side; hidden for a side the deck names no line for.
var winner_label := Label.new()
## Why the round ended; hidden while the reason id is unknown.
var reason_label := Label.new()
## "Back to the ship in 3…": End's end tick from PhaseChanged; hidden when End has none.
var countdown_label := Label.new()
## Night's fade while it runs; null otherwise.
var fade: Tween
## The host's reason id and the round's length in seconds (show_reason), from MatchEnded through
## the model (#548); &"" and -1 until known.
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
	night.theme_type_variation = &"ToyBackdropFullScreen"
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(night)
	band.name = "Band"
	band.theme_type_variation = &"ToyBand"
	_place(band, Control.PRESET_TOP_WIDE, BAND_TOP, BAND_BOTTOM, Control.GROW_DIRECTION_END)
	night.add_child(band)
	_label(title_label, "Title", &"ToyTitleHero", TITLE_KEY)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(title_label)
	lines.name = "Lines"
	lines.theme_type_variation = &"ToyColumnTwentyFour"
	_place(lines, Control.PRESET_TOP_WIDE, LINES_TOP, LINES_TOP, Control.GROW_DIRECTION_END)
	night.add_child(lines)
	_label(winner_label, "Won", &"ToyTitleOnDark")
	lines.add_child(winner_label)
	_label(reason_label, "Reason", &"ToyTextMutedOnDark")
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lines.add_child(reason_label)
	_label(countdown_label, "Back", &"ToyTextMutedOnDark")
	countdown_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_place(
		countdown_label,
		Control.PRESET_BOTTOM_WIDE,
		BACK_BOTTOM,
		BACK_BOTTOM,
		Control.GROW_DIRECTION_BEGIN
	)
	night.add_child(countdown_label)
	for control: Control in find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	_show_winner(&"")
	_retext()
	outro_began.connect(_play_outro)


## `host_tick`: the newest host tick known (-1: none yet). The mode stays in GameUi's call shape;
## nothing on the screen reads it since one line names the winner for everyone (#1572).
func refresh(model: ClientModel, _mode: GameMode, host_tick: int) -> void:
	_show_winner(model.winner)
	if model.ended_by != reason or model.round_seconds != round_seconds:
		show_reason(model.ended_by, model.round_seconds)
	var count := count_shown(model, host_tick)
	if count != _count:
		_count = count
		_retext()


## Why the round ended: the host's reason id and the round's length in seconds (-1: unknown), as
## MatchEnded gave them (refresh calls it when the model's differ).
func show_reason(reason_id: StringName, seconds: int) -> void:
	reason = reason_id
	round_seconds = seconds
	_retext()


## The winner line: the same for every player (no plate for a win or a loss since ui-2.0.0).
func winner_shown() -> Label:
	return winner_label


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


func _play_outro() -> void:
	UiSounds.outro(self)


## The winning side's line, and the band's colour by it: the danger band (and title) when a side
## in ALERT_SIDES won, the accent one otherwise.
func _show_winner(side: StringName) -> void:
	var key: String = SIDE_KEYS.get(side, "")
	winner_label.text = key
	winner_label.visible = not key.is_empty()
	var alert := ALERT_SIDES.has(side)
	band.theme_type_variation = &"ToyBandAlert" if alert else &"ToyBand"
	title_label.theme_type_variation = &"ToyTitleHeroAlert" if alert else &"ToyTitleHero"


## The texts built from a key with data: the reason and the countdown, in the current language;
## and the title the reason picks (a plain key, it translates itself).
func _retext() -> void:
	title_label.text = TITLE_KEYS.get(reason, TITLE_KEY)
	var reason_key: String = REASON_KEYS.get(reason, "")
	reason_label.visible = not reason_key.is_empty()
	if reason_key.is_empty():
		reason_label.text = ""
	else:
		var time := round_time(round_seconds) if round_seconds >= 0 else ""
		reason_label.text = tr(reason_key).format({"time": time})
	countdown_label.visible = _count >= 0
	countdown_label.text = tr(BACK_KEY).format({"count": _count}) if _count >= 0 else ""


## `node` anchored at `preset` with its top and bottom offsets, growing vertically as `grow`
## says (the wide presets span the screen's width).
static func _place(
	node: Control,
	preset: Control.LayoutPreset,
	top: float,
	bottom: float,
	grow: Control.GrowDirection
) -> void:
	node.set_anchors_preset(preset)
	node.offset_top = top
	node.offset_bottom = bottom
	node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	node.grow_vertical = grow


static func _label(label: Label, node_name: String, variation: StringName, key := "") -> void:
	label.name = node_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = key
