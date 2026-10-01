class_name MovementRule
extends RefCounted
## Where every accepted MoveClaim goes (ARCHITECTURE §7, §7.1, §9.2). A claim of an older epoch is
## dropped as stale, and so is one whose client tick does not rise. Every other claim is checked,
## and a claim that fails a check changes nothing but the epoch: its player gets a Correction with
## a new epoch and the host's position (that player only), so the claims still in flight are
## dropped and one correction does not cascade. A claim that passes becomes the player's last
## accepted position, which every range rule reads.
##
## `client_tick` counts 20 Hz core ticks (Ticks.RATE) of the client's own clock, not its physics
## frames (60 Hz by default): the speed and rate checks give one core tick of travel and credit per
## client tick, so a client sending its physics frame count would run out of credit at once.
##
## The checks, in order:
## - Well formed: an int client tick, finite position, velocity and facing (NaN or inf fail), and
##   an int jump count within the wire's u16 (0 to MAX_JUMPS).
##   A negative client tick is dropped when below the baseline, like any tick that does not rise,
##   and corrected when there is none: a negative claim_tick means "no baseline yet".
## - The client tick rises at a bounded rate: a player earns one tick of credit per host tick, keeps
##   at most MAX_TICK_CREDIT of it (so a catch-up burst after a stall passes, #70), and a claim
##   may cover no more client ticks than its credit. So the speed check below can trust the
##   client's own tick delta, and no claim teleports by inflating it. A claim past its credit is
##   corrected and the next one starts a new client-tick baseline, so a client whose ticks ran
##   ahead of the host's (the host stalled and lost ticks) is corrected once and goes on.
## - Jumps (`jumps`, E2): the client's count of jumps since it adopted the epoch (0 after Welcome,
##   a placement or a Correction), which survives the LATEST lane's merge of claims (§4.3). A count
##   below the last accepted claim's in the epoch is corrected, and so is a rise d above the client
##   ticks the claim covers (but for a fresh claim, the first of a client-tick baseline, whose span
##   is unknown): a client lands between two jumps (#117 item 6). A rise d >= 1 is one
##   jump: WorldQuery finds a floor within step height (+ STEP_CLEARANCE, a ledge crossing) below
##   the player's last accepted position and stamina covers d times the jump's cost, settled first:
##   the claim's own ticks with its own flags, then any later ones (settle_ahead). A merged burst
##   of d jumps pays for each but grants one jump height, because the merged claims' take-offs
##   are lost (accepted in the ADR). A downed player crawls and never jumps: any new jump of
##   theirs is corrected. The last claim need not say it was on the floor: claims go at 20 Hz
##   and the client's physics at 60 Hz, so a landing and a jump can fall in one claim. The
##   take-off is the higher of that floor and the last feet, so the peak stays bounded.
## - Horizontal speed over the client's tick delta: per covered tick the state's speed (for the
##   living sprint in the sprint state with movement input, else walk; for the downed the crawl
##   speed, with no sprint), plus, for the living only, sprint speed for being pushed (§7.1
##   "Pushing apart", proposed for M4) for at most PUSH_TICKS covered ticks, while another living
##   player's last accepted position is within push_reach() of the claim's path, plus a tick of
##   sprinting per host tick its claims were lost (the downed push nobody and nobody pushes them),
##   plus DISTANCE_SLACK_M. After a claim that sprinted by its own input, one covered tick more
##   may go at sprint speed: the sprint's last tick, which the claim's flags may no longer show.
##   The crawl's slack is CRAWL_SLACK_FRACTION of its own travel (+ the float slack) instead: a
##   fixed slack per claim would let a client sending one-tick claims crawl at twice the speed.
##   The host never checks or corrects overlap between players.
## - Height: until the next landing (a claim on the floor with a WorldQuery floor within step
##   height), the feet stay within the jump height (+ JUMP_SLACK) of the take-off after an
##   accepted jump, else within step height (+ STEP_CLEARANCE, + the horizontal travel times
##   tan(FLOOR_MAX_ANGLE) for a slope or a staircase) of the last landing's floor: the higher of
##   the floor WorldQuery found and the claim's feet less landing_slack(), since on stairs whose
##   treads are narrower than the capsule the rays may miss the step it rests on. The slope
##   allowance counts the travel of at most SLOPE_TICKS covered ticks: stored credit buys no more
##   climb than that. Falling is not bounded, and walls are not checked (§7.1).
##   A downed player is bounded the same way: with no jump, its rise is the step height (plus the
##   slope allowance) above its last landing.
## - Held in place (M4-4): while a raise runs on a downed player (Channels.holding), a claim
##   farther than HOLD_SLACK_M from where the raise started is corrected (the engineer's answer 8
##   on PR #133), so a raise restarted again and again cannot carry a downed player along.
## Then the claim settles its covered ticks of stamina (StaminaLedger), an accepted jump pays its
## cost, and the player's SelfStatus is touched (sent at the end of the tick).
##
## The facing is a claim relayed to everyone in the snapshots (the M4 ADR §3, Host trust), and an
## honest one can be degenerate (a bot falling straight down claims (0, -1, 0)): the accepted
## facing is stored as a unit vector (stored_facing), the last one kept when the claim's has no
## direction, its pitch clamped to MAX_PITCH_DEG.
##
## Every tolerance below is a placeholder, "not a decision", except where it copies the client.

