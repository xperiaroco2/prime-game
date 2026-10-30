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
## synthetic voice talks (M5-1): in talk spurts by default, or continuously. A measurement (M5-4's
## voice_load) runs in the bots runner only when named.

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
## Said with a setup the lobby would refuse: its usual cause.
const HINT := ": bans that leave fewer task types than tasks need the lower tasks too"

@export var mode: GameMode
## One of the mode's maps; empty means the mode's first test bench (GameMode.bench_maps, #767:
## bots play only the flat levels, ARCHITECTURE §9.7), else its default map (played_map()).
@export var map := ""
@export var session_seed := 100_000_000_001
## How many bots play, 1 to the mode's maximum of players.
@export var bots := 1
## Match settings (whole numbers) that differ from the mode's defaults.
@export var settings: Dictionary[StringName, int] = {}
## The set settings (a set of the mode's task type ids: the base mode's `banned_task_types`, the
## host's bans, #79) that differ from the empty default, sent with `settings` in the setup's one
## ChangeSettings. A ban that leaves fewer task types than `tasks` needs the lower `tasks` in
## `settings` too: the lobby checks the numbers and the sets together (DealTasks.settings_problem).
@export var id_sets: Dictionary[StringName, PackedStringArray] = {}
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
## A load measurement (M5-4's voice_load, ARCHITECTURE §9.7): the bots runner plays it only when it
## is named (`tools\run.cmd bots voice_load --instances 8`), never in its run of every scenario
## (verify's `bots`), whose time it would multiply. The core runner's suite still plays it.
@export var measurement := false


## The steps of bot `bot` (1-based), in order; empty when it has no script.
func steps_of(bot: int) -> Array[ScenarioStep]:
	if bot < 1 or bot > scripts.size() or scripts[bot - 1] == null:
		return []
	return scripts[bot - 1].steps


## The setup's ChangeSettings arguments, as the host's bot sends them: `settings` (the numbers and
## the sets, by id) and `map` when one is named or the played map is not the mode's default (a test
## bench, #767); empty when the setup changes nothing.
func setup_change() -> Dictionary:
	var played := played_map()
	var sends_map := not map.is_empty() or (mode != null and played != mode.default_map())
	if settings.is_empty() and id_sets.is_empty() and not sends_map:
		return {}
	var values := {}
	for id: StringName in settings:
		values[String(id)] = settings[id]
	for id: StringName in id_sets:
		values[String(id)] = Array(id_sets[id])
	var args := {"settings": values}
	if sends_map:
		args["map"] = played
	return args


## The map the scenario plays on: `map` when named, else the mode's first test bench, else its
## default map; empty without a mode.
func played_map() -> String:
	if not map.is_empty():
		return map
	if mode == null:
		return ""
	return mode.bench_maps[0] if not mode.bench_maps.is_empty() else mode.default_map()


## What makes this scenario unplayable, each once; empty when it is fine. `events`: every event a
## bot can receive -> the fields a scenario may match on it (ScenarioBot.receivable_events(), from
## the wire schema: core/ references no net/), handed in by the runner; then each event a `never`,
## Expect, ExpectNone or WaitFor names, and each of its `fields` keys, must be one of them (#1235:
## a misspelled `never` or ExpectNone never matches, so it would pass forever). Empty skips that.
func problems(events: Dictionary[StringName, PackedStringArray] = {}) -> PackedStringArray:
	var found := PackedStringArray()
	if mode == null:
		found.append("no mode")
		return found
	if bots < 1 or bots > mode.max_players:
		found.append("bots is %d, outside 1 to %d" % [bots, mode.max_players])
	if not map.is_empty() and not mode.maps.has(map):
		found.append("map %s is not one of the mode's maps" % map)
	if not setup_change().is_empty() and not steps_of(1).is_empty():
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
	found.append_array(_set_problems())
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
		found.append_array(_join_problems(bot))
		for step: ScenarioStep in steps_of(bot):
			if step == null:
				found.append("bot %d has an empty step" % bot)
				continue
			for problem: String in step.problems():
				found.append("bot %d, %s: %s" % [bot, step.step_name(), problem])
			for problem: String in _step_event_problems(step, events):
				found.append("bot %d, %s: %s" % [bot, step.step_name(), problem])
			if step is StepExpectDrunk:
				found.append_array(_expect_drunk_problems(bot, step as StepExpectDrunk))
	for i in never.size():
		if never[i] == null:
			found.append("never %d is empty" % i)
		elif never[i].event.is_empty():
			found.append("never %d has no event" % i)
		elif not events.is_empty():
			for problem: String in event_problems(never[i].event, never[i].fields, events):
				found.append("never %d: %s" % [i, problem])
	return found


