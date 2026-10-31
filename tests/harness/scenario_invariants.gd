class_name ScenarioInvariants
extends RefCounted
## The §5 invariants over every bot's stream (ARCHITECTURE §5, §9.7), written independently of the
## events' declared audiences: each check reads the match state's truth (roles, life states, who
## is present), never an event's audience(), so a wrong declaration (Teammates declared to
## everyone, say) fails here even though view_of agrees with it.
## - A crew member learns one role, its own, and a player of a role that knows its teammates
##   learns only that role's players; every role it learns is the truth when it learns it.
## - Nobody gets another player's health, stamina or damage (Damaged, SelfStatus), and no avatar in
##   a snapshot holds a field outside the public ones (AVATAR_FIELDS).
## - A Rejected reaches exactly the peer whose command was just applied.
## - Every present player receives the same task events (StationPlaced, ItemSpawned,
##   PackageDelivered, TaskState, TaskProgress, ZoneProgress, ItemVanished, ItemChanged, the
##   Generator's SwitchChanged and ButtonPressed, #797, Cooking's OrderPosted and HerbsDealt, #772,
##   the car repair's LiftChanged and PartNeeded, #807, the photo task's FilmLoaded and
##   ShotTaken, #781, Cooking's GrillLoaded and IngredientPlaced, #773, and the car repair's
##   FitChanged and PartFitted, #808, the photo task's PhotoPrinted and PhotoHung, #782, and
##   Cooking's BurgerPlated and BurgerServed, #1101, and the ship engine's EngineProblemOpened,
##   EngineProblemFixed and EngineBlast, #1453, and its problem kinds' GillFlipped, BreakerChain
##   and CrystalChanged, #1461).
## - No event and no snapshot holds the session seed or a match seed.
## - The own-avatar invariant (the knockdown rework's KE5, §9, #847): per tick, a peer's snapshot
##   holds its own avatar exactly when its player is knocked down or limp (#1393), read from the
##   life state and PlayerState.limp, never from Snapshots.for_peer (own_avatar_problem).
## - Per tick, no peer's snapshot holds a dead player's avatar (the dead have none). The voice
##   invariant (§6): no peer's speakers include a downed or dead speaker; a downed peer hears only
##   living speakers; a dead peer's speakers are empty.
## - The distance invariant (§5, E45): per tick, every speaker a peer hears stands within the
##   phase's hearing radius (VoiceRule.radius_of the mode's rule for the phase), between the two
##   last accepted positions in 3D, compared as VoiceRule.within compares them, so a pair at the
##   edge passes; a phase whose radius is 0 hears nobody. Written apart from the rule's hears and
##   speakers_of: a rule that routes past its own radius fails here though view_of agrees with it.
## - Nothing reaches only the dead: every event a dead peer receives is either for it alone (an
##   event for one peer, FOR_ONE or a one-peer declaration, naming it) or also reaches every living
##   peer present then.
## - The crouch invariant (the crouch ADR, KE1; KE10 as #991 amended it, #790): per tick, no
##   snapshot shows an avatar crouched unless its player is alive (crouch_problem); the crouch
##   plays in every phase and on every map. The sneak alike (#990): no snapshot shows an avatar
##   sneaking unless its player is alive and not crouched (sneak_problem); none posed unless its
##   player is alive (pose_problem, #1296). The drunk value alike (#1390): no snapshot shows an
##   avatar's `drunk` other than its player's PlayerState.drunk, outside 0..PlayerRules.drunk_max,
##   or above 0 in a phase that lists no DrunkTicks (drunk_problem): the bar is the hall's alone.
##   The limp alike (#1393): no snapshot shows an avatar's `limp` other than its player's
##   is_limp(), a limp player not alive, or one in a phase that lists no LimpTicks (limp_problem).
## - No Damaged reaches a player whose invulnerability runs (PlayerState.invulnerable_until, after a
##   respawn or a revive: strikes skip it, M4-3).
## - The scenario's `never` events reach nobody they name.
## - The record invariant (the photo ADR §8, #781): every row of a ShotTaken names a present peer
##   ALIVE or knocked down at the shot, once, at its accepted position now (the shot's own call),
##   and within the mode's PhotoTask range_m plus PhotoTask.RECORD_MARGIN_M of the lens (the camera
##   station's position raised by the eye height): no claim's step of slack (record_step), which
##   only LeakCheck, seeing positions at the ends of ticks, needs (#788). Written apart from
##   PhotoTask's record builder (record_problems), so a builder that gives a row to a player
##   standing elsewhere fails here though view_of agrees.

