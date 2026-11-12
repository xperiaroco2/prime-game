class_name GameDiscovery
extends RefCounted
## The lobbies nearby in the game (#1316; ARCHITECTURE §4.9), out of game.gd: the host of a shared
## session answers the finders on the local network (LobbyResponder) while its lobby takes
## joiners, and the suit menu's Find a lobby lists what LobbyFinder hears while the page is open
## (FindPage.show_lobbies). It runs only for the launched game that lives in the ship (`enabled`,
## Game._ready: GameShip.homes with the command line read) or a test that sets `enabled` itself:
## a Game with no command line (every other test, runner and playcheck window) opens no
## discovery socket, a ship_home test Game included.
##
## What an answer says is the own host's lobby as its own ClientModel holds it: the lobby's name,
## the host's name, the players and the mode's most, and how to join it: the room's code for a
## code host (none yet: no answer), else the port it hosts on. Nothing private: what the lobby
## shows anyway.

## Whether this game answers and finds at all.
var enabled := false
var responder := LobbyResponder.new()
var finder := LobbyFinder.new()

## The port the responder could not bind while this hosting lasts: tried once, not every frame.
var _refused := false


## Every frame (Game._process): the answers while hosting a lobby, the list while Find is open.
func process(game: Game) -> void:
	var hosting := enabled and game.hosting()
	if not hosting:
		responder.stop()
		_refused = false
	elif not responder.running() and not _refused:
		_refused = not responder.start()
	responder.poll(describe.bind(game))
	var find := game.ui.esc.find
	var finding := enabled and find.is_visible_in_tree()
	if finding and not finder.running():
		finder.start()
	elif not finding and finder.running():
		finder.stop()
		# Its rows go with it: opened again, the page starts from what is heard then.
		find.show_lobbies([] as Array[LobbyFinder.Found])
	if finder.running():
		finder.poll()
		find.show_lobbies(finder.lobbies())


## Closes both sockets (the game leaves the tree).
func close() -> void:
	responder.stop()
	finder.stop()


## The own lobby's answer now, or null while it takes no joiner (no session, not the lobby screen,
## a code host whose room has no code yet), or when no finder nearby could join it: a session
## bound to this machine alone, or a code room on this process's own LAN service (--signal=lan:
## a joiner's Join by code asks its own service, which never heard of it). The query and host
## numbers are the responder's.
static func describe(game: Game) -> LobbyBeacon.Answer:
	var client := game.client()
	if client == null or not client.is_welcomed() or game.screen() != GameFlow.Screen.LOBBY:
		return null
	var model := client.model
	var answer := LobbyBeacon.Answer.new()
	answer.protocol = WireSchema.VERSION
	answer.players = model.roster.size()
	answer.most = game.mode.max_players
	answer.lobby_name = model.lobby_name
	answer.host_name = model.host_name()
	if game.hosted_bind == LaunchOptions.LOCALHOST:
		return null
	var room := game.room()
	if room != null:
		if room.lan != null:
			return null
		answer.code = room.code()
		if not LobbyBeacon.is_code(answer.code):
			return null
	else:
		answer.port = game.hosted_port
	return answer
