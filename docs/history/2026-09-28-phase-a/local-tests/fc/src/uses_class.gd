extends RefCounted

func f() -> int:
	var t: OkThing = OkThing.new()
	return t.value()
