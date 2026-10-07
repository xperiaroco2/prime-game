extends GdUnitTestSuite
## The M6 design §3 item 4: no screen shows another player's address, candidates or whether
## another player is relayed. client/ reads no peer's address or ICE state from any API, and its
## screens (client/ui/) name no transport at all: what a screen knows of a join is what the player
## typed (JoinTarget) and the step (JoinProgress). The overlay (F3) shows only the own
## connection's kind and round trip (#431), which reach client/ through the own ClientSession alone.

## Calls and words that would hand a screen a peer's address, port, candidates or relay status.
const FORBIDDEN: Array[String] = [
	"get_peer_address",
	"get_remote_address",
	"get_packet_ip",
	"get_peer_port",
	"get_remote_port",
	"ice_candidate",
	"typ relay",
	"get_connection_state",
	"get_gathering_state",
	"local_candidates",
]
## The transport's calls for the own connection: only ClientSession, over its own transport, makes
## them. server/ never does, so the host's player cannot read a peer's.
const OWN_CONNECTION: Array[String] = ["own_route(", "own_round_trip_ms(", "measure_round_trip"]
const OWN_SESSION := "res://client/net/client_session.gd"
## Transport classes the screens never name.
const TRANSPORTS: Array[String] = ["EnetTransport", "WebRtcTransport", "LoopbackTransport"]


func test_no_client_file_reads_a_peers_address_or_ice_state() -> void:
	for path: String in _scripts("res://client"):
		var source := FileAccess.get_file_as_string(path)
		for word: String in FORBIDDEN:
			if word == "local_candidates" and path == "res://client/app/code_room.gd":
				continue  # sets the own host's candidate filter; reads nothing
			(
				assert_bool(source.contains(word))
				. override_failure_message("%s names %s" % [path, word])
				. is_false()
			)


func test_only_the_own_session_reads_its_connection() -> void:
	var paths := _scripts("res://client")
	paths.append_array(_scripts("res://server"))
	for path: String in paths:
		if path == OWN_SESSION:
			continue
		var source := FileAccess.get_file_as_string(path)
		for word: String in OWN_CONNECTION:
			(
				assert_bool(source.contains(word))
				. override_failure_message("%s names %s" % [path, word])
				. is_false()
			)
	var session := FileAccess.get_file_as_string(OWN_SESSION)
	for word: String in OWN_CONNECTION:
		assert_bool(session.contains("_transport." + word)).override_failure_message(word).is_true()


func test_no_screen_names_a_transport() -> void:
	for path: String in _scripts("res://client/ui"):
		var source := FileAccess.get_file_as_string(path)
		for word: String in TRANSPORTS:
			(
				assert_bool(source.contains(word))
				. override_failure_message("%s names %s" % [path, word])
				. is_false()
			)


func _scripts(folder: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		found.append_array(_scripts(folder.path_join(sub)))
	return found
