class_name TutorialScreen
extends Control
## The tutorial's screens in the Toy style (#492; ARCHITECTURE §4.7.50): the UI handoff's s1, node
## for node (prime-game-ui `ui-0.4.0` `docs/handoff/s01-tutorial.md`), over the round's HUD (#489)
## on the HUD layer. Px at the 1920x1080 base (#287):
## - The invite (first launch only, open_invite()): `Dim` (ToyBackdrop), `Lang` (two language
##   chips at the top right, one ButtonGroup, each language named in itself) and `Box` (the raised
##   ToyPanelDialog: the title, the body, Start and Skip). Start has the focus as it opens.
## - `Step` (top centre, 40 px down, 912 px wide): "Step n of 9", the title, and How: the how
##   sentence in pieces around the keycap of the action bound now (KeyLabel, #211), or lesson 1's
##   row of keycaps (`HowKeys`), or nothing (lesson 4: title only, the engineer's answer on PR
##   #722). Lesson 5's «?» is a ToyKeyRound keycap, the look of the map's «?».
## - `List` (top right, 256 px down, 440 px wide): the nine lessons, a done one with a check at the
##   right edge, the current one a one-line ToyChipLight (the plate widens to the left for a long
##   one), the rest muted and wrapping.
## Styled only through the shared theme's variations (no override); a keycap's `min_width`, or
## `wide_min_width` for Space, Shift, Tab and Esc, read into `custom_minimum_size` again after the
## large-text swap. The plates take no mouse and no focus. Texts with data or drawn in pieces are
## set from code (`auto_translate_mode` DISABLED) and written again on
## NOTIFICATION_TRANSLATION_CHANGED (#208); the plain keys translate themselves. It reads nothing
## itself: GameTutorial feeds it (show_lessons) and hears its signals, so no other screen knows
## the tutorial exists.

## The invite's Start: lesson 1 begins and the invite is gone for good.
signal start_pressed
## The invite's Skip, or Esc on it (GameUi's overlay): the main menu, the invite gone for good.
signal skip_pressed
## A language chip was pressed (one of Languages.ALL): the game applies and saves it.
signal language_chosen(language: String)

## The places and fixed sizes the handoff gives (px; layout, not style).
const EDGE := 40
const LIST_TOP := 256
const STEP_WIDTH := 912
const TITLE_WIDTH := 600
const LIST_WIDTH := 440
const NAME_WIDTH := 240
const BOX_WIDTH := 688
const BODY_WIDTH := 480
const CHECK_SIZE := Vector2(24, 24)
## A plate stacked under another at the top centre: the gap of s9's Protect chip under the HUD's
## timer (LifeScreen.PROTECT_TOP); s1 draws no dead player ("not a decision").
const STACK_GAP := 24
## The map's «?» (MapScreen's task rows), drawn as lesson 5's round keycap.
const HOWTO_TEXT := "?"
## Lesson 1's walking keys: one group, named by `control.walk`; every other key of a key row is a
## group of its own, named by its Controls row.
const WALK: Array[StringName] = [&"move_forward", &"move_left", &"move_back", &"move_right"]
const WALK_KEY := "control.walk"
## The language chips in the handoff's order: node name, language.
const LANGUAGES: Dictionary[String, String] = {"Uk": Languages.UKRAINIAN, "En": Languages.ENGLISH}

var dim: Panel
var lang := HBoxContainer.new()
var chips: Dictionary[String, Button] = {}
var box: ToyRaised
var invite_title := UiParts.styled_label("tutorial.invite.title", &"ToyTitleOnLight")
var invite_body := UiParts.styled_label("tutorial.invite.body", &"ToyTextMutedOnLight")
var start_button: Button
var skip_button := Button.new()
var step := PanelContainer.new()
var progress_label := UiParts.styled_label("", &"ToyTextMutedOnDark")
var title_label := UiParts.styled_label("", &"ToyTitleOnDark")
## The step's How row (a sentence with a keycap) or HowKeys row (lesson 1), rebuilt per step.
var how: HBoxContainer
var list := PanelContainer.new()
var rows := VBoxContainer.new()

