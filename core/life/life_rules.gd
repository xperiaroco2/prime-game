class_name LifeRules
extends RefCounted
## The life rule (ARCHITECTURE §3.4, §3.5, §5, §9.2): damage, the knockdown, the revive, death,
## the respawn, invulnerability and leaving mid-round. The one place that lowers a player's health
## or changes its life state during a round. Strike (2g) calls damage(); LifeTicks calls die() when
## a knockdown runs out, and its Respawn calls respawn() when a death's respawn time runs out; the
## raise (RaiseDowned, M4-4) calls revive() when it completes, and the give-up (Die) calls die();
## RoundPhase calls leave() on a PeerLeft.
##
## - damage(): health falls by the amount, never below 0; Damaged to the victim only, and its
##   SelfStatus is touched (sent at the end of the tick). The hit stops the victim's own channel (a
##   raise it runs: RaiseStopped, Channels.interrupt). At 0 health the player is knocked down.
## - knock_down(): every channel the player runs stops first (Channels.interrupt_involving: a
##   raiser downed stops its raise). The player is downed where it stands: on the floor below its
##   last accepted position (WorldQuery, from just above the feet: Items.lifted), with a new
##   epoch, so the walk-speed claims it sent while living are dropped as stale and its first claim
##   as downed starts a new baseline there (MovementRule treats it like a placement); its
##   knockdown runs out `PlayerRules.knockdown_s` later (PlayerState.life_deadline, which
##   LifeTicks reads). Then
##   KnockedDown (everyone) and Correction (the downed player only: its new epoch and position).
##   Its stamina is settled up to the knockdown first, as the living player it was: the ticks
##   since its last claim pay for its sprint, not regenerate as a downed player's would.
##   Nothing drops: a downed player keeps its hand. No fact: no win condition reads a knockdown.
## - revive(): a downed player whose raise completed stands up where it lay, living, with the
##   raise's health (at most PlayerRules.health), its stamina as it was (settled first, as the
##   downed player it was: it regenerated), no deadline, and invulnerable (make_invulnerable). Then
##   Revived (everyone) and its SelfStatus at the end of the tick. No Correction and no new epoch:
##   the raise held it in place (MovementRule), so its client stands where the host has it, and its
##   next claim is checked at walking speed from there. No fact: no win condition reads a revive.
## - die(): every channel targeting the downed player stops first (a raise of a player who gives
##   up: RaiseStopped). A downed player dies: its body comes to rest on the floor below its last
##   accepted position, recorded in MatchState.bodies until it leaves or respawns; it has no
##   avatar any more, and no Correction is sent (the dead send no claims). Its respawn time runs out
##   `PlayerRules.respawn_s` later (PlayerState.life_deadline). Then, in this order:
##   Died (everyone), the fact player_died, and only then the held item drops at the body
##   (Items.place, `death`). The fact comes before the drop so a win condition that the death
##   meets is checked before one that the dropped item meets (§3.4).
## - respawn(): a dead player is living again at a respawn marker (Respawn draws it): its body is
##   removed, its role kept, its health and stamina full, its hands empty, a new epoch (a
##   placement for the movement rule), and invulnerable (make_invulnerable). Then Respawned
##   (everyone; it removes the body, E26) and Correction (that player only), and its SelfStatus
##   at the end of the tick. No fact: no win condition reads a respawn.
## - make_invulnerable(): strikes skip the player for `PlayerRules.invulnerable_s`
##   (PlayerState.invulnerable_until); nothing ends it early (the engineer's answer 3, PR #133).
## - leave(): every channel the player runs or is the target of stops first (RaiseStopped). The
##   life state becomes left, and a dead player's body is removed (a downed or dead
##   player who leaves leaves no body: the engineer's answer 1 on PR #133); PlayerLeft (everyone
##   else), then the fact player_left, then the held item drops on the floor below where the
##   player stood (Items.drop_held, `leave`).
##
## No event names an attacker or a cause (§4.2). The name is LifeRules, not Life, so that no global
## class shadows the enum PlayerState.Life.


