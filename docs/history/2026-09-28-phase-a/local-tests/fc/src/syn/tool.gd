@tool
extends Node

@export_tool_button("Do it") var do_it: Callable = func() -> void: print("x")
