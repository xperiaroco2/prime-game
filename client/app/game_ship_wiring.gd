class_name GameShipWiring
extends RefCounted
## The ship's suit menu wired to Game (#1285; ARCHITECTURE §4.7.66), out of game.gd to keep it
## under lint's 1000 lines: Find a lobby's Join (by the code, or directly at an address), its Host
## directly, the panel's Host (with a code) and Tutorial each leave the own ship first
## (GameShip.go) and then start their session; at the end of Game._ready, with no session
## started by the launch options or the first launch's tutorial, the game boots into the ship.


static func setup(game: Game) -> void:
	var find := game.ui.esc.find
	find.set_default_port(game.options.port)
	find.code_join_requested.connect(
		func(code: String) -> void: game.ship.go(game, game.join_code.bind(code))
	)
	find.direct_join_requested.connect(
		func(address: String, port: int) -> void: game.ship.go(game, game.join.bind(address, port))
	)
	find.direct_host_requested.connect(
		func(port: int) -> void: game.ship.go(game, func() -> void: game.host(port))
	)
	game.ui.esc.host_requested.connect(
		func() -> void: game.ship.go(game, func() -> void: game.host_with_code(game.options.port))
	)
	game.ui.esc.tutorial_requested.connect(
		func() -> void: game.ship.go(game, func() -> void: game.start_tutorial(false))
	)
	if game.client() == null and game.options.problem.is_empty():
		game.ship.start(game)
