class_name GameJoin
extends RefCounted
## Game's join under way, out of game.gd to keep it under lint's 1000 lines (#1249): what this
## client joined and the transport it joins with (Game.join_target sets them, Game._end_session
## reads and drops them), the connecting screen's step, time since Join and the room's code
## (refresh), the code or address a join keeps (remember) and the menu's fields of a command line's
## join (fill_menu).

## What this client joined; null for a host or no session.
var target: JoinTarget
## The transport it joins with; null for a host or no session.
var transport: NetTransport
## When the join started (Time.get_ticks_msec), for the connecting screen's time since Join.
var started_ms := 0
## This game's content hash, for the version check against `found`.
var own_content := 0


## Each frame of a session: the connecting screen's step and the time since Join. Then the room's
## code to whoever knows it: the host from its room (waiting for the service, then the code, or a
## line saying none is coming), a code joiner the code it typed, a Direct joiner none. Once
## welcomed, the title names the lobby (#214: the host's answer carries its name).
func refresh(game: Game) -> void:
	var client := game.client()
	var room := game.room()
	var webrtc := transport as WebRtcTransport
	if client.is_welcomed():
		game.ui.connecting.set_lobby(client.model.lobby_name, client.model.host_name())
	if target != null and not client.is_welcomed():
		var found := webrtc.found_protocol if webrtc != null else -1
		var connected := transport.own_id() != 0
		game.ui.connecting.set_step(JoinProgress.step(target.is_code(), found, connected))
		game.ui.connecting.set_elapsed(floori((Time.get_ticks_msec() - started_ms) / 1000.0))
	var code := ""
	if room != null:
		code = room.code()
	elif target != null and target.is_code():
		code = target.code
	var line := JoinProgress.code_text(code, room != null and room.gone(), room != null)
	game.ui.lobby_hud.show_code(code, room != null and room.gone(), room != null)
	game.ui.esc.lobby.show_code(line, code)


## Keeps the code or the address a join used as the settings' last one (#640): the menu's fields
## start with it. The address is as the Direct field shows it: the port only when not the default.
static func remember(game: Game, joined: JoinTarget) -> void:
	var settings := game.settings
	if joined.is_code():
		settings.last_code = joined.code
	else:
		settings.last_address = (
			joined.address if joined.port == game.ui.menu.default_port else joined.label()
		)
	settings.write()


## The menu's panel and field of a join from the command line, so Back finds them there as if
## typed: the code, or the address with its port when not the default. One that does not parse
## (`typed`, as given) waits in the Direct field with its Join off, so the player sees what the
## command line named (#493 review: the menu has no reason line).
static func fill_menu(game: Game, joined: JoinTarget, typed := "") -> void:
	var menu := game.ui.menu
	if joined.is_code():
		menu.code_edit.text = joined.code
		menu.open_panel(MainMenu.Open.CODE, false)
	else:
		if joined.problem.is_empty():
			typed = joined.label() if joined.port != menu.default_port else joined.address
		menu.address_edit.text = typed.strip_edges()
		menu.open_panel(MainMenu.Open.DIRECT, false)
