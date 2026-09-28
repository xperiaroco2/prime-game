class_name HookThing
extends RefCounted

var count: int = 0


func bump(by: int) -> int:
	count += by
	return count
