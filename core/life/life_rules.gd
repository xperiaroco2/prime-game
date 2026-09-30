class_name LifeRules
extends RefCounted
## The life rule (ARCHITECTURE §3.4, §3.5, §5, §9.2): damage, death and leaving mid-round. The one
## place that lowers a player's health or changes its life state during a round. Strike (2g) calls
## damage(); RoundPhase calls leave() on a PeerLeft.
##
## - damage(): health falls by the amount, never below 0; Damaged to the victim only, and its
##   SelfStatus is touched (sent at the end of the tick). At 0 health the player dies.
## - die(): the body comes to rest on the floor below the last accepted position (WorldQuery, from
##   just above the feet: Items.lifted), recorded in MatchState.bodies; the life state becomes
##   ghost; the ghost appears at the body: its position is the body's, with a new epoch, so the
##   claims it sent while alive are dropped as stale and its first claim as a ghost starts a new
##   baseline there (MovementRule treats it like a placement). Then, in this order: Died
##   (everyone), Correction (the ghost only: its new epoch and position), the fact player_died,
##   and only then the held item drops at the body (Items.place, `death`). The fact comes before
##   the drop so a win condition that the death meets is checked before one that the dropped item
##   meets (§3.4: the last crew member killed with its package over its circle is a dissident
##   win).
## - leave(): the life state becomes left (which counts as dead for the win conditions), no body
##   stays; PlayerLeft (everyone else), then the fact player_left, then the held item drops on the
##   floor below where the player stood (Items.drop_held, `leave`).
##
## No event names a killer or a cause (§4.2). The name is LifeRules, not Life, so that no global
## class shadows the enum PlayerState.Life.


## `peer` takes `amount` thousandths of damage. Damaged (the victim), its SelfStatus touched, and
## at 0 health die(). A player who is not alive takes none: that is a rule error, logged.
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
		die(ctx, peer)


## `peer` dies: its body, its ghost at the body, Died, Correction, player_died, then the drop.
static func die(ctx: MatchContext, peer: int) -> void:
	var dead := ctx.state.player(peer)
	if dead == null or not dead.is_alive():
		ctx.error("die: player %d is not alive" % peer)
		return
	var body := ctx.world.floor_below(Items.lifted(dead.position))
	if body == WorldQuery.NO_FLOOR:
		ctx.error("die: no floor below %s for the body of player %d" % [dead.position, peer])
		body = dead.position
	ctx.state.bodies[peer] = body
	dead.life = PlayerState.Life.GHOST
	dead.position = body
	dead.velocity = Vector3.ZERO
	dead.epoch += 1
	ctx.emit(DiedEvent.new(peer, body))
	ctx.emit(CorrectionEvent.new(peer, dead.epoch, dead.position, dead.velocity))
	var fact := Fact.new(Facts.PLAYER_DIED)
	fact.player = peer
	fact.position = body
	ctx.raise_fact(fact)
	# The item rests at the body itself, not at a second floor query from the same point.
	var held := Items.held_by(ctx.state, peer)
	if held != null:
		Items.place(ctx, held, body, Items.DEATH)


## `peer` leaves while its life state counts (Round, §3.5): left, PlayerLeft, player_left, then the
## drop. A player who left already changes nothing.
static func leave(ctx: MatchContext, peer: int) -> void:
	var leaver := ctx.state.player(peer)
	if leaver == null or not leaver.is_present():
		return
	leaver.life = PlayerState.Life.LEFT
	ctx.emit(PlayerLeftEvent.new(peer))
	var fact := Fact.new(Facts.PLAYER_LEFT)
	fact.player = peer
	ctx.raise_fact(fact)
	Items.drop_held(ctx, peer, Items.LEAVE)
