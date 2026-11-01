extends OccluderInstance3D
## The lobby's render settings (#1523; the art lobby hall's HANDOFF, prime-game-art#356, "Light and
## cost" and its open question on the ship's interior), on the lobby's `ShipOccluder`, after `Hall`:
## - the positional shadow atlas the art's shots use (4096, all four quadrants subdivided 4, for the
##   pendants' shadowed spots), set on the viewport the lobby draws in while the lobby is in the
##   tree and the viewport's own settings put back as it leaves, so no match map changes;
## - occlusion culling on that viewport for as long, with this node's occluder built on _ready from
##   the docked ship's opaque hull (the `skin_*` pieces) and its shut jaw nose: the ship's interior
##   (the hall, the corridors, the tip rooms) is drawn only where a window, the canopy or a porthole
##   shows it, not behind the hull, where the hall's views saw it (about 2700 to 3200 draw calls).
## The host's LevelWorld reads the scene outside the tree, so none of this runs there.

const ATLAS_SIZE := 4096
const ATLAS_QUADRANT := Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
## The ship's pieces whose meshes occlude, relative to this node's parent (the lobby's root).
const SHIP_PIECES := "Hall/Ship/Pieces"
const SHIP_NOSE := "Hall/Ship/Nose"
const HULL_PREFIX := "skin_"

var _kept_atlas_size: int = 0
var _kept_quadrants: Array[Viewport.PositionalShadowAtlasQuadrantSubdiv] = []
var _kept_occlusion: bool = false


func _enter_tree() -> void:
	var viewport: Viewport = get_viewport()
	_kept_atlas_size = viewport.positional_shadow_atlas_size
	_kept_quadrants.clear()
	for quadrant: int in 4:
		_kept_quadrants.append(viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
	_kept_occlusion = viewport.use_occlusion_culling
	viewport.positional_shadow_atlas_size = ATLAS_SIZE
	for quadrant: int in 4:
		viewport.set_positional_shadow_atlas_quadrant_subdiv(quadrant, ATLAS_QUADRANT)
	viewport.use_occlusion_culling = true


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	viewport.positional_shadow_atlas_size = _kept_atlas_size
	for quadrant: int in _kept_quadrants.size():
		viewport.set_positional_shadow_atlas_quadrant_subdiv(quadrant, _kept_quadrants[quadrant])
	viewport.use_occlusion_culling = _kept_occlusion


func _ready() -> void:
	var meshes: Array[MeshInstance3D] = []
	var pieces: Node = get_parent().get_node_or_null(SHIP_PIECES)
	if pieces != null:
		for piece: Node in pieces.get_children():
			if piece.name.begins_with(HULL_PREFIX):
				_collect(piece, meshes)
	var nose: Node = get_parent().get_node_or_null(SHIP_NOSE)
	if nose != null:
		_collect(nose, meshes)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for mesh: MeshInstance3D in meshes:
		_add_opaque_surfaces(mesh, vertices, indices)
	set_meta("occluder_meshes", meshes.size())
	set_meta("occluder_triangles", floori(indices.size() / 3.0))
	if indices.is_empty():
		return
	var built := ArrayOccluder3D.new()
	built.set_arrays(vertices, indices)
	occluder = built


static func _collect(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect(child, into)


## Whether `material` hides what is behind it: a base material without transparency, or a shader
## (the hull's `metal.gdshader`) that writes no ALPHA and draws its depth.
static func _is_opaque(material: Material) -> bool:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
		var code: String = (material as ShaderMaterial).shader.code
		return not (
			code.contains("ALPHA")
			or code.contains("blend_add")
			or code.contains("depth_draw_never")
		)
	return false


## The surfaces of `mesh` that hide what is behind them (no transparency), in this node's space.
## A renderer that keeps no mesh data (the headless one) gives no arrays: nothing is added.
func _add_opaque_surfaces(
	mesh: MeshInstance3D, vertices: PackedVector3Array, indices: PackedInt32Array
) -> void:
	var to_here: Transform3D = global_transform.affine_inverse() * mesh.global_transform
	for surface: int in mesh.mesh.get_surface_count():
		if not _is_opaque(mesh.get_active_material(surface)):
			continue
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			surface_indices = arrays[Mesh.ARRAY_INDEX]
		if surface_indices.is_empty():
			for i: int in surface_vertices.size():
				surface_indices.append(i)
		var base: int = vertices.size()
		for vertex: Vector3 in surface_vertices:
			vertices.append(to_here * vertex)
		for index: int in surface_indices:
			indices.append(base + index)
