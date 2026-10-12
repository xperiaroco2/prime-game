class_name PhotoTask
extends TaskType
## The photo task (#687; ARCHITECTURE §9.5; the photo ADR, its part P2 #781): one shared task whose
## subtasks are the photos with a person hung on the board, N the subtasks setting. Nobody owns
## it: any living player of any role loads the camera, takes a shot, takes a film from the box,
## prints and hangs (Interact, through the station kinds' rules; PD1). P2 builds the deal, the
## load and the shot; the film box, the printer and the board refuse every use `unavailable` until
## P3 (#782) gives them theirs.
##
## The deal (DealTasks calls deal() when the draw picks it; ADR §2.1): with N = 0 nothing at all
## (the task has no subtasks and is done, #79). Else a station on the one marker of each of the five
## kinds, in the order camera, photo spot, film box, printer, board (station ids in that order),
## StationPlaced for each in id order, then one fresh film on the `film` marker: ItemSpawned, then
## item_rested with the spawn cause (PE11). No RNG: nothing is drawn.
##
## The camera (ADR §2.2, §2.3; PE17): it holds a film while the film it was loaded with still lies
## where the load laid it, the same item (the ItemState itself, so a vanished film's recycled id
## never matches) with the move serial (ItemState.moves) the load left. Any lift (a pick-up, a
## take onto the belt beside a two-handed item) or a vanish empties it, whatever the tick. An
## Interact at an empty camera loads: the fresh film the actor holds in the hand, else on the belt,
## lies at the camera (Items.lay_on_station, item_rested `on_station`, no ItemPlaced), and
## FilmLoaded goes to everyone. At a loaded camera it shoots: the film's next shot, who is in the
## frame (ADR §3.2: ALIVE players with their feet outside the camera's cylinder, so never the
## shooter, whose head lies in the PhotoFrame with a clear line from the lens; has_person never
## sent, PE5) and the record (ADR §3.3), then ShotTaken to everyone. A film with no shot is fresh;
## shots stay on their film whoever carries it, until ResetMatch (ADR §2.8).
##
## Refusals (use_problem, after HandNotTwoHanded, AtStation and StationInSight): `unavailable` once
## the task is done (PD12) and at every station but the camera (P2); at a loaded camera
## `no_frames_left` when its film has frames_per_film shots; at an empty one `no_film` when the
## actor carries no film, `film_exposed` when every film it carries has a shot (PD16 (a)). None
## reads a role; each names only what the actor carries or the camera's public state.
##
## Emits: StationPlaced and ItemSpawned (everyone) in the deal; FilmLoaded and ShotTaken
## (everyone) on a use (use_emits). Raises item_rested (spawn) in the deal and (on_station) at a
## load. No event names a player (PD13).

## How far beyond range_m from the lens a player still goes into the record (ADR §3.3: generous, the
## renderer clips the rest).
const RECORD_MARGIN_M := 2.0
## The record's most rows: the snapshot's most avatars (ADR §3.3; WireSchema.MAX_AVATARS).
const MAX_RECORD := 15
## Shot ids wrap here: ShotTaken's `shot` is a u16.
const SHOT_IDS := 0x10000
## The bounds of the frame's numbers (PE12).
const MIN_FOV_DEG := 1.0
const MAX_FOV_DEG := 179.0
const MIN_ASPECT := 0.25
const MAX_ASPECT := 4.0
const MIN_RANGE_M := 0.5
const MAX_RANGE_M := 100.0


## One shot (ADR §2.3): its film's item id, the host tick, whether any candidate counted, and who.
class Shot:
	extends RefCounted

	var id := 0
	var film := -1
	var tick := 0
	var has_person := false
	## The peers that counted, in peer order (ADR §3.2's `subjects`).
	var subjects := PackedInt32Array()


## A film with at least one shot: the item itself (identity, so a recycled id is another film)
## and its shots' ids, in shot order.
class Film:
	extends RefCounted

	var item: ItemState
	var shots := PackedInt32Array()


