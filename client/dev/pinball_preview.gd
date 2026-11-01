extends Node3D
## A preview of the pinball's client (#1400, ARCHITECTURE §4.7.63) for `tools\run.cmd shot`: the
## lobby hall with PinballViews driven from a fake ClientModel: a game on (a score, two balls
## left, the left flipper up, the ball mid-table) and a best a roster member owns, its name in his
## body colour. `stage` picks the view: "close_up" (the own player seated: the close-up lens at
## its marker, where its ease ends) or "table" (a bystander standing at the machine's spot, the
## other player seated). The sun and the sky are the preview's own (the game lights the hall).
## Dev only, nothing here reaches the game.

const LOBBY := "res://levels/lobby/lobby.tscn"
const Preview := preload("res://client/dev/screen_preview.gd")
const OWN := 1
const OWNER := 2
## The render tick the ball is drawn at, and the ball's table-local place then.
const RENDER_TICK := 100
const BALL := Vector3(0.08, 0.03, -0.35)
## A bystander's eye over the machine's spot (PlayerController's standing eye, about).
const EYE_M := 1.6
## The roster: the own player and the best's owner (names and colour indices; preview only).
const OWN_NAME := "Olena"
const OWNER_NAME := "Taras"
const OWNER_COLOUR := 3

## "close_up" or "table".
@export_enum("close_up", "table") var stage := "close_up"

var _model: ClientModel
var _views := PinballViews.new()


func _ready() -> void:
	_light()
	var level := (load(LOBBY) as PackedScene).instantiate()
	add_child(level)
	_model = ClientModel.new(load(Preview.MODE) as GameMode)
	_model.own_peer = OWN
	_member(OWN, OWN_NAME, 0)
	_member(OWNER, OWNER_NAME, OWNER_COLOUR)
	var pinball := _model.pinball
	pinball.game = 1
	pinball.player = OWN if stage == "close_up" else OWNER
	pinball.left = true
	pinball.in_play = true
	pinball.score = 1250
	pinball.balls_left = 2
	pinball.best = 4800
	pinball.best_name = OWNER_NAME
	_views.model = _model
	_views.drawn_at = func() -> float: return float(RENDER_TICK)
	add_child(_views)
	_views.level = level
	pinball.fold_snapshot({"tick": RENDER_TICK, "ball": BALL})
	_views.on_snapshot(RENDER_TICK, {})
	if stage == "close_up":
		var lens := _views.close_up.camera
		lens.global_transform = _views.close_up.marker.global_transform
		lens.make_current()
		return
	var camera := Camera3D.new()
	add_child(camera)
	var spot := get_tree().get_first_node_in_group(&"spawn_pinball") as Node3D
	camera.look_at_from_position(
		spot.global_position + Vector3.UP * EYE_M, _views.table.global_position
	)
	camera.current = true


func _member(peer: int, member_name: String, colour: int) -> void:
	var member := ClientModel.Member.new()
	member.name = member_name
	member.colour = colour
	_model.roster[peer] = member


func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
