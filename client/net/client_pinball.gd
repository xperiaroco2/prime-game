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
## The ball on the table as the newest snapshot shows it (#1399): whether one is there, its
## table-local place (Intents.BALL_MOVED on the host) and the host tick of that snapshot. A snapshot
## without a ball takes it away. #1400 draws it, interpolated.
var ball_shown := false
var ball := Vector3.ZERO
var ball_tick := 0


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


## Folds the ball of one snapshot newer than the last folded (ClientModel.fold_snapshot checks the
## tick): its `ball`, or none when the key is absent.
func fold_snapshot(fields: Dictionary) -> void:
	ball_tick = fields["tick"]
	ball_shown = fields.has("ball")
	ball = fields["ball"] if ball_shown else Vector3.ZERO


## Forgets the game and the ball, not the best (ClientModel.clear_match: LoadMatch, entering the
## lobby).
func clear_match() -> void:
	game = 0
	player = -1
	left = false
	right = false
	in_play = false
	score = 0
	balls_left = 0
	ball_shown = false
	ball = Vector3.ZERO
	ball_tick = 0
