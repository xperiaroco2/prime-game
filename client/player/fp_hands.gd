class_name FpHands
extends Node3D
## The first-person hands (#1587; ARCHITECTURE §4.7.69): the art package's viewmodel (concept A,
## prime-game-art#136, its HANDOFF.md) under the local player's camera, at an identity transform,
## its axes the camera's. Every mesh of it, and the crystal it holds, is on PhotoLayers.HANDS
## alone with no shadow, so only FpView's own camera draws it (at the package's 50 degrees) and
## neither the live view nor a picture does.
## - The clips switch by state (clip_for): Idle or Run with an empty hand, Crystal_Idle or
##   Crystal_Run with a crystal, blended over BLEND_S; the run's speed follows the own speed. A
##   hit (play_hit) plays Punch or Crystal_Hit once, then the state's clip again.
## - A held crystal (crystal_charged or crystal_spent) is the energy crystal's own look
##   (ShipCrystalLook) on the package's CrystalSocket, its own light at LIGHT_SHARE of a crystal's
##   in a socket (the engineer's 40 % of 2026-11-18): it lights the room round the eye and never the
##   hands, and on LIVE_AVATAR a picture never draws it. The others see the carried crystal as
##   before (the greybox carried item at the holder).
## - The colour (set_tint): the own body colour (BodyColours) times each material's own albedo, as
##   CharacterRig tints a remote body.
## - Both arms are the package's (its FPArms skin on one rig): where each hand is in a clip, the
##   left too, is the clip's own. The code picks clips and tints and layers every mesh it finds, so
##   a package with both hands in view, or with the arms split into meshes, needs no change here.
## It reads nothing itself: the controller (update) and ItemViews (set_held, set_tint) feed it, and
## Game plays the hit on the host's own Swung. Without the package's nodes (CI's Git LFS stand-in)
## it shows nothing and every call is harmless.

## The package's GLB: a later package from the art repo replaces this one file (and its credits);
## the code uses the HANDOFF's node and clip names only.
const GLB := "res://assets/body/fp_hands/fp_hands.glb"
const IDLE := &"Idle"
const RUN := &"Run"
const PUNCH := &"Punch"
const CRYSTAL_IDLE := &"Crystal_Idle"
const CRYSTAL_RUN := &"Crystal_Run"
const CRYSTAL_HIT := &"Crystal_Hit"
const SOCKET := "CrystalSocket"
## The kinds the hands hold as the energy crystal; any other kind leaves them empty.
const CRYSTAL_KINDS: Array[StringName] = [&"crystal_charged", &"crystal_spent"]
## A switch between two state clips blends over this many seconds (the HANDOFF's 0.15 s).
const BLEND_S := 0.15
## A hit starts nearly at once: its first frames are the state's pose anyway.
const HIT_BLEND_S := 0.05
## The share of ShipCrystalLook.OMNI_ENERGY (a crystal's light in a socket) the held one keeps in
## first person (2026-11-18).
const LIGHT_SHARE := 0.4
## The horizontal speed, m/s, from which the hands run. A look, "not a decision".
const RUN_FROM_MPS := 0.5
## The speed, m/s, at which the run clip (one character Jog cycle) plays at 1. A look.
const RUN_CLIP_MPS := 4.5
## The run clip's speed stays between these. Looks.
const RUN_SCALE_MIN := 0.7
const RUN_SCALE_MAX := 1.6
## The package's default body colour (HANDOFF "The colour slot and the light": sRGB 0.40 0.86
## 0.80), the hands' colour until the own one is known (set_tint).
const DEFAULT_TINT := Color(0.40, 0.86, 0.80)

## The package's scene, loaded once for every controller.
static var _package: PackedScene

## The package's scene instance, null without one.
var model: Node3D
var player: AnimationPlayer
## The package's CrystalSocket (its BoneAttachment3D's child), null without one.
var socket: Node3D
## The held crystal's look, made at the first crystal held; null before (and in CI).
var crystal: ShipCrystalLook
## The hands' own camera over the view (attach), null before.
var view: FpView

var _scene: PackedScene
var _materials: Array[BaseMaterial3D] = []
var _albedo: Array[Color] = []
var _tint := DEFAULT_TINT
var _held: StringName = &""
var _speed := 0.0
var _hitting := false


## Hands from `scene` (tests pass a fixture); the package's GLB by default.
func _init(scene: PackedScene = null) -> void:
	name = "FpHands"
	_scene = scene


func _ready() -> void:
	if model == null:
		build()


## Instances the package once (at _ready, or a test calls it). Without its AnimationPlayer the
## instance is dropped and the hands stay empty.
func build() -> void:
	if model != null:
		return
	var scene := _scene
	if scene == null and _package == null and ResourceLoader.exists(GLB):
		_package = load(GLB) as PackedScene
	if scene == null:
		scene = _package
	if scene == null:
		return
	var made := scene.instantiate() as Node3D
	if made == null:
		return
	var players := made.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		made.free()
		return
	model = made
	model.name = "Model"
	add_child(model)
	player = players[0] as AnimationPlayer
	player.animation_finished.connect(_on_finished)
	socket = model.find_child(SOCKET, true, false) as Node3D
	_set_loops()
	_own_materials()
	PhotoLayers.assign(model, PhotoLayers.HANDS, false)
	_apply_tint()
	_play(clip_for(0.0, false), 0.0)


