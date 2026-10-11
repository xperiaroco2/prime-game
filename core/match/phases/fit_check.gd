class_name FitCheck
extends RefCounted
## Whether the settings fit the chosen map for the current player count (ARCHITECTURE §3.2,
## §9.4): the player count within the mode's bounds, and the demands of every row into a phase on
## the map (markers per spawn tag, colours per station kind) within the map's markers and the
## palettes (Demands.shortfalls). The lobby's `all_ready` needs it to pass, and SettingsChanged
## carries it, so the lobby can show why `all_ready` cannot fire.


## What the rows into the map demand with the current settings and players.
static func demands(ctx: MatchContext) -> Demands:
	return LayoutCheck.demands_of(
		ctx.mode,
		PhaseSpec.Level.MAP,
		ctx.state.settings,
		ctx.state.present_peers().size(),
		ctx.state.id_sets
	)


## Every reason the settings do not fit, as HostTexts (#548): the player count first
## (`players_few` or `players_many`, with `count` off the bound, `min` and `max`), then `no_layout`
## or the map's shortfalls (Demands.shortfalls). Empty when they fit.
static func shortfalls(ctx: MatchContext, needed: Demands) -> Array[HostText]:
	var found: Array[HostText] = []
	var players := ctx.state.present_peers().size()
	var bounds: Dictionary[StringName, int] = {
		&"min": ctx.mode.min_players, &"max": ctx.mode.max_players
	}
	if players < ctx.mode.min_players:
		bounds[&"count"] = ctx.mode.min_players - players
		found.append(HostText.of(HostText.PLAYERS_FEW, PackedStringArray(), bounds))
	elif players > ctx.mode.max_players:
		bounds[&"count"] = players - ctx.mode.max_players
		found.append(HostText.of(HostText.PLAYERS_MANY, PackedStringArray(), bounds))
	var layout := ctx.map_layout()
	if layout == null:
		# No arguments: a map path is not a wire id, and SettingsChanged names the map.
		found.append(HostText.of(HostText.NO_LAYOUT))
	else:
		found.append_array(needed.shortfalls(layout))
	return found


static func fits(ctx: MatchContext) -> bool:
	return shortfalls(ctx, demands(ctx)).is_empty()


## SettingsChanged with the settings, the demands against the map and the shortfalls.
static func settings_changed(ctx: MatchContext) -> SettingsChangedEvent:
	var needed := demands(ctx)
	return SettingsChangedEvent.new(
		ctx.state.settings,
		ctx.state.map,
		ctx.state.present_peers().size(),
		needed,
		ctx.map_layout(),
		shortfalls(ctx, needed),
		id_sets(ctx),
		ctx.state.lobby_name
	)


## Every set setting of the mode with its value: the host's, or its default, the empty set.
static func id_sets(ctx: MatchContext) -> Dictionary[StringName, PackedStringArray]:
	var values := ctx.mode.default_id_sets()
	for id: StringName in values:
		values[id] = ctx.id_set(id)
	return values


## `all_ready` (§3.2): every player ready, and the settings fit the map for them.
static func all_ready(ctx: MatchContext) -> bool:
	var peers := ctx.state.present_peers()
	if peers.is_empty():
		return false
	for peer: int in peers:
		if not ctx.state.players[peer].ready:
			return false
	return fits(ctx)
