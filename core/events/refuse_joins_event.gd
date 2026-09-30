class_name RefuseJoinsEvent
extends MatchEvent
## A directive (ARCHITECTURE §3.5, §4.2): entering Loading, server/ starts refusing new
## connections (`NetTransport.set_refuse_new_connections(true)`). Audience: server, no peer.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.SERVER


func event_name() -> StringName:
	return &"RefuseJoins"


func audience() -> Audience:
	return Audience.server()
