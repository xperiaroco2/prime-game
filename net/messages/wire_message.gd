class_name WireMessage
extends RefCounted
## One message as the codec sees it (ARCHITECTURE §4.4): the row's name and its payload as plain
## data. An intent's `fields` are the `args` of its MatchCommand and its `seq` the command's seq;
## an event's `fields` equal its to_dict(); a snapshot's are {tick, avatars}; a voice frame's are
## its fields and the opaque Opus bytes. Wire-only fields live outside `fields`: `seq` (every
## RELIABLE intent's), `peer` (ForceRole's player, the command's peer) and the presence flags.

## The row's name (`Hello`, `PhaseChanged`).
var name: StringName
## The row's kind; set by the decoder.
var kind := 0
var seq := 0
## ForceRole's player; 0 for every other row.
var peer := 0
var fields: Dictionary = {}


func _init(
	message_name: StringName = &"",
	message_fields: Dictionary = {},
	message_seq := 0,
	message_peer := 0
) -> void:
	name = message_name
	fields = message_fields
	seq = message_seq
	peer = message_peer
