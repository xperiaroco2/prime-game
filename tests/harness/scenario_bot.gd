class_name ScenarioBot
extends RefCounted
## One bot of a scenario runner (ARCHITECTURE §9.7, §4.6): its script's progress and everything its
## client knows, learned only from the events and snapshots it received, as (name, fields): the
## core runner gives each event's to_dict(), a network bot its ClientSession's decoded messages. A
## target the bot cannot know from them fails the scenario, so a scenario also proves that its
## mechanic is playable with what a player is told.

## A copy of ItemState.Where, in the same order (a test pins it): a FLYING item's place is unknown
## until its flight ends.
enum Where { GROUND, HAND, LOCKED, BELT, FLYING }

## The events for one peer whose fields name no peer (§4.6): whoever receives one is its subject,
## so a step's `peer` field matches the receiving bot.
const OWN_EVENTS: Array[StringName] = [
	&"RoleAssigned", &"Damaged", &"SelfStatus", &"Correction", &"Rejected"
]
## The ship's engine's console's station kind (content/tasks/ship_engine.tres), which StationPlaced
## names to every player.
const ENGINE_CONSOLE := &"engine_console"

static var _receivable: Dictionary[StringName, PackedStringArray] = {}

var number: int
## Its peer id; 0 until it is known (a network bot learns it when it connects).
var peer: int
var steps: Array[ScenarioStep] = []
## The runner's map from bot number to peer id, for `bot(i)` targets.
var peers: ScenarioPeers
var step_index := 0
## The tick the current step started, or -1 before it starts.
var step_started := -1
## The index in `events` where the current step started, and where the previous one did.
var step_cursor := 0
var previous_cursor := 0
## The sequence number of the intent the current step sent, or -1.
var sent_seq := -1
## The item the current step names (PickUp) or held when it sent (PutDown), or -1.
var sent_item := -1
## The player the current step's intent names (Raise's target), or 0.
var sent_peer := 0
var connected := false
## Its Welcome arrived.
var joined := false
## It left, or the host disconnected it: it acts and receives no more, unless it left by its own
## Leave and a Join follows (returns()).
var gone := false
## Its own Leave step made it gone (a host's DisconnectPeer does not): a Join may follow.
var left := false
## Its synthetic voice sends frames (a network runner's, BotVoice); a Talk step turns it off or on.
var talking := true
## Every event it received, in order: name and fields (the event's to_dict()).
var events: Array[WireMessage] = []
## Its connections before the current one, oldest first, each {peer, events}: a bot that joined
## again after its Leave (P12 (a) of the returning-players ADR) starts each connection empty.
var lives: Array[Dictionary] = []
## A returning Join's next try (P12 (t2)): the tick before which it does not connect again, and
## why its last try was refused ("" before any).
var retry_tick := 0
var last_refusal := ""

## What its client knows of itself.
var epoch := 0
## Its jumps since it adopted `epoch` (MoveClaim's `jumps`, §4.3): 0 again on every new epoch.
var jumps := 0
var position := Vector3.ZERO
## Downed, from its own KnockedDown until its own Died or Revived; dead from then until its own
## Respawned or the next match.
var downed := false
var dead := false
## Limp (#1393), from its own avatar's `limp` flag in its last snapshot (a limp player's snapshot
## holds its own avatar, KE5): it sends only its look until it gets up.
var limp := false
var role: StringName
## Its three places (GDD §6), item ids or -1, and the selected one, whose item is in the hand
## (ItemPickedUp with `place` and `belted`, Swapped with `place`, ItemPlaced).
var places: Array[int] = [-1, -1, -1]
var selected := 0
## Its hand item, or -1.
var held: int:
	get:
		return places[selected]
var sprint_available := true
## Its own drunk value, from its SelfStatus (the bar, #1390).
var drunk := 0
## Its first belt item (the lowest non-selected place that holds one), or -1.
var belted: int:
	get:
		for at in places.size():
			if at != selected and places[at] >= 0:
				return places[at]
		return -1
