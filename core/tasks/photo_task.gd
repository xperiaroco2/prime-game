class_name PhotoTask
extends TaskType
## The photo task (#687; ARCHITECTURE §9.5; the photo ADR, its parts P2 #781 and P3 #782): one
## shared task whose subtasks are the photos with a person hung on the board, N the subtasks
## setting. Nobody owns it: any living player of any role loads the camera, takes a shot, takes a
## film from the box, prints and hangs (Interact, through the station kinds' rules; PD1).
##
## The deal (DealTasks calls deal() when the draw picks it; ADR §2.1): with N = 0 nothing at all
## (the task has no subtasks and is done, #79). Else a station on the one marker of each of the five
## kinds, in the order camera, photo spot, film box, printer, board (station ids in that order),
## StationPlaced for each in id order, then one fresh film on the `film` marker: ItemSpawned, then
## item_rested with the spawn cause (PE11). The `photo` marker is the printer's tray. No RNG.
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
## shots stay on their film whoever carries it, until it is printed (ADR §2.8).
##
## The box (ADR §2.5, PE7): a new film, given to the actor by GiveItem.give_new (the film kind's
## cap, ItemSpawned, Items.give, ItemPickedUp), also once the task is done (PD12). The printer
## (§2.6, PD3, PD16 (a), PE8): the actor's film with a shot (the hand's, else the belt's) prints
## every shot it has, in shot order, each a photo on the tray (the photo kind's cap, ItemSpawned,
## PhotoPrinted, item_rested `spawn`), then the film vanishes (Items.vanish, ItemVanished). The
## board (§2.7, PD6, PE9): the actor's photo (the hand's, else the belt's) with a person in its shot
## is locked there for good (Items.lock_at), PhotoHung counted, then the next subtask is done
## (Tasks.subtask_done: TaskState, TaskProgress); one without lies there (Items.lay_on_station),
## PhotoHung not counted, for PickUp to take down. The cap (PE10, cap_tier): a fresh film outside
## the camera vanishes before one with shots, the camera's film last; every photo alike. A vanish
## in a command of this type drops the vanished item's entries in that command (_prune).
##
## Refusals (use_problem, after the rule's HandNotTwoHanded, AtStation and StationInSight): the box
## only `unavailable` when the film kind is at its cap with none loose (GiveItem.cap_problem); the
## others `unavailable` once the task is done (PD12); at a loaded camera `no_frames_left` when its
## film has frames_per_film shots; at an empty one `no_film` when the actor carries no film,
## `film_exposed` when every film it carries has a shot (PD16 (a)); at the printer
## `nothing_to_print` when no film the actor carries has a shot; at the board `no_photo` when it
## carries no photo. None reads a role; each names only what the actor carries or public state.
##
## Emits: StationPlaced and ItemSpawned (everyone) in the deal; on a use (use_emits) FilmLoaded,
## ShotTaken, PhotoPrinted, PhotoHung, ItemSpawned, ItemVanished, Items.give's ItemPlaced and
## ItemPickedUp, TaskState and TaskProgress (everyone). Raises item_rested (spawn) in the deal and
## at a print, (on_station) at a load and an uncounted hang, and subtask_done at a counted hang.
## No event names a player (PD13).

## The centimetres of a metre, for the whole-number arguments of HostText.PHOTO_SPOT_NEAR.
const CM := 100.0
## How far beyond range_m from the lens a player still goes into the record (ADR §3.3: generous, the
## renderer clips the rest).
const RECORD_MARGIN_M := 2.0
## The record's most rows: the most avatars but the photographer's own (ADR §3.3;
## WireSchema.MAX_OTHER_AVATARS).
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


## A printed photo: the item itself (identity, as Film) and the shot it shows.
class Print:
	extends RefCounted

	var item: ItemState
	var shot := 0


