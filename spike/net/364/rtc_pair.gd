extends SceneTree
## M6-1 spike (#364), throwaway: two processes, one WebRTCPeerConnection each, the three negotiated
## channels of the M6 ADR §2.2 (RELIABLE id 1, LATEST id 2 and VOICE id 3, both unordered with no
## resend). Signalling is a TCP socket on 127.0.0.1; host candidates are rewritten to 127.0.0.1.
##   tools/run.sh run spike/net/364/rtc_pair.gd --headless --instances 2 -- --port=<p> --mode=<m>
## PRIME_INSTANCE 1 is the sender ("host", the offerer), 2 the receiver. Modes:
## - overhead: sizes x channels, 20 ms apart, with time marks for the lo sniffer (sniff.py).
## - sendtime: 81 sends of 58 B on VOICE per 20 ms for 10 s; the 81 put_packet calls timed.
## - freeze: voice (--voice=N streams), LATEST 200 B per 50 ms, RELIABLE beat per 100 ms; the
##   receiver freezes 5.2 s, then the sender does; counts, losses and every state change.
## - hang: as freeze, but the receiver's main thread hangs --hang=S seconds.
## - stop: the sender SIGSTOPs the receiver's whole process for --stop=S seconds (all threads,
##   so ICE consent and SCTP heartbeats stop), then SIGCONTs it. --mp=1 wraps both connections in
##   WebRTCMultiplayerPeer (its own channels) to see whether it drops the peer on DISCONNECTED.

const CH_RELIABLE := 1
const CH_LATEST := 2
const CH_VOICE := 3
const SIZES: Array[int] = [1, 58, 100, 500, 1000, 1031]

var role: int = 0
var mode: String = ""
var port: int = 0
var opts: Dictionary[String, String] = {}
var server: TCPServer
var tcp: StreamPeerTCP
var pc: WebRTCPeerConnection
var mp: WebRTCMultiplayerPeer
var chans: Dictionary[int, WebRTCDataChannel] = {}
var t0: int = 0
var last_pc_state: int = -1
var last_ch_state: Dictionary[int, int] = {}
var opened_at: int = -1
var peer_pid: int = 0
var done: bool = false
var step_after: Array[int] = []
var step_do: Array[Callable] = []
var step_i: int = 0
var step_at: int = 0
## Traffic generator (sender) and counters (receiver).
var traffic: bool = false
var voice_streams: int = 0
var next_voice: int = 0
var next_latest: int = 0
var next_beat: int = 0
var seq: Dictionary[int, int] = {CH_RELIABLE: 0, CH_LATEST: 0, CH_VOICE: 0}
var got: Dictionary[int, int] = {CH_RELIABLE: 0, CH_LATEST: 0, CH_VOICE: 0}
var max_seq: Dictionary[int, int] = {CH_RELIABLE: -1, CH_LATEST: -1, CH_VOICE: -1}
var beat_order_ok: bool = true
var last_poll_us: int = 0


func _init() -> void:
	role = int(OS.get_environment("PRIME_INSTANCE"))
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1]
	port = _opt_i("port", "0")
	mode = _opt("mode", "overhead")
	voice_streams = _opt_i("voice", "81")
	Engine.max_fps = 1000
	t0 = Time.get_ticks_msec()
	if role == 1:
		server = TCPServer.new()
		server.listen(port, "127.0.0.1")
	else:
		tcp = StreamPeerTCP.new()
		tcp.connect_to_host("127.0.0.1", port)
	_make_connection()


func _opt(k: String, d: String) -> String:
	return opts[k] if opts.has(k) else d


func _opt_i(k: String, d: String) -> int:
	return int(_opt(k, d))


func _ms() -> int:
	return Time.get_ticks_msec() - t0


func log_line(s: String) -> void:
	print("SPIKE r%d %7d %.6f %s" % [role, _ms(), Time.get_unix_time_from_system(), s])