const TASK_EVENTS: Array[StringName] = [
	&"StationPlaced",
	&"ItemSpawned",
	&"PackageDelivered",
	&"TaskState",
	&"TaskProgress",
	&"ZoneProgress",
	&"ItemVanished",
	&"SwitchChanged",
	&"ButtonPressed",
	&"ItemChanged",
	&"OrderPosted",
	&"HerbsDealt",
	&"LiftChanged",
	&"PartNeeded",
	&"FilmLoaded",
	&"ShotTaken",
	&"GrillLoaded",
	&"IngredientPlaced",
	&"FitChanged",
	&"PartFitted",
	&"PhotoPrinted",
	&"PhotoHung",
	&"BurgerPlated",
	&"BurgerServed",
	&"EngineProblemOpened",
	&"EngineProblemFixed",
	&"EngineBlast",
	&"GillFlipped",
	&"BreakerChain",
	&"CrystalChanged",
]
const PRIVATE_NUMBERS: Array[StringName] = [&"Damaged", &"SelfStatus"]
## What anyone may see of another player (§4.2); health and stamina are never avatar fields.
const AVATAR_FIELDS: Array[String] = [
	"position",
	"velocity",
	"facing",
	"downed",
	"invulnerable",
	"crouched",
	"sneaking",
	"posed",
	"limp",
	"drunk",
	"held_item",
	"belt_item",
	"belt_item2",
]

## The peer whose command the runner applies now, or 0 outside a command (a tick, the start).
var sender := 0

var _game: Match
var _scenario: BotScenario
var _peers: ScenarioPeers
var _seeds: Array[int] = []
## keys() for a numbers map of `_keys_for` entries (-1: not built yet).
var _keys := PackedStringArray()
var _keys_for := -1


## `peers` is the runner's map from bot number to peer id (the `never` check); the core runner's by
## default.
func _init(game: Match, scenario: BotScenario, peers: ScenarioPeers = null) -> void:
	_game = game
	_scenario = scenario
	_peers = peers if peers != null else ScenarioPeers.core(scenario.bots)
	_seeds.append(scenario.session_seed)


## The broken invariants of one Match call (HostSession's observer, §4.5): its command's sender,
## each event of its slice, and, after a tick (no command), the tick's snapshots and voice routing.
func check_call(command: MatchCommand, slice: Array[EmittedEvent]) -> PackedStringArray:
	var found := PackedStringArray()
	sender = command.peer if command != null else 0
	for emitted: EmittedEvent in slice:
		found.append_array(check_event(emitted))
	if command == null:
		found.append_array(check_tick())
	sender = 0
	return found


## The session seed and every match seed seen so far: no message may hold one.
func seeds() -> Array[int]:
	return _seeds.duplicate()


## Every return key a Hello carried: each bot's (ScenarioBot.key_of) and each the host keeps (its
## numbers map; the chaos hostile's too), and the one no player holds that a hostile's Hello may
## carry (ScenarioBot.key_of(bots + 1)). No message may hold one (§3.5, the returning-players ADR).
## The list is rebuilt only when the host's numbers map grew (asked once per event and per tick).
func keys() -> PackedStringArray:
	var held := _game.state.numbers.size()
	if held == _keys_for:
		return _keys
	_keys = PackedStringArray()
	for number in range(1, _scenario.bots + 2):
		_keys.append(ScenarioBot.key_of(number))
	for key: String in _game.state.numbers:
		if not _keys.has(key):
			_keys.append(key)
	_keys_for = held
	return _keys


