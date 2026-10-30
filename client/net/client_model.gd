class_name ClientModel
extends RefCounted
## What one client knows now (ARCHITECTURE §4.6), folded from the events and snapshots it decoded:
## its peer id and epoch, the phase, the roster, the settings, the items with every player's hand
## and belt and their flights (§7.1.16), the stations (a zone's progress too), the tasks and
## bodies, each player's life (E25), the avatars of the newest snapshot and its own SelfStatus.
## Built only from what the host sent this client, never from core/ state (invariant 2). The game
## mode is the client's own copy, read for where each phase plays.
##
## A match's facts (items, stations, bodies, role, tasks, avatars and the like) are cleared on
## LoadMatch and on entering the lobby: a new level holds none of the old ones. A snapshot sent
## before that change but arriving after it (the unreliable lane against the reliable one) is not
## folded (#251): see _snapshot_floor.

## A player's life as the public events tell it (E25): the client's own words for core/'s life
## states, so no client/ file names a core/ state class (client/CLAUDE.md).
enum Life { ALIVE, DOWNED, DEAD, LEFT }

## An item's holder when nobody holds it (no peer id is 0).
const NO_HOLDER := 0
## A player's places, the hand's and the belt's (GDD §6 "Drawing from the belt"), 0..2.
const PLACES := 3


## One player of the roster.
class Member:
	extends RefCounted
	var name := ""
	var ready := false
	## The body colour, an index into PlayerColours (#551): public, every player sees it.
	var colour := 0


## One item as the events describe it.
class Item:
	extends RefCounted
	var kind: StringName
	var position := Vector3.ZERO
	## The peer carrying it; NO_HOLDER when it rests somewhere.
	var holder := NO_HOLDER
	## Who carried it right before its last ItemPickedUp: another player when that take was a
	## hand-over (#1389, HandOver), NO_HOLDER for a take from the world. Only that event's fold
	## writes it, so the sound chooser can tell where the take happened.
	var handed_from := NO_HOLDER
	## Carried on the holder's belt rather than in its hand (M4-5, E29).
	var belted := false
	## Its place among the holder's three (0..2, GDD §6 "Drawing from the belt"), or -1 when nobody
	## carries it (ItemPickedUp `place`).
	var carry_place := -1
	## A package's circle and colour; -1 and white for any other item.
	var station := -1
	var colour := Color.WHITE
	var delivered := false
	## A car repair part fitted to the car (PartFitted, #808): locked at the car's use spot, held by
	## nobody and never taken again: it rests nowhere (rests() is false), so no view draws it and no
	## crosshair names it (the car repair ADR's RE12, #811).
	var fitted := false
	## Cooking (#776): the station it lies on, a place's plate or the grill (IngredientPlaced,
	## GrillLoaded), -1 for none; whether it is locked there (every plated ingredient and the
	## grill's patty: no PickUp takes it; since #1101 nothing on a plate is right or wrong before
	## its burger is served). A pickup, a put down or a throw clears both. Nothing records who put
	## it there (the ADR's §3).
	var on_station := -1
	var locked := false
	## A plated burger (BurgerPlated, #1101): the kind ids on its slots (bun, patty, herb; empty for
	## any other item) and the place it was plated on (-1 for none), whose order it serves.
	var parts := PackedStringArray()
	var place := -1
	## In flight (§7.1.16): from its ItemThrown until its ItemPlaced (cause `thrown`) or
	## PackageDelivered. The launch exactly as the event carries it, so a client draws the arc
	## from the same vectors the host's flight uses (37e): the thrower, the origin, velocity and
	## gravity, and the launch tick L (the point at host tick t is the arc's at t - L). While it
	## flies, `position` is the origin, a stand-in: the item rests nowhere (rests() is false).
	var flying := false
	var thrower := NO_HOLDER
	var flight_origin := Vector3.ZERO
	var flight_velocity := Vector3.ZERO
	var flight_gravity := Vector3.ZERO
	var flight_tick := 0
	## A printed photo (#787, photo P8): the shot whose picture it shows, as PhotoPrinted named it; -1
	## for any other item.
	var shot := -1

	## Lies in the world at `position`: nobody carries it, it is not in flight and not fitted to a
	## car (a delivered package rests in its circle).
	func rests() -> bool:
		return holder == NO_HOLDER and not flying and not fitted


## One task as its TaskState tells it (E30): the task screen's row.
class Task:
	extends RefCounted
	## The task type's id: the client's own copy of the mode gives its name and description.
	var type: StringName
	var done := 0
	var total := 0