var phase: StringName
var match_id := 0
## A LoadMatch arrived that no LoadAck step answers: the default is to acknowledge at once.
var load_ack_due := false
## The match id of the last LoadMatch acknowledged at once (no LoadAck step was current), or -1.
var auto_acked_match := -1
## The match id of the LoadMatch that the bot's LoadAck step is to answer, or -1.
var unanswered_load := -1
## Item id -> {kind, position, where, station}, from ItemSpawned, ItemPickedUp, ItemPlaced and
## PackageDelivered. `where` tells GROUND from carried only: a Swapped leaves HAND and BELT as they
## were (the bot's own places are `places`).
var items: Dictionary[int, Dictionary] = {}
## Station id -> position, and station id -> its StationKind id, from StationPlaced.
var stations: Dictionary[int, Vector3] = {}
var station_kinds: Dictionary[int, StringName] = {}
## The ship's engine as its client folds it (ClientEngineBook, #1498): the open problems, the
## breaker chains, the gill slits and the crystals, from the engine's public events alone, as a
## player's client keeps it (MendEngine reads it).
var engine := ClientEngineBook.new()
## The engine's console was pressed (its ButtonPressed), and its bar is full (the console's
## ZoneProgress at its `needed`): the engine is done.
var engine_started := false
var engine_done := false
## Peer -> where the bot last saw that player: PlayerJoined, Welcome, PlayersPlaced, snapshots.
var seen: Dictionary[int, Vector3] = {}
## Peer -> that player's drunk value in the bot's last snapshot that showed it (#1390).
var drunk_seen: Dictionary[int, int] = {}

var _next_seq := 1
var _client_tick := 0
## A placement of the bot (PlayersPlaced naming it, its own KnockedDown, Revived or Respawned)
## awaits its Correction: core/ emits exactly one after each, so a network poll that splits the
## two still expects it, and any other Correction fails. A death sends none.
var _correction_due := false
## A Correction no placement explained, while the bot was not limp: the limp's start (#1393) has
## no event of its own, so the next snapshot must show the bot limp (see), else it fails. A second
## one before that snapshot fails at once: one limp starts with one Correction.
var _unexplained := ""
## The Corrections no placement explained since the bot was last seen not limp. A limp gets the
## go-limp's (when the snapshot showing it limp came first over the network) and the get-up's,
## never one for a claim (KE4, §7.1.21): a third fails.
var _limp_corrections := 0


func _init(
	bot_number: int,
	peer_id: int,
	script_steps: Array[ScenarioStep],
	bot_peers: ScenarioPeers = null
) -> void:
	number = bot_number
	peer = peer_id
	steps = script_steps
	peers = bot_peers if bot_peers != null else ScenarioPeers.new()


## The step it is on, or null when its script is done.
func current_step() -> ScenarioStep:
	return steps[step_index] if step_index < steps.size() else null


func finished() -> bool:
	return (gone and not returns()) or current_step() == null


## Whether it left by its own Leave and its next step joins it again: it acts again, on a new
## connection (begin_return).
func returns() -> bool:
	return gone and left and current_step() is StepJoin


## Whether a runner lets it act this tick: it is not gone, or it returns.
func acts() -> bool:
	return not gone or returns()


## Whether it is joining again after its Leave and its Welcome has not arrived yet.
func returning() -> bool:
	return not lives.is_empty() and not joined


## Starts its next connection on `new_peer` (0 until a network bot learns it): the one that ended
## goes to `lives`, and everything a connection learns starts empty again (its script goes on).
func begin_return(new_peer: int) -> void:
	lives.append({"peer": peer, "events": events})
	_new_connection(new_peer)


