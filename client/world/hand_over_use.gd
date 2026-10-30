class_name HandOverUse
extends Node3D
## The hand-over key (#1411, an offer since #1434; ARCHITECTURE §4.1 `HandOver`, `TakeOffer`,
## `CancelOffer`, §4.7.10; GDD §6 "Handing over"): E (`interact`, provisional: the engineer's to
## confirm) does one of three things, chosen each physics step (choose()):
## - TAKE: aimed at a standing player who offers the own player its hand item (ClientModel.offers,
##   from the public OfferMade), E sends TakeOffer(target = that giver).
## - CANCEL: while the own player has an open offer, E sends CancelOffer, wherever it aims (so a
##   giver still aiming at its receiver cancels rather than offering again, which the host's
##   negated Offering would refuse).
## - OFFER: aimed at a standing player while the own hand holds any item, E sends HandOver(target).
## Each needs a phase whose own copy accepts its intent from the living. Its prompt is cue() with
## the deck key cue_key(): the HUD's Aim, in the lobby and the round alike.
##
## The client mirrors the host's checks (§7.1) so that it offers only what the host would accept:
## the own player standing (body_life_of: not limp, #1393, the host refuses a limp player every
## action), the other a present standing player other than the own (TargetLiving refuses a limp
## one), within the rule's TargetInReach of the feet less the hint's walking margin
## (TargetChoice.hint_reach, #319: the host measures from the feet of the last claim it accepted),
## and the line from the own eye to the other's eye clear of the level (TargetInSight `at_eye`).
## The host checks everything again; a refusal shows nothing, as every refusal of an action in
## the world (§4.3.2: the client predicts nothing of an offer, so nothing is undone).
##
## E does one thing: any other target E has wins over the hand-over (an item or a station
## ItemInteractions offers, a downed player LifeView would raise, the photo viewfinder that E
## closes), so with one of them under the crosshair prompt() is NONE.
##
## The target is cast in the physics step after ItemInteractions' (PHYSICS_PRIORITY), the only
## time the physics space may be read: the first thing along the camera's ray, so a wall in front
## hides a player behind it.

## What E would do now.
enum Prompt { NONE, OFFER, TAKE, CANCEL }

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
var _prompt := Prompt.NONE
var _reach_m := 0.0
var _take_reach_m := 0.0


func _init() -> void:
	name = "HandOverUse"
	process_physics_priority = PHYSICS_PRIORITY


func setup(client: ClientSession, game_mode: GameMode) -> void:
	session = client
	model = client.model if client != null else null
	mode = game_mode
	_reach_m = hint_reach_of(mode) if mode != null else 0.0
	_take_reach_m = hint_reach_of(mode, Intents.TAKE_OFFER) if mode != null else 0.0
	_target = 0
	_prompt = Prompt.NONE


## The reach of `game_mode`'s rule on `intent` (HandOver, TakeOffer: its TargetInReach), in
## metres from the feet; 0 when the mode has no such rule, which offers nothing.
static func reach_of(game_mode: GameMode, intent: StringName = Intents.HAND_OVER) -> float:
	for rule: Rule in game_mode.actions:
		if rule.trigger != intent:
			continue
		for condition: Condition in rule.conditions:
			var reach := condition as TargetInReach
			if reach != null:
				return reach.reach_m
	return 0.0


## The reach the prompt and E offer a player within: reach_of() less the hint's walking margin
## (TargetChoice.hint_reach, as the pick-up's and the raise's); 0 when the mode has no such rule.
static func hint_reach_of(game_mode: GameMode, intent: StringName = Intents.HAND_OVER) -> float:
	return TargetChoice.hint_reach(reach_of(game_mode, intent), game_mode)


## Whether the own player may send `intent` now: standing (not downed, dead or limp) in a phase
## whose own copy accepts it from the living.
static func may_send(client_model: ClientModel, intent: StringName) -> bool:
	if client_model == null:
		return false
	if client_model.body_life_of(client_model.own_peer) != ClientModel.Life.ALIVE:
		return false
	var spec := client_model.phase_spec()
	return spec != null and (spec.senders_of(intent) & AcceptSpec.From.LIVING) != 0


## Whether the own player could offer its hand item now, whoever it aims at: may_send(HandOver),
## any item in its hand (#1434: every kind), and no offer of its own open.
static func can_hand(client_model: ClientModel, game_mode: GameMode) -> bool:
	if game_mode == null or not may_send(client_model, Intents.HAND_OVER):
		return false
	var own := client_model.own_peer
	if client_model.offer_of(own) != 0:
		return false
	return client_model.items.has(client_model.hand_item(own))


## Whether E would offer the own hand item to `peer`, whose feet stand at `target_feet`, from the
## own feet at `feet` (can_hand(), then the host's TargetLiving and TargetInReach within
## `reach_m`; the sight is the physics space's, _aimed()).
static func offers(
	client_model: ClientModel,
	game_mode: GameMode,
	peer: int,
	feet: Vector3,
	target_feet: Vector3,
	reach_m: float
) -> bool:
	if not can_hand(client_model, game_mode):
		return false
	return _standing_other(client_model, peer, feet, target_feet, reach_m)