## The broken invariants of one emitted event, checked right after the step that emitted it.
func check_event(emitted: EmittedEvent) -> PackedStringArray:
	var found := PackedStringArray()
	var event := emitted.event
	var name := event.event_name()
	var state := _game.state
	if event is LoadMatchEvent:
		var seed_now := state.rng.match_seed()
		if not _seeds.has(seed_now):
			_seeds.append(seed_now)
	if event is RoleAssignedEvent:
		var assigned := event as RoleAssignedEvent
		for peer: int in emitted.recipients:
			_learn_role(peer, assigned.peer, assigned.role, found)
	elif event is TeammatesEvent:
		var teammates := event as TeammatesEvent
		for peer: int in emitted.recipients:
			for other: int in teammates.peers:
				_learn_role(peer, other, teammates.role, found)
	if PRIVATE_NUMBERS.has(name):
		var owner: int = event.get("peer")
		for peer: int in emitted.recipients:
			if peer != owner:
				found.append("peer %d received %s of peer %d" % [peer, name, owner])
	if event is RejectedEvent and emitted.recipients != PackedInt32Array([sender]):
		found.append("Rejected reached %s, not the sender %d" % [emitted.recipients, sender])
	if TASK_EVENTS.has(name):
		var present := PackedInt32Array(state.present_peers())
		if emitted.recipients != present:
			found.append(
				"%s reached %s, not every present player %s" % [name, emitted.recipients, present]
			)
	for seed_value: int in _seeds:
		if holds_int(event.to_dict(), seed_value):
			found.append("%s holds a seed" % name)
	if holds_text(event.to_dict(), keys()):
		found.append("%s holds a return key" % name)
	found.append_array(_check_dead_recipients(emitted))
	if event is DamagedEvent:
		for peer: int in emitted.recipients:
			var victim := state.player(peer)
			if victim != null and victim.is_invulnerable(emitted.tick):
				found.append(
					(
						"peer %d received Damaged at tick %d while invulnerable until tick %d"
						% [peer, emitted.tick, victim.invulnerable_until]
					)
				)
	for never: NeverEvent in _scenario.never:
		if not ScenarioPlay.event_matches(event, never.event, never.fields, _peers):
			continue
		for peer: int in emitted.recipients:
			if never.bot == 0 or _peers.peers_of(never.bot).has(peer):
				found.append("peer %d received %s, which the scenario says never" % [peer, name])
	if event is ShotTakenEvent:
		found.append_array(_check_record(event as ShotTakenEvent))
	return found


## The broken invariants of one tick's snapshots and voice routing.
func check_tick() -> PackedStringArray:
	var found := PackedStringArray()
	var state := _game.state
	var radius := phase_radius(_game)
	for peer: int in state.present_peers():
		var snapshot := _game.snapshot_for(peer)
		var avatars: Dictionary = snapshot.get("avatars", {})
		for seed_value: int in _seeds:
			if holds_int(snapshot, seed_value):
				found.append("peer %d's snapshot holds a seed" % peer)
		if holds_text(snapshot, keys()):
			found.append("peer %d's snapshot holds a return key" % peer)
		for other: int in avatars:
			var avatar: Dictionary = avatars[other]
			for field: Variant in avatar:
				if not AVATAR_FIELDS.has(str(field)):
					found.append("peer %d's snapshot shows %s of peer %d" % [peer, field, other])
			var crouch := crouch_problem(_game, other, avatar)
			if crouch != "":
				found.append("peer %d's snapshot %s" % [peer, crouch])
			var sneak := sneak_problem(_game, other, avatar)
			if sneak != "":
				found.append("peer %d's snapshot %s" % [peer, sneak])
			var pose := pose_problem(_game, other, avatar)
			if pose != "":
				found.append("peer %d's snapshot %s" % [peer, pose])
			var drunk := drunk_problem(_game, other, avatar)
			if drunk != "":
				found.append("peer %d's snapshot %s" % [peer, drunk])
			var limp := limp_problem(_game, other, avatar)
			if limp != "":
				found.append("peer %d's snapshot %s" % [peer, limp])
		# A phase that sends no snapshot (End, Loading) has none to check.
		var player := _game.state.player(peer)
		var downed := (
			_life_of(peer) == PlayerState.Life.DOWNED or (player != null and player.is_limp())
		)
		var own := own_avatar_problem(peer, avatars, downed) if not snapshot.is_empty() else ""
		if own != "":
			found.append("peer %d's snapshot %s" % [peer, own])
		var speakers := _game.speakers_for(peer)
		found.append_array(_check_voice(peer, speakers))
		found.append_array(_check_distance(peer, speakers, radius))
		for other: int in avatars:
			if _life_of(other) == PlayerState.Life.DEAD:
				found.append("peer %d sees dead %d in its snapshot" % [peer, other])
	return found


