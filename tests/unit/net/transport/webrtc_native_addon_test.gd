extends GdUnitTestSuite
## The webrtc-native addon loads headless (#367, the M6 design's E57): its classes
## register, and the engine's WebRTC classes reach them. Without the extension Godot has
## no WebRTC implementation outside the web export, so every test here fails. Builds
## objects only: no ICE servers, no signalling, nothing on the network.

const EXTENSION := "res://addons/webrtc_native/webrtc_native.gdextension"


func test_the_extension_is_loaded() -> void:
	assert_bool(GDExtensionManager.is_extension_loaded(EXTENSION)).is_true()
	assert_bool(ClassDB.class_exists(&"WebRTCLibPeerConnection")).is_true()
	assert_bool(ClassDB.class_exists(&"WebRTCLibDataChannel")).is_true()


func test_a_peer_connection_creates_a_data_channel() -> void:
	var connection := WebRTCPeerConnection.new()
	assert_int(connection.initialize({})).is_equal(OK)
	assert_int(connection.get_connection_state()).is_equal(WebRTCPeerConnection.STATE_NEW)
	var channel := connection.create_data_channel("smoke", {"negotiated": true, "id": 1})
	assert_object(channel).is_not_null()
	assert_str(channel.get_label()).is_equal("smoke")
	assert_bool(channel.is_negotiated()).is_true()
	assert_int(channel.get_id()).is_equal(1)
	assert_int(channel.get_ready_state()).is_equal(WebRTCDataChannel.STATE_CONNECTING)
	channel.close()
	connection.close()


func test_a_multiplayer_peer_takes_a_peer_connection() -> void:
	var peer := WebRTCMultiplayerPeer.new()
	assert_int(peer.create_server()).is_equal(OK)
	var connection := WebRTCPeerConnection.new()
	assert_int(connection.initialize({})).is_equal(OK)
	assert_int(peer.add_peer(connection, 2)).is_equal(OK)
	assert_bool(peer.has_peer(2)).is_true()
	peer.remove_peer(2)
	assert_bool(peer.has_peer(2)).is_false()
	peer.close()
	connection.close()
