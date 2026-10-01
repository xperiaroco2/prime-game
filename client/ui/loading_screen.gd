class_name LoadingScreen
extends Control
## The loading screen (ARCHITECTURE §4.7): the map being loaded and who has loaded it
## (PlayerLoaded), from the own ClientModel.

var map_label := Label.new()
var players_label := Label.new()


func _init() -> void:
	name = "LoadingScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color(0.05, 0.05, 0.07)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var column := UiParts.centered_column(self, "Loading")
	column.add_child(map_label)
	column.add_child(players_label)


func refresh(model: ClientModel) -> void:
	map_label.text = "Map: %s" % model.map.get_file().get_basename()
	var peers: Array[int] = []
	peers.assign(model.roster.keys())
	peers.sort()
	var lines := PackedStringArray()
	for peer in peers:
		var done := model.loaded.has(peer)
		lines.append("%s  %s" % [model.roster[peer].name, "loaded" if done else "loading..."])
	players_label.text = "\n".join(lines)
