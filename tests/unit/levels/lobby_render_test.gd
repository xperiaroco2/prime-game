extends GdUnitTestSuite
## The lobby's render settings (#1523, levels/lobby/lobby_render.gd): while the lobby is in the
## tree its viewport has the art lobby hall's shadow atlas (4096, every quadrant subdivided 4) and
## occlusion culling on, and as the lobby leaves the viewport gets its own settings back, so a match
## map draws as before. The occluder's hull is built from mesh data the headless renderer does not
## keep: its draw-call cut is measured in a window (the PR), here only the meshes it reads.

const LOBBY := "res://levels/lobby/lobby.tscn"
const OCCLUDER := "ShipOccluder"
const ATLAS_SIZE := 4096

var _viewport: Viewport
var _kept_size: int
var _kept_quadrants: Array[Viewport.PositionalShadowAtlasQuadrantSubdiv] = []
var _kept_occlusion: bool


func before_test() -> void:
	_viewport = get_viewport()
	_kept_size = _viewport.positional_shadow_atlas_size
	_kept_quadrants.clear()
	for quadrant: int in 4:
		_kept_quadrants.append(_viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
	_kept_occlusion = _viewport.use_occlusion_culling


func after_test() -> void:
	_viewport.positional_shadow_atlas_size = _kept_size
	for quadrant: int in 4:
		_viewport.set_positional_shadow_atlas_quadrant_subdiv(quadrant, _kept_quadrants[quadrant])
	_viewport.use_occlusion_culling = _kept_occlusion


func test_the_lobby_sets_the_art_shadow_atlas_and_occlusion_while_in_the_tree() -> void:
	# Settings no match map has, so the lobby's own ones show and the restore is seen.
	_viewport.positional_shadow_atlas_size = 2048
	for quadrant: int in 4:
		_viewport.set_positional_shadow_atlas_quadrant_subdiv(
			quadrant, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64
		)
	_viewport.use_occlusion_culling = false
	var lobby: Node3D = (load(LOBBY) as PackedScene).instantiate() as Node3D
	add_child(lobby)
	await get_tree().process_frame
	assert_int(_viewport.positional_shadow_atlas_size).is_equal(ATLAS_SIZE)
	for quadrant: int in 4:
		assert_int(_viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant)).is_equal(
			Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
		)
	assert_bool(_viewport.use_occlusion_culling).is_true()
	remove_child(lobby)
	lobby.free()
	assert_int(_viewport.positional_shadow_atlas_size).is_equal(2048)
	for quadrant: int in 4:
		assert_int(_viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant)).is_equal(
			Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64
		)
	assert_bool(_viewport.use_occlusion_culling).is_false()


## The occluder reads the docked ship's hull (its skin pieces) and its shut nose: a rename in the
## ship package that leaves it nothing to read fails here, not as a silent draw-call regression.
func test_the_occluder_reads_the_ship_hull_and_nose_after_the_hall() -> void:
	var lobby: Node3D = auto_free((load(LOBBY) as PackedScene).instantiate()) as Node3D
	var occluder: Node = lobby.get_node_or_null(OCCLUDER)
	assert_object(occluder).is_instanceof(OccluderInstance3D)
	assert_int(occluder.get_index()).is_greater(lobby.get_node("Hall").get_index())
	add_child(lobby)
	await get_tree().process_frame
	assert_int(occluder.get_meta("occluder_meshes", 0) as int).is_greater(0)