## The client's `PlayerController.STEP_CLEARANCE`: it crosses a ledge's edge this far above the
## top, so a rise without a jump reaches step height plus this (ARCHITECTURE §7, #46).
const STEP_CLEARANCE := 0.01
## Godot's default `CharacterBody3D.floor_max_angle` (45°), which the client keeps: the steepest
## walkable slope.
const FLOOR_MAX_ANGLE := PI / 4.0
## Extra horizontal distance a claim may travel beyond its speed, for rounding.
const DISTANCE_SLACK_M := 0.05
## The crawl's slack, a fraction of the crawl's own travel: DISTANCE_SLACK_M is as long as a whole
## tick of the crawl, so a client sending a claim every tick would crawl at twice the speed.
const CRAWL_SLACK_FRACTION := 0.1
## Extra height a claim may reach beyond its bound: positions are 32-bit floats.
const HEIGHT_SLACK_M := 0.001
## WorldQuery looks for the floor from this far above the feet, so feet resting on it find it.
const FLOOR_PROBE_M := 0.1
## How far a claim of a player held in place (a raise) may be from where the raise started
## (Channel.held_at). Not for the wire: positions travel as 32-bit floats, as Vector3 holds them in
## this build, so a claim of where the host put the player matches it exactly. A margin for the
## client's physics settling the held capsule by a hair; it cannot add up, being measured from the
## one start point.
const HOLD_SLACK_M := 0.001
## Horizontal travel in one claim that counts as moving, for stamina (the client's MOVE_EPSILON).
const MOVE_EPSILON := 0.0001
## Client ticks a player may claim ahead of the host's ticks: the credit after a placement.
const TICK_LEAD := 10
## The most host ticks of credit a player keeps: 10 s, above #70's 5 s catch-up burst.
const MAX_TICK_CREDIT := 200
## Its key in MatchState's per-part state (§9.1): the per-player records below.
const PART_KEY := &"movement"
## The steepest stored facing, up or down: a facing straight up or down has no yaw for a head or
## a camera built from it (the M4 ADR §3).
const MAX_PITCH_DEG := 89.0
## The highest jump count a claim may carry: the wire's `jumps: u16` (§4.3). Core checks it itself
## (invariant 1), so a count that skipped the codec cannot overflow the stamina cost.
const MAX_JUMPS := 0xFFFF
## The push allowance's reach (#76): a living player is granted it only while another living
## player's last accepted position lies within PUSH_REACH_RADII capsule radii (two capsules
## touching) plus PUSH_LAG_S of sprinting of the claim's path. The lag: the pushed client moves
## away from the pusher where it draws it, SnapshotBuffer's delay (about 0.1 s) plus a round trip
## behind the pusher's position on the host. With two radii alone, an honest head-on push over the
## loopback (#143's network push test) was corrected: the players were 0.86 m apart on the host.
const PUSH_REACH_RADII := 2.0
const PUSH_LAG_S := 0.2
## The most covered ticks whose travel the slope allowance counts (#76): 0.5 s, so an honest climb
## whose claims were lost for up to nine ticks in a row passes, and a claim covering stored credit
## (up to MAX_TICK_CREDIT ticks) rises no higher than SLOPE_TICKS ticks of its travel would take
## it. Accepted: a 45° climb through a stall of more than about half a second is corrected once.
const SLOPE_TICKS := 10
## The most covered ticks the push allowance counts (#76), for the same reason: a client that kept
## quiet for MAX_TICK_CREDIT ticks would otherwise travel 200 ticks of walk plus push (115 m) in
## one claim whose path passes near anyone. Accepted: an honest player pushed through a stall of
## more than about half a second is corrected once.
const PUSH_TICKS := 10