func _make_connection() -> void:
	pc = WebRTCPeerConnection.new()
	pc.initialize({})
	pc.session_description_created.connect(_on_sdp)
	pc.ice_candidate_created.connect(_on_cand)
	if _opt("mp", "0") == "1":
		mp = WebRTCMultiplayerPeer.new()
		if role == 1:
			mp.create_server()
		else:
			mp.create_client(2)
		mp.peer_connected.connect(func(id: int) -> void: log_line("mp peer_connected %d" % id))
		mp.peer_disconnected.connect(
			func(id: int) -> void: log_line("mp peer_disconnected %d" % id)
		)
		mp.add_peer(pc, 2 if role == 1 else 1)
	else:
		chans[CH_RELIABLE] = pc.create_data_channel(
			"reliable", {"negotiated": true, "id": CH_RELIABLE}
		)
		chans[CH_LATEST] = pc.create_data_channel(
			"latest", {"negotiated": true, "id": CH_LATEST, "ordered": false, "maxRetransmits": 0}
		)
		chans[CH_VOICE] = pc.create_data_channel(
			"voice", {"negotiated": true, "id": CH_VOICE, "ordered": false, "maxRetransmits": 0}
		)
		for id: int in chans:
			var ch: WebRTCDataChannel = chans[id]
			log_line(
				(
					"channel %d label=%s ordered=%s maxRetransmits=%d negotiated=%s"
					% [
						id,
						ch.get_label(),
						ch.is_ordered(),
						ch.get_max_retransmits(),
						ch.is_negotiated()
					]
				)
			)


func _send_sig(d: Dictionary) -> void:
	if tcp != null and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		tcp.put_utf8_string(JSON.stringify(d))


func _on_sdp(type: String, sdp: String) -> void:
	pc.set_local_description(type, sdp)
	_send_sig({"t": type, "sdp": sdp})


func _on_cand(media: String, index: int, cand: String) -> void:
	# Only IPv4 host candidates, rewritten to the loopback: the spike runs on 127.0.0.1.
	var parts: PackedStringArray = cand.split(" ")
	var at: int = parts.find("typ")
	if at < 2 or parts[at + 1] != "host" or not parts[at - 2].contains("."):
		return
	parts[at - 2] = "127.0.0.1"
	_send_sig({"t": "cand", "m": media, "i": index, "c": " ".join(parts)})


func _on_sig(d: Dictionary) -> void:
	var t: String = str(d["t"])
	if t == "offer" or t == "answer":
		pc.set_remote_description(t, str(d["sdp"]))
	elif t == "cand":
		pc.add_ice_candidate(str(d["m"]), int(d["i"] as float), str(d["c"]))
	elif t == "pid":
		peer_pid = int(d["pid"] as float)
	elif t == "end":
		_finish()


func _signalling() -> void:
	if role == 1 and tcp == null and server.is_connection_available():
		tcp = server.take_connection()
		log_line("signalling connected")
		pc.create_offer()
	if tcp == null:
		return
	tcp.poll()
	if role == 2 and tcp.get_status() == StreamPeerTCP.STATUS_ERROR:
		tcp = StreamPeerTCP.new()
		tcp.connect_to_host("127.0.0.1", port)
		return
	if (
		role == 2
		and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED
		and opened_at < 0
		and peer_pid == 0
	):
		peer_pid = -1
		_send_sig({"t": "pid", "pid": OS.get_process_id()})
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED and tcp.get_available_bytes() > 0:
		var d: Variant = JSON.parse_string(tcp.get_utf8_string())
		if d is Dictionary:
			_on_sig(d as Dictionary)


func _log_states() -> void:
	var s: int = pc.get_connection_state()
	if s != last_pc_state:
		log_line("pc state %d -> %d" % [last_pc_state, s])
		last_pc_state = s
	for id: int in chans:
		var ch: WebRTCDataChannel = chans[id]
		var cs: int = ch.get_ready_state()
		if cs != last_ch_state.get(id, -1):
			log_line("channel %d state %d" % [id, cs])
			last_ch_state[id] = cs


func _all_open() -> bool:
	if mp != null:
		return (
			mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
			and mp.has_peer(2 if role == 1 else 1)
		)
	for id: int in chans:
		var ch: WebRTCDataChannel = chans[id]
		if ch.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			return false
	return true


