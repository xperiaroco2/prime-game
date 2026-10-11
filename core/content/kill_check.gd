class_name KillCheck
extends RefCounted
## ModeCheck's rule for a task type that can kill (TaskType.kills(): the car's drop; the car
## repair ADR's RE6, #806): a phase that accepts Interact in such a mode lists LifeTicks with a
## Respawn, so a dead player always comes back. Its own file only because mode_check.gd is at
## gdlint's line limit.


## The errors of `spec`, a phase of `mode`: one when the mode has a type that can kill, the phase
## accepts Interact, and it lists no LifeTicks with a Respawn; else none.
static func problems(mode: GameMode, spec: PhaseSpec) -> PackedStringArray:
	var found := PackedStringArray()
	var killers := killing_types(mode)
	if killers.is_empty() or not _accepts(spec, Intents.INTERACT) or respawns(spec):
		return found
	found.append(
		(
			(
				"phase %s accepts Interact, and task type %s can kill (TaskType.kills()),"
				+ " but lists no LifeTicks with a Respawn: the dead would stay dead"
			)
			% [spec.id, ", ".join(killers)]
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