## What the checks remember of one player between claims.
class Motion:
	extends RefCounted
	## The player's epoch this record last saw; another one means a placement since.
	var epoch := -1
	## Client ticks the player may still claim.
	var credit := 0
	## The host tick up to which the credit was earned.
	var credit_tick := 0
	## The height the feet are bounded from: the last landing's floor, or the take-off.
	var base_y := 0.0
	## An accepted jump, until the next landing.
	var jumping := false
	## A claim covered more client ticks than its credit: the next claim restarts the client-tick
	## baseline, so a client whose ticks ran ahead of the host's is corrected once, not forever.
	var rebase := false
	## The jump count of the last accepted claim in this epoch.
	var jumps := 0
	## The host tick of the last accepted claim or placement: how stale the position is that
	## another player's push allowance measures from (_near_living_player).
	var accepted_tick := -1


## One MoveClaim's fields, read and checked for type and finiteness.
class Claim:
	extends RefCounted
	var client_tick := 0
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var facing := Vector3.FORWARD
	var sprint := false
	## The player gave movement input.
	var moving := false
	## The client's jump count in the epoch (E2).
	var jumps := 0
	var on_floor := false


## What the checks found, for accepting the claim.
class Checked:
	extends RefCounted
	var covered := 0
	## Jumps the claim adds to the last accepted count: 0, or d >= 1 for one jump allowance.
	var new_jumps := 0
	var take_off_y := 0.0
	## Horizontal metres from the last accepted position.
	var travel := 0.0
	## The claim gave movement input and moved horizontally: what sprint stamina counts.
	var moved_itself := false
	var settled: StaminaLedger.Settlement


## All the records.
class MotionTable:
	extends RefCounted
	var by_peer: Dictionary[int, Motion] = {}


func apply(ctx: MatchContext, command: MatchCommand) -> void:
	var player := ctx.state.player(command.peer)
	if player == null or command.get_int("epoch", -1) != player.epoch:
		return
	var motion := _motion(ctx.state, player.peer)
	if motion.epoch != player.epoch:
		_after_placement(motion, player, ctx.state.player_rules, ctx.tick)
	SelfStatusFeed.touch(ctx.state, player.peer)
	var claim := _read(command)
	if claim == null:
		_correct(ctx, player, motion)
		return
	var fresh := player.claim_tick < 0 or motion.rebase
	var covered := 1 if fresh else claim.client_tick - player.claim_tick
	if covered <= 0:
		return
	if claim.client_tick < 0:
		_correct(ctx, player, motion)
		return
	motion.credit = mini(MAX_TICK_CREDIT, motion.credit + ctx.tick - motion.credit_tick)
	motion.credit_tick = ctx.tick
	if covered > motion.credit:
		# The ticks it claims past its credit are lost, not owed: the next claim starts a new
		# baseline (and the credit is not refilled, so this buys no distance). Stamina is settled
		# up to now meanwhile, as after a placement.
		motion.rebase = true
		StaminaLedger.settle_ahead(player, ctx.state.player_rules, ctx.tick)
		_correct(ctx, player, motion)
		return
	var checked := _check(ctx, player, motion, claim, covered, fresh)
	if checked == null:
		_correct(ctx, player, motion)
		return
	_accept(ctx, player, motion, claim, checked)


