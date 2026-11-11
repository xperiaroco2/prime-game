class_name WorkbenchScreen
extends PanelContainer
## The mutation workbench's own screen (prime-game-ui `ui-2.5.4` `docs/handoff/s11-workbench.md`,
## #1572; ARCHITECTURE §4.7.65): the machine's screen, not an overlay. `Screen` (ToyPanelDialog,
## 960 x 540, the SubViewport's root once a machine shows it, #1285) holds one of three states:
## - `Idle`: the machine's name and Start (`start_pressed`).
## - `Choose`: the name and the player's points (`Balance`, the only place they show), then one card
##   per mutation (`Cards`): its name, what it does, its price and Mutate (`mutate_pressed`), which
##   reads "N short" and is disabled when the points are short; the card under the pointer (the
##   crosshair's pushed motion) is drawn pointed.
## - `Step`: the chosen mutation's name, "Step into the machine" and ten pips filling while the
##   player stands in the capsule.
## It draws what it is given and sends nothing: points and mutations are not in the game yet
## (docs/ROADMAP.md: "points and mutations" are not planned), so no game state feeds it; the dev
## preview draws the handoff's samples. Styled only through the shared theme's variations; texts
## are deck keys, the numbers data.

## Start was pressed on the idle screen.
signal start_pressed
## Mutate was pressed on the card of the mutation `id`.
signal mutate_pressed(id: StringName)

enum State { IDLE, CHOOSE, STEP }

## The screen's size: the SubViewport's (the handoff's 960 x 540).
const SIZE := Vector2(960, 540)
## Start's least width (the handoff's: an easy mark for the crosshair).
const START_WIDTH := 288
## A card's effect line's least width.
const EFFECT_WIDTH := 200


## One mutation on offer: its id, deck keys and price in points (content data, from the game).
class Mutation:
	extends RefCounted
	var id: StringName
	var name_key := ""
	var effect_key := ""
	var cost := 0

	func _init(mutation_id: StringName, name: String, effect: String, price: int) -> void:
		id = mutation_id
		name_key = name
		effect_key = effect
		cost = price


var state := State.IDLE
var idle := CenterContainer.new()
var start_button := Button.new()
var choose := VBoxContainer.new()
var points_label := UiParts.styled_label("", &"ToyPlateTimer")
var cards := HBoxContainer.new()
var step := CenterContainer.new()
var chosen_label := UiParts.styled_label("", &"ToyKicker")
var pips := ToyPips.new(ToyPips.HEALTH)

## What the choose screen shows: the points and the mutations (each card's Mutate and its texts
## are written again on a language change).
var _points := 0
var _mutations: Array[Mutation] = []


func _init() -> void:
	name = "Screen"
	theme_type_variation = &"ToyPanelDialog"
	custom_minimum_size = SIZE
	_build_idle()
	_build_choose()
	_build_step()
	show_idle()


## Nobody uses the machine: its name and Start.
func show_idle() -> void:
	_show(State.IDLE)


## The choice for a player with `points` among `mutations`.
func show_choose(points: int, mutations: Array[Mutation]) -> void:
	_points = points
	_mutations = mutations
	_build_cards()
	_show(State.CHOOSE)


## The chosen mutation (its name's deck key) and its progress, 0 to 1, as ten pips.
func show_step(name_key: String, progress: float) -> void:
	chosen_label.text = name_key
	pips.set_fraction(clampf(progress, 0.0, 1.0))
	_show(State.STEP)


## The card of the mutation `id`; null for none.
func card_of(id: StringName) -> PanelContainer:
	for card: Node in cards.get_children():
		if card.get_meta(&"mutation", &"") == id:
			return card as PanelContainer
	return null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_write_cards()


func _show(now: State) -> void:
	state = now
	idle.visible = now == State.IDLE
	choose.visible = now == State.CHOOSE
	step.visible = now == State.STEP


func _build_idle() -> void:
	idle.name = "Idle"
	add_child(idle)
	var column := _column("V", &"ToyColumnTwentyFour")
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	idle.add_child(column)
	var title := UiParts.styled_label("workbench.title", &"ToyTitleMachine")
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	start_button.name = "Start"
	start_button.text = "workbench.start"
	start_button.theme_type_variation = &"ToyButtonPrimary"
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.custom_minimum_size = Vector2(START_WIDTH, 0)
	start_button.pressed.connect(start_pressed.emit)
	ToyPress.attach(start_button)
	column.add_child(start_button)


