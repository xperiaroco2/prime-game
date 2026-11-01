class_name SnapshotEncoder
extends RefCounted
## Builds each viewer's Snapshot payload of one tick (ARCHITECTURE §4.5 "Snapshots", #1234): each
## avatar's record is encoded once per tick through WireSchema, with every check its wire types
## make, and each viewer's payload is the tick, the count and the (peer, record) entries of the
## avatars Match.snapshot_for gave that viewer, in ascending peer order, after the pinball's ball
## when one is on the table (#1399, the same for everyone). Every payload is byte for
## byte what WireSchema.encode gives for the Snapshot of that viewer's avatars: before, the host
## encoded each avatar again for each viewer, O(N^2) encodes a tick.
##
## Filtering stays core/'s (invariant 2): this encodes only the avatars a viewer's snapshot holds,
## and reuses an entry's bytes only for a record equal to the one they were encoded from, typed
## value for typed value (var_to_bytes, a local comparison that never reaches the wire); another
## record is encoded on its own. A payload past the row's cap or most avatars, or an avatar the
## codec refuses, gets WireSchema's refusal: nothing to send, and the error it logged.

const SNAPSHOT := &"Snapshot"
const AVATARS := "avatars"
const BALL := "ball"

## Snapshot's kind, its cap and its most avatars.
var kind := 0
var cap := 0
var max_avatars := 0

var _schema: WireSchema
var _tick := 0
## What WireSchema writes for no avatars under `_tick`, its last byte the map's count; built at the
## tick's first payload, empty when the codec refused the tick.
var _header := PackedByteArray()
var _header_built := false
## This tick's entries by peer: the bytes (its key, then its record) and the record they encode, as
## var_to_bytes gives it.
var _entries: Dictionary[int, PackedByteArray] = {}
var _records: Dictionary[int, PackedByteArray] = {}
## The pinball's ball the header holds (#1399: {"ball": place}, or empty), and its var_to_bytes.
var _ball := {}
var _ball_bytes := PackedByteArray()


func _init(schema: WireSchema) -> void:
	_schema = schema
	var row := schema.row_named(SNAPSHOT)
	kind = row.kind
	cap = row.cap
	max_avatars = row.field_named(AVATARS).max_count


## Starts host tick `tick`: the last tick's entries are forgotten.
func start(tick: int) -> void:
	_tick = tick
	_header_built = false
	_entries.clear()
	_records.clear()


## The Snapshot of `snapshot` (one viewer's Match.snapshot_for: its "avatars", and its "ball" when
## the pinball's ball is on the table) under the started tick: WireSchema.encode's bytes, or empty
## when it refuses them (it logged why). The ball is the same for every viewer (§5), so it sits in
## the header; one that differs from the header's builds the header and the entries again.
func payload(snapshot: Dictionary) -> PackedByteArray:
	var avatars: Dictionary = snapshot.get(AVATARS, {})
	var ball := {}
	if snapshot.has(BALL):
		ball[BALL] = snapshot[BALL]
	var ball_bytes := var_to_bytes(ball)
	if not _header_built or ball_bytes != _ball_bytes:
		_header_built = true
		_ball = ball
		_ball_bytes = ball_bytes
		_entries.clear()
		_records.clear()
		_header = _schema.encode(_message({}))
	if _header.is_empty():
		return PackedByteArray()
	if avatars.size() > max_avatars:
		return _schema.encode(_message(avatars))
	var peers := avatars.keys()
	for peer: Variant in peers:
		if not peer is int or not avatars[peer] is Dictionary:
			return _schema.encode(_message(avatars))
	peers.sort()
	var built := _header.duplicate()
	built[built.size() - 1] = peers.size()
	for peer: int in peers:
		var entry := _entry(peer, avatars[peer] as Dictionary)
		if entry.is_empty():
			return entry
		built.append_array(entry)
	if built.size() > cap:
		return _schema.encode(_message(avatars))
	return built


## The bytes of `record` as the avatars map writes it for `peer`: this tick's, when they encode an
## equal record; else encoded now. Empty when the codec refused it (it logged why).
func _entry(peer: int, record: Dictionary) -> PackedByteArray:
	var compared := var_to_bytes(record)
	if _records.has(peer) and _records[peer] == compared:
		return _entries[peer]
	var one := _schema.encode(_message({peer: record}))
	if one.is_empty():
		return one
	var entry := one.slice(_header.size())
	_entries[peer] = entry
	_records[peer] = compared
	return entry


## The Snapshot of `avatars` under the started tick, with the header's ball: every encode shares
## the header's bytes up to the map's count.
func _message(avatars: Dictionary) -> WireMessage:
	var fields := {"tick": _tick, AVATARS: avatars}
	fields.merge(_ball)
	return WireMessage.new(SNAPSHOT, fields)
