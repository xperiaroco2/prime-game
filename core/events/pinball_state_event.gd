class_name PinballStateEvent
extends MatchEvent
## The lobby's pinball machine, its whole state (ARCHITECTURE §4.2, §7.1.22; #1398): the game's
## serial (`game`, which the table's reports name), the seated player or -1, the flippers, whether
## a ball is on the table, the score, the balls left, the lobby's best score and its owner's name.
## Sent on every change (Pinball.announce), again to everyone when a player joins or after
## ResetMatch (PinballTicks). Public: the others watch the same game and the display shows the best.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var game := 0
## The seated player's peer, or -1.
var player := -1
var left := false
var right := false
var in_play := false
var score := 0
var balls_left := 0
var best := 0
var best_name := ""


func event_name() -> StringName:
	return &"PinballState"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {
		"game": game,
		"player": player,
		"left": left,
		"right": right,
		"in_play": in_play,
		"score": score,
		"balls_left": balls_left,
		"best": best,
		"best_name": best_name,
	}