## The photo task's state (§9.1): the station ids, the tray, the photos to hang, the camera's film,
## the shots, the films that have them, the printed photos and the counted shots. Only PhotoTask
## reads and writes it; nothing of it is sent but through its events.
class State:
	extends TaskState

	var camera := -1
	var photo_spot := -1
	var film_box := -1
	var printer := -1
	var board := -1
	## The printer's tray: the `photo` marker of the level dealt on (PE8).
	var tray := Vector3.ZERO
	## The subtasks: the setting at the deal.
	var photos := 0
	## The film the camera was loaded with, and its move serial after the load (PE17).
	var loaded: ItemState = null
	var loaded_moves := -1
	var next_shot := 0
	var shots: Dictionary[int, Shot] = {}
	## Film item id -> its entry.
	var films: Dictionary[int, Film] = {}
	## Photo item id -> its entry.
	var print_entries: Dictionary[int, Print] = {}
	## The shots whose photos were hung counted, in hang order.
	var counted := PackedInt32Array()

	func done_count() -> int:
		return mini(counted.size(), photos)

	func total() -> int:
		return photos

	func is_done() -> bool:
		return done_count() >= photos

	## The entry of `item` if it is that very film and has a shot, else null (fresh).
	## The next shot id no live shot has: a wrapped counter must not hand out the id that a photo
	## still unhung shows, since the hang reads its shot by id.
	func free_shot_id() -> int:
		var id := next_shot
		while shots.has(id):
			id = (id + 1) % SHOT_IDS
		return id

	func film_of(item: ItemState) -> Film:
		var entry: Film = films.get(item.id)
		return entry if entry != null and entry.item == item else null

	## The entry of `item` if it is that very photo, printed by this task, else null.
	func print_of(item: ItemState) -> Print:
		var entry: Print = print_entries.get(item.id)
		return entry if entry != null and entry.item == item else null


@export var camera: StationKind
## A display kind (C1): its marker is the aim; nobody uses it.
@export var photo_spot: StationKind
@export var film_box: StationKind
@export var printer: StationKind
@export var board: StationKind
@export var film: ItemKind
@export var photo: ItemKind
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
	task_state.tray = ctx.layout.positions(photo.spawn_tag)[0]
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
	if station.id == task_state.film_box:
		return GiveItem.cap_problem(ctx.state, film)
	if task_state.is_done():
		return StationUsable.UNAVAILABLE
	var problem := StationUsable.UNAVAILABLE
	if station.id == task_state.camera:
		problem = _camera_problem(ctx, task_state)
	elif station.id == task_state.printer:
		problem = &"" if _exposed(ctx, task_state) != null else StationUsable.NOTHING_TO_PRINT
	elif station.id == task_state.board:
		problem = &"" if _carried_photo(ctx) != null else StationUsable.NO_PHOTO
	return problem


func use_reasons() -> Array[StringName]:
	return [
		StationUsable.UNAVAILABLE,
		StationUsable.NO_FILM,
		StationUsable.NO_FRAMES_LEFT,
		StationUsable.FILM_EXPOSED,
		StationUsable.NOTHING_TO_PRINT,
		StationUsable.NO_PHOTO,
	]


func use_station(ctx: MatchContext, task: MatchTask, station: StationState) -> void:
	if task == null:
		return  # StationUsable refused it.
	var task_state := task.state as State
	if station.id == task_state.film_box:
		GiveItem.give_new(ctx, film, station.position)
		_prune(ctx.state, task_state)
	elif station.id == task_state.camera:
		_use_camera(ctx, task_state, station)
	elif station.id == task_state.printer:
		_print(ctx, task_state)
	elif station.id == task_state.board:
		_hang(ctx, task, station)
	else:
		ctx.error("PhotoTask: station %d takes no use" % station.id)


func use_emits() -> Array[Script]:
	return [
		FilmLoadedEvent,
		ShotTakenEvent,
		PhotoPrintedEvent,
		PhotoHungEvent,
		ItemSpawnedEvent,
		ItemVanishedEvent,
		ItemPlacedEvent,
		ItemPickedUpEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]


