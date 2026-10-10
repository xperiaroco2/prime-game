class_name LifeView
extends Node3D
## The own player's life in 3D (ARCHITECTURE §4.7, the revision in 3D; M4-9): the cameras, the
## countdowns, the life inputs and the lift music, from the own ClientModel, the interpolated poses
## (AvatarViews) and the client's own copy of the mode only (the M4 ADR's §3 items 1, 2, 3, 8).
##
## - Living: the player's own first-person camera. E held on a downed player in reach (a walking
##   margin short of the host's, raise_hint_reach_of()) sends Raise(target), its release
##   StopRaise() (D6); the host checks everything again.
## - Downed: the DownedCamera over the own body with the own look, and SightHider hiding what the
##   body's eye could not see. The give_up key (F, #211) held for GIVE_UP_HOLD_S sends GiveUp()
##   once (D6).
## - Dead: spectating. The first target is drawn by SpectateTargets with the client's own
##   generator; the left and right mouse buttons cycle; a target that goes down, dies or leaves is
##   replaced by a new first target. A living target is watched from its eyes (its interpolated
##   pose: the body's position, yaw and head pitch, already guarded against a degenerate facing),
##   as the target sees itself: its body and head hidden, its hand item in the spectate camera's
##   own FirstPersonHand and the views of its hand and belt items at its body hidden (#168); a
##   downed one through the DownedCamera above its body, and with no target the DownedCamera
##   stays above the own body. Nothing about the target is sent. The lift music plays.
## - Respawned: first person again where the Correction put the player; the music stops.
## - The ears (M5-5, E40): an Ears listener made current and placed after the cameras in every
##   physics step by the own life: the own eye, the own body's head while downed, the target's eye
##   or body's head while spectating (_place_ears()).
##
## Cameras are placed in the physics step at PHYSICS_PRIORITY: after the avatars (-80) and the
## local player (0) moved, before SightHider (10) casts from the pivot.

enum View { FIRST_PERSON, DOWNED, SPECTATE_EYES, SPECTATE_ABOVE }

const PHYSICS_PRIORITY := 5
## Seconds the give_up key must be held to give up (D6: a placeholder, "not a decision").
const GIVE_UP_HOLD_S := 1.0
## How far the crosshair's ray looks for a downed player, in metres: past any reach the host
## grants, since the reach is checked from the feet afterwards (raise_target()).
const RAISE_RAY_M := 4.0

var model: ClientModel
var session: ClientSession
## The client's own copy of the game mode.
var mode: GameMode
var player: PlayerController
var avatars: AvatarViews
## The item views (M4-8): a target watched from its eyes has its items in the first-person hand,
## not at its body. Null in tests without items.
var items: ItemViews
## Read the keyboard and mouse. Tests turn it off and call the actions themselves.
var reads_device_input := true
## Whether the life inputs apply now (the game turns it off under the Esc menu and outside the
## round).
var listening := true
## The spectate targets' generator (the purpose `spectate`): from the system's entropy unless a
## test seeds it.
var rng := RandomNumberGenerator.new()
var countdowns: LifeCountdowns

var _targets: SpectateTargets
var _downed_camera := DownedCamera.new()
var _spectate_camera := Camera3D.new()
## The watched target's hand item, where its own first-person view shows it.
var _spectate_hand := FirstPersonHand.new()
var _hider := SightHider.new()
var _music := LiftMusic.new()
var _ears := Ears.new()
var _view := View.FIRST_PERSON
var _target := 0
var _target_life := ClientModel.Life.ALIVE
## The body hidden while watched from its eyes; null when none.
var _watched: RemotePlayerBody
var _give_up_held_s := 0.0
var _gave_up := false
## E is held for a raise (sent, or waiting for its RaiseStarted).
var _raise_wanted := false
## The downed player under the crosshair in reach, cast in the physics step (raise_target()).
var _raise_peer := 0
## Whether the mouse was captured at the last _process: the click that captures it (the
## controller's _unhandled_input) still reads as just pressed, and must not cycle the target.
var _was_captured := false
var _reach_m := 0.0
## The own look when the player died: the camera above the own body keeps it.
var _last_look := Vector2.ZERO


func _init() -> void:
	name = "Life"
	process_physics_priority = PHYSICS_PRIORITY
	rng.randomize()
	_targets = SpectateTargets.new(rng)
	_spectate_camera.name = "SpectateCamera"
	_spectate_hand.name = "SpectateHand"
	_spectate_camera.add_child(_spectate_hand)
	add_child(_downed_camera)
	add_child(_spectate_camera)
	add_child(_hider)
	add_child(_music)
	_ears.name = "Ears"
	add_child(_ears)


