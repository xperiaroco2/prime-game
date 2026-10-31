class_name BoothSessions
extends RefCounted
## The photo booth's session (#1396; ARCHITECTURE §9.4.2, §9.5.28): at most one per match, in
## MatchState's per-part state (so ResetMatch drops it). StartBooth starts it, BoothTicks advances
## it on the host's clock, StopBooth (a transition action) ends it with the phase. Its frames are
## not kept: each FLASH event carries its record, and the session remembers only who was in any
## frame, so a strip that vanishes frees nothing here.

## Its key in MatchState's per-part state (§9.1).
const PART_KEY := &"booth"
## Strip ids wrap here (a u16 on the wire).
const STRIP_IDS := 0x10000


## The running session, or null.
static func running(state: MatchState) -> Session:
	return _table(state).session


## Starts a session for the actor at the station the intent names: BoothStep STARTED.
static func start(ctx: MatchContext, effect: StartBooth) -> void:
	var station := Stations.target_of(ctx)
	var presser := ctx.state.player(ctx.actor)
	if station == null or presser == null or running(ctx.state) != null:
		ctx.error("StartBooth: no station, no presser, or a session runs already")
		return
	var table := _table(ctx.state)
	var session := Session.new()
	session.effect = effect
	session.station = station.id
	session.presser = presser
	session.strip = table.next_strip
	session.first_flash = ctx.tick + effect.countdown_ticks()
	table.next_strip = (table.next_strip + 1) % STRIP_IDS
	table.session = session
	var started := BoothStepEvent.new(session.station, session.strip, BoothStepEvent.STARTED)
	started.presser = presser.peer
	started.frames = effect.frames
	started.countdown = effect.countdown_ticks()
	started.gap = effect.gap_ticks()
	ctx.emit(started)


## One tick of the running session (BoothTicks): it stops when its presser left the match (a
## downed or limp presser keeps it); a flash due at
## this tick fires; after the last one the strips print in the same tick.
static func advance(ctx: MatchContext) -> void:
	var session := running(ctx.state)
	if session == null:
		return
	var station: StationState = ctx.state.stations.get(session.station)
	if station == null or not _same_present(ctx.state, session.presser):
		stop(ctx)
		return
	if ctx.tick < session.next_flash_tick():
		return
	_flash(ctx, session, station)
	if session.frames_done >= session.effect.frames:
		_print(ctx, session, station)


## Ends the running session with no print: BoothStep STOPPED. Nothing when none runs.
static func stop(ctx: MatchContext) -> void:
	var session := running(ctx.state)
	if session == null:
		return
	_table(ctx.state).session = null
	ctx.emit(BoothStepEvent.new(session.station, session.strip, BoothStepEvent.STOPPED))


## The frame at this tick: every living present player inside the station's cylinder, in peer
## order, with the body state it has now.
static func frame_of(state: MatchState, station: StationState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for peer: int in state.peers():
		var player := state.player(peer)
		if (
			not player.is_present()
			or not player.is_alive()
			or not station.contains(player.position)
		):
			continue
		(
			rows
			. append(
				{
					"peer": peer,
					"colour": player.colour,
					"position": player.position,
					"facing": player.facing,
					"crouched": player.crouched,
					"sneaking": player.sneaking,
					"posed": player.posed,
					"limp": player.is_limp(),
				}
			)
		)
	return rows


static func _flash(ctx: MatchContext, session: Session, station: StationState) -> void:
	var rows := frame_of(ctx.state, station)
	for row: Dictionary in rows:
		var peer: int = row["peer"]
		if not session.seen.has(peer):
			session.seen[peer] = ctx.state.player(peer)
	var flash := BoothStepEvent.new(session.station, session.strip, BoothStepEvent.FLASH)
	flash.frame = session.frames_done
	flash.record = rows
	session.frames_done += 1
	ctx.emit(flash)


## One strip for each player in any frame who is still the same player, present and alive (a peer
## id comes back after a leave, net/CLAUDE.md), in peer order: GiveItem.give_new as that player
## (hands, belt, feet; the cap's vanish first). Then PRINTED naming them, or STOPPED when none was
## made.
static func _print(ctx: MatchContext, session: Session, station: StationState) -> void:
	_table(ctx.state).session = null
	var peers: Array[int] = []
	for peer: int in session.seen:
		peers.append(peer)
	peers.sort()
	var made := PackedInt32Array()
	for peer: int in peers:
		var player := session.seen[peer]
		if not _same_present(ctx.state, player) or not player.is_alive():
			continue
		var as_receiver := ctx.copy()
		as_receiver.actor = peer
		as_receiver.command = null
		var strip := GiveItem.give_new(as_receiver, session.effect.strip, station.position)
		if strip != null:
			made.append(strip.id)
	if made.is_empty():
		ctx.emit(BoothStepEvent.new(session.station, session.strip, BoothStepEvent.STOPPED))
		return
	var printed := BoothStepEvent.new(session.station, session.strip, BoothStepEvent.PRINTED)
	printed.items = made
	ctx.emit(printed)


## Whether `player` is still in the roster as itself (not a later player with its peer id) and
## present.
static func _same_present(state: MatchState, player: PlayerState) -> bool:
	return player != null and state.player(player.peer) == player and player.is_present()


static func _table(state: MatchState) -> Table:
	return state.part_state(PART_KEY, func() -> RefCounted: return Table.new()) as Table


## The match's booth state: the running session and the next strip id.
class Table:
	extends RefCounted
	var session: Session = null
	var next_strip := 0


## One running session.
class Session:
	extends RefCounted
	var effect: StartBooth
	var station := -1
	var presser: PlayerState
	var strip := 0
	## The tick of the first flash.
	var first_flash := 0
	var frames_done := 0
	## The players in any frame so far, by peer.
	var seen: Dictionary[int, PlayerState] = {}

	## The tick of the next flash.
	func next_flash_tick() -> int:
		return first_flash + frames_done * effect.gap_ticks()