## One station: a delivery circle, a zone (#36), or the Generator's generator or a switch (#797).
## Nothing here names who used it: no event of a station carries a player.
class Station:
	extends RefCounted
	var kind: StringName
	var colour := Color.WHITE
	var position := Vector3.ZERO
	## Done: a package was delivered to it (§4.2 PackageDelivered) and no other item routed to it
	## is undelivered (DE7 of the delivery-by-meaning ADR), or, for a zone or the
	## generator, its last ZoneProgress has `ticks` at `needed` (ZE8 of the zone task ADR).
	var done := false
	## A zone's progress, or the generator's charge (GE7), as its last ZoneProgress told it (ZE4,
	## ZE8): its ticks so far, the ticks it needs, whether it counts, and the host tick this held at
	## (-1 before the first). The client predicts nothing: ZoneViews extrapolates from these alone.
	var ticks := 0
	var needed := 0
	var counting := false
	var progress_tick := -1
	## A switch of the Generator: whether it is on, as its last SwitchChanged told it; a placed
	## switch is off until its first (GE9, GE14).
	var on := false
	## The Generator's button: the ButtonPressed events decoded for it, so a view can tell a new
	## press (its sound, its animation) from one it has shown.
	var presses := 0
	## The car repair's lift panel (#807): whether the car is up or going up, and the host tick of
	## the hold's start or stop, as its last LiftChanged told it (-1 before the first). The view
	## derives the car's height from these and its own copy of `rise_seconds`; nothing names who
	## holds.
	var up := false
	var lift_tick := -1
	## The host tick of the last hold's start (the last LiftChanged with `up`), kept by its stop, so
	## a view knows how high the car got before it dropped (#811); -1 before the first.
	var rise_tick := -1
	## The car repair's picture (#807): the part kind id the car needs now, as its last PartNeeded
	## told it; empty for none.
	var part := &""
	## The car repair's car (#808): the player fitting a part, 0 for none, and the host tick the fit
	## began or stopped, as its last FitChanged told it (-1 before the first); a completed fit
	## (PartFitted) leaves no fitter. The fitter's own view derives its progress from the tick and
	## its copy of the fit's seconds. Nothing at the lift panel reads it (the ADR's §3, RD14 (a)).
	var fitter := 0
	var fit_tick := -1
	## The parts fitted to the car, as the PartFitted events decoded for it told it.
	var fitted := 0
	## Cooking's place (#776): its order as OrderPosted told it (the bun and the fried patty kind
	## ids, the herb's icon index; empty and -1 before); `done` once a right burger plated on it is
	## served (BurgerServed, #1101). The order's herb is never sent; what lies on its plate is the
	## items whose `on_station` it is (plated_on).
	var bun := &""
	var patty := &""
	var icon := -1
	## Cooking's grill (#776): its patty and the host ticks it turns fried and burnt at, as the
	## last GrillLoaded told it; -1 when empty (the patty's ItemPickedUp empties it).
	var grill_item := -1
	var fried_tick := -1
	var burnt_tick := -1
	## The photo camera (#786, photo P7): the film loaded in it, as FilmLoaded told it, and the
	## shots on that film so far (ShotTaken's film and count only); -1 and 0 when empty (the film's
	## ItemPickedUp, ItemPlaced or ItemVanished empties it, as the host's PE17). The frames left are
	## the type's `frames_per_film` less `shots` (PhotoUse.frames_left).
	var film := -1
	var shots := 0
	## The photo board (#787): the photos hung on it by slot, as PhotoHung told it; -1 a free slot
	## (an uncounted photo taken down leaves its slot free), no trailing free slots.
	var hung := PackedInt32Array()


## A shot as ShotTaken told it (#787, photo P8): its camera, its film and the record, the avatar
## rows a picture is drawn from (peer, position, facing, downed, crouched, held_item, belt_item).
## Nothing in it names the shooter (PD13) or says whether a person is in the frame (PE5).
class Shot:
	extends RefCounted
	var station := -1
	var film := -1
	var record: Array[Dictionary] = []


## The slots of a cooking place's plate: a bun, a patty and a herb (#776); full, E takes the
## burger (#1101).
const ORDER_SLOTS := 3