## Follows `client`'s model and events, with `game_mode`'s numbers, until reset().
func setup(client: ClientSession, game_mode: GameMode, views: AvatarViews) -> void:
	session = client
	model = client.model
	mode = game_mode
	avatars = views
	countdowns = LifeCountdowns.new(mode.player_rules, LifeCountdowns.raise_seconds_of(mode))
	_reach_m = raise_hint_reach_of(mode)
	client.event_received.connect(on_event)


## Forgets the session (it ended): first person, nothing hidden, no music.
## The model is forgotten before the view is chosen, or a dead player's own DEAD would start the
## music again in the main menu, and nothing would stop it.
func reset() -> void:
	session = null
	model = null
	countdowns = null
	_show(View.FIRST_PERSON)
	player = null
	_target = 0
	_raise_wanted = false
	_raise_peer = 0
	_release_ears()


## The reach of the mode's raise (its TargetInReach), from the feet as the host measures it; 0
## when the mode has no raise.
static func raise_reach_of(game_mode: GameMode) -> float:
	for rule: Rule in game_mode.actions:
		if rule.trigger != Intents.RAISE:
			continue
		for condition: Condition in rule.conditions:
			var reach := condition as TargetInReach
			if reach != null:
				return reach.reach_m
	return 0.0


## The reach the raise hint and E offer a downed player within, in metres from the feet: the
## mode's raise reach less the pick-up hint's walking margin (TargetChoice.hint_reach()). The host
## measures from the feet of the last claim it accepted, which trail the player's own while
## walking in, so E at the first hint would otherwise be refused `out_of_reach` (#352, as #319).
## 0 when the mode has no raise.
static func raise_hint_reach_of(game_mode: GameMode) -> float:
	return TargetChoice.hint_reach(raise_reach_of(game_mode), game_mode)


## The camera in use, for tests and the listener.
func view() -> View:
	return _view


## The peer a dead player watches, 0 for none.
func target() -> int:
	return _target


func downed_camera() -> DownedCamera:
	return _downed_camera


func spectate_camera() -> Camera3D:
	return _spectate_camera


## The watched target's hand item under the spectate camera (#168).
func spectate_hand() -> FirstPersonHand:
	return _spectate_hand


func hider() -> SightHider:
	return _hider


func music() -> LiftMusic:
	return _music


## The listener every voice and world sound is heard from (E40).
func ears() -> Ears:
	return _ears


## The own raise's progress for the HUD's raise bar (#489) at the estimated host tick `tick`:
## 0 to 1 while the living own player raises someone, the downed player's raise bar's value;
## negative otherwise.
func raise_shown(tick: float) -> float:
	if model == null or countdowns == null or _own_life() != ClientModel.Life.ALIVE:
		return LifeCountdowns.NONE
	if countdowns.raising() == 0:
		return LifeCountdowns.NONE
	return countdowns.raise_progress(tick)


## The rescuer's cue in the HUD's Aim (#497, the engineer on PR #721): the label of the raise key
## bound now (KeyLabel's `interact`) while the living own player's crosshair is on a downed player E
## would raise (raise_target()); "" otherwise. It offers exactly what E does, so it follows the
## mode's raise: the base mode's raise has no team condition (anyone raises any downed player), so
## a dissident sees it over a downed engineer too. Whether a player is downed is public; nothing
## else of the downed player is in it.
func raise_cue() -> String:
	if model == null or _own_life() != ClientModel.Life.ALIVE or raise_target() == 0:
		return ""
	return KeyLabel.of_action(&"interact")


## What the downed, dead and respawn screen shows now (LifeScreen, #497), at the estimated host
## tick `tick`.
func hud(tick: float) -> LifeHud.Shown:
	if model == null or countdowns == null:
		return LifeHud.Shown.new()
	var local := LifeHud.Local.new()
	local.watching = _target if _is_dead() else 0
	local.give_up_held_s = _give_up_held_s
	local.give_up_hold_s = GIVE_UP_HOLD_S
	local.read_keys()
	return LifeHud.of(model, countdowns, tick, local)


## Every decoded event: the countdowns, at the estimated host tick of its arrival.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if model == null:
		return
	var own := model.own_peer
	countdowns.on_event(event_name, fields, own, float(avatars.host_tick()))
	match event_name:
		&"KnockedDown":
			if fields["peer"] as int == own:
				_give_up_held_s = 0.0
				_gave_up = false
		&"RaiseStarted":
			# E was let go before the raise started: stop it at once.
			if fields["raiser"] as int == own and not _raise_wanted:
				session.send_intent(Intents.STOP_RAISE)


