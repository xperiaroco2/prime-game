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
## A living player swaps its hand and belt items (M4-5, vision revision 1: Two hands).
const SWAP := &"Swap"

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
]

## The intents that are a player's actions in the world, not the session's controls: the dead send
## none of them, not even the host under HOST (Match._accepts, vision revision 1).
const PLAYER_ACTIONS: Array[StringName] = [
	MOVE_CLAIM, PICK_UP, PUT_DOWN, USE, RAISE, STOP_RAISE, GIVE_UP, SWAP
]

## Commands server/ originates from what the transport reports; not intents, never rejected.
const PEER_CONNECTED := &"PeerConnected"
const PEER_LEFT := &"PeerLeft"
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
	HELLO: {"version": TYPE_INT, "content": TYPE_INT},
	SET_READY: {"ready": TYPE_BOOL},
	CHANGE_SETTINGS: {"settings": TYPE_DICTIONARY, "map": TYPE_STRING},
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
	FORCE_ROLE: {"role": TYPE_STRING},
	FORCE_CLOCK: {"seconds": TYPE_INT},
}
