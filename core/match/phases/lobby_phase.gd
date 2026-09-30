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


## ChangeSettings(settings, map) from the host (§4.1): `settings` maps setting ids to whole
## numbers and names only the settings that change; `map` is optional. Every value is checked
## before any is applied: a key the mode does not declare or a value that is not an int
## (`unknown_setting`), a value outside its bounds (`out_of_bounds`), a map the mode does not
## list (`unknown_map`). Whether they fit the map is checked at `all_ready`.
static func _change_settings(ctx: MatchContext, command: MatchCommand) -> bool:
	var raw: Variant = command.args.get("settings", {})
	if not raw is Dictionary:
		ctx.reject(command, RejectReasons.UNKNOWN_SETTING)
		return false
	var changes: Dictionary[StringName, int] = {}
	var given: Dictionary = raw
	for key: Variant in given:
		var spec_of: SettingSpec = null
		if key is String or key is StringName:
			spec_of = ctx.mode.find_setting(StringName(str(key)))
		var value: Variant = given[key]
		if spec_of == null or not value is int:
			ctx.reject(command, RejectReasons.UNKNOWN_SETTING)
			return false
		if not spec_of.accepts(value as int):
			ctx.reject(command, RejectReasons.OUT_OF_BOUNDS)
			return false
		changes[spec_of.id] = value as int
	var map := ctx.state.map
	if command.args.has("map"):
		var asked: Variant = command.args["map"]
		if not asked is String or not ctx.mode.maps.has(asked as String):
			ctx.reject(command, RejectReasons.UNKNOWN_MAP)
			return false
		map = asked as String
	for id: StringName in changes:
		ctx.state.settings[id] = changes[id]
	ctx.state.map = map
	ctx.emit(FitCheck.settings_changed(ctx))
	return true


static func _check_all_ready(ctx: MatchContext) -> void:
	if FitCheck.all_ready(ctx):
		ctx.report_outcome(ALL_READY)
