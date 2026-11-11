class_name GameShip
extends RefCounted
## The own ship with no session (#1285; ARCHITECTURE §4.7.66): the game boots straight into the
## aliens' ship, the lobby the player walks around, and every player comes back to it when a
## session ends or they leave it (prime-game-ui's s04 `boot` and s05 `ship`). There is no main menu
## on the way: the suit menu (Esc) hosts, joins and holds Settings.
##
## The ship is the base mode's lobby hosted on a private LoopbackHub, as the tutorial is (#601,
## GameTutorial): no socket opens, nobody else can join, no replay is written, Game.hosting() is
## false (Leave and Quit ask nobody) and the UI shows the ship's place (GameUi.set_ship): the lobby
## HUD's Esc hint alone, the suit menu's Find a lobby, Host and Tutorial. Hosting, joining or the
## tutorial first leave it (go()); when that session ends without a failure to read (or after a
## failure's Back) a new private ship starts again (come_back()).
##
## It runs only for the game a player launched (no launch option, the settings read from a file,
## as GameTutorial.first_launch reads them) or a Game asking with `ship_home`: a Game with no
## command line (every test, runner and playcheck window) keeps the main menu as before.

## The private hub's port: a key in it only, nothing listens on it ("not a decision").
const PORT := LaunchOptions.DEFAULT_PORT

## The private ship session runs.
var running := false
## A session is being swapped in for the ship (go()): its end starts no ship again.
var _swapping := false


## Whether `game` lives in the ship between sessions: the launched game, or a Game asking for it.
static func homes(game: Game) -> bool:
	if game.ship_home:
		return true
	return (
		game.read_command_line
		and game.options != null
		and not game.options.given
		and not game.settings.path.is_empty()
	)


## Starts the private ship on `game`; false while a session runs or when it could not start.
func start(game: Game) -> bool:
	if game.client() != null or running or not homes(game):
		return false
	running = true
	game.ui.set_ship(true)
	# Try again after a failed start starts the ship again, never an older session.
	game.set_retry(func() -> void: start(game))
	var schema := WireSchema.game(OS.is_debug_build())
	var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
	if not game.host_on(transport, PORT, LaunchOptions.LOCALHOST):
		end(game)
		return false
	return true


## The ship's session ended (Game._end_session): the UI leaves the ship's place.
func end(game: Game) -> void:
	if not running:
		return
	running = false
	game.ui.set_ship(false)


## Leaves the ship for `next` (host, join or the tutorial), called once it is gone; at once when
## no ship runs. In the same frame, as the main menu's Host after a Leave: Game._end_session has
## taken the ship's host out of the tree and left its ended client nothing to send, and the new
## SessionNode takes an automatic name beside the old one queued for freeing. When `next` starts
## nothing and shows no failure (a target that does not parse), the ship comes back.
func go(game: Game, next: Callable) -> void:
	if not running:
		next.call()
		return
	_swapping = true
	game.leave()
	_swapping = false
	next.call()
	if game.client() == null and game.failure.is_empty():
		come_back(game)


## A session ended with nothing to read (or a failure's Back): back in a new private ship one
## frame later, outside the ended session's own signal (Game._show_end runs inside it).
func come_back(game: Game) -> void:
	if _swapping or not homes(game):
		return
	_start_later.call_deferred(game.get_instance_id())


## A failure's Join directly in the ship (Game.open_direct, queued after come_back's start): the
## suit menu on Find a lobby's address entry.
func open_direct(game_id: int) -> void:
	var game := instance_from_id(game_id) as Game
	if game == null or not running:
		return
	game.open_esc()
	game.ui.esc.press(EscMenuState.Tab.FIND)
	game.ui.esc.find.show_direct(true)


## By the instance id: a Game freed in between (a test's end) is no call on a freed object.
func _start_later(game_id: int) -> void:
	var game := instance_from_id(game_id) as Game
	if game == null or not game.is_inside_tree() or game.client() != null:
		return
	if game.failure.is_empty() and not game.quitting():
		start(game)
