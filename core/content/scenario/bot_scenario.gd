class_name BotScenario
extends Resource
## A scripted match that shows a mechanic working end to end, played only with what each player
## is told (ARCHITECTURE §9.7). Data only, like every class in this folder: the runners in
## tests/harness/ (the core runner, 2j) and M3's bots play it. Files: content/scenarios/*.tres.
##
## The setup: the mode, the map, the session seed, the bots (bot 1 is the host's own client), the
## match settings that differ from the defaults (the host's bot sends them and the map in one
## ChangeSettings right after its join, so it joins at the start) and the roles forced per bot
## (debug builds only, invariant 8; a forced role counts toward its quota), and the match clock's
## length when it is forced (clock_s, ForceClock, M4-3). By default every bot joins at the start and
## acknowledges every LoadMatch at once; the steps StepJoin and StepLoadAck change that for one bot.
## Then one script per bot, run at the same time; the expected ends, one per match played, in order;
## a time limit for the whole run; the events some bot must never receive; and how the bots'
## synthetic voice talks (M5-1): in talk spurts by default, or continuously.

## How the bots' synthetic voice talks (ARCHITECTURE §4.6): 50 frames a second in talk spurts, a
## deterministic pattern per bot, like players whose gate opens while they speak; or every frame,
## the load of everyone talking at once (M5-4's measurement).
enum Voice { SPURTS, CONTINUOUS }

## An expected end that is no winning side: passes when every script finished within the time
## limit and no further MatchEnded arrived.
const NONE := &"none"
## The smallest session seed: the runner's seed check (§5) looks for the seed's number in every
## event, so a small seed would be mistaken for a peer id, an item id or a count.
const MIN_SEED := 1_000_000

@export var mode: GameMode
## One of the mode's maps; empty means its first.
@export var map := ""
@export var session_seed := 100_000_000_001
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
## The match clock's length in seconds, forced by the host's bot with the debug command ForceClock
## (debug builds only, invariant 8) in place of the match duration setting's whole minutes; 0
## keeps the setting. A scenario that ends by time up then need not wait a whole minute.
@export var clock_s := 0
## Seconds of match time for the whole run.
@export var time_limit_s := 120.0
@export var never: Array[NeverEvent] = []
@export var voice := Voice.SPURTS


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
	if clock_s < 0 or clock_s > 0xFFFF:
		found.append("clock_s %d is outside 0 to %d" % [clock_s, 0xFFFF])
	if time_limit_s <= 0.0:
		found.append("time_limit_s is not positive")
	if voice < 0 or voice >= Voice.size():
		found.append("voice %d is neither SPURTS nor CONTINUOUS" % voice)
	if session_seed < MIN_SEED:
		found.append(
			(
				"session_seed %d is below %d, too small to tell apart from ids and counts"
				% [session_seed, MIN_SEED]
			)
		)
	for bot in range(1, scripts.size() + 1):
		var joins := 0
		for step: ScenarioStep in steps_of(bot):
			if step is StepJoin:
				joins += 1
		if joins > 1:
			found.append("bot %d has %d Join steps; at most one" % [bot, joins])
		elif joins == 1 and not steps_of(bot)[0] is StepJoin:
			# Before its Welcome a bot runs only a Join, so a later Join would never be reached.
			found.append("bot %d: Join must be its first step" % bot)
		for step: ScenarioStep in steps_of(bot):
			if step == null:
				found.append("bot %d has an empty step" % bot)
				continue
			for problem: String in step.problems():
				found.append("bot %d, %s: %s" % [bot, step.step_name(), problem])
	return found
