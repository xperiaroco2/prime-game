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
## MoveClaim's covered ticks with that claim's flags, which the session latches over its steps
## (ClientSession.claim_sent), so the prediction settles the same ticks with the same flags
## (settle_claim) instead of cutting the steps' time itself, and pays a claim's jumps after its
## ticks, as the host does. A SelfStatus then answers a claim sent some ticks ago, and the claims
## since are still in flight: follow_status keeps the prediction when the host's number is one it
## predicted after one of its last claims (the host agrees so far; a number only one claim left
## gives the round trip in claims), and otherwise (a cost the client does not predict, a hit, a
## respawn, a claim the host dropped) takes the host's number and settles again on top of it as
## many of the newest claims as that round trip says are in flight. Setting each SelfStatus as it
## arrives (set_status) would give back the ticks still in flight: a sprinter whose stamina ran out
## would sprint on for a round trip, more than the host's one tick of allowance covers, and the
## host would correct them.

const TICK_SECONDS := 1.0 / Ticks.RATE
## Float rounding of 1/60 s steps must not lose a tick.
const _CARRY_SLACK := 1e-6
## The claims follow_status remembers: well over a round trip at 20 Hz (1.6 s).
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
## The last HISTORY claims settled, oldest first, and how many of the newest ones the host had not
## answered yet when it was last seen to agree (by claims only).
var _claims: Array[SettledClaim] = []
var _in_flight := 1


## One settled claim, for follow_status: what it covered and claimed, and the numbers before and
## after it.
class SettledClaim:
	extends RefCounted
	var covered := 0
	var sprint := false
	var moved_itself := false
	var downed := false
	var jumps_cost := 0
	var sprinting_before := false
	var stamina_after := 0


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


## A MoveClaim went out (ClientSession.claim_sent): its `covered` ticks are settled with its
## latched `sprint` flag and `moved_itself`, as the host's ledger settles them, then the jumps
## since the last claim are paid. `downed`: the player's life when it was sent.
func settle_claim(covered: int, sprint: bool, moved_itself: bool, downed: bool) -> void:
	var claim := SettledClaim.new()
	claim.covered = covered
	claim.sprint = sprint
	claim.moved_itself = moved_itself
	claim.downed = downed
	claim.jumps_cost = _jumps_due
	claim.sprinting_before = _sprinting
	_jumps_due = 0
	_settle(claim)
	_claims.append(claim)
	if _claims.size() > HISTORY:
		_claims.pop_front()


## The host's number from a SelfStatus (thousandths), by claims: kept when it is what this
## predicted after one of the claims it remembers, else taken, with the claims the host has not
## answered settled again on top of it (the class comment).
func follow_status(thousandths: int) -> void:
	if not _by_claims:
		set_status(thousandths)
		return
	var host := clampi(thousandths, 0, _most)
	for age: int in _claims.size():
		var index := _claims.size() - 1 - age
		if _claims[index].stamina_after != host:
			continue
		# SelfStatus goes out only when it changes, so it answers the first claim that left this
		# number. Where the claim before left it too (stamina full, or flat), that claim is
		# unknown and the round trip learnt at the last clear match is kept.
		if index > 0 and _claims[index - 1].stamina_after != host:
			_in_flight = age
		return
	var replay := mini(_in_flight, _claims.size())
	var first := _claims.size() - replay
	stamina = host
	if first < _claims.size():
		_sprinting = _claims[first].sprinting_before
	for i: int in range(first, _claims.size()):
		_claims[i].sprinting_before = _sprinting
		_settle(_claims[i])


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


## Settles `claim` from the current numbers with the ledger's rule (StaminaLedger.simulate), and
## records what it left.
func _settle(claim: SettledClaim) -> void:
	for i: int in claim.covered:
		_sprinting = _sprint_state(claim.sprint, _sprinting, claim.downed)
		if _sprinting and claim.moved_itself:
			stamina = maxi(0, stamina - _cost)
		else:
			stamina = mini(_most, stamina + _regen)
	stamina = maxi(0, stamina - claim.jumps_cost)
	claim.stamina_after = stamina


## StaminaLedger's sprint state of a tick: sprint held by a living player, started at
## `sprint_start` and lasting while stamina is above 0.
func _sprint_state(held: bool, was_sprinting: bool, downed: bool) -> bool:
	if not held or downed:
		return false
	if was_sprinting:
		return stamina > 0
	return stamina >= _sprint_start
