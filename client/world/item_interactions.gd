class_name ItemInteractions
extends Node3D
## The own player's item keys (ARCHITECTURE §4.7, Interactions; the M4 ADR's §2, D6; M4-8), while
## the own player is living in the round:
## - E (`interact`) sends PickUp(item) for the item TargetChoice offers under the crosshair;
## - Q (`put_down`) sends PutDown(facing) while the own hand holds an item;
## - the left mouse button (`use`) sends Use(facing) while the own hand holds an item; the click
##   that captures the mouse is not a use;
## - X (`swap`) sends Swap() while the own hand or belt holds an item;
## - G (`throw`, the throwing ADR's TD7 (a); the key provisional) sends Throw(facing) while the own
##   hand holds an item that the client's own copy of the mode has a Throw rule for, in a phase
##   that takes Throw from the living, one at a time (`predicting`): `throw_sent` then starts its
##   predicted arc (ItemViews, §4.7.25). With no such rule nothing is sent.
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

var _target := -1
## The reach the hint offers within (TargetChoice.hint_reach_of): the host's, less a margin.
var _reach_m := 0.0
## Whether the mouse was captured at the last _process: the click that captures it (the
## controller's _unhandled_input) still reads as just pressed, and must not use the item.
var _was_captured := false


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


## What the crosshair would do, for the HUD; empty for nothing.
func hint() -> String:
	var item: ClientModel.Item = model.items.get(_target) if model != null else null
	if item == null:
		return ""
	var kind := mode.find_item_kind(item.kind)
	return "E: pick up %s" % (kind.display_name if kind != null else String(item.kind))


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
func use() -> int:
	if not _acts() or model.hand_item(model.own_peer) < 0:
		return -1
	return session.send_intent(Intents.USE, {"facing": player.look_vector()})


## X: Swap() while the own hand or belt holds an item.
func swap() -> int:
	var own := model.own_peer if model != null else 0
	if not _acts() or (model.hand_item(own) < 0 and model.belt_item(own) < 0):
		return -1
	return session.send_intent(Intents.SWAP)


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
## nothing behind it), then the item along it and the reach from the feet (TargetChoice); then
## the host's InSight: the line from the camera to the item's middle must be clear of the level,
## so an item just behind a thin wall or around a door jamb, whose pick sphere the ray enters
## before the wall, is never named (the M4 ADR's §3 item 5).
func cast_target() -> int:
	if not _acts() or not player.is_inside_tree() or _reach_m <= 0.0:
		return -1
	var eye := player.get_camera().global_position
	var look := player.look_vector()
	var to := eye + look * TargetChoice.RAY_M
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		eye, to, PhysicsLayers.WORLD | PhysicsLayers.DOWNED, [player.get_rid()]
	)
	var hit := space.intersect_ray(query)
	var blocked_at := TargetChoice.RAY_M
	if not hit.is_empty():
		blocked_at = eye.distance_to(hit["position"] as Vector3)
	var picked := TargetChoice.choose(
		model, eye, look, blocked_at, player.global_position, _reach_m
	)
	if picked < 0:
		return -1
	var item := model.items[picked]
	var sight := PhysicsRayQueryParameters3D.create(
		eye, ItemView.centre_of(item.kind, item.position), PhysicsLayers.WORLD, [player.get_rid()]
	)
	return picked if space.intersect_ray(sight).is_empty() else -1


func _physics_process(_delta: float) -> void:
	_target = cast_target() if listening else -1


func _process(_delta: float) -> void:
	if model == null or player == null or not reads_device_input:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var was_captured := _was_captured
	_was_captured = captured
	if not listening:
		return
	if Input.is_action_just_pressed(&"interact"):
		pick_up()
	if Input.is_action_just_pressed(&"put_down"):
		put_down()
	if Input.is_action_just_pressed(&"swap"):
		swap()
	if Input.is_action_just_pressed(&"throw"):
		throw()
	if captured and was_captured and Input.is_action_just_pressed(&"use"):
		use()


## Whether the item keys act: a session, a local player, the own player living.
func _acts() -> bool:
	return (
		session != null
		and model != null
		and player != null
		and model.life_of(model.own_peer) == ClientModel.Life.ALIVE
	)
