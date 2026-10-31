class_name ItemWorld
extends Node3D
## M4-8's part of the round under World (ARCHITECTURE §4.7): the items (ItemViews), the circles
## and the destination marker (CircleViews), the zones and their fill (ZoneViews, #650), the item
## keys and the crosshair's target (ItemInteractions; the throw key's arc, #645) and the world
## sounds (WorldSounds; the photo task's shutter, print and hang, #785) and the photo camera's
## flash (PhotoFlashes, #785) and the Generator's station scenes in the level (StationViews, #801)
## and its hum while it charges (StationHums, #801) and the photo camera's viewfinder
## (PhotoViewfinder, #786) and its scenes and items (PhotoViews, #787) and the shots' pictures
## (PhotoPictures, #787) and the hand-over key and its target (HandOverUse, #1411) and the world
## toggles' parts (ToggleViews, #1295),
## all from the own ClientModel, the interpolated poses and the
## client's own copy of the mode. It also gives the HUD what the model does not hold
## (`hud_local`): the predicted stamina and the item under the crosshair.
##
## A task type's view is its TaskClient's (TaskClients.make_views, #1260, §4.7.59): every row's,
## not only the mode's types', each given the model, the mode and, where it has them, the host
## tick and the level, and cleared at a reset; a mode's type with none is reported at setup
## (TaskClients.report_missing). The lookups by a hit or an item below
## (station_of_hit, drawn_point, aim_point) stay per type.

## ItemWorld's children by name in their tree order (the order they process in), the task types'
## views among them; a view not named here comes after them all.
const _ORDER: Array[StringName] = [
	&"ItemViews",
	&"CircleViews",
	&"ZoneViews",
	&"ItemInteractions",
	&"HandOverUse",
	&"WorldSounds",
	&"PhotoFlashes",
	&"StationViews",
	&"StationHums",
	&"ToggleViews",
	&"CookingViews",
	&"PhotoViewfinder",
	&"CarRepairViews",
	&"PhotoViews",
	&"PhotoPictures",
]

var items := ItemViews.new()
## The task types' views, keyed by their core script (TaskClients.make_views).
var task_views: Dictionary[Script, Node3D] = TaskClients.make_views()
var interactions := ItemInteractions.new()
## The hand-over key (#1411): after the item keys, whose targets win over it.
var hand_over := HandOverUse.new()
var sounds := WorldSounds.new()
var flashes := PhotoFlashes.new()
## The Generator's station scenes (its TaskClient's view): station_of_hit asks it first.
var stations := task_views.get(Generator) as StationViews
var hums := StationHums.new()
## The world toggles' parts in the level (#1295): no task type's view, so a fixed child.
var toggles := ToggleViews.new()
## Cooking's scenes (its TaskClient's view): station_of_hit, drawn_point and aim_point ask it.
var cooking := task_views.get(Cooking) as CookingViews
var viewfinder := PhotoViewfinder.new()
## The car repair's scenes (its TaskClient's view): station_of_hit and the near hit ask it.
var car_repair := task_views.get(CarRepair) as CarRepairViews
## The photo task's scenes and items (its TaskClient's view): drawn_point and aim_point ask it.
var photos := task_views.get(PhotoTask) as PhotoViews
var pictures := PhotoPictures.new()

var _model: ClientModel
var _mode: GameMode
var _player: PlayerController
## The estimated host tick (AvatarViews.host_tick), for the own fit's bar.
var _host_tick := Callable()


func _init() -> void:
	name = "Items"
	items.name = "ItemViews"
	interactions.name = "ItemInteractions"
	sounds.name = "WorldSounds"
	flashes.name = "PhotoFlashes"
	hums.name = "StationHums"
	toggles.name = "ToggleViews"
	pictures.name = "PhotoPictures"
	for each: Node3D in [
		items,
		interactions,
		hand_over,
		sounds,
		flashes,
		hums,
		toggles,
		viewfinder,
		pictures,
	]:
		add_child(each)
	for view: Node3D in task_views.values():
		add_child(view)
	var at := 0
	for child_name: StringName in _ORDER:
		var child := get_node_or_null(NodePath(child_name))
		if child != null:
			move_child(child, at)
			at += 1
	items.pictures = pictures
	# The throw key's predicted arc, one at a time, and the throw's sounds when the drawn item
	# launches and lands (37e).
	interactions.throw_sent.connect(items.predict_throw)
	interactions.predicting = items.is_predicting
	interactions.station_of_body = stations.station_of_body
	interactions.station_of_hit = station_of_hit
	interactions.station_near_hit = car_repair.station_of_point
	interactions.aim_of = aim_point
	interactions.viewfinder = viewfinder
	hand_over.interactions = interactions
	interactions.chair_spots = chair_spots
	items.station_point = drawn_point
	hums.ears = sounds.ears
	items.sound_due.connect(sounds.on_event)