## An ExpectDrunk in bot `bot`'s script names 0 (itself, its SelfStatus) or another bot of the
## scenario: its own number would read an avatar its snapshot never holds, and fail as unseen.
func _expect_drunk_problems(bot: int, step: StepExpectDrunk) -> PackedStringArray:
	var found := PackedStringArray()
	if step.bot > bots:
		found.append("bot %d, ExpectDrunk: bot %d is outside 0 to %d" % [bot, step.bot, bots])
	elif step.bot == bot:
		found.append(
			(
				"bot %d, ExpectDrunk: bot %d is this bot itself, which reads its own value as bot 0"
				% [bot, bot]
			)
		)
	return found


## The event problems of a step that waits for or checks an event (Expect, ExpectNone, WaitFor);
## empty for any other step or without `events`.
static func _step_event_problems(
	step: ScenarioStep, events: Dictionary[StringName, PackedStringArray]
) -> PackedStringArray:
	if events.is_empty():
		return PackedStringArray()
	if step is StepExpect:
		return event_problems((step as StepExpect).event, (step as StepExpect).fields, events)
	if step is StepExpectNone:
		var none := step as StepExpectNone
		return event_problems(none.event, none.fields, events)
	if step is StepWaitFor:
		return event_problems((step as StepWaitFor).event, (step as StepWaitFor).fields, events)
	return PackedStringArray()


## Why `event` with `fields` would never match an event a bot receives: a name that is none of
## `events`, or a field key its event lacks. An empty name is the step's own problem.
static func event_problems(
	event: StringName, fields: Dictionary, events: Dictionary[StringName, PackedStringArray]
) -> PackedStringArray:
	var found := PackedStringArray()
	if event.is_empty():
		return found
	if not events.has(event):
		found.append("event %s is none a bot receives" % event)
		return found
	for key: Variant in fields:
		if not events[event].has(str(key)):
			found.append("event %s has no field %s" % [event, key])
	return found


## The problems of bot `bot`'s Join steps, each once (§9.7). Before its Welcome a bot runs only a
## Join, and a bot that left receives nothing: so a Join is its first step or the step directly
## after its own Leave (P12 (a) of the returning-players ADR), anything else would never be
## reached. A Join after a Leave tries again until its deadline_s (P12 (t2)), so that lies above
## its at_s; a first Join fails at its first refusal and has none. Bot 1, the host's own client,
## never joins again: its Leave ends the session it hosts.
func _join_problems(bot: int) -> PackedStringArray:
	var found := PackedStringArray()
	var steps := steps_of(bot)
	var misplaced := false
	for i in steps.size():
		var join := steps[i] as StepJoin
		if join == null:
			continue
		var returning := i > 0 and steps[i - 1] is StepLeave
		if i > 0 and not returning:
			misplaced = true
		elif returning and bot == 1:
			found.append("bot 1 is the host's own client: it does not join again after its Leave")
		elif returning and join.deadline_s <= join.at_s:
			found.append(
				(
					"bot %d: a Join after its Leave needs deadline_s above at_s (%s s)"
					% [bot, join.at_s]
				)
			)
		elif not returning and join.deadline_s != 0.0:
			found.append(
				"bot %d: a first Join has no deadline_s; only a Join after its Leave retries" % bot
			)
	if misplaced:
		found.append("bot %d: a Join is its first step or directly follows its own Leave" % bot)
	return found


## The set settings' problems: a set the mode does not declare, an id that is none of its task
## types, and then, as the lobby would refuse the setup's ChangeSettings, the numbers and the sets
## together by every row's actions (DealTasks: bans that leave fewer task types than `tasks`).
func _set_problems() -> PackedStringArray:
	var found := PackedStringArray()
	for id: StringName in id_sets:
		var spec := mode.find_setting(id)
		if spec == null or spec.is_number():
			found.append("set setting %s is not one of the mode's sets of task types" % id)
			continue
		for type_id: String in id_sets[id]:
			if mode.find_task_type(StringName(type_id)) == null:
				found.append("set setting %s names %s, not a task type of the mode" % [id, type_id])
	if not found.is_empty():
		return found
	var numbers := mode.default_settings()
	for id: StringName in settings:
		if numbers.has(id):
			numbers[id] = settings[id]
	var sets := mode.default_id_sets()
	sets.merge(id_sets, true)
	for row: Transition in mode.transitions:
		if row == null:
			continue
		for action: RuleEffect in row.actions:
			if action == null:
				continue
			var reason := action.settings_problem(numbers, sets, mode)
			if not reason.is_empty():
				found.append(
					"the lobby refuses the setup's settings and sets (%s)%s" % [reason, HINT]
				)
				return found
	return found
