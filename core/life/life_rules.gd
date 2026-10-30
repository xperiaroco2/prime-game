class_name LifeRules
extends RefCounted
## The life rule (ARCHITECTURE §3.4, §3.5, §5, §9.2): damage, the knockdown, the revive, death,
## the respawn, invulnerability and leaving mid-round. The one place that lowers a player's health
## or changes its life state during a round. Strike (2g) calls damage(); LifeTicks calls die() when
## a knockdown runs out, and its Respawn calls respawn() when a death's respawn time runs out; the
## raise (RaiseDowned, M4-4) calls revive() when it completes, and the give-up (Die) calls die();
## RoundPhase calls leave() on a PeerLeft. A task type that can kill (TaskType.kills(): the car's
## drop) queues kill() through kill_later().
##
## - damage(): health falls by the amount, never below 0; Damaged to the victim only, and its
##   SelfStatus is touched (sent at the end of the tick). The hit stops the victim's own channel
##   when its effect stops on a hit (a raise it runs: RaiseStopped; Channels.interrupt_hit,
##   ChannelEffect.stops_on_hit); a hold with HoldStation.hit_stops false goes on (the car repair
##   ADR's RD10 (c), #805). At 0 health the player is knocked down, which stops every channel;
##   in a phase with a PhaseSpec.hit_limp (the base mode's Lobby and Countdown, #1439) it goes
##   limp instead for that GoLimp's limp_s, with the blow's launch, and gets up at full health.
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
##   Nothing drops: a downed player keeps its hand and belt items. No fact: no win condition reads
##   a knockdown. On a map PlayerRules.motion_maps lists (the knockdown rework's §4, KE12) the body
##   moves instead: it stays at the last accepted position with the launch (damage's, from a
##   Strike: KE9) as its velocity, which KnockedDown and the Correction name, keeps a BodyMotion
##   (PlayerState.motion, KE3) with that floor as its fallback rest, and LaunchBody (server) starts
##   the host's body. A launch on any other map is dropped.
## - body_moved(), count_motion() and rest(): server/'s reports (BodyMoved, KE14) set a moving
##   body's point and velocity; the motion ends at the standing floor under its capsule once the
##   reports stay slow for the rest time, or once it has lasted the longest motion (LifeTicks),
##   else at the fallback with an error (KE15); StopBody. A death, a leave, a revive and
##   ResetMatch end it too (stop_motion), each with StopBody.
## - revive(): a downed player whose raise completed stands up where it lay, living, with the
##   raise's health (at most PlayerRules.health), its stamina as it was (settled first, as the
##   downed player it was: it regenerated), no deadline, a new epoch (a placement for the movement
##   rule, as a respawn is), and invulnerable (make_invulnerable). Then Revived (everyone), its
##   Correction (that player only: where it lay; the knockdown rework's KE6) and its SelfStatus at
##   the end of the tick. A downed player's claims move nothing (MovementRule, KE4), so without the
##   Correction its client would stand up where its last walking claim was; with it, its next
##   claim is checked at walking speed from where it lay. No fact: no win condition reads a revive.
## - die(): every channel targeting the downed player stops first (a raise of a player who gives
##   up: RaiseStopped). A downed player dies: its body comes to rest on the floor below its last
##   accepted position, recorded in MatchState.bodies until it leaves or respawns; it has no
##   avatar any more, and no Correction is sent (the dead send no claims). Its respawn time runs out
##   `PlayerRules.respawn_s` later (PlayerState.life_deadline). Then, in this order:
##   Died (everyone), the fact player_died, and only then its items drop at the body, the hand's
##   first, then the belt's (Items.place_carried, `death`). The fact comes before the drop so a win
##   condition that the death meets is checked before one that a dropped item meets (§3.4).
## - kill(): the instant kill (the car repair ADR's RE6, #806): a living or downed player,
##   invulnerable or not (RD7), dies at once, everything else as die(): every channel it runs or
##   is the target of stops first, then its body, Died, player_died and the drop at the body, and
##   its respawn time. A living player's health falls to 0 (its SelfStatus touched); no
##   KnockedDown and no Correction. A task type that can kill calls it through the queue below, and
##   the mode check requires LifeTicks with a Respawn wherever such a mode takes Interact.
## - kill_later() and settle_kills() (RE17): a kill decided inside a command, a tick system or a
##   channel's step (the car's drop, from inside Channels.interrupt) is queued, never run halfway
##   through someone's command. Match settles the queue once a command's dispatch has finished,
##   after the phase's own timers and after each tick system, and Channels.advance after each
##   channel's step, so a kill lands in the command or tick of its cause, after its own events:
##   the queued players die in peer-id order; one no longer living or downed (dead already, or
##   left) is skipped with no rule error; once the step has an outcome (a win recorded earlier in
##   it) the queue clears with no kill, so nothing dies after the outcome (RD16 (c)). Kills that a
##   kill queues (its channels' stops) settle in the same call. A transition drops the queue.
## - respawn(): a dead player is living again at a respawn marker (Respawn draws it): its body is
##   removed, its role kept, its health and stamina full, its hand and belt empty, a new epoch (a
##   placement for the movement rule), and invulnerable (make_invulnerable). Then Respawned
##   (everyone; it removes the body, E26) and Correction (that player only), and its SelfStatus
##   at the end of the tick. No fact: no win condition reads a respawn.
## - make_invulnerable(): strikes skip the player for `PlayerRules.invulnerable_s`
##   (PlayerState.invulnerable_until); nothing ends it early (the engineer's answer 3, PR #133).
## - leave(): every channel the player runs or is the target of stops first (RaiseStopped). The
##   life state becomes left, and a dead player's body is removed (a downed or dead
##   player who leaves leaves no body: the engineer's answer 1 on PR #133); PlayerLeft (everyone
##   else), then the fact player_left, then its items drop on the floor below where the player
##   stood, the hand's first, then the belt's (Items.drop_carried, `leave`).
## - go_limp(), get_up(), push_limp(), clear_limp(): the limp (#1393, ARCHITECTURE §7.1.21), a
##   living player's rag-doll body with the knockdown's machinery (BodyMotion, LaunchBody,
##   BodyMoved,
##   rest, StopBody) and none of its life consequences. A limp player takes no damage (damage()
##   returns as for the invulnerable); a knockdown, a death and a leave end the limp. A hit's limp
##   (LimpState.refill) ends at full health when the player stays living: its get-up or a
##   placement (#1439); restore_health() fills a living player up (EndLimps.restore_health).
##
## No event names an attacker or a cause (§4.2). The name is LifeRules, not Life, so that no global
## class shadows the enum PlayerState.Life.

