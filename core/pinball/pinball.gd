class_name Pinball
extends RefCounted
## The lobby's pinball machine (#1398; ARCHITECTURE §7.1.22, §9.4; GDD §3 "The pinball"): one
## player at a time works both flippers while the others watch; the machine shows this lobby's best
## score and the name of the player who made it; it cannot be nudged (no such intent, no TILT).
##
## The machine is a station of no task type (StationTicks places it); its Interact rule seats the
## actor and starts a game (UsePinball), or gives the seat up when the actor is the seated player.
## The game (who sits, the balls, the score, the flippers) is per-part state (MatchState.part_state,
## cleared by ResetMatch); the best score, its owner's name and the games' count are session state
## (MatchState.session_part_state, kept by ResetMatch), so the best stays from match to match while
## the lobby stays, and is gone when the host closes it. The owner's name is copied when the game
## starts, so it stays when the owner leaves.
##
## The table (the ball's physics, server/, #1399) reports into core through four commands that
## server/ originates (Intents.TABLE_REPORTS), each naming the game it belongs to (`game`, the
## serial PinballState carries): BallLaunched, TargetHit (`target`, a PinballTarget's id) and
## BallLost (report()), and BallMoved, the ball's place for the snapshots (shown_ball()). A report
## of a game that is not the live one (none seated, or another game since) is ignored: a report in
## flight at a release is a normal race. Every change but BallMoved goes out as one public
## PinballState, the whole state (announce()).
##
## A game ends (end(): the best updated, the seat freed) after its last ball, on the seated
## player's Interact again (UsePinball), through PinballTicks when the seated player is no longer
## present, alive and standing, or out of the machine's cylinder (walked away; a knockdown, a death,
## a limp, a leave), and through EndPinball on a row out of the phases that list PinballTicks (no
## seat survives into a match). The score of a game that ends early counts for the best too.

## Its key in MatchState's per-part state (the game) and session state (the best).
const PART_KEY := &"pinball"
## The reason a Flippers gets from anyone but the seated, standing player (PinballSeated).
const NOT_SEATED := &"not_seated"
## The highest score a game reaches: the display's nine digits (the wire carries a u32).
const MAX_SCORE := 999_999_999


## The machine's game: the last one stays (its score, no player) until the next starts.
class Machine:
	extends RefCounted
	## The game's serial in the session (Session.games when it started), 0 before the first.
	var serial := 0
	## The seated player's peer, or -1: no game running.
	var player := -1
	## The seated player's name when the game started: the best's owner's name if that player left.
	var player_name := ""
	## The station the game is played at, or -1.
	var station := -1
	var balls_left := 0
	## Whether a ball is on the table (BallLaunched, until BallLost).
	var in_play := false
	## Whether the ball on the table has a place (a BallMoved since its BallLaunched), and the place:
	## table-local metres (Intents.BALL_MOVED), public in every snapshot (#1399, §5).
	var ball_placed := false
	var ball := Vector3.ZERO
	var score := 0
	var left := false
	var right := false
	## The targets' points, target id -> points: UsePinball's data, copied when the game starts.
	var points: Dictionary[StringName, int] = {}
	## The players present at the last PinballState: PinballTicks tells the state again when one is
	## missing (a joiner; every player after ResetMatch made a new Machine).
	var told: Dictionary[int, bool] = {}


## What the session keeps (ResetMatch does not clear it; nothing is written to disk).
class Session:
	extends RefCounted
	var best := 0
	var best_name := ""
	## How many games the session started: the next game's serial is one more.
	var games := 0


## The machine's game, made on first use.
static func game(state: MatchState) -> Machine:
	return state.part_state(PART_KEY, func() -> RefCounted: return Machine.new()) as Machine


## The session's best score and games' count, made on first use.
static func session(state: MatchState) -> Session:
	return state.session_part_state(PART_KEY, func() -> RefCounted: return Session.new()) as Session


## The seated player's peer, or -1.
static func seated(state: MatchState) -> int:
	return game(state).player


## Whether `player` may keep the seat: present, alive and standing (not limp).
static func standing(player: PlayerState) -> bool:
	return (
		player != null
		and player.is_present()
		and player.life == PlayerState.Life.ALIVE
		and not player.is_limp()
	)


## The actor takes the seat at station `station_id` and a game starts: `balls` balls, score 0, no
## ball on the table, both flippers down, the targets' points copied. One PinballState.
static func start(
	ctx: MatchContext, station_id: int, balls: int, targets: Array[PinballTarget]
) -> void:
	var played := game(ctx.state)
	var kept := session(ctx.state)
	var actor := ctx.actor_state()
	kept.games += 1
	played.serial = kept.games
	played.player = ctx.actor
	played.player_name = actor.name if actor != null else ""
	played.station = station_id
	played.balls_left = balls
	played.in_play = false
	played.score = 0
	played.left = false
	played.right = false
	played.points.clear()
	for target: PinballTarget in targets:
		if target != null:
			played.points[target.id] = target.points
	announce(ctx)


## The running game ends: a score above the best (strictly: a tie keeps the older) replaces it
## with the player's name; the seat is freed, the ball and the flippers cleared, the score kept for
## the display. One PinballState; nothing when no game runs.
static func end(ctx: MatchContext) -> void:
	var played := game(ctx.state)
	if played.player < 0:
		return
	var kept := session(ctx.state)
	if played.score > kept.best:
		kept.best = played.score
		# The name now (a SetProfile mid-game renames the owner); the copy from the game's start
		# only for a player already gone.
		var owner := ctx.state.player(played.player)
		kept.best_name = owner.name if owner != null else played.player_name
	played.player = -1
	played.player_name = ""
	played.station = -1
	played.balls_left = 0
	played.in_play = false
	played.ball_placed = false
	played.left = false
	played.right = false
	announce(ctx)


