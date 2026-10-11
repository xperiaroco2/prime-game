class_name ChaosHonestClaims
extends RefCounted
## The host's answers to the hostile bot's own claims (#693): those without the chaos tag, whose
## ChaosFrames.claim_shape is -1, which bot 4's script sends as any honest bot does. An honest bot
## fails on a Correction outside a placement (ScenarioBot), but bot 4's script adopts none:
## ChaosRun._is_chaos_answer takes each for a chaos claim's, so a refused honest claim of bot 4 went
## unseen (#674: its walk away corrected over WebRTC). So ChaosRun checks the host's answer to each
## of them on the host (any transport): an honest claim is never corrected. A placement's Correction
## (PlacePlayers, a knockdown, a respawn) comes with another call, never with a claim's.

## The hostile's honest claims the movement rule accepted (its claim_tick is the claim's): a claim
## Match drops before the rule looks at it (a phase without claims, a stale epoch) is not counted.
var accepted := 0
## The honest claims the host corrected, and the failure of the first of them.
var corrected := 0
var first := ""


## Bot 4's honest claim: a MoveClaim of `hostile_peer` (0 before it has one) without the tag.
static func is_honest(command: MatchCommand, hostile_peer: int) -> bool:
	return (
		command.kind == Intents.MOVE_CLAIM
		and hostile_peer != 0
		and command.peer == hostile_peer
		and ChaosFrames.claim_shape(command.args) < 0
	)


## Notes the host's answer `slice` to `command`, when it is bot 4's honest claim: a Correction to
## its peer is counted (the first one is kept, naming the run's seed); a claim the movement rule
## accepted (`player`, the host's PlayerState of the peer, holds its client tick) is counted too.
## Any other command is ignored.
func check(
	command: MatchCommand,
	slice: Array[EmittedEvent],
	player: PlayerState,
	hostile_peer: int,
	seed_value: int
) -> void:
	if not is_honest(command, hostile_peer):
		return
	for emitted: EmittedEvent in slice:
		var correction := emitted.event as CorrectionEvent
		if correction != null and correction.peer == command.peer:
			corrected += 1
			if first.is_empty():
				first = (
					(
						"chaos seed %d: the host corrected an honest claim of bot 4 (peer %d, "
						+ "client tick %s, epoch %s, at %s): Correction %s"
					)
					% [
						seed_value,
						command.peer,
						command.args.get("client_tick"),
						command.args.get("epoch"),
						command.args.get("position"),
						correction.to_dict(),
					]
				)
			return
	if player != null and player.claim_tick == command.args.get("client_tick"):
		accepted += 1


## The failures so far: the first correction, with how many followed it (a bot 4 left corrected
## would add one per tick); empty when none.
func failures() -> PackedStringArray:
	if corrected == 0:
		return PackedStringArray()
	return PackedStringArray(["%s (and %d more)" % [first, corrected - 1]])