## The kill queue's key in MatchState's per-part state (§9.1): ResetMatch clears it.
const KILL_QUEUE_KEY := &"kill_queue"


## The players whose kill is queued (kill_later), in the order queued.
class KillQueue:
	extends RefCounted
	var peers: Array[int] = []


## `peer` takes `amount` thousandths of damage. Damaged (the victim), its SelfStatus touched, and
## at 0 health knock_down(), or go_limp() in a phase with a PhaseSpec.hit_limp (#1439). A player who
## is not alive takes none: that is a rule error, logged.
## An invulnerable player takes none and gets no Damaged, with no error: invulnerability blocks
## every damage source, not only the strikes that Strike.targets already skips.
static func damage(ctx: MatchContext, peer: int, amount: int, launch := Vector3.ZERO) -> void:
	var victim := ctx.state.player(peer)
	if victim == null or not victim.is_alive():
		ctx.error("damage: player %d is not alive" % peer)
		return
	if victim.is_invulnerable(ctx.tick) or victim.is_limp():
		return
	var taken := maxi(0, amount)
	victim.health = maxi(0, victim.health - taken)
	ctx.emit(DamagedEvent.new(peer, taken, victim.health))
	SelfStatusFeed.touch(ctx.state, peer)
	# A hit stops what the victim was holding (a raise: vision revision 1, Revive), unless its effect
	# goes on through hits (the lift's hold, RD10 (c)).
	Channels.interrupt_hit(ctx, peer)
	if victim.health == 0:
		# Only the blow that knocks the player down launches it (KD1 (a)): a hit that does not
		# pushes nothing, since the living move client-side (invariant 7).
		var spec := ctx.phase_spec()
		if spec != null and spec.hit_limp != null:
			# The hall's hit (#1439): the victim goes limp, never down, and gets up refilled.
			go_limp(ctx, peer, spec.hit_limp.limp_s, true, launch)
		else:
			knock_down(ctx, peer, launch)


