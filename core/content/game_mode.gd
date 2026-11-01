class_name GameMode
extends ContentPart
## Which phases, rules and settings a match has (ARCHITECTURE §3.1, §9.3). A game mode is data:
## core/ classes composed in a `.tres` in `content/modes/`. Match knows no mode; it runs this one.
## ModeCheck refuses a mode that names something it does not declare (§9.1).
##
## The class defaults are neutral (0): a mode's numbers are written in its data, where the
## designer sees them (the engineer's answer on #49), and a mode that omits them is refused.

@export var min_players := 0
@export var max_players := 0
@export var settings: Array[SettingSpec] = []
@export var player_rules: PlayerRules
@export var sides: Array[SideSpec] = []
@export var roles: Array[GameRole] = []
@export var item_kinds: Array[ItemKind] = []
## The lobby level's path, which server/ loads.
@export var lobby_level: String
## The maps' paths; a match plays on one of them (default_map() by default).
@export var maps: PackedStringArray = PackedStringArray()
## The maps of `maps` that are test benches only (#767: the flat greybox, for the bot scenarios and
## the information-leak test, ARCHITECTURE §9.7): the lobby never offers one and no match starts on
## one by default; a bot scenario plays on the first unless it names another map. Players play the
## rest (player_maps()).
@export var bench_maps: PackedStringArray = PackedStringArray()
## Rules on intents that apply to every player.
@export var actions: Array[Rule] = []
## Rules on facts (§9.2).
@export var reactions: Array[Rule] = []
## In order: each type's check of a fact runs in this order.
@export var task_types: Array[TaskType] = []
## In order: the first that holds wins.
@export var win_conditions: Array[WinCondition] = []
@export var phases: Array[PhaseSpec] = []
@export var first_phase: StringName
@export var transitions: Array[Transition] = []
## The pose wheel's leg stances and arm gestures (#1485), or null for a mode without the wheel. A
## rule holding TakeWheelPose needs it (ModeCheck).
@export var wheel_poses: WheelPoses


func find_phase(id: StringName) -> PhaseSpec:
	for phase: PhaseSpec in phases:
		if phase != null and phase.id == id:
			return phase
	return null


## The row for `outcome` from phase `from`, or null.
func find_transition(from: StringName, outcome: StringName) -> Transition:
	for row: Transition in transitions:
		if row != null and row.from == from and row.outcome == outcome:
			return row
	return null


func find_setting(id: StringName) -> SettingSpec:
	for setting: SettingSpec in settings:
		if setting != null and setting.id == id:
			return setting
	return null


func find_side(id: StringName) -> SideSpec:
	for side: SideSpec in sides:
		if side != null and side.id == id:
			return side
	return null


func find_role(id: StringName) -> GameRole:
	for role: GameRole in roles:
		if role != null and role.id == id:
			return role
	return null


func find_item_kind(id: StringName) -> ItemKind:
	for kind: ItemKind in item_kinds:
		if kind != null and kind.id == id:
			return kind
	return null


func find_task_type(id: StringName) -> TaskType:
	for type: TaskType in task_types:
		if type != null and type.id == id:
			return type
	return null


## The maps players play, in the order of `maps`: every map but the test benches (`bench_maps`).
func player_maps() -> PackedStringArray:
	var found := PackedStringArray()
	for map: String in maps:
		if not bench_maps.has(map):
			found.append(map)
	return found


## The map a match starts on, and plays unless the host picks another: the first map players play;
## empty when the mode has none.
func default_map() -> String:
	var playable := player_maps()
	return playable[0] if not playable.is_empty() else ""


## Every declared whole-number setting at its default.
func default_settings() -> Dictionary[StringName, int]:
	var values: Dictionary[StringName, int] = {}
	for setting: SettingSpec in settings:
		if setting != null and setting.is_number():
			values[setting.id] = setting.default_value
	return values


## Every declared set setting (SettingSpec.Kind.TASK_TYPES) at its default, the empty set.
func default_id_sets() -> Dictionary[StringName, PackedStringArray]:
	var values: Dictionary[StringName, PackedStringArray] = {}
	for setting: SettingSpec in settings:
		if setting != null and not setting.is_number():
			values[setting.id] = PackedStringArray()
	return values


## The ids of the settings some part of the mode names in a `*_setting` property (the parts
## ModeCheck walks): a declared setting outside them changes nothing in a match, so the lobby hides
## its row and the presets that change it (the base mode's `knives` in the M8 slice, #1525).
func read_settings() -> Array[StringName]:
	var found: Array[StringName] = []
	_collect_read(self, found, {})
	return found


static func _collect_read(value: Variant, found: Array[StringName], seen: Dictionary) -> void:
	if value is Array:
		for item: Variant in value as Array:
			_collect_read(item, found, seen)
		return
	if value is Script or not (value is Resource) or seen.has(value):
		return
	var resource: Resource = value
	seen[resource] = true
	for property: Dictionary in resource.get_property_list():
		var name: String = property["name"]
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0 or name == "script":
			continue
		var child: Variant = resource.get(name)
		if name.ends_with("_setting") and (child is StringName or child is String):
			var id := StringName(str(child))
			if not id.is_empty() and not found.has(id):
				found.append(id)
		else:
			_collect_read(child, found, seen)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if min_players < 1 or min_players > max_players:
		found.append("players: min_players %d and max_players %d" % [min_players, max_players])
	if max_players > PlayerColours.COUNT:
		# A joiner takes the first free body colour (#551): one more player than colours has none.
		found.append(
			(
				"players: max_players %d is more than the %d body colours"
				% [max_players, PlayerColours.COUNT]
			)
		)
	if player_rules == null:
		found.append("the mode has no player_rules")
	if phases.is_empty():
		found.append("the mode has no phases")
	elif find_phase(first_phase) == null:
		found.append("first_phase %s is not a phase of the mode" % first_phase)
	for spec: PhaseSpec in phases:
		if spec == null:
			continue
		if spec.level == PhaseSpec.Level.LOBBY and lobby_level.is_empty():
			found.append("phase %s plays in the lobby, but lobby_level is empty" % spec.id)
		elif spec.level == PhaseSpec.Level.MAP and maps.is_empty():
			found.append("phase %s plays on the map, but the mode has no maps" % spec.id)
	for map: String in bench_maps:
		if not maps.has(map):
			found.append("bench map %s is not one of the mode's maps" % map)
	if not maps.is_empty() and player_maps().is_empty():
		found.append("every map is a test bench: players have none")
	return found
