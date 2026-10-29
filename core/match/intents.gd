class_name Intents
extends RefCounted
## The names of the intents (ARCHITECTURE §4.1) and of the commands server/ originates. A rule's
## trigger and a phase's allowlist name intents from ALL; ModeCheck refuses any other name.

const HELLO := &"Hello"
const SET_READY := &"SetReady"
const CHANGE_SETTINGS := &"ChangeSettings"
const LOAD_ACK := &"LoadAck"
const MOVE_CLAIM := &"MoveClaim"
const PICK_UP := &"PickUp"
const PUT_DOWN := &"PutDown"
const USE := &"Use"
const RETURN_TO_LOBBY := &"ReturnToLobby"
## A living player starts raising a downed one, `target` (M4-4, E28): sent on pressing E over it.
const RAISE := &"Raise"
## The raiser lets go of E (M4-4, E28).
const STOP_RAISE := &"StopRaise"
## A downed player gives up and dies at once (M4-4).
const GIVE_UP := &"GiveUp"
## X: a living player draws the place it held last back into the hand (M4-5, vision revision 1:
## Two hands; GDD §6 "Drawing from the belt": with one item it moves it between hand and belt).
const SWAP := &"Swap"
## The host's player asks a scripted mode to go on (#599, the tutorial's stages): a session control
## like ReturnToLobby, no argument. The base mode accepts it in no phase (`not_accepted`).
const NEXT_STAGE := &"NextStage"
## A player sets its own name and body colour (#551, #73), a session control: both are always sent.
## The host cleans the name, gives the first free colour on a clash and tells everyone
## (ProfileChanged). The base mode accepts it in the lobby only, from a player.
const SET_PROFILE := &"SetProfile"
## A living player throws its hand item along `facing` (#37, the throwing ADR's TE4): the host
## takes only the facing; the origin, the speed and the arc are its own (ThrowItem).
const THROW := &"Throw"
## A living player uses the placed station `station` (StationPlaced's id) or the item `item` (a box
## on the ground; the cooking ADR's CE1, #770), sent on E over it (the Generator ADR's GE1, #796).
## Exactly one of the two names something, the other is -1 (the wire's none); both or neither is
## refused `bad_args` (Match._target_problem). A station's kind owns its rule (StationKind.actions,
## tried before the role's and the mode's, never the hand item's; §9.2); an item's kind owns its
## rule alone (ItemKind.target_actions, never the role's or the mode's). An id that names no placed
## station or no item, and a station of a display kind (StationKind.display), is refused
## `nothing_to_do` before any owner is tried. The host checks reach and sight itself (AtStation and
## StationInSight; InReach and InSight).
const INTERACT := &"Interact"
## A living player draws its place `place` (0..2) into the hand (GDD §6 "Drawing from the belt",
## #1218): keys 1, 2 and 3, and the mouse wheel stepping through the three. The host checks the
## place (PlaceInRange, PlaceChanges); a two-handed hand item is put down at the feet first.
const DRAW := &"Draw"
## A living player takes the seated pose where it stands (#1296; GDD §12 "The camera wall": the
## watcher sits in the chair): PlayerState.posed, which every peer sees on the avatar. The mode's
## rule decides where it may (a TakePose rule and its conditions); any own move ends it
## (MovementRule). No argument.
const POSE := &"Pose"

## Every intent a client may send.
const ALL: Array[StringName] = [
	HELLO,
	SET_READY,
	CHANGE_SETTINGS,
	LOAD_ACK,
	MOVE_CLAIM,
	PICK_UP,
	PUT_DOWN,
	USE,
	RETURN_TO_LOBBY,
	RAISE,
	STOP_RAISE,
	GIVE_UP,
	SWAP,
	NEXT_STAGE,
	SET_PROFILE,
	THROW,
	INTERACT,
	DRAW,
	POSE,
]

## The intents that are a player's actions in the world, not the session's controls: the dead send
## none of them, not even the host under HOST (Match._accepts, vision revision 1).
const PLAYER_ACTIONS: Array[StringName] = [
	MOVE_CLAIM,
	PICK_UP,
	PUT_DOWN,
	USE,
	RAISE,
	STOP_RAISE,
	GIVE_UP,
	SWAP,
	THROW,
	INTERACT,
	DRAW,
	POSE
]

