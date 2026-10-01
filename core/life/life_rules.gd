class_name LifeRules
extends RefCounted
## The life rule (ARCHITECTURE §3.4, §3.5, §5, §9.2): damage, the knockdown, death and leaving
## mid-round. The one place that lowers a player's health or changes its life state during a
## round. Strike (2g) calls damage(); LifeTicks calls die() when a knockdown runs out; RoundPhase
## calls leave() on a PeerLeft.
##
## - damage(): health falls by the amount, never below 0; Damaged to the victim only, and its
##   SelfStatus is touched (sent at the end of the tick). At 0 health the player is knocked down.
## - knock_down(): the player is downed where it stands: on the floor below its last accepted
##   position (WorldQuery, from just above the feet: Items.lifted), with a new epoch, so the
##   walk-speed claims it sent while living are dropped as stale and its first claim as downed
##   starts a new baseline there (MovementRule treats it like a placement); its knockdown runs out
##   `PlayerRules.knockdown_s` later (PlayerState.life_deadline, which LifeTicks reads). Then
##   KnockedDown (everyone) and Correction (the downed player only: its new epoch and position).
##   Nothing drops: a downed player keeps its hand. No fact: no win condition reads a knockdown.
## - die(): a downed player dies: its body comes to rest on the floor below its last accepted
##   position, recorded in MatchState.bodies until it leaves (or, from M4-3, respawns); it has no
##   avatar any more, and no Correction is sent (the dead send no claims). Then, in this order:
##   Died (everyone), the fact player_died, and only then the held item drops at the body
##   (Items.place, `death`). The fact comes before the drop so a win condition that the death
##   meets is checked before one that the dropped item meets (§3.4).
## - leave(): the life state becomes left, and a dead player's body is removed (a downed or dead
##   player who leaves leaves no body: the engineer's answer 1 on PR #133); PlayerLeft (everyone
##   else), then the fact player_left, then the held item drops on the floor below where the
##   player stood (Items.drop_held, `leave`).
##
## No event names an attacker or a cause (§4.2). The name is LifeRules, not Life, so that no global
## class shadows the enum PlayerState.Life.


## `peer` takes `amount` thousandths of damage. Damaged (the victim), its SelfStatus touched, and
## at 0 health knock_down(). A player who is not alive takes none: that is a rule error, logged.
static func damage(ctx: MatchContext, peer: int, amount: int) -> void:
	var victim := ctx.state.player(peer)
	if victim == null or not victim.is_alive():
		ctx.error("damage: player %d is not alive" % peer)
		return
	var taken := maxi(0, amount)
	victim.health = maxi(0, victim.health - taken)
	ctx.emit(DamagedEvent.new(peer, taken, victim.health))
	SelfStatusFeed.touch(ctx.state, peer)
	if victim.health == 0:
		knock_down(ctx, peer)


## `peer`, living, is downed where it stands: KnockedDown, then its Correction.
static func knock_down(ctx: MatchContext, peer: int) -> void:
	var downed := ctx.state.player(peer)
	if downed == null or not downed.is_alive():
		ctx.error("knock_down: player %d is not alive" % peer)
		return
	var rules := ctx.state.player_rules
	if rules == null:
		ctx.error("knock_down: the mode has no PlayerRules")
		return
	var lies_at := _floor_at(ctx, downed, "knock_down")
	downed.life = PlayerState.Life.DOWNED
	downed.life_deadline = ctx.tick + Ticks.from_seconds(rules.knockdown_s)
	downed.position = lies_at
	downed.velocity = Vector3.ZERO
	downed.sprinting = false
	downed.epoch += 1
	ctx.emit(KnockedDownEvent.new(peer, lies_at))
	ctx.emit(CorrectionEvent.new(peer, downed.epoch, downed.position, downed.velocity))


## `peer`, downed, dies: its body, Died, player_died, then the drop at the body.
static func die(ctx: MatchContext, peer: int) -> void:
	var dead := ctx.state.player(peer)
	if dead == null or dead.life != PlayerState.Life.DOWNED:
		ctx.error("die: player %d is not downed" % peer)
		return
	var body := _floor_at(ctx, dead, "die")
	ctx.state.bodies[peer] = body
	dead.life = PlayerState.Life.DEAD
	dead.life_deadline = -1
	dead.position = body
	dead.velocity = Vector3.ZERO
	ctx.emit(DiedEvent.new(peer, body))
	var fact := Fact.new(Facts.PLAYER_DIED)
	fact.player = peer
	fact.position = body
	ctx.raise_fact(fact)
	# The item rests at the body itself, not at a second floor query from the same point.
	var held := Items.held_by(ctx.state, peer)
	if held != null:
		Items.place(ctx, held, body, Items.DEATH)


## `peer` leaves while its life state counts (Round, §3.5): left, no body, PlayerLeft,
## player_left, then the drop. A player who left already changes nothing.
static func leave(ctx: MatchContext, peer: int) -> void:
	var leaver := ctx.state.player(peer)
	if leaver == null or not leaver.is_present():
		return
	leaver.life = PlayerState.Life.LEFT
	leaver.life_deadline = -1
	ctx.state.bodies.erase(peer)
	ctx.emit(PlayerLeftEvent.new(peer))
	var fact := Fact.new(Facts.PLAYER_LEFT)
	fact.player = peer
	ctx.raise_fact(fact)
	Items.drop_held(ctx, peer, Items.LEAVE)


## The floor below `player`'s last accepted position; where it is, logged, when there is none.
static func _floor_at(ctx: MatchContext, player: PlayerState, what: String) -> Vector3:
	var found := ctx.world.floor_below(Items.lifted(player.position))
	if found == WorldQuery.NO_FLOOR:
		ctx.error("%s: no floor below %s for player %d" % [what, player.position, player.peer])
		return player.position
	return found