## `peer`, living, is downed where it stands: KnockedDown, then its Correction; on a map
## PlayerRules.motion_maps lists, a motion with `launch` as its velocity and LaunchBody.
static func knock_down(ctx: MatchContext, peer: int, launch := Vector3.ZERO) -> void:
	var downed := ctx.state.player(peer)
	if downed == null or not downed.is_alive():
		ctx.error("knock_down: player %d is not alive" % peer)
		return
	var rules := ctx.state.player_rules
	if rules == null:
		ctx.error("knock_down: the mode has no PlayerRules")
		return
	Channels.interrupt_involving(ctx, peer)
	# A limp player knocked down (the tutorial's KnockDown) lies downed instead: its limp body ends,
	# and a downed player keeps its health.
	clear_limp(ctx, downed, false)
	var lies_at := _floor_at(ctx, downed, "knock_down")
	StaminaLedger.settle_ahead(downed, rules, ctx.tick)
	var moves := rules.motion_plays_on(ctx.state.map)
	downed.life = PlayerState.Life.DOWNED
	downed.life_deadline = ctx.tick + Ticks.from_seconds(rules.knockdown_s)
	downed.sprinting = false
	downed.crouched = false
	downed.sneaking = false
	# A posed player downed stands up from the chair: its client learns it in its SelfStatus (#1383).
	var was_posed := downed.posed
	downed.posed = false
	if downed.sober() or was_posed:
		SelfStatusFeed.touch(ctx.state, peer)
	downed.epoch += 1
	if moves:
		# The body starts at the last accepted position with the launch (§4, step 2): the
		# knockdown tick's snapshot starts each ragdoll the way the host's body starts.
		downed.velocity = launch if launch.is_finite() else Vector3.ZERO
		downed.motion = BodyMotion.new(downed.epoch, lies_at)
	else:
		downed.position = lies_at
		downed.velocity = Vector3.ZERO
	ctx.emit(KnockedDownEvent.new(peer, downed.position))
	ctx.emit(CorrectionEvent.new(peer, downed.epoch, downed.position, downed.velocity))
	if moves:
		ctx.emit(LaunchBodyEvent.new(peer, downed.epoch, downed.position, downed.velocity))


## A report of the host's body (BodyMoved, KE14), which server/ originates: taken only for a body in
## motion whose epoch it names (any other is dropped with no error: a report racing a stop or a
## give-up). A finite report sets the point and the velocity, and ends the motion at its rest
## (KE15) once the reports have stayed slower than PlayerRules.rest_speed_mps for rest_s, counted
## in reports; one that is not finite ends it at the fallback, with an error.
static func body_moved(ctx: MatchContext, command: MatchCommand) -> void:
	var moved := ctx.state.player(command.peer)
	var rules := ctx.state.player_rules
	if moved == null or moved.motion == null or rules == null:
		return
	if not moved.holds_still():
		ctx.error("BodyMoved: player %d moves but is neither downed nor limp" % command.peer)
		stop_motion(ctx, moved)
		return
	if command.get_int("epoch", -1) != moved.motion.epoch:
		return
	var lowest := command.get_vector3("position", Vector3.INF)
	var velocity := command.get_vector3("velocity", Vector3.INF)
	if not lowest.is_finite() or not velocity.is_finite():
		ctx.error(
			(
				"BodyMoved: player %d reported %s moving at %s: it rests at %s"
				% [command.peer, lowest, velocity, moved.motion.fallback]
			)
		)
		_rest_at(ctx, moved, moved.motion.fallback)
		return
	moved.position = lowest
	moved.velocity = velocity
	if velocity.length() >= rules.rest_speed_mps:
		moved.motion.slow_reports = 0
		return
	moved.motion.slow_reports += 1
	if moved.motion.slow_reports >= maxi(1, Ticks.from_seconds(rules.rest_s)):
		rest(ctx, moved)


