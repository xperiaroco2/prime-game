class_name HowtoCards
extends RefCounted
## Where the how-to cards (#254, HowtoCard) live and which ones a screen shows: a task type's card
## is `TASKS/<task type id>.tres`, a basic of the Esc menu's Guide `BASICS_FOLDER/<id>.tres`
## (content data; a content test holds that every task type of every mode has a valid card).

const TASKS := "res://content/howto/tasks/"
const BASICS_FOLDER := "res://content/howto/basics/"
## The Guide's basics, in its order (prime-game-ui's s5 `guide`): moving and hands, voice, downed
## and back.
const BASICS: Array[StringName] = [&"moving", &"voice", &"downed"]


## The card of the task type `type`; null when it has none.
static func of_task(type: StringName) -> HowtoCard:
	return _load(TASKS + "%s.tres" % type)


## The card of the basic `id` (one of BASICS); null when it has none.
static func of_basic(id: StringName) -> HowtoCard:
	return _load(BASICS_FOLDER + "%s.tres" % id)


## The cards of `mode`'s task types that have one and play on `map` (TaskType.maps; every type
## when `map` is empty), in the mode's order: the Guide lists the picked map's (DE16 of the
## delivery-by-meaning ADR), so the House shows one Delivery and the greybox another.
static func of_tasks(mode: GameMode, map := "") -> Array[HowtoCard]:
	var found: Array[HowtoCard] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type == null or not type.plays_on(map):
			continue
		var card := of_task(type.id)
		if card != null:
			found.append(card)
	return found


## The map a client's task lists follow (DE16): `map`, the lobby's picked one or the match's, else
## `mode`'s default (GameMode.default_map(), the picker's first) while no Welcome has named one, so
## a list never shows every map's types at once; empty with no mode.
static func shown_map(mode: GameMode, map: String) -> String:
	if not map.is_empty() or mode == null:
		return map
	return mode.default_map()


## What keeps `mode`'s task types from each having a valid card, one line each; empty when every
## one has (the content test holds it for every mode in content/modes/).
static func problems_of(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	for type: TaskType in mode.task_types:
		if type == null:
			continue
		var card := of_task(type.id)
		if card == null:
			found.append("task type %s has no how-to card at %s%s.tres" % [type.id, TASKS, type.id])
			continue
		if card.id != type.id:
			found.append("the card of task type %s says it is %s's" % [type.id, card.id])
		for problem: String in card.problems():
			found.append("the card of task type %s: %s" % [type.id, problem])
	return found


## The task types this round may deal, in `mode`'s order: the pool of the mode's DealTasks (its
## task types minus the ones the host banned in the lobby, the id set its `banned_setting` names
## in `model`'s settings; no other set) that play on the lobby's map (`model.map`, TaskType.maps;
## every type while the model has no map or is null); none when the mode deals no tasks. The deal
## itself comes at the end of Loading (DealTasks on `all_loaded`), so the loading screen knows no
## more.
static func dealable(mode: GameMode, model: ClientModel) -> Array[StringName]:
	var found: Array[StringName] = []
	var deal := deal_of(mode)
	if deal == null:
		return found
	var banned := PackedStringArray()
	var map := ""
	if model != null:
		banned = model.id_sets.get(deal.banned_setting, PackedStringArray())
		map = model.map
	for type: TaskType in DealTasks.pool_of(mode, banned, map):
		found.append(type.id)
	return found


## The DealTasks among `mode`'s transition actions (the base mode's on `all_loaded`); null when
## it deals no tasks.
static func deal_of(mode: GameMode) -> DealTasks:
	if mode == null:
		return null
	for row: Transition in mode.transitions:
		if row == null:
			continue
		for action: RuleEffect in row.actions:
			if action is DealTasks:
				return action as DealTasks
	return null


## Those of `types` that have a card, in their order: the loading screen picks among them, so a
## type without one (the content test fails it) does not hide a later type's card.
static func with_card(types: Array[StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for type: StringName in types:
		if of_task(type) != null:
			found.append(type)
	return found


static func _load(path: String) -> HowtoCard:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as HowtoCard
