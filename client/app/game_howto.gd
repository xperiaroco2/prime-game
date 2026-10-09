class_name GameHowto
extends RefCounted
## Game's how-to card wiring (#254), out of game.gd to keep it under lint's 1000 lines: the
## player's progress (Game.howto), the Esc menu's Guide tab, the loading screen's card and the
## round's finished tasks. Each call reads the Game's state then, so a Game.howto a test sets after
## _ready is the one used.


## At Game's _ready: its progress, the player's file under user://
## (HowtoProgress.for_this_player()) or in memory with `read_command_line` off, unless a test set
## one; the Guide tab's mode; and the loading screen's card at each loading.
static func setup(game: Game) -> void:
	if game.howto == null:
		var own := game.read_command_line
		game.howto = HowtoProgress.for_this_player() if own else HowtoProgress.new()
	game.ui.esc.guide.set_mode(game.mode)
	game.ui.loading_started.connect(func() -> void: loading_started(game))


## The map loading started: the how-to card of a task type this round may deal that the player has
## not completed, shown at most HowtoProgress.LOADING_SHOWS times (#254), instead of the tip.
static func loading_started(game: Game) -> void:
	var client := game.client()
	var model := client.model if client != null else null
	var types := HowtoCards.with_card(HowtoCards.dealable(game.mode, model))
	var type := game.howto.loading_pick(types)
	if not type.is_empty() and game.ui.show_loading_card(type):
		game.howto.note_loading_shown(type)


## Each frame of a session on screen `now`: in the Round, and at its End (the round's last task
## can finish in the frame the match ends), the tasks finished complete their types
## (HowtoProgress.follow).
static func follow(game: Game, now: GameFlow.Screen) -> void:
	if now == GameFlow.Screen.ROUND or now == GameFlow.Screen.END:
		game.howto.follow(game.client().model)