## PE10's tiers for the film kind's cap: 2 the film in the camera, 1 a film with shots elsewhere, 0
## a fresh one; every photo 0, since a tier by its shot's person would tell everyone through
## ItemVanished which photos hold one (PE5). Which film has shots and which lies in the camera are
## public already (FilmLoaded, ShotTaken, film_exposed).
func cap_tier(state: MatchState, item: ItemState) -> int:
	if film == null or item.kind != film:
		return 0
	var task := Stations.task_of(state, self)
	if task == null:
		return 0
	var task_state := task.state as State
	if _loaded_in(state, task_state) == item:
		return 2
	return 1 if task_state.film_of(item) != null else 0


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
	return [
		StationPlacedEvent,
		ItemSpawnedEvent,
		FilmLoadedEvent,
		ShotTakenEvent,
		PhotoPrintedEvent,
		PhotoHungEvent,
		ItemVanishedEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]


## The level fit check (PE12, FitCheck and LayoutCheck through TaskType.layout_problems): a photo
## spot marker no farther than the camera kind's radius plus the photo spot kind's from the
## camera's marker horizontally is refused, so no part of the spot lies in the camera's reach
## (PD18) and the frame never looks straight up or down. HostText.PHOTO_SPOT_NEAR, only when the
## map holds one marker of each (the demands report any other count).
func layout_problems(layout: LevelLayout) -> Array[HostText]:
	var found: Array[HostText] = []
	if camera == null or photo_spot == null:
		return found
	if layout.count(camera.spawn_tag) != 1 or layout.count(photo_spot.spawn_tag) != 1:
		return found
	var apart := camera.radius_m + photo_spot.radius_m
	var at := layout.positions(camera.spawn_tag)[0]
	var spot := layout.positions(photo_spot.spawn_tag)[0]
	var length := Vector2(spot.x - at.x, spot.z - at.z).length()
	if length <= apart:
		found.append(
			HostText.of(
				HostText.PHOTO_SPOT_NEAR,
				PackedStringArray([photo_spot.spawn_tag, camera.spawn_tag]),
				{&"need": ceili(apart * CM), &"have": floori(length * CM)}
			)
		)
	return found


func most_layout_problems() -> int:
	return 1


## PE12: the five station kinds, with different spawn tags; the photo spot a display kind with no
## rule; the four others each an Interact rule ending in UseStation, the box's paying a Cooldown;
## the film and photo kinds declared by the mode, one-handed, their spawn tags none of a station
## kind's; frames_per_film at least 1; the frame's numbers within bounds; the item
## kinds' caps (CE3's floor). The subtasks setting, from at least 0, is TaskType.check's (G0).
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


## Whether the level being entered has a marker of each station kind and of the film's and the
## photo's tags; the fit check keeps a match from getting here without them.
func _fits(ctx: MatchContext) -> bool:
	if not has_layout(ctx, "PhotoTask"):
		return false
	var needs: Dictionary[StringName, int] = {film.spawn_tag: 1, photo.spawn_tag: 1}
	for kind: StationKind in _kinds():
		needs[kind.spawn_tag] = 1
	var lacking := short_markers(ctx.layout, needs)
	if lacking.is_empty():
		return true
	ctx.error("PhotoTask: the map has no %s marker" % lacking.keys()[0])
	return false


## The camera's refusal (ADR §2.2, §2.3): at a loaded camera `no_frames_left` once its film has
## every frame shot; at an empty one `no_film` or `film_exposed` by what the actor carries.
func _camera_problem(ctx: MatchContext, task_state: State) -> StringName:
	var loaded := _loaded_in(ctx.state, task_state)
	if loaded != null:
		var entry := task_state.film_of(loaded)
		var shots := entry.shots.size() if entry != null else 0
		return StationUsable.NO_FRAMES_LEFT if shots >= frames_per_film else &""
	var carried := _carried(ctx, film)
	if carried.is_empty():
		return StationUsable.NO_FILM
	if _fresh(task_state, carried) == null:
		return StationUsable.FILM_EXPOSED
	return &""


