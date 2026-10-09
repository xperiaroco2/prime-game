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


## The cards of `mode`'s task types that have one, in the mode's order.
static func of_tasks(mode: GameMode) -> Array[HowtoCard]:
	var found: Array[HowtoCard] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		var card := of_task(type.id) if type != null else null
		if card != null:
			found.append(card)
	return found


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


## The task types this round may deal, in `mode`'s order: the mode's minus the ones the host
## banned in the lobby (every id set of `model`'s settings is a set of banned task types,
## SettingSpec.Kind.TASK_TYPES). The deal itself comes at the end of Loading (DealTasks on
## `all_loaded`), so the loading screen knows no more than this.
static func dealable(mode: GameMode, model: ClientModel) -> Array[StringName]:
	var banned := PackedStringArray()
	if model != null:
		for id: StringName in model.id_sets:
			banned.append_array(model.id_sets[id])
	var found: Array[StringName] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type != null and not banned.has(String(type.id)):
			found.append(type.id)
	return found


static func _load(path: String) -> HowtoCard:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as HowtoCard
