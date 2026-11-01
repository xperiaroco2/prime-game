class_name ShipCrystalLook
extends RefCounted
## The energy crystal's look (#1556), ported from the art package's `crystal.gd` (prime-game-art
## `assets/prop/energy_crystal/export/`, main 06a42b8e; ARCHITECTURE §11.1): an instance of the
## imported energy_crystal.glb with the shell, core, metal and light materials on by their glTF
## material names, and a small cyan OmniLight3D inside, so a charged crystal lights what is near
## it. One charge drives the two states: 1 charged (cyan, glowing), 0 spent (grey stone, no light,
## the cap's windows at LIGHT_SPENT of their glow); values between fade. A socket or a charger
## seats one on its `crystal_anchor` (seat()); values only: ShipStationLooks drives them from the
## filtered model.

const GLB := "res://assets/environment/energy_crystal/energy_crystal.glb"
const SHELL := preload("res://assets/environment/energy_crystal/crystal_shell.gdshader")
const CORE := preload("res://assets/environment/energy_crystal/crystal_core.gdshader")
const METAL := preload("res://assets/environment/energy_crystal/crystal_metal.gdshader")

const LIGHT_COLOUR := Color(0.0, 0.72, 1.0)
## The cap's windows and lens at full charge, and the share of it they keep when spent.
const LIGHT_ENERGY := 2.2
const LIGHT_SPENT := 0.22
## The crystal's own light at full charge, and its reach.
const OMNI_ENERGY := 2.6
const OMNI_RANGE := 2.4
## The light of a crystal seated in a charger, softened (the charger package's SEATED_OMNI_*).
const SEATED_OMNI_ENERGY := 0.5
const SEATED_OMNI_RANGE := 0.9
const SEATED_OMNI_COLOUR := Color(0.3, 0.78, 1.0)

var _node: Node3D
var _shell: ShaderMaterial
var _core: ShaderMaterial
var _light: StandardMaterial3D
var _omni: OmniLight3D
var _omni_energy := OMNI_ENERGY
var _charge := -1.0


## A new crystal with its look on, charged; null when the GLB has none of the crystal's surfaces
## (CI's Git LFS stand-in). Each crystal has its own materials.
static func apply() -> ShipCrystalLook:
	var scene := load(GLB) as PackedScene
	var root := scene.instantiate() as Node3D if scene != null else null
	if root == null:
		return null
	var look := ShipCrystalLook.new()
	var by_name := look._materials()
	var matched := 0
	var box := AABB()
	var first := true
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i: int in mesh.mesh.get_surface_count():
			var src: Material = mesh.mesh.surface_get_material(i)
			var key: String = src.resource_name if src != null else ""
			if by_name.has(key):
				mesh.set_surface_override_material(i, by_name[key])
				matched += 1
			else:
				push_warning("ShipCrystalLook: no look for surface material '%s'" % key)
		var b: AABB = ShipStationLooks.relative(mesh, root) * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if matched == 0:
		root.free()
		return null
	root.name = "EnergyCrystal"
	look._node = root
	look._omni = OmniLight3D.new()
	look._omni.name = "CrystalLight"
	look._omni.light_color = LIGHT_COLOUR
	look._omni.omni_range = OMNI_RANGE
	look._omni.omni_attenuation = 1.6
	look._omni.shadow_enabled = false
	# In the crystal, under the cap.
	look._omni.position = box.get_center() - Vector3(0.0, box.size.y * 0.12, 0.0)
	root.add_child(look._omni)
	look.set_charge(1.0)
	return look


## The crystal's node (its root, which seat() parents).
func node() -> Node3D:
	return _node


## The crystal's own light.
func omni() -> OmniLight3D:
	return _omni


## Parents the crystal to `anchor` with no offset (the packages' anchors put its tip on their
## collar). Its own light skips the station layer (GROUND: the station's meshes, so its light
## never burns their bronze white, as the art's layer 20 does; the level's lights still reach
## them); `softened` gives it a charger's softer seated light.
func seat(anchor: Node3D, softened: bool) -> void:
	if _node.get_parent() != null:
		_node.get_parent().remove_child(_node)
	anchor.add_child(_node)
	_node.transform = Transform3D.IDENTITY
	_omni.light_cull_mask = _omni.light_cull_mask & ~PhotoLayers.GROUND
	if softened:
		_omni.omni_range = SEATED_OMNI_RANGE
		_omni.light_color = SEATED_OMNI_COLOUR
		_omni_energy = SEATED_OMNI_ENERGY
	var c := _charge
	_charge = -1.0
	set_charge(c)


## The crystal's state: 1 charged, 0 spent, values between fade.
func set_charge(charge: float) -> void:
	var c := clampf(charge, 0.0, 1.0)
	if c == _charge:
		return
	_charge = c
	_shell.set_shader_parameter("charge", c)
	_core.set_shader_parameter("charge", c)
	_light.emission_energy_multiplier = LIGHT_ENERGY * lerpf(LIGHT_SPENT, 1.0, c)
	_omni.light_energy = _omni_energy * c
	_omni.visible = c > 0.001


func charge() -> float:
	return _charge


## Whether the crystal is drawn (a socket's while it holds one, a charger's while it holds one).
func set_shown(on: bool) -> void:
	_node.visible = on


func shown() -> bool:
	return _node.visible


## The shell's, the core's and the cap's light materials (for tests).
func materials() -> Array[Material]:
	return [_shell, _core, _light]


func _materials() -> Dictionary[String, Material]:
	_shell = ShaderMaterial.new()
	_shell.shader = SHELL
	_core = ShaderMaterial.new()
	_core.shader = CORE
	var bronze := ShaderMaterial.new()
	bronze.shader = METAL
	var graphite := ShaderMaterial.new()
	graphite.shader = METAL
	graphite.set_shader_parameter("base_color", Color(0.305, 0.305, 0.318))
	graphite.set_shader_parameter("worn_color", Color(0.68, 0.665, 0.645))
	graphite.set_shader_parameter("metallic", 0.8)
	graphite.set_shader_parameter("roughness", 0.42)
	_light = StandardMaterial3D.new()
	_light.albedo_color = Color(0.02, 0.05, 0.06)
	_light.roughness = 0.2
	_light.emission_enabled = true
	_light.emission = LIGHT_COLOUR
	return {
		"crystal_shell": _shell,
		"crystal_core": _core,
		"crystal_bronze": bronze,
		"crystal_graphite": graphite,
		"crystal_light": _light,
	}
