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
##   below the last accepted claim's in the epoch is corrected. A rise d >= 1 is one jump:
##   WorldQuery finds a floor within step height (+ STEP_CLEARANCE, a ledge crossing) below the
##   player's last accepted position and stamina covers d times the jump's cost, settled first:
##   the claim's own ticks with its own flags, then any later ones (settle_ahead). A merged burst
##   of d jumps pays for each but grants one jump height, because the merged claims' take-offs
##   are lost (accepted in the ADR). A downed player crawls and never jumps: any new jump of
##   theirs is corrected. The last claim need not say it was on the floor: claims go at 20 Hz
##   and the client's physics at 60 Hz, so a landing and a jump can fall in one claim. The
##   take-off is the higher of that floor and the last feet, so the peak stays bounded.
## - Horizontal speed over the client's tick delta: per covered tick the state's speed (for the
##   living sprint in the sprint state with movement input, else walk; for the downed the crawl
##   speed, with no sprint), plus, for the living only, sprint speed for being pushed (§7.1
##   "Pushing apart", proposed for M4; the downed push nobody and nobody pushes them), plus
##   DISTANCE_SLACK_M. The crawl's slack is CRAWL_SLACK_FRACTION of its own travel (+ the float
##   slack) instead: a fixed slack per claim would let a client sending one-tick claims crawl at
##   twice the crawl speed. The host never checks or corrects overlap between players.
## - Height: until the next landing (a claim on the floor with a WorldQuery floor within step
##   height), the feet stay within the jump height (+ JUMP_SLACK) of the take-off after an
##   accepted jump, else within step height (+ STEP_CLEARANCE, + the horizontal travel times
##   tan(FLOOR_MAX_ANGLE) for a slope or a staircase) of the last landing's floor. Falling is not
##   bounded, and walls are not checked (§7.1).
##   A downed player is bounded the same way: with no jump, its rise is the step height (plus the
##   slope allowance) above its last landing.
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
	var checked := _check(ctx, player, motion, claim, covered)
	if checked == null:
		_correct(ctx, player, motion)
		return
	_accept(ctx, player, motion, claim, checked)


## Runs the checks after the tick rate's; null when one fails. May settle stamina up to now, which
## applies only ticks that have passed (§9.2).
static func _check(
	ctx: MatchContext, player: PlayerState, motion: Motion, claim: Claim, covered: int
) -> Checked:
	var rules := ctx.state.player_rules
	var checked := Checked.new()
	checked.covered = covered
	checked.travel = (
		Vector2(claim.position.x - player.position.x, claim.position.z - player.position.z).length()
	)
	checked.moved_itself = claim.moving and checked.travel > MOVE_EPSILON
	checked.settled = StaminaLedger.simulate(
		player, rules, ctx.tick, claim.sprint, checked.moved_itself, covered
	)
	checked.new_jumps = claim.jumps - motion.jumps
	if checked.new_jumps < 0:
		# A count that falls within an epoch is no honest client's.
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
	if checked.travel > _allowed_travel(player, rules, covered, checked.settled, claim.moving):
		return null
	var jumping := jumped or motion.jumping
	var base_y := checked.take_off_y if jumped else motion.base_y
	if claim.position.y - base_y > _allowed_rise(rules, jumping, checked.travel):
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
			motion.base_y = landing.y
	motion.credit -= checked.covered
	motion.rebase = false
	player.position = claim.position
	player.velocity = claim.velocity
	player.facing = stored_facing(claim.facing, player.facing)
	player.on_floor = claim.on_floor
	player.claim_tick = claim.client_tick
	player.sprint_held = claim.sprint
	player.moving = checked.moved_itself


## The horizontal metres a claim covering `covered` client ticks may travel. `moving`: the claim
## gave movement input.
static func _allowed_travel(
	player: PlayerState,
	rules: PlayerRules,
	covered: int,
	settled: StaminaLedger.Settlement,
	moving: bool
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
	var walk_ticks := covered - sprint_ticks
	var travel := (
		(sprint_ticks * rules.sprint_speed_mps + walk_ticks * rules.walk_speed_mps)
		* metres_per_tick
	)
	# A pushed living player moves out of an overlap at up to sprint speed on top of its own
	# (§7.1 "Pushing apart"; proposed for M4, not decided).
	travel += covered * rules.sprint_speed_mps * metres_per_tick
	return travel + DISTANCE_SLACK_M


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