## The state clip for an own speed of `speed` m/s with a crystal held or not.
static func clip_for(speed: float, crystal_held: bool) -> StringName:
	var running := speed >= RUN_FROM_MPS
	if crystal_held:
		return CRYSTAL_RUN if running else CRYSTAL_IDLE
	return RUN if running else IDLE


## The hit's clip with a crystal held or not.
static func hit_clip(crystal_held: bool) -> StringName:
	return CRYSTAL_HIT if crystal_held else PUNCH


static func is_crystal(kind: StringName) -> bool:
	return CRYSTAL_KINDS.has(kind)


## The run clip's speed at an own speed of `speed` m/s.
static func run_scale(speed: float) -> float:
	return clampf(speed / RUN_CLIP_MPS, RUN_SCALE_MIN, RUN_SCALE_MAX)


## Puts the hands under the player's `camera`, their own camera (a new FpView following it) under
## `holder` (the controller), and leaves the crystal to them: `hand`, the hand item, draws none
## while the package is in.
func attach(holder: Node, camera: Camera3D, hand: FirstPersonHand) -> void:
	camera.add_child(self)
	if model == null:
		return
	if socket != null:
		hand.hidden_kinds = CRYSTAL_KINDS
	view = FpView.new()
	view.source = camera
	holder.add_child(view)


## Every physics frame (the controller's): the own horizontal speed, which the state's clip
## follows, and whether the hands are drawn at all (`shown`: the own player living).
func update(speed: float, shown := true) -> void:
	_speed = speed
	if view != null:
		view.shown = shown
	_follow_state()


## The own hand's item kind (empty: none), from the own ClientModel through ItemViews: a crystal
## kind shows the crystal on the socket and the crystal clips.
func set_held(kind: StringName) -> void:
	if kind == _held:
		return
	_held = kind
	if is_crystal(kind):
		_show_crystal(1.0 if kind == &"crystal_charged" else 0.0)
	elif crystal != null:
		crystal.set_shown(false)
	_follow_state()


## The kind set_held last gave.
func held() -> StringName:
	return _held


## Whether the hands hold a crystal now.
func holds_crystal() -> bool:
	return is_crystal(_held)


## Plays the hit (the host accepted the own Use: its Swung), Punch or Crystal_Hit once.
func play_hit() -> void:
	var clip := hit_clip(holds_crystal())
	if player == null or not player.has_animation(clip):
		return
	_hitting = true
	# A held button chains the hits (each lasts the swing rate): one still ending starts over.
	if StringName(player.current_animation) == clip:
		player.seek(0.0, true)
	else:
		_play(clip, HIT_BLEND_S)


## Tints the hands by the own body colour: each material's own albedo times `colour`.
func set_tint(colour: Color) -> void:
	if colour == _tint:
		return
	_tint = colour
	_apply_tint()


func tint() -> Color:
	return _tint


## The clip playing now, empty without the package.
func current_clip() -> StringName:
	return StringName(player.current_animation) if player != null else &""


func _follow_state() -> void:
	if player == null:
		return
	# A hit ends at animation_finished; one stopped otherwise frees the state all the same.
	if _hitting and not player.is_playing():
		_hitting = false
	if _hitting:
		return
	var clip := clip_for(_speed, holds_crystal())
	if clip != StringName(player.current_animation):
		_play(clip, BLEND_S)
	player.speed_scale = run_scale(_speed) if clip == RUN or clip == CRYSTAL_RUN else 1.0


func _play(clip: StringName, blend: float) -> void:
	if player == null or not player.has_animation(clip):
		return
	player.speed_scale = 1.0
	player.play(clip, blend)


func _on_finished(clip: StringName) -> void:
	if clip == PUNCH or clip == CRYSTAL_HIT:
		_hitting = false
		_follow_state()


func _show_crystal(charge: float) -> void:
	if socket == null:
		return
	if crystal == null:
		crystal = ShipCrystalLook.apply()
		if crystal == null:
			return
		crystal.seat(socket, false)
		PhotoLayers.assign(crystal.node(), PhotoLayers.HANDS, false)
		# Its own light lights the room round the eye (its cull mask reaches GROUND) and never the
		# hands; on LIVE_AVATAR, as a carried item's, the live camera draws it and a picture never.
		var omni := crystal.omni()
		omni.layers = PhotoLayers.LIVE_AVATAR
		omni.light_cull_mask = omni.light_cull_mask & ~PhotoLayers.HANDS
		crystal.set_light_share(LIGHT_SHARE)
	crystal.set_charge(charge)
	crystal.set_shown(true)


func _apply_tint() -> void:
	for i: int in _materials.size():
		_materials[i].albedo_color = _albedo[i] * _tint


## The state clips loop and the hits play once, whatever a package's clip names say (a looping hit
## would never send animation_finished).
func _set_loops() -> void:
	for clip: StringName in [IDLE, RUN, CRYSTAL_IDLE, CRYSTAL_RUN, PUNCH, CRYSTAL_HIT]:
		if player.has_animation(clip):
			var once := clip == PUNCH or clip == CRYSTAL_HIT
			player.get_animation(clip).loop_mode = (
				Animation.LOOP_NONE if once else Animation.LOOP_LINEAR
			)


func _own_materials() -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i: int in mesh.get_surface_override_material_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			if material == null:
				continue
			var own := material.duplicate() as BaseMaterial3D
			mesh.set_surface_override_material(i, own)
			_materials.append(own)
			_albedo.append(own.albedo_color)
