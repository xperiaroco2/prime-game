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
## The base mode's Draw (GDD §6): PlaceInRange, then PlaceChanges (§9.4).
const NO_SUCH_PLACE := PlaceInRange.NO_SUCH_PLACE
const SAME_PLACE := PlaceChanges.SAME_PLACE
const NOT_CHANNELING := &"not_channeling"
const NOT_DOWNED := &"not_downed"
## The base mode's HandOver (#1389, #1434): a negated Offering, TargetLiving, then
## TargetInReach (2 m between the two players' last accepted feet) after HoldsItem; TakeOffer's
## OfferedTo and CancelOffer's Offering answer `no_offer` without an open offer.
const NO_OFFER := Offers.NO_OFFER
const NOT_LIVING := TargetLiving.NOT_LIVING
const HAND_OVER_REACH_M := 2.0
## TargetDowned of a downed target whose body still moves (the knockdown rework's KE15).
const MOVING := &"moving"
const OUT_OF_REACH := &"out_of_reach"
## The base mode's InReach of PickUp (§9.4: 2 m from the actor's last accepted feet to the item's
## rest position), checked after ItemOnGround and before InSight.
const PICK_UP_REACH_M := 2.0
## The base mode's allowlist (§3.2): phase -> intent -> who may send it (From bits).
## Round takes Throw from the living (the base mode's Throw rule, 37f, #646): with an empty hand
## HoldsItem refuses it as `empty_hand` before OverFloor's `no_floor` is asked; the hostile's own
## bot never holds an item, so a hostile Throw is never thrown.
## Lobby and Countdown take the hand, the belt and Interact from the living as Round does (#1388),
## with the same refusals (no item or station is in the hall yet); not Throw, Raise or Pose. Use
## from the living is never sent where a phase takes it: any hand hits (#1437).
## They also take HandOver, TakeOffer and CancelOffer from the living (#1389, #1434), as the Round
## does: HandOver's first condition is HoldsItem (`empty_hand`), and the hostile's own bot never
## holds an item. And they take Flippers from the living (#1398): PinballSeated answers `not_seated`
## unless the sender sits at the pinball, which a chaos peer never does (it stands metres away).
const ACCEPTS: Dictionary[StringName, Dictionary] = {
	&"lobby":
	{
		&"Hello": From.NEWCOMER,
		&"MoveClaim": From.LIVING,
		&"SetReady": From.PLAYER,
		&"ChangeSettings": From.HOST,
		&"SetProfile": From.PLAYER,
		&"Interact": From.LIVING,
		&"PickUp": From.LIVING,
		&"PutDown": From.LIVING,
		&"Use": From.LIVING,
		&"UseSecondary": From.LIVING,
		&"Swap": From.LIVING,
		&"Draw": From.LIVING,
		&"HandOver": From.LIVING,
		&"TakeOffer": From.LIVING,
		&"CancelOffer": From.LIVING,
		&"Flippers": From.LIVING,
	},
	&"countdown":
	{
		&"Hello": From.NEWCOMER,
		&"MoveClaim": From.LIVING,
		&"SetReady": From.PLAYER,
		&"Interact": From.LIVING,
		&"PickUp": From.LIVING,
		&"PutDown": From.LIVING,
		&"Use": From.LIVING,
		&"UseSecondary": From.LIVING,
		&"Swap": From.LIVING,
		&"Draw": From.LIVING,
		&"HandOver": From.LIVING,
		&"TakeOffer": From.LIVING,
		&"CancelOffer": From.LIVING,
		&"Flippers": From.LIVING,
	},
	&"loading": {&"LoadAck": From.PLAYER},
	# The silent pregame (#213) takes nothing: a MoveClaim is dropped, the rest not_accepted.
	&"pregame": {},
	&"round":
	{
		&"MoveClaim": From.LIVING | From.DOWNED,
		&"PickUp": From.LIVING,
		&"PutDown": From.LIVING,
		&"Use": From.LIVING,
		&"UseSecondary": From.LIVING,
		&"Raise": From.LIVING,
		&"StopRaise": From.LIVING,
		&"Swap": From.LIVING,
		&"Draw": From.LIVING,
		&"Throw": From.LIVING,
		&"Interact": From.LIVING,
		&"Pose": From.LIVING,
		&"HandOver": From.LIVING,
		&"TakeOffer": From.LIVING,
		&"CancelOffer": From.LIVING,
		&"GiveUp": From.DOWNED,
	},
	&"end": {&"ReturnToLobby": From.HOST},
}
## The intents the base mode accepts in no phase, from no sender, the host included: the part of
## ACCEPTS that has no row above (accepts() reads an absent intent as refused). NextStage (#599,
## E65) is a scripted mode's control: the tutorial's phases list it, the base mode's none. A test
## pins that every intent is in a phase of ACCEPTS or here, so a new intent needs a decision.
## Interact (#796) left it when the Generator (G5, #800) gave Round its row.
## Pose (#1296) left it when the camera wall's chair (#1383) gave Round its row.
const NEVER_ACCEPTED: Array[StringName] = [&"NextStage"]


