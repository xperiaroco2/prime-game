class_name FixtureKillTick
extends TickSystem
## A test tick system for the kill queue (LifeRules.kill_later, settled after each tick system; the
## car repair ADR's RE17, #806): it queues the kill of each of `queues` that is still living, and
## notes the life of `reports` (a peer, 0: none) as "P<peer> <life>" to everyone, so a test sees
## whether a kill queued earlier in the tick has landed by the time this system runs.

@export var queues: Array[int] = []
@export var reports := 0


static func queuing(peers: Array[int]) -> FixtureKillTick:
	var system := FixtureKillTick.new()
	system.queues = peers
	return system


static func reporting(peer: int) -> FixtureKillTick:
	var system := FixtureKillTick.new()
	system.reports = peer
	return system


func run(ctx: MatchContext) -> void:
	for peer: int in queues:
		var victim := ctx.state.player(peer)
		if victim != null and victim.is_alive():
			LifeRules.kill_later(ctx, peer)
	if reports > 0:
		var life: String = PlayerState.Life.keys()[ctx.state.player(reports).life]
		ctx.emit(FixtureNoteEvent.new("P%d %s" % [reports, life]))


func emits() -> Array[Script]:
	return [FixtureNoteEvent, DiedEvent, SelfStatusEvent, ItemPlacedEvent]
