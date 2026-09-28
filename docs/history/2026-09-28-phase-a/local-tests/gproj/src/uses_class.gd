extends RefCounted

func g() -> int:
	var t := OkThing.new()
	return t.bump(2)
