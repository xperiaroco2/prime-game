class_name AllowJoinsEvent
extends MatchEvent
## A directive (ARCHITECTURE §3.5, §4.2): entering Lobby, server/ accepts new connections again
## (`NetTransport.set_refuse_new_connections(false)`). Audience: server, no peer.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.SERVER


func event_name() -> StringName:
	return &"AllowJoins"


func audience() -> Audience:
	return Audience.server()