## The reason the host must reject `intent` (with `args`) from `peer` with, or SILENT; `phase` is
## the phase it is applied in, `player` the sender's state (null for a newcomer), `match_id` the
## current match's id, `state` the match the intent meets (its items and the other players; null:
## no item exists and the sender is the only player), `mode` the mode played (null: its rules are
## not known, so Interact's role and mode rules are not looked for).
static func answer(
	intent: StringName,
	args: Dictionary,
	peer: int,
	phase: StringName,
	player: PlayerState,
	match_id: int,
	state: MatchState = null,
	mode: GameMode = null
) -> StringName:
	if not accepts(intent, peer, phase, player):
		# A refused MoveClaim is dropped (E15); everything else is not_accepted (§3.1). A chaos
		# peer never sends a Hello as a newcomer (that would be its join).
		return SILENT if intent == Intents.MOVE_CLAIM else RejectReasons.NOT_ACCEPTED
	return _rule(intent, args, peer, player, match_id, state, mode)


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
	if player.is_limp() and intent != Intents.MOVE_CLAIM and Intents.PLAYER_ACTIONS.has(intent):
		# A limp player sends no player's action but its facing (#1393, §7.1.21).
		return false
	var living := player.life == PlayerState.Life.ALIVE
	return (
		from & From.PLAYER != 0
		or (from & From.LIVING != 0 and living)
		or (from & From.DOWNED != 0 and player.life == PlayerState.Life.DOWNED)
		or (from & From.HOST != 0 and peer == NetTransport.HOST_ID)
	)


## What the hostile's borrowed return key broke (#639; the returning-players ADR: a key a present
## player holds stays with that player): its Hello carried the key of the honest bot at
## `honest_peer`, sent once that bot had joined, so the hostile joined after it as a new number
## and bound none, and the honest bot keeps the number its `honest_key` binds. Empty when nothing.
static func key_problems(
	state: MatchState, hostile_peer: int, honest_peer: int, honest_key: String
) -> PackedStringArray:
	var found := PackedStringArray()
	var bound: int = state.numbers.get(honest_key, 0)
	if bound == 0:
		found.append("the honest bot's return key binds no number")
	var honest := state.player(honest_peer) if honest_peer != 0 else null
	if honest != null and honest.number != bound:
		found.append("the honest bot holds number %d, its key binds %d" % [honest.number, bound])
	var hostile := state.player(hostile_peer) if hostile_peer != 0 else null
	if hostile == null:
		found.append("the hostile peer is no player at the end, so its number was not checked")
		return found
	if hostile.number <= bound:
		found.append(
			(
				"the hostile peer holds number %d with the honest bot's key (bound to %d)"
				% [hostile.number, bound]
			)
		)
	for key: String in state.numbers:
		if state.numbers[key] == hostile.number:
			found.append("the hostile peer's number %d is bound to a key" % hostile.number)
	return found


