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
## The maps' paths; a match plays on one of them (the first by default).
@export var maps: PackedStringArray = PackedStringArray()
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


## Every declared setting at its default.
func default_settings() -> Dictionary[StringName, int]:
	var values: Dictionary[StringName, int] = {}
	for setting: SettingSpec in settings:
		if setting != null:
			values[setting.id] = setting.default_value
	return values


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if min_players < 1 or min_players > max_players:
		found.append("players: min_players %d and max_players %d" % [min_players, max_players])
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
	return found
