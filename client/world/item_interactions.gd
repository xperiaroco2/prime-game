class_name ItemInteractions
extends Node3D
## The own player's item keys (ARCHITECTURE §4.7, Interactions; the M4 ADR's §2, D6; M4-8), while
## the own player is living in the round:
## - E (`interact`) sends PickUp(item) for the item TargetChoice offers under the crosshair (on a
##   box, #776: a tap sends Interact(station -1, item), a hold of HOLD_SECONDS PickUp), or
##   Interact(station, item -1) for the station it offers there (#801, §4.7.54); on a photo camera
##   holding a film (#786, §4.7.56) a tap opens the viewfinder (PhotoViewfinder, nothing sent) and
##   a hold of HOLD_SECONDS sends PickUp of its film, the box's gesture;
## - in the viewfinder: E or the keys no longer listening close it, the left mouse button sends
##   the shot, Interact(camera, item -1), while its film has frames left; no other item key acts;
## - Q (`put_down`) sends PutDown(facing) while the own hand holds an item;
## - the left mouse button (`use`) sends Use(facing) while the own hand holds an item; the click
##   that captures the mouse is not a use;
## - X (`swap`) sends Swap() while the own hand or belt holds an item;
## - G (`throw`, the throwing ADR's TD7 (a); the key provisional) sends Throw(facing) while the own
##   hand holds an item that the client's own copy of the mode has a Throw rule for, in a phase
##   that takes Throw from the living, one at a time (`predicting`): `throw_sent` then starts its
##   predicted arc (ItemViews, §4.7.52). With no such rule nothing is sent.
## The facing is the camera's look vector (E22). The host decides everything and the client
## predicts nothing of an action's outcome but the throw's drawn arc, which changes no slot: the
## slots change only with the host's events. The keys
## a raise uses (E on a downed player, LifeView) are M4-9's: a downed player in front of an item
## stops the item's ray, so E on a downed player picks up nothing behind it.
##
## The target is cast in the physics step, the only time the physics space may be read (it is
## locked outside it with physics on its own thread), after the local player moved (0).

## The throw key sent Throw as `seq` from the camera at `eye` along `look` (ItemViews predicts).
signal throw_sent(seq: int, eye: Vector3, look: Vector3)

const PHYSICS_PRIORITY := 6
## How long E is held on a box to pick it up rather than take from it (the cooking ADR's CD4 (a);
## a placeholder, not a decision): a release before it is the tap.
const HOLD_SECONDS := 0.4
## The keys 1, 2 and 3 (GDD §6 "Drawing from the belt"): the action of each place, 0..2.
const PLACE_ACTIONS: Array[StringName] = [&"place_1", &"place_2", &"place_3"]

var model: ClientModel
var session: ClientSession
## The client's own copy of the mode: PickUp's reach and the kinds' display names.
var mode: GameMode
var player: PlayerController
## Read the keyboard and mouse. Tests turn it off and call the actions themselves.
var reads_device_input := true
## Whether the item keys apply now (the game turns it off under the Esc menu and outside the
## round).
var listening := true
## Whether a throw still waits for the host's answer (ItemWorld gives ItemViews.is_predicting).
var predicting := Callable()
## Whether the mouse is captured, which `use` and the shot need (the click that captures it acts
## on nothing): Input's mouse mode unless replaced. Game gives its MousePointer's, so a pointer
## that never touches Input (a playcheck window's, #1114) still lets the left button act; tests
## replace it too, as headless Godot keeps no mouse mode (CAPTURED reads back as VISIBLE).
var mouse_captured := func() -> bool: return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## Which station a collider of the level belongs to (StationViews.station_of_body, given by
## ItemWorld), -1 for none; unset: only the use spot names a station.
var station_of_body := Callable()
## The same from the hit's collider and its shape index (body, shape) -> station id, -1 for none
## (ItemWorld's, which also names a herb bed by its shape of the beds' shared body, #776); when
## set it is asked instead of `station_of_body`.
var station_of_hit := Callable()
## Asked when the hit's collider named no station: (body, hit point) -> station id, -1 for none
## (ItemWorld gives CarRepairViews.station_of_point: the shelf's one body names the bin nearest
## the point, #811); unset: never asked.
var station_near_hit := Callable()
## Where the crosshair aims at an item lying on a cooking station (CookingViews.aim_of, #776):
## id -> Vector3 or null (TargetChoice.aim_at); unset: such an item is never named.
var aim_of := Callable()
## The photo camera's viewfinder (ItemWorld's, #786); null: a tap on a loaded camera opens nothing.
var viewfinder: PhotoViewfinder

