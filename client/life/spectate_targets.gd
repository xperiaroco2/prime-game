class_name SpectateTargets
extends RefCounted
## Whom a dead player watches (ARCHITECTURE §4.7 Spectating; V9, the engineer's answer 6 on PR
## #133), from the own ClientModel only. The first target is a random living player other than
## the own one, drawn with the client's own generator (the purpose `spectate`: seeded from the
## system's entropy in the game, by the test in a test), else a random downed one, else none (0:
## the camera stays above the own body). Next and previous cycle through the living and the downed
## in peer-id order. A target that goes down, dies or leaves is lost: the camera draws a new first
## target. Nothing about the target is ever sent, and the attacker is not known here, so it is
## never preferred.

var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## The players a dead player may watch: every other player of the roster who is living or
## downed, in peer-id order.
static func candidates(model: ClientModel, own: int) -> Array[int]:
	var found: Array[int] = []
	for peer: int in model.roster:
		var life := model.life_of(peer)
		if peer != own and (life == ClientModel.Life.ALIVE or life == ClientModel.Life.DOWNED):
			found.append(peer)
	found.sort()
	return found


## A random living player, else a random downed one, else 0.
func first(model: ClientModel, own: int) -> int:
	var living: Array[int] = []
	var downed: Array[int] = []
	for peer: int in candidates(model, own):
		if model.life_of(peer) == ClientModel.Life.ALIVE:
			living.append(peer)
		else:
			downed.append(peer)
	var pool := living if not living.is_empty() else downed
	if pool.is_empty():
		return 0
	return pool[_rng.randi_range(0, pool.size() - 1)]


## The next (`step` 1) or previous (-1) candidate after `current` in peer-id order, wrapping; 0
## when there is none. From no target, or one no longer a candidate, it starts at the end that
## `step` points from.
static func cycle(model: ClientModel, own: int, current: int, step: int) -> int:
	var found := candidates(model, own)
	if found.is_empty():
		return 0
	var at := found.find(current)
	if at < 0:
		return found[0] if step > 0 else found[found.size() - 1]
	return found[posmod(at + step, found.size())]


## Whether a target watched while `was` is lost now that it is `now`: it went down, died or left.
## A downed target that is revived stays.
static func lost(was: ClientModel.Life, now: ClientModel.Life) -> bool:
	if now == ClientModel.Life.DEAD or now == ClientModel.Life.LEFT:
		return true
	return was == ClientModel.Life.ALIVE and now == ClientModel.Life.DOWNED