## One tick of `peer`'s motion (LifeTicks, every tick, reports or not): once it has lasted
## PlayerRules.longest_motion_s it ends as at rest (§4, step 7).
static func count_motion(ctx: MatchContext, peer: int) -> void:
	var moving := ctx.state.player(peer)
	var rules := ctx.state.player_rules
	if moving == null or moving.motion == null or rules == null:
		return
	moving.motion.ticks += 1
	if moving.motion.ticks >= maxi(1, Ticks.from_seconds(rules.longest_motion_s)):
		rest(ctx, moving)


## `player`'s motion ends at its rest (KE15): the standing floor under its capsule at its point
## (WorldQuery.stand_floor_below from a capsule's radius up, lifted as Items.lifted lifts a point),
## else the fallback with an error (no floor: a level with a hole, §4, step 6); StopBody.
static func rest(ctx: MatchContext, player: PlayerState) -> void:
	var rules := ctx.state.player_rules
	var radius := rules.capsule_radius_m if rules != null else 0.0
	var found := ctx.world.stand_floor_below(Items.lifted(player.position + Vector3.UP * radius))
	if found == WorldQuery.NO_FLOOR:
		ctx.error(
			(
				"rest: no floor under the body of player %d at %s: it rests at %s"
				% [player.peer, player.position, player.motion.fallback]
			)
		)
		found = player.motion.fallback
	_rest_at(ctx, player, found)


## Ends `player`'s motion where it is, if it has one: StopBody lets server/ free the host's body.
## Its point and velocity stay as they are; the caller sets them.
static func stop_motion(ctx: MatchContext, player: PlayerState) -> void:
	if player == null or player.motion == null:
		return
	player.motion = null
	ctx.emit(StopBodyEvent.new(player.peer))


## Ends every motion (ResetMatch), in peer-id order, each with its StopBody.
static func stop_every_motion(ctx: MatchContext) -> void:
	for peer: int in ctx.state.peers():
		stop_motion(ctx, ctx.state.players[peer])


## `peer`, downed, dies: its body, Died, player_died, then both slots drop at the body.
static func die(ctx: MatchContext, peer: int) -> void:
	var dead := ctx.state.player(peer)
	if dead == null or dead.life != PlayerState.Life.DOWNED:
		ctx.error("die: player %d is not downed" % peer)
		return
	_to_dead(ctx, dead, "die")


## `peer`, living or downed, invulnerable or not, dies at once (RE6, RD7): as die(), and a living
## player's health falls to 0. A player who is neither (dead already, left, or unknown) is a rule
## error, logged; settle_kills() skips such a player before it calls this. A part in the middle of
## someone's command or a channel's hook queues the kill (kill_later) instead (RE17).
static func kill(ctx: MatchContext, peer: int) -> void:
	var victim := ctx.state.player(peer)
	if victim == null or not _killable(victim):
		ctx.error("kill: player %d is not living or downed" % peer)
		return
	if victim.health != 0:
		victim.health = 0
		SelfStatusFeed.touch(ctx.state, peer)
	if victim.sprinting:
		# A knockdown ends the sprint (knock_down); a kill from standing must too, with the ticks
		# since its last claim paid as its sprint's.
		if ctx.state.player_rules != null:
			StaminaLedger.settle_ahead(victim, ctx.state.player_rules, ctx.tick)
		victim.sprinting = false
	_to_dead(ctx, victim, "kill")


## Queues `peer`'s kill for the next settle_kills() (RE17): the end of the command, tick system or
## channel step running now. Queuing a player twice kills it once.
static func kill_later(ctx: MatchContext, peer: int) -> void:
	var queue := _kill_queue(ctx.state)
	if not queue.peers.has(peer):
		queue.peers.append(peer)


## Kills the queued players in peer-id order (RE17), skipping one no longer living or downed with
## no rule error; once the step has an outcome (MatchContext.step_has_outcome) the rest of the
## queue clears with no kill (RD16 (c)). Kills that a kill queues (its channels' stops) settle here
## too, in peer-id order after it. Match and Channels.advance call it.
static func settle_kills(ctx: MatchContext) -> void:
	var queue := _kill_queue(ctx.state)
	while not queue.peers.is_empty():
		var queued: Array[int] = queue.peers.duplicate()
		queue.peers.clear()
		queued.sort()
		for peer: int in queued:
			if ctx.step_has_outcome():
				queue.peers.clear()
				return
			var victim := ctx.state.player(peer)
			if victim != null and _killable(victim):
				kill(ctx, peer)


