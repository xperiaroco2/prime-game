extends RefCounted


func f(d: Dictionary) -> void:
	var v: Variant = d.get("k")
	v.do_thing()
	print(v.some_prop)