## Its own peer id once welcomed; 0 before.
var own_peer := 0
## Its movement epoch: Welcome's, then each Correction's.
var epoch := 0
var phase: StringName = &""
## The countdown's or the match clock's end as a host tick; -1 when none runs.
var end_tick := -1
var roster: Dictionary[int, Member] = {}
## Where each player was last placed: Welcome's spot and positions, PlayerJoined, PlayersPlaced.
var spots: Dictionary[int, Vector3] = {}
var settings: Dictionary[StringName, int] = {}
var id_sets: Dictionary[StringName, PackedStringArray] = {}
var map := ""
## The lobby's name the host set (#214), from Welcome and each SettingsChanged; "" until the host
## names it: the default, which the UI shows as `lobby.default_name` with host_name().
var lobby_name := ""
## What holds all_ready back, as the last SettingsChanged listed it: host texts (#548), each
## {id, ids, numbers}, which HostTextView words in this client's language.
var shortfalls: Array[Dictionary] = []
## The last LoadMatch's id; -1 before the first.
var match_id := -1
## Peers whose load the host confirmed for this match.
var loaded: Dictionary[int, bool] = {}
var start_tick := -1
var role: StringName = &""
## Role -> its players, for a role whose players know each other.
var teammates: Dictionary[StringName, PackedInt32Array] = {}
var items: Dictionary[int, Item] = {}
## Peer -> its selected place, the one in the hand (0..2, GDD §6), from ItemPickedUp and Swapped
## `place`; a peer missing here has the first (0), as at the start of a match.
var selected_places: Dictionary[int, int] = {}
var stations: Dictionary[int, Station] = {}
## Peer -> where its body lies: the dead of this match (Died); a respawn or a leave removes it
## (E26).
var bodies: Dictionary[int, Vector3] = {}
## Peer -> its life state, for the players who are not living (E25): KnockedDown makes one
## downed, Died dead, PlayerLeft left; Respawned and Revived make it living again. Absent means
## living.
var lives: Dictionary[int, Life] = {}
## Downed peer -> the peer raising it, while a raise runs (M4-4): RaiseStarted adds one;
## RaiseStopped, Revived, the leave of either and a new match remove it. The client times the
## raise's progress itself, from RaiseStarted and the mode's raise time.
var raises: Dictionary[int, int] = {}
## Giver -> the peer its hand item is offered to, while the offer is open (#1434, public):
## OfferMade adds one; OfferEnded, the leave of either and a new match remove it.
var offers: Dictionary[int, int] = {}
## Task id -> its public state (TaskState, E30), for the task screen.
var tasks: Dictionary[int, Task] = {}
## Cooking's herbs as HerbsDealt told them (#776): the herb kind id per icon index (the herb
## board) and per bed, in bed station order. Empty before the deal.
var herb_code := PackedStringArray()
var herb_beds := PackedStringArray()
## The photo task's films (#786): film item id -> the shots taken on it, as the ShotTaken events
## told them; a fresh film (no shot) has no entry. Kept wherever the film goes (it keeps its shots,
## the photo ADR's §2.8), dropped at its ItemVanished (printed, or the cap).
var film_shots: Dictionary[int, int] = {}
## The shots whose pictures may still be shown (#787, photo P8), by shot id: each ShotTaken's
## record, kept while a film lists the shot or a photo shows it, as the host's PhotoTask._prune.
var shots: Dictionary[int, Shot] = {}
## The shots each film still lists, by film item id, in shot order (a print moves them to its
## photos); film_shots keeps the frames used, which a print never lowers.
var film_pictures: Dictionary[int, PackedInt32Array] = {}
var tasks_done := 0
var tasks_total := 0
## The winning side once the match ended; empty before.
var winner: StringName = &""
## Why the match ended (MatchEnded, #548): the id of the win condition that ended it, empty when
## none did or before the end; and the round's play time in whole seconds, -1 when it gave none.
var ended_by: StringName = &""
var round_seconds := -1
## The newest snapshot's tick and avatars (peer -> {position, velocity, facing, downed, crouched,
## sneaking, invulnerable, held_item, belt_item}): the other players', and the own player's only
## while it is knocked down (KE5; AvatarViews draws it as its ragdoll, 728d).
var snapshot_tick := -1
var avatars: Dictionary = {}
## Its own SelfStatus (and Damaged's health); -1 until the first arrives.
var health := -1
var stamina := -1
var sprint_available := false
## How drunk the own player is (SelfStatus, #1390; 0 sober, up to the mode's PlayerRules.drunk_max):
## the controller's sway and drift read it (#1391). 0 until a SelfStatus says more, and again on
## clear_match (no host word follows a leave).
var drunk := 0
## Whether the own player sits posed (its SelfStatus, #1383): the snapshot hides the own avatar,
## so this is the only place the posing client learns it; false until a SelfStatus says so.
var posed := false
## Goes up at every fold after which the own player may not have been heard for a while: the
## phase changed, or its own life left living. VoiceSender compares it between its steps, so a
## knockdown and a revive (or Round, End, Lobby) folded between two of them still mark what waits
## in the microphone as recorded unheard (#241).
var silencings := 0
## The estimated host tick now, for _snapshot_floor: AvatarViews sets its host_tick(). A client that
## draws nothing (a bot) has none and floors at the newest snapshot held.
var host_tick_now := Callable()

var _mode: GameMode
## Snapshots of this host tick or older are not folded: clear_match() sets it to the host tick
## estimated at the change, or to the newest snapshot held if that is higher. The newest held
## alone is not enough: the late snapshot is usually newer than every one held (tick T-1 delayed
## past the PhaseChanged of tick T, #251). The host's tick runs on across matches, so a floor never
## holds back a later match's snapshots. -1 before the first clear.
var _snapshot_floor := -1


func _init(mode: GameMode) -> void:
	_mode = mode


## Whether `peer` is living as far as this client knows: never knocked down or dead in this match.
func is_alive(peer: int) -> bool:
	return life_of(peer) == Life.ALIVE


## The life state of `peer` as this client knows it from the public events (E25): ALIVE unless a
## KnockedDown, a Died or a PlayerLeft of this match said otherwise and no Respawned undid it.
func life_of(peer: int) -> Life:
	return lives.get(peer, Life.ALIVE)