var _target := -1
var _station := -1
## The reach the hint offers within (TargetChoice.hint_reach_of): the host's, less a margin.
var _reach_m := 0.0
## Whether the mouse was captured at the last _process: the click that captures it (the
## controller's _unhandled_input) still reads as just pressed, and must not use the item.
var _was_captured := false
## The box E went down on (#776, CD4 (a)), -1 for none, and how long E has been held on it.
var _held := -1
var _held_for := 0.0
## The photo camera holding a film E went down on (#786), -1 for none; timed by `_held_for` too.
var _held_camera := -1
## The station whose hold E started (#811: Interact on a kind whose rule ends in a HoldStation,
## StationUse.holds), -1 for none: E released sends StopRaise once, wherever the crosshair is then
## (the host keeps the hold while the feet stay at the station, the car repair ADR's §2.2).
var _hold_station := -1
## The own photo held up close (#787), -1 for none.
var _close_item := -1


func _init() -> void:
	process_physics_priority = PHYSICS_PRIORITY


func setup(client: ClientSession, game_mode: GameMode) -> void:
	session = client
	model = client.model if client != null else null
	mode = game_mode
	_reach_m = TargetChoice.hint_reach_of(mode) if mode != null else 0.0


## The item the crosshair is on, within the hint's reach from the feet (the host's, less
## TargetChoice's margin), or -1 (cast in the last physics step).
func target() -> int:
	return _target


## The item pick-up the crosshair would do, with the interact key bound now (E by default,
## KeyLabel, #211); empty for nothing, a station target included (#801: the HUD names a station
## through `station_target()`). The HUD reads `target()` since #489 (it shows no keys); this is
## kept for its tests and a later tutorial (#492).
func hint() -> String:
	var item: ClientModel.Item = model.items.get(_target) if model != null else null
	if item == null:
		return ""
	var kind := mode.find_item_kind(item.kind)
	var what := kind.display_name if kind != null else String(item.kind)
	return "%s: pick up %s" % [KeyLabel.of_action(&"interact"), what]


## The station the crosshair is on that E would use (TargetChoice.choose_target, #801), or -1
## (cast in the last physics step). Never set while `target()` is.
func station_target() -> int:
	return _station


## E: Interact(station, item -1) for the station target (#801; the host decides what it does:
## a switch toggles, the generator's button starts the charge, an empty photo camera takes the
## carried fresh film, #786), else PickUp for the item target; the sequence number sent, or -1
## when nothing was sent. On a station whose Interact starts a hold (the lift panel, the car's
## fit; StationUse.holds) the hold is remembered for release_hold().
func interact() -> int:
	if _station >= 0 and _acts():
		# A loaded photo camera shoots only from the viewfinder (#786; its tap opens that).
		if PhotoUse.is_loaded_camera(model, mode, _station):
			return -1
		var station: ClientModel.Station = model.stations.get(_station)
		if station != null and StationUse.holds(mode, station.kind):
			_hold_station = _station
		return session.send_intent(Intents.INTERACT, {"station": _station, "item": -1})
	return pick_up()


## E released, or the keys stopped listening, after interact() started a hold (#811, RE5):
## StopRaise once, whatever the crosshair aims at now; the sequence number sent, or -1 for no hold.
func release_hold() -> int:
	var station := _hold_station
	_hold_station = -1
	if station < 0 or session == null:
		return -1
	return session.send_intent(Intents.STOP_RAISE)


## The station whose hold E started (#811), -1 for none.
func hold_station() -> int:
	return _hold_station


