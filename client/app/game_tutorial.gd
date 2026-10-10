class_name GameTutorial
extends RefCounted
## Game's solo tutorial session (docs/design/tutorial.md §2.1, §5: E62, E69, E70; ARCHITECTURE
## §4.7.43), out of game.gd to keep it under lint's 1000 lines. Game.start_tutorial() hosts the
## tutorial mode the way Game.host() hosts the base mode, through the same HostNode façade, but on
## a LoopbackTransport of a private LoopbackHub: no socket opens and nobody else can join. The own
## ClientSession runs on HostNode.own_client as when hosting; the two StandIns join the same hub.
##
## The mode is the session's: Game.mode is the tutorial's while it runs and the one it had before
## once it ends (end(), from Game._end_session), so a networked session after it uses the base
## mode again. The tutorial's host writes no replay (Game.host_on asks `running`), the game sends
## the own SetReady(true) once welcomed (the tutorial has no Ready key), and Game.hosting() is
## false: Leave and Quit act at once, with no question for other players, and end it as a host's
## Leave does (the reason `closed`: no failure shows).
##
## It starts by itself only on a first launch (first_launch()); the main menu's Tutorial and
## --tutorial start it without the invite. #492 draws the invite while `invite_open` holds.

## The tutorial mode (T2, #600).
const MODE_PATH := "res://content/modes/tutorial_mode.tres"
## The host's port: a key in the private hub only, nothing listens on it ("not a decision").
const PORT := LaunchOptions.DEFAULT_PORT
## The node the stand-ins run under, a child of Game.
const STAND_INS_NAME := "StandIns"

## A tutorial session runs: from start() to end().
var running := false
## It started on a first launch: the invite is due (#492 draws it over the room, Start or Skip).
var invite_open := false
## The hub of the next start; null: a fresh private one. A test seam: a port taken in it makes the
## host refuse to start.
var hub: LoopbackHub

## Game.mode before the tutorial took its place.
var _base_mode: GameMode
var _stand_ins: StandIns


## Whether a launch starts the tutorial by itself, with its invite (E70): no launch option at all,
## the settings read from a file (`path` set) and its flag absent there. A Game with no command
## line (every test, every runner and playcheck window) keeps its settings in memory, and any
## option (the runner's host and join windows) is `given`: neither ever starts it.
static func first_launch(options: LaunchOptions, settings: UserSettings) -> bool:
	return not options.given and not settings.path.is_empty() and not settings.tutorial_seen


## At the end of Game._ready, after its launch options started any session: the main menu's
## Tutorial, then --tutorial, else the first launch's own start.
func setup(game: Game) -> void:
	game.ui.menu.tutorial_requested.connect(func() -> void: game.start_tutorial(false))
	if game.client() != null or not game.options.problem.is_empty():
		return
	if game.options.tutorial:
		game.start_tutorial(false)
	elif first_launch(game.options, game.settings):
		game.start_tutorial(true)


## Starts the tutorial session on `game` (Game.start_tutorial); false while a session runs, or
## when the host could not start (host-failed shows then, as for Game.host()).
func start(game: Game, with_invite: bool) -> bool:
	if game.client() != null or running:
		return false
	_base_mode = game.mode
	game.mode = load(MODE_PATH) as GameMode
	running = true
	invite_open = with_invite
	var schema := WireSchema.game(OS.is_debug_build())
	var session_hub := hub if hub != null else LoopbackHub.new()
	var transport := LoopbackTransport.new(schema.kind_table(), session_hub)
	if not game.host_on(transport, PORT, LaunchOptions.LOCALHOST):
		# The player never saw the invite: a first launch must offer it again.
		invite_open = false
		end(game)
		return false
	game.client().welcomed.connect(_on_welcomed.bind(game))
	_stand_ins = StandIns.new(session_hub, game.mode, PORT, game.clock, schema)
	_stand_ins.name = STAND_INS_NAME
	game.add_child(_stand_ins)
	return true


## The own player is in: its Ready (the tutorial has no Ready key), then the stand-ins join, so
## the host names them after it (Player2, Player3).
func _on_welcomed(_own_peer: int, game: Game) -> void:
	game.set_ready(true)
	if _stand_ins != null:
		_stand_ins.join_host()


## The session ended (Game._end_session, after the host went): the stand-ins go and the mode is
## the one before again. A tutorial that began with the invite counts as seen (the flag written):
## until #492's Start and Skip set it, a first launch must not start it on every launch.
func end(game: Game) -> void:
	if not running:
		return
	if _stand_ins != null:
		game.remove_child(_stand_ins)
		_stand_ins.queue_free()
		_stand_ins = null
	game.mode = _base_mode
	_base_mode = null
	if invite_open:
		mark_seen(game)
	running = false
	invite_open = false


## Sets the tutorial flag in the player's settings and writes them (in memory: nothing written).
func mark_seen(game: Game) -> void:
	game.settings.tutorial_seen = true
	game.settings.write()


## The stand-ins of the running tutorial; 0 without one.
func stand_ins() -> int:
	return _stand_ins.count() if _stand_ins != null else 0
