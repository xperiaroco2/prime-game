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

## Every intent a client may send.
const ALL: Array[StringName] = [
	HELLO, SET_READY, CHANGE_SETTINGS, LOAD_ACK, MOVE_CLAIM, PICK_UP, PUT_DOWN, USE, RETURN_TO_LOBBY
]

## Commands server/ originates from what the transport reports; not intents, never rejected.
const PEER_CONNECTED := &"PeerConnected"
const PEER_LEFT := &"PeerLeft"
