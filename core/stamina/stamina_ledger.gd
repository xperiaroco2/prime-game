class_name StaminaLedger
extends RefCounted
## The stamina rule of ARCHITECTURE §7.1 and Q7, one ledger per player on its PlayerState: its
## stamina in thousandths, the host tick up to which it is settled, and its sprint state.
##
## - Each settled tick first takes the sprint state: it starts when sprint is held and stamina is
##   at least `sprint_start`, and lasts while sprint is held and stamina is above 0.
## - A tick in the sprint state in which the player gave movement input and moved horizontally
##   costs `sprint_cost_per_s` / 20; every other tick regenerates `stamina_regen_per_s` / 20, up to
##   the maximum. Only the player's own movement counts: a pushed player pays nothing for the
##   push (the engineer's decision of 2026-09-30, #46).
## - A claim settles the ticks it covers, never past the current host tick, each with the flags
##   its masks give that tick (MovementRule, simulate_ticks, #155). Before a jump or a hit is
##   checked, the ticks not yet settled are settled with the last claim's sprint flag and movement
##   (settle_ahead), so an idle player is not refused on stale stamina; a later claim settles only
##   what is left.
## - At 0 stamina walking works; sprint and jump need their full cost (Q7).
## - Only the living sprint: a downed player crawls (MovementRule), is never in the sprint state
##   and regenerates as usual, since it spends none (vision revision 1).
##
## The client's PredictedStamina (client/player/) predicts with the same rule and follows
## SelfStatus: on the network claim by claim, from the claim each SelfStatus names (M4-7, E24,
## #155; ARCHITECTURE §7.1 Speed).


## The result of settling a run of ticks, before it is committed to the player.
class Settlement:
	extends RefCounted
	var stamina := 0
	var sprinting := false
	var settled_tick := -1
	## The ticks settled.
	var ticks := 0
	## simulate_ticks only: of all the ticks it was given, settled or not, those in the sprint
	## state with the player's own movement, which a claim may cover at sprint speed.
	var fast_ticks := 0


## Settles `player` through host tick `through_tick`, as if it held sprint (`sprint_held`) and
## moved itself (`moving`) on each tick, and commits it.
static func settle(
	player: PlayerState, rules: PlayerRules, through_tick: int, sprint_held: bool, moving: bool
) -> Settlement:
	var result := simulate(player, rules, through_tick, sprint_held, moving)
	commit(player, result)
	return result


## Settles the ticks up to `now` that no claim has settled yet, with the last claim's sprint flag
## and movement: before a jump or a hit is checked (§7.1).
static func settle_ahead(player: PlayerState, rules: PlayerRules, now: int) -> void:
	settle(player, rules, now, player.sprint_held, player.moving)


## What settle() would do, without changing `player`.
static func simulate(
	player: PlayerState, rules: PlayerRules, through_tick: int, sprint_held: bool, moving: bool
) -> Settlement:
	var result := Settlement.new()
	result.stamina = player.stamina
	result.sprinting = player.sprinting
	result.settled_tick = player.stamina_settled_tick
	if player.stamina_settled_tick < 0:
		# No ledger yet (a join, or ResetMatch): it starts here, with nothing to settle.
		result.settled_tick = through_tick
		return result
	var count := maxi(0, through_tick - player.stamina_settled_tick)
	result.ticks = count
	result.settled_tick = player.stamina_settled_tick + count
	var most := Ticks.thousandths(rules.stamina)
	var cost := Ticks.per_tick(rules.sprint_cost_per_s)
	var regen := Ticks.per_tick(rules.stamina_regen_per_s)
	var moving_sprint := sprint_held and moving
	for i in count:
		result.sprinting = _sprint_state(
			player.life, sprint_held, result.sprinting, result.stamina, rules
		)
		if result.sprinting and moving:
			result.stamina = maxi(0, result.stamina - cost)
		else:
			result.stamina = mini(most, result.stamina + regen)
		if result.stamina == most and result.sprinting == sprint_held and not moving_sprint:
			# Full and steady: every remaining tick is the same.
			break
	return result


## What settling a claim's covered ticks would do, each tick with its own flags (#155), without
## changing `player`: `sprint_held[j]` and `moving[j]` are the j-th tick's, oldest first. Like
## simulate(), never past `through_tick`: `ticks` counts the oldest ticks that fit and the
## settlement stops after them. The ticks past it are run on from there for `fast_ticks` only,
## which counts, over every given tick, those in the sprint state with the player's own movement.
static func simulate_ticks(
	player: PlayerState,
	rules: PlayerRules,
	through_tick: int,
	sprint_held: Array[bool],
	moving: Array[bool]
) -> Settlement:
	var result := Settlement.new()
	var count := sprint_held.size()
	var fits := 0
	if player.stamina_settled_tick < 0:
		# No ledger yet (a join, or ResetMatch): it starts here, with nothing to settle.
		result.settled_tick = through_tick
	else:
		fits = clampi(through_tick - player.stamina_settled_tick, 0, count)
		result.settled_tick = player.stamina_settled_tick + fits
	result.ticks = fits
	var most := Ticks.thousandths(rules.stamina)
	var cost := Ticks.per_tick(rules.sprint_cost_per_s)
	var regen := Ticks.per_tick(rules.stamina_regen_per_s)
	var stamina := player.stamina
	var sprinting := player.sprinting
	for j in count:
		if j == fits:
			result.stamina = stamina
			result.sprinting = sprinting
		sprinting = _sprint_state(player.life, sprint_held[j], sprinting, stamina, rules)
		if sprinting and moving[j]:
			stamina = maxi(0, stamina - cost)
			result.fast_ticks += 1
		else:
			stamina = mini(most, stamina + regen)
	if fits == count:
		result.stamina = stamina
		result.sprinting = sprinting
	return result


static func commit(player: PlayerState, result: Settlement) -> void:
	player.stamina = result.stamina
	player.sprinting = result.sprinting
	player.stamina_settled_tick = result.settled_tick


## Whether holding sprint now would put the player in the sprint state on its next tick: what
## SelfStatus calls "sprint available".
static func sprint_available(player: PlayerState, rules: PlayerRules) -> bool:
	return _sprint_state(player.life, true, player.sprinting, player.stamina, rules)


## The player's ledger as it is: commit() puts it back (a refused jump claim, MovementRule).
static func snapshot(player: PlayerState) -> Settlement:
	var result := Settlement.new()
	result.stamina = player.stamina
	result.sprinting = player.sprinting
	result.settled_tick = player.stamina_settled_tick
	return result


## Spends `amount` thousandths (a jump, a hit).
static func spend(player: PlayerState, amount: int) -> void:
	player.stamina = maxi(0, player.stamina - amount)


## Whether `player` has at least `amount` thousandths.
static func covers(player: PlayerState, amount: int) -> bool:
	return player.stamina >= amount


static func _sprint_state(
	life: PlayerState.Life, held: bool, was_sprinting: bool, stamina: int, rules: PlayerRules
) -> bool:
	if not held or life != PlayerState.Life.ALIVE:
		return false
	if was_sprinting:
		return stamina > 0
	return stamina >= Ticks.thousandths(rules.sprint_start)
