class_name PredictedStamina
extends StaminaSource
## The local player's stamina (ARCHITECTURE §4.7 and §7.1, the M4 ADR's E24): predicted between
## SelfStatus updates with the rule of `core/`'s StaminaLedger, of which this is the client's only
## copy, and following each SelfStatus (below). Sprint and jump are gated by the prediction, so a
## player whose stamina ran out stops sprinting at once rather than a round trip later. The numbers
## are the client's own copy of the mode's PlayerRules (the content hash makes them the host's).
##
## The rule, in thousandths per 20 Hz tick like the ledger's, so both count the same:
## - Off the network (the dev room, the controller's own tests) the physics steps' time is cut into
##   ticks (Ticks.RATE), and each SelfStatus is set as it arrives (set_status). Each tick costs the
##   sprint cost per tick when its last step was in the sprint state with the player's own
##   movement, and regenerates the regeneration per tick otherwise, up to the maximum (a push is
##   free, the engineer's decision of 2026-09-30).
## - The sprint state starts at `sprint_start` and lasts while sprint is held and stamina is
##   above 0; a jump needs its full cost and spends it at once (Q7).
## - Only the living sprint and jump: the downed (the controller's life) crawl, are never in
##   the sprint state and regenerate as usual, since they spend none (M4-2's crawl check).
##
## On the network (#155, follow_claims()) the ticks are the claims': the host's ledger settles each
## MoveClaim's covered ticks with the flags its masks give each tick, which are that claim's
## latched flags (ClientSession.claim_sent), so the prediction settles the same ticks with the same
## flags (settle_claim) instead of cutting the steps' time itself, and pays a claim's jumps after
## its ticks, as the host does. A SelfStatus answers a claim sent some ticks ago and names its
## client tick (none, -1, before the first claim since a placement): follow_status takes the
## host's number and sprint availability, and settles again on top of them exactly the claims
## after that one (with none, the claims of the current epoch), which are still in flight. A claim
## after it from an older epoch than the client's never reached the host's ledger: it was refused
## (a Correction started the client's epoch) or dropped as stale, so its ticks are left to the next
## claim, which covers them, and its jumps are never charged (the session counts them from 0 in the
## new epoch). Events arrive in order on one reliable channel, so a status that arrives after a
## Correction was sent after it. So a cost the client does not predict (a hit, a jump the host
## refused) or a tick the host could not settle is taken in with the next status, and the ticks in
## flight are never given back: a client that set each
## SelfStatus as it arrived (set_status) would sprint on for a round trip after its stamina ran
## out, and the host would correct it.

const TICK_SECONDS := 1.0 / Ticks.RATE
## Float rounding of 1/60 s steps must not lose a tick.
const _CARRY_SLACK := 1e-6
## The claims follow_status remembers: well over a round trip at 20 Hz (1.6 s). A SelfStatus naming
## an older claim has every remembered one settled again.
const HISTORY := 32

## Thousandths of a point (§3.3), like SelfStatus.
var stamina := 0

var _most := 0
var _sprint_start := 0
var _jump_cost := 0
var _cost := 0
var _regen := 0
## Seconds of steps not yet settled as a tick.
var _carry := 0.0
## Settled by the claims (follow_claims) instead of the steps' time.
var _by_claims := false
## The sprint state the host's ledger has after the last settled claim (by claims only).
var _sprinting := false
## Thousandths the jumps since the last claim cost, paid after its ticks (by claims only).
var _jumps_due := 0
## The last HISTORY claims settled, oldest first (by claims only).
var _claims: Array[SettledClaim] = []


## One settled claim, for follow_status: when it went and what it covered and claimed.
class SettledClaim:
	extends RefCounted
	var epoch := 0
	var tick := 0
	var covered := 0
	var sprint := false
	var moved_itself := false
	var downed := false
	var jumps_cost := 0


func _init(rules: PlayerRules) -> void:
	_most = Ticks.thousandths(rules.stamina)
	_sprint_start = Ticks.thousandths(rules.sprint_start)
	_jump_cost = Ticks.thousandths(rules.jump_cost)
	_cost = Ticks.per_tick(rules.sprint_cost_per_s)
	_regen = Ticks.per_tick(rules.stamina_regen_per_s)
	stamina = _most


## The host's number from a SelfStatus (thousandths): the prediction goes on from there.
func set_status(thousandths: int) -> void:
	stamina = clampi(thousandths, 0, _most)


## Settles by the claims from now on (the controller attached to a session): report() then only
## counts jumps, and settle_claim settles the ticks.
func follow_claims() -> void:
	_by_claims = true
	_carry = 0.0


## Whether it settles by the claims.
func follows_claims() -> bool:
	return _by_claims