## The photo task's state (§9.1): the station ids, the photos to hang, the camera's film, the
## shots and the films that have them, and the counted photos (P3 fills it). Only PhotoTask reads
## and writes it; nothing of it is sent but through its events.
class State:
	extends TaskState

	var camera := -1
	var photo_spot := -1
	var film_box := -1
	var printer := -1
	var board := -1
	## The subtasks: the setting at the deal.
	var photos := 0
	## The film the camera was loaded with, and its move serial after the load (PE17).
	var loaded: ItemState = null
	var loaded_moves := -1
	var next_shot := 0
	var shots: Dictionary[int, Shot] = {}
	## Film item id -> its entry.
	var films: Dictionary[int, Film] = {}
	## The shots whose photos were hung counted (P3).
	var counted := PackedInt32Array()

	func done_count() -> int:
		return mini(counted.size(), photos)

	func total() -> int:
		return photos

	func is_done() -> bool:
		return done_count() >= photos

	## The entry of `item` if it is that very film and has a shot, else null (fresh).
	func film_of(item: ItemState) -> Film:
		var entry: Film = films.get(item.id)
		return entry if entry != null and entry.item == item else null


@export var camera: StationKind
## A display kind (C1): its marker is the aim; nobody uses it.
@export var photo_spot: StationKind
@export var film_box: StationKind
@export var printer: StationKind
@export var board: StationKind
@export var film: ItemKind
@export var photo: ItemKind
## The photo task's own subtasks setting: the photos with a person to hang.
@export var subtasks_setting: StringName
## How many shots a film takes. At least 1. The neutral default is out of bounds on purpose.
@export var frames_per_film := 0
## The frame's vertical field of view in degrees, 1 to 179. Out of bounds by default on purpose.
@export var fov_deg := 0.0
## The frame's width over its height, 0.25 to 4. Out of bounds by default on purpose.
@export var aspect := 0.0
## How far from the lens a head still counts, 0.5 to 100 metres. Out of bounds by default.
@export var range_m := 0.0


func new_state() -> TaskState:
	return State.new()


func item_spawn_tags() -> Array[StringName]:
	if film == null:
		return []
	return [film.spawn_tag]


func deal(ctx: MatchContext) -> void:
	var count := maxi(ctx.setting(subtasks_setting), 0)
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	task_state.photos = count
	if count == 0 or not _fits(ctx):
		return
	var placed: Array[StationState] = []
	for kind: StationKind in _kinds():
		placed.append(
			ctx.state.add_station(kind, ctx.layout.positions(kind.spawn_tag)[0], Color.WHITE)
		)
	task_state.camera = placed[0].id
	task_state.photo_spot = placed[1].id
	task_state.film_box = placed[2].id
	task_state.printer = placed[3].id
	task_state.board = placed[4].id
	for station: StationState in placed:
		ctx.emit(
			StationPlacedEvent.new(station.id, station.kind.id, station.colour, station.position)
		)
	var free := Items.free_markers(ctx, film.spawn_tag)
	if free.is_empty():
		ctx.error("PhotoTask: an item already rests on the %s marker" % film.spawn_tag)
		return
	var item := Items.spawn(ctx, film, free[0])
	if item == null:
		return  # Every item id in use (Items.spawn logged it).
	ctx.emit(ItemSpawnedEvent.new(item.id, film.id, item.position))
	Items.raise_rested(ctx, item, Items.SPAWN)


func use_problem(ctx: MatchContext, task: MatchTask, station: StationState) -> StringName:
	if task == null:
		return StationUsable.UNAVAILABLE
	var task_state := task.state as State
	if task_state.is_done() or station.id != task_state.camera:
		return StationUsable.UNAVAILABLE
	var loaded := _loaded(ctx, task_state)
	if loaded != null:
		var entry := task_state.film_of(loaded)
		var shots := entry.shots.size() if entry != null else 0
		return StationUsable.NO_FRAMES_LEFT if shots >= frames_per_film else &""
	var carried := _carried_films(ctx)
	if carried.is_empty():
		return StationUsable.NO_FILM
	if _fresh(task_state, carried) == null:
		return StationUsable.FILM_EXPOSED
	return &""


