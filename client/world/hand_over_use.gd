class_name HandOverUse
extends Node3D
## The hand-over key (#1411; ARCHITECTURE §4.1 `HandOver`, §4.7.10; GDD §6 "The hand and the
## belt"): E (`interact`, provisional: the engineer's to confirm) aimed at a living player sends
## HandOver(target) while the own hand holds an item the client's own copy of the mode lets go
## from hand to hand, in a phase that accepts HandOver from the living (the base mode: the Lobby
## and the Countdown, so the bar's mug goes to a friend). Its prompt is cue(): the HUD's Aim, in
## the lobby and the round alike.
##
## The client mirrors the host's checks of the HandOver rule (§7.1) so that it offers only what
## the host would accept: the hand item's kind handable (HandHandable) and one-handed
## (HandNotTwoHanded), the target a present living player other than the own (TargetLiving), within
## the rule's TargetInReach of the feet less the hint's walking margin (TargetChoice.hint_reach,
## #319: the host measures from the feet of the last claim it accepted), and the line from the own
## eye to the target's clear of the level (TargetInSight `at_eye`). The host checks everything
## again; a refusal shows nothing, as every refusal of an action in the world (§4.3.2: the client
## predicts nothing of a hand-over, so nothing is undone).
##
## E does one thing: any other target E has wins over the hand-over (an item or a station
## ItemInteractions offers, a downed player LifeView would raise, the photo viewfinder that E
## closes), so with one of them under the crosshair target() is 0 and no prompt shows.
##
## The target is cast in the physics step after ItemInteractions' (PHYSICS_PRIORITY), the only
## time the physics space may be read: the first thing along the camera's ray, so a wall in front
## hides a player behind it.

const PHYSICS_PRIORITY := 7
## How far the camera's ray looks for a player, in metres: past any reach the host grants, since
## the reach is checked from the feet afterwards (as TargetChoice.RAY_M).
const RAY_M := 4.0

var model: ClientModel
var session: ClientSession
## The client's own copy of the mode.
var mode: GameMode
var player: PlayerController
## The item keys, whose targets win over the hand-over (ItemWorld sets it).
var interactions: ItemInteractions
## The downed player E would raise (LifeView.raise_target), 0 for none; Game sets it.
var raise_target := Callable()
## Whether the key is read from the devices (false for a game a test or the bots drive).
var reads_device_input := true
## Whether the keys count now: a screen the player walks on (the lobby, the round) with no Esc
## menu (GamePlayer.apply_flags).
var listening := true

var _target := 0
var _reach_m := 0.0


func _init() -> void:
	name = "HandOverUse"
	process_physics_priority = PHYSICS_PRIORITY


func setup(client: ClientSession, game_mode: GameMode) -> void:
	session = client
	model = client.model if client != null else null
	mode = game_mode
	_reach_m = hint_reach_of(mode) if mode != null else 0.0
	_target = 0


## The reach of `game_mode`'s HandOver (its TargetInReach), in metres from the feet; 0 when the
## mode has no HandOver rule, which offers nothing.
static func reach_of(game_mode: GameMode) -> float:
	for rule: Rule in game_mode.actions:
		if rule.trigger != Intents.HAND_OVER:
			continue
		for condition: Condition in rule.conditions:
			var reach := condition as TargetInReach
			if reach != null:
				return reach.reach_m
	return 0.0


## The reach the prompt and E offer a player within: reach_of() less the hint's walking margin
## (TargetChoice.hint_reach, as the pick-up's and the raise's); 0 when the mode has no HandOver.
static func hint_reach_of(game_mode: GameMode) -> float:
	return TargetChoice.hint_reach(reach_of(game_mode), game_mode)