## E went down (#776): in the viewfinder it closes it (#786); on a station target or an item that
## is no box, interact() at once; on a box (CookingUse.is_box) or a photo camera holding a film
## (PhotoUse.is_loaded_camera, #786) it starts the hold there and sends nothing yet: the release
## before HOLD_SECONDS taps it (release_interact()), the hold reaching it picks the box or the
## camera's film up (hold_step()). The sequence number sent, or -1 when nothing was sent.
func press_interact() -> int:
	_held = -1
	_held_camera = -1
	if viewing():
		viewfinder.leave()
		return -1
	var item: ClientModel.Item = model.items.get(_target) if model != null else null
	if _station < 0 and item != null and _acts() and CookingUse.is_box(mode, item.kind):
		_held = _target
		_held_for = 0.0
		return -1
	if _station >= 0 and _acts() and PhotoUse.is_loaded_camera(model, mode, _station):
		_held_camera = _station
		_held_for = 0.0
		return -1
	return interact()


## E released (#776): a hold on a box shorter than HOLD_SECONDS taps it, Interact(station -1,
## item), and one on a loaded photo camera opens the viewfinder there (#786, nothing sent), if the
## keys still listen and the crosshair is still on that box or camera (it can leave in the frame
## E is released, before hold_step() runs); the sequence number sent, or -1 when nothing was sent.
func release_interact() -> int:
	var box := _held
	var camera := _held_camera
	_held = -1
	_held_camera = -1
	if not listening or not _acts():
		return -1
	if camera >= 0:
		if _station == camera and viewfinder != null:
			viewfinder.enter(camera)
		return -1
	if box < 0 or _target != box or not model.items.has(box):
		return -1
	return session.send_intent(Intents.INTERACT, {"station": -1, "item": box})


## E still held for `delta` seconds (#776): once the hold on a box reaches HOLD_SECONDS, PickUp of
## that box, once, and on a loaded photo camera PickUp of its film (#786, PD17 (a)); the release
## then sends nothing. The hold is dropped, sending nothing, when the keys stop listening (the Esc
## menu, the tutorial's invite), the own player cannot act, the crosshair leaves the box or camera,
## or the camera's film leaves it. The sequence number sent, or -1.
func hold_step(delta: float) -> int:
	if _held < 0 and _held_camera < 0:
		return -1
	var on_box := _held >= 0 and _target == _held
	var on_camera := (
		_held_camera >= 0
		and _station == _held_camera
		and PhotoUse.is_loaded_camera(model, mode, _held_camera)
	)
	if not listening or not _acts() or not (on_box or on_camera):
		_held = -1
		_held_camera = -1
		return -1
	_held_for += delta
	if _held_for < HOLD_SECONDS:
		return -1
	var item := _held if on_box else model.stations[_held_camera].film
	_held = -1
	_held_camera = -1
	# The film's PickUp is the mode's (InReach from the feet), whatever the camera's cylinder.
	var film: ClientModel.Item = model.items.get(item)
	if (
		not on_box
		and (film == null or player.global_position.distance_to(film.position) > _reach_m)
	):
		return -1
	return session.send_intent(Intents.PICK_UP, {"item": item})


## The box E is held on now (#776), -1 for none.
func held_box() -> int:
	return _held


## The loaded photo camera E is held on now (#786), -1 for none.
func held_camera() -> int:
	return _held_camera


## Whether the photo camera's viewfinder is up (#786).
func viewing() -> bool:
	return viewfinder != null and viewfinder.active()


## Whether the own photo is held up close (#787).
func close_up() -> bool:
	return _close_item >= 0


## The left mouse button in the viewfinder (#786): the shot, Interact(camera, item -1), while the
## own player can act and the camera's film has frames left (the host refuses the rest anyway);
## the sequence number sent, or -1 when nothing was sent.
func shoot() -> int:
	if not viewing() or not _acts():
		return -1
	var camera := viewfinder.station()
	if PhotoUse.frames_left(model, mode, camera) <= 0:
		return -1
	return session.send_intent(Intents.INTERACT, {"station": camera, "item": -1})


## E: PickUp(item) for the target; the sequence number sent, or -1 when nothing was sent.
func pick_up() -> int:
	if _target < 0 or not _acts():
		return -1
	return session.send_intent(Intents.PICK_UP, {"item": _target})


