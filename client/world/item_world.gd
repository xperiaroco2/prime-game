class_name ItemWorld
extends Node3D
## M4-8's part of the round under World (ARCHITECTURE §4.7): the items (ItemViews), the circles
## and the destination marker (CircleViews), the item keys and the crosshair's target
## (ItemInteractions) and the world sounds (WorldSounds), all from the own ClientModel,
## the interpolated poses and the client's own copy of the mode. It also gives the HUD what the
## model does not hold (`hud_local`): the predicted stamina and the item under the crosshair.

var items := ItemViews.new()
var circles := CircleViews.new()
var interactions := ItemInteractions.new()
var sounds := WorldSounds.new()

var _model: ClientModel
var _mode: GameMode
var _player: PlayerController


func _init() -> void:
	name = "Items"
	items.name = "ItemViews"
	circles.name = "CircleViews"
	interactions.name = "ItemInteractions"
	sounds.name = "WorldSounds"
	for each: Node3D in [items, circles, interactions, sounds]:
		add_child(each)


## Follows `client`'s model with the client's own copy of `game_mode`; `views` draws the others.
func setup(client: ClientSession, game_mode: GameMode, views: AvatarViews) -> void:
	_model = client.model
	_mode = game_mode
	items.model = _model
	items.mode = game_mode
	items.avatars = views
	circles.model = _model
	circles.mode = game_mode
	interactions.setup(client, game_mode)
	sounds.model = _model
	sounds.avatars = views
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
	items.model = null
	circles.model = null
	sounds.model = null
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
	return local


## The session's events: the world sounds.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if _model != null:
		sounds.on_event(event_name, fields)
