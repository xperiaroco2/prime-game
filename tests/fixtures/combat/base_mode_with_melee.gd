class_name FixtureBaseModeWithMelee
extends GameMode
## The base mode as it was before the M8 slice took the hitting out of its Round (#1497): the
## shipped base mode (`content/modes/base_mode.tres`, read when this loads, so it never drifts from
## it) plus Round accepting Use from the living (the mode's fallback hit, Strike, and the knife's
## own Use rule) and the Loading row's SpawnItems of the knife by the setting `knives` (RNG purpose
## `knives`) between the task deal and the placement, where the shipped mode had them. The engineer
## took both out of the shipped match for the M8 slice (#507, comment 6549409184: "you can only
## take the crystal in your hands"; GDD §3 "The M8 slice", item 2), keeping the code, the knife and
## the lobby's hits; the bot scenarios and the chaos run that knock players down in a round play
## here. Loaded through `base_mode_with_melee.tres` (PATH), so a bot scenario can name it as its
## mode and a command log replays it by its path.

const PATH := "res://tests/fixtures/combat/base_mode_with_melee.tres"
const BASE_MODE := "res://content/modes/base_mode.tres"
const KNIFE := "res://content/items/knife.tres"
const KNIVES := &"knives"


func _init() -> void:
	var base := load(BASE_MODE) as GameMode
	for property: Dictionary in base.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name: String = property["name"]
			var value: Variant = base.get(property_name)
			# Its own arrays: the copies below leave the cached shipped mode's alone (the parts in
			# them are shared, as the shipped mode's own).
			if value is Array:
				value = (value as Array).duplicate()
			elif value is Dictionary:
				value = (value as Dictionary).duplicate()
			set(property_name, value)
	round_takes_use(self)
	_loading_spawns_knives()


## The mode, loaded from PATH.
static func mode() -> GameMode:
	return load(PATH) as GameMode


## Gives `target` an own copy of Round that takes Use from the living, after PutDown (its place in
## the shipped mode before #1497). `target`'s phases array must be its own, as a fixture mode's copy
## of the shipped one is (house_zone_test.gd's knockdown on the zone fixture).
static func round_takes_use(target: GameMode) -> void:
	for index: int in target.phases.size():
		var spec := target.phases[index]
		if spec.id != &"round":
			continue
		var copy := spec.duplicate() as PhaseSpec
		var use := AcceptSpec.new()
		use.intent = Intents.USE
		use.from = AcceptSpec.From.LIVING
		var accepts: Array[AcceptSpec] = []
		for accept: AcceptSpec in spec.accepts:
			accepts.append(accept)
			if accept.intent == Intents.PUT_DOWN:
				accepts.append(use)
		if not accepts.has(use):
			push_error("base_mode_with_melee: the shipped Round takes no PutDown")
		copy.accepts = accepts
		target.phases[index] = copy


## An own copy of the Loading row `all_loaded` that places the knives after the task deal and before
## the players (its order in the shipped mode before #1497: the deal's RNG draws stay the same).
func _loading_spawns_knives() -> void:
	for index: int in transitions.size():
		var row := transitions[index]
		if row.from != &"loading" or row.outcome != &"all_loaded":
			continue
		var copy := row.duplicate() as Transition
		var spawn := SpawnItems.new()
		spawn.kind = load(KNIFE) as ItemKind
		spawn.count_setting = KNIVES
		spawn.rng_purpose = KNIVES
		var row_actions: Array[RuleEffect] = []
		var placed := false
		for action: RuleEffect in row.actions:
			if action is PlacePlayers and not placed:
				row_actions.append(spawn)
				placed = true
			row_actions.append(action)
		if not placed:
			push_error("base_mode_with_melee: the shipped Loading row places no players")
		copy.actions = row_actions
		transitions[index] = copy