## Q: PutDown(facing) while the own hand holds an item.
func put_down() -> int:
	if not _acts() or model.hand_item(model.own_peer) < 0:
		return -1
	return session.send_intent(Intents.PUT_DOWN, {"facing": player.look_vector()})


## The left mouse button: Use(facing) while the own hand holds an item.
## The primary button with a photo in the hand (#787) holds it up close or back and sends nothing
## (a photo has no Use rule).
func use() -> int:
	if not _acts() or model.hand_item(model.own_peer) < 0:
		return -1
	var hand_id := model.hand_item(model.own_peer)
	if PhotoUse.is_photo(mode, model.items[hand_id].kind):
		_set_close(hand_id if _close_item != hand_id else -1)
		return -1
	return session.send_intent(Intents.USE, {"facing": player.look_vector()})


## X: Swap() while the own player carries an item: back to the place it held last (GDD §6).
func swap() -> int:
	var own := model.own_peer if model != null else 0
	if not _acts() or (model.hand_item(own) < 0 and model.belt_item(own) < 0):
		return -1
	return session.send_intent(Intents.SWAP)


## 1, 2, 3: Draw(place), the place 0..2 into the hand (GDD §6 "Drawing from the belt"); not the
## selected one, which the host would refuse (`same_place`).
func draw(place: int) -> int:
	if not _acts() or place < 0 or place >= ClientModel.PLACES:
		return -1
	if place == model.selected_place(model.own_peer):
		return -1
	return session.send_intent(Intents.DRAW, {"place": place})


## The mouse wheel: Draw of the next place (`step` 1) or the one before (-1), round the three.
func step_place(step: int) -> int:
	if not _acts():
		return -1
	return draw(posmod(model.selected_place(model.own_peer) + step, ClientModel.PLACES))


## G: Throw(facing) of the own hand item, when the client's own copy of the mode has a Throw rule
## for it (found as core finds it) and the phase takes Throw from the living, and no throw waits
## for its answer; the sequence number sent, or -1 when nothing was sent.
func throw() -> int:
	if not _acts() or mode == null:
		return -1
	var item: ClientModel.Item = model.items.get(model.hand_item(model.own_peer))
	if item == null or ItemArc.rule_of(mode, item.kind, model.role) == null:
		return -1
	var phase := mode.find_phase(model.phase)
	var living := AcceptSpec.From.LIVING | AcceptSpec.From.PLAYER
	if phase == null or (phase.senders_of(Intents.THROW) & living) == 0:
		return -1
	if predicting.is_valid() and predicting.call() as bool:
		return -1
	var eye := player.get_camera().global_position
	var look := player.look_vector()
	var seq := session.send_intent(Intents.THROW, {"facing": look})
	if seq >= 0:
		throw_sent.emit(seq, eye, look)
	return seq


## The target's cast: the camera's ray against the level (as the host's line of sight) and the
## downed players' capsules (a downed player in front is M4-9's raise target, and E there picks up
## nothing behind it), then the item or station along it and the reach from the feet
## (TargetChoice.choose_target; the level's hit names a station when it is a station scene's
## collision, `station_of_body`); then the host's InSight: the line from the camera to the item's
## middle must be clear of the level, so an item just behind a thin wall or around a door jamb,
## whose pick sphere the ray enters before the wall, is never named (the M4 ADR's §3 item 5); for
## a station the host's StationInSight, the line to its lifted floor point (#801).
func cast_target() -> TargetChoice.Target:
	var none := TargetChoice.Target.new()
	if not _acts() or not player.is_inside_tree():
		return none
	var eye := player.get_camera().global_position
	var look := player.look_vector()
	var to := eye + look * TargetChoice.RAY_M
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		eye,
		to,
		PhysicsLayers.WORLD | PhysicsLayers.DOWNED | PhysicsLayers.MOVERS,
		[player.get_rid()]
	)
	var hit := space.intersect_ray(query)
	var blocked_at := TargetChoice.RAY_M
	var device := -1
	if not hit.is_empty():
		blocked_at = eye.distance_to(hit["position"] as Vector3)
		if station_of_hit.is_valid():
			device = station_of_hit.call(hit["collider"] as Object, hit["shape"] as int) as int
		elif station_of_body.is_valid():
			device = station_of_body.call(hit["collider"] as Object) as int
		if device < 0 and station_near_hit.is_valid():
			device = (
				station_near_hit.call(hit["collider"] as Object, hit["position"] as Vector3) as int
			)
	var picked := TargetChoice.choose_target(
		model, mode, eye, look, blocked_at, player.global_position, _reach_m, device, aim_of
	)
	var seen := Vector3.ZERO
	if picked.is_item():
		var item := model.items[picked.id]
		seen = ItemView.centre_of(item.kind, item.position)
		# On a plate (#776): the host's InSight looks at where it lies, the place's use spot.
		if item.on_station >= 0:
			seen = Items.lifted(item.position)
	elif picked.is_station():
		seen = Items.lifted(model.stations[picked.id].position)
	else:
		return none
	var sight := PhysicsRayQueryParameters3D.create(
		eye, seen, PhysicsLayers.WORLD, [player.get_rid()]
	)
	return picked if space.intersect_ray(sight).is_empty() else none