## The peer raising `peer` (a downed player) as far as this client knows, or 0 when nobody is.
func raiser_of(peer: int) -> int:
	return raises.get(peer, 0)


## The downed player `raiser` is raising, or 0 when it raises nobody.
func raised_by(raiser: int) -> int:
	for target: int in raises:
		if raises[target] == raiser:
			return target
	return 0


## The peer `giver` offers its hand item to as far as this client knows, or 0 (#1434).
func offer_of(giver: int) -> int:
	return offers.get(giver, 0)


## The item `peer` holds in its hand as the events tell it (ItemPickedUp, Swapped, ItemPlaced), or
## -1. The own player's slots come only from these: its avatar reaches it only while it is
## knocked down (KE5).
func hand_item(peer: int) -> int:
	return _carried(peer, false)


## The item `peer` carries on its belt as the events tell it, or -1: the one in the lower place of
## its two belt places (GDD §6); belt_item2 is the other.
func belt_item(peer: int) -> int:
	var belt := _belt_of(peer)
	return belt[0] if belt.size() > 0 else -1


## The item in the higher of `peer`'s two belt places, or -1.
func belt_item2(peer: int) -> int:
	var belt := _belt_of(peer)
	return belt[1] if belt.size() > 1 else -1


## `peer`'s selected place, the one in its hand (0..2, GDD §6): the keys 1, 2 and 3 show it as 1..3.
func selected_place(peer: int) -> int:
	return selected_places.get(peer, 0)


## The item in `peer`'s place `place` (0..2), or -1.
func item_in_place(peer: int, place: int) -> int:
	for id: int in items:
		if items[id].holder == peer and items[id].carry_place == place:
			return id
	return -1


## Whether the newest snapshot shows `peer` invulnerable (the avatar's flag, M4-3): strikes skip
## it after a respawn or a revive. The own player's arrives only while it is knocked down or limp.
func is_invulnerable(peer: int) -> bool:
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("invulnerable", false)


## Whether the newest snapshot shows `peer` crouched (the avatar's flag, the crouch ADR, KE1): only
## a living player where the crouch plays. The own player's arrives while knocked down or limp.
func is_crouched(peer: int) -> bool:
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("crouched", false)


## Whether the newest snapshot shows `peer` sneaking (the avatar's flag, #990): only a living player
## that is not crouched. The own player's arrives while downed or limp, never sneaking.
func is_sneaking(peer: int) -> bool:
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("sneaking", false)


## life_of(), but DOWNED while the newest snapshot shows `peer` limp (avatar flag, §7.1.21, KE5).
func body_life_of(peer: int) -> Life:
	var limp: bool = (avatars.get(peer, {}) as Dictionary).get("limp", false)
	return Life.DOWNED if limp and life_of(peer) == Life.ALIVE else life_of(peer)


## The client's own copy of the current phase, or null.
func phase_spec() -> PhaseSpec:
	return _mode.find_phase(phase)


## The body colour of `peer` (an index into PlayerColours), 0 for a peer not on the roster.
func colour_of(peer: int) -> int:
	var member: Member = roster.get(peer)
	return member.colour if member != null else 0


## The host's name as the roster has it (its own player is peer 1), or "" when it is not there:
## the default lobby name `lobby.default_name` is built from it (#214).
func host_name() -> String:
	var host: Member = roster.get(NetTransport.HOST_ID)
	return host.name if host != null else ""


## Folds one decoded event into the model.
func fold(event_name: StringName, fields: Dictionary) -> void:
	var phase_before := phase
	var living_before := life_of(own_peer) == Life.ALIVE
	_fold_event(event_name, fields)
	if phase != phase_before or (living_before and life_of(own_peer) != Life.ALIVE):
		silencings += 1


