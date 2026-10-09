class_name ChaosOracle
extends RefCounted
## The rules' answer to a well-formed chaos intent, written from ARCHITECTURE, not from the code
## that gives it (§3.1, the base mode's table in §3.2, §4.1, §7.1, E14, E15): evaluated against the
## state the intent meets when the host applies it (the observer's match right after the call; a
## refused intent changes nothing, so the state after it is the state it met). The chaos peers send
## only intents the rules refuse whatever the timing, or that are dropped in silence, so a wrong
## acceptance shows as a missing Rejected and as a difference from the baseline run.

## The base mode's allowlist (§3.2): phase -> intent -> who may send it. LIVING and DOWNED are the
## life states; PLAYER any present player that is not dead; HOST peer 1; NEWCOMER a peer whose Hello
## was not accepted yet.
enum From { NEWCOMER = 1, PLAYER = 2, LIVING = 4, HOST = 16, DOWNED = 32 }

## No reply: the intent is dropped in silence (a MoveClaim the phase refuses, E15; a LoadAck of
## another match, §4.1).
const SILENT := &""
## A PickUp names this item, which no match spawns (ids count from 0 up to the items of the deal).
const NO_ITEM := 4000
## The reasons the conditions of the base mode's actions give (§9.4, §9.5).
const UNAVAILABLE := &"unavailable"
const EMPTY_HAND := &"empty_hand"
const NOTHING_TO_SWAP := &"nothing_to_swap"
const NOT_CHANNELING := &"not_channeling"
const NOT_DOWNED := &"not_downed"
const OUT_OF_REACH := &"out_of_reach"
## The base mode's InReach of PickUp (§9.4: 2 m from the actor's last accepted feet to the item's
## rest position), checked after ItemOnGround and before InSight.
const PICK_UP_REACH_M := 2.0
## The base mode's allowlist (§3.2): phase -> intent -> who may send it (From bits).
const ACCEPTS: Dictionary[StringName, Dictionary] = {
	&"lobby":
	{
		&"Hello": From.NEWCOMER,
		&"MoveClaim": From.LIVING,
		&"SetReady": From.PLAYER,
		&"ChangeSettings": From.HOST,
	},
	&"countdown": {&"Hello": From.NEWCOMER, &"MoveClaim": From.LIVING, &"SetReady": From.PLAYER},
	&"loading": {&"LoadAck": From.PLAYER},
	# The silent pregame (#213) takes nothing: a MoveClaim is dropped, the rest not_accepted.
	&"pregame": {},
	&"round":
	{
		&"MoveClaim": From.LIVING | From.DOWNED,
		&"PickUp": From.LIVING,
		&"PutDown": From.LIVING,
		&"Use": From.LIVING,
		&"Raise": From.LIVING,
		&"StopRaise": From.LIVING,
		&"Swap": From.LIVING,
		&"GiveUp": From.DOWNED,
	},
	&"end": {&"ReturnToLobby": From.HOST},
}
## The intents the base mode accepts in no phase, from no sender, the host included: the part of
## ACCEPTS that has no row above (accepts() reads an absent intent as refused). NextStage (#599,
## E65) is a scripted mode's control: the tutorial's phases list it, the base mode's none. A test
## pins that every intent is in a phase of ACCEPTS or here, so a new intent needs a decision.
const NEVER_ACCEPTED: Array[StringName] = [&"NextStage"]


## The reason the host must reject `intent` (with `args`) from `peer` with, or SILENT; `phase` is
## the phase it is applied in, `player` the sender's state (null for a newcomer), `match_id` the
## current match's id, `state` the match the intent meets (its items and the other players; null:
## no item exists and the sender is the only player).
static func answer(
	intent: StringName,
	args: Dictionary,
	peer: int,
	phase: StringName,
	player: PlayerState,
	match_id: int,
	state: MatchState = null
) -> StringName:
	if not accepts(intent, peer, phase, player):
		# A refused MoveClaim is dropped (E15); everything else is not_accepted (§3.1). A chaos
		# peer never sends a Hello as a newcomer (that would be its join).
		return SILENT if intent == Intents.MOVE_CLAIM else RejectReasons.NOT_ACCEPTED
	return _rule(intent, args, peer, player, match_id, state)


## Whether the phase's allowlist takes `intent` from `peer` (§3.1, §3.2).
static func accepts(intent: StringName, peer: int, phase: StringName, player: PlayerState) -> bool:
	var from: int = (ACCEPTS.get(phase, {}) as Dictionary).get(intent, 0)
	if intent == Intents.SET_READY and phase == &"countdown":
		# Countdown takes SetReady(false) only (§4.1); the chaos peers send true.
		return false
	if player == null:
		return from & From.NEWCOMER != 0
	if player.life == PlayerState.Life.DEAD or player.life == PlayerState.Life.LEFT:
		# The dead send no intents as players (§3.1); the host's own controls are peer 1's.
		return false
	var living := player.life == PlayerState.Life.ALIVE
	return (
		from & From.PLAYER != 0
		or (from & From.LIVING != 0 and living)
		or (from & From.DOWNED != 0 and player.life == PlayerState.Life.DOWNED)
		or (from & From.HOST != 0 and peer == NetTransport.HOST_ID)
	)


## The answer of an intent the allowlist took, for what a chaos peer sends (§4.1).
static func _rule(
	intent: StringName,
	args: Dictionary,
	peer: int,
	player: PlayerState,
	match_id: int,
	state: MatchState
) -> StringName:
	var answer_now := RejectReasons.NOTHING_TO_DO
	match intent:
		Intents.SET_READY:
			answer_now = RejectReasons.UNCHANGED if args.get("ready") == player.ready else &"?"
		Intents.LOAD_ACK:
			answer_now = SILENT if args.get("match_id") != match_id else RejectReasons.UNCHANGED
		Intents.PICK_UP:
			answer_now = _pick_up(args.get("item", -1) as int, player, state)
		Intents.PUT_DOWN:
			answer_now = EMPTY_HAND if player.held_item < 0 else &"?"
		Intents.USE:
			answer_now = RejectReasons.NOTHING_TO_DO if player.held_item < 0 else &"?"
		Intents.SWAP:
			var empty := player.held_item < 0 and player.belt_item < 0
			answer_now = NOTHING_TO_SWAP if empty else &"?"
		Intents.STOP_RAISE:
			answer_now = NOT_CHANNELING
		Intents.RAISE:
			var target_peer: int = args.get("target", 0)
			var target := player if target_peer == peer else null
			if state != null and target_peer != peer:
				target = state.player(target_peer)
			# TargetDowned comes first (§9.5): a target that is not downed answers not_downed,
			# whatever its role; a downed one the chaos peers never name.
			var standing := target != null and target.life != PlayerState.Life.DOWNED
			answer_now = NOT_DOWNED if standing else &"?"
	# "?": an input the chaos peers never send in that state; the check reports it.
	return answer_now


## PickUp's conditions in their order (§9.4): ItemOnGround (`unavailable`), then InReach from the
## sender's last accepted feet (`out_of_reach`). An item on the ground within reach is "?": the
## chaos peers name only items that rest far from them, so a pick-up it could take is a race the
## check reports, never an answer.
static func _pick_up(id: int, player: PlayerState, state: MatchState) -> StringName:
	var item: ItemState = state.items.get(id) if state != null else null
	if item == null or item.where != ItemState.Where.GROUND:
		return UNAVAILABLE
	if player.position.distance_to(item.position) > PICK_UP_REACH_M:
		return OUT_OF_REACH
	return &"?"