## Whether E would take `peer`'s offer (TakeOffer): may_send(TakeOffer), `peer` a present standing
## player other than the own who offers to the own player, its feet at `target_feet` within
## `reach_m` of the own feet at `feet`.
static func takes(
	client_model: ClientModel, peer: int, feet: Vector3, target_feet: Vector3, reach_m: float
) -> bool:
	if not may_send(client_model, Intents.TAKE_OFFER):
		return false
	if client_model.offer_of(peer) != client_model.own_peer:
		return false
	return _standing_other(client_model, peer, feet, target_feet, reach_m)


## What E would do with `aimed` under the crosshair (0 for nobody in sight), in this order: take
## its offer to the own player, cancel the own open offer (wherever it aims), offer the own hand
## item to it; NONE when none applies.
static func choose(
	client_model: ClientModel,
	game_mode: GameMode,
	aimed: int,
	feet: Vector3,
	aimed_feet: Vector3,
	reach_m: float,
	take_reach_m: float
) -> Prompt:
	if client_model == null:
		return Prompt.NONE
	if aimed != 0 and takes(client_model, aimed, feet, aimed_feet, take_reach_m):
		return Prompt.TAKE
	if client_model.offer_of(client_model.own_peer) != 0:
		if may_send(client_model, Intents.CANCEL_OFFER):
			return Prompt.CANCEL
		return Prompt.NONE
	if aimed != 0 and offers(client_model, game_mode, aimed, feet, aimed_feet, reach_m):
		return Prompt.OFFER
	return Prompt.NONE


## What E would do now (chosen in the last physics step).
func prompt() -> Prompt:
	return _prompt


## The player E would offer to or take from, or the own offer's receiver for CANCEL; 0 for none.
func target() -> int:
	return _target


## The prompt: the label of the interact key bound now (KeyLabel, #211) while prompt() is not
## NONE; "" otherwise. HudText.hand_over_cue() words it with cue_key().
func cue() -> String:
	return KeyLabel.of_action(&"interact") if _prompt != Prompt.NONE else ""


## The deck key that words cue() (HudText): offer, take or cancel; "" for NONE.
func cue_key() -> String:
	match _prompt:
		Prompt.OFFER:
			return HudText.HAND_OVER_CUE
		Prompt.TAKE:
			return HudText.TAKE_OFFER_CUE
		Prompt.CANCEL:
			return HudText.OFFERING_CUE
	return ""


## E: HandOver(target), TakeOffer(target) or CancelOffer by prompt(), after the claim twin
## (ClientSession.send_intent: each is a player action, §4.1); the sequence number sent, or -1
## when nothing was sent.
func hand_over() -> int:
	if session == null or model == null:
		return -1
	match _prompt:
		Prompt.OFFER:
			if _target != 0 and can_hand(model, mode):
				return session.send_intent(Intents.HAND_OVER, {"target": _target})
		Prompt.TAKE:
			if _target != 0 and model.offer_of(_target) == model.own_peer:
				return session.send_intent(Intents.TAKE_OFFER, {"target": _target})
		Prompt.CANCEL:
			if model.offer_of(model.own_peer) != 0:
				return session.send_intent(Intents.CANCEL_OFFER, {})
	return -1


## The player under the crosshair the offer may go to or come from, or 0: the first body along
## the camera's ray that is no wall, a living player's (RemotePlayerBody), with the line from the
## own eye to its eye clear of the level.
func _aimed() -> RemotePlayerBody:
	if player == null or not player.is_inside_tree():
		return null
	var eye := player.get_camera().global_position
	var to := eye + player.look_vector() * RAY_M
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		eye, to, PhysicsLayers.WORLD | PhysicsLayers.LIVING, [player.get_rid()]
	)
	var body := space.intersect_ray(query).get("collider") as RemotePlayerBody
	if body == null or not body.is_living():
		return null
	var crouched := body.is_crouched()
	var their_eye := body.global_position + Vector3.UP * body.rules.eye_height_of(crouched)
	var sight := PhysicsRayQueryParameters3D.create(
		eye, their_eye, PhysicsLayers.WORLD, [player.get_rid()]
	)
	return body if space.intersect_ray(sight).is_empty() else null


## Whether `peer` is a present standing player other than the own, its feet at `target_feet`
## within `reach_m` (> 0) of `feet`.
static func _standing_other(
	client_model: ClientModel, peer: int, feet: Vector3, target_feet: Vector3, reach_m: float
) -> bool:
	if reach_m <= 0.0 or peer == 0 or peer == client_model.own_peer:
		return false
	if not client_model.roster.has(peer):
		return false
	if client_model.body_life_of(peer) != ClientModel.Life.ALIVE:
		return false
	return feet.distance_to(target_feet) <= reach_m


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
	_prompt = Prompt.NONE
	if not listening or model == null or _yields():
		return
	var body := _aimed()
	var aimed := body.peer if body != null else 0
	var feet := player.global_position if player != null else Vector3.ZERO
	var aimed_feet := body.global_position if body != null else Vector3.ZERO
	_prompt = choose(model, mode, aimed, feet, aimed_feet, _reach_m, _take_reach_m)
	match _prompt:
		Prompt.OFFER, Prompt.TAKE:
			_target = aimed
		Prompt.CANCEL:
			_target = model.offer_of(model.own_peer)


func _process(_delta: float) -> void:
	if not reads_device_input or not listening or model == null:
		return
	if Input.is_action_just_pressed(&"interact"):
		hand_over()