## The sprint state of the host's ledger after the last settled claim: whether the claim before
## the next one ended in the sprint state (by claims only; a bot asks can_sprint with it).
func is_sprinting() -> bool:
	return _sprinting


## A MoveClaim of `epoch` at client tick `tick` went out (ClientSession.claim_sent): its `covered`
## ticks are settled with its latched `sprint` flag and `moved_itself`, as the host's ledger
## settles them, then the jumps since the last claim are paid. `downed`: the player's life when
## it was sent.
func settle_claim(
	epoch: int, tick: int, covered: int, sprint: bool, moved_itself: bool, downed: bool
) -> void:
	var claim := SettledClaim.new()
	claim.epoch = epoch
	claim.tick = tick
	claim.covered = covered
	claim.sprint = sprint
	claim.moved_itself = moved_itself
	claim.downed = downed
	claim.jumps_cost = _jumps_due
	_jumps_due = 0
	_settle(claim)
	_claims.append(claim)
	if _claims.size() > HISTORY:
		_claims.pop_front()


## A SelfStatus (thousandths, sprint available), by claims: the host's numbers after its claim of
## client tick `claim_tick` (-1: none since its placement), with the claims after it (with none,
## those of the client's current `epoch`) settled again on top (the class comment). Sprint
## available is the host's sprint state wherever that decides the next tick (stamina between 0
## and the start), so the claims settle on from the host's state, not the prediction's. A claim of
## an older epoch than `epoch` is settled again without its jumps: the host never accepted it.
func follow_status(thousandths: int, available: bool, claim_tick: int, epoch: int) -> void:
	if not _by_claims:
		set_status(thousandths)
		return
	var first := _claims.size()
	while first > 0 and _in_flight(_claims[first - 1], claim_tick, epoch):
		first -= 1
	stamina = clampi(thousandths, 0, _most)
	_sprinting = available
	for i: int in range(first, _claims.size()):
		_settle(_claims[i], _claims[i].epoch == epoch)


## The jumps since the last claim will never be claimed: the session adopted a new epoch (a
## Correction or a placement), whose claims count jumps from 0, so the host never charges them.
func forget_unclaimed_jumps() -> void:
	_jumps_due = 0


func can_sprint(was_sprinting: bool, downed: bool) -> bool:
	if downed:
		return false
	if was_sprinting:
		return stamina > 0
	return stamina >= _sprint_start


func can_jump(downed: bool) -> bool:
	return not downed and stamina - _jumps_due >= _jump_cost


func report(delta: float, sprinted_moving: bool, jumped: bool, downed: bool) -> void:
	# The downed spend nothing (StaminaLedger): their steps only regenerate.
	sprinted_moving = sprinted_moving and not downed
	if jumped and not downed and _by_claims:
		_jumps_due += _jump_cost
	elif jumped and not downed:
		stamina = maxi(0, stamina - _jump_cost)
	if _by_claims:
		return
	_carry += delta
	while _carry >= TICK_SECONDS - _CARRY_SLACK:
		_carry -= TICK_SECONDS
		if sprinted_moving:
			stamina = maxi(0, stamina - _cost)
		else:
			stamina = mini(_most, stamina + _regen)


## In points, for the HUD and tests.
func get_stamina() -> float:
	return maxi(0, stamina - _jumps_due) / float(Ticks.THOUSANDTHS)


## Whether `claim` was still in flight when the host sent a SelfStatus naming `claim_tick`: sent
## after that claim, or, when it names none, in the client's current `epoch` (since its placement;
## an older epoch's claims were settled before it, or dropped).
static func _in_flight(claim: SettledClaim, claim_tick: int, epoch: int) -> bool:
	if claim_tick >= 0:
		return claim.tick > claim_tick
	return claim.epoch == epoch


## Settles `claim` from the current numbers with the ledger's rule (StaminaLedger.simulate_ticks,
## every tick with the claim's flags), and pays its jumps when `with_jumps`.
func _settle(claim: SettledClaim, with_jumps := true) -> void:
	for i: int in claim.covered:
		_sprinting = _sprint_state(claim.sprint, _sprinting, claim.downed)
		if _sprinting and claim.moved_itself:
			stamina = maxi(0, stamina - _cost)
		else:
			stamina = mini(_most, stamina + _regen)
	if with_jumps:
		stamina = maxi(0, stamina - claim.jumps_cost)


## StaminaLedger's sprint state of a tick: sprint held by a living player, started at
## `sprint_start` and lasting while stamina is above 0.
func _sprint_state(held: bool, was_sprinting: bool, downed: bool) -> bool:
	if not held or downed:
		return false
	if was_sprinting:
		return stamina > 0
	return stamina >= _sprint_start
