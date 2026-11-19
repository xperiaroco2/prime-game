class_name FpView
extends CanvasLayer
## The first-person hands' own camera (#1587; ARCHITECTURE §4.7.68), as first-person games draw a
## viewmodel and as the art package's HANDOFF asks: a Camera3D at the package's FOV_DEG, its
## transform the player camera's every frame, in a transparent SubViewport the size of the screen
## laid over the live view, under the HUD (layer LAYER). It shares the level's World3D and draws
## PhotoLayers.HANDS alone: the hands (FpHands) and the crystal they hold. A soft fill light on that
## layer alone lights them from the upper left (the package's shots: a directional light, energy
## FILL_ENERGY, warm white), with the level's own lights (light_level puts HANDS on each light
## that reaches GROUND). It shows while `shown` and the player camera is the current one (not the
## downed, spectate or viewfinder camera).

## The package's vertical field of view, degrees (HANDOFF `[view] fov_deg`).
const FOV_DEG := 50.0
## Under GameUi's layers (1 and up): the hands sit between the 3D view and the HUD.
const LAYER := -1
const FILL_ENERGY := 0.35
const FILL_COLOUR := Color(1.0, 0.95, 0.88)
## The fill light's direction in the camera's space: from the upper left, slightly behind.
const FILL_EULER := Vector3(deg_to_rad(-35.0), deg_to_rad(-40.0), 0.0)

## The player camera the hands' camera follows.
var source: Camera3D
## Whether the hands are drawn at all (the controller's: the own player living).
var shown := true
var container := SubViewportContainer.new()
var viewport := SubViewport.new()
var camera := Camera3D.new()
var fill := DirectionalLight3D.new()
## The environment the hands' own is a copy of (hands_environment), to copy it again on a change.
var _looks_of: Environment


func _init() -> void:
	name = "FpView"
	layer = LAYER
	container.name = "Hands"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.focus_mode = Control.FOCUS_NONE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	viewport.name = "Viewport"
	viewport.transparent_bg = true
	viewport.own_world_3d = false
	viewport.gui_disable_input = true
	# The hands receive no shadows: the pass renders no shadow map of the level's lights.
	viewport.positional_shadow_atlas_size = 0
	container.add_child(viewport)
	camera.name = "Camera"
	camera.fov = FOV_DEG
	camera.cull_mask = PhotoLayers.HANDS
	camera.current = true
	viewport.add_child(camera)
	fill.name = "Fill"
	fill.layers = PhotoLayers.HANDS
	fill.light_cull_mask = PhotoLayers.HANDS
	fill.light_energy = FILL_ENERGY
	fill.light_color = FILL_COLOUR
	fill.shadow_enabled = false
	# The fill is the hands' alone: no sun of the shared world's sky, no part in baked or GI light.
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.light_bake_mode = Light3D.BAKE_DISABLED
	fill.rotation = FILL_EULER
	camera.add_child(fill)
	# After the controller's own _process (the drunk sway moves its camera there).
	process_priority = 100


func _process(_delta: float) -> void:
	var on := drawn()
	container.visible = on
	if not on:
		return
	camera.global_transform = source.global_transform
	camera.near = source.near
	var looks := source.environment if source.environment != null else _world_environment()
	if looks != _looks_of:
		_looks_of = looks
		camera.environment = hands_environment(looks)


## Whether the hands are drawn now: shown, and the player camera is its viewport's current one.
func drawn() -> bool:
	return (
		shown
		and source != null
		and is_instance_valid(source)
		and source.is_inside_tree()
		and source.current
	)


## The hands' environment: a copy of the live view's `looks` (its tone, ambient light and
## exposure) whose background is the transparent clear colour, without the screen-space and
## volume passes (SSAO, SSIL, SDFGI, fog, volumetric fog, glow) a second full-screen pass of the
## hands alone needs not pay for; null for none.
static func hands_environment(looks: Environment) -> Environment:
	if looks == null:
		return null
	var own := looks.duplicate() as Environment
	own.background_mode = Environment.BG_CLEAR_COLOR
	own.ssao_enabled = false
	own.ssil_enabled = false
	own.sdfgi_enabled = false
	own.fog_enabled = false
	own.volumetric_fog_enabled = false
	own.glow_enabled = false
	return own


## Puts PhotoLayers.HANDS on every light under `level` the live view draws (its `layers` in
## LIVE_VIEW): on its `layers`, so the hands' camera draws it, and on its `light_cull_mask`, so it
## lights the hands. The hands stay lit as the room round them, the lobby's own lights (layer 11)
## too. GameLevel.swap runs it on every level it adds; a light added later (the dead's hall, a
## photo's flash) does not light the hands.
static func light_level(level: Node) -> void:
	if level == null:
		return
	for node: Node in level.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.layers & PhotoLayers.LIVE_VIEW != 0:
			light.layers |= PhotoLayers.HANDS
			light.light_cull_mask |= PhotoLayers.HANDS


func _world_environment() -> Environment:
	var world := source.get_world_3d()
	return world.environment if world != null else null
