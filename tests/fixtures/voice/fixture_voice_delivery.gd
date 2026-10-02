class_name FixtureVoiceDelivery
extends RefCounted
## One relayed voice frame on its way to a listener, for the VoiceJitter suites: its stream seq
## (unbounded here, sent as u16), the host tick it was relayed at, its bytes and when it arrives.

var seq: int
var tick: int
var frame: PackedByteArray
var arrival: int


func _init(s: int, t: int, f: PackedByteArray, a: int) -> void:
	seq = s
	tick = t
	frame = f
	arrival = a