var _step_column := VBoxContainer.new()
var _languages := ButtonGroup.new()
## The last show_lessons() arguments, drawn again on a translation change.
var _lessons: TutorialLessons
var _lesson := 0
var _step := 0
var _done: Array[bool] = []
## What the plates drew last: the arguments and every key label, so a rebind redraws them.
var _drawn: Array = []


func _init() -> void:
	name = "TutorialScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_build_step()
	_build_list()
	_build_invite()
	for plate: Control in [step, list]:
		_ignore_mouse(plate)
	step.visible = false
	list.visible = false
	_show_invite(false)


## Opens the invite over the room: the plates hide, Start takes the focus.
func open_invite() -> void:
	_show_invite(true)
	_mark_language()
	_focus_start.call_deferred()


## Closes the invite (Start or Skip chosen, or the session over).
func close_invite() -> void:
	_show_invite(false)


func invite_shown() -> bool:
	return box.visible


## Esc on the invite (GameUi's overlay): its Skip.
func skip() -> void:
	skip_pressed.emit()


## Draws the plates: `lessons`, the current lesson (1-based, 0: none current) and its step
## (1-based), and which lessons are done. Redraws only when something changed, the bound keys'
## labels included (a rebind in Settings > Controls, the keyboard layout), so the game may call it
## every frame.
func show_lessons(
	lessons: TutorialLessons, lesson: int, step_number: int, done: Array[bool]
) -> void:
	_lessons = lessons
	_lesson = lesson
	_step = step_number
	_done = done.duplicate()
	var now := _state_now()
	if now == _drawn:
		return
	_drawn = now
	_redraw()


## The plates are gone (the session ended); the next show_lessons() draws them afresh.
func clear() -> void:
	_lessons = null
	_lesson = 0
	_step = 0
	_done.clear()
	_drawn.clear()
	step.visible = false
	list.visible = false
	close_invite()


## Places the Step plate STACK_GAP under `plate` (lesson 7's Spectate plate of LifeScreen, which
## holds the same top centre while the player is dead), or at its own place with null.
func set_step_under(plate: Control) -> void:
	var top := float(EDGE)
	if plate != null:
		top = plate.get_rect().end.y + STACK_GAP
	if step.offset_top != top:
		step.offset_top = top
		step.offset_bottom = top


## The step shown now, or null.
func current_step() -> TutorialStep:
	if _lessons == null or _lesson < 1 or _lesson > _lessons.lessons.size():
		return null
	var steps := _lessons.lessons[_lesson - 1].steps
	return steps[_step - 1] if _step >= 1 and _step <= steps.size() else null


## The How row as drawn: its shown labels and keycaps, joined by spaces.
func how_text() -> String:
	var words := PackedStringArray()
	for label: Label in how.find_children("*", "Label", true, false):
		if not label.visible or label.text.is_empty():
			continue
		var keyed := label.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED
		words.append(tr(label.text) if keyed else label.text)
	return " ".join(words)


## The keycaps of the step as drawn (each a PanelContainer holding its Text label).
func keycaps() -> Array[PanelContainer]:
	var found: Array[PanelContainer] = []
	for node: Node in how.find_children("*", "PanelContainer", true, false):
		found.append(node as PanelContainer)
	return found


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_mark_language()
		if _lessons != null:
			_drawn = _state_now()
			_redraw()


## The arguments and the labels of every key the plates draw.
func _state_now() -> Array:
	var labels := PackedStringArray()
	var current := current_step()
	if current != null:
		for key: StringName in current.keys:
			labels.append(KeyLabel.of_action(key) + str(KeyLabel.is_wide_action(key)))
	if _lessons != null:
		for each: TutorialLesson in _lessons.lessons:
			if not each.list_action.is_empty():
				labels.append(KeyLabel.of_action(each.list_action))
	return [_lessons, _lesson, _step, _done.duplicate(), labels]


