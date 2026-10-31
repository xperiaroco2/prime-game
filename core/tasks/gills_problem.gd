class_name GillsProblem
extends ProblemKind
## The ship engine's overheat (ARCHITECTURE §9.3, §9.5.27; GDD §8 "Overheat", as PR #1429 wrote it):
## a problem on one of the throat's two gill sets, its site the set's round button. It opens with
## all five slits shut (red); one white bar then runs over the five, 1-2-3-4-5-4-3-2 and round
## again, one step every `step_seconds`, from the problem's opening tick (the bar is a pure function
## of the host tick: bar_slit()). A press of the button flips the slit under the bar at the tick
## the host applies it: a shut one opens, an open one shuts again (GDD: "too fast on the last one:
## shut again, and round once more"); GillFlipped to everyone. All five open: fixed.
##
## Timing under latency (#1461, technical): the host judges the slit at the tick it applies the
## Interact, which carries no client tick. Part 3's client draws the bar from the problem's opening
## tick (EngineProblemOpened's `deadline` less the kind's `seconds` in ticks) at its estimate of the
## host tick its press would land on, so what a player aims at is what the host judges.

## The slits of a gill set (GDD §8: five crescent slits).
const SLITS := 5
## The white bar's slits, step by step, round and round (GDD §8: 1-2-3-4-5-4-3-2).
const BAR: Array[int] = [0, 1, 2, 3, 4, 3, 2, 1]
## The bounds of `step_seconds`.
const MIN_STEP_SECONDS := 0.05
const MAX_STEP_SECONDS := 10.0
## Every slit open.
const ALL_OPEN := (1 << SLITS) - 1

## One step of the white bar (GDD §8's placeholder: 0.6 s), converted once to host ticks, at least
## 1. The neutral default is out of bounds on purpose: the data sets it.
@export var step_seconds := 0.0


## A gill problem's own state (EngineProblem.data).
class Data:
	extends RefCounted
	## The open slits, bit i for slit i (0, the mouth side, to 4).
	var open := 0


## One step of the bar in host ticks, at least 1.
func step_ticks() -> int:
	return maxi(1, Ticks.from_seconds(step_seconds))


## The slit under the white bar of `problem` at host tick `tick` (0 to 4).
func bar_slit(problem: EngineProblem, tick: int) -> int:
	var steps := maxi(0, tick - problem.opened) / step_ticks()
	return BAR[steps % BAR.size()]


## Whether `slit` of `problem` is open.
static func is_open(problem: EngineProblem, slit: int) -> bool:
	return ((problem.data as Data).open & (1 << slit)) != 0


func opened(_ctx: MatchContext, _task: MatchTask, problem: EngineProblem) -> void:
	problem.data = Data.new()


func use_station(
	ctx: MatchContext, task: MatchTask, station: StationState, problem: EngineProblem
) -> void:
	if problem == null:
		return  # use_problem refused it.
	var data := problem.data as Data
	var slit := bar_slit(problem, ctx.tick)
	data.open ^= 1 << slit
	ctx.emit(GillFlippedEvent.new(station.id, slit, is_open(problem, slit)))
	if data.open == ALL_OPEN:
		ShipEngine.fix(ctx, task, problem)


func use_emits() -> Array[Script]:
	return [GillFlippedEvent]


## ProblemKind's check; `step_seconds` within bounds.
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	append_found(
		found,
		[
			out_of_bounds(
				"problem kind %s step_seconds" % id,
				step_seconds,
				MIN_STEP_SECONDS,
				MAX_STEP_SECONDS
			)
		]
	)
	return found