## The longest horizontal step one movement claim may take under `rules` (MovementRule's travel
## bound at its widest: the most ticks of credit sprinting, the push allowance, the slack), the
## record invariant's tolerance between a row and an accepted position.
static func record_step(rules: PlayerRules) -> float:
	if rules == null:
		return 0.0
	var ticks := MovementRule.MAX_TICK_CREDIT + MovementRule.PUSH_TICKS
	return ticks * rules.sprint_speed_mps / Ticks.RATE + MovementRule.DISTANCE_SLACK_M


## The mode's PhotoTask whose camera kind has the id `kind`, or null.
static func photo_task_of(mode: GameMode, kind: StringName) -> PhotoTask:
	if mode == null or kind.is_empty():
		return null
	for type: TaskType in mode.task_types:
		var photo := type as PhotoTask
		if photo != null and photo.camera != null and photo.camera.id == kind:
			return photo
	return null


## The record invariant's broken parts (the photo ADR §8) for a ShotTaken's `rows` (its record, as
## sent or as decoded): each row's peer is in `living` (present and ALIVE or knocked down at the
## shot) and named once; its position lies within `step_m` horizontally of the peer's position in
## one of `accepted` (peer -> Vector3 each: the accepted positions the shot falls between) and
## within `range_m` + PhotoTask.RECORD_MARGIN_M + `step_m` of `lens`. A millimetre of slack covers
## the wire's 32-bit floats.
static func record_problems(
	rows: Array,
	lens: Vector3,
	range_m: float,
	step_m: float,
	living: PackedInt32Array,
	accepted: Array[Dictionary]
) -> PackedStringArray:
	const SLACK_M := 0.001
	var found := PackedStringArray()
	var named := PackedInt32Array()
	for row: Variant in rows:
		var fields: Dictionary = row if row is Dictionary else {}
		var peer: int = fields.get("peer", 0) if fields.get("peer") is int else 0
		var at: Vector3 = fields.get("position") if fields.get("position") is Vector3 else lens
		if not living.has(peer):
			found.append("a ShotTaken row names peer %d, not alive or downed at the shot" % peer)
			continue
		if named.has(peer):
			found.append("a ShotTaken names peer %d twice" % peer)
		named.append(peer)
		var bound := range_m + PhotoTask.RECORD_MARGIN_M + step_m + SLACK_M
		if at.distance_to(lens) > bound:
			found.append(
				(
					"a ShotTaken row puts peer %d at %s, %.3f m from the lens at %s, beyond %.3f m"
					% [peer, at, at.distance_to(lens), lens, bound]
				)
			)
		var near := false
		for positions: Dictionary in accepted:
			if not positions.has(peer):
				continue
			var was: Vector3 = positions[peer]
			if Vector2(at.x - was.x, at.z - was.z).length() <= step_m + SLACK_M:
				near = true
		if not near:
			found.append(
				(
					"a ShotTaken row puts peer %d at %s, a step away from every accepted position"
					% [peer, at]
				)
			)
	return found