## A returning Join's try was refused for `reason`: it tries again from tick `next_tick` on a new
## connection (on the same peer id until a network runner learns another), and what the refused
## one received is dropped: it never joined.
func refused(reason: String, next_tick: int) -> void:
	last_refusal = reason
	retry_tick = next_tick
	_new_connection(peer)


## The return key bot `number` sends in every Hello (ARCHITECTURE §3.5, §9.7): fixed from its
## number, in every runner and over every transport, so a bot that left and joins again is known by
## it (P12 (a) of the returning-players ADR). Not a secret: a test key.
static func key_of(bot_number: int) -> String:
	return ReturnKey.of("bot%d" % bot_number, "bots")


## Whether its script joins it later (a Join first) instead of at the start. A Join after its own
## Leave is no late join: the bot joined at the start before it left.
func joins_late() -> bool:
	return not steps.is_empty() and steps[0] is StepJoin


func start_step(at_tick: int) -> void:
	step_started = at_tick
	previous_cursor = step_cursor
	step_cursor = events.size()
	sent_seq = -1
	sent_item = -1
	sent_peer = 0


func finish_step() -> void:
	step_index += 1
	step_started = -1


func next_seq() -> int:
	_next_seq += 1
	return _next_seq - 1


func next_client_tick() -> int:
	_client_tick += 1
	return _client_tick


## Takes one event its peer received, as (name, fields), and learns from it. Returns a failure, or
## "".
func receive(event_name: StringName, fields: Dictionary) -> String:
	events.append(WireMessage.new(event_name, fields))
	match event_name:
		&"Welcome":
			joined = true
			peer = fields["peer"] as int
			epoch = fields["epoch"] as int
			jumps = 0
			position = fields["spot"] as Vector3
			phase = StringName(str(fields["phase"]))
			var positions: Dictionary = fields["positions"]
			for other: int in positions:
				seen[other] = positions[other]
			_welcome_items(fields.get("items", []) as Array)
		&"PlayerJoined":
			seen[fields["peer"] as int] = fields["spot"] as Vector3
		&"PlayersPlaced":
			var spots: Dictionary = fields["spots"]
			for other: int in spots:
				seen[other] = spots[other]
			if spots.has(peer):
				_correction_due = true
		&"Correction":
			if not _correction_due:
				var problem := _unexplained_correction(fields)
				if not problem.is_empty():
					return problem
			_correction_due = false
			epoch = fields["epoch"] as int
			jumps = 0
			position = fields["position"] as Vector3
		&"KnockedDown":
			var knocked := fields["peer"] as int
			seen[knocked] = fields["position"] as Vector3
			if knocked == peer:
				downed = true
				_correction_due = true
		&"Died":
			var died := fields["peer"] as int
			seen[died] = fields["position"] as Vector3
			if died == peer:
				downed = false
				dead = true
		&"Respawned":
			var back := fields["peer"] as int
			seen[back] = fields["position"] as Vector3
			if back == peer:
				dead = false
				_correction_due = true
		&"Revived":
			# It stands up where it lay, placed there by the Correction that follows (KE6).
			if fields["peer"] as int == peer:
				downed = false
				_correction_due = true
		_:
			engine.fold(event_name, fields)
			_learn(event_name, fields)
	return ""


## Takes the avatars of a snapshot: where it sees the other players and their drunk values. The
## own avatar, which a knocked-down or limp player's snapshot carries (KE5, #1393), gives only
## whether the bot lies limp: the bot knows where it is. Returns a failure, or "": a Correction no
## placement explained and this snapshot does not show limp.
func see(avatars: Dictionary) -> String:
	var own: Dictionary = avatars.get(peer, {})
	limp = own.get("limp", false) == true
	var problem := _unexplained if not limp else ""
	if not limp:
		_limp_corrections = 0
	elif not _unexplained.is_empty():
		_limp_corrections = 1
	_unexplained = ""
	for other: int in avatars:
		if other == peer:
			continue
		var avatar: Dictionary = avatars[other]
		seen[other] = avatar["position"]
		drunk_seen[other] = avatar.get("drunk", 0) as int
	return problem