## Whether a kill is queued: Match settles only then, so a step with none builds no context.
static func kills_queued(state: MatchState) -> bool:
	return not _kill_queue(state).peers.is_empty()


## Drops every queued kill: a transition is moving the match on, and nothing dies after the step's
## outcome (RD16 (c)). Match calls it once the old phase has exited.
static func drop_kills(state: MatchState) -> void:
	_kill_queue(state).peers.clear()


## `peer`, downed, stands up where it lies (a completed raise): living with `health` whole points
## (at most PlayerRules.health), stamina kept, a new epoch, invulnerable. Revived (everyone), then
## its Correction, then its SelfStatus (at the end of the tick).
static func revive(ctx: MatchContext, peer: int, health: int) -> void:
	var revived := ctx.state.player(peer)
	if revived == null or revived.life != PlayerState.Life.DOWNED:
		ctx.error("revive: player %d is not downed" % peer)
		return
	var rules := ctx.state.player_rules
	if rules == null:
		ctx.error("revive: the mode has no PlayerRules")
		return
	# TargetDowned refuses a moving body (KD4 (a)): a motion here is a bug, ended where it is.
	stop_motion(ctx, revived)
	# The ticks since its last claim regenerated as a downed player's (it spends none).
	StaminaLedger.settle_ahead(revived, rules, ctx.tick)
	revived.life = PlayerState.Life.ALIVE
	revived.life_deadline = -1
	revived.knockdown_left = -1
	revived.health = mini(Ticks.thousandths(health), Ticks.thousandths(rules.health))
	revived.sprint_held = false
	revived.moving = false
	revived.velocity = Vector3.ZERO
	revived.epoch += 1
	make_invulnerable(ctx, peer)
	ctx.emit(RevivedEvent.new(peer))
	ctx.emit(CorrectionEvent.new(peer, revived.epoch, revived.position, revived.velocity))
	SelfStatusFeed.touch(ctx.state, peer)


## `peer`, dead, comes back at `at` (a respawn marker, which Respawn draws): its body goes, it is
## living with its role, full health and stamina, an empty hand and belt and a new epoch, and
## invulnerable (make_invulnerable). Respawned (everyone), then its Correction, then its SelfStatus
## (at the end of the tick).
static func respawn(ctx: MatchContext, peer: int, at: Vector3) -> void:
	var back := ctx.state.player(peer)
	if back == null or back.life != PlayerState.Life.DEAD:
		ctx.error("respawn: player %d is not dead" % peer)
		return
	var rules := ctx.state.player_rules
	if rules == null:
		ctx.error("respawn: the mode has no PlayerRules")
		return
	if not back.carried_items().is_empty():
		# The death dropped them (die); a full place is a rule error, and its item drops here.
		ctx.error("respawn: player %d still carries items %s" % [peer, back.carried_items()])
		Items.drop_carried(ctx, peer, Items.DEATH)
	ctx.state.bodies.erase(peer)
	back.life = PlayerState.Life.ALIVE
	back.life_deadline = -1
	back.health = Ticks.thousandths(rules.health)
	back.stamina = Ticks.thousandths(rules.stamina)
	# The ledger starts again at the respawn: nothing before it is settled as this life's.
	back.stamina_settled_tick = ctx.tick
	back.sprinting = false
	back.crouched = false
	back.sneaking = false
	back.posed = false
	back.sober()
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
## player_left, then both slots drop. A player who left already changes nothing.
static func leave(ctx: MatchContext, peer: int) -> void:
	var leaver := ctx.state.player(peer)
	if leaver == null or not leaver.is_present():
		return
	Channels.interrupt_involving(ctx, peer)
	# A leave ends the motion and leaves no body (§4).
	stop_motion(ctx, leaver)
	leaver.limp = null
	leaver.life = PlayerState.Life.LEFT
	leaver.life_deadline = -1
	leaver.knockdown_left = -1
	ctx.state.bodies.erase(peer)
	ctx.emit(PlayerLeftEvent.new(peer))
	var fact := Fact.new(Facts.PLAYER_LEFT)
	fact.player = peer
	ctx.raise_fact(fact)
	Items.drop_carried(ctx, peer, Items.LEAVE)


