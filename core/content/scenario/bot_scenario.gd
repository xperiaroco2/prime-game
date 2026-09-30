class_name BotScenario
extends Resource
## A scripted match that shows a mechanic working end to end, played only with what each player
## is told (ARCHITECTURE §9.7). Data only, like every class in this folder: the runners in
## tests/harness/ (the core runner, 2j) and M3's bots play it. Files: content/scenarios/*.tres.
##
## The setup: the mode, the map, the session seed, the bots (bot 1 is the host's own client), the
## match settings that differ from the defaults (the host's bot sends them and the map in one
## ChangeSettings right after its join, so it joins at the start) and the roles forced per bot
## (debug builds only, invariant 8; a forced role counts toward its quota). By default every bot
## joins at the start and acknowledges every LoadMatch at once; the steps StepJoin and StepLoadAck
## change that for one bot. Then one script per bot, run at the same time; the expected ends, one
## per match played, in order; a time limit for the whole run; and the events some bot must never
## receive.

## An expected end that is no winning side: passes when every script finished within the time
## limit and no further MatchEnded arrived.
const NONE := &"none"

@export var mode: GameMode
## One of the mode's maps; empty means its first.
@export var map := ""
@export var session_seed := 1
## How many bots play, 1 to the mode's maximum of players.
@export var bots := 1
## Match settings (whole numbers) that differ from the mode's defaults.
@export var settings: Dictionary[StringName, int] = {}
## Bot number -> role id, forced before the deal (debug builds only).
@export var forced_roles: Dictionary[int, StringName] = {}
## scripts[i] is bot i + 1's; a bot without one only joins and loads.
@export var scripts: Array[BotScript] = []
## One per match the scenario plays, in order: a side id of the mode, or NONE.
@export var expected_ends: Array[StringName] = []
## Seconds of match time for the whole run.
@export var time_limit_s := 120.0
@export var never: Array[NeverEvent] = []


## The steps of bot `bot` (1-based), in order; empty when it has no script.
func steps_of(bot: int) -> Array[ScenarioStep]:
	if bot < 1 or bot > scripts.size() or scripts[bot - 1] == null:
		return []
	return scripts[bot - 1].steps


## What makes this scenario unplayable, each once; empty when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if mode == null:
		found.append("no mode")
		return found
	if bots < 1 or bots > mode.max_players:
		found.append("bots is %d, outside 1 to %d" % [bots, mode.max_players])
	if not map.is_empty() and not mode.maps.has(map):
		found.append("map %s is not one of the mode's maps" % map)
	if (not settings.is_empty() or not map.is_empty()) and not steps_of(1).is_empty():
		for step: ScenarioStep in steps_of(1):
			if step is StepJoin:
				found.append("bot 1 sends the setup's settings and map, so it joins at the start")
	if scripts.size() > bots:
		found.append("%d scripts for %d bots" % [scripts.size(), bots])
	for bot: int in forced_roles:
		if bot < 1 or bot > bots:
			found.append("a forced role for bot %d, outside 1 to %d" % [bot, bots])
		elif mode.find_role(forced_roles[bot]) == null:
			found.append(
				"bot %d is forced to role %s, which the mode lacks" % [bot, forced_roles[bot]]
			)
	for id: StringName in settings:
		if mode.find_setting(id) == null:
			found.append("setting %s is not the mode's" % id)
	if expected_ends.is_empty():
		found.append("no expected end")
	for end: StringName in expected_ends:
		if end != NONE and mode.find_side(end) == null:
			found.append("expected end %s is neither none nor a side of the mode" % end)
	if time_limit_s <= 0.0:
		found.append("time_limit_s is not positive")
	for bot in range(1, scripts.size() + 1):
		for step: ScenarioStep in steps_of(bot):
			if step == null:
				found.append("bot %d has an empty step" % bot)
				continue
			for problem: String in step.problems():
				found.append("bot %d, %s: %s" % [bot, step.step_name(), problem])
	return found
