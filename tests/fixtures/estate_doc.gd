extends RefCounted
## The forest estate's design doc (docs/design/estate-map.md §3), read for the estate greybox's
## tests (#1158): the modules' rows (centre, footprint, clearing radius), the creek's line and its
## crossings, so the map and the doc never disagree silently (the level piece ADR's "A check").

const DOC := "res://docs/design/estate-map.md"
const MAP := "res://levels/estate/estate.tscn"
const ROOMS := "res://levels/estate/rooms/"


## One row of §3's module table.
class Module:
	## The module's name without its parenthesis ("Gazebo (photo)" is "Gazebo").
	var name: String
	## Its centre in plan metres (x east, y south).
	var centre: Vector2
	## Its footprint in whole metres when the doc gives one as "W x D" or "W wide x D deep";
	## zero when it is round or only a width.
	var size: Vector2i
	## Its clearing's radius; 0 when the doc gives none.
	var radius: float

	func _init(row_name: String, at: Vector2, dims: Vector2i, clearing: float) -> void:
		name = row_name
		centre = at
		size = dims
		radius = clearing


## §3's module rows that parse.
static func modules() -> Array[Module]:
	var out: Array[Module] = []
	var row := RegEx.create_from_string(
		"^\\| ([^|]+?) \\| (-?[\\d.]+), (-?[\\d.]+) \\| ([^|]*?) \\| *([\\d.]*) *\\| [^|]*\\|$"
	)
	var size := RegEx.create_from_string("^(\\d+)(?: wide)? x (\\d+)\\b")
	for line in _section_3():
		var m := row.search(line)
		if m == null:
			continue
		var name := m.get_string(1).get_slice(" (", 0)
		var at := Vector2(float(m.get_string(2)), float(m.get_string(3)))
		var dims := Vector2i.ZERO
		var s := size.search(m.get_string(4))
		if s != null:
			dims = Vector2i(int(s.get_string(1)), int(s.get_string(2)))
		var radius := float(m.get_string(5)) if not m.get_string(5).is_empty() else 0.0
		out.append(Module.new(name, at, dims, radius))
	return out


## The table rows of §3 that are not its header or rule: each must be a module.
static func row_count() -> int:
	var count := 0
	for line in _section_3():
		if line.begins_with("| ") and not line.begins_with("| Module |"):
			count += 1
	return count


## The creek's line, the points before "about 3 m wide".
static func creek() -> PackedVector2Array:
	var out := PackedVector2Array()
	var line := _creek_paragraph().get_slice(", about", 0)
	for m in RegEx.create_from_string("\\((-?[\\d.]+), (-?[\\d.]+)\\)").search_all(line):
		out.append(Vector2(float(m.get_string(1)), float(m.get_string(2))))
	return out


## The creek's crossings by their doc names ("log bridge"), at their plan points.
static func crossings() -> Dictionary[String, Vector2]:
	var out: Dictionary[String, Vector2] = {}
	var rest := _creek_paragraph().get_slice(", about", 1)
	var named := RegEx.create_from_string("(?:the|a) ([a-z ]+?) \\((-?[\\d.]+), (-?[\\d.]+)\\)")
	for m in named.search_all(rest):
		out[m.get_string(1)] = Vector2(float(m.get_string(2)), float(m.get_string(3)))
	return out


## The creek's unit normal, pointing south, at its segment nearest `p`.
static func creek_normal(p: Vector2) -> Vector2:
	var line := creek()
	var best := 0
	for i in line.size() - 1:
		if (
			distance_to_segment(p, line[i], line[i + 1])
			< distance_to_segment(p, line[best], line[best + 1])
		):
			best = i
	var d := (line[best + 1] - line[best]).normalized()
	var n := Vector2(-d.y, d.x)
	return n if n.y > 0 else -n


static func distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


static func pascal(name: String) -> String:
	var out := ""
	for w in _words(name):
		out += w.substr(0, 1).to_upper() + w.substr(1)
	return out


static func snake(name: String) -> String:
	var out := PackedStringArray()
	for w in _words(name):
		out.append(w.to_lower())
	return "_".join(out)


static func _words(name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in RegEx.create_from_string("[A-Za-z0-9]+").search_all(name):
		out.append(m.get_string())
	return out


## §3's paragraph that starts "**The creek:**", its lines joined.
static func _creek_paragraph() -> String:
	var lines := PackedStringArray()
	for line in _section_3():
		if line.begins_with("**The creek:**"):
			lines.append(line)
		elif not lines.is_empty():
			if line.strip_edges().is_empty():
				break
			lines.append(line)
	return " ".join(lines)


static func _section_3() -> PackedStringArray:
	var lines := PackedStringArray()
	var inside := false
	for line in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("## "):
			inside = line.begins_with("## 3.")
		elif inside:
			lines.append(line)
	return lines
