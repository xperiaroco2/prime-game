class_name PregameScreen
extends Control
## The pregame screen (ARCHITECTURE §3.6, §4.7.39, #213, #496, #1571): the black intro of about
## 3 s, built node for node as the UI track drew it (prime-game-ui `docs/handoff/s06-pre-game.md`
## at ui-2.5.4, the role reveal of the target's frame 4): on the opaque `Night`, `Reveal` holds
## fixed places so the band never moves between the sides: "Your role" in small capitals, the own
## role in hero capitals on a band across the whole width (the danger band for a side in
## ALERT_SIDES), its goal under the band and, for a player whose role knows its teammates (a
## dissident), a dot in each teammate's body colour and their names. When the round starts Night
## fades out over the round's HUD (a cut under reduced motion), then the screen hides. No input,
## no word about the microphone (the engineer on #175, 2026-10-02).
##
## It reads only the own player's view: `ClientModel.role`, the own role's `teammates`, and the
## roster's (public) names and body colours of those teammates; nothing of any other player's
## role (#175).

## Emitted once per pregame when the own role shows, with the own role's side in the client's own
## mode (empty for a role the mode does not know), never once the round has started: the screen
## plays the side's sound on it (SIDE_SOUNDS, UiSounds.role on the UI bus; #716, #213, #175).
signal role_revealed(role: StringName, side: StringName)

## Night's fade when the round starts (the handoff's 0.4 s); a cut under UiPrefs.reduced_motion.
const FADE_SECONDS := 0.4
## The deck's keys (§4.7.26).
const TITLE_KEY := "pregame.your_role"
const TEAM_KEY := "pregame.teammate"
## The own role's generic goal by its id (the base mode's `crew` and `dissident`, as
## ContentNames names them); a role not here shows no goal line (no deck key for it).
const GOAL_KEYS: Dictionary[StringName, String] = {
	&"crew": "role.goal.engineer",
	&"dissident": "role.goal.dissident",
}
## The own side's sound by the side's id in the mode (the base mode's `crew` and `dissidents`, as
## EndScreen.SIDE_KEYS names them); a side not here plays nothing (#716).
const SIDE_SOUNDS: Dictionary[StringName, StringName] = {
	&"crew": SfxSet.UI_ROLE_ENGINEERS,
	&"dissidents": SfxSet.UI_ROLE_DISSIDENTS,
}
## The sides drawn on the danger band (the handoff's `human`: the side that spoils the party);
## any other side on the accent band (`alien`).
const ALERT_SIDES: Array[StringName] = [&"dissidents"]
## The handoff's fixed places (px from the top at the 1920x1080 base, #287).
const KICKER_TOP := 270.0
const BAND_TOP := 345.0
const BAND_BOTTOM := 630.0
const GOAL_TOP := 684.0
const GOAL_TEXT_WIDTH := 1080.0
const TEAM_TOP := 870.0

## The opaque ground (P2); it fades out over the round's HUD.
var night := Panel.new()
## The reveal's full-rect root; hidden until the own role is known and when the round starts.
var reveal_box := Control.new()
var title_label := Label.new()
## The band across the whole width and the own role on it.
var band := PanelContainer.new()
var role_label := Label.new()
## The goal's plain line under the band.
var goal := PanelContainer.new()
var goal_label := Label.new()
## The teammates' row: a Dot per teammate, then their names (`pregame.teammate`); hidden without.
var team := HBoxContainer.new()
var team_label := Label.new()
## Night's fade while it runs; null otherwise.
var fade: Tween
## The teammates' names shown now (data, never translated).
var team_names := PackedStringArray()
## The teammates' body colours (PlayerColours indices) the dots show now, in the names' order.
var team_colours := PackedInt32Array()
## Whether role_revealed went out in this pregame.
var _revealed := false


func _init() -> void:
	name = "PregameScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	night.name = "Night"
	night.theme_type_variation = &"ToyBackdropFullScreen"
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(night)
	reveal_box.name = "Reveal"
	reveal_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(reveal_box)
	_label(title_label, "YourRole", &"ToyKicker", TITLE_KEY)
	title_label.uppercase = true
	_place(title_label, Control.PRESET_TOP_WIDE, KICKER_TOP, KICKER_TOP)
	reveal_box.add_child(title_label)
	band.name = "Band"
	band.theme_type_variation = &"ToyBand"
	_place(band, Control.PRESET_TOP_WIDE, BAND_TOP, BAND_BOTTOM)
	reveal_box.add_child(band)
	_label(role_label, "Role", &"ToyTitleHero")
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_label.uppercase = true
	band.add_child(role_label)
	goal.name = "Goal"
	goal.theme_type_variation = &"ToyPlateGoal"
	_place(goal, Control.PRESET_CENTER_TOP, GOAL_TOP, GOAL_TOP)
	reveal_box.add_child(UiParts.sized(goal))
	_label(goal_label, "Text", &"ToyPlateGoalText")
	goal_label.custom_minimum_size = Vector2(GOAL_TEXT_WIDTH, 0)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.add_child(goal_label)
	team.name = "Team"
	team.theme_type_variation = &"ToyRowTwelve"
	_place(team, Control.PRESET_CENTER_TOP, TEAM_TOP, TEAM_TOP)
	reveal_box.add_child(team)
	team_label.name = "Text"
	team_label.theme_type_variation = &"ToyTextOnDark"
	team_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A key with a placeholder and the players' names: set from code, never translated again.
	team_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	team.add_child(team_label)
	# No input in the pregame (#488 rule 4), as on the post game screen: it only draws.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control: Control in find_children("*", "Control", true, false):
		_inert(control)
	var nobody: Array[int] = []
	_show_role("", "", false, nobody)
	role_revealed.connect(_play_role_sound)


