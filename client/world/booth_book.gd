class_name BoothBook
extends RefCounted
## The client's photo booth sessions (#1397, ARCHITECTURE §4.7.62), folded from the host's public
## BoothStep events (§9.5.29) after the own ClientModel folded them: each session's FLASH records in
## frame order, and the strip items PRINTED bound to the session whose frames they show. It keeps
## the client_pinball shape (fold, clear_match) but sits in client/world/, not in ClientModel: the
## model is at gdlint's line limit and client/net/ is #1474's (a joiner's strips through Welcome);
## it moves to the model when ClientModel is split. #1474's Welcome hands a joiner's strips over
## through bind_strip.
##
## A strip is bound to its item id from PRINTED until that id's next ItemSpawned or ItemVanished
## (an id freed and reused is a new item, CE3: the ItemSpawned of a print comes before its PRINTED),
## so a reused id never shows an old strip; a hand-over keeps the id, so a friend sees the same
## strip. A session lives while it runs or a strip shows it (RefCounted: nothing else holds it).

enum State { RUNNING, PRINTED, STOPPED }
const STEP_EVENT := &"BoothStep"

## The running session by station id (one at most per booth).
var _running: Dictionary[int, Session] = {}
## The session each strip item id shows.
var _bound: Dictionary[int, Session] = {}
## Strip item ids printed and not yet shown sliding into a hand (take_fresh).
var _fresh: Dictionary[int, bool] = {}


## One session of a booth: its plan and the frames taken.
class Session:
	extends RefCounted
	var station := -1
	## The host's session id (u16, wraps): a STARTED always makes a new Session.
	var strip := -1
	var presser := 0
	## The frames planned (STARTED); 0 when this client missed STARTED.
	var frames := 0
	## The countdown and the gap between flashes, in host ticks (STARTED).
	var countdown := 0
	var gap := 0
	## The host tick STARTED was folded at (BoothViews sets it), -1 unknown.
	var started_at := -1
	var state := State.RUNNING
	## Each frame's record rows by frame index (a frame missed is absent).
	var records: Dictionary[int, Array] = {}

	## The frames the strip shows: the planned count, else one past the last frame seen.
	func frame_count() -> int:
		var count := frames
		for index: int in records.keys():
			count = maxi(count, index + 1)
		return count

	## Frame `index`'s rows; empty when it was missed.
	func record_of(index: int) -> Array[Dictionary]:
		var rows: Array[Dictionary] = []
		if records.has(index):
			rows.assign(records[index])
		return rows

	## The frames taken so far.
	func flashes() -> int:
		return records.size()


## Folds one event (ItemWorld calls it after the model folded the event).
func fold(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		STEP_EVENT:
			_fold_step(fields)
		&"ItemSpawned", &"ItemVanished":
			unbind(fields.get("item", -1) as int)
		&"LoadMatch":
			clear_match()


## The session strip item `item_id` shows, or null.
func session_of(item_id: int) -> Session:
	return _bound.get(item_id)


## The session running at station `station_id`, or null.
func running_at(station_id: int) -> Session:
	return _running.get(station_id)


## Every running session.
func running() -> Array[Session]:
	var found: Array[Session] = []
	found.assign(_running.values())
	return found


## Whether a session is still held (running, or shown by a strip).
func holds(session: Session) -> bool:
	return session != null and (_running.values().has(session) or _bound.values().has(session))


## Whether strip `item_id` was just printed (the own hand slides it in); forgets every fresh
## strip, since the print is in its place by the first ask: one printed onto the belt or the floor
## never slides in later. ItemViews asks once a physics frame.
func take_fresh(item_id: int) -> bool:
	var fresh := _fresh.has(item_id)
	_fresh.clear()
	return fresh


## Binds strip item `item_id` to a finished session of `records` (one row array per frame, in
## frame order): #1474's Welcome gives a joiner the strips printed before it joined.
func bind_strip(item_id: int, frames: int, records: Array) -> Session:
	var session := Session.new()
	session.frames = frames
	session.state = State.PRINTED
	for index in records.size():
		var rows: Array[Dictionary] = []
		rows.assign(records[index] as Array)
		session.records[index] = rows
	_bound[item_id] = session
	return session


## Drops strip item `item_id`'s binding (it vanished or its id is a new item).
func unbind(item_id: int) -> void:
	_bound.erase(item_id)
	_fresh.erase(item_id)


## Forgets every session (a match loads, the lobby is entered again, the session ended).
func clear_match() -> void:
	_running.clear()
	_bound.clear()
	_fresh.clear()


func _fold_step(fields: Dictionary) -> void:
	var station := fields.get("station", -1) as int
	var strip := fields.get("strip", -1) as int
	var step := fields.get("step", -1) as int
	if step == BoothStepEvent.STARTED:
		var started := Session.new()
		started.station = station
		started.strip = strip
		started.presser = fields.get("presser", 0) as int
		started.frames = fields.get("frames", 0) as int
		started.countdown = fields.get("countdown", 0) as int
		started.gap = fields.get("gap", 0) as int
		_running[station] = started
		return
	var session: Session = _running.get(station)
	if session == null or session.strip != strip:
		# Joined after STARTED (or a session this client never saw start): the frames from here.
		session = Session.new()
		session.station = station
		session.strip = strip
		_running[station] = session
	match step:
		BoothStepEvent.FLASH:
			var rows: Array[Dictionary] = []
			for row: Variant in fields.get("record", []) as Array:
				if row is Dictionary:
					rows.append((row as Dictionary).duplicate(true))
			session.records[fields.get("frame", 0) as int] = rows
		BoothStepEvent.PRINTED:
			session.state = State.PRINTED
			_running.erase(station)
			for id: int in fields.get("items", PackedInt32Array()) as PackedInt32Array:
				_bound[id] = session
				_fresh[id] = true
		BoothStepEvent.STOPPED:
			session.state = State.STOPPED
			_running.erase(station)
