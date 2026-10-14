class_name FixtureBaseModeWithZones
extends GameMode
## The base mode as release/m7's #649 made it, for the zone task's tests and scenarios: the
## shipped base mode (`content/modes/base_mode.tres`, read when this loads, so it never drifts
## from it) plus the zone task `content/tasks/hold_the_zone.tres`, the setting `zones` (1 to 1)
## and `tasks` 2 (1 to 2): every match deals Delivery and the zone task; the Generator, its
## setting and Round's Interact (#800) left out. The engineer took the
## zone task out of the shipped base mode on #842 (comment 6110558513: "only from the mode, now"),
## keeping its code, its tests and the House's zones; this fixture is where they run. Loaded
## through `base_mode_with_zones.tres` (PATH), so a bot scenario can name it as its mode.

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
	# Without the Generator (#800): its House would deal two of three types, and these tests are
	# the zone task beside Delivery, as #649 made it. The Generator's own tests load the shipped mode.
	var without: Array[StringName] = []
	var types: Array[TaskType] = []
	for type: TaskType in base.task_types:
		if type is Generator:
			without.append(type.subtasks_setting)
		else:
			types.append(type)
	types.append(load(ZONE_TASK) as TaskType)
	task_types = types
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


## Round's own copy without Interact, which only the Generator's station rules handle (the mode
## check refuses an accepted intent no rule handles); the shipped mode's phases stay as they are.
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
