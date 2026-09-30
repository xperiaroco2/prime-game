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
		ctx.mode, PhaseSpec.Level.MAP, ctx.state.settings, ctx.state.present_peers().size()
	)


## Every reason the settings do not fit; empty when they do.
static func shortfalls(ctx: MatchContext, needed: Demands) -> PackedStringArray:
	var found := PackedStringArray()
	var players := ctx.state.present_peers().size()
	if players < ctx.mode.min_players or players > ctx.mode.max_players:
		found.append(
			(
				"%d player(s), the mode plays with %d to %d"
				% [players, ctx.mode.min_players, ctx.mode.max_players]
			)
		)
	var layout := ctx.map_layout()
	if layout == null:
		found.append("no layout for the map %s" % ctx.state.map)
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
		shortfalls(ctx, needed)
	)


## `all_ready` (§3.2): every player ready, and the settings fit the map for them.
static func all_ready(ctx: MatchContext) -> bool:
	var peers := ctx.state.present_peers()
	if peers.is_empty():
		return false
	for peer: int in peers:
		if not ctx.state.players[peer].ready:
			return false
	return fits(ctx)
