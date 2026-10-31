class_name StubProblemKind
extends ProblemKind
## A ship engine problem kind for the unit tests (ARCHITECTURE §9.6; #1453): a use of a site with
## an open problem fixes it at once; `spans` sites per problem (the first `spans` of the free ones,
## or the default draw of one); the hooks it gets are written down in `calls` as "<hook> <problem
## id>", so a test sees the engine call the interface. `calls` is test bookkeeping, not match
## state: a fresh stub per match.

## How many sites one problem takes: 1 draws one (ProblemKind's default), more take the first ones.
var spans := 1
## The hooks called, in order.
var calls: Array[String] = []


func claim(
	ctx: MatchContext,
	task: MatchTask,
	free: PackedInt32Array,
	stage: int,
	rng: RandomNumberGenerator
) -> PackedInt32Array:
	if spans <= 1:
		return super(ctx, task, free, stage, rng)
	return free.slice(0, spans)


func opened(_ctx: MatchContext, _task: MatchTask, problem: EngineProblem) -> void:
	calls.append("opened %d" % problem.id)
	problem.data = "stub"


func cleared(_ctx: MatchContext, _task: MatchTask, problem: EngineProblem) -> void:
	calls.append("cleared %d" % problem.id)


func use_station(
	ctx: MatchContext, task: MatchTask, _station: StationState, problem: EngineProblem
) -> void:
	if problem != null:
		ShipEngine.fix(ctx, task, problem)
