class_name PinballSounds
extends RefCounted
## When the lobby's pinball sounds (#1674; GDD §3 "The pinball"; ARCHITECTURE §4.7.63): SfxSet's
## pinball ids from the own ClientPinball alone (its public PinballState), never core/ state.
## PinballViews asks due() each physics frame and hands each cue to WorldSounds as a
## SoundChooser.CUE at the table, so it is cut at the hearing range and muffled like any world
## sound: the dead's machine is heard by the dead around it only.
## - a flipper raised (`left` or `right` up): PINBALL_FLIPPER;
## - a ball launched (`in_play` up): PINBALL_LAUNCH; a ball off the table (`in_play` down):
##   PINBALL_DRAIN;
## - points scored (`score` up: a bumper, a kicker or a target): PINBALL_BUMPER, once a frame;
## - a new best (`best` up, at the game's end): PINBALL_BEST.
## Edges only, within one game (its serial): the first state seen, a new game and the state told
## again after a join or ResetMatch play nothing; clear() forgets it (LoadMatch).

var _seeded := false
var _game := 0
var _left := false
var _right := false
var _in_play := false
var _score := 0
var _best := 0


## The cues due now, each a SoundChooser.CUE's fields, for `pinball` at the table's place `at`.
func due(pinball: ClientPinball, at: Vector3) -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	if _seeded and pinball.game_serial() == _game:
		if (pinball.left and not _left) or (pinball.right and not _right):
			cues.append(_cue(SfxSet.PINBALL_FLIPPER, at))
		if pinball.in_play and not _in_play:
			cues.append(_cue(SfxSet.PINBALL_LAUNCH, at))
		elif _in_play and not pinball.in_play:
			cues.append(_cue(SfxSet.PINBALL_DRAIN, at))
		if pinball.score > _score:
			cues.append(_cue(SfxSet.PINBALL_BUMPER, at))
	if _seeded and pinball.best > _best:
		cues.append(_cue(SfxSet.PINBALL_BEST, at))
	_seeded = true
	_game = pinball.game_serial()
	_left = pinball.left
	_right = pinball.right
	_in_play = pinball.in_play
	_score = pinball.score
	_best = pinball.best
	return cues


## Forgets the state seen: the next due() only seeds.
func clear() -> void:
	_seeded = false


static func _cue(id: StringName, at: Vector3) -> Dictionary:
	return {"id": id, "position": at}