## `peer` takes `amount` thousandths of damage. Damaged (the victim), its SelfStatus touched, and
## at 0 health knock_down(). A player who is not alive takes none: that is a rule error, logged.
## An invulnerable player takes none and gets no Damaged, with no error: invulnerability blocks
## every damage source, not only the strikes that Strike.targets already skips.
static func damage(ctx: MatchContext, peer: int, amount: int) -> void:
	var victim := ctx.state.player(peer)
	if victim == null or not victim.is_alive():
		ctx.error("damage: player %d is not alive" % peer)
		return
	if victim.is_invulnerable(ctx.tick):
		return
	var taken := maxi(0, amount)
	victim.health = maxi(0, victim.health - taken)
	ctx.emit(DamagedEvent.new(peer, taken, victim.health))
	SelfStatusFeed.touch(ctx.state, peer)
	# A hit stops what the victim was holding (a raise: vision revision 1, Revive).
	Channels.interrupt(ctx, peer)
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
	Channels.interrupt_involving(ctx, peer)
	var lies_at := _floor_at(ctx, downed, "knock_down")
	StaminaLedger.settle_ahead(downed, rules, ctx.tick)
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
	Channels.interrupt_involving(ctx, peer)
	var body := _floor_at(ctx, dead, "die")
	ctx.state.bodies[peer] = body
	dead.life = PlayerState.Life.DEAD
	var rules := ctx.state.player_rules
	dead.life_deadline = ctx.tick + Ticks.from_seconds(rules.respawn_s) if rules != null else -1
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


## `peer`, downed, stands up where it lies (a completed raise): living with `health` whole points
## (at most PlayerRules.health), stamina kept, invulnerable. Revived (everyone), then its SelfStatus
## (at the end of the tick).
static func revive(ctx: MatchContext, peer: int, health: int) -> void:
	var revived := ctx.state.player(peer)
	if revived == null or revived.life != PlayerState.Life.DOWNED:
		ctx.error("revive: player %d is not downed" % peer)
		return
	var rules := ctx.state.player_rules
	if rules == null:
		ctx.error("revive: the mode has no PlayerRules")
		return
	# The ticks since its last claim regenerated as a downed player's (it spends none).
	StaminaLedger.settle_ahead(revived, rules, ctx.tick)
	revived.life = PlayerState.Life.ALIVE
	revived.life_deadline = -1
	revived.knockdown_left = -1
	revived.health = mini(Ticks.thousandths(health), Ticks.thousandths(rules.health))
	revived.velocity = Vector3.ZERO
	make_invulnerable(ctx, peer)
	ctx.emit(RevivedEvent.new(peer))
	SelfStatusFeed.touch(ctx.state, peer)


## `peer`, dead, comes back at `at` (a respawn marker, which Respawn draws): its body goes, it is
## living with its role, full health and stamina, empty hands and a new epoch, and invulnerable
## (make_invulnerable). Respawned (everyone), then its Correction, then its SelfStatus (at the end
## of the tick).
static func respawn(ctx: MatchContext, peer: int, at: Vector3) -> void:
	var back := ctx.state.player(peer)
	if back == null or back.life != PlayerState.Life.DEAD:
		ctx.error("respawn: player %d is not dead" % peer)
		return
	var rules := ctx.state.player_rules
	if rules == null:
		ctx.error("respawn: the mode has no PlayerRules")
		return
	if back.held_item >= 0:
		# The death dropped it (die); a hand still full is a rule error, and the item drops here.
		ctx.error("respawn: player %d still holds item %d" % [peer, back.held_item])
		Items.drop_held(ctx, peer, Items.DEATH)
	ctx.state.bodies.erase(peer)
	back.life = PlayerState.Life.ALIVE
	back.life_deadline = -1
	back.health = Ticks.thousandths(rules.health)
	back.stamina = Ticks.thousandths(rules.stamina)
	# The ledger starts again at the respawn: nothing before it is settled as this life's.
	back.stamina_settled_tick = ctx.tick
	back.sprinting = false
	back.sprint_held = false
	back.moving = false
	back.position = at
	back.velocity = Vector3.ZERO
	back.epoch += 1
	make_invulnerable(ctx, peer)
	ctx.emit(RespawnedEvent.new(peer, at))
	ctx.emit(CorrectionEvent.new(peer, back.epoch, back.position, back.velocity))
	SelfStatusFeed.touch(ctx.state, peer)


## `peer` is invulnerable from now for PlayerRules.invulnerable_s (vision revision 1, V8): strikes
## skip it (Strike.targets) until then, and nothing ends it early, not even its own attack (the
## engineer's answer 3 on PR #133). The respawn and the revive call it.
static func make_invulnerable(ctx: MatchContext, peer: int) -> void:
	var player := ctx.state.player(peer)
	var rules := ctx.state.player_rules
	if player == null or rules == null:
		ctx.error("make_invulnerable: no player %d or no PlayerRules" % peer)
		return
	player.invulnerable_until = ctx.tick + Ticks.from_seconds(rules.invulnerable_s)


## `peer` leaves while its life state counts (Round, §3.5): left, no body, PlayerLeft,
## player_left, then the drop. A player who left already changes nothing.
static func leave(ctx: MatchContext, peer: int) -> void:
	var leaver := ctx.state.player(peer)
	if leaver == null or not leaver.is_present():
		return
	Channels.interrupt_involving(ctx, peer)
	leaver.life = PlayerState.Life.LEFT
	leaver.life_deadline = -1
	leaver.knockdown_left = -1
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