func use_reasons() -> Array[StringName]:
	return [
		StationUsable.UNAVAILABLE,
		StationUsable.NO_FILM,
		StationUsable.NO_FRAMES_LEFT,
		StationUsable.FILM_EXPOSED,
	]


func use_station(ctx: MatchContext, task: MatchTask, station: StationState) -> void:
	if task == null:
		return  # StationUsable refused it.
	var task_state := task.state as State
	if station.id != task_state.camera:
		ctx.error("PhotoTask: station %d takes no use yet" % station.id)
		return
	var loaded := _loaded(ctx, task_state)
	if loaded != null:
		_shoot(ctx, task_state, station, loaded)
		return
	var fresh := _fresh(task_state, _carried_films(ctx))
	if fresh == null:
		ctx.error("PhotoTask: player %d carries no fresh film to load" % ctx.actor)
		return
	Items.lay_on_station(ctx, fresh, station.position)
	task_state.loaded = fresh
	task_state.loaded_moves = fresh.moves
	ctx.emit(FilmLoadedEvent.new(station.id, fresh.id))


func use_emits() -> Array[Script]:
	return [FilmLoadedEvent, ShotTakenEvent]


## Exactly one marker of each station kind's tag, one `photo` marker (the printer's tray) and one
## `film` marker, whatever the setting and the players (PE12, GE10).
func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	for kind: StationKind in _kinds():
		if kind == null:
			return  # The check refuses such a mode.
		into.add_markers(kind.spawn_tag, 1, true)
	for kind: ItemKind in [film, photo]:
		if kind == null:
			return
		into.add_markers(kind.spawn_tag, 1, true)


func emits() -> Array[Script]:
	return [StationPlacedEvent, ItemSpawnedEvent, FilmLoadedEvent, ShotTakenEvent]


## The level fit check (PE12): a photo spot marker no farther than the camera kind's radius plus
## the photo spot kind's from the camera's marker horizontally is refused, so no part of the spot
## lies in the camera's reach (PD18) and the frame never looks straight up or down.
func layout_problems(map: String, layout: LevelLayout) -> PackedStringArray:
	var found := PackedStringArray()
	if camera == null or photo_spot == null:
		return found
	var apart := camera.radius_m + photo_spot.radius_m
	for at: Vector3 in layout.positions(camera.spawn_tag):
		for spot: Vector3 in layout.positions(photo_spot.spawn_tag):
			if Vector2(spot.x - at.x, spot.z - at.z).length() <= apart:
				found.append(
					(
						"%s: PhotoTask %s's %s marker at %s lies within %s m of the %s marker at %s"
						% [map, id, photo_spot.spawn_tag, spot, apart, camera.spawn_tag, at]
					)
				)
	return found


