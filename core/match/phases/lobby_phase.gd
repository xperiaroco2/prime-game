class_name LobbyPhase
extends Phase
## The base mode's Lobby (ARCHITECTURE §3.2, §3.5, §9.4). On entry AllowJoins (server). Joins
## (Hello: Welcome, PlayerJoined, SettingsChanged), leaves (PlayerLeft, SettingsChanged),
## SetReady (true or false, only a change: ReadyChanged) and the host's ChangeSettings
## (SettingsChanged; a change un-readies nobody). Reports `all_ready` when every player is ready
## and the settings fit the map (FitCheck): after a SetReady, a settings change, a leave, and on
## entry, so a lobby re-entered with everyone still ready moves on at once.

const ALL_READY := &"all_ready"


func handled_intents() -> Array[StringName]:
	return [Intents.HELLO, Intents.SET_READY, Intents.CHANGE_SETTINGS]


func outcomes() -> Array[StringName]:
	return [ALL_READY]


func enter(ctx: MatchContext) -> void:
	ctx.emit(AllowJoinsEvent.new())
	_check_all_ready(ctx)


func handle_intent(ctx: MatchContext, command: MatchCommand) -> void:
	match command.kind:
		Intents.HELLO:
			# A joiner is not ready, so a join never completes all_ready.
			JoinRules.hello(ctx, command, spec.id)
		Intents.SET_READY:
			if not JoinRules.has_ready_flag(ctx, command):
				return
			if JoinRules.set_ready(ctx, command, command.get_bool("ready")):
				_check_all_ready(ctx)
		Intents.CHANGE_SETTINGS:
			if _change_settings(ctx, command):
				_check_all_ready(ctx)
		_:
			ctx.reject(command, RejectReasons.NOTHING_TO_DO)


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.connect_peer(ctx, peer)


func on_peer_left(ctx: MatchContext, peer: int) -> void:
	if JoinRules.leave(ctx, peer):
		ctx.emit(FitCheck.settings_changed(ctx))
		_check_all_ready(ctx)


## ChangeSettings(settings, map) from the host (§4.1): `settings` maps setting ids to values and
## names only the settings that change; `map` is optional. A whole-number setting takes an int; a
## set of task types (the bans, #79) takes an Array of task type ids, which replaces the set.
## Every value is checked before any is applied: a key the mode does not declare, or a value of
## the wrong type (`unknown_setting`); a number outside its bounds, or an id that is not one of
## the mode's task types (`out_of_bounds`); a map the mode does not list (`unknown_map`); then
## the settings as they would be, by every row's actions (RuleEffect.settings_problem: DealTasks
## refuses more `tasks` than task types left, or every type banned). Whether they fit the map is
## checked at `all_ready`.
static func _change_settings(ctx: MatchContext, command: MatchCommand) -> bool:
	var raw: Variant = command.field("settings") if command.has_field("settings") else {}
	if not raw is Dictionary:
		ctx.reject(command, RejectReasons.UNKNOWN_SETTING)
		return false
	var numbers: Dictionary[StringName, int] = ctx.state.settings.duplicate()
	var sets: Dictionary[StringName, PackedStringArray] = ctx.state.id_sets.duplicate(true)
	var given: Dictionary = raw
	for key: Variant in given:
		var spec_of: SettingSpec = null
		if key is String or key is StringName:
			spec_of = ctx.mode.find_setting(StringName(str(key)))
		if spec_of == null:
			ctx.reject(command, RejectReasons.UNKNOWN_SETTING)
			return false
		var reason := (
			_take_number(spec_of, given[key], numbers)
			if spec_of.is_number()
			else _take_task_types(ctx.mode, spec_of, given[key], sets)
		)
		if not reason.is_empty():
			ctx.reject(command, reason)
			return false
	var map := ctx.state.map
	if command.has_field("map"):
		var asked: Variant = command.field("map")
		if not asked is String or not ctx.mode.maps.has(asked as String):
			ctx.reject(command, RejectReasons.UNKNOWN_MAP)
			return false
		map = asked as String
	for row: Transition in ctx.mode.transitions:
		if row == null:
			continue
		for action: RuleEffect in row.actions:
			if action == null:
				continue
			var problem := action.settings_problem(numbers, sets, ctx.mode)
			if not problem.is_empty():
				ctx.reject(command, problem)
				return false
	ctx.state.settings = numbers
	ctx.state.id_sets = sets
	ctx.state.map = map
	ctx.emit(FitCheck.settings_changed(ctx))
	return true


## A whole number for `declared` into `numbers`; the rejection reason, or empty.
static func _take_number(
	declared: SettingSpec, value: Variant, numbers: Dictionary[StringName, int]
) -> StringName:
	if not value is int:
		return RejectReasons.UNKNOWN_SETTING
	if not declared.accepts(value as int):
		return RejectReasons.OUT_OF_BOUNDS
	numbers[declared.id] = value as int
	return &""


## A set of task type ids for `declared` into `sets`, in the mode's order with duplicates collapsed;
## the rejection reason, or empty.
static func _take_task_types(
	mode: GameMode,
	declared: SettingSpec,
	value: Variant,
	sets: Dictionary[StringName, PackedStringArray]
) -> StringName:
	if not value is Array and not value is PackedStringArray:
		return RejectReasons.UNKNOWN_SETTING
	var asked: Dictionary[StringName, bool] = {}
	for entry: Variant in value:
		if not entry is String and not entry is StringName:
			return RejectReasons.UNKNOWN_SETTING
		var id := StringName(str(entry))
		if mode.find_task_type(id) == null:
			return RejectReasons.OUT_OF_BOUNDS
		asked[id] = true
	var ids := PackedStringArray()
	for type: TaskType in mode.task_types:
		if type != null and asked.has(type.id):
			ids.append(String(type.id))
	sets[declared.id] = ids
	return &""


static func _check_all_ready(ctx: MatchContext) -> void:
	if FitCheck.all_ready(ctx):
		ctx.report_outcome(ALL_READY)