## Commands server/ originates from what the transport and the host's physics report; not intents,
## never rejected. No message type carries PeerConnected, PeerLeft or BodyMoved: no peer sends one.
const PEER_CONNECTED := &"PeerConnected"
const PEER_LEFT := &"PeerLeft"
## A report of the host's body of `peer` while it moves (the knockdown rework's KE14), {"epoch",
## "position", "velocity"}: the epoch its LaunchBody named, the capsule's lowest point and its
## velocity. server/ puts one per moving body at the head of each step-4 batch (§4.5.3), so it is
## stamped with the tick it runs; taken in every phase (LifeRules.body_moved), and kept in the
## command log, so a replay rests every body where the match did with no physics.
const BODY_MOVED := &"BodyMoved"
## Forces a role on `peer` for the deals that follow, {"role": id}; an empty id clears it. server/
## originates it in debug builds only (§8, §9.4 DealRoles): from peer 1's debug-kind message only
## (the host's own client: a dev console command, the bots runner's bot 1; §4.3, E17), never from
## another peer's message. The core scenario runner queues it directly.
const FORCE_ROLE := &"ForceRole"
## Forces the length of the match clocks that start from now on, {"seconds": n}, replacing
## StartClock's minutes setting; 0 clears it. Debug builds only, exactly as ForceRole (§8): the bot
## scenarios' `clock_s`, so a scenario that ends by time up need not wait a whole minute (M4-3).
const FORCE_CLOCK := &"ForceClock"

## The fields each intent (and ForceRole and ForceClock) carries in MatchCommand.args, with their
## Variant types (ARCHITECTURE §4.1, §4.3, §4.4): intent -> {field -> Variant.Type}. The rules read
## args only through these names (MatchCommand.field and its typed getters), and a test in tests/
## checks the wire table (net/messages/) against them, so a field renamed on one side fails that
## test instead of reading as missing. A field may be absent (ChangeSettings's `map`); its type is
## the one it has when present. The wire's own fields are not args: `seq` (MatchCommand.seq), the
## presence flags and ForceRole's `peer` (MatchCommand.peer). Once the wire carries them (3d), every
## change here is a protocol change: it updates §4.3 and bumps JoinRules.PROTOCOL_VERSION in the
## same PR.
const FIELDS: Dictionary[StringName, Dictionary] = {
	HELLO: {"version": TYPE_INT, "content": TYPE_INT, "name": TYPE_STRING, "key": TYPE_STRING},
	SET_READY: {"ready": TYPE_BOOL},
	CHANGE_SETTINGS: {"settings": TYPE_DICTIONARY, "map": TYPE_STRING, "lobby_name": TYPE_STRING},
	LOAD_ACK: {"match_id": TYPE_INT},
	MOVE_CLAIM:
	{
		"epoch": TYPE_INT,
		"client_tick": TYPE_INT,
		"position": TYPE_VECTOR3,
		"velocity": TYPE_VECTOR3,
		"facing": TYPE_VECTOR3,
		"sprint": TYPE_BOOL,
		"moving": TYPE_BOOL,
		"on_floor": TYPE_BOOL,
		"crouched": TYPE_BOOL,
		"sneaking": TYPE_BOOL,
		"jumps": TYPE_INT,
		"sprint_ticks": TYPE_INT,
		"moved_ticks": TYPE_INT,
	},
	PICK_UP: {"item": TYPE_INT},
	PUT_DOWN: {"facing": TYPE_VECTOR3},
	USE: {"facing": TYPE_VECTOR3},
	RETURN_TO_LOBBY: {},
	RAISE: {"target": TYPE_INT},
	STOP_RAISE: {},
	GIVE_UP: {},
	SWAP: {},
	NEXT_STAGE: {},
	SET_PROFILE: {"name": TYPE_STRING, "colour": TYPE_INT},
	THROW: {"facing": TYPE_VECTOR3},
	INTERACT: {"station": TYPE_INT, "item": TYPE_INT},
	DRAW: {"place": TYPE_INT},
	POSE: {},
	FORCE_ROLE: {"role": TYPE_STRING},
	FORCE_CLOCK: {"seconds": TYPE_INT},
	BODY_MOVED: {"epoch": TYPE_INT, "position": TYPE_VECTOR3, "velocity": TYPE_VECTOR3},
}