## The answer of an intent the allowlist took, for what a chaos peer sends (§4.1).
static func _rule(
	intent: StringName,
	args: Dictionary,
	peer: int,
	player: PlayerState,
	match_id: int,
	state: MatchState,
	mode: GameMode
) -> StringName:
	var answer_now := RejectReasons.NOTHING_TO_DO
	match intent:
		Intents.SET_READY:
			answer_now = RejectReasons.UNCHANGED if args.get("ready") == player.ready else &"?"
		Intents.SET_PROFILE:
			# The chaos peers send SetProfile the lobby takes only with the sender's own name and
			# colour (#551): never a change, so its answer does not depend on the others'.
			var same: bool = args.get("name") == player.name and args.get("colour") == player.colour
			answer_now = RejectReasons.UNCHANGED if same else &"?"
		Intents.LOAD_ACK:
			answer_now = SILENT if args.get("match_id") != match_id else RejectReasons.UNCHANGED
		Intents.PICK_UP:
			answer_now = _pick_up(args.get("item", -1) as int, player, state)
		Intents.PUT_DOWN, Intents.THROW:
			answer_now = EMPTY_HAND if player.held_item < 0 else &"?"
		Intents.USE:
			# Any hand hits (#1437), so the chaos peers never send Use where a phase takes it from
			# them (ChaosHostile: Loading only); there it would swing, or be too_soon or tired.
			answer_now = &"?"
		Intents.USE_SECONDARY:
			answer_now = RejectReasons.NOTHING_TO_DO if player.held_item < 0 else &"?"
		Intents.SWAP:
			var empty := player.carried_items().is_empty()
			answer_now = NOTHING_TO_SWAP if empty else &"?"
		Intents.DRAW:
			answer_now = _draw(args.get("place", -1), player)
		Intents.POSE:
			# The levels the chaos runs play (ScenarioLevels.of: the greybox) hold no chair marker of
			# the base mode's Pose row (chaos_test pins it), so no sender stands at one.
			answer_now = OUT_OF_REACH
		Intents.STOP_RAISE:
			answer_now = NOT_CHANNELING
		Intents.RAISE:
			var target_peer: int = args.get("target", 0)
			var target := player if target_peer == peer else null
			if state != null and target_peer != peer:
				target = state.player(target_peer)
			# TargetDowned comes first (§9.5): a target that is not downed answers not_downed,
			# whatever its role; a downed one still moving answers moving (KE15, never on the greybox,
			# KE12); one at rest the chaos peers never name.
			var standing := target != null and target.life != PlayerState.Life.DOWNED
			if standing:
				answer_now = NOT_DOWNED
			elif target != null and target.motion != null:
				answer_now = MOVING
			else:
				answer_now = &"?"
		Intents.INTERACT:
			answer_now = _interact(args, player, state, mode)
		Intents.HAND_OVER:
			answer_now = _hand_over(args.get("target", 0) as int, peer, player, state)
		Intents.TAKE_OFFER:
			answer_now = _take_offer(args.get("target", 0) as int, peer, player, state)
		Intents.CANCEL_OFFER:
			answer_now = _cancel_offer(peer, state)
		Intents.FLIPPERS:
			var seated := state != null and Pinball.seated(state) == peer
			answer_now = Pinball.NOT_SEATED if not seated else &"?"
	# "?": an input the chaos peers never send in that state; the check reports it.
	return answer_now


## Interact's target checks (§4.1, the cooking ADR's CE1): naming both a station and an item, or
## neither, is `bad_args`; an id that names nothing, or a display station (CE6), is `nothing_to_do`;
## a target that exists but has no Interact rule where the host looks for one is `nothing_to_do`
## too (Match._find_action: a placed station tries its kind's actions, then the actor's role's and
## the mode's; an item only its kind's target_actions). In the base mode only the Generator's,
## Cooking's and car repair's station kinds and Cooking's boxes have one (§9.5.19, §9.5.20,
## §9.5.21), and all three play on the House alone (GD7, CD15, #810), so on the greybox every
## accepted Interact gets this. The lobby's tap (#1390) and pinball machine (#1398), both placed by
## StationTicks, have one whose first condition is AtStation: a sender outside its cylinder gets
## `out_of_reach` (the chaos peers stand on the hall's player markers, metres from the Bar and the
## Pinball). Any other target with the rule is "?" (its conditions are the mode's, and the chaos
## run never meets one). `mode` null: only the target kind's rules.
static func _interact(
	args: Dictionary, player: PlayerState, state: MatchState, mode: GameMode
) -> StringName:
	var station: int = args.get("station", -1)
	var item: int = args.get("item", -1)
	if (station >= 0) == (item >= 0):
		return RejectReasons.BAD_ARGS
	var rules: Array[Rule] = []
	var target: StationState = null
	if state != null and item >= 0:
		if state.items.has(item):
			rules = (state.items[item] as ItemState).kind.target_actions
	elif state != null and state.stations.has(station):
		target = state.stations[station]
		if not target.kind.display:
			rules = target.kind.actions.duplicate()
			var role: GameRole = null
			if mode != null and player != null:
				role = mode.find_role(player.role)
			if role != null:
				rules.append_array(role.actions)
			if mode != null:
				rules.append_array(mode.actions)
	for rule: Rule in rules:
		if rule.trigger != Intents.INTERACT:
			continue
		var reach := not rule.conditions.is_empty() and rule.conditions[0] is AtStation
		if reach and target != null and player != null and not target.contains(player.position):
			return AtStation.OUT_OF_REACH
		return &"?"
	return RejectReasons.NOTHING_TO_DO