## Runs the checks after the tick rate's; null when one fails. May settle stamina up to now, which
## applies only ticks that have passed (§9.2). `fresh`: the claim starts a client-tick baseline,
## so `covered` is 1 whatever span of client ticks it really covers.
static func _check(
	ctx: MatchContext, player: PlayerState, motion: Motion, claim: Claim, covered: int, fresh: bool
) -> Checked:
	var rules := ctx.state.player_rules
	var checked := Checked.new()
	checked.covered = covered
	checked.travel = (
		Vector2(claim.position.x - player.position.x, claim.position.z - player.position.z).length()
	)
	checked.moved_itself = claim.moving and checked.travel > MOVE_EPSILON
	if held_against(ctx.state, player, claim.position):
		return null
	# Read before a jump commits this claim's settlement.
	var sprint_tail := player.sprinting and player.moving
	checked.settled = StaminaLedger.simulate(
		player, rules, ctx.tick, claim.sprint, checked.moved_itself, covered
	)
	checked.new_jumps = claim.jumps - motion.jumps
	if checked.new_jumps < 0:
		# A count that falls within an epoch is no honest client's.
		return null
	if checked.new_jumps > covered and not fresh:
		# A client lands between two jumps, so no honest claim adds more jumps than it covers
		# client ticks (#117 item 6): a merged burst of d jumps covers at least d ticks. A fresh
		# claim's span is unknown; the stamina check and the one jump height still bound it.
		return null
	var jumped := checked.new_jumps > 0
	if jumped and player.life == PlayerState.Life.DOWNED:
		# The downed crawl: no jump.
		return null
	if jumped:
		# The claim's own ticks are settled with its own flags, so a sprint before the jump is paid;
		# then any ticks up to now with the last claim's (settle_ahead), before the cost is checked.
		StaminaLedger.commit(player, checked.settled)
		StaminaLedger.settle_ahead(player, rules, ctx.tick)
		var take_off := _floor_under(ctx.world, player.position, rules)
		if take_off == WorldQuery.NO_FLOOR:
			return null
		if not StaminaLedger.covers(player, _jumps_cost(rules, checked.new_jumps)):
			return null
		checked.take_off_y = maxf(take_off.y, player.position.y)
	var pushed := (
		player.is_alive() and _near_living_player(ctx.state, player, claim.position, ctx.tick)
	)
	var allowed := _allowed_travel(
		player, rules, covered, checked.settled, claim.moving, pushed, sprint_tail
	)
	if checked.travel > allowed:
		return null
	var jumping := jumped or motion.jumping
	var base_y := checked.take_off_y if jumped else motion.base_y
	# The slope allowance counts the travel of at most SLOPE_TICKS covered ticks.
	var slope_travel := minf(checked.travel, allowed * mini(covered, SLOPE_TICKS) / covered)
	if claim.position.y - base_y > _allowed_rise(rules, jumping, slope_travel):
		return null
	return checked