## Follows `client`'s model with the client's own copy of `game_mode`; `views` draws the others.
func setup(client: ClientSession, game_mode: GameMode, views: AvatarViews) -> void:
	_model = client.model
	_mode = game_mode
	# A type with no TaskClient is drawn and offered nothing: say so once, never silently.
	TaskClients.report_missing(game_mode)
	items.model = _model
	items.mode = game_mode
	items.avatars = views
	for view: Node3D in task_views.values():
		# Object.set does nothing on a missing member: a view without these draws nothing, so say so.
		if not (&"model" in view and &"mode" in view):
			push_error("%s has no model and mode member (TaskClient.make_view)" % view.name)
			continue
		view.set(&"model", _model)
		view.set(&"mode", game_mode)
		if &"host_tick" in view:
			view.set(&"host_tick", views.host_tick)
	_host_tick = views.host_tick
	pictures.model = _model
	toggles.mode = game_mode
	toggles.model = _model
	pictures.mode = game_mode
	pictures.avatars = views
	pictures.flashes = flashes
	hums.model = _model
	hums.mode = game_mode
	hums.host_tick = views.host_tick
	interactions.setup(client, game_mode)
	hand_over.setup(client, game_mode)
	viewfinder.model = _model
	viewfinder.mode = game_mode
	sounds.model = _model
	sounds.avatars = views
	sounds.mode = game_mode
	# A photo camera's lens stands the eye height above its marker, as PhotoTask's.
	var lens_m := game_mode.player_rules.eye_height_m if game_mode.player_rules != null else 0.0
	sounds.lens_m = lens_m
	flashes.model = _model
	flashes.lens_m = lens_m
	client.event_received.connect(on_event)


## The local player, once welcomed.
func set_player(player: PlayerController) -> void:
	_player = player
	items.player = player
	interactions.player = player
	hand_over.player = player
	viewfinder.player = player
	sounds.player = player


## Forgets the session (it ended).
func reset() -> void:
	items.clear()
	for view: Node3D in task_views.values():
		if view.has_method(&"clear"):
			view.call(&"clear")
		view.set(&"model", null)
		if &"host_tick" in view:
			view.set(&"host_tick", Callable())
	items.model = null
	_host_tick = Callable()
	pictures.clear()
	pictures.model = null
	hums.clear()
	hums.model = null
	toggles.model = null
	sounds.model = null
	sounds.mode = null
	flashes.clear()
	flashes.model = null
	viewfinder.clear()
	interactions.setup(null, _mode)
	interactions.player = null
	hand_over.setup(null, _mode)
	hand_over.player = null
	items.player = null
	sounds.player = null
	_model = null
	_player = null


## What the HUD shows besides the model, at the estimated host tick `tick` (negative: the views'
## host tick): the raise bar (`raising`) shows the own raise's progress `raise` (-1: none), else
## the own fit at the car (#811), only while the own player is the car's fitter
## (CarRepairUse.fit_progress); never both at once, so the larger is the one running.
func hud_local(tick: float = -1.0, raise: float = -1.0) -> HudText.Local:
	var local := HudText.Local.new()
	if _player != null and _player.stamina != null:
		local.stamina = _player.stamina.get_stamina()
	local.aim = interactions.target()
	local.aim_station = interactions.station_target()
	local.viewing = viewfinder.active()
	local.raising = maxf(raise, fit_shown(tick))
	return local


## The own fit's progress at host tick `tick` (negative: the views' host tick), 0 to 1; -1 when
## the own player fits no car (#811).
func fit_shown(tick: float = -1.0) -> float:
	if _model == null:
		return -1.0
	var now := tick
	if now < 0.0:
		if not _host_tick.is_valid():
			return -1.0
		now = float(_host_tick.call() as int)
	var shown := -1.0
	for type: CarRepair in CarRepairUse.types_of(_mode):
		shown = maxf(shown, CarRepairUse.fit_progress(_model, type, now))
	return shown


## The session's events: the arcs of the items in flight, the photo flashes and the world
## sounds. A throw's launch and landing sounds wait for the drawn item to launch and land
## (ItemViews' sound_due), so they are not played here.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if _model == null:
		return
	items.on_event(event_name, fields)
	flashes.on_event(event_name, fields)
	pictures.on_event(event_name, fields)
	viewfinder.on_event(event_name, fields)
	if event_name == &"ItemThrown":
		return
	if event_name == &"ItemPlaced" and fields.get("cause", &"") == Items.THROWN:
		return
	sounds.on_event(event_name, fields)


## The level now (Game's), or null: StationViews finds the Generator's station scenes in it,
## CookingViews Cooking's, ToggleViews the world toggles' parts (#1295).
func set_level(level: Node) -> void:
	toggles.level = level
	for view: Node3D in task_views.values():
		if &"level" in view:
			view.set(&"level", level)


## The positions of the loaded scene's Marker3Ds in `group` (ItemInteractions.chair_spots, #1383):
## the chairs a Pose row's AtMarker names, read from the level every client loads (§9.6).
func chair_spots(group: StringName) -> PackedVector3Array:
	var spots := PackedVector3Array()
	if not is_inside_tree():
		return spots
	for node: Node in get_tree().get_nodes_in_group(group):
		var marker := node as Marker3D
		if marker != null and marker.is_inside_tree():
			spots.append(marker.global_position)
	return spots


## The station a ray hit names (ItemInteractions.station_of_hit): StationViews' by the body, then
## CookingViews' by the body and its shape (the herb beds share one body, #776), then
## CarRepairViews' (a scene's `Collision`, the car's `Lift`, #811); -1 for none.
func station_of_hit(body: Object, shape: int) -> int:
	var id := stations.station_of_body(body)
	if id < 0:
		id = cooking.station_of_hit(body, shape)
	return id if id >= 0 else car_repair.station_of_hit(body, shape)


## Where ItemViews draws resting item `id` (its station_point): on a cooking station
## (CookingViews.point_of), else in a photo camera, on the tray or on the board
## (PhotoViews.drawn_point, #787); null where it lies.
func drawn_point(id: int) -> Variant:
	var at: Variant = cooking.point_of(id)
	return at if at != null else photos.drawn_point(id)


## Where the crosshair aims at item `id` (ItemInteractions' aim_of): CookingViews', else
## PhotoViews' (never the film in a camera); null for none.
func aim_point(id: int) -> Variant:
	var at: Variant = cooking.point_of(id)
	return at if at != null else photos.aim_point(id)