## Takes a Correction no placement explained. Sober (its SelfStatus drunk 0): it fails at once, as
## no limp can start (one mug from sober stays under too much: the base mode's 40 under 90; a
## mug that crossed it would fail here loudly). Drunk, not limp: maybe the limp's start (GoLimp),
## which see() checks with the next snapshot; a second before it fails. Limp: the go-limp's or the
## get-up's (LimpTicks, EndLimps); a third fails. Returns a failure, or "".
func _unexplained_correction(fields: Dictionary) -> String:
	var at := "epoch %d, at %s" % [fields["epoch"], fields["position"]]
	if limp:
		_limp_corrections += 1
		if _limp_corrections > 2:
			return (
				"a third Correction while limp (%s): a limp bot's claims are never corrected" % at
			)
		return ""
	if drunk <= 0:
		return "a Correction outside a placement (%s): an honest bot is never corrected" % at
	if not _unexplained.is_empty():
		return "a second Correction outside a placement (%s): an honest bot is never corrected" % at
	_unexplained = "a Correction outside a placement (%s): an honest bot is never corrected" % at
	return ""


## The reason of the Rejected answering `seq` since the current step started, or "".
func rejection_of(seq: int) -> StringName:
	for i in range(step_cursor, events.size()):
		var event := events[i]
		if event.name == &"Rejected" and event.fields["seq"] == seq:
			return StringName(str(event.fields["reason"]))
	return &""


## The first event since `from` that `matches` (a Callable taking a WireMessage) accepts, or null.
func find_since(from: int, matches: Callable) -> WireMessage:
	for i in range(from, events.size()):
		if matches.call(events[i]):
			return events[i]
	return null


## The value of `field` in an event this bot received: the payload's, else, for `peer` of an event
## for one peer that names none (OWN_EVENTS), the bot's own peer id; null when it has none.
func field_of(event: WireMessage, field: String) -> Variant:
	if event.fields.has(field):
		return event.fields[field]
	if field == "peer" and OWN_EVENTS.has(event.name):
		return peer
	return null


## Every event a bot can receive -> the fields a step or a `never` may match on it (field_of): the
## wire schema's event rows and their payload's names, plus `peer` for OWN_EVENTS. What
## BotScenario.problems() checks a scenario's event names and `fields` keys against (#1235).
static func receivable_events() -> Dictionary[StringName, PackedStringArray]:
	if _receivable.is_empty():
		for row: WireRow in WireSchema.game(true).rows():
			if row.kind < WireSchema.FIRST_EVENT or row.kind >= WireSchema.FIRST_STATE:
				continue
			var fields := row.field_names()
			if OWN_EVENTS.has(row.name) and not fields.has("peer"):
				fields.append("peer")
			_receivable[row.name] = fields
	return _receivable


## Where `target` is, as the bot knows it, or Vector3.INF when it cannot know.
func where_is(target: ScenarioTarget) -> Vector3:
	var found := Vector3.INF
	match target.kind:
		ScenarioTarget.Kind.POINT:
			found = target.point
		ScenarioTarget.Kind.BOT:
			var other := peers.peer_of(target.bot)
			if other == 0:
				found = Vector3.INF
			else:
				found = position if other == peer else seen.get(other, Vector3.INF)
		ScenarioTarget.Kind.CIRCLE_OF_HELD:
			if held >= 0 and items.has(held):
				var station: int = items[held]["station"]
				found = stations.get(station, Vector3.INF)
		ScenarioTarget.Kind.STATION:
			var station := station_of(target)
			if station >= 0:
				found = stations[station]
		_:
			var item := item_of(target)
			# An item in flight is somewhere along its arc: its last known place would mislead a step.
			if item >= 0 and items[item]["where"] != Where.FLYING:
				found = items[item]["position"]
	return found


