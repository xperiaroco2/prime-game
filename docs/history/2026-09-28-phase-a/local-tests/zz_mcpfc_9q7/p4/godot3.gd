extends KinematicBody

export var speed = 5.0
onready var cam = $Camera

func _ready():
	yield(get_tree().create_timer(1.0), "timeout")
	connect("body_entered", self, "_on_body")
