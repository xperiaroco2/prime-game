class_name ChaosHonestClaims
extends RefCounted
## The host's answers to the hostile bot's own claims (#693): those without the chaos tag, whose
## ChaosFrames.claim_shape is -1, which bot 4's script sends as any honest bot does. An honest bot
## fails on a Correction outside a placement (ScenarioBot), but bot 4's script adopts none:
## ChaosRun._is_chaos_answer takes each for a chaos claim's, so a refused honest claim of bot 4 went
## unseen (#674: its walk away corrected over WebRTC). So ChaosRun checks the host's answer to each
## of them on the host (any transport): an honest claim is never corrected. A placement's Correction
## (PlacePlayers, a knockdown, a respawn) comes with another call, never with a claim's.

## The hostile's honest claims that reached the host, each answer checked.
var count := 0


## Bot 4's honest claim: a MoveClaim of `hostile_peer` (0 before it has one) without the tag.
static func is_honest(command: MatchCommand, hostile_peer: int) -> bool:
	return (
		command.kind == Intents.MOVE_CLAIM
		and hostile_peer != 0
		and command.peer == hostile_peer
		and ChaosFrames.claim_shape(command.args) < 0
	)


## For bot 4's honest claim (counted), the failure when the host's answer `slice` corrects it,
## naming the run's seed; else "" (also for any other command, not counted).
func check(
	command: MatchCommand, slice: Array[EmittedEvent], hostile_peer: int, seed_value: int
) -> String:
	if not is_honest(command, hostile_peer):
		return ""
	count += 1
	for emitted: EmittedEvent in slice:
		var correction := emitted.event as CorrectionEvent
		if correction != null and correction.peer == command.peer:
			return (
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
	return ""