## `dead` (living or downed: the caller checked) dies: every channel it runs or is the target of
## stops first, its body on the floor below, Died, player_died, then both slots drop at the body.
static func _to_dead(ctx: MatchContext, dead: PlayerState, what: String) -> void:
	var peer := dead.peer
	Channels.interrupt_involving(ctx, peer)
	# A death during the motion ends it where it is (KD8 (a)): the body on the floor below its
	# point, and its items with it.
	stop_motion(ctx, dead)
	dead.limp = null
	var body := _floor_at(ctx, dead, what)
	ctx.state.bodies[peer] = body
	dead.life = PlayerState.Life.DEAD
	if dead.posed:
		# A kill from the chair (the car's drop) stands the body up: a corpse is never shown
		# seated, and its client learns it in its SelfStatus (#1383).
		dead.posed = false
		SelfStatusFeed.touch(ctx.state, peer)
	var rules := ctx.state.player_rules
	dead.life_deadline = ctx.tick + Ticks.from_seconds(rules.respawn_s) if rules != null else -1
	dead.knockdown_left = -1
	dead.position = body
	dead.velocity = Vector3.ZERO
	ctx.emit(DiedEvent.new(peer, body))
	var fact := Fact.new(Facts.PLAYER_DIED)
	fact.player = peer
	fact.position = body
	ctx.raise_fact(fact)
	# The items rest at the body itself, not at a second floor query from the same point.
	Items.place_carried(ctx, peer, body, Items.DEATH)


## `peer`, living, goes limp for `limp_s` (#1393; ARCHITECTURE §7.1.21; GoLimp): a rag-doll the
## host's physics moves, while its life stays ALIVE (not downed: no KnockedDown, no deadline, no
## health change). Every channel it runs or is the target of stops first, its stamina is settled
## as the living player it was, and its sprint, crouch, sneak and seat end; it keeps its drunk
## value, its hand and its belt. A new epoch, then a BodyMotion with the floor below as its fallback
## rest, its Correction (the player only) and LaunchBody (server) at its point with `launch` as its
## velocity (none for the drink; the knock-out blow's for a hit, as a knockdown's, #1439). `refill`:
## the player gets up at full health (LimpState.refill: a hit's limp at 0 health).
## A player limp already stays as it is; one not alive is a rule error, logged.
static func go_limp(
	ctx: MatchContext, peer: int, limp_s: float, refill := false, launch := Vector3.ZERO
) -> void:
	var player := ctx.state.player(peer)
	if player == null or not player.is_alive():
		ctx.error("go_limp: player %d is not alive" % peer)
		return
	if player.is_limp():
		return
	var rules := ctx.state.player_rules
	if rules == null:
		ctx.error("go_limp: the mode has no PlayerRules")
		return
	Channels.interrupt_involving(ctx, peer)
	var lies_at := _floor_at(ctx, player, "go_limp")
	StaminaLedger.settle_ahead(player, rules, ctx.tick)
	player.sprinting = false
	player.crouched = false
	player.sneaking = false
	player.posed = false
	player.sprint_held = false
	player.moving = false
	player.limp = LimpState.new(ctx.tick + maxi(1, Ticks.from_seconds(limp_s)))
	player.limp.refill = refill
	player.epoch += 1
	player.velocity = launch if launch.is_finite() else Vector3.ZERO
	player.motion = BodyMotion.new(player.epoch, lies_at)
	ctx.emit(CorrectionEvent.new(peer, player.epoch, player.position, player.velocity))
	ctx.emit(LaunchBodyEvent.new(peer, player.epoch, player.position, player.velocity))
	SelfStatusFeed.touch(ctx.state, peer)


