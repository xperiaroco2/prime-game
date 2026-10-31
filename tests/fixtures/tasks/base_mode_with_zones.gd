class_name FixtureBaseModeWithZones
extends GameMode
## The base mode as release/m7's #649 made it, for the zone task's tests and scenarios: the
## shipped base mode (`content/modes/base_mode.tres`, read when this loads, so it never drifts
## from it) plus the zone task `content/tasks/hold_the_zone.tres`, the setting `zones` (1 to 1)
## and `tasks` 2 (1 to 2): every match deals Delivery and the zone task; the Generator, the photo
## task (#784), Cooking (#775), car repair (#810) and the ship's engine (#1462), their settings,
## Cooking's item kinds and the Interact accepts of Round (#800), the Lobby and the Countdown
## (#1388) left out (the film, photo, car part and crystal item kinds stay, unused). The
## engineer took the zone task out of the shipped base mode on #842 (comment 6110558513: "only
## from the mode, now"), keeping its code, its tests and the House's zones; this fixture is where
## they run. Loaded through `base_mode_with_zones.tres` (PATH), so a bot scenario can name it as
## its mode.

const PATH := "res://tests/fixtures/tasks/base_mode_with_zones.tres"
const BASE_MODE := "res://content/modes/base_mode.tres"
const ZONE_TASK := "res://content/tasks/hold_the_zone.tres"


func _init() -> void:
	var base := load(BASE_MODE) as GameMode
	for property: Dictionary in base.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name: String = property["name"]
			var value: Variant = base.get(property_name)
			# Its own arrays: a test that changes the fixture's list leaves the cached shipped
			# mode's alone (the parts in them are shared, as the shipped mode's own).
			if value is Array:
				value = (value as Array).duplicate()
			elif value is Dictionary:
				value = (value as Dictionary).duplicate()
			set(property_name, value)
	var tasks := SettingSpec.new()
	tasks.id = &"tasks"
	tasks.display_name = "Tasks"
	tasks.default_value = 2
	tasks.min_value = 1
	tasks.max_value = 2
	var zones := SettingSpec.new()
	zones.id = &"zones"
	zones.display_name = "Zones (Hold the zone)"
	zones.default_value = 1
	zones.min_value = 1
	zones.max_value = 1
	# Without the Generator (#800), the photo task (#784), Cooking (#775), car repair (#810) and
	# the ship's engine (#1462, its stations used with the Interact this Round drops): these tests
	# are the zone task beside Delivery, as #649 made it. Their own tests load the shipped mode.
	# Cooking's item kinds go too: its boxes' take is an Interact rule, which Round here no longer
	# accepts (the car parts have no rule).
	var without: Array[StringName] = []
	var types: Array[TaskType] = []
	var kinds_out: Array[ItemKind] = []
	for type: TaskType in base.task_types:
		var other := type is Generator or type is PhotoTask or type is Cooking
		if other or type is CarRepair or type is ShipEngine:
			without.append(type.subtasks_setting)
		else:
			types.append(type)
		if type is Cooking:
			kinds_out.append_array((type as Cooking).kinds())
			kinds_out.append_array((type as Cooking).boxes)
	types.append(load(ZONE_TASK) as TaskType)
	task_types = types
	var kinds: Array[ItemKind] = []
	for kind: ItemKind in base.item_kinds:
		if not kinds_out.has(kind):
			kinds.append(kind)
	item_kinds = kinds
	_without_interact()
	var with_zones: Array[SettingSpec] = []
	for spec: SettingSpec in base.settings:
		if without.has(spec.id):
			continue
		with_zones.append(tasks if spec.id == &"tasks" else spec)
		if spec.id == &"packages":
			with_zones.append(zones)
	settings = with_zones


## The mode, loaded from PATH.
static func mode() -> GameMode:
	return load(PATH) as GameMode


## The own copies (Round, the Lobby and the Countdown) without Interact, which only the task types'
## station rules left out above handle (the mode check refuses an accepted intent no rule
## handles); the shipped mode's phases stay as they are.
func _without_interact() -> void:
	var own: Array[PhaseSpec] = []
	for spec: PhaseSpec in phases:
		if spec.senders_of(Intents.INTERACT) == 0:
			own.append(spec)
			continue
		var copy := spec.duplicate() as PhaseSpec
		var accepts: Array[AcceptSpec] = []
		for accept: AcceptSpec in spec.accepts:
			if accept.intent != Intents.INTERACT:
				accepts.append(accept)
		copy.accepts = accepts
		own.append(copy)
	phases = own