## The seated player's flippers are now `left` and `right`: one PinballState when one changed, none
## when both are as they were (the client sends its held state again; a lost one sticks nothing).
static func set_flippers(ctx: MatchContext, left: bool, right: bool) -> void:
	var played := game(ctx.state)
	if played.player < 0 or (played.left == left and played.right == right):
		return
	played.left = left
	played.right = right
	announce(ctx)


## A table report (Intents.TABLE_REPORTS; Match._dispatch, in every phase) of the game `game`:
## BallLaunched puts a ball on the table while none is and balls are left; TargetHit adds the
## target's points while a ball is on the table; BallLost takes the ball off and one ball away, and
## the last one ends the game. A report of a game that is not the live one, or one that does not
## fit (a second launch, a hit or a loss with no ball on the table) is ignored, with no event; a
## target id the game's data does not hold is a table bug (ctx.error). Each change: one
## PinballState. BallMoved (#1399) only places the ball on the table for the snapshots
## (shown_ball()): no event, the ball's place is no PinballState.
static func report(ctx: MatchContext, command: MatchCommand) -> void:
	var played := game(ctx.state)
	if played.player < 0 or command.get_int("game", -1) != played.serial:
		return
	match command.kind:
		Intents.BALL_MOVED:
			var position := command.get_vector3("position")
			if played.in_play and position.is_finite():
				played.ball = position
				played.ball_placed = true
			return
		Intents.BALL_LAUNCHED:
			if played.in_play or played.balls_left <= 0:
				return
			played.in_play = true
			played.ball_placed = false
		Intents.TARGET_HIT:
			var target := StringName(command.get_string("target"))
			if not played.points.has(target):
				ctx.error("TargetHit: the pinball has no target %s" % target)
				return
			if not played.in_play:
				return
			played.score = mini(played.score + played.points[target], MAX_SCORE)
		Intents.BALL_LOST:
			if not played.in_play:
				return
			played.in_play = false
			played.ball_placed = false
			played.balls_left -= 1
			if played.balls_left <= 0:
				end(ctx)
				return
	announce(ctx)


## The ball every snapshot shows (#1399, §5: public, the same for every viewer): {"ball": its
## table-local place} while a game's ball is on the table and the table has placed it; else empty,
## and the snapshot holds no ball.
static func shown_ball(state: MatchState) -> Dictionary:
	var played := game(state)
	if played.player < 0 or not played.in_play or not played.ball_placed:
		return {}
	return {"ball": played.ball}


## Whether the session's machine has anything to show: a game was ever started (before that every
## peer's default is the state, so nothing is told).
static func started(state: MatchState) -> bool:
	return session(state).games > 0


## Whether every present player was told the current state.
static func told_all(state: MatchState) -> bool:
	var told := game(state).told
	for peer: int in state.peers():
		if state.players[peer].is_present() and not told.has(peer):
			return false
	return true


## One PinballState (everyone) with the whole state; every present player is now told.
static func announce(ctx: MatchContext) -> void:
	var played := game(ctx.state)
	played.told.clear()
	for peer: int in ctx.state.peers():
		if ctx.state.players[peer].is_present():
			played.told[peer] = true
	ctx.emit(state_event(ctx.state))


## The machine's whole state as an event.
static func state_event(state: MatchState) -> PinballStateEvent:
	var played := game(state)
	var kept := session(state)
	var shown := PinballStateEvent.new()
	shown.game = played.serial
	shown.player = played.player
	shown.left = played.left
	shown.right = played.right
	shown.in_play = played.in_play
	shown.score = played.score
	shown.balls_left = played.balls_left
	shown.best = kept.best
	shown.best_name = kept.best_name
	return shown


## Every rule of `mode` (its actions, its roles', its item kinds' and its station kinds') that holds
## `part` among its conditions or effects: where a pinball part sits (its check()).
static func rules_holding(mode: GameMode, part: ContentPart) -> Array[Rule]:
	var lists: Array[Array] = [mode.actions]
	for role: GameRole in mode.roles:
		if role != null:
			lists.append(role.actions)
	for kind: ItemKind in mode.item_kinds:
		if kind != null:
			lists.append(kind.actions)
			lists.append(kind.target_actions)
	for kind: StationKind in Stations.kinds_in(mode):
		lists.append(kind.actions)
	var found: Array[Rule] = []
	for rules: Array in lists:
		for entry: Variant in rules:
			var rule := entry as Rule
			if rule == null or found.has(rule):
				continue
			if _rule_holds(rule, part):
				found.append(rule)
	return found


## Whether `rule` holds `part` among its effects or its conditions. Each typed array's `has` is
## given only its own element type: a RuleEffect asked of Array[Condition] prints an engine error.
static func _rule_holds(rule: Rule, part: ContentPart) -> bool:
	if part is RuleEffect:
		return rule.effects.has(part as RuleEffect)
	if part is Condition:
		return rule.conditions.has(part as Condition)
	return false


## Whether `rule` holds a condition of class `type` that is not negated.
static func holds_condition(rule: Rule, type: Script) -> bool:
	for condition: Condition in rule.conditions:
		if condition != null and condition.get_script() == type and not condition.negate:
			return true
	return false