## The record invariant over a ShotTaken just emitted: the lens from the camera station and the
## mode's eye height, the range from the mode's PhotoTask whose camera kind it is, the life states
## and the positions now.
func _check_record(shot: ShotTakenEvent) -> PackedStringArray:
	var state := _game.state
	var station: StationState = state.stations.get(shot.station)
	var rules := _game.mode.player_rules
	var task := photo_task_of(_game.mode, station.kind.id if station != null else &"")
	if task == null or rules == null:
		return PackedStringArray(
			["ShotTaken names station %d, no camera of a PhotoTask" % shot.station]
		)
	var lens := station.position + Vector3.UP * rules.eye_height_m
	var living := PackedInt32Array()
	for peer: int in state.present_peers():
		var life := _life_of(peer)
		if life == PlayerState.Life.ALIVE or life == PlayerState.Life.DOWNED:
			living.append(peer)
	# The check runs in the shot's own Match call (check_call), so the positions now are those the
	# record was taken from, with no claim's step of slack: LeakCheck needs that step, as it sees the
	# positions only at the ends of ticks; here it would widen the lens's bound by some 70 m, more
	# than the House, and a row for a player standing anywhere on it would pass (#788).
	var accepted: Array[Dictionary] = [_positions_now()]
	return record_problems(shot.record, lens, task.range_m, 0.0, living, accepted)


## Each present player's accepted position now.
func _positions_now() -> Dictionary[int, Vector3]:
	var positions: Dictionary[int, Vector3] = {}
	for peer: int in _game.state.present_peers():
		positions[peer] = _game.state.player(peer).position
	return positions


## The recipients of `emitted` who are dead now and got it although some living peer present did
## not, unless it is an event for one peer naming that recipient (LeakCheck.for_one).
func _check_dead_recipients(emitted: EmittedEvent) -> PackedStringArray:
	var found := PackedStringArray()
	var event := emitted.event
	var living := PackedInt32Array()
	for peer: int in _game.state.present_peers():
		if _life_of(peer) == PlayerState.Life.ALIVE:
			living.append(peer)
	for peer: int in emitted.recipients:
		if _life_of(peer) != PlayerState.Life.DEAD:
			continue
		if LeakCheck.for_one(event) and event.get("peer") is int and event.get("peer") == peer:
			continue
		for other: int in living:
			if not emitted.recipients.has(other):
				found.append(
					(
						"dead peer %d received %s, which living peer %d did not"
						% [peer, event.event_name(), other]
					)
				)
	return found


## The voice invariant's broken parts for `peer`'s `speakers` this tick (§6), from the life
## states alone, never the voice rule.
func _check_voice(peer: int, speakers: PackedInt32Array) -> PackedStringArray:
	var found := PackedStringArray()
	var life := _life_of(peer)
	if life == PlayerState.Life.DEAD and not speakers.is_empty():
		found.append("dead peer %d hears %s" % [peer, speakers])
	for speaker: int in speakers:
		var mouth := _life_of(speaker)
		if mouth == PlayerState.Life.DOWNED:
			found.append("peer %d hears downed %d" % [peer, speaker])
		if mouth == PlayerState.Life.DEAD:
			found.append("peer %d hears dead %d" % [peer, speaker])
		if life == PlayerState.Life.DOWNED and mouth != PlayerState.Life.ALIVE:
			found.append("downed peer %d hears %d, who is not living" % [peer, speaker])
	return found


## The distance invariant's broken parts for `peer`'s `speakers` this tick, against the phase's
## hearing radius `radius`, from the last accepted positions alone, never the voice rule.
func _check_distance(peer: int, speakers: PackedInt32Array, radius: float) -> PackedStringArray:
	var found := PackedStringArray()
	var state := _game.state
	for speaker: int in speakers:
		var ear := state.player(peer)
		var mouth := state.player(speaker)
		if ear == null or mouth == null:
			found.append("peer %d hears %d, and one of them is not a player" % [peer, speaker])
			continue
		var problem := distance_problem(ear.position, mouth.position, radius)
		if not problem.is_empty():
			found.append("peer %d hears %d %s" % [peer, speaker, problem])
	return found