## The station id a STATION `target` names (the n-th, from 1, of its kind in station-id order,
## from the bot's own StationPlaced), or -1 when the bot knows no such station.
func station_of(target: ScenarioTarget) -> int:
	if target.kind != ScenarioTarget.Kind.STATION:
		return -1
	var ids: Array[int] = []
	for id: int in station_kinds:
		if station_kinds[id] == target.station_kind:
			ids.append(id)
	ids.sort()
	if target.index >= 1 and target.index <= ids.size():
		return ids[target.index - 1]
	return -1


## The item `target` names, as the bot knows it, or -1.
func item_of(target: ScenarioTarget) -> int:
	if target.kind == ScenarioTarget.Kind.PACKAGE:
		var ids := _ids_of_kind(&"package")
		return ids[target.index - 1] if target.index <= ids.size() else -1
	if target.kind == ScenarioTarget.Kind.NEAREST:
		var best := -1
		var best_distance := INF
		for id: int in _ids_of_kind(target.item_kind):
			if items[id]["where"] != Where.GROUND:
				continue
			var at: Vector3 = items[id]["position"]
			# In three dimensions: an item straight above or below, on another storey, is far.
			var distance := (at - position).length()
			if distance < best_distance:
				best = id
				best_distance = distance
		return best
	return -1


## The last events it received, by name, for a failure's report.
func last_events(count: int = 12) -> Array[StringName]:
	var names: Array[StringName] = []
	for i in range(maxi(0, events.size() - count), events.size()):
		names.append(events[i].name)
	return names


