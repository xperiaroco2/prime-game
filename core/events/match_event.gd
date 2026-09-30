class_name MatchEvent
extends RefCounted
## An event core/ emits (ARCHITECTURE §4.2). Each event class declares its one audience
## (audience()), evaluated at emission; neither the data nor an effect chooses recipients. When
## the parts of a fact have different audiences, core/ emits separate events (a hit: a public
## Swung, a private Damaged). A new audience needs a new event class.
##
## Every event class also declares `const AUDIENCE_KIND`, the Audience.Kind its audience() always
## has, so ModeCheck can tell from the class alone whether it goes to everyone (§9.2).


## The name of §4.2's catalogue (`PhaseChanged`).
func event_name() -> StringName:
	return &""


func audience() -> Audience:
	return Audience.server()


## The payload as plain data: what the recipient learns, and what view_of compares.
func to_dict() -> Dictionary:
	return {}


## The event's name and payload as one dictionary, for logs and comparisons.
func describe() -> Dictionary:
	return {"event": event_name(), "fields": to_dict()}