## Makes a checked claim the player's last accepted one: settles its ticks, pays an accepted jump,
## and tracks jumps and landings.
static func _accept(
	ctx: MatchContext, player: PlayerState, motion: Motion, claim: Claim, checked: Checked
) -> void:
	var rules := ctx.state.player_rules
	if checked.new_jumps == 0:
		# A jump claim settled its ticks in _check already.
		StaminaLedger.commit(player, checked.settled)
	else:
		StaminaLedger.spend(player, _jumps_cost(rules, checked.new_jumps))
		motion.jumping = true
		motion.base_y = checked.take_off_y
	motion.jumps = claim.jumps
	if claim.on_floor:
		var landing := _floor_under(ctx.world, claim.position, rules)
		if landing != WorldQuery.NO_FLOOR:
			motion.jumping = false
			# On stairs whose treads are narrower than the capsule, the rays may all miss the step
			# the capsule rests on and find the one below (#143): the claim's own feet, less the
			# slack of a rounded bottom on a step's corner, bound the base from below.
			motion.base_y = maxf(landing.y, claim.position.y - landing_slack(rules))
	motion.credit -= checked.covered
	motion.rebase = false
	motion.accepted_tick = ctx.tick
	player.position = claim.position
	player.velocity = claim.velocity
	player.facing = stored_facing(claim.facing, player.facing)
	player.on_floor = claim.on_floor
	player.claim_tick = claim.client_tick
	player.sprint_held = claim.sprint
	player.moving = checked.moved_itself


## The horizontal metres a claim covering `covered` client ticks may travel. `moving`: the claim
## gave movement input; `pushed`: another living player is near enough to push this one;
## `sprint_tail`: the last accepted claim moved itself in the sprint state.
static func _allowed_travel(
	player: PlayerState,
	rules: PlayerRules,
	covered: int,
	settled: StaminaLedger.Settlement,
	moving: bool,
	pushed: bool,
	sprint_tail: bool
) -> float:
	var metres_per_tick := 1.0 / Ticks.RATE
	if player.life == PlayerState.Life.DOWNED:
		# The crawl: its speed alone, with no sprint and no push allowance, and a slack in
		# proportion (plus the float slack positions need) rather than a fixed one per claim.
		var crawl := covered * rules.crawl_speed_mps * metres_per_tick
		return crawl * (1.0 + CRAWL_SLACK_FRACTION) + HEIGHT_SLACK_M
	# Ticks the claim covers beyond what could be settled now take the state a next tick has.
	var sprint_ticks := settled.sprint_ticks
	if settled.next_sprinting:
		sprint_ticks += covered - settled.ticks
	if not moving:
		# Sprint speed of its own only with the movement input that pays for it: without input a
		# living player coasts (walk speed covers the client's deceleration) or is pushed, and
		# holding sprint then would buy speed for free.
		sprint_ticks = 0
	if sprint_tail:
		# The sprint's last tick (#76): a claim sends the flags of the client's last physics step,
		# so one that lets go of the input within the tick claims none after most of a sprint
		# tick, and a client learns a tick late that its stamina ran out. One covered tick more
		# at sprint speed, after a claim that sprinted by its own input; the push allowance
		# covered both before #76. Not charged, and a held sprint without input gets it once.
		# #155 (latching the flags on the client) would let the host drop it.
		sprint_ticks = mini(covered, sprint_ticks + 1)
	var walk_ticks := covered - sprint_ticks
	var travel := (
		(sprint_ticks * rules.sprint_speed_mps + walk_ticks * rules.walk_speed_mps)
		* metres_per_tick
	)
	if pushed:
		# A pushed living player moves out of an overlap at up to sprint speed on top of its own
		# (§7.1 "Pushing apart"; proposed for M4, not decided).
		# At most PUSH_TICKS ticks of it: stored credit buys no more push.
		travel += mini(covered, PUSH_TICKS) * rules.sprint_speed_mps * metres_per_tick
	return travel + DISTANCE_SLACK_M