## Draw's conditions in their order (§9.4): PlaceInRange (`no_such_place`, a place outside 0..2),
## then PlaceChanges (`same_place`, the place already in the hand). Any other place is "?".
static func _draw(place: Variant, player: PlayerState) -> StringName:
	if not place is int or place < 0 or place >= PlayerState.PLACES:
		return NO_SUCH_PLACE
	return SAME_PLACE if place == player.selected_place else &"?"


## HandOver's conditions in their order (§9.4, #1389, #1434): HoldsItem (`empty_hand`), a negated
## Offering (`not_allowed` while the sender's own offer is open), TargetLiving (`bad_args` for the
## sender itself, `not_living` for a peer that is no player, limp, downed, dead or gone), then
## TargetInReach (`out_of_reach`, more than 2 m between the last accepted feet). A target within
## reach is "?": TargetInSight needs the level, and the hostile's own bot never holds an item, so
## its HandOver stops at HoldsItem.
static func _hand_over(
	target_peer: int, peer: int, player: PlayerState, state: MatchState
) -> StringName:
	if player.held_item < 0:
		return EMPTY_HAND
	var held: ItemState = state.items.get(player.held_item) if state != null else null
	if held == null:
		return &"?"
	if Offers.live(state, peer) != null:
		return RejectReasons.NOT_ALLOWED
	return _living_in_reach(target_peer, peer, player, state)


## TakeOffer's conditions in their order (§9.4, #1434): OfferedTo (`bad_args` for the sender itself,
## `no_offer` unless `target_peer` offers the sender its hand item now), then TargetLiving and
## TargetInReach as HandOver's. Nobody offers the hostile's bot anything (its bot names others, and
## the honest bots never hand over), so its TakeOffer stops at `no_offer`.
static func _take_offer(
	target_peer: int, peer: int, player: PlayerState, state: MatchState
) -> StringName:
	if target_peer == peer:
		return RejectReasons.BAD_ARGS
	var offer := Offers.live(state, target_peer) if state != null else null
	if offer == null or offer.target != peer:
		return NO_OFFER
	return _living_in_reach(target_peer, peer, player, state)


## CancelOffer's Offering (§9.4, #1434): `no_offer` unless the sender's own offer is open, which the
## hostile's bot, never holding an item, never has.
static func _cancel_offer(peer: int, state: MatchState) -> StringName:
	return NO_OFFER if state == null or Offers.live(state, peer) == null else &"?"


## TargetLiving (`bad_args` for the sender itself, `not_living`), then TargetInReach
## (`out_of_reach`); "?" past them (TargetInSight needs the level).
static func _living_in_reach(
	target_peer: int, peer: int, player: PlayerState, state: MatchState
) -> StringName:
	if target_peer == peer:
		return RejectReasons.BAD_ARGS
	var target := state.player(target_peer)
	if target == null or target.life != PlayerState.Life.ALIVE or target.is_limp():
		return NOT_LIVING
	if player.position.distance_to(target.position) > HAND_OVER_REACH_M:
		return OUT_OF_REACH
	return &"?"


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
