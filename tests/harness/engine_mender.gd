class_name EngineMender
extends RefCounted
## What a MendEngine step's bot does next on the ship's engine (ARCHITECTURE §9.7, §9.5.27; #1498):
## a pure policy over what the bot was told (ScenarioBot: its ClientEngineBook, its stations, its
## position and hand) and the mode's problem kinds, the content a player's client has too. One per
## bot and step: it remembers its own presses only. ScenarioPlay._mend walks and sends what it
## picks, with the host tick its press would land on (ScenarioPlay._landing_tick).
##
## - Not started: the step's `start` bot walks to the console and presses it; the others wait there.
## - Its problems (id % `of` == `share`), the soonest deadline first; with a crystal in its hands,
##   that crystal's problem. A crystal charging needs nobody until it waits.
## - Gills: at the button, a press in the middle half of a bar step while the bar is on a shut slit,
##   once a step (a press on an open slit would shut it again).
## - Breakers: at the next breaker of the chain, the first at once, any other inside its green
##   window less a margin each side (too early or too late a press knocks the presser down).
## - Crystal: pull it at its socket, load it into a free charger (the problem's own by id when
##   free), press the charger, take it once it waits, fit it at its socket.
## - Below a station's floor (the ground under the ship's deck) it walks the step's `boarding`
##   points in order first.

enum Act { WAIT, WALK, PRESS }

## How near (horizontally) a bot walks to a station to press it: well inside its 2 m cylinder.
const REACH_M := 1.0
## A station this much higher than the bot is on the deck above it: board first.
const BELOW_M := 0.1
## A boarding point counts as reached within this much (WalkTo's stop distance is 0 there).
const BOARDED_M := 0.05
## The ticks a bot waits for its press's answer before it presses the same station again (a
## breaker already on refuses a second press `unavailable`; a gill press is once a bar step).
const SETTLE_TICKS := 10
## The ticks kept clear at each end of a breaker's green window, against the bot's estimate of
## the host tick (exact in the core runner, within a tick or two over the network).
const GREEN_MARGIN_TICKS := 6


## A move: WAIT; WALK to `to`; PRESS `station` (an Interact).
class Move:
	extends RefCounted
	var act := Act.WAIT
	var station := -1
	var to := Vector3.ZERO

	func _init(what: Act, station_id: int = -1, at: Vector3 = Vector3.ZERO) -> void:
		act = what
		station = station_id
		to = at


var step: StepMendEngine
var gills: GillsProblem
var breakers: BreakersProblem
var crystal: CrystalProblem

## The next `boarding` point to walk to while the bot is below its target.
var _boarded := 0
## Station -> the tick its last press was to land on.
var _pressed: Dictionary[int, int] = {}
## Gill problem id -> the bar step it was last pressed in.
var _gill_step: Dictionary[int, int] = {}
## Crystal problem ids whose crystal waited charged in a charger: the next use is its fit.
var _charged: Dictionary[int, bool] = {}


## `kinds`: the ship engine's problem kinds (ShipEngine.kinds), one of each class it mends.
func _init(mend: StepMendEngine, kinds: Array[ProblemKind]) -> void:
	step = mend
	for kind: ProblemKind in kinds:
		if kind is GillsProblem:
			gills = kind as GillsProblem
		elif kind is BreakersProblem:
			breakers = kind as BreakersProblem
		elif kind is CrystalProblem:
			crystal = kind as CrystalProblem


## The bot's next move, its press landing on host tick `tick`.
func decide(bot: ScenarioBot, tick: int) -> Move:
	var console := _console(bot)
	if bot.downed or bot.dead or bot.engine_done or console < 0:
		return Move.new(Act.WAIT)
	if not bot.engine_started:
		return _press(bot, console, tick) if step.start else _go(bot, bot.stations[console])
	var id := pick(bot)
	if id < 0:
		return _go(bot, bot.stations[console])
	return _mend(bot, id, tick)


