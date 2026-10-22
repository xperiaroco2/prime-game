extends RefCounted
## The station-room check the House's station suites share (#1256): each room scene, loaded and
## instanced, holds each of its stations under `Stations`, instancing its station scene, and the
## art's own copy of the device (a node with the station's `metadata/station`) is gone from the
## room's dressing (the scene is the device). The asserts are the calling suite's, so a failure is
## its test's.

const ROOMS := "res://levels/house/rooms/"


## `stations`: room name -> {station node under `Stations` -> its scene, `scenes_dir` + that}.
static func check(suite: GdUnitTestSuite, stations: Dictionary, scenes_dir: String = "") -> void:
	for room: String in stations:
		var root := (
			suite.auto_free((load(ROOMS + room + ".tscn") as PackedScene).instantiate()) as Node
		)
		var in_room: Dictionary = stations[room]
		for station_name: String in in_room:
			var where := "%s: Stations/%s" % [room, station_name]
			var station := root.get_node_or_null("Stations/" + station_name)
			suite.assert_object(station).override_failure_message(where).is_not_null()
			if station == null:
				continue
			suite.assert_str(station.scene_file_path).override_failure_message(where).is_equal(
				scenes_dir + str(in_room[station_name])
			)
			# The art's props of the same device (`metadata/station`) would stand a second one.
			for copy: Node in with_station_meta(root, station_name):
				(
					GdUnitTestSuite
					. assert_bool(copy == station)
					. override_failure_message(
						"%s: %s still stands the art's device" % [where, root.get_path_to(copy)]
					)
					. is_true()
				)


## Every node under `node` (itself too) whose `metadata/station` is `station`.
static func with_station_meta(node: Node, station: String) -> Array[Node]:
	var found: Array[Node] = []
	if str(node.get_meta(&"station", "")) == station:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(with_station_meta(child, station))
	return found
