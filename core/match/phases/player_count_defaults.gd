class_name PlayerCountDefaults
extends RefCounted
## The lobby's defaults that follow the player count (ARCHITECTURE §9.1, #1492): each whole-number
## setting whose SettingSpec has a `defaults_by_players` table and which the host never named
## (MatchState.host_settings) takes SettingSpec.default_for(the players present). The base mode's
## `dissidents` (the default humans) is one.
##
## Called where the lobby's roster changes and before what tells it: JoinRules.hello (after
## add_player, before Welcome, which copies the settings), the Lobby's and the Countdown's
## PeerLeft (before their SettingsChanged) and ResetMatch (after the players who left are
## dropped). Never in Loading or later: LoadMatch has carried the settings by then and no
## SettingsChanged follows, so a drop there keeps the value the deal reads.


static func follow(ctx: MatchContext) -> void:
	var players := ctx.state.present_peers().size()
	for spec: SettingSpec in ctx.mode.settings:
		if spec == null or not spec.is_number() or spec.defaults_by_players.is_empty():
			continue
		if ctx.state.host_settings.has(spec.id):
			continue
		ctx.state.settings[spec.id] = spec.default_for(players)
