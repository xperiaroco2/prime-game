class_name ShipZapScreen
extends Node
## The own screen when the ship zaps the player (#1585; GDD §8 "The ship is in an emergency mode",
## ARCHITECTURE §9.5.27): the private ShipZapped starts a short blue full-screen flash, the own
## camera's shake (PlayerController.shake) and the notice on the HUD (notice_showing, read by the
## HUD through ItemWorld.hud_local). Their lengths are the mode's CrystalProblem's
## (`zap_flash_seconds`, `zap_notice_seconds`: the client's own copy); no flash without a value for
## them. Only the carrier gets the event (§5), so a spectator never sees a thing of this; the zap's
## sound is everyone's (ItemPlaced, cause `zapped`). A phase change ends all of it.

## The flash at its peak; it fades over `zap_flash_seconds`. A placeholder, "not a decision" (the
## look is variant B of the card on #1585).
const FLASH_PEAK := Color(0.18, 0.5, 1.0, 0.7)
## Under the game's Ui layer: the flash never covers the notice it announces.
const OVERLAY_LAYER := 0

var player: PlayerController
## The flash over the view (a ColorRect on its own canvas layer), hidden but at a flash.
var overlay := CanvasLayer.new()

var _blue := ColorRect.new()
var _flash_seconds := 0.0
var _notice_seconds := 0.0
var _flash_left := 0.0
var _notice_left := 0.0


func _init() -> void:
	name = "ShipZapScreen"
	overlay.name = "ZapFlash"
	overlay.layer = OVERLAY_LAYER
	overlay.visible = false
	_blue.name = "Blue"
	_blue.color = Color(FLASH_PEAK, 0.0)
	_blue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blue.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(_blue)
	add_child(overlay)
	set_process(false)


## The zap's numbers of `game_mode`'s crystal kind; none (no ship's engine): nothing ever starts.
func set_mode(game_mode: GameMode) -> void:
	var kind := crystal_of(game_mode)
	_flash_seconds = kind.zap_flash_seconds if kind != null else 0.0
	_notice_seconds = kind.zap_notice_seconds if kind != null else 0.0


## The crystal kind of `game_mode`'s ship engine, or null.
static func crystal_of(game_mode: GameMode) -> CrystalProblem:
	if game_mode == null:
		return null
	for type: TaskType in game_mode.task_types:
		var engine := type as ShipEngine
		if engine == null:
			continue
		for kind: ProblemKind in engine.kinds:
			if kind is CrystalProblem:
				return kind as CrystalProblem
	return null


func on_event(event_name: StringName, _fields: Dictionary) -> void:
	if event_name == &"PhaseChanged":
		_stop()
	elif event_name == &"ShipZapped":
		_start()


func notice_showing() -> bool:
	return _notice_left > 0.0


func flash_alpha() -> float:
	return _blue.color.a if overlay.visible else 0.0


func _start() -> void:
	_flash_left = _flash_seconds
	_notice_left = _notice_seconds
	overlay.visible = _flash_left > 0.0
	set_process(true)
	if player != null and _flash_seconds > 0.0:
		player.shake(_flash_seconds)
	_show_flash()


func _stop() -> void:
	_flash_left = 0.0
	_notice_left = 0.0
	overlay.visible = false
	set_process(false)


func _process(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	_notice_left = maxf(0.0, _notice_left - delta)
	_show_flash()
	if _flash_left <= 0.0 and _notice_left <= 0.0:
		set_process(false)


func _show_flash() -> void:
	overlay.visible = _flash_left > 0.0
	if _flash_seconds > 0.0:
		_blue.color = Color(
			FLASH_PEAK, FLASH_PEAK.a * clampf(_flash_left / _flash_seconds, 0.0, 1.0)
		)