## The camera's use: a shot when it holds a film, else the load of the actor's fresh film.
func _use_camera(ctx: MatchContext, task_state: State, station: StationState) -> void:
	var loaded := _loaded_in(ctx.state, task_state)
	if loaded != null:
		_shoot(ctx, task_state, station, loaded)
		return
	var fresh := _fresh(task_state, _carried(ctx, film))
	if fresh == null:
		ctx.error("PhotoTask: player %d carries no fresh film to load" % ctx.actor)
		return
	Items.lay_on_station(ctx, fresh, station.position)
	task_state.loaded = fresh
	task_state.loaded_moves = fresh.moves
	ctx.emit(FilmLoadedEvent.new(station.id, fresh.id))


## The print (ADR §2.6, PD3, PD16 (a), PE8, PE11): each shot of the actor's exposed film, in shot
## order, a photo on the tray (the photo kind's cap first: GiveItem.make_room), ItemSpawned,
## PhotoPrinted, item_rested `spawn`; then the film vanishes and its entry goes. Should the cap
## find no loose photo (the check's floor keeps that from happening, bar a recycled item id past
## MAX_ITEM_ID, which a normal match never reaches) the film keeps the shots
## not printed, with the error logged.
func _print(ctx: MatchContext, task_state: State) -> void:
	var item := _exposed(ctx, task_state)
	if item == null:
		ctx.error("PhotoTask: player %d carries no film with a shot to print" % ctx.actor)
		return
	var entry := task_state.film_of(item)
	var printed := 0
	for shot: int in entry.shots:
		if not GiveItem.make_room(ctx, photo):
			ctx.error("PhotoTask: the photo kind is at its cap with none loose")
			break
		var made := Items.spawn(ctx, photo, task_state.tray)
		if made == null:
			break  # Every item id in use (Items.spawn logged it).
		var binding := Print.new()
		binding.item = made
		binding.shot = shot
		task_state.print_entries[made.id] = binding
		ctx.emit(ItemSpawnedEvent.new(made.id, photo.id, made.position))
		ctx.emit(PhotoPrintedEvent.new(made.id, shot))
		Items.raise_rested(ctx, made, Items.SPAWN)
		printed += 1
	if printed < entry.shots.size():
		entry.shots = entry.shots.slice(printed)
	else:
		Items.vanish(ctx, item)
	_prune(ctx.state, task_state)


## The hang (ADR §2.7, PD6, PE9, PE11): the actor's photo, the hand's, else the belt's. Its shot
## has a person: PhotoHung counted, locked on the board for good, then the next subtask done.
## Else PhotoHung not counted, and it lies on the board for PickUp to take down.
func _hang(ctx: MatchContext, task: MatchTask, station: StationState) -> void:
	var task_state := task.state as State
	var item := _carried_photo(ctx)
	if item == null:
		ctx.error("PhotoTask: player %d carries no photo to hang" % ctx.actor)
		return
	var entry := task_state.print_of(item)
	var shot: Shot = task_state.shots.get(entry.shot) if entry != null else null
	var counted := shot != null and shot.has_person
	ctx.emit(PhotoHungEvent.new(item.id, station.id, counted))
	if not counted:
		Items.lay_on_station(ctx, item, station.position)
		return
	Items.lock_at(ctx, item, station.position)
	var index := task_state.counted.size()
	task_state.counted.append(shot.id)
	Tasks.subtask_done(ctx, task, {"subtask": index, "item": item.id, "shot": shot.id})


