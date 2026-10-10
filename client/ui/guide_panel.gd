class_name GuidePanel
extends HBoxContainer
## The Esc menu's Guide (#254; prime-game-ui's s5 `guide` at ui-0.4.0): every how-to card, any
## time, the lobby included. Left, List: the basics (`guide.basics`: moving and hands, voice,
## downed and back, cards of the tutorial's words) and the tasks (`guide.tasks`: one chip per task
## type of the mode with a card), one ButtonGroup over every chip; right, the selected chip's card
## (HowtoCardView, 160x120 art), titled with the chip's text. Its own control, so the Esc menu's
## restyle (#491) hosts it as it is. Drawn for a light page (the handoff's ToyPanelMenu: the
## ...OnLight captions and chips; the Toy Esc menu since #491) or a dark one (...OnDark, an
## option no menu uses now).

## The list's width (the handoff's: the longest chip at large text), in pixels (layout).
const LIST_WIDTH := 332.0
## The spacer between the basics and the tasks caption, in pixels (layout).
const GAP := 8.0

## The page it sits on: ToyHints.LIGHT (the handoff's) or DARK.
var context := ToyHints.LIGHT
var list := UiParts.scroll()
var column := VBoxContainer.new()
var tasks_label := Label.new()
var group := ButtonGroup.new()
## Every chip by its card's id (a basic's or a task type's), in the list's order.
var chips: Dictionary[StringName, Button] = {}
## The selected chip's card (a ToyRaised of HowtoCardView); null before any card is selected.
var card: ToyRaised
## The selected card's id; &"" for none.
var selected: StringName = &""

var _cards: Dictionary[StringName, HowtoCard] = {}
var _task_chips: Array[Button] = []


func _init(on_context: StringName = ToyHints.LIGHT) -> void:
	context = on_context
	name = "Guide"
	theme_type_variation = &"ToyRowTwentyFour"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.name = "List"
	list.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.follow_focus = true
	add_child(list)
	column.name = "V"
	column.theme_type_variation = &"ToyColumnEight"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(column)
	var basics := UiParts.styled_label(
		"guide.basics", _look(&"ToyTextMutedOnLight", &"ToyTextMutedOnDark")
	)
	basics.name = "Basics"
	column.add_child(basics)
	for id: StringName in HowtoCards.BASICS:
		var basic := HowtoCards.of_basic(id)
		if basic != null:
			column.add_child(_chip(basic))
	var gap := Control.new()
	gap.name = "Gap"
	gap.custom_minimum_size = Vector2(0, GAP)
	column.add_child(gap)
	tasks_label.name = "Tasks"
	tasks_label.text = "guide.tasks"
	tasks_label.theme_type_variation = _look(&"ToyTextMutedOnLight", &"ToyTextMutedOnDark")
	column.add_child(tasks_label)
	set_mode(null)


## The task chips of `mode`'s task types with a card, in its order; the first task's card is
## selected (the handoff's sample), else the first basic's.
func set_mode(mode: GameMode) -> void:
	for chip: Button in _task_chips:
		chips.erase(_id_of(chip))
		_cards.erase(_id_of(chip))
		column.remove_child(chip)
		chip.free()
	_task_chips.clear()
	for each: HowtoCard in HowtoCards.of_tasks(mode):
		var chip := _chip(each)
		_task_chips.append(chip)
		column.add_child(chip)
	tasks_label.visible = not _task_chips.is_empty()
	var first := _task_chips[0] if not _task_chips.is_empty() else null
	if first == null and not chips.is_empty():
		first = chips.values()[0]
	select(_id_of(first) if first != null else &"")


## Shows the card of the chip `id` and presses its chip; &"" or an unknown id shows none.
func select(id: StringName) -> void:
	if card != null:
		# Freed now (a chip's press, never the card's own signal, gets here): a Game made and
		# freed in one frame leaves no orphan.
		remove_child(card)
		card.free()
		card = null
	selected = id if _cards.has(id) else &""
	if selected.is_empty():
		return
	card = HowtoCardView.raised(_cards[selected], HowtoCardView.GUIDE_ART, context)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(card)
	var chip := chips[selected]
	if not chip.button_pressed:
		chip.button_pressed = true


func _chip(shown: HowtoCard) -> Button:
	var chip := UiParts.toggle(
		String(shown.title), Callable(), _look(&"ToyChipToggleOnLight", &"ToyChipToggleOnDark")
	)
	chip.name = String(shown.id).to_pascal_case()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.button_group = group
	chip.set_meta(&"howto", shown.id)
	chip.pressed.connect(select.bind(shown.id))
	chips[shown.id] = chip
	_cards[shown.id] = shown
	return chip


## `on_light` or `on_dark`, for the page's context.
func _look(on_light: StringName, on_dark: StringName) -> StringName:
	return on_dark if context == ToyHints.DARK else on_light


static func _id_of(chip: Button) -> StringName:
	return chip.get_meta(&"howto", &"") as StringName
