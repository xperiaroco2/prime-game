class_name ItemWorld
extends Node3D
## M4-8's part of the round under World (ARCHITECTURE §4.7): the items (ItemViews), the circles
## and the destination marker (CircleViews), the zones and their fill (ZoneViews, #650), the item
## keys and the crosshair's target (ItemInteractions; the throw key's arc, #645) and the world
## sounds (WorldSounds; the photo task's shutter, print and hang, #785) and the photo camera's
## flash (PhotoFlashes, #785) and the Generator's station scenes in the level (StationViews, #801)
## and its hum while it charges (StationHums, #801),
## all from the own ClientModel, the interpolated poses and the
## client's own copy of the mode. It also gives the HUD what the model does not hold
## (`hud_local`): the predicted stamina and the item under the crosshair.

var items := ItemViews.new()
var circles := CircleViews.new()
var zones := ZoneViews.new()
var interactions := ItemInteractions.new()
var sounds := WorldSounds.new()
var flashes := PhotoFlashes.new()
var stations := StationViews.new()
var hums := StationHums.new()
var cooking := CookingViews.new()

var _model: ClientModel
var _mode: GameMode
var _player: PlayerController


func _init() -> void:
	name = "Items"
	items.name = "ItemViews"
	circles.name = "CircleViews"
	zones.name = "ZoneViews"
	interactions.name = "ItemInteractions"
	sounds.name = "WorldSounds"
	flashes.name = "PhotoFlashes"
	stations.name = "StationViews"
	hums.name = "StationHums"
	cooking.name = "CookingViews"
	for each: Node3D in [
		items, circles, zones, interactions, sounds, flashes, stations, hums, cooking
	]:
		add_child(each)
	# The throw key's predicted arc, one at a time, and the throw's sounds when the drawn item
	# launches and lands (37e).
	interactions.throw_sent.connect(items.predict_throw)
	interactions.predicting = items.is_predicting
	interactions.station_of_body = stations.station_of_body
	interactions.station_of_hit = station_of_hit
	interactions.aim_of = cooking.point_of
	items.station_point = cooking.point_of
	hums.ears = sounds.ears
	items.sound_due.connect(sounds.on_event)


## Follows `client`'s model with the client's own copy of `game_mode`; `views` draws the others.
func setup(client: ClientSession, game_mode: GameMode, views: AvatarViews) -> void:
	_model = client.model
	_mode = game_mode
	items.model = _model
	items.mode = game_mode
	items.avatars = views
	circles.model = _model
	circles.mode = game_mode
	zones.model = _model
	zones.mode = game_mode
	zones.host_tick = views.host_tick
	stations.model = _model
	stations.mode = game_mode
	cooking.model = _model
	cooking.mode = game_mode
	cooking.host_tick = views.host_tick
	hums.model = _model
	hums.mode = game_mode
	hums.host_tick = views.host_tick
	interactions.setup(client, game_mode)
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
	sounds.player = player


## Forgets the session (it ended).
func reset() -> void:
	items.clear()
	circles.clear()
	zones.clear()
	items.model = null
	circles.model = null
	zones.model = null
	zones.host_tick = Callable()
	stations.model = null
	cooking.model = null
	cooking.host_tick = Callable()
	hums.clear()
	hums.model = null
	sounds.model = null
	sounds.mode = null
	flashes.clear()
	flashes.model = null
	interactions.setup(null, _mode)
	interactions.player = null
	items.player = null
	sounds.player = null
	_model = null
	_player = null


## What the HUD shows besides the model, at the estimated host tick.
func hud_local() -> HudText.Local:
	var local := HudText.Local.new()
	if _player != null and _player.stamina != null:
		local.stamina = _player.stamina.get_stamina()
	local.aim = interactions.target()
	local.aim_station = interactions.station_target()
	return local


## The session's events: the arcs of the items in flight, the photo flashes and the world
## sounds. A throw's launch and landing sounds wait for the drawn item to launch and land
## (ItemViews' sound_due), so they are not played here.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if _model == null:
		return
	items.on_event(event_name, fields)
	flashes.on_event(event_name, fields)
	if event_name == &"ItemThrown":
		return
	if event_name == &"ItemPlaced" and fields.get("cause", &"") == Items.THROWN:
		return
	sounds.on_event(event_name, fields)


## The level now (Game's), or null: StationViews finds the Generator's station scenes in it,
## CookingViews Cooking's.
func set_level(level: Node) -> void:
	stations.level = level
	cooking.level = level


## The station a ray hit names (ItemInteractions.station_of_hit): StationViews' by the body, then
## CookingViews' by the body and its shape (the herb beds share one body, #776); -1 for none.
func station_of_hit(body: Object, shape: int) -> int:
	var id := stations.station_of_body(body)
	return id if id >= 0 else cooking.station_of_hit(body, shape)
