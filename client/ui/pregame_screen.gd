class_name PregameScreen
extends Control
## The pregame screen (ARCHITECTURE §3.6, §4.7.39, #213, #496): the black intro of about 3 s,
## built node for node as the UI track drew it (prime-game-ui `docs/handoff/s06-pre-game.md` at
## ui-0.4.0). On the opaque `Night`, `V`: "Your role", the own role on the title plate, its goal
## and, for a player whose role knows its teammates (a dissident), the teammates' names. When the
## round starts Night fades out over the round's HUD (a cut under reduced motion), then the screen
## hides. No input, no word about the microphone (the engineer on #175, 2026-10-02).
##
## It reads only the own player's view: `ClientModel.role`, the own role's `teammates`, and the
## roster's (public) names of those teammates; nothing of any other player's role (#175).

## Emitted once per pregame when the own role shows: the hook for the one sound per role (#213,
## #175). No role sound exists yet, so nothing is connected and the intro is silent.
signal role_revealed(role: StringName)

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

## The opaque black (P2); it fades out over the round's HUD.
var night := Panel.new()
## The centred column of 1152 px; hidden until the own role is known and when the round starts.
var column := VBoxContainer.new()
var title_label := Label.new()
## The own role on the title plate; `role_plate` is its ToyRaised wrapper.
var role_label := Label.new()
var role_plate: ToyRaised
## The goal and the team line.
var text_box := VBoxContainer.new()
var goal_label := Label.new()
## The teammates' names (`pregame.teammate`); hidden without any.
var team_label := Label.new()
## Night's fade while it runs; null otherwise.
var fade: Tween
## The teammates' names shown now (data, never translated).
var team_names := PackedStringArray()
## Whether role_revealed went out in this pregame.
var _revealed := false


func _init() -> void:
	name = "PregameScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	night.name = "Night"
	night.theme_type_variation = &"ToyBackdropNight"
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(night)
	column.name = "V"
	column.theme_type_variation = &"ToyColumnThirtyTwo"
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(1152, 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)
	_label(title_label, "YourRole", &"ToyTextMutedOnDark", TITLE_KEY)
	column.add_child(title_label)
	role_label.name = "Role"
	role_label.theme_type_variation = &"ToyTitlePlate"
	role_plate = UiParts.raised(role_label)
	role_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(role_plate)
	text_box.name = "Text"
	text_box.theme_type_variation = &"ToyColumnSixteen"
	column.add_child(text_box)
	_label(goal_label, "Goal", &"ToyTextOnDark")
	goal_label.custom_minimum_size = Vector2(1152, 0)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(goal_label)
	_label(team_label, "Team", &"ToyTextMutedOnDark")
	team_label.custom_minimum_size = Vector2(1152, 0)
	team_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A key with a placeholder and the players' names: set from code, never translated again.
	team_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text_box.add_child(team_label)
	# No input in the pregame (#488 rule 4), as on the post game screen: it only draws.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control: Control in find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	_show_role("", "", PackedStringArray())


## Shows the intro from the own `model` and the client's own `mode`.
func refresh(model: ClientModel, mode: GameMode) -> void:
	var goal_key: String = GOAL_KEYS.get(model.role, "")
	_show_role(HudText.role_key(model, mode), goal_key, team_of(model))
	if not model.role.is_empty() and not _revealed and is_visible_in_tree():
		_revealed = true
		role_revealed.emit(model.role)


## The pregame shows: Night opaque, the column as the role allows. Called on every frame of it.
func reveal() -> void:
	_stop_fade()
	column.visible = not role_label.text.is_empty()
	night.modulate.a = 1.0
	visible = true


## The round starts: the column goes and Night fades out over the HUD, then the screen hides; at
## once under reduced motion or outside the tree (nothing draws there).
func lift() -> void:
	if not visible:
		return
	column.visible = false
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
	if model.role.is_empty() or not model.teammates.has(model.role):
		return names
	for peer: int in model.teammates[model.role]:
		if peer != model.own_peer and model.roster.has(peer):
			names.append(model.roster[peer].name)
	return names


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_retext()


func _show_role(role_key: String, goal_key: String, names: PackedStringArray) -> void:
	role_label.text = role_key
	goal_label.text = goal_key
	goal_label.visible = not goal_key.is_empty()
	team_names = names
	_retext()
	if fade == null:
		column.visible = not role_key.is_empty()


## The team line in the current language: the deck's key with the names joined by ", ".
func _retext() -> void:
	team_label.visible = not team_names.is_empty()
	if team_names.is_empty():
		team_label.text = ""
	else:
		team_label.text = tr(TEAM_KEY).format({"names": ", ".join(team_names)})


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