## The camera's film (PE17): the item it was loaded with, while that very ItemState is still in the
## match, lying, with the move serial the load left; else null (the camera is empty).
func _loaded_in(state: MatchState, task_state: State) -> ItemState:
	var item := task_state.loaded
	if item == null:
		return null
	if state.items.get(item.id) != item:
		return null
	if item.where != ItemState.Where.GROUND or item.moves != task_state.loaded_moves:
		return null
	return item


## The items of `kind` the actor carries: the hand's, then the belt's.
func _carried(ctx: MatchContext, kind: ItemKind) -> Array[ItemState]:
	var found: Array[ItemState] = []
	for item: ItemState in [
		Items.held_by(ctx.state, ctx.actor), Items.belted_by(ctx.state, ctx.actor)
	]:
		if item != null and item.kind == kind:
			found.append(item)
	return found


## The first fresh film of `carried` (no shot yet), or null.
func _fresh(task_state: State, carried: Array[ItemState]) -> ItemState:
	for item: ItemState in carried:
		if task_state.film_of(item) == null:
			return item
	return null


## The actor's first film with a shot, the hand's, else the belt's (PE11), or null.
func _exposed(ctx: MatchContext, task_state: State) -> ItemState:
	for item: ItemState in _carried(ctx, film):
		if task_state.film_of(item) != null:
			return item
	return null


## The actor's photo, the hand's, else the belt's (PE11), or null.
func _carried_photo(ctx: MatchContext) -> ItemState:
	var carried := _carried(ctx, photo)
	return carried[0] if not carried.is_empty() else null


## Drops the entries of items no longer in the match (a vanish at a cap or a print, in the
## vanishing command; ARCHITECTURE §9.5): a film's, a photo's, the shots none of the rest shows,
## and the camera's film. The identity checks already keep a recycled id from reading them.
func _prune(state: MatchState, task_state: State) -> void:
	for item_id: int in task_state.films.keys():
		if state.items.get(item_id) != task_state.films[item_id].item:
			task_state.films.erase(item_id)
	for item_id: int in task_state.print_entries.keys():
		if state.items.get(item_id) != task_state.print_entries[item_id].item:
			task_state.print_entries.erase(item_id)
	var shown: Dictionary[int, bool] = {}
	for entry: Film in task_state.films.values():
		for shot: int in entry.shots:
			shown[shot] = true
	for entry: Print in task_state.print_entries.values():
		shown[entry.shot] = true
	for shot: int in task_state.shots.keys():
		if not shown.has(shot):
			task_state.shots.erase(shot)
	var loaded := task_state.loaded
	if loaded != null and state.items.get(loaded.id) != loaded:
		task_state.loaded = null


## The shot (ADR §2.3, §3.2, §3.3): who counts, the record, the film's next shot, then ShotTaken.
func _shoot(ctx: MatchContext, task_state: State, station: StationState, item: ItemState) -> void:
	var eye := Vector3.UP * _eye_height(ctx)
	var lens := station.position + eye
	var spot: StationState = ctx.state.stations.get(task_state.photo_spot)
	var aim := spot.position + eye if spot != null else lens + Vector3.FORWARD
	var frame := PhotoFrame.between(lens, aim, fov_deg, aspect, range_m)
	var shot := Shot.new()
	shot.id = task_state.free_shot_id()
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
			var head := player.position + _head_of(ctx, player)
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
						"crouched": player.crouched,
						"held_item": player.held_item,
						"belt_item": player.belt_item,
					}
				)
			)
	shot.has_person = not shot.subjects.is_empty()
	task_state.next_shot = (shot.id + 1) % SHOT_IDS
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


## How far above its feet a candidate's head is (the crouch ADR, KE2): the eye height, or the
## crouched eye height while it is crouched, so a player crouched behind a wall lower than the
## standing eye is not in the photo while the picture draws it crouched.
func _head_of(ctx: MatchContext, player: PlayerState) -> Vector3:
	if ctx.state.player_rules == null:
		return Vector3.ZERO
	return Vector3.UP * ctx.state.player_rules.eye_height_of(player.crouched)