## PE12: the five station kinds, with different spawn tags; the photo spot a display kind with no
## rule; the four others each an Interact rule ending in UseStation, the box's paying a Cooldown;
## the film and photo kinds declared by the mode, one-handed, their spawn tags none of a station
## kind's; frames_per_film at least 1; the frame's numbers within bounds; the subtasks setting a
## declared whole number from at least 0; the item kinds' caps (CE3's floor).
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	var names := ["camera", "photo_spot", "film_box", "printer", "board"]
	var kinds := _kinds()
	var tags: Array[StringName] = []
	for i in kinds.size():
		var kind := kinds[i]
		if kind == null:
			found.append("PhotoTask %s has no %s station kind" % [id, names[i]])
			continue
		if tags.has(kind.spawn_tag):
			found.append(
				"PhotoTask %s: station kinds share the spawn tag %s" % [id, kind.spawn_tag]
			)
		tags.append(kind.spawn_tag)
		if kind == photo_spot:
			if not kind.display or not kind.actions.is_empty():
				found.append(
					(
						"PhotoTask %s: photo spot kind %s must be a display kind with no rule"
						% [id, kind.id]
					)
				)
		elif not _ends_in_use(kind):
			found.append(
				"PhotoTask %s: station kind %s has no Interact rule with UseStation" % [id, kind.id]
			)
		elif kind == film_box and not _pays_cooldown(kind):
			found.append("PhotoTask %s: film box kind %s pays no Cooldown" % [id, kind.id])
	_check_items(mode, tags, found)
	if frames_per_film < 1:
		found.append("PhotoTask %s has %d frames_per_film, fewer than 1" % [id, frames_per_film])
	append_found(
		found,
		[
			out_of_bounds("PhotoTask %s fov_deg" % id, fov_deg, MIN_FOV_DEG, MAX_FOV_DEG),
			out_of_bounds("PhotoTask %s aspect" % id, aspect, MIN_ASPECT, MAX_ASPECT),
			out_of_bounds("PhotoTask %s range_m" % id, range_m, MIN_RANGE_M, MAX_RANGE_M),
		]
	)
	if subtasks_setting.is_empty():
		found.append("PhotoTask %s has no subtasks_setting" % id)
	elif mode != null:
		var spec := mode.find_setting(subtasks_setting)
		if spec != null and spec.is_number() and spec.min_value < 0:
			found.append("PhotoTask %s: setting %s goes below 0" % [id, subtasks_setting])
	if mode != null:
		_check_caps(mode, found)
	return found


## The station kinds in station-id order.
func _kinds() -> Array[StationKind]:
	return [camera, photo_spot, film_box, printer, board]


func _check_items(mode: GameMode, tags: Array[StringName], found: PackedStringArray) -> void:
	var item_names := ["film", "photo"]
	var items: Array[ItemKind] = [film, photo]
	for i in items.size():
		var kind := items[i]
		if kind == null:
			found.append("PhotoTask %s has no %s item kind" % [id, item_names[i]])
			continue
		if mode != null and mode.find_item_kind(kind.id) != kind:
			found.append(
				"PhotoTask %s names item kind %s, which the mode does not declare" % [id, kind.id]
			)
		if kind.is_two_handed():
			found.append("PhotoTask %s: item kind %s is two-handed" % [id, kind.id])
		if kind.spawn_tag.is_empty():
			found.append("PhotoTask %s: item kind %s has no spawn_tag" % [id, kind.id])
		elif tags.has(kind.spawn_tag):
			found.append(
				(
					"PhotoTask %s: item kind %s shares the spawn tag %s with a station kind"
					% [id, kind.id, kind.spawn_tag]
				)
			)


## The film's cap at least twice the most players plus 1; the photo's at least twice the most
## players plus the setting's maximum plus frames_per_film plus 1 (PE12, CE3's floor).
func _check_caps(mode: GameMode, found: PackedStringArray) -> void:
	var most := 0
	var spec := mode.find_setting(subtasks_setting) if not subtasks_setting.is_empty() else null
	if spec != null and spec.is_number():
		most = maxi(spec.max_value, 0)
	var hands := 2 * mode.max_players
	if film != null and film.max_items < hands + 1:
		found.append(
			(
				"PhotoTask %s: film kind %s has max_items %d, below %d (twice %d players, 1)"
				% [id, film.id, film.max_items, hands + 1, mode.max_players]
			)
		)
	var least := hands + most + maxi(frames_per_film, 0) + 1
	if photo != null and photo.max_items < least:
		var text := "PhotoTask %s: photo kind %s has max_items %d, below %d"
		text += " (twice %d players, %d photos, %d frames, 1)"
		found.append(
			text % [id, photo.id, photo.max_items, least, mode.max_players, most, frames_per_film]
		)


static func _ends_in_use(kind: StationKind) -> bool:
	for rule: Rule in kind.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		if rule.effects[-1] is UseStation:
			return true
	return false


## Whether an Interact rule of `kind` that ends in UseStation pays a Cooldown (PE14).
static func _pays_cooldown(kind: StationKind) -> bool:
	for rule: Rule in kind.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		if not (rule.effects[-1] is UseStation):
			continue
		for condition: Condition in rule.conditions:
			if condition is Cooldown:
				return true
	return false


