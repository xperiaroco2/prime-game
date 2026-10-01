class_name LifeView
extends Node3D
## The own player's life in 3D (ARCHITECTURE §4.7, the revision in 3D; M4-9): the cameras, the
## countdowns, the life inputs and the lift music, from the own ClientModel, the interpolated poses
## (AvatarViews) and the client's own copy of the mode only (the M4 ADR's §3 items 1, 2, 3, 8).
##
## - Living: the player's own first-person camera. E held on a downed player in reach sends
##   Raise(target), its release StopRaise() (D6); the host checks everything again.
## - Downed: the DownedCamera over the own body with the own look, and SightHider hiding what the
##   body's eye could not see. G held for GIVE_UP_HOLD_S sends GiveUp() once (D6).
## - Dead: spectating. The first target is drawn by SpectateTargets with the client's own
##   generator; the left and right mouse buttons cycle; a target that goes down, dies or leaves is
##   replaced by a new first target. A living target is watched from its eyes (its interpolated
##   pose: the body's position, yaw and head pitch, already guarded against a degenerate facing),
##   a downed one through the DownedCamera above its body, and with no target the DownedCamera
##   stays above the own body. Nothing about the target is sent. The lift music plays.
## - Respawned: first person again where the Correction put the player; the music stops.
##
## Cameras are placed in the physics step at PHYSICS_PRIORITY: after the avatars (-80) and the
## local player (0) moved, before SightHider (10) casts from the pivot.

enum View { FIRST_PERSON, DOWNED, SPECTATE_EYES, SPECTATE_ABOVE }

const PHYSICS_PRIORITY := 5
## Seconds G must be held to give up (D6: a placeholder, "not a decision").
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
var _hider := SightHider.new()
var _music := LiftMusic.new()
var _view := View.FIRST_PERSON
var _target := 0
var _target_life := ClientModel.Life.ALIVE
## The body hidden while watched from its eyes; null when none.
var _watched: RemotePlayerBody
var _give_up_held_s := 0.0
var _gave_up := false
## E is held for a raise (sent, or waiting for its RaiseStarted).
var _raise_wanted := false
var _reach_m := 0.0
## The own look when the player died: the camera above the own body keeps it.
var _last_look := Vector2.ZERO


func _init() -> void:
	name = "Life"
	process_physics_priority = PHYSICS_PRIORITY
	rng.randomize()
	_targets = SpectateTargets.new(rng)
	_spectate_camera.name = "SpectateCamera"
	add_child(_downed_camera)
	add_child(_spectate_camera)
	add_child(_hider)
	add_child(_music)


## Follows `client`'s model and events, with `game_mode`'s numbers, until reset().
func setup(client: ClientSession, game_mode: GameMode, views: AvatarViews) -> void:
	session = client
	model = client.model
	mode = game_mode
	avatars = views
	countdowns = LifeCountdowns.new(mode.player_rules, LifeCountdowns.raise_seconds_of(mode))
	_reach_m = raise_reach_of(mode)
	client.event_received.connect(on_event)


## Forgets the session (it ended): first person, nothing hidden, no music.
func reset() -> void:
	_show(View.FIRST_PERSON)
	session = null
	model = null
	player = null
	countdowns = null
	_target = 0
	_raise_wanted = false


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


func hider() -> SightHider:
	return _hider


func music() -> LiftMusic:
	return _music


## What the life panel shows now, at the estimated host tick `tick`.
func hud(tick: float) -> LifeHud.Shown:
	if model == null or countdowns == null:
		return LifeHud.Shown.new()
	var local := LifeHud.Local.new()
	local.watching = _target if _is_dead() else 0
	local.give_up_held_s = _give_up_held_s
	local.give_up_hold_s = GIVE_UP_HOLD_S
	local.can_raise = _own_life() == ClientModel.Life.ALIVE and raise_target() != 0
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


## Sends GiveUp() while downed (G held long enough); once per knockdown.
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


## The downed player the crosshair is on, if the mode's raise reach holds from the feet as the
## host measures it (§4.7 Interactions); 0 when none. The first thing along the camera's ray: a
## wall in front hides a downed player behind it.
func raise_target() -> int:
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
	if not (reads_device_input and listening):
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
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				if Input.is_action_just_pressed(&"spectate_next"):
					cycle_target(1)
				elif Input.is_action_just_pressed(&"spectate_previous"):
					cycle_target(-1)


func _physics_process(_delta: float) -> void:
	if model == null or player == null:
		return
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
