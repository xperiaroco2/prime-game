extends RefCounted
## Builders shared by the voice rules' suites (ARCHITECTURE §6): FixtureModes.basic() with a given
## voice rule in its lobby and its round, positions, and what a peer heard on the last tick
## (view_of, §5). Built in code: a part's unit test never loads `content/` (§9.6).


## FixtureModes.basic() with `lobby_rule` in the lobby and `round_rule` in the round.
static func mode(lobby_rule: VoiceRule, round_rule: VoiceRule) -> GameMode:
	var made := FixtureModes.basic()
	made.find_phase(&"lobby").voice_rule = lobby_rule
	made.find_phase(&"round").voice_rule = round_rule
	return made


## `peers` joined in the lobby of a match whose lobby and round use `rule`.
static func in_lobby(rule: VoiceRule, peers: Array[int]) -> Match:
	return FixtureModes.started(mode(rule, rule), peers)


## `peers` in the round (placed on round_player markers 1 m apart) of a match whose lobby and
## round use `rule`.
static func in_round(rule: VoiceRule, peers: Array[int]) -> Match:
	return FixtureModes.in_round(mode(rule, rule), peers)


## Sets `peer`'s last accepted position directly (§7.1).
static func put(game: Match, peer: int, at: Vector3) -> void:
	game.state.player(peer).position = at


## Runs one tick and returns the speakers `peer` could hear on it, as recorded for view_of.
static func tick_and_hear(game: Match, peer: int) -> Array:
	FixtureModes.run_ticks(game, 1)
	return heard(game, peer)


## The speakers `peer` could hear on the last tick, as recorded for view_of; empty when none
## were recorded for it.
static func heard(game: Match, peer: int) -> Array:
	var speakers := game.view_of(peer).speakers
	var at := game.ticked_through()
	return Array(speakers[at]) if speakers.has(at) else []