## Whether a living player other than `player` may be pushing it: that player's last accepted
## position is within push_reach() of the claim's path (from `player`'s last accepted position to
## `to`), measured horizontally, with the feet at most the capsule's height from the path's. The
## downed and the dead push nobody (§7.1 The crawl). The reach grows by a tick of sprinting for
## each host tick since that player's last accepted claim beyond the one between two claims, up to
## PUSH_TICKS (`now`: the host tick): its lost claims leave its position behind where it pushes.
static func _near_living_player(
	state: MatchState, player: PlayerState, to: Vector3, now: int
) -> bool:
	var rules := state.player_rules
	var table := (
		state.part_state(PART_KEY, func() -> RefCounted: return MotionTable.new()) as MotionTable
	)
	var lag_per_tick := rules.sprint_speed_mps / Ticks.RATE
	var from := Vector2(player.position.x, player.position.z)
	var path := Vector2(to.x, to.z) - from
	var lowest := minf(player.position.y, to.y) - rules.capsule_height_m
	var highest := maxf(player.position.y, to.y) + rules.capsule_height_m
	for other: PlayerState in state.players.values():
		if other == player or not other.is_alive():
			continue
		if other.position.y < lowest or other.position.y > highest:
			continue
		var reach := push_reach(rules)
		var motion: Motion = table.by_peer.get(other.peer)
		if motion != null and motion.accepted_tick >= 0:
			var lost := clampi(now - motion.accepted_tick - 1, 0, PUSH_TICKS)
			reach += lost * lag_per_tick
		var at := Vector2(other.position.x, other.position.z) - from
		var along := 0.0
		if not path.is_zero_approx():
			along = clampf(at.dot(path) / path.length_squared(), 0.0, 1.0)
		if (at - path * along).length() <= reach:
			return true
	return false


## Whether a running raise holds `player` in place (Channels.holding) and a claim at `to` would
## move it: farther than HOLD_SLACK_M, in any direction, from where the raise started
## (Channel.held_at; the engineer's answer 8 on PR #133). Such a claim is corrected.
static func held_against(state: MatchState, player: PlayerState, to: Vector3) -> bool:
	var channel := Channels.holding(state, player.peer)
	return channel != null and to.distance_to(channel.held_at) > HOLD_SLACK_M


## How far from a claim's path another living player's last accepted position may be for the push
## allowance, in metres: PUSH_REACH_RADII capsule radii plus PUSH_LAG_S of sprinting (2.2 m with
## the MVP's numbers). A placeholder, "not a decision", until the M4 playtest.
static func push_reach(rules: PlayerRules) -> float:
	return PUSH_REACH_RADII * rules.capsule_radius_m + PUSH_LAG_S * rules.sprint_speed_mps


## The facing to store for a claimed `claimed` (finite) after `last`: a unit vector whose pitch is
## at most MAX_PITCH_DEG up or down. A claim with no direction keeps `last`; one straight up or
## down keeps the yaw of `last` (or faces Vector3.FORWARD's when that has none either).
static func stored_facing(claimed: Vector3, last: Vector3) -> Vector3:
	var largest := maxf(absf(claimed.x), maxf(absf(claimed.y), absf(claimed.z)))
	if not claimed.is_finite() or largest == 0.0:
		return last
	# Scaled before normalising, so a huge finite claim still gives a unit vector.
	var unit := (claimed / largest).normalized()
	var flat := Vector2(unit.x, unit.z)
	if flat.is_zero_approx():
		flat = Vector2(last.x, last.z)
		if flat.is_zero_approx():
			flat = Vector2(Vector3.FORWARD.x, Vector3.FORWARD.z)
	var yaw := flat.normalized()
	var most := deg_to_rad(MAX_PITCH_DEG)
	var pitch := clampf(atan2(unit.y, Vector2(unit.x, unit.z).length()), -most, most)
	return Vector3(yaw.x * cos(pitch), sin(pitch), yaw.y * cos(pitch))


## The stamina `count` jumps cost, in thousandths.
static func _jumps_cost(rules: PlayerRules, count: int) -> int:
	return count * Ticks.thousandths(rules.jump_cost)


## How far above its base the feet of a claim may be.
static func _allowed_rise(rules: PlayerRules, jumping: bool, travel: float) -> float:
	if jumping:
		return rules.jump_height_m + jump_slack(rules) + HEIGHT_SLACK_M
	return rules.step_height_m + STEP_CLEARANCE + travel * tan(FLOOR_MAX_ANGLE) + HEIGHT_SLACK_M


