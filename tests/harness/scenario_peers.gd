class_name ScenarioPeers
extends RefCounted
## A runner's map from bot number to peer id (ARCHITECTURE §4.6, §9.7). A scenario names players by
## bot number, and nothing on the wire tells a bot which peer is bot i, so each runner owns its map
## and passes it to the steps (ScenarioPlay, ScenarioBot) and to ScenarioInvariants: the core runner
## keeps 1 and PEER_BASE + i, the one-process bots runner fills it as LoopbackHub hands out ids,
## and over ENet each instance learns it from the files the bots write (`refresh`).

## The core runner's bot i > 1 is peer PEER_BASE + i, so a scenario that confuses bot numbers with
## peer ids fails.
const PEER_BASE := 1000

## Called with this map when a lookup misses, so a map that grows out of band (the ENet runner's
## `peers` file) can be read again; it may add entries with set_peer().
var refresh := Callable()

var _peer_of: Dictionary[int, int] = {}


## The core runner's map for `bots` bots: bot 1 is peer 1, bot i is PEER_BASE + i.
static func core(bots: int) -> ScenarioPeers:
	var made := ScenarioPeers.new()
	for bot in range(1, bots + 1):
		made.set_peer(bot, 1 if bot == 1 else PEER_BASE + bot)
	return made


func set_peer(bot: int, peer: int) -> void:
	_peer_of[bot] = peer


## The peer id of bot `bot`, or 0 when it is not known (yet).
func peer_of(bot: int) -> int:
	if not _peer_of.has(bot) and refresh.is_valid():
		refresh.call(self)
	return _peer_of.get(bot, 0)


## The bot number of peer `peer`, or 0 when no bot has it.
func bot_of(peer: int) -> int:
	for bot: int in _peer_of:
		if _peer_of[bot] == peer:
			return bot
	return 0


func has_bot(bot: int) -> bool:
	return _peer_of.has(bot)


## Bot number -> peer id, a copy.
func to_dict() -> Dictionary[int, int]:
	return _peer_of.duplicate()
