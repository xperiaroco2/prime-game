class_name UseMirror
extends RuleEffect
## The actor's Interact at a place of the lobby's mirror (ARCHITECTURE §7.1.24, §9.4; #1394; GDD §3
## "The mirror"): its own place's Interact gives the place up (Mirror.leave); any other free place's
## takes it, giving up the one it held (Mirror.take). Only in a station kind's rule on Interact,
## after the conditions required_conditions() lists (MirrorFree refuses a place another player
## holds `unavailable`); where it is, MirrorTicks is (check(): MirrorTicks.problems).
##
## Emits: MirrorPlaces (everyone). No demands.


func run(ctx: MatchContext) -> void:
	var station := Stations.target_of(ctx)
	if station == null:
		return
	if Mirror.holder(ctx.state, station.id) == ctx.actor:
		Mirror.leave(ctx, station.id)
	else:
		Mirror.take(ctx, station.id)


## The condition classes a rule holding this effect must hold, not negated (check()): the actor at
## the place and seeing it, and the place free or its own.
static func required_conditions() -> Array[Script]:
	return [AtStation, StationInSight, MirrorFree]


func emits() -> Array[Script]:
	return [MirrorPlacesEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	# One place per player: MirrorPlaces lists at most MAX_PLACES (the wire's cap).
	if mode.max_players > Mirror.MAX_PLACES:
		found.append(
			(
				"the mirror tells at most %d places, the mode takes %d players"
				% [Mirror.MAX_PLACES, mode.max_players]
			)
		)
	var kinds_rules: Array[Rule] = []
	for kind: StationKind in Stations.kinds_in(mode):
		kinds_rules.append_array(kind.actions)
	for rule: Rule in Pinball.rules_holding(mode, self):
		if rule.trigger != Intents.INTERACT or not kinds_rules.has(rule):
			found.append(
				"UseMirror is only for a station kind's rule on Interact, not %s" % rule.trigger
			)
			continue
		for required: Script in required_conditions():
			if not Pinball.holds_condition(rule, required):
				found.append(
					(
						"the mirror's rule uses a place, which requires the condition %s"
						% required.get_global_name()
					)
				)
	found.append_array(MirrorTicks.problems(mode))
	return found
