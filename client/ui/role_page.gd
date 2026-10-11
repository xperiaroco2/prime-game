class_name RolePage
extends HBoxContainer
## The Esc menu's Role page (#491; prime-game-ui handoff s05 `role-engineer`, `role-dissident` at
## ui-0.4.0), in the round only: Left (You, the own role, its goal) and, for a role with teammates
## (a dissident's), Team: "Your team · n" and a two-column list in join order with the teammate
## mark, scrolling in a 250 px view; hidden with no teammates. It shows a RoleFacts (the own
## ClientModel's role and Teammates only).

## The Team list's view height and the mark's size (px at the 1920x1080 base, layout).
const TEAM_VIEW := Vector2(0, 250)
const GOAL_WIDTH := Vector2(400, 0)
const MARK_SIZE := Vector2(20, 20)
const STRETCH_LEFT := 1.1
const TEAM_KEY := "esc.role.teammates"

var left := VBoxContainer.new()
var you_label := UiParts.styled_label("player.you", &"ToyTextMutedOnLight")
var role_label := UiParts.styled_label("", &"ToyDisplayOnLight")
var goal_label := UiParts.styled_label("", &"ToyTextOnLight")
var team := VBoxContainer.new()
var count_label := UiParts.styled_label("", &"ToyTextMutedOnLight")
var scroll := UiParts.scroll()
var grid := GridContainer.new()

var _facts := RoleFacts.new()


func _init() -> void:
	name = "Role"
	theme_type_variation = &"ToyRowThirtyTwo"
	left.name = "Left"
	left.theme_type_variation = &"ToyColumnEight"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = STRETCH_LEFT
	add_child(left)
	you_label.name = "You"
	left.add_child(you_label)
	role_label.name = "Role"
	left.add_child(role_label)
	goal_label.name = "Goal"
	goal_label.custom_minimum_size = GOAL_WIDTH
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(goal_label)
	team.name = "Team"
	team.theme_type_variation = &"ToyColumnTwelve"
	team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(team)
	count_label.name = "Count"
	count_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	team.add_child(count_label)
	scroll.name = "Scroll"
	scroll.custom_minimum_size = TEAM_VIEW
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	team.add_child(scroll)
	grid.name = "Grid"
	grid.theme_type_variation = &"ToyGridList"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	show_facts(_facts)


## Shows `facts`.
func show_facts(facts: RoleFacts) -> void:
	_facts = facts
	role_label.text = facts.role_key
	goal_label.text = facts.goal_key
	goal_label.visible = not facts.goal_key.is_empty()
	team.visible = not facts.team.is_empty()
	if _names() != facts.team:
		for child: Node in grid.get_children():
			grid.remove_child(child)
			child.free()
		for mate: String in facts.team:
			grid.add_child(_mate(mate))
	_retext()


## The names the list shows now.
func _names() -> PackedStringArray:
	var shown := PackedStringArray()
	for row: Node in grid.get_children():
		shown.append((row.get_node(^"Name") as Label).text)
	return shown


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and count_label != null:
		_retext()
	elif what == NOTIFICATION_THEME_CHANGED and grid != null:
		for row: Node in grid.get_children():
			_tint(row.get_node(^"Mark") as TextureRect)


func _retext() -> void:
	count_label.text = tr(TEAM_KEY).format({"count": _facts.team.size()})


func _mate(mate: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Mate%d" % grid.get_child_count()
	row.theme_type_variation = &"ToyRowEight"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mark := TextureRect.new()
	mark.name = "Mark"
	mark.texture = TeammateMark.ART
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = MARK_SIZE
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var label := UiParts.styled_label(mate, &"ToyTextOnLight")
	label.name = "Name"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	_tint(mark)
	return row


## The handoff's tint: ToyTextOnLight's font colour.
func _tint(mark: TextureRect) -> void:
	mark.self_modulate = get_theme_color(&"font_color", &"ToyTextOnLight")
