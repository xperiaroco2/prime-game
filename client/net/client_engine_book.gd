class_name ClientEngineBook
extends RefCounted
## The ship's engine as the own client knows it (#1462; ARCHITECTURE §9.5.27, "For part 3's
## client"), folded from its public events alone: ClientModel.fold hands it every event and it keeps
## the engine's. The console's bar is the console station's ZoneProgress (ClientModel.Station), the
## stage count its TaskState; the rest is here. Nothing names a player or a kind, and nothing is
## predicted: a view derives the countdowns, the gills' white bar and the breakers' lamps from these
## and its own copy of the mode.


## One open problem: EngineProblemOpened until EngineProblemFixed of its id or an EngineBlast. Its
## stations, the host tick it blows on and, for the tripped breakers, the problem's last
## BreakerChain: the tripped breaker stations in their order, how many are on and the host tick
## the last one's window is measured from (-1 while none is on).
class Problem:
	extends RefCounted
	var stations := PackedInt32Array()
	var deadline := -1
	var breakers := PackedInt32Array()
	var next := 0
	var since := -1


## A socket's crystal as its last CrystalChanged told it: the charger holding it (-1 none), that
## charger's phase (CrystalProblem's EMPTY, LOADED, CHARGING or WAITING) and the host tick a charge
## ends on (-1 when not charging), and its item while it is out of the socket (-1 while the socket
## holds it: a view tells a pulled crystal from a spent one by it, #1550).
class Crystal:
	extends RefCounted
	var charger := -1
	var phase := 0
	var tick := -1
	var item := -1


## The open problems by id.
var problems: Dictionary[int, Problem] = {}
## The blasts so far and the stage the last one dropped the engine to (0 before the first): a
## view tells a new blast by the count.
var blasts := 0
var stage := 0
## Each gill set's open slits by its button's station, a bit per slit (bit 0 the mouth side), as
## the GillFlipped events since its problem opened told it: all shut at each EngineProblemOpened
## that names the station.
var slits: Dictionary[int, int] = {}
## Each socket's crystal by the socket's station.
var crystals: Dictionary[int, Crystal] = {}


## Folds `event_name` if it is one of the engine's; every other event is left alone.
func fold(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		&"EngineProblemOpened":
			var problem := Problem.new()
			var at: PackedInt32Array = fields["stations"]
			problem.stations = at.duplicate()
			problem.deadline = fields["deadline"]
			problems[fields["problem"] as int] = problem
			for id: int in problem.stations:
				slits.erase(id)
		&"EngineProblemFixed":
			problems.erase(fields["problem"] as int)
		&"EngineBlast":
			problems.clear()
			blasts += 1
			stage = fields["stage"]
		&"BreakerChain":
			var chained: Problem = problems.get(fields["problem"] as int)
			if chained == null:
				return
			var order: PackedInt32Array = fields["breakers"]
			chained.breakers = order.duplicate()
			chained.next = fields["next"]
			chained.since = fields["since"]
		&"GillFlipped":
			var bit := 1 << (fields["slit"] as int)
			var station: int = fields["station"]
			var now_open: bool = fields["open"]
			var open: int = slits.get(station, 0)
			slits[station] = (open | bit) if now_open else (open & ~bit)
		&"CrystalChanged":
			var crystal := Crystal.new()
			crystal.charger = fields["charger"]
			crystal.phase = fields["phase"]
			crystal.tick = fields["tick"]
			crystal.item = fields["item"]
			crystals[fields["station"] as int] = crystal


## The open problem holding `station`, or null.
func problem_at(station: int) -> Problem:
	for problem: Problem in problems.values():
		if problem.stations.has(station):
			return problem
	return null


## The host tick the problem opened on: its deadline less its kind's timer, as the host set it
## (ShipEngine: at least one tick).
static func opened_tick(problem: Problem, kind: ProblemKind) -> int:
	return problem.deadline - maxi(1, Ticks.from_seconds(kind.seconds))