func _mend(bot: ScenarioBot, id: int, tick: int) -> Move:
	var problem: ClientEngineBook.Problem = bot.engine.problems[id]
	var kind := _kind_of(bot, problem)
	if kind == gills:
		return _mend_gills(bot, id, problem, tick)
	if kind == breakers:
		return _mend_breakers(bot, problem, tick)
	return _mend_crystal(bot, id, problem, tick)


## The id of the problem the bot works on, or -1: with a crystal in its hands that crystal's,
## else its share's open problem with the soonest deadline that needs a hand now.
func pick(bot: ScenarioBot) -> int:
	var found := -1
	var soonest := 0
	for id: int in bot.engine.problems:
		if id % step.of != step.share:
			continue
		var problem: ClientEngineBook.Problem = bot.engine.problems[id]
		var kind := _kind_of(bot, problem)
		if kind == null:
			continue
		if kind == crystal:
			if _carries(bot, problem):
				return id
			var out := _crystal_at(bot, problem)
			if out != null and out.charger >= 0 and out.phase == CrystalProblem.CHARGING:
				continue
		if bot.held >= 0:
			continue
		if found < 0 or problem.deadline < soonest:
			found = id
			soonest = problem.deadline
	return found


## Forgets the press of `station`: its Interact was refused, so a later one may follow at once.
func refused(station: int) -> void:
	_pressed.erase(station)


func _mend_gills(bot: ScenarioBot, id: int, problem: ClientEngineBook.Problem, tick: int) -> Move:
	var button := problem.stations[0]
	if not _near(bot, button):
		return _go(bot, bot.stations[button])
	var since := tick - ClientEngineBook.opened_tick(problem, gills)
	if since < 0:
		return Move.new(Act.WAIT)
	var step_ticks := gills.step_ticks()
	@warning_ignore("integer_division")
	var bar_step := since / step_ticks
	var into := since % step_ticks
	var slit := GillsProblem.BAR[bar_step % GillsProblem.BAR.size()]
	var slits: int = bot.engine.slits.get(button, 0)
	var open := (slits & (1 << slit)) != 0
	@warning_ignore("integer_division")
	var middle := into >= step_ticks / 4 and into <= step_ticks * 3 / 4
	if open or not middle or _gill_step.get(id, -1) == bar_step:
		return Move.new(Act.WAIT)
	_gill_step[id] = bar_step
	_pressed[button] = tick
	return Move.new(Act.PRESS, button)


func _mend_breakers(bot: ScenarioBot, problem: ClientEngineBook.Problem, tick: int) -> Move:
	if problem.breakers.is_empty() or problem.next >= problem.breakers.size():
		return _go(bot, bot.stations[problem.stations[0]])
	var breaker := problem.breakers[problem.next]
	if not _near(bot, breaker):
		return _go(bot, bot.stations[breaker])
	if problem.next > 0:
		var since := tick - problem.since
		var earliest := breakers.ramp_ticks() + GREEN_MARGIN_TICKS
		var latest := breakers.ramp_ticks() + breakers.green_ticks() - GREEN_MARGIN_TICKS
		if since < earliest or since > latest:
			return Move.new(Act.WAIT)
	return _press(bot, breaker, tick)


func _mend_crystal(bot: ScenarioBot, id: int, problem: ClientEngineBook.Problem, tick: int) -> Move:
	var socket := problem.stations[0]
	var out := _crystal_at(bot, problem)
	if out != null and out.charger >= 0:
		if out.phase == CrystalProblem.WAITING:
			_charged[id] = true
		# Loaded: press it; waiting: take it out (charging: pick() left it).
		return _press(bot, out.charger, tick)
	if not _carries(bot, problem):
		if (bot.crystal_items.get(socket, -1) as int) < 0:
			return _press(bot, socket, tick)  # The pull.
		return Move.new(Act.WAIT)  # Out, in nobody's hands it knows: nothing to do.
	if _charged.has(id):
		return _press(bot, socket, tick)  # The fit.
	var charger := _free_charger(bot, id)
	if charger < 0:
		return Move.new(Act.WAIT)
	return _press(bot, charger, tick)  # The load.


