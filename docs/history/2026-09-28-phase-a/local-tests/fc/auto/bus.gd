extends Node

signal pinged(n: int)


func ping() -> void:
	pinged.emit(1)


func _init() -> void:
	print("BUS_INIT")


func _ready() -> void:
	print("BUS_READY")
