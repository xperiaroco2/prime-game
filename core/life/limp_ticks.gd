class_name LimpTicks
extends TickSystem
## The limp's push and its get-up (#1393; GDD §3 Base mode, "The bar"; ARCHITECTURE §7.1.21,
## §9.4.5), every tick of the phase that lists it (the base mode's Lobby and Countdown), each limp
## player in ascending peer order:
## - at LimpState.until it stands up where its body lies (LifeRules.get_up: a moving body rests
##   first, StopBody; a new epoch and its Correction). Its drunk value stays (DrunkTicks lowers it).
## - else, once `cooldown_s` has passed since its last push, the players walking into it push it:
##   a pusher is living and not limp, its last accepted point within `reach_m` of the body's
##   (horizontal) and `height_m` (vertical), its claimed horizontal speed at least `min_speed_mps`
##   and toward the body. Each adds the direction from its point to the body's times its speed
##   (at most PlayerRules.sprint_speed_mps) times `gain`; the sum, on top of the body's horizontal
##   velocity, is held to `max_speed_mps`, its vertical velocity kept: LifeRules.push_limp
##   (LaunchBody with the new velocity, the same epoch). No intent carries a push: it comes from
##   the host's accepted points alone, so nobody pushes from out of reach (invariants 1, 7).
## Every number is provisional, "not a decision" (the engineer tunes them).
##
## Emits: StopBody (server), Correction (the player), LaunchBody (server). No demands.

## How near a pusher's point is to the body's, horizontally, in metres.
@export var reach_m := 0.0
## How far apart the two points may be vertically, in metres.
@export var height_m := 0.0
## The slowest claimed horizontal speed that pushes, in metres per second.
@export var min_speed_mps := 0.0
## The push's share of the pusher's speed.
@export var gain := 0.0
## The fastest a push leaves the body, horizontally, in metres per second.
@export var max_speed_mps := 0.0
## The shortest time between two pushes of one body, in seconds.
@export var cooldown_s := 0.0


func run(ctx: MatchContext) -> void:
	var rules := ctx.state.player_rules
	if rules == null:
		return
	for peer: int in ctx.state.peers():
		var body := ctx.state.players[peer]
		if not body.is_limp():
			continue
		if ctx.tick >= body.limp.until:
			LifeRules.get_up(ctx, peer)
			continue
		var pushed := body.limp.push_tick
		if pushed >= 0 and ctx.tick < pushed + maxi(1, Ticks.from_seconds(cooldown_s)):
			continue
		var shove := push_of(ctx.state, body, rules)
		if shove == Vector3.ZERO:
			continue
		var flat := Vector3(body.velocity.x, 0.0, body.velocity.z) + shove
		flat = flat.limit_length(max_speed_mps)
		LifeRules.push_limp(ctx, peer, Vector3(flat.x, body.velocity.y, flat.z))


## The horizontal velocity the pushers of `body` add to it now (ZERO for none), in peer order.
func push_of(state: MatchState, body: PlayerState, rules: PlayerRules) -> Vector3:
	var total := Vector3.ZERO
	for peer: int in state.peers():
		var pusher := state.players[peer]
		if peer == body.peer or not pusher.is_alive() or pusher.is_limp():
			continue
		var gap := body.position - pusher.position
		if not gap.is_finite() or absf(gap.y) > height_m:
			continue
		var flat := Vector3(gap.x, 0.0, gap.z)
		var distance := flat.length()
		if distance > reach_m or is_zero_approx(distance):
			continue
		var walk := Vector3(pusher.velocity.x, 0.0, pusher.velocity.z)
		var speed := walk.length()
		if not is_finite(speed) or speed < min_speed_mps:
			continue
		var toward := flat / distance
		if walk.dot(toward) <= 0.0:
			continue
		total += toward * minf(speed, rules.sprint_speed_mps) * gain
	return total


func emits() -> Array[Script]:
	return [StopBodyEvent, CorrectionEvent, LaunchBodyEvent]


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(
		found,
		[
			out_of_bounds("reach_m", reach_m, 0.5, 3),
			out_of_bounds("height_m", height_m, 0.5, 3),
			out_of_bounds("min_speed_mps", min_speed_mps, 0, 8),
			out_of_bounds("gain", gain, 0.1, 5),
			out_of_bounds("max_speed_mps", max_speed_mps, 0.5, 8),
			out_of_bounds("cooldown_s", cooldown_s, 0.05, 5),
		]
	)
	return found


## The problems of `mode`'s limp (GoLimp.check): a phase lists LimpTicks, every phase that does
## lists a LifeTicks too (it bounds the body's motion), and every row from such a phase into one
## without runs an EndLimps, so nobody is limp where nothing gets them up. Empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var any := false
	for phase: PhaseSpec in mode.phases:
		if phase == null or not _lists(phase, "LimpTicks"):
			continue
		any = true
		if not _lists(phase, "LifeTicks"):
			found.append("phase %s lists a LimpTicks and no LifeTicks" % phase.id)
	if not any:
		found.append("GoLimp: no phase lists a LimpTicks, so nobody limp would get up")
	for row: Transition in mode.transitions:
		if row == null:
			continue
		var from := mode.find_phase(row.from)
		var to := mode.find_phase(row.to)
		if from == null or to == null or not _lists(from, "LimpTicks") or _lists(to, "LimpTicks"):
			continue
		var ends := false
		for action: RuleEffect in row.actions:
			ends = ends or action is EndLimps
		if not ends:
			found.append(
				"row %s -> %s runs no EndLimps: a limp would outlast it" % [row.from, row.to]
			)
	return found


static func _lists(phase: PhaseSpec, kind: String) -> bool:
	for system: TickSystem in phase.tick_systems:
		if kind == "LimpTicks" and system is LimpTicks:
			return true
		if kind == "LifeTicks" and system is LifeTicks:
			return true
	return false