## `peer`, limp, stands up by itself where its body lies (LimpTicks at LimpState.until, EndLimps):
## a moving body rests first (rest(): the standing floor under it, StopBody); then the limp ends,
## a new epoch and its Correction (the player only), as a placement for the movement rule. No event
## for the others: the snapshot's limp flag drops. Its drunk value stays; a hit's limp
## (LimpState.refill) gets up at full health (#1439). A player not limp is left as it is.
static func get_up(ctx: MatchContext, peer: int) -> void:
	var player := ctx.state.player(peer)
	if player == null or not player.is_limp():
		return
	if player.motion != null:
		rest(ctx, player)
	var refill := player.limp.refill
	player.limp = null
	if refill:
		restore_health(ctx, peer)
	var rules := ctx.state.player_rules
	if rules != null:
		StaminaLedger.settle_ahead(player, rules, ctx.tick)
	player.sprint_held = false
	player.moving = false
	player.velocity = Vector3.ZERO
	player.epoch += 1
	ctx.emit(CorrectionEvent.new(peer, player.epoch, player.position, player.velocity))
	SelfStatusFeed.touch(ctx.state, peer)


## `peer`'s limp body is pushed (LimpTicks): it moves on from its point at `velocity`, a fresh
## BodyMotion of the same epoch (its counters from 0: the longest motion counts per push; a body at
## rest starts again) and LaunchBody (server), which replaces the host's body. The epoch stays: no
## report of the replaced body can come (server/ reports only the live one), and the limp player
## needs no Correction. A player not limp is a rule error, logged.
static func push_limp(ctx: MatchContext, peer: int, velocity: Vector3) -> void:
	var body := ctx.state.player(peer)
	if body == null or not body.is_limp() or not velocity.is_finite():
		ctx.error("push_limp: player %d is not limp, or the push %s" % [peer, velocity])
		return
	var fallback := body.motion.fallback if body.motion != null else _floor_at(ctx, body, "push")
	body.velocity = velocity
	body.motion = BodyMotion.new(body.epoch, fallback)
	body.limp.push_tick = ctx.tick
	ctx.emit(LaunchBodyEvent.new(peer, body.epoch, body.position, velocity))


## Ends `player`'s limp, if it has one, with no get-up: its body's motion ends (StopBody) and the
## caller places it (a placement, a knockdown). A hit's limp (LimpState.refill) ends at full health
## when `refill` (a placement, a leave pass true; a knockdown passes false: the downed keep health,
## #1439). Nothing when it is not limp.
static func clear_limp(ctx: MatchContext, player: PlayerState, refill: bool) -> void:
	if player == null or not player.is_limp():
		return
	var refilled := refill and player.limp.refill
	player.limp = null
	stop_motion(ctx, player)
	if refilled:
		restore_health(ctx, player.peer)


## `peer`, living, back at full health (PlayerRules.health): its SelfStatus touched. A hit's limp at
## its end (get_up, clear_limp) and EndLimps.restore_health (#1439). A player not alive, or at full
## health already, is left as it is.
static func restore_health(ctx: MatchContext, peer: int) -> void:
	var player := ctx.state.player(peer)
	var rules := ctx.state.player_rules
	if player == null or not player.is_alive() or rules == null:
		return
	var full := Ticks.thousandths(rules.health)
	if player.health >= full:
		return
	player.health = full
	SelfStatusFeed.touch(ctx.state, peer)


static func _rest_at(ctx: MatchContext, player: PlayerState, at: Vector3) -> void:
	player.position = at
	player.velocity = Vector3.ZERO
	stop_motion(ctx, player)


static func _killable(player: PlayerState) -> bool:
	return player.life == PlayerState.Life.ALIVE or player.life == PlayerState.Life.DOWNED


static func _kill_queue(state: MatchState) -> KillQueue:
	return (
		state.part_state(KILL_QUEUE_KEY, func() -> RefCounted: return KillQueue.new()) as KillQueue
	)


## The floor below `player`'s last accepted position; where it is, logged, when there is none.
static func _floor_at(ctx: MatchContext, player: PlayerState, what: String) -> Vector3:
	var found := ctx.world.floor_below(Items.lifted(player.position))
	if found == WorldQuery.NO_FLOOR:
		ctx.error("%s: no floor below %s for player %d" % [what, player.position, player.peer])
		return player.position
	return found
