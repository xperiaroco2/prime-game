extends Node

onready var lbl = $Label

func _ready():
	yield(get_tree(), "idle_frame")
