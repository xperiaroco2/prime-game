class_name ChaosJoining
extends RefCounted
## A chaos peer's transport to the host (ChaosRun), over WebRTC, ENet or the loopback, made
## without joining: join() joins it. The hostile's join waits until the host holds an honest bot's
## PlayerJoined, since its Hello carries that bot's return key (#639); the malformed peer joins at
## once.

var transport: NetTransport
## Its outbox (ChaosFrames.Packet), taken each frame.
var take := Callable()
## Its raw sends.
var send_raw := Callable()
## Whether join() ran.
var joined := false

var _join := Callable()


## A transport of the host's at `port`: over WebRTC with the fault shim's `shim_seed`, else over
## ENet with `over_network`, else on the loopback `hub`. `shim_seed` is called over WebRTC only.
static func make(
	kinds: NetKindTable,
	port: int,
	hub: LoopbackHub,
	over_network: bool,
	webrtc: bool,
	shim_seed: Callable
) -> ChaosJoining:
	var made := ChaosJoining.new()
	if webrtc:
		var rtc := BotWebRtc.new(kinds, port, shim_seed.call() as int)
		rtc.keep_outbox = true
		made._use(rtc, rtc.join.bind(BotWebRtc.CODE, 0), rtc.take_outbox, rtc.send_raw)
	elif over_network:
		var enet := ChaosEnet.new(kinds)
		made._use(
			enet, enet.join.bind(ChaosRun.ENET_ADDRESS, port), enet.take_outbox, enet.send_raw
		)
	else:
		var loopback := ChaosLoopback.new(kinds, hub)
		made._use(
			loopback, loopback.join.bind("loopback", port), loopback.take_outbox, loopback.send_raw
		)
	return made


## Joins once the honest `bot` (its peer in `peers`) is a player in `state`. True when it joined
## now.
func join_after(peers: ScenarioPeers, bot: int, state: MatchState) -> bool:
	if joined or not peers.has_bot(bot) or not state.players.has(peers.peer_of(bot)):
		return false
	join()
	return true


## Joins the host, once.
func join() -> void:
	if joined:
		return
	joined = true
	_join.call()


func _use(made: NetTransport, join_call: Callable, take_call: Callable, raw: Callable) -> void:
	transport = made
	_join = join_call
	take = take_call
	send_raw = raw