## Sends GiveUp() while downed (the give_up key, F, held long enough); once per knockdown.
func give_up() -> void:
	if _own_life() != ClientModel.Life.DOWNED or _gave_up:
		return
	_gave_up = true
	session.send_intent(Intents.GIVE_UP)


## E pressed: Raise(target) for the downed player under the crosshair in reach, if any.
func press_raise() -> void:
	_raise_wanted = true
	var target_peer := raise_target()
	if target_peer != 0:
		session.send_intent(Intents.RAISE, {"target": target_peer})


## E released: StopRaise() if a raise by the own player runs.
func release_raise() -> void:
	_raise_wanted = false
	if countdowns != null and countdowns.raising() != 0:
		session.send_intent(Intents.STOP_RAISE)


## The downed player the crosshair is on, if it lies within the raise hint's reach of the feet
## (raise_hint_reach_of(): the host measures from the feet too, §4.7 Interactions, from its last
## accepted claim); 0 when none. Cast in the last physics step, the only time the physics space
## may be read (it is locked outside it with physics on its own thread).
func raise_target() -> int:
	return _raise_peer


## raise_target()'s cast: the first thing along the camera's ray, so a wall in front hides a
## downed player behind it.
func _cast_raise_target() -> int:
	if player == null or not player.is_inside_tree() or _reach_m <= 0.0:
		return 0
	var camera := player.get_camera()
	var from := camera.global_position
	var to := from + player.look_vector() * RAISE_RAY_M
	var mask := PhysicsLayers.WORLD | PhysicsLayers.DOWNED
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var body := hit.get("collider") as RemotePlayerBody
	if body == null or body.peer == 0:
		return 0
	if model.life_of(body.peer) != ClientModel.Life.DOWNED:
		return 0
	if player.global_position.distance_to(body.global_position) > _reach_m:
		return 0
	return body.peer


## Next (`step` 1) or previous (-1) spectate target, while dead.
func cycle_target(step: int) -> void:
	if not _is_dead():
		return
	_target = SpectateTargets.cycle(model, model.own_peer, _target, step)
	_target_life = model.life_of(_target)


func _process(delta: float) -> void:
	if model == null or player == null:
		return
	if not reads_device_input:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var was_captured := _was_captured
	_was_captured = captured
	if not listening:
		# Nothing reads the keys now (the Esc menu): a held raise or give-up key must not keep acting.
		_give_up_held_s = 0.0
		if _raise_wanted:
			release_raise()
		return
	match _own_life():
		ClientModel.Life.ALIVE:
			if Input.is_action_just_pressed(&"interact"):
				press_raise()
			elif _raise_wanted and not Input.is_action_pressed(&"interact"):
				release_raise()
		ClientModel.Life.DOWNED:
			if Input.is_action_pressed(&"give_up"):
				_give_up_held_s += delta
				if _give_up_held_s >= GIVE_UP_HOLD_S:
					give_up()
			else:
				_give_up_held_s = 0.0
		ClientModel.Life.DEAD:
			if captured and was_captured:
				if Input.is_action_just_pressed(&"spectate_next"):
					cycle_target(1)
				elif Input.is_action_just_pressed(&"spectate_previous"):
					cycle_target(-1)


func _physics_process(_delta: float) -> void:
	if model == null or player == null:
		_raise_peer = 0
		return
	var alive := _own_life() == ClientModel.Life.ALIVE
	_raise_peer = _cast_raise_target() if alive else 0
	match _own_life():
		ClientModel.Life.DOWNED:
			var angles := SnapshotBuffer.look_angles(player.look_vector(), Vector2.ZERO)
			_last_look = angles
			_show_downed(player.global_position, angles.x, angles.y)
		ClientModel.Life.DEAD, ClientModel.Life.LEFT:
			_spectate()
		_:
			_last_look = SnapshotBuffer.look_angles(player.look_vector(), Vector2.ZERO)
			_target = 0
			_show(View.FIRST_PERSON)
	_place_ears()