func _build_choose() -> void:
	choose.name = "Choose"
	choose.theme_type_variation = &"ToyColumnTwentyFour"
	add_child(choose)
	var top := HBoxContainer.new()
	top.name = "Top"
	top.theme_type_variation = &"ToyRowSixteen"
	choose.add_child(top)
	var title := UiParts.styled_label("workbench.title", &"ToyTitleMachine")
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	var balance := PanelContainer.new()
	balance.name = "Balance"
	balance.theme_type_variation = &"ToyPlateBalance"
	balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(balance)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.theme_type_variation = &"ToyRowSixteen"
	balance.add_child(row)
	var label := UiParts.styled_label("workbench.points", &"ToyTextMutedOnLight")
	label.name = "Label"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	points_label.name = "Points"
	points_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	points_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(points_label)
	cards.name = "Cards"
	cards.theme_type_variation = &"ToyRowTwentyFour"
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choose.add_child(cards)


func _build_step() -> void:
	step.name = "Step"
	add_child(step)
	var column := _column("V", &"ToyColumnTwentyFour")
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	step.add_child(column)
	chosen_label.name = "Chosen"
	chosen_label.uppercase = true
	chosen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(chosen_label)
	var step_in := UiParts.styled_label("workbench.step_in", &"ToyTitleOnLight")
	step_in.name = "StepIn"
	step_in.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(step_in)
	pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(pips)


## One card per mutation, in the given order, named by its id in PascalCase.
func _build_cards() -> void:
	for child: Node in cards.get_children():
		cards.remove_child(child)
		child.free()
	for mutation: Mutation in _mutations:
		cards.add_child(_card(mutation))
	_write_cards()


func _card(mutation: Mutation) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = String(mutation.id).to_pascal_case()
	card.theme_type_variation = &"ToyMutationCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta(&"mutation", mutation.id)
	card.mouse_entered.connect(_point.bind(card, true))
	card.mouse_exited.connect(_point.bind(card, false))
	var column := _column("V", &"ToyColumnSixteen")
	card.add_child(column)
	var card_name := UiParts.styled_label(mutation.name_key, &"ToyMutationCardName")
	card_name.name = "Name"
	column.add_child(card_name)
	var effect := UiParts.styled_label(mutation.effect_key, &"ToyMutationCardText")
	effect.name = "Effect"
	effect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	effect.custom_minimum_size = Vector2(EFFECT_WIDTH, 0)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(effect)
	var cost := UiParts.styled_label("", &"ToyMutationCardCost")
	cost.name = "Cost"
	cost.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(cost)
	var buy := Button.new()
	buy.name = "Buy"
	buy.theme_type_variation = &"ToyButtonMutate"
	buy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	buy.pressed.connect(func() -> void: mutate_pressed.emit(mutation.id))
	ToyPress.attach(buy)
	column.add_child(buy)
	return card


## The cards' texts and looks for the points now: the price, and Mutate or "N short" (disabled)
## with the name and the price dimmed.
func _write_cards() -> void:
	points_label.text = str(_points)
	for index in mini(cards.get_child_count(), _mutations.size()):
		var mutation := _mutations[index]
		var card := cards.get_child(index)
		var short := mutation.cost - _points
		var affordable := short <= 0
		var cost := card.get_node(^"V/Cost") as Label
		cost.text = tr_n("unit.points", "unit.points", mutation.cost).format(
			{"count": mutation.cost}
		)
		cost.theme_type_variation = (
			&"ToyMutationCardCost" if affordable else &"ToyMutationCardCostOff"
		)
		(card.get_node(^"V/Name") as Label).theme_type_variation = (
			&"ToyMutationCardName" if affordable else &"ToyMutationCardNameOff"
		)
		var buy := card.get_node(^"V/Buy") as Button
		buy.disabled = not affordable
		buy.text = (
			tr("workbench.mutate") if affordable else tr("workbench.short").format({"count": short})
		)


## The card under the pointer (the crosshair's pushed motion) is drawn pointed.
static func _point(card: PanelContainer, on: bool) -> void:
	card.theme_type_variation = &"ToyMutationCardPointed" if on else &"ToyMutationCard"


static func _column(column_name: String, variation: StringName) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = column_name
	column.theme_type_variation = variation
	return column