## Shows the intro from the own `model` and the client's own `mode`. The own role revealed for the
## first time in this pregame emits `role_revealed`; not while Night fades out over the round (a
## role that arrives that late plays no sound in the round).
func refresh(model: ClientModel, mode: GameMode) -> void:
	var goal_key: String = GOAL_KEYS.get(model.role, "")
	var role := mode.find_role(model.role)
	var side: StringName = role.side if role != null else &""
	_show_role(
		HudText.role_key(model, mode), goal_key, ALERT_SIDES.has(side), team_peers(model), model
	)
	if model.role.is_empty() or _revealed or fade != null or not is_visible_in_tree():
		return
	_revealed = true
	role_revealed.emit(model.role, side)


## The pregame shows: Night opaque, the reveal as the role allows. Called on every frame of it.
func reveal() -> void:
	_stop_fade()
	reveal_box.visible = not role_label.text.is_empty()
	night.modulate.a = 1.0
	visible = true


## The round starts: the reveal goes and Night fades out over the HUD, then the screen hides; at
## once under reduced motion or outside the tree (nothing draws there).
func lift() -> void:
	if not visible:
		return
	reveal_box.visible = false
	_stop_roles()
	_stop_fade()
	if UiPrefs.reduced_motion or not is_inside_tree():
		_lifted()
		return
	night.modulate.a = 1.0
	fade = create_tween()
	fade.tween_property(night, ^"modulate:a", 0.0, FADE_SECONDS)
	fade.tween_callback(_lifted)


## Any screen but the round's start: hidden at once, ready for the next pregame.
func stop() -> void:
	_stop_roles()
	_stop_fade()
	_lifted()


## Whether Night is fading out over the round now.
func lifting() -> bool:
	return fade != null


## The names of the own role's teammates, the own player left out, in the host's order; a peer
## not in the roster (it left) is skipped. Empty for a role whose players do not know each other
## (the host sends Teammates only to those, §5), and before RoleAssigned.
static func team_of(model: ClientModel) -> PackedStringArray:
	var names := PackedStringArray()
	for peer: int in team_peers(model):
		names.append(model.roster[peer].name)
	return names


## The own role's teammates' peers as team_of names them.
static func team_peers(model: ClientModel) -> Array[int]:
	var peers: Array[int] = []
	if model.role.is_empty() or not model.teammates.has(model.role):
		return peers
	for peer: int in model.teammates[model.role]:
		if peer != model.own_peer and model.roster.has(peer):
			peers.append(peer)
	return peers


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_retext()


## The own role on its band (the danger band when `alert`), its goal, and the teammates `peers`
## of `model`'s roster (their names and body colours).
func _show_role(
	role_key: String, goal_key: String, alert: bool, peers: Array[int], model: ClientModel = null
) -> void:
	role_label.text = role_key
	band.theme_type_variation = &"ToyBandAlert" if alert else &"ToyBand"
	role_label.theme_type_variation = &"ToyTitleHeroAlert" if alert else &"ToyTitleHero"
	goal_label.text = goal_key
	goal.visible = not goal_key.is_empty()
	var names := PackedStringArray()
	var colours := PackedInt32Array()
	for peer: int in peers:
		names.append(model.roster[peer].name)
		colours.append(model.roster[peer].colour)
	team_names = names
	if colours != team_colours:
		team_colours = colours
		_rebuild_dots()
	_retext()
	if fade == null:
		reveal_box.visible = not role_key.is_empty()


## One Dot per teammate in its body colour (content data, self_modulate), before the names.
func _rebuild_dots() -> void:
	for child: Node in team.get_children():
		if child != team_label:
			team.remove_child(child)
			child.free()
	for colour: int in team_colours:
		var dot := Panel.new()
		dot.name = "Dot"
		dot.theme_type_variation = &"ToyRosterDot"
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.self_modulate = BodyColours.of(colour)
		_inert(dot)
		team.add_child(UiParts.sized(dot), true)
		team.move_child(dot, team.get_child_count() - 2)


## The team line in the current language: the deck's key with the names joined by ", ".
func _retext() -> void:
	team.visible = not team_names.is_empty()
	if team_names.is_empty():
		team_label.text = ""
	else:
		team_label.text = tr(TEAM_KEY).format({"names": ", ".join(team_names)})


func _play_role_sound(_role: StringName, side: StringName) -> void:
	if SIDE_SOUNDS.has(side):
		UiSounds.role(self, SIDE_SOUNDS[side])


## A role sound that began near the pregame's end stops with it, so none plays in the round.
func _stop_roles() -> void:
	if is_inside_tree():
		UiSounds.stop_roles(get_tree())


func _stop_fade() -> void:
	if fade != null:
		fade.kill()
		fade = null


## Hidden and reset for the next pregame: Night opaque again, the next role announced again.
func _lifted() -> void:
	fade = null
	visible = false
	night.modulate.a = 1.0
	_revealed = false


static func _label(label: Label, node_name: String, variation: StringName, key := "") -> void:
	label.name = node_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = key


## `control` at the `preset`'s anchors, `top` and `bottom` from them and 0 across, growing both
## ways across and down (the handoff's grow both/end).
static func _place(
	control: Control, preset: Control.LayoutPreset, top: float, bottom: float
) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = top
	control.offset_bottom = bottom
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_END


## No input in the pregame: `control` neither takes the mouse nor the focus.
static func _inert(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.focus_mode = Control.FOCUS_NONE