func _redraw() -> void:
	var current := current_step()
	step.visible = current != null and not invite_shown()
	list.visible = _lessons != null and not invite_shown()
	if current != null:
		_draw_step(current)
	_draw_list()


func _draw_step(current: TutorialStep) -> void:
	var total := _lessons.lessons.size()
	progress_label.text = tr("tutorial.step.progress").format(
		{"count": str(_lesson), "total": str(total)}
	)
	title_label.text = current.title_key
	if how != null:
		_step_column.remove_child(how)
		how.free()
	if not current.how_key.is_empty():
		how = _how_sentence(current)
	elif not current.keys.is_empty():
		how = _how_keys(current.keys)
	else:
		how = HBoxContainer.new()
		how.name = "How"
		how.visible = false
	_step_column.add_child(how)
	_ignore_mouse(how)
	_size_keycaps(how)


## A sentence with a keycap: the how text split at {key}, each piece through strip_edges(), a
## Label per non-empty piece and the keycap between them; a text without {key} is one Label.
func _how_sentence(current: TutorialStep) -> HBoxContainer:
	var row := _row("How", &"ToyRowEight")
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sentence := tr(current.how_key)
	var pieces := LifeHud.give_up_pieces(sentence)
	_piece(row, "Before", pieces[0])
	if sentence.contains("{key}") and not current.keys.is_empty():
		row.add_child(_keycap_of(current.keys[0]))
	_piece(row, "After", pieces[1])
	return row


## Lesson 1's row: the walking keys under `control.walk`, then each other key with its Controls
## row's name.
func _how_keys(keys: Array[StringName]) -> HBoxContainer:
	var row := _row("HowKeys", &"ToyRowTwentyFour")
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var walk_keys: HBoxContainer = null
	for key: StringName in keys:
		if WALK.has(key):
			if walk_keys == null:
				var walk := _row("Walk", &"ToyRowEight")
				row.add_child(walk)
				walk_keys = _row("Keys", &"ToyRowFour")
				walk.add_child(walk_keys)
				walk.add_child(_group_label(WALK_KEY))
			walk_keys.add_child(_keycap_of(key, _short_name(key)))
			continue
		var group := _row(_short_name(key), &"ToyRowEight")
		row.add_child(group)
		group.add_child(_keycap_of(key))
		group.add_child(_group_label(str(Controls.ACTIONS.get(key, key))))
	return row


## A keycap for `key` (an InputMap action, or TutorialStep.HOWTO_GLYPH for the map's «?»).
func _keycap_of(key: StringName, node_name := "Key") -> PanelContainer:
	var keycap := PanelContainer.new()
	keycap.name = node_name
	var text := UiParts.styled_label("", &"ToyKeyText")
	text.name = "Text"
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keycap.add_child(text)
	if key == TutorialStep.HOWTO_GLYPH:
		keycap.theme_type_variation = &"ToyKeyRound"
		text.text = HOWTO_TEXT
		keycap.set_meta(&"wide", false)
	else:
		keycap.theme_type_variation = &"ToyKeyOnDark"
		text.text = KeyLabel.of_action(key)
		keycap.set_meta(&"wide", KeyLabel.is_wide_action(key))
	# UiParts.sized() for the width alone: read again after every theme change (deferred, for its
	# cache reason), so the large-text keycaps take their larger `min_width`.
	var resize := func() -> void:
		if is_instance_valid(keycap):
			_size_keycap(keycap)
	keycap.theme_changed.connect(resize, CONNECT_DEFERRED)
	return keycap


## A keycap's width from its variation: `wide_min_width` for a wide key, else `min_width`.
static func _size_keycap(keycap: PanelContainer) -> void:
	if is_instance_valid(keycap) and keycap.is_inside_tree():
		var wide: bool = keycap.get_meta(&"wide", false)
		keycap.custom_minimum_size = Vector2(UiParts.size_of(keycap, wide).x, 0)


static func _size_keycaps(row: Control) -> void:
	for node: Node in row.find_children("*", "PanelContainer", true, false):
		_size_keycap(node as PanelContainer)


