@abstract class_name AbsSyn
extends RefCounted

@export var hp: int = 3
static var counter: int = 0

@abstract func area() -> float


func sum(...rest: Array) -> int:
	var total: int = 0
	for v: int in rest:
		total += v
	return total


func scores() -> Dictionary[String, int]:
	var d: Dictionary[String, int] = {"a": 1}
	return d


func kind(x: Variant) -> String:
	match typeof(x):
		TYPE_INT when x > 3:
			return "big"
		_:
			pass
	if x is not String:
		return r"raw\n"
	return "s"


@warning_ignore_start("unused_variable")


func noisy() -> void:
	var z: int = 1


@warning_ignore_restore("unused_variable")

@abstract class Inner:
	extends RefCounted

	@abstract func g() -> void


class Impl:
	extends Inner

	func g() -> void:
		pass
