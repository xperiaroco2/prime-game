class_name BoothTicks
extends TickSystem
## The photo booth's clock (#1396; ARCHITECTURE §3.3, §9.4.5, §9.5.28): every tick of a phase that
## lists it, the running booth session advances (BoothSessions.advance): it stops when its presser
## left the match, a flash due at this tick records the booth's frame, and the strips print right
## after the last flash. A phase without it refuses StartBooth (`unavailable`), and BoothCheck
## requires StopBooth on every row from a phase that lists it to one that does not, so no session
## outlives its clock.
##
## Emits: BoothStep (FLASH, PRINTED, STOPPED); for the print, what GiveItem.give_new emits
## (ItemVanished, ItemSpawned, ItemPlaced, ItemPickedUp); all to everyone. No demands.


func run(ctx: MatchContext) -> void:
	BoothSessions.advance(ctx)


func emits() -> Array[Script]:
	return [BoothStepEvent, ItemVanishedEvent, ItemSpawnedEvent, ItemPlacedEvent, ItemPickedUpEvent]


## Whether `spec` lists a BoothTicks.
static func listed_in(spec: PhaseSpec) -> bool:
	if spec == null:
		return false
	for system: TickSystem in spec.tick_systems:
		if system is BoothTicks:
			return true
	return false
