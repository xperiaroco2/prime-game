class_name ChaosZones
extends RefCounted
## What ChaosRun reads of the match's zones (the zone task, #647; ChaosScenario.ZONE stations):
## whether a point is near one, whether a living player other than one stands in one, and the
## ticks the match's one zone counted. Pure reads of a MatchState; split out of ChaosRun when
## main's and release/m7's checks together took it past gdlint's 1000 lines (#837).


## Whether `at` is within a zone's radius plus 1 m, horizontally.
static func near(state: MatchState, at: Vector3) -> bool:
	for id: int in state.stations:
		var station := state.stations[id]
		if station.kind == null or station.kind.id != ChaosScenario.ZONE:
			continue
		var apart := Vector2(at.x - station.position.x, at.z - station.position.z)
		if apart.length() <= station.kind.radius_m + 1.0:
			return true
	return false


## Whether a living player but `skip` stands in a zone: bot 2 may carry its package across one.
static func other_inside(state: MatchState, skip: int) -> bool:
	for id: int in state.stations:
		var station := state.stations[id]
		if station.kind == null or station.kind.id != ChaosScenario.ZONE:
			continue
		for peer: int in state.peers():
			var player := state.player(peer)
			if peer != skip and player != null and player.is_alive():
				if station.contains(player.position):
					return true
	return false


## The ticks the match's one zone counted so far (0 before the deal).
static func ticks(state: MatchState) -> int:
	for id: int in state.tasks:
		var task := state.tasks[id]
		if task.type is ZoneTask:
			var zone_state := task.state as ZoneTask.State
			return zone_state.ticks[0] if zone_state.ticks.size() > 0 else 0
	return 0