## Puts the ears where the own life hears from (Ears.point()), turned with the current camera,
## and makes them current. Runs after the cameras were placed in this step.
func _place_ears() -> void:
	if not player.is_inside_tree():
		return
	var own_feet := player.global_transform
	if _is_dead() and model.bodies.has(model.own_peer):
		own_feet = Transform3D(Basis.IDENTITY, model.bodies[model.own_peer])
	var target_body := avatars.body_of(_target) if _is_dead() and _target != 0 else null
	var watched := _target if target_body != null else 0
	var target_feet := target_body.global_transform if target_body != null else Transform3D()
	var eye := player.get_camera().global_position
	var at := Ears.point(
		_own_life(), own_feet, eye, watched, _target_life, target_feet, mode.player_rules
	)
	var camera := get_viewport().get_camera_3d()
	var turned := camera.global_basis if camera != null else Basis.IDENTITY
	_ears.global_transform = Transform3D(turned, at)
	if not _ears.is_current():
		_ears.make_current()


## The session ended: the ears are no longer the listener.
func _release_ears() -> void:
	if _ears.is_inside_tree() and _ears.is_current():
		_ears.clear_current()


## The dead's camera: keeps or replaces the target, then watches it.
func _spectate() -> void:
	var own := model.own_peer
	if _target != 0:
		var now := model.life_of(_target)
		if SpectateTargets.lost(_target_life, now):
			_target = 0
		else:
			_target_life = now
	if _target == 0:
		_target = _targets.first(model, own)
		_target_life = model.life_of(_target)
	var body := avatars.body_of(_target) if _target != 0 else null
	if body != null and _target_life == ClientModel.Life.ALIVE:
		var eye := body.global_position + Vector3.UP * mode.player_rules.eye_height_m
		var look := Vector3(body.head().rotation.x, body.rotation.y, 0.0)
		_spectate_camera.global_transform = Transform3D(Basis.from_euler(look), eye)
		_watch(body)
		_show(View.SPECTATE_EYES)
		_hold_as_seen(_target)
	elif body != null:
		_watch(null)
		_show_downed(body.global_position, body.rotation.y, body.head().rotation.x)
		_view = View.SPECTATE_ABOVE
	elif model.bodies.has(own):
		# No target (or its avatar not drawn yet): above the own body, with the last own look.
		_watch(null)
		_show_downed(model.bodies[own], _last_look.x, _last_look.y)
		_view = View.SPECTATE_ABOVE


## The DownedCamera over the feet at `feet` with that look; SightHider casts from its pivot.
func _show_downed(feet: Vector3, yaw: float, pitch: float) -> void:
	_downed_camera.place(feet + Vector3.UP * mode.player_rules.eye_height_m, yaw, pitch)
	_show(View.DOWNED)
	_hider.watch_from(_downed_camera.pivot())


## Makes `which` the current camera; SightHider runs only with the downed camera, the music only
## while dead.
func _show(which: View) -> void:
	_view = which
	if which == View.FIRST_PERSON or which == View.SPECTATE_EYES:
		_hider.stop()
	if which != View.SPECTATE_EYES:
		_watch(null)
		_spectate_hand.show_item(&"", Color.WHITE)
	var camera: Camera3D
	match which:
		View.FIRST_PERSON:
			var usable := is_instance_valid(player) and player.is_inside_tree()
			camera = player.get_camera() if usable else null
		View.SPECTATE_EYES:
			camera = _spectate_camera
		_:
			camera = _downed_camera.camera()
	if camera != null and not camera.current:
		camera.make_current()
	if _is_dead():
		_music.start()
	else:
		_music.stop()


## The items of `peer`, watched from its eyes, as it sees them itself: the hand item in the
## spectate camera's first-person hand, and neither item at its body (ItemViews shows and places
## those views earlier in each physics step, at its priority 1, so a target no longer watched has
## them back in the next step, and a new one never shows them for a step).
func _hold_as_seen(peer: int) -> void:
	var hand: ClientModel.Item = model.items.get(model.hand_item(peer))
	if hand == null:
		_spectate_hand.show_item(&"", Color.WHITE)
	else:
		var kind := mode.find_item_kind(hand.kind)
		_spectate_hand.show_item(hand.kind, hand.colour, kind != null and kind.is_two_handed())
	if items == null:
		return
	for item_id: int in [model.hand_item(peer), model.belt_item(peer)]:
		var view := items.view_of(item_id)
		if view != null:
			view.show_look(false)


## Hides `body`'s meshes while watched from its eyes, and shows the one watched before.
func _watch(body: RemotePlayerBody) -> void:
	if _watched == body:
		return
	if is_instance_valid(_watched):
		_watched.set_watched(false)
	_watched = body
	if body != null:
		body.set_watched(true)


func _own_life() -> ClientModel.Life:
	return model.life_of(model.own_peer)


func _is_dead() -> bool:
	if model == null:
		return false
	var life := _own_life()
	return life == ClientModel.Life.DEAD or life == ClientModel.Life.LEFT
