class_name EngineProblem
extends RefCounted
## One open problem of the ship's engine (ARCHITECTURE §9.5.27): match state in ShipEngine.State,
## never in a part. The engine writes every field but `data`, which belongs to its kind
## (ProblemKind.opened() sets it; the gills' slits, the tripped breakers' order).

## Its id within the match, 1 up (EngineProblemOpened's and EngineProblemFixed's `problem`).
var id: int
var kind: ProblemKind
## Its stations' ids, ascending (ProblemKind.claim's answer).
var stations: PackedInt32Array
## The host tick it opened on.
var opened: int
## The host tick it blows on unless a command of that tick fixed it.
var deadline: int
## The engine's stage it opened in, 1 up.
var stage: int
## The kind's own state of this problem; null until the kind sets it.
var data: Variant = null


func _init(
	problem_id: int,
	problem_kind: ProblemKind,
	station_ids: PackedInt32Array,
	opened_at: int,
	deadline_tick: int,
	in_stage: int
) -> void:
	id = problem_id
	kind = problem_kind
	stations = station_ids
	opened = opened_at
	deadline = deadline_tick
	stage = in_stage
