class_name WireMeter
extends RefCounted
## What the host's transport carried, per remote peer and host tick, for `tools\run.cmd perf`
## (ARCHITECTURE §9.7, #187): a harness-side meter that MeteredLoopback and MeteredEnet feed from
## their send(), and PerfRun from the host transport's packet_received. It reads no core/ state and
## changes nothing it counts. Peer 1, the host's own client, is left out: its messages never reach
## a network.
##
## Down (host to client): frame bytes (payload plus NetFrame's header) of every message sent, of the
## VoiceBatch messages alone, and each Snapshot's payload bytes (its row's cap is a payload cap). Up
## (client to host): the payload bytes of every message that is not voice, and the voice frames,
## the units of the host's per-peer budgets (PeerBudget, E7).
##
## sent() and received() run inside the host step PerfRun times, so they only append four ints to
## a flat buffer; flush() folds the buffer into the tables after the timed window (to_dict() flushes
## too), and the host-step figure carries no Dictionary work of the meter's.

enum Table { DOWN, DOWN_VOICE, SNAPSHOTS, UP, UP_VOICE }

## Ints per buffered record: table, peer, tick, amount.
const RECORD := 4

## The host tick the next messages count for: the runner sets it before each host step.
var tick := 0
## Peer -> {tick: frame bytes sent to it}.
var down: Dictionary[int, Dictionary] = {}
## Peer -> {tick: frame bytes of the VoiceBatch messages sent to it}.
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
## Records not yet folded into the tables, RECORD ints each.
var _pending := PackedInt64Array()


func _init(schema: WireSchema) -> void:
	_snapshot_kind = schema.kind_of(&"Snapshot")
	_voice_down_kind = schema.kind_of(&"VoiceBatch")
	_voice_up_kind = schema.kind_of(&"VoiceUp")


## The host sent `payload` of `kind` to `peer`.
func sent(peer: int, kind: int, payload: PackedByteArray) -> void:
	if peer == NetTransport.HOST_ID:
		return
	var frame := payload.size() + NetFrame.HEADER_BYTES
	_record(Table.DOWN, peer, frame)
	if kind == _voice_down_kind:
		_record(Table.DOWN_VOICE, peer, frame)
	elif kind == _snapshot_kind:
		_record(Table.SNAPSHOTS, peer, payload.size())


## The host's transport delivered `payload` of `kind` from `peer`.
func received(peer: int, kind: int, payload: PackedByteArray) -> void:
	if peer == NetTransport.HOST_ID:
		return
	if kind == _voice_up_kind:
		_record(Table.UP_VOICE, peer, 1)
	else:
		_record(Table.UP, peer, payload.size())


## Folds the buffered records into the tables; PerfRun calls it after each timed host step.
func flush() -> void:
	var tables: Array[Dictionary] = [down, down_voice, snapshots, up, up_voice]
	for at in range(0, _pending.size(), RECORD):
		var table: Dictionary = tables[_pending[at]]
		var peer := _pending[at + 1]
		var row: Dictionary = table.get(peer, {})
		var had: int = row.get(_pending[at + 2], 0)
		row[_pending[at + 2]] = had + _pending[at + 3]
		table[peer] = row
	_pending.clear()


## Every table, for the run's JSON file (keys become strings there).
func to_dict() -> Dictionary:
	flush()
	return {
		"down": down,
		"down_voice": down_voice,
		"snapshots": snapshots,
		"up": up,
		"up_voice_frames": up_voice,
	}


func _record(table: Table, peer: int, amount: int) -> void:
	_pending.append(table)
	_pending.append(peer)
	_pending.append(tick)
	_pending.append(amount)