## The list of the nine lessons, rebuilt.
func _draw_list() -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.free()
	if _lessons == null:
		return
	for number in range(1, _lessons.lessons.size() + 1):
		var lesson: TutorialLesson = _lessons.lessons[number - 1]
		var base := _short_name(lesson.list_key)
		var done := number <= _done.size() and _done[number - 1]
		if done:
			rows.add_child(_done_row(base, lesson))
		elif number == _lesson:
			var chip := PanelContainer.new()
			chip.name = base + "Now"
			chip.theme_type_variation = &"ToyChipLight"
			chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			chip.add_child(_list_label(lesson, &"ToyChipLightText", false))
			rows.add_child(chip)
		else:
			var label := _list_label(lesson, &"ToyTextMutedOnDark", true)
			label.name = base
			rows.add_child(label)
	_ignore_mouse(rows)
	for check: Node in rows.find_children("Check", "TextureRect", true, false):
		_tint(check as TextureRect)


func _done_row(base: String, lesson: TutorialLesson) -> HBoxContainer:
	var row := _row(base + "Done", &"ToyRowEight")
	var label := _list_label(lesson, &"ToyTextOnDark", true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var check := TextureRect.new()
	check.name = "Check"
	check.texture = ToyIcons.texture(&"check")
	check.custom_minimum_size = CHECK_SIZE
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.theme_changed.connect(_tint.bind(check))
	row.add_child(check)
	return row


## The check in the colour of the done lesson's name.
static func _tint(check: TextureRect) -> void:
	if is_instance_valid(check) and check.is_inside_tree():
		check.self_modulate = check.get_theme_color(&"font_color", &"ToyTextOnDark")


## A lesson's name: its list key, which translates itself, or (with a `list_action`) its text with
## the bound key in `{key}`, set from code.
func _list_label(lesson: TutorialLesson, variation: StringName, wrapping: bool) -> Label:
	var label := UiParts.styled_label(lesson.list_key, variation)
	label.name = "Name"
	if not lesson.list_action.is_empty():
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var bound := KeyLabel.of_action(lesson.list_action)
		label.text = tr(lesson.list_key).format({"key": bound})
	if wrapping:
		label.custom_minimum_size = Vector2(NAME_WIDTH, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A How piece: a Label with the stripped piece, hidden when it is empty.
func _piece(row: HBoxContainer, piece_name: String, text: String) -> void:
	var label := UiParts.styled_label(text, &"ToyTextOnDark")
	label.name = piece_name
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.visible = not text.is_empty()
	row.add_child(label)


func _group_label(key: String) -> Label:
	var label := UiParts.styled_label(key, &"ToyTextOnDark")
	label.name = "Label"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _build_step() -> void:
	step.name = "Step"
	step.theme_type_variation = &"ToyPlate"
	step.custom_minimum_size = Vector2(STEP_WIDTH, 0)
	_pin(step, Control.PRESET_CENTER_TOP, Vector2(0, EDGE), GROW_DIRECTION_BOTH)
	_step_column.name = "V"
	_step_column.theme_type_variation = &"ToyColumnEight"
	_step_column.alignment = BoxContainer.ALIGNMENT_CENTER
	step.add_child(_step_column)
	progress_label.name = "Progress"
	progress_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_column.add_child(progress_label)
	title_label.name = "Title"
	title_label.custom_minimum_size = Vector2(TITLE_WIDTH, 0)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_column.add_child(title_label)
	how = _row("How", &"ToyRowEight")
	how.visible = false
	_step_column.add_child(how)


func _build_list() -> void:
	list.name = "List"
	list.theme_type_variation = &"ToyPlate"
	list.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_pin(list, Control.PRESET_TOP_RIGHT, Vector2(-EDGE, LIST_TOP), GROW_DIRECTION_BEGIN)
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnSixteen"
	list.add_child(column)
	var head := UiParts.styled_label("tutorial.list.title", &"ToyTextOnDark")
	head.name = "Head"
	column.add_child(head)
	rows.name = "Rows"
	rows.theme_type_variation = &"ToyColumnEight"
	column.add_child(rows)


func _build_invite() -> void:
	dim = UiParts.backdrop(self, &"ToyBackdrop")
	dim.name = "Dim"
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	lang.name = "Lang"
	lang.theme_type_variation = &"ToyRowEight"
	_pin(lang, Control.PRESET_TOP_RIGHT, Vector2(-EDGE, EDGE), GROW_DIRECTION_BEGIN)
	for chip_name: String in LANGUAGES:
		var language: String = LANGUAGES[chip_name]
		# Each language is named in itself: lang.uk holds the same word in every locale.
		var chip := UiParts.toggle(
			Languages.name_key(language),
			func() -> void: language_chosen.emit(language),
			&"ToyChipToggleOnDark"
		)
		chip.name = chip_name
		chip.button_group = _languages
		lang.add_child(chip)
		chips[language] = chip
	var face := PanelContainer.new()
	face.name = "Box"
	face.theme_type_variation = &"ToyPanelDialog"
	box = UiParts.raised(face, ToyHints.DARK)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(BOX_WIDTH, 0)
	add_child(box)
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnThirtyTwo"
	face.add_child(column)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.theme_type_variation = &"ToyColumnTwelve"
	column.add_child(text)
	invite_title.name = "Title"
	invite_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(invite_title)
	invite_body.name = "Body"
	invite_body.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	invite_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(invite_body)
	var buttons := _row("Buttons", &"ToyRowSixteen")
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	var start_raised := UiParts.button(
		"tutorial.invite.start", start_pressed.emit, &"ToyButtonPrimary", ToyHints.LIGHT
	)
	start_button = start_raised.face as Button
	start_button.name = "Start"
	start_raised.name = "StartRaised"
	buttons.add_child(start_raised)
	skip_button.name = "Skip"
	skip_button.text = "tutorial.invite.skip"
	skip_button.theme_type_variation = &"ToyButtonGhostOnLight"
	skip_button.pressed.connect(skip)
	ToyPress.attach(skip_button)
	buttons.add_child(skip_button)


func _show_invite(on: bool) -> void:
	dim.visible = on
	lang.visible = on
	box.visible = on
	if on:
		step.visible = false
		list.visible = false
	elif _lessons != null:
		step.visible = current_step() != null
		list.visible = true


## The chip of the language the game speaks now shows pressed.
func _mark_language() -> void:
	var spoken := TranslationServer.get_locale().get_slice("_", 0)
	if chips.has(spoken) and not chips[spoken].button_pressed:
		# `toggled` only (a chip acts on `pressed`): ToyToggle redraws both, the group lets go of
		# the other chip.
		chips[spoken].button_pressed = true


func _focus_start() -> void:
	if start_button.is_visible_in_tree():
		start_button.grab_focus()


## A box row `node_name` of the spacing `variation`.
static func _row(node_name: String, variation: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.theme_type_variation = variation
	return row


## `node`'s name for a key or action: its last part in PascalCase (`tutorial.list.pick_up` ->
## PickUp, `move_back` -> Backward as its Controls row says, `sprint` -> Sprint).
static func _short_name(key: StringName) -> String:
	var source := str(Controls.ACTIONS.get(key, key))
	return source.get_slice(".", source.get_slice_count(".") - 1).to_pascal_case()


## Every Control under `root`, `root` too, takes no mouse and no focus.
static func _ignore_mouse(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.focus_mode = Control.FOCUS_NONE
	for node: Node in root.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE


## Adds `node` anchored at `preset` with all four offsets at `at`; it grows down and as `grow_x`.
func _pin(
	node: Control, preset: Control.LayoutPreset, at: Vector2, grow_x: Control.GrowDirection
) -> void:
	node.set_anchors_preset(preset)
	node.offset_left = at.x
	node.offset_right = at.x
	node.offset_top = at.y
	node.offset_bottom = at.y
	node.grow_horizontal = grow_x
	node.grow_vertical = Control.GROW_DIRECTION_END
	add_child(node)