func _physics_process(_delta: float) -> void:
	# The close-up ends when the hand item changes, the own player is knocked down or dies, the
	# viewfinder opens or the keys stop listening (#787).
	if _close_item >= 0 and (not listening or viewing() or not _acts()):
		_set_close(-1)
	elif _close_item >= 0 and model.hand_item(model.own_peer) != _close_item:
		_set_close(-1)
	# The keys stopped listening (the Esc menu, the round's end): the viewfinder closes (#786).
	if viewing() and not listening:
		viewfinder.leave()
	# In the viewfinder nothing is aimed at: the HUD names nothing, and E closes it.
	var aimed := TargetChoice.Target.new()
	if listening and not viewing():
		aimed = cast_target()
	_target = aimed.id if aimed.is_item() else -1
	_station = aimed.id if aimed.is_station() else -1


func _process(delta: float) -> void:
	if model == null or player == null or not reads_device_input:
		return
	var captured := mouse_captured.call() as bool
	var was_captured := _was_captured
	_was_captured = captured
	# Knocked down, dead or gone: the host already stopped the hold (the car repair ADR's §2.3).
	if model.life_of(model.own_peer) != ClientModel.Life.ALIVE:
		_hold_station = -1
	if not listening:
		_held = -1
		_held_camera = -1
		release_hold()
		return
	if _hold_station >= 0 and not Input.is_action_pressed(&"interact"):
		release_hold()
	if Input.is_action_just_pressed(&"interact"):
		press_interact()
	elif (_held >= 0 or _held_camera >= 0) and not Input.is_action_pressed(&"interact"):
		release_interact()
	else:
		hold_step(delta)
	if viewing():
		if captured and was_captured and Input.is_action_just_pressed(&"use"):
			shoot()
		return
	if Input.is_action_just_pressed(&"put_down"):
		put_down()
	for place: int in ClientModel.PLACES:
		if Input.is_action_just_pressed(PLACE_ACTIONS[place]):
			draw(place)
	if Input.is_action_just_pressed(&"swap"):
		swap()
	if Input.is_action_just_pressed(&"throw"):
		throw()
	if captured and was_captured and Input.is_action_just_pressed(&"use"):
		use()


## The mouse wheel draws the next place down, the one before up (GDD §6). It is no InputMap action:
## the wheel is no binding (Controls.NOT_BINDABLE_BUTTONS).
func _unhandled_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed or not reads_device_input or not listening:
		return
	if viewing() or not mouse_captured.call():
		return
	if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step_place(1)
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		step_place(-1)


## Whether the item keys act: a session, a local player, the own player living.
func _acts() -> bool:
	return (
		session != null
		and model != null
		and player != null
		and model.life_of(model.own_peer) == ClientModel.Life.ALIVE
	)


func _set_close(id: int) -> void:
	_close_item = id
	if player != null and player.is_inside_tree():
		player.hand_view().set_close(id >= 0)