## Why the snapshot avatar `avatar` of `peer` breaks the crouch invariant (the crouch ADR, KE1),
## or "" when it does not: it shows `crouched` though the player is not alive. Read from the
## player's state, written apart from MovementRule, so a rule that keeps a downed or dead player's
## crouch fails here though view_of agrees with it. The crouch plays in every phase and on every
## map (#991: the engineer removed the per-map list), so no phase or map clause remains.
static func crouch_problem(game: Match, peer: int, avatar: Dictionary) -> String:
	if avatar.get("crouched") != true:
		return ""
	var player := game.state.player(peer)
	if player == null or player.life != PlayerState.Life.ALIVE:
		return "shows peer %d crouched, not alive" % peer
	return ""


## Why the snapshot avatar `avatar` of `peer` breaks the sneak's invariant (#990), or "" when it
## does not: it shows `sneaking` though the player is not alive, or is crouched (the crouch wins,
## #989). Read from the player's state, written apart from MovementRule, like crouch_problem.
static func sneak_problem(game: Match, peer: int, avatar: Dictionary) -> String:
	if avatar.get("sneaking") != true:
		return ""
	var player := game.state.player(peer)
	if player == null or player.life != PlayerState.Life.ALIVE or player.crouched:
		return "shows peer %d sneaking, not alive or crouched" % peer
	return ""


## Why the snapshot avatar `avatar` of `peer` breaks the seated pose's invariant (#1296), or ""
## when it does not: it shows `posed` though the player is not alive. Read from the player's state,
## written apart from MovementRule, like crouch_problem. `player.moving` is no sign of a bug: an
## honest client that sits down out of a walk sends its claim twin first, which repeats its last
## (moving) claim, so the tick of its Pose shows it posed with `moving` still set (the move-ends
## rules are take_pose_test's).
static func pose_problem(game: Match, peer: int, avatar: Dictionary) -> String:
	if avatar.get("posed") != true:
		return ""
	var player := game.state.player(peer)
	if player == null or player.life != PlayerState.Life.ALIVE:
		return "shows peer %d posed, not alive" % peer
	return ""


## Why the snapshot avatar `avatar` of `peer` breaks the bar's invariant (#1390), or "" when it
## does not: its `drunk` differs from the player's state, leaves 0..PlayerRules.drunk_max, or is
## above 0 in a phase whose tick systems hold no DrunkTicks (the base mode's Lobby and Countdown
## hold it; placement, knockdown, respawn and reset sober a player up), written apart from Drink.
static func drunk_problem(game: Match, peer: int, avatar: Dictionary) -> String:
	var drunk: int = avatar.get("drunk", 0)
	var player := game.state.player(peer)
	if player != null and drunk != player.drunk:
		return "shows peer %d drunk %d, its state %d" % [peer, drunk, player.drunk]
	var most := game.mode.player_rules.drunk_max if game.mode.player_rules != null else 0
	if drunk < 0 or drunk > most:
		return "shows peer %d drunk %d, outside 0..%d" % [peer, drunk, most]
	if drunk == 0:
		return ""
	var phase := game.mode.find_phase(game.phase_id())
	if phase != null:
		for system: TickSystem in phase.tick_systems:
			if system is DrunkTicks:
				return ""
	return (
		"shows peer %d drunk %d in phase %s, which sobers nobody" % [peer, drunk, game.phase_id()]
	)


## Why the snapshot avatar `avatar` of `peer` breaks the limp's invariant (#1393), or "" when it
## does not: its `limp` differs from the player's is_limp(), or the player lies limp while not
## alive or in a phase whose tick systems hold no LimpTicks (nothing there would get it up; the
## countdown's end runs EndLimps), written apart from GoLimp and Snapshots.
static func limp_problem(game: Match, peer: int, avatar: Dictionary) -> String:
	var shown: bool = avatar.get("limp", false) == true
	var player := game.state.player(peer)
	if player == null:
		return ""
	if shown != player.is_limp():
		return "shows peer %d limp %s, its state %s" % [peer, shown, player.is_limp()]
	if not shown:
		return ""
	if player.life != PlayerState.Life.ALIVE:
		return "shows peer %d limp, not alive" % peer
	var phase := game.mode.find_phase(game.phase_id())
	if phase != null:
		for system: TickSystem in phase.tick_systems:
			if system is LimpTicks:
				return ""
	return "shows peer %d limp in phase %s, which gets nobody up" % [peer, game.phase_id()]


