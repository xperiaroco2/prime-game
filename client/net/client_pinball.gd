class_name ClientPinball
extends RefCounted
## The lobby's pinball as the own client knows it (#1398; ARCHITECTURE §9.5.28), folded from its
## public PinballState alone: ClientModel.fold hands it every event and it keeps the machine's. The
## game (who sits, the flippers, the ball, the score, the balls left) is a match fact that
## clear_match forgets; the best score and its owner's name are the lobby's, kept until the client
## leaves it (the host keeps them in MatchState.session_part_state and tells them again after
## ResetMatch). Nothing is predicted: a view (#1400) draws these.

## The game's serial, which the table's reports name; 0 before the first game.
var game := 0
## The seated player's peer, or -1 when the seat is free.
var player := -1
var left := false
var right := false
var in_play := false
var score := 0
var balls_left := 0
## The lobby's best score and its owner's name ("" while nobody has played).
var best := 0
var best_name := ""


## Folds one decoded event; any but PinballState changes nothing.
func fold(event_name: StringName, fields: Dictionary) -> void:
	if event_name != &"PinballState":
		return
	game = fields["game"]
	player = fields["player"]
	left = fields["left"]
	right = fields["right"]
	in_play = fields["in_play"]
	score = fields["score"]
	balls_left = fields["balls_left"]
	best = fields["best"]
	best_name = fields["best_name"]


## Forgets the game, not the best (ClientModel.clear_match: LoadMatch, entering the lobby).
func clear_match() -> void:
	game = 0
	player = -1
	left = false
	right = false
	in_play = false
	score = 0
	balls_left = 0