## How far above the jump height an honest jump may put the feet (ARCHITECTURE §7, #46): a
## capsule's rounded bottom rolls onto a ledge corner up to r * (1 - cos(floor_max_angle)) higher
## (about 0.12 m), and a jump from mid-crossing a step starts STEP_CLEARANCE higher.
static func jump_slack(rules: PlayerRules) -> float:
	return rules.capsule_radius_m * (1.0 - cos(FLOOR_MAX_ANGLE)) + STEP_CLEARANCE


## How far below the floor it stands on a landing claim's feet may be (#76, #143): a capsule's
## rounded bottom resting on a step's corner hangs up to r * (1 - cos(floor_max_angle)) below it
## (about 0.12 m). A placeholder, "not a decision", until the M4 playtest.
static func landing_slack(rules: PlayerRules) -> float:
	return rules.capsule_radius_m * (1.0 - cos(FLOOR_MAX_ANGLE))


## The floor WorldQuery finds under feet at `feet` (the capsule's footprint: stand_floor_below,
## so a player on a ledge's edge stands on the ledge; E10), if it is within step height below
## them; else NO_FLOOR. Crossing a ledge's edge, the client's feet are up to step height +
## STEP_CLEARANCE above the lower floor while it counts as grounded (and may jump), so that is the
## bound.
static func _floor_under(world: WorldQuery, feet: Vector3, rules: PlayerRules) -> Vector3:
	var found := world.stand_floor_below(feet + Vector3.UP * FLOOR_PROBE_M)
	var most := rules.step_height_m + STEP_CLEARANCE + HEIGHT_SLACK_M
	if found == WorldQuery.NO_FLOOR or feet.y - found.y > most:
		return WorldQuery.NO_FLOOR
	return found


## A placement (PlacePlayers, §3.2) set the player's position and epoch: the claims start again
## from there, on the floor, with a fresh client-tick baseline and credit. The ticks since the
## last claim are settled as standing still: the player did not move itself across the scene
## change.
static func _after_placement(
	motion: Motion, player: PlayerState, rules: PlayerRules, now: int
) -> void:
	motion.epoch = player.epoch
	motion.credit = TICK_LEAD
	motion.credit_tick = now
	motion.base_y = player.position.y
	motion.jumping = false
	motion.rebase = false
	motion.jumps = 0
	motion.accepted_tick = now
	player.on_floor = true
	player.claim_tick = -1
	player.sprint_held = false
	player.moving = false
	StaminaLedger.settle_ahead(player, rules, now)


## A failed check: a new epoch and the host's position, to that player only (§7).
static func _correct(ctx: MatchContext, player: PlayerState, motion: Motion) -> void:
	player.epoch += 1
	motion.epoch = player.epoch
	# The client counts its jumps from 0 again once it adopts the new epoch (§4.3).
	motion.jumps = 0
	ctx.emit(CorrectionEvent.new(player.peer, player.epoch, player.position, player.velocity))


## The claim's fields, or null when one is missing, of the wrong type or not finite.
static func _read(command: MatchCommand) -> Claim:
	var tick: Variant = command.field("client_tick")
	var position: Variant = command.field("position")
	var velocity: Variant = command.field("velocity")
	var facing: Variant = command.field("facing")
	var jumps: Variant = command.field("jumps")
	if not (tick is int and position is Vector3 and velocity is Vector3 and facing is Vector3):
		return null
	if not jumps is int or jumps < 0 or jumps > MAX_JUMPS:
		return null
	var claim := Claim.new()
	claim.client_tick = tick
	claim.position = position
	claim.velocity = velocity
	claim.facing = facing
	if not (claim.position.is_finite() and claim.velocity.is_finite() and claim.facing.is_finite()):
		return null
	claim.sprint = command.get_bool("sprint")
	claim.moving = command.get_bool("moving")
	claim.jumps = jumps
	claim.on_floor = command.get_bool("on_floor")
	return claim


static func _motion(state: MatchState, peer: int) -> Motion:
	var table := (
		state.part_state(PART_KEY, func() -> RefCounted: return MotionTable.new()) as MotionTable
	)
	if not table.by_peer.has(peer):
		table.by_peer[peer] = Motion.new()
	return table.by_peer[peer]