func _learn(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		&"RoleAssigned":
			role = StringName(str(fields["role"]))
		&"LoadMatch":
			match_id = fields["match_id"] as int
			items.clear()
			stations.clear()
			station_kinds.clear()
			_forget_engine()
			_clear_places()
			downed = false
			dead = false
			if current_step() is StepLoadAck:
				unanswered_load = match_id
			else:
				load_ack_due = true
		&"PhaseChanged":
			phase = StringName(str(fields["phase"]))
		&"StationPlaced":
			stations[fields["station"] as int] = fields["position"] as Vector3
			station_kinds[fields["station"] as int] = StringName(str(fields["kind"]))
		&"ItemSpawned":
			items[fields["item"] as int] = {
				"kind": StringName(str(fields["kind"])),
				"position": fields["position"] as Vector3,
				"where": Where.GROUND,
				"station": fields.get("station", -1) as int,
			}
		# `belted` names the item this take put on the belt: the hand item (E29), or `item` itself
		# when it went straight onto the belt beside a two-handed hand item, which stays held (the
		# cooking ADR, CE20, CE21). A full belt's item went down first (its ItemPlaced cleared it).
		&"ItemPickedUp":
			var item := fields["item"] as int
			var to_belt := fields.get("belted", -1) as int
			if items.has(item):
				items[item]["where"] = Where.BELT if to_belt == item else Where.HAND
			if to_belt != item and items.has(to_belt):
				items[to_belt]["where"] = Where.BELT
			if fields["peer"] as int == peer:
				places[fields.get("place", 0) as int] = item
				if to_belt != item:
					selected = fields.get("place", 0) as int
			else:
				# Another player took it: from this bot's hand, when it was handed over (#1389).
				_let_go(item)
		&"Swapped":
			if fields["peer"] as int == peer:
				selected = fields["place"] as int
		&"ItemThrown":
			var item := fields["item"] as int
			if items.has(item):
				items[item]["where"] = Where.FLYING
				items[item]["position"] = fields["origin"] as Vector3
			_let_go(item)
		# Also the end of a flight (cause `thrown`): the item rests at `position` again.
		&"ItemPlaced":
			var item := fields["item"] as int
			if items.has(item):
				items[item]["where"] = Where.GROUND
				items[item]["position"] = fields["position"] as Vector3
			_let_go(item)
		&"PackageDelivered":
			var item := fields["item"] as int
			if items.has(item):
				items[item]["where"] = Where.LOCKED
		# The station tasks lay an item from a hand at a station with no ItemPlaced (#1209): a film
		# in the camera lies there to be picked up again once shot (FilmLoaded); a patty on the grill,
		# an ingredient on a place, a hung photo and a fitted part are locked there.
		&"FilmLoaded":
			var item := fields["item"] as int
			_let_go(item)
			if items.has(item):
				items[item]["where"] = Where.GROUND
				items[item]["position"] = stations.get(fields["station"] as int, Vector3.INF)
		&"GrillLoaded", &"IngredientPlaced", &"PhotoHung", &"PartFitted":
			var item := fields["item"] as int
			_let_go(item)
			if items.has(item):
				items[item]["where"] = Where.LOCKED
		&"ItemVanished":
			var item := fields["item"] as int
			_let_go(item)
			items.erase(item)
		&"SelfStatus":
			sprint_available = fields["sprint_available"] as bool
			drunk = fields.get("drunk", 0) as int
		&"ButtonPressed":
			if station_kinds.get(fields["station"] as int, &"") == ENGINE_CONSOLE:
				engine_started = true
		&"ZoneProgress":
			var needed := fields["needed"] as int
			var charged := fields["ticks"] as int
			var console: bool = station_kinds.get(fields["station"] as int, &"") == ENGINE_CONSOLE
			if console and needed > 0 and charged >= needed:
				engine_done = true
		# A crystal loaded into a charger leaves the hand with no event of its own (Items.lock_at):
		# CrystalChanged naming a charger says it is locked there.
		&"CrystalChanged":
			var item := fields["item"] as int
			if fields["charger"] as int >= 0 and item >= 0:
				_let_go(item)
				if items.has(item):
					items[item]["where"] = Where.LOCKED


## The engine as nothing told it yet: a new match or a new connection.
func _forget_engine() -> void:
	engine = ClientEngineBook.new()
	engine_started = false
	engine_done = false


## The hall's items as a Welcome lists them (#1404), in place of any known before: each row's
## kind, position and rest state (its `where`, in Where's order); a locked one at no station.
func _welcome_items(rows: Array) -> void:
	items.clear()
	for row: Dictionary in rows:
		items[row["item"] as int] = {
			"kind": StringName(str(row["kind"])),
			"position": row["position"] as Vector3,
			"where": row["where"] as int,
			"station": -1,
		}


## The bot no longer holds or belts `item`.
func _let_go(item: int) -> void:
	var at := places.find(item)
	if at >= 0:
		places[at] = -1


## Empty hands and belt, the hand on the first place.
func _clear_places() -> void:
	places.fill(-1)
	selected = 0


func _ids_of_kind(kind: StringName) -> Array[int]:
	var ids: Array[int] = []
	for id: int in items:
		if items[id]["kind"] == kind:
			ids.append(id)
	ids.sort()
	return ids


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## A new connection on `new_peer`: not connected, nothing received, nothing known of the match.
func _new_connection(new_peer: int) -> void:
	peer = new_peer
	connected = false
	joined = false
	gone = false
	left = false
	events = []
	step_started = -1
	step_cursor = 0
	previous_cursor = 0
	sent_seq = -1
	sent_item = -1
	sent_peer = 0
	epoch = 0
	jumps = 0
	position = Vector3.ZERO
	downed = false
	dead = false
	role = &""
	_clear_places()
	sprint_available = true
	phase = &""
	match_id = 0
	load_ack_due = false
	auto_acked_match = -1
	unanswered_load = -1
	items.clear()
	stations.clear()
	station_kinds.clear()
	_forget_engine()
	seen.clear()
	_next_seq = 1
	_client_tick = 0
	_correction_due = false
	_unexplained = ""
	_limp_corrections = 0
	limp = false
