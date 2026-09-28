extends RefCounted


func sum_all(first: int, ...rest: Array) -> int:
	var total: int = first
	for v: int in rest:
		total += v
	return total