## Whether the own player could hand its hand item over now, whoever it aims at: living (not limp,
## #1393: the host refuses a limp player every action), in a
## phase whose own copy accepts HandOver from the living, holding in its hand an item whose kind is
## handable and not two-handed.
static func can_hand(client_model: ClientModel, game_mode: GameMode) -> bool:
	if client_model == null or game_mode == null:
		return false
	var own := client_model.own_peer
	if client_model.body_life_of(own) != ClientModel.Life.ALIVE:
		return false
	var spec := client_model.phase_spec()
	if spec == null or (spec.senders_of(Intents.HAND_OVER) & AcceptSpec.From.LIVING) == 0:
		return false
	var item: ClientModel.Item = client_model.items.get(client_model.hand_item(own))
	if item == null:
		return false
	var kind := game_mode.find_item_kind(item.kind)
	return kind != null and kind.is_handable() and not kind.is_two_handed()


## Whether E would hand the own hand item to `peer`, whose feet stand at `target_feet`, from the
## own feet at `feet` (can_hand(), then the host's TargetLiving and TargetInReach within
## `reach_m`; the sight is the physics space's, cast_target()).
static func offers(
	client_model: ClientModel,
	game_mode: GameMode,
	peer: int,
	feet: Vector3,
	target_feet: Vector3,
	reach_m: float
) -> bool:
	if not can_hand(client_model, game_mode) or reach_m <= 0.0:
		return false
	if peer == 0 or peer == client_model.own_peer or not client_model.roster.has(peer):
		return false
	if client_model.life_of(peer) != ClientModel.Life.ALIVE:
		return false
	return feet.distance_to(target_feet) <= reach_m


## The living player E would hand the own hand item to, or 0 (cast in the last physics step).
func target() -> int:
	return _target


## The prompt: the label of the interact key bound now (KeyLabel, #211) while target() names a
## player; "" otherwise. HudText.hand_over_cue() words it.
func cue() -> String:
	return KeyLabel.of_action(&"interact") if _target != 0 else ""


## E: HandOver(target) for target(), after the claim twin (ClientSession.send_intent: HandOver is
## a player action, §4.1); the sequence number sent, or -1 when nothing was sent.
func hand_over() -> int:
	if _target == 0 or session == null or not can_hand(model, mode):
		return -1
	return session.send_intent(Intents.HAND_OVER, {"target": _target})


## The player under the crosshair the hand-over may go to, or 0: the first body along the camera's
## ray that is no wall, a living player's (RemotePlayerBody) whom offers() accepts, with the line
## from the own eye to its eye clear of the level.
func cast_target() -> int:
	if player == null or not player.is_inside_tree() or not can_hand(model, mode):
		return 0
	var eye := player.get_camera().global_position
	var to := eye + player.look_vector() * RAY_M
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		eye, to, PhysicsLayers.WORLD | PhysicsLayers.LIVING, [player.get_rid()]
	)
	var body := space.intersect_ray(query).get("collider") as RemotePlayerBody
	if body == null or not body.is_living():
		return 0
	if not offers(model, mode, body.peer, player.global_position, body.global_position, _reach_m):
		return 0
	var crouched := body.is_crouched()
	var their_eye := body.global_position + Vector3.UP * body.rules.eye_height_of(crouched)
	var sight := PhysicsRayQueryParameters3D.create(
		eye, their_eye, PhysicsLayers.WORLD, [player.get_rid()]
	)
	return body.peer if space.intersect_ray(sight).is_empty() else 0


## Whether E has another target now, which wins over the hand-over.
func _yields() -> bool:
	if interactions != null:
		if interactions.viewing():
			return true
		if interactions.target() >= 0 or interactions.station_target() >= 0:
			return true
	return raise_target.is_valid() and (raise_target.call() as int) != 0


func _physics_process(_delta: float) -> void:
	_target = 0
	if listening and not _yields():
		_target = cast_target()


func _process(_delta: float) -> void:
	if not reads_device_input or not listening or model == null:
		return
	if Input.is_action_just_pressed(&"interact"):
		hand_over()