## Whether the level being entered has a marker of each station kind and of the film's tag; the
## fit check keeps a match from getting here without them.
func _fits(ctx: MatchContext) -> bool:
	if ctx.layout == null:
		ctx.error("PhotoTask: no layout for the level being entered")
		return false
	var tags: Array[StringName] = [film.spawn_tag]
	for kind: StationKind in _kinds():
		tags.append(kind.spawn_tag)
	for tag: StringName in tags:
		if ctx.layout.count(tag) < 1:
			ctx.error("PhotoTask: the map has no %s marker" % tag)
			return false
	return true


## The camera's film (PE17): the item it was loaded with, while that very ItemState is still in the
## match, lying, with the move serial the load left; else null (the camera is empty).
func _loaded(ctx: MatchContext, task_state: State) -> ItemState:
	var item := task_state.loaded
	if item == null:
		return null
	if ctx.state.items.get(item.id) != item:
		return null
	if item.where != ItemState.Where.GROUND or item.moves != task_state.loaded_moves:
		return null
	return item


## The films the actor carries: the hand's, then the belt's.
func _carried_films(ctx: MatchContext) -> Array[ItemState]:
	var found: Array[ItemState] = []
	for item: ItemState in [
		Items.held_by(ctx.state, ctx.actor), Items.belted_by(ctx.state, ctx.actor)
	]:
		if item != null and item.kind == film:
			found.append(item)
	return found


## The first fresh film of `carried` (no shot yet), or null.
func _fresh(task_state: State, carried: Array[ItemState]) -> ItemState:
	for item: ItemState in carried:
		if task_state.film_of(item) == null:
			return item
	return null


## The shot (ADR §2.3, §3.2, §3.3): who counts, the record, the film's next shot, then ShotTaken.
func _shoot(ctx: MatchContext, task_state: State, station: StationState, item: ItemState) -> void:
	var eye := Vector3.UP * _eye_height(ctx)
	var lens := station.position + eye
	var spot: StationState = ctx.state.stations.get(task_state.photo_spot)
	var aim := spot.position + eye if spot != null else lens + Vector3.FORWARD
	var frame := PhotoFrame.between(lens, aim, fov_deg, aspect, range_m)
	var shot := Shot.new()
	shot.id = task_state.next_shot
	shot.film = item.id
	shot.tick = ctx.tick
	var record: Array[Dictionary] = []
	var peers := ctx.state.present_peers()
	peers.sort()
	for peer: int in peers:
		var player := ctx.state.player(peer)
		if player.life != PlayerState.Life.ALIVE and player.life != PlayerState.Life.DOWNED:
			continue
		if station.contains(player.position):
			continue
		if player.life == PlayerState.Life.ALIVE:
			var head := player.position + eye
			if frame.contains(head) and ctx.world.line_of_sight(lens, head):
				shot.subjects.append(peer)
		if (
			record.size() < MAX_RECORD
			and player.position.distance_to(lens) <= range_m + RECORD_MARGIN_M
		):
			(
				record
				. append(
					{
						"peer": peer,
						"position": player.position,
						"facing": player.facing,
						"downed": player.life == PlayerState.Life.DOWNED,
						"held_item": player.held_item,
						"belt_item": player.belt_item,
					}
				)
			)
	shot.has_person = not shot.subjects.is_empty()
	task_state.next_shot = (task_state.next_shot + 1) % SHOT_IDS
	task_state.shots[shot.id] = shot
	var entry := task_state.film_of(item)
	if entry == null:
		entry = Film.new()
		entry.item = item
		task_state.films[item.id] = entry
	entry.shots.append(shot.id)
	ctx.emit(ShotTakenEvent.new(station.id, item.id, shot.id, record))


func _eye_height(ctx: MatchContext) -> float:
	if ctx.state.player_rules == null:
		ctx.error("PhotoTask: the mode has no PlayerRules; the lens stands at the marker")
		return 0.0
	return ctx.state.player_rules.eye_height_m
