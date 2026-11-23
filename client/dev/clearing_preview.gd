extends Node3D
## A preview of the M8 round's clearing (#1687) for `tools\run.cmd shot`: the map as the client
## loads it, the eye at a player's height on the round's start marker `marker`, looking `yaw_deg`
## off the marker's facing (0: the ship's ramp; 180: out to the fog and the boundary). `fog_density`
## above 0 replaces the map's own for the shot, to compare looks. Dev only: nothing here reaches
## the game.

const MAP := "res://levels/clearing/clearing.tscn"
## The player camera's height over the floor and its field of view (client/player/player.tscn).
const EYE_M := 1.62
const FOV_DEG := 75.0

@export var marker := "RoundPlayer02"
@export var yaw_deg := 0.0
@export var fog_density := 0.0


func _ready() -> void:
	var level := (load(MAP) as PackedScene).instantiate() as Node3D
	add_child(level)
	if fog_density > 0.0:
		var sky := level.get_node(^"Sky") as WorldEnvironment
		sky.environment = sky.environment.duplicate() as Environment
		sky.environment.fog_density = fog_density
	var at := level.get_node(NodePath("Markers/" + marker)) as Node3D
	var camera := Camera3D.new()
	camera.fov = FOV_DEG
	camera.cull_mask = PhotoLayers.LIVE_VIEW
	add_child(camera)
	var facing := -at.global_basis.z
	facing.y = 0.0
	facing = facing.normalized().rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var eye := at.global_position + Vector3.UP * EYE_M
	camera.look_at_from_position(eye, eye + facing)
	camera.current = true
