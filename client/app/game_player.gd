class_name GamePlayer
extends RefCounted
## Game's wiring of the local player, out of game.gd to keep it under lint's 1000 lines (#1249):
## its physics step and input flags for the screen shown (apply_flags), the mouse for a new screen
## (point_for), its body following its own life fold (sync_life), its placing (place) and what the
## HUD knows besides the model (hud_local). It keeps no state: the player, the views and the
## pointer are Game's.


## The local player's physics step and input flags for `now`: it steps only on a screen that is not
## frozen and while it has a body (the dead stand still until their Respawned, M4-9), and the keys
## count only there with no Esc menu. Game._process applies them every frame (the Esc menu), and
## Game._on_event as soon as the session folds an event in its physics step (#241): under load
## several physics steps run before the next _process, and the player must neither step nor claim
## after the phase turns frozen (Loading, Pregame, End), nor wait for _process to walk again.
static func apply_flags(game: Game, now: GameFlow.Screen) -> void:
	var player := game.player()
	if player == null:
		return
	var life := game.life()
	var items := game.items()
	player.set_physics_process(not GameFlow.frozen(now) and not _dead(player))
	var listening := not GameFlow.frozen(now) and not game.ui.blocks_keys()
	player.reads_device_input = game.device_input and listening
	# The map frees the mouse for its «?» while the player still walks, jumps, picks up and talks
	# (the designer's answer on #253): the controller only stops looking and recapturing. So
	# does the tutorial's invite (#492), under which no key counts.
	player.mouse_free = game.ui.frees_mouse()
	life.reads_device_input = game.device_input
	life.listening = listening and now == GameFlow.Screen.ROUND
	items.interactions.reads_device_input = game.device_input
	# The hand keys count in the lobby too (#1408: the hall's tap and mugs; the Lobby accepts them,
	# #1388); the raise is the round's alone.
	var hands := now == GameFlow.Screen.ROUND or now == GameFlow.Screen.LOBBY
	items.interactions.listening = listening and hands
	# So is the hand-over (#1411: the bar's mug to a friend); the client's own copy of the phase
	# decides whether it offers one (HandOverUse.can_hand).
	items.hand_over.reads_device_input = game.device_input
	items.hand_over.listening = listening and hands
	if not listening:
		# Nothing reads the keys now: W held when Esc opened must not keep walking.
		player.release_keys()


## The mouse for the screen just shown (GameFlow.pointer_on): a mouse captured in the round would
## stay captured on the end screen's button; the lobby and the round capture it (#517), and so do
## Loading and Pregame when the change closed the Esc menu that freed it (`menu_closed`, #726);
## never from under the Esc menu, and only while the window has the focus (MousePointer.focused):
## a window in the background a click captures later.
static func point_for(game: Game, now: GameFlow.Screen, menu_closed: bool) -> void:
	var wanted := GameFlow.pointer_on(now)
	if wanted == GameFlow.Pointer.FREE:
		game.pointer.capture(false)
	elif (wanted == GameFlow.Pointer.CAPTURE or menu_closed) and not game.ui.esc_open():
		if game.pointer.focused():
			game.pointer.capture(true)


## The own player's body follows its own life fold (M4-9): it holds still and looks while downed (a
## KnockedDown naming it, KE4), has no body while dead (Died; apply_flags stops the physics step,
## so it neither walks nor claims until its Respawned), and walks again once living (Revived,
## Respawned, a new match, the lobby). Limp (its own avatar's flag, §7.1.21) it holds still as if
## downed until it gets up. Only a change switches the body, since switching stops it.
static func sync_life(game: Game) -> void:
	var player := game.player()
	if player == null:
		return
	var model := game.client().model
	var own_life := model.body_life_of(model.own_peer)
	if player.life != own_life:
		player.life = own_life


## Puts `player` at `position` through teleport(), so the step-up check measures from there and
## not from where _ready found the body.
static func place(player: PlayerController, position: Vector3, velocity: Vector3) -> void:
	player.teleport(Transform3D(player.global_transform.basis, position))
	player.velocity = velocity


## What the HUD knows besides the model: the predicted stamina and the item under the crosshair
## (ItemWorld), the own raise's progress at the estimated host tick `tick`, the raise cue's key and
## whether anyone may hear the own player (#489, #497).
static func hud_local(game: Game, tick: float) -> HudText.Local:
	var life := game.life()
	var player := game.player()
	var local := game.items().hud_local(tick, life.raise_shown(tick))
	local.raise_key = life.raise_cue()
	local.hand_over_key = game.items().hand_over.cue()
	local.hand_over_cue_key = game.items().hand_over.cue_key()
	local.sit_key = game.items().interactions.sit_cue()
	local.mic = game.sender().live()
	if player != null and not _dead(player):
		local.placed = true
		local.position = life.own_point()
		var look := player.look_vector()
		local.heading = atan2(look.x, -look.z)
	return local


static func _dead(player: PlayerController) -> bool:
	return player.life == ClientModel.Life.DEAD or player.life == ClientModel.Life.LEFT
