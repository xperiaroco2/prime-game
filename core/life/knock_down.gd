class_name KnockDown
extends RuleEffect
## Knocks down one present living player (ARCHITECTURE §3.4, §9.4.3; #599): a transition action
## of the tutorial's stages (docs/design/tutorial.md §2.3, §2.5). `pick` 0 is the host's player
## (peer 1); n >= 1 is the n-th present player other than peer 1, in peer-id order.
## LifeRules.knock_down downs it where it stands; with `then_die`, LifeRules.die follows at once
## (its body, Died, player_died and the drop at the body, as when a knockdown runs out).
##
## A pick that names nobody present, or a player who is not alive (LifeRules.knock_down's own
## error), is a rule error, recorded during the row (Match.row_error_count; HostSession ends the
## session, §4.5.11), and nothing happens: one error, and `then_die` never kills a player this
## action did not down. Without `then_die` the downed stays downed until a LifeTicks of its phase
## runs the knockdown out; ModeCheck warns on a row into a phase with no LifeTicks, where it stays
## downed for good (the tutorial's `raise_stage` wants exactly that).
##
## Emits: RaiseStopped (everyone), for a channel involving the player (none in a row: Match stops
## every channel first); KnockedDown (everyone); Correction (the downed: its new epoch). With
## `then_die`: Died (everyone), the dropped items' ItemPlaced (death, everyone); raises player_died,
## then item_rested per item. No demands.

## The host's peer id (§4: the host is always peer 1).
const HOST := 1

## 0: the host's player; n: the n-th other present player in peer-id order.
@export var pick := 0
## Dies at once after the knockdown (LifeRules.die).
@export var then_die := false


func run(ctx: MatchContext) -> void:
	var peer := picked(ctx.state)
	if peer < 0:
		ctx.error("KnockDown: pick %d names no present player" % pick)
		return
	var player := ctx.state.player(peer)
	var was_alive := player.is_alive()
	LifeRules.knock_down(ctx, peer)
	if then_die and was_alive and player.life == PlayerState.Life.DOWNED:
		LifeRules.die(ctx, peer)


## The peer `pick` names among the present players of `state`, or -1 for none.
func picked(state: MatchState) -> int:
	var others: Array[int] = []
	for peer: int in state.present_peers():
		if peer != HOST:
			others.append(peer)
	if pick == 0:
		return HOST if state.is_present(HOST) else -1
	if pick < 0 or pick > others.size():
		return -1
	return others[pick - 1]


func emits() -> Array[Script]:
	var found: Array[Script] = [RaiseStoppedEvent, KnockedDownEvent, CorrectionEvent]
	if then_die:
		found.append_array([DiedEvent, ItemPlacedEvent])
	return found


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	# n others exist only with n + 1 players: a pick of max_players or more never names anyone.
	var problem := out_of_bounds("KnockDown pick", pick, 0, maxi(0, mode.max_players - 1))
	if not problem.is_empty():
		found.append(problem)
	return found