func _packet(ch: int, size: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(size)
	if size >= 8:
		p.encode_u32(0, seq[ch])
		p.encode_u32(4, _ms())
	seq[ch] = seq[ch] + 1
	return p


func _put(ch: int, size: int) -> void:
	var c: WebRTCDataChannel = chans[ch]
	var err: Error = c.put_packet(_packet(ch, size))
	if err != OK:
		log_line("put_packet ch %d size %d err %d" % [ch, size, err])


## Drains every channel; returns how many packets were read, per channel.
func _drain() -> Dictionary[int, int]:
	var n: Dictionary[int, int] = {CH_RELIABLE: 0, CH_LATEST: 0, CH_VOICE: 0}
	for id: int in chans:
		var ch: WebRTCDataChannel = chans[id]
		while ch.get_available_packet_count() > 0:
			var p: PackedByteArray = ch.get_packet()
			n[id] = n[id] + 1
			got[id] = got[id] + 1
			if p.size() >= 8:
				var s: int = p.decode_u32(0)
				if id == CH_RELIABLE and s != max_seq[id] + 1:
					beat_order_ok = false
				max_seq[id] = maxi(max_seq[id], s)
	return n


func _traffic() -> void:
	var now: int = _ms()
	while now >= next_voice:
		next_voice += 20
		for i in voice_streams:
			_put(CH_VOICE, 58)
	while now >= next_latest:
		next_latest += 50
		_put(CH_LATEST, 200)
	while now >= next_beat:
		next_beat += 100
		_put(CH_RELIABLE, 16)


func _start_traffic() -> void:
	traffic = true
	next_voice = _ms()
	next_latest = _ms()
	next_beat = _ms()


func _process(_delta: float) -> bool:
	_signalling()
	if mp != null:
		mp.poll()
		while mp.get_available_packet_count() > 0:
			mp.get_packet()
	else:
		pc.poll()
		for id: int in chans:
			var ch: WebRTCDataChannel = chans[id]
			ch.poll()
	_log_states()
	if opened_at < 0 and _all_open():
		opened_at = _ms()
		log_line("open after %d ms" % opened_at)
		_plan()
		step_at = _ms()
	if role == 2 and mp == null:
		var gap: int = Time.get_ticks_usec() - last_poll_us
		var n: Dictionary[int, int] = _drain()
		if gap > 1000000:
			log_line(
				(
					"first poll after a %d ms gap read reliable=%d latest=%d voice=%d"
					% [gap / 1000, n[CH_RELIABLE], n[CH_LATEST], n[CH_VOICE]]
				)
			)
	last_poll_us = Time.get_ticks_usec()
	if role == 1 and traffic and mp == null:
		_traffic()
	if opened_at >= 0:
		_run_steps()
	if _ms() > _opt_i("deadline", "120000"):
		log_line("deadline")
		_finish()
	return done


func _finish() -> void:
	if done:
		return
	log_line(
		(
			"final sent r=%d l=%d v=%d got r=%d l=%d v=%d maxseq r=%d l=%d v=%d beats_in_order=%s pc=%d"
			% [
				seq[CH_RELIABLE],
				seq[CH_LATEST],
				seq[CH_VOICE],
				got[CH_RELIABLE],
				got[CH_LATEST],
				got[CH_VOICE],
				max_seq[CH_RELIABLE],
				max_seq[CH_LATEST],
				max_seq[CH_VOICE],
				beat_order_ok,
				pc.get_connection_state(),
			]
		)
	)
	if role == 1:
		_send_sig({"t": "end"})
		tcp.poll()
	done = true
	pc.close()


## Steps: {"after": ms since the previous step, "do": Callable}.
func _run_steps() -> void:
	while step_i < step_do.size() and _ms() - step_at >= step_after[step_i]:
		var c: Callable = step_do[step_i]
		step_i += 1
		step_at = _ms()
		c.call()


func _step(after: int, c: Callable) -> void:
	step_after.append(after)
	step_do.append(c)


func _plan() -> void:
	if role != 1:
		if mode == "freeze":
			_step(1500, func() -> void: _freeze(5200))
		elif mode == "hang":
			_step(1500, func() -> void: _freeze(_opt_i("hang", "30") * 1000))
		return
	if mode == "overhead":
		_step(1000, func() -> void: pass)
		for size: int in SIZES:
			for ch: int in [CH_VOICE, CH_LATEST, CH_RELIABLE]:
				_step(300, func() -> void: log_line("mark start ch=%d size=%d" % [ch, size]))
				for i in 50:
					_step(20, func() -> void: _put(ch, size))
				_step(300, func() -> void: log_line("mark end ch=%d size=%d" % [ch, size]))
		for size in range(1100, 1300, 4):
			_step(100, func() -> void: log_line("mark start ch=3 size=%d" % size))
			for i in 5:
				_step(20, func() -> void: _put(CH_VOICE, size))
			_step(100, func() -> void: log_line("mark end ch=3 size=%d" % size))
		for size: int in [1150, 1160, 1170, 1180, 1190, 1200, 1210]:
			for ch: int in [CH_LATEST, CH_RELIABLE]:
				_step(100, func() -> void: log_line("mark start ch=%d size=%d" % [ch, size]))
				for i in 5:
					_step(20, func() -> void: _put(ch, size))
				_step(300, func() -> void: log_line("mark end ch=%d size=%d" % [ch, size]))
		_step(1000, _finish)
	elif mode == "sendtime":
		_step(1000, _send_timed)
	elif mode == "freeze":
		_step(0, _start_traffic)
		# The receiver freezes at 1.5 s for 5.2 s; then the sender freezes.
		_step(9000, func() -> void: _freeze(5200))
		_step(4000, _finish)
	elif mode == "hang":
		_step(0, _start_traffic)
		_step(_opt_i("hang", "30") * 1000 + 6000, _finish)
	elif mode == "stop":
		if mp == null:
			_step(0, _start_traffic)
		var stop_s: int = _opt_i("stop", "20")
		_step(1500, func() -> void: _signal_peer("STOP"))
		for i in stop_s:
			_step(1000, func() -> void: _report_mp())
		_step(0, func() -> void: _signal_peer("CONT"))
		for i in 10:
			_step(1000, func() -> void: _report_mp())
		_step(0, _finish)


func _report_mp() -> void:
	if mp != null:
		log_line(
			(
				"mp has_peer(2)=%s status=%d pc=%d"
				% [mp.has_peer(2), mp.get_connection_status(), pc.get_connection_state()]
			)
		)
	else:
		log_line(
			(
				"pc=%d voice buffered=%d"
				% [
					pc.get_connection_state(),
					(chans[CH_VOICE] as WebRTCDataChannel).get_buffered_amount()
				]
			)
		)


func _signal_peer(sig: String) -> void:
	var out: Array = []
	var code: int = OS.execute("kill", ["-" + sig, str(peer_pid)], out, true)
	log_line("kill -%s %d -> %d" % [sig, peer_pid, code])


func _freeze(ms: int) -> void:
	log_line("freeze %d ms (main thread)" % ms)
	OS.delay_msec(ms)
	log_line("thaw; pc=%d" % pc.get_connection_state())


func _send_timed() -> void:
	# 500 ticks of 20 ms; each tick 81 sends of 58 B on VOICE (or --ch=). Busy-waits between ticks.
	var ch: int = _opt_i("ch", str(CH_VOICE))
	var c: WebRTCDataChannel = chans[ch]
	var times: Array[int] = []
	var p := PackedByteArray()
	p.resize(58)
	var next: int = Time.get_ticks_usec()
	var errors: int = 0
	for tick in 500:
		while Time.get_ticks_usec() < next:
			pass
		next += 20000
		var a: int = Time.get_ticks_usec()
		for i in 81:
			if c.put_packet(p) != OK:
				errors += 1
		times.append(Time.get_ticks_usec() - a)
		pc.poll()
	times.sort()
	var total: int = 0
	for t in times:
		total += t
	log_line(
		(
			"sendtime ch=%d ticks=%d median_us=%d p99_us=%d max_us=%d mean_us=%d errors=%d buffered=%d"
			% [
				ch,
				times.size(),
				times[times.size() / 2],
				times[int(times.size() * 0.99)],
				times[-1],
				total / times.size(),
				errors,
				c.get_buffered_amount()
			]
		)
	)
	_step(2000, _finish)