## Whether the bot holds the problem's crystal.
static func _carries(bot: ScenarioBot, problem: ClientEngineBook.Problem) -> bool:
	var item: int = bot.crystal_items.get(problem.stations[0], -1)
	return item >= 0 and bot.held == item


## A charger holding no crystal: the problem's own (by id over the chargers) when free, else the
## nearest free one; -1 when none is free.
func _free_charger(bot: ScenarioBot, id: int) -> int:
	var chargers: Array[int] = []
	var charger_kind := crystal.fixtures[0].id if not crystal.fixtures.is_empty() else &""
	for station: int in bot.station_kinds:
		if bot.station_kinds[station] == charger_kind:
			chargers.append(station)
	chargers.sort()
	if chargers.is_empty():
		return -1
	var busy: Array[int] = []
	for socket: int in bot.engine.crystals:
		var held: ClientEngineBook.Crystal = bot.engine.crystals[socket]
		if held.charger >= 0:
			busy.append(held.charger)
	var own := chargers[id % chargers.size()]
	if not busy.has(own):
		return own
	var found := -1
	for charger: int in chargers:
		if busy.has(charger):
			continue
		if found < 0 or _distance(bot, charger) < _distance(bot, found):
			found = charger
	return found


## Walks to `station` and presses it once there, unless a press of it is still unanswered.
func _press(bot: ScenarioBot, station: int, tick: int) -> Move:
	if not _near(bot, station):
		return _go(bot, bot.stations[station])
	if tick - (_pressed.get(station, -SETTLE_TICKS) as int) < SETTLE_TICKS:
		return Move.new(Act.WAIT)
	_pressed[station] = tick
	return Move.new(Act.PRESS, station)


## Walks towards `at` (over the boarding points while below it), or waits there.
func _go(bot: ScenarioBot, at: Vector3) -> Move:
	if bot.position.y < at.y - BELOW_M and _boarded < step.boarding.size():
		var point := step.boarding[_boarded]
		if _flat_distance(bot.position, point) > BOARDED_M:
			return Move.new(Act.WALK, -1, point)
		_boarded += 1
		if _boarded < step.boarding.size():
			return Move.new(Act.WALK, -1, step.boarding[_boarded])
	if bot.position.y >= at.y - BELOW_M:
		_boarded = 0
	if _flat_distance(bot.position, at) <= REACH_M:
		return Move.new(Act.WAIT)
	return Move.new(Act.WALK, -1, at)


func _near(bot: ScenarioBot, station: int) -> bool:
	var at: Vector3 = bot.stations[station]
	return at.y - bot.position.y <= BELOW_M and _flat_distance(bot.position, at) <= REACH_M


func _distance(bot: ScenarioBot, station: int) -> float:
	return _flat_distance(bot.position, bot.stations[station])


func _console(bot: ScenarioBot) -> int:
	for station: int in bot.station_kinds:
		if bot.station_kinds[station] == ScenarioBot.engine_console():
			return station
	return -1


## The kind whose site the problem's first station is, or null.
func _kind_of(bot: ScenarioBot, problem: ClientEngineBook.Problem) -> ProblemKind:
	var site: StringName = bot.station_kinds.get(problem.stations[0], &"")
	for kind: ProblemKind in [gills, breakers, crystal]:
		if kind != null and kind.site != null and kind.site.id == site:
			return kind
	return null


static func _crystal_at(
	bot: ScenarioBot, problem: ClientEngineBook.Problem
) -> ClientEngineBook.Crystal:
	return bot.engine.crystals.get(problem.stations[0])


static func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()