func _fold_event(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		&"Welcome":
			_welcome(fields)
		&"PlayerJoined":
			var member := Member.new()
			member.name = fields["name"]
			member.colour = fields["colour"]
			roster[fields["peer"] as int] = member
			spots[fields["peer"] as int] = fields["spot"]
		&"PlayerLeft":
			var peer: int = fields["peer"]
			roster.erase(peer)
			spots.erase(peer)
			avatars.erase(peer)
			_fold_leave(peer)
		&"ReadyChanged":
			var member: Member = roster.get(fields["peer"] as int)
			if member != null:
				member.ready = fields["ready"]
		&"ProfileChanged":
			var changed: Member = roster.get(fields["peer"] as int)
			if changed != null:
				changed.name = fields["name"]
				changed.colour = fields["colour"]
		&"SettingsChanged":
			settings = fields["settings"]
			id_sets = fields["id_sets"]
			map = fields["map"]
			var listed: Array[Dictionary] = []
			listed.assign(fields["shortfalls"] as Array)
			shortfalls = listed
			lobby_name = fields["lobby_name"]
		&"PhaseChanged":
			_enter(fields["phase"] as StringName)
			end_tick = fields["end_tick"]
		&"PlayersPlaced":
			var placed: Dictionary[int, Vector3] = fields["spots"]
			spots.merge(placed, true)
		&"LoadMatch":
			clear_match()
			match_id = fields["match_id"]
			map = fields["map"]
			settings = fields["settings"]
		&"PlayerLoaded":
			loaded[fields["peer"] as int] = true
		&"RoundStarted":
			start_tick = fields["start_tick"]
		&"RoleAssigned":
			role = fields["role"]
		&"Teammates":
			teammates[fields["role"] as StringName] = fields["peers"]
		_:
			_fold_match_event(event_name, fields)


## Folds one decoded snapshot: its avatars replace the older ones. The model keeps a copy: the
## DecodedView records the same Dictionary, and a PlayerLeft must not change what was decoded. One
## at or below _snapshot_floor is of a match the model forgot and is not folded.
func fold_snapshot(fields: Dictionary) -> void:
	var tick: int = fields["tick"]
	if tick > snapshot_tick and tick > _snapshot_floor:
		snapshot_tick = tick
		avatars = (fields["avatars"] as Dictionary).duplicate(true)


## Forgets a match's facts: on LoadMatch and on entering the lobby. Raises _snapshot_floor.
func clear_match() -> void:
	_snapshot_floor = maxi(_snapshot_floor, snapshot_tick)
	if host_tick_now.is_valid():
		_snapshot_floor = maxi(_snapshot_floor, host_tick_now.call() as int)
	loaded.clear()
	start_tick = -1
	role = &""
	teammates.clear()
	items.clear()
	selected_places.clear()
	tasks.clear()
	stations.clear()
	herb_code = PackedStringArray()
	herb_beds = PackedStringArray()
	film_shots.clear()
	shots.clear()
	film_pictures.clear()
	bodies.clear()
	lives.clear()
	raises.clear()
	offers.clear()
	tasks_done = 0
	tasks_total = 0
	winner = &""
	ended_by = &""
	round_seconds = -1
	snapshot_tick = -1
	avatars = {}
	drunk = 0
	posed = false


func _welcome(fields: Dictionary) -> void:
	own_peer = fields["peer"]
	epoch = fields["epoch"]
	roster.clear()
	for entry: Dictionary in fields["roster"]:
		var member := Member.new()
		member.name = entry["name"]
		member.ready = entry["ready"]
		member.colour = entry["colour"]
		roster[entry["peer"] as int] = member
	settings = fields["settings"]
	map = fields["map"]
	phase = fields["phase"]
	lobby_name = fields["lobby_name"]
	var positions: Dictionary[int, Vector3] = fields["positions"]
	spots = positions.duplicate()
	spots[own_peer] = fields["spot"]


func _fold_match_event(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		&"StationPlaced":
			var station := Station.new()
			station.kind = fields["kind"]
			station.colour = fields["colour"]
			station.position = fields["position"]
			stations[fields["station"] as int] = station
		&"ItemSpawned":
			var item := Item.new()
			item.kind = fields["kind"]
			item.position = fields["position"]
			item.station = fields.get("station", -1)
			item.colour = fields.get("colour", Color.WHITE)
			items[fields["item"] as int] = item
		&"ItemPickedUp", &"Swapped":
			_fold_slots(event_name, fields)
		&"ItemChanged":
			# Another kind where it is (the cooking ADR, CE4): its view is rebuilt with the new look.
			var changed: Item = items.get(fields["item"] as int)
			if changed != null:
				changed.kind = fields["kind"]
		&"OrderPosted", &"BurgerPlated", &"BurgerServed":
			_fold_cooking(event_name, fields)
		&"HerbsDealt":
			var code: PackedStringArray = fields["code"]
			var beds: PackedStringArray = fields["beds"]
			herb_code = code.duplicate()
			herb_beds = beds.duplicate()
		&"IngredientPlaced", &"GrillLoaded":
			_fold_cooking_put(event_name, fields)
		&"FilmLoaded", &"ShotTaken":
			_fold_camera(event_name, fields)
			if event_name == &"ShotTaken":
				ClientShotBook.record(shots, film_pictures, fields)
			ClientShotBook.prune(shots, film_pictures, items)
		&"PhotoPrinted", &"PhotoHung":
			_fold_photo(event_name, fields)
			ClientShotBook.prune(shots, film_pictures, items)
		&"ItemPlaced":
			var item: Item = items.get(fields["item"] as int)
			_unstation(fields["item"] as int)
			if item != null:
				item.holder = NO_HOLDER
				item.belted = false
				item.carry_place = -1
				item.flying = false
				item.position = fields["position"]
		&"ItemThrown":
			_fold_throw(fields)
		&"ItemVanished":
			# Gone for good (the cooking ADR, CE3): its view goes with it; a later ItemSpawned may
			# reuse the id for a new item.
			_unstation(fields["item"] as int)
			items.erase(fields["item"] as int)
			film_pictures.erase(fields["item"] as int)
			ClientShotBook.prune(shots, film_pictures, items)
			film_shots.erase(fields["item"] as int)
		&"PackageDelivered":
			var item: Item = items.get(fields["item"] as int)
			if item != null:
				item.holder = NO_HOLDER
				item.belted = false
				item.carry_place = -1
				item.flying = false
				item.delivered = true
			var station_id: int = fields["station"]
			var station: Station = stations.get(station_id)
			if station != null:
				station.done = _all_delivered_to(station_id)
		&"ZoneProgress":
			_fold_zone(fields)
		&"SwitchChanged", &"ButtonPressed":
			_fold_generator(event_name, fields)
		&"LiftChanged", &"PartNeeded", &"FitChanged":
			_fold_car_repair(event_name, fields)
		&"PartFitted":
			_fold_part_fitted(fields)
		&"TaskProgress":
			tasks_done = fields["done"]
			tasks_total = fields["total"]
		&"TaskState":
			var task := Task.new()
			task.type = fields["type"]
			task.done = fields["done"]
			task.total = fields["total"]
			tasks[fields["task"] as int] = task
		&"Damaged":
			health = fields["health"]
		&"SelfStatus":
			health = fields["health"]
			stamina = fields["stamina"]
			sprint_available = fields["sprint_available"]
			drunk = fields.get("drunk", 0)
			posed = fields.get("posed", false)
		&"KnockedDown", &"Died", &"Respawned":
			_fold_life(event_name, fields)
		&"OfferMade", &"OfferEnded":
			_fold_offer(event_name, fields)
		&"RaiseStarted", &"RaiseStopped", &"Revived":
			_fold_raise(event_name, fields)
		&"Correction":
			epoch = fields["epoch"]
		&"MatchEnded":
			winner = fields["side"]
			ended_by = fields.get("reason", &"")
			var numbers: Dictionary = fields.get("numbers", {})
			round_seconds = numbers.get(&"time", -1)


## The station `fields["station"]` names, or null when the model knows none of that id.
func _station_of(fields: Dictionary) -> Station:
	return stations.get(fields["station"] as int)


## Cooking (#772, #1101): an order posted at its place, a burger plated, a burger served (only a
## right one marks its place done).
func _fold_cooking(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"BurgerPlated":
		var burger: Item = items.get(fields["item"] as int)
		if burger != null:
			burger.parts = PackedStringArray([fields["bun"], fields["patty"], fields["herb"]])
			burger.place = fields["station"]
		return
	var station := _station_of(fields)
	if station == null:
		return
	match event_name:
		&"OrderPosted":
			station.bun = fields["bun"]
			station.patty = fields["patty"]
			station.icon = fields["icon"]
		&"BurgerServed":
			if fields["right"] as bool:
				station.done = true


## ZoneProgress: a zone of the zone task (#36) or the Generator's charge (#797) counting or done.
func _fold_zone(fields: Dictionary) -> void:
	var zone := _station_of(fields)
	if zone == null:
		return
	zone.ticks = fields["ticks"]
	zone.needed = fields["needed"]
	zone.counting = fields["counting"]
	zone.progress_tick = fields["tick"]
	zone.done = zone.needed > 0 and zone.ticks >= zone.needed


## The Generator (#797): a switch toggled or its button pressed.
func _fold_generator(event_name: StringName, fields: Dictionary) -> void:
	var station := _station_of(fields)
	if station == null:
		return
	match event_name:
		&"SwitchChanged":
			station.on = fields["on"]
		&"ButtonPressed":
			station.presses += 1


## The car repair (#807, #808): the lift raised or lowered, the part needed next, a fit started or
## stopped. A completed fit (PartFitted) is _fold_part_fitted's.
func _fold_car_repair(event_name: StringName, fields: Dictionary) -> void:
	var station := _station_of(fields)
	if station == null:
		return
	match event_name:
		&"LiftChanged":
			station.up = fields["up"]
			station.lift_tick = fields["tick"]
			if station.up:
				station.rise_tick = station.lift_tick
		&"PartNeeded":
			station.part = fields["kind"]
		&"FitChanged":
			station.fitter = fields["fitter"]
			station.fit_tick = fields["tick"]


## A pickup puts the item into `place` (GDD §6 "Drawing from the belt"): into the hand, which then
## selects that place, while `belted`, when it names another item, is the old hand item, which stays
## in its place, now on the belt (E29); a hand item that did not fit follows as ItemPlaced. When
## `belted` names the item itself (the cooking ADR, CE20, CE21: a take beside a two-handed hand
## item), it goes straight onto the belt into `place` and the hand item stays held. A swap (a Draw
## or X) selects `place`: its item, if any, comes into the hand and the others hang on the belt.
func _fold_slots(event_name: StringName, fields: Dictionary) -> void:
	var peer: int = fields["peer"]
	var place: int = fields.get("place", 0)
	if event_name == &"Swapped":
		_select(peer, place)
		return
	var id: int = fields["item"]
	var to_belt: int = fields.get("belted", -1)
	_unstation(id)
	_unstation(to_belt)
	var picked: Item = items.get(id)
	if picked != null:
		# A carried item another player takes was handed over (#1389): it rests nowhere between.
		picked.handed_from = picked.holder if picked.holder != peer else NO_HOLDER
		picked.holder = peer
		picked.carry_place = place
	var belted: Item = items.get(to_belt)
	if belted != null:
		belted.holder = peer
	if to_belt != id:
		_select(peer, place)
	elif picked != null:
		picked.belted = true


## `peer`'s selected place is `place` now: the item there is in its hand, its others on its belt.
func _select(peer: int, place: int) -> void:
	selected_places[peer] = place
	for item: Item in items.values():
		if item.holder == peer:
			item.belted = item.carry_place != place


## A put on a cooking place's plate (IngredientPlaced) or on the grill (GrillLoaded, #776): the
## host sends no ItemPlaced for either (Items.lock_at), so the item leaves the putter's hand here
## and lies at the station, locked. Right or wrong is never known here (#1101). Who put it is
## never kept (the ADR's §3).
func _fold_cooking_put(event_name: StringName, fields: Dictionary) -> void:
	var station_id: int = fields["station"]
	var station: Station = stations.get(station_id)
	var item_id: int = fields["item"]
	var item: Item = items.get(item_id)
	if item != null:
		item.holder = NO_HOLDER
		item.belted = false
		item.carry_place = -1
		item.flying = false
		item.on_station = station_id
		item.locked = true
		if station != null:
			item.position = station.position
	if station != null and event_name == &"GrillLoaded":
		station.grill_item = item_id
		station.fried_tick = fields["fried"]
		station.burnt_tick = fields["burnt"]


## The ids of the items on station `station_id` (a cooking place's plate), ascending.
func plated_on(station_id: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	for item_id: int in items:
		if items[item_id].on_station == station_id:
			found.append(item_id)
	found.sort()
	return found


## A film loaded into the photo camera (FilmLoaded) or a shot on it (ShotTaken, #786): the host
## sends no ItemPlaced for the load (Items.lay_on_station), so the film leaves the loader's hand or
## belt here and lies at the camera, unlocked (PickUp takes it out). A shot counts on its film and
## names the camera's film again. Nothing records who loaded or shot (PD13); the record is P8's.
func _fold_camera(event_name: StringName, fields: Dictionary) -> void:
	var station_id: int = fields["station"]
	var camera: Station = stations.get(station_id)
	var film_id: int = fields["item"] if event_name == &"FilmLoaded" else fields["film"]
	if event_name == &"ShotTaken":
		film_shots[film_id] = film_shots.get(film_id, 0) + 1
	else:
		var film: Item = items.get(film_id)
		if film != null:
			film.holder = NO_HOLDER
			film.belted = false
			film.carry_place = -1
			film.flying = false
			film.on_station = station_id
			film.locked = false
			if camera != null:
				film.position = camera.position
	if camera != null:
		camera.film = film_id
		camera.shots = film_shots.get(film_id, 0)


## Clears what a cooking put or a load left on item `item_id` (#776, #786): it lies on no station
## any more, and a grill or a photo camera holding it is empty (no event marks either empty but the
## item's own ItemPickedUp, ItemPlaced or ItemVanished).
func _unstation(item_id: int) -> void:
	if item_id < 0:
		return
	var item: Item = items.get(item_id)
	if item != null:
		item.on_station = -1
		item.locked = false
	for station: Station in stations.values():
		if station.grill_item == item_id:
			station.grill_item = -1
			station.fried_tick = -1
			station.burnt_tick = -1
		if station.film == item_id:
			station.film = -1
			station.shots = 0
		var slot := station.hung.find(item_id)
		if slot >= 0:
			station.hung[slot] = -1
			while not station.hung.is_empty() and station.hung[station.hung.size() - 1] < 0:
				station.hung.resize(station.hung.size() - 1)


## Whether no item routed to the station is still undelivered (DE7 of the delivery-by-meaning
## ADR): a drop-off with two bottles is done after the second. Asked only on a PackageDelivered,
## never on StationPlaced or ItemSpawned, so a drop-off is not done before its items arrive.
func _all_delivered_to(station_id: int) -> bool:
	for item: Item in items.values():
		if item.station == station_id and not item.delivered:
			return false
	return true


## A throw (§7.1.16): the item leaves its thrower's hand and flies, its launch kept exactly as
## sent, until its ItemPlaced or PackageDelivered ends the flight. A phase change ends no flight
## here: the host pauses one in a phase without FlightTicks, and hiding it then is the view's (37e).
func _fold_throw(fields: Dictionary) -> void:
	var item: Item = items.get(fields["item"] as int)
	if item == null:
		return
	_unstation(fields["item"] as int)
	item.holder = NO_HOLDER
	item.belted = false
	item.carry_place = -1
	item.flying = true
	item.thrower = fields["peer"]
	item.flight_origin = fields["origin"]
	item.flight_velocity = fields["velocity"]
	item.flight_gravity = fields["gravity"]
	item.flight_tick = fields["tick"]
	item.position = item.flight_origin


## PartFitted (#808): the part leaves the fitter's hand, locked at the car's use spot, and the
## car has no fitter any more.
func _fold_part_fitted(fields: Dictionary) -> void:
	var car := _station_of(fields)
	if car != null:
		car.fitter = 0
		car.fitted += 1
	var item: Item = items.get(fields["item"] as int)
	if item != null:
		item.holder = NO_HOLDER
		item.belted = false
		item.carry_place = -1
		item.flying = false
		item.fitted = true
		if car != null:
			item.position = car.position


## The item `peer` carries in the hand (`on_belt` false) or on the belt, or -1.
func _carried(peer: int, on_belt: bool) -> int:
	for id: int in items:
		var item := items[id]
		if item.holder == peer and item.belted == on_belt:
			return id
	return -1


## The items on `peer`'s belt, in place order (an item of no known place last).
func _belt_of(peer: int) -> Array[int]:
	var belt: Array[int] = []
	for id: int in items:
		if items[id].holder == peer and items[id].belted:
			belt.append(id)
	belt.sort_custom(func(a: int, b: int) -> bool: return _order(a) < _order(b))
	return belt


func _order(id: int) -> int:
	var at := items[id].carry_place
	return at if at >= 0 else PLACES


## A knockdown makes its player downed; a death makes it dead, with its body; a respawn makes it
## living again and removes its body (E25, E26).
func _fold_life(event_name: StringName, fields: Dictionary) -> void:
	var peer: int = fields["peer"]
	if event_name == &"KnockedDown":
		lives[peer] = Life.DOWNED
	elif event_name == &"Respawned":
		lives.erase(peer)
		bodies.erase(peer)
	else:
		lives[peer] = Life.DEAD
		bodies[peer] = fields["position"]


## A raise starting records its raiser; one stopping forgets it; a revive also makes the raised
## player living again (M4-4).
func _fold_raise(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"RaiseStarted":
		raises[fields["target"] as int] = fields["raiser"] as int
	elif event_name == &"RaiseStopped":
		raises.erase(fields["target"] as int)
	else:
		var peer: int = fields["peer"]
		raises.erase(peer)
		lives.erase(peer)


## An offer made records its target; one ended forgets it (#1434).
func _fold_offer(event_name: StringName, fields: Dictionary) -> void:
	var giver: int = fields["giver"]
	if event_name == &"OfferMade":
		offers[giver] = fields["target"] as int
	elif offers.get(giver, 0) == (fields["target"] as int):
		offers.erase(giver)


## A player who left mid-match leaves no body (E26, the engineer's answer 1 on PR #133).
func _fold_leave(peer: int) -> void:
	bodies.erase(peer)
	lives[peer] = Life.LEFT
	# The host stops a raise of or by a leaver first (RaiseStopped); a lost order changes nothing.
	raises.erase(peer)
	var raised := raised_by(peer)
	if raised != 0:
		raises.erase(raised)
	# The host ends an offer of or to a leaver first (OfferEnded); a lost order changes nothing.
	offers.erase(peer)
	for giver: int in offers.keys():
		if offers[giver] == peer:
			offers.erase(giver)


## Enters `next`: a match's facts are cleared when it plays in the lobby and the phase before did
## not (End -> Lobby), so a lobby holds no items or bodies of the match before.
func _enter(next: StringName) -> void:
	var before := phase_spec()
	phase = next
	var after := phase_spec()
	var in_lobby := after != null and after.level == PhaseSpec.Level.LOBBY
	if in_lobby and (before == null or before.level != PhaseSpec.Level.LOBBY):
		clear_match()


## A printed photo shows its shot (PhotoPrinted), which leaves its film's list; a hung photo
## (PhotoHung) leaves the hand or belt for the board's next free slot: locked there when counted,
## else lying on it for a PickUp to take down. The host sends no ItemPlaced for a hang.
func _fold_photo(event_name: StringName, fields: Dictionary) -> void:
	var photo: Item = items.get(fields["item"] as int)
	if event_name == &"PhotoPrinted":
		var shot_id: int = fields["shot"]
		ClientShotBook.unlist(film_pictures, shot_id)
		if photo != null:
			photo.shot = shot_id
		return
	var board: Station = stations.get(fields["station"] as int)
	if photo == null:
		return
	photo.holder = NO_HOLDER
	photo.belted = false
	photo.carry_place = -1
	photo.flying = false
	photo.on_station = fields["station"]
	photo.locked = fields["counted"]
	if board == null:
		return
	photo.position = board.position
	var slot := hang_slot(board)
	if slot == board.hung.size():
		board.hung.append(fields["item"] as int)
	else:
		board.hung[slot] = fields["item"]


## The slot of `board` the next hung photo takes: the lowest free one (a taken-down uncounted
## photo's), else a new one after the last. Counted photos never move.
static func hang_slot(board: Station) -> int:
	var free := board.hung.find(-1)
	return free if free >= 0 else board.hung.size()
