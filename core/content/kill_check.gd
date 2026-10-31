class_name KillCheck
extends RefCounted
## ModeCheck's rules for a task type that can kill or knock down, so a player always comes back
## (§9.3). A type that can kill (TaskType.kills(): the car's drop; the car repair ADR's RE6, #806):
## a phase that accepts Interact in such a mode lists LifeTicks with a Respawn. A type whose tick
## can knock down (TaskType.knocks_down(): the ship engine's blast, #1453): a phase that lists
## TaskTicks in such a mode lists LifeTicks with a Respawn, since the downed bleed out into death.
## Its own file only because mode_check.gd is at gdlint's line limit.


## The errors of `spec`, a phase of `mode`: one per rule above it breaks; else none.
static func problems(mode: GameMode, spec: PhaseSpec) -> PackedStringArray:
	var found := PackedStringArray()
	if respawns(spec):
		return found
	var killers := killing_types(mode)
	if not killers.is_empty() and _accepts(spec, Intents.INTERACT):
		found.append(
			(
				(
					"phase %s accepts Interact, and task type %s can kill (TaskType.kills()),"
					+ " but lists no LifeTicks with a Respawn: the dead would stay dead"
				)
				% [spec.id, ", ".join(killers)]
			)
		)
	var knockers := knocking_types(mode)
	if not knockers.is_empty() and _lists_task_ticks(spec):
		found.append(
			(
				(
					"phase %s lists TaskTicks, and task type %s can knock down"
					+ " (TaskType.knocks_down()), but lists no LifeTicks with a Respawn: the downed"
					+ " would stay downed or dead"
				)
				% [spec.id, ", ".join(knockers)]
			)
		)
	return found


## The ids of the mode's task types that can kill (TaskType.kills()), in the mode's order.
static func killing_types(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	for type: TaskType in mode.task_types:
		if type != null and type.kills():
			found.append(type.id)
	return found


## The ids of the mode's task types whose tick can knock down (TaskType.knocks_down()), in the
## mode's order.
static func knocking_types(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	for type: TaskType in mode.task_types:
		if type != null and type.knocks_down():
			found.append(type.id)
	return found


## Whether `spec` lists a LifeTicks that holds a Respawn: its dead come back.
static func respawns(spec: PhaseSpec) -> bool:
	for system: TickSystem in spec.tick_systems:
		if system is LifeTicks and (system as LifeTicks).respawn != null:
			return true
	return false


## Whether `spec` accepts `intent` from anyone.
static func _accepts(spec: PhaseSpec, intent: StringName) -> bool:
	for entry: AcceptSpec in spec.accepts:
		if entry != null and entry.intent == intent:
			return true
	return false


## Whether `spec` lists TaskTicks.
static func _lists_task_ticks(spec: PhaseSpec) -> bool:
	for system: TickSystem in spec.tick_systems:
		if system is TaskTicks:
			return true
	return false
