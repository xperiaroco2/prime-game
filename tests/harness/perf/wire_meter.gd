class_name WireMeter
extends RefCounted
## What the host's transport carried, per remote peer and host tick, for `tools\run.cmd perf`
## (ARCHITECTURE §9.7, #187): a harness-side meter that MeteredLoopback and MeteredEnet feed from
## their send(), and PerfRun from the host transport's packet_received. It reads no core/ state and
## changes nothing it counts. Peer 1, the host's own client, is left out: its messages never reach
## a network.
##
## Down (host to client): frame bytes (payload plus NetFrame's header) of every message sent, of the
## VoiceDown messages alone, and each Snapshot's payload bytes (its row's cap is a payload cap). Up
## (client to host): the payload bytes of every message that is not voice, and the voice frames,
## the units of the host's per-peer budgets (PeerBudget, E7).

## The host tick the next messages count for: the runner sets it before each host step.
var tick := 0
## Peer -> {tick: frame bytes sent to it}.
var down: Dictionary[int, Dictionary] = {}
## Peer -> {tick: frame bytes of the VoiceDown messages sent to it}.
var down_voice: Dictionary[int, Dictionary] = {}
## Peer -> {tick: payload bytes of the Snapshot sent to it}.
var snapshots: Dictionary[int, Dictionary] = {}
## Peer -> {tick: payload bytes it sent that are not voice}.
var up: Dictionary[int, Dictionary] = {}
## Peer -> {tick: voice frames it sent}.
var up_voice: Dictionary[int, Dictionary] = {}

var _snapshot_kind := 0
var _voice_down_kind := 0
var _voice_up_kind := 0


func _init(schema: WireSchema) -> void:
	_snapshot_kind = schema.kind_of(&"Snapshot")
	_voice_down_kind = schema.kind_of(&"VoiceDown")
	_voice_up_kind = schema.kind_of(&"VoiceUp")


## The host sent `payload` of `kind` to `peer`.
func sent(peer: int, kind: int, payload: PackedByteArray) -> void:
	if peer == NetTransport.HOST_ID:
		return
	var frame := payload.size() + NetFrame.HEADER_BYTES
	_add(down, peer, frame)
	if kind == _voice_down_kind:
		_add(down_voice, peer, frame)
	elif kind == _snapshot_kind:
		_add(snapshots, peer, payload.size())


## The host's transport delivered `payload` of `kind` from `peer`.
func received(peer: int, kind: int, payload: PackedByteArray) -> void:
	if peer == NetTransport.HOST_ID:
		return
	if kind == _voice_up_kind:
		_add(up_voice, peer, 1)
	else:
		_add(up, peer, payload.size())


## Every table, for the run's JSON file (keys become strings there).
func to_dict() -> Dictionary:
	return {
		"down": down,
		"down_voice": down_voice,
		"snapshots": snapshots,
		"up": up,
		"up_voice_frames": up_voice,
	}


func _add(table: Dictionary[int, Dictionary], peer: int, amount: int) -> void:
	var row: Dictionary = table.get(peer, {})
	var had: int = row.get(tick, 0)
	row[tick] = had + amount
	table[peer] = row