## The hearing radius of `game`'s current phase: VoiceRule.radius_of the voice rule the mode's data
## names for it (0 with none), the number the client fades to silence at (E41).
static func phase_radius(game: Match) -> float:
	var spec := game.mode.find_phase(game.phase_id())
	return VoiceRule.radius_of(spec.voice_rule if spec != null else null)


## Why a voice between a listener at `ear` and a speaker at `mouth` breaks the distance invariant
## under the hearing radius `radius_m`, or "" when it does not. The comparison is
## VoiceRule.within's, written again here (`distance_squared_to(...) <= r * r` from the listener),
## so a pair exactly at the edge passes and a change to within does not change this check; a
## radius of 0 hears nobody.
static func distance_problem(ear: Vector3, mouth: Vector3, radius_m: float) -> String:
	if radius_m <= 0.0:
		return "in a phase whose hearing radius is 0"
	var squared := ear.distance_squared_to(mouth)
	if squared <= radius_m * radius_m:
		return ""
	return "from %.3f m, beyond the phase's hearing radius of %.3f m" % [sqrt(squared), radius_m]


## Why the avatars of `peer`'s snapshot break the own-avatar invariant (the knockdown rework's KE5,
## §9, #847), or "" when they do not: they hold the viewer's own avatar exactly when the host's
## state has the viewer knocked down or limp (`downed`, read from the life state and
## PlayerState.limp, #1393, never from Snapshots.for_peer), so an inverted or a widened exception
## fails here though view_of agrees.
static func own_avatar_problem(peer: int, avatars: Dictionary, downed: bool) -> String:
	if avatars.has(peer) and not downed:
		return "shows peer %d its own avatar, not knocked down" % peer
	if downed and not avatars.has(peer):
		return "lacks the own avatar of knocked-down peer %d" % peer
	return ""


## The life state of `peer`, LEFT for a peer that is not a player.
func _life_of(peer: int) -> PlayerState.Life:
	var player := _game.state.player(peer)
	return player.life if player != null else PlayerState.Life.LEFT


func _learn_role(peer: int, about: int, role: StringName, found: PackedStringArray) -> void:
	var state := _game.state
	var truth: StringName = state.players[about].role if state.players.has(about) else &""
	if role != truth:
		found.append("peer %d learned that %d is %s, but it is %s" % [peer, about, role, truth])
	if about == peer:
		return
	var own: StringName = state.players[peer].role if state.players.has(peer) else &""
	var own_role := _game.mode.find_role(own)
	if own_role == null or not own_role.knows_teammates or truth != own:
		found.append("peer %d (%s) learned the role of peer %d (%s)" % [peer, own, about, truth])


## Whether `value` holds any of `texts` in a String or StringName, at any depth (a key or a
## value).
static func holds_text(value: Variant, texts: PackedStringArray) -> bool:
	if value is String or value is StringName:
		var text := str(value)
		for wanted: String in texts:
			if text.contains(wanted):
				return true
	elif value is Dictionary:
		var fields: Dictionary = value
		for key: Variant in fields:
			if holds_text(key, texts) or holds_text(fields[key], texts):
				return true
	elif value is Array or value is PackedStringArray:
		for element: Variant in value:
			if holds_text(element, texts):
				return true
	return false


## Whether `value` holds the whole number `number`, at any depth.
static func holds_int(value: Variant, number: int) -> bool:
	if value is int:
		return value == number
	if value is Dictionary:
		var fields: Dictionary = value
		for key: Variant in fields:
			if holds_int(key, number) or holds_int(fields[key], number):
				return true
	elif value is Array:
		for element: Variant in value as Array:
			if holds_int(element, number):
				return true
	elif value is PackedInt32Array or value is PackedInt64Array:
		for element: int in value:
			if element == number:
				return true
	return false
