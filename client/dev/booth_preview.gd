extends Node3D
## A preview of the photo booth's client (#1397, ARCHITECTURE §4.7.62) for `tools\run.cmd shot`:
## the base mode's booth driven by BoothBook, BoothViews and StripPictures from a fake
## ClientModel, three players in its cylinder. `stage` picks the moment: "flash" (the own player
## in the frame: the lamp flares and the white fades over the view), "print" (the players
## have stepped out, the lamp is gone, the strip prop slides out of the slot) or "strip" (the
## three frames rendered from the records, the strip's image on the left and the strip's card on
## the right). With `character` the puppets wear the art's character
## (CharacterSet.load_default(), the game's case). The greybox booth and the room are the
## preview's own. Dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const OWN := 1
const BOOTH := 4
const SESSION := 1
const STRIP_ID := 40
const FRAMES := 3
const BOOTH_AT := Vector3(0, 0, 0)
## The preview's own greybox booth 2.5 m behind the marker, as the hall's PhotoBooth box stands.
const BOOTH_BOX := Vector3(2.0, 2.4, 0.6)
## Where the players stand and face, frame by frame (peer, offset from the marker, facing).
const PLAYERS: Array[Array] = [
	[OWN, Vector3(-0.6, 0, 0.1), Vector3(0.1, 0, 1)],
	[2, Vector3(0.0, 0, 0.3), Vector3(0, 0, 1)],
	[3, Vector3(0.6, 0, 0.0), Vector3(-0.2, 0, 1)],
]
## Mid-print: how far the prop has slid when the shot is taken, in seconds.
const PRINT_AGE := 0.6

## "flash", "print" or "strip".
@export var stage := "flash"
## The puppets wear the art's character, as in the game (needs the Git LFS content).
@export var character := false

var _model: ClientModel
var _book := BoothBook.new()
var _views := BoothViews.new()
var _strips := StripPictures.new()
var _shown: TextureRect
var _card: Node3D
var _avatars: AvatarViews


func _ready() -> void:
	var mode := load(Preview.MODE) as GameMode
	_model = ClientModel.new(mode)
	_model.own_peer = OWN
	_fold(PhaseChangedEvent.new(&"lobby", 100000))
	_room()
	_fold(StationPlacedEvent.new(BOOTH, &"booth", Color.WHITE, BOOTH_AT))
	_views.model = _model
	_views.book = _book
	_views.host_tick = func() -> int: return 100
	add_child(_views)
	_strips.book = _book
	_strips.mode = mode
	if character:
		_avatars = AvatarViews.new()
		_avatars.character = CharacterSet.load_default()
		_strips.avatars = _avatars
	add_child(_strips)
	var started := BoothStepEvent.new(BOOTH, SESSION, BoothStepEvent.STARTED)
	started.presser = OWN
	started.frames = FRAMES
	started.countdown = 3 * Ticks.RATE
	started.gap = 2 * Ticks.RATE
	_fold(started)
	var flashes := FRAMES if stage != "flash" else 1
	for frame: int in flashes:
		var flash := BoothStepEvent.new(BOOTH, SESSION, BoothStepEvent.FLASH)
		flash.frame = frame
		flash.record = _record(frame)
		_fold(flash)
	if stage != "flash":
		_fold(ItemSpawnedEvent.new(STRIP_ID, StripLooks.STRIP, BOOTH_AT))
		_fold(ItemPickedUpEvent.new(OWN, STRIP_ID))
		var printed := BoothStepEvent.new(BOOTH, SESSION, BoothStepEvent.PRINTED)
		printed.items = PackedInt32Array([STRIP_ID])
		_fold(printed)
	# The moment is held still: the preview ages it by hand, never by the frame clock.
	_views.set_process(false)
	if stage == "print":
		_views.advance(PRINT_AGE)
	elif stage == "strip":
		# The flash and the print are over: only the strip shows.
		_views.advance(BoothViews.PRINT_SECONDS + 1.0)
	else:
		_bodies(mode)
	var camera := Camera3D.new()
	add_child(camera)
	if stage == "strip":
		_card = StripLooks.build(StripLooks.STRIP)
		_card.position = Vector3(0.05, 1.0, 0)
		_card.rotation = Vector3(PI * 0.5, 0, 0)
		add_child(_card)
		camera.look_at_from_position(Vector3(0, 1.0, 0.32), Vector3(0, 1.0, 0))
	elif stage == "print":
		camera.look_at_from_position(Vector3(0.5, 1.1, 1.0), Vector3(0, 0.75, 0))
	else:
		camera.look_at_from_position(Vector3(0.4, 1.7, 4.2), Vector3(0, 1.0, 0))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_shown = TextureRect.new()
	_shown.anchor_right = 0.5
	_shown.anchor_bottom = 1.0
	_shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shown.visible = stage == "strip"
	layer.add_child(_shown)


func _process(_delta: float) -> void:
	if stage != "strip":
		return
	var texture := _strips.texture_of(_book.session_of(STRIP_ID))
	if texture != null and _shown.texture == null:
		_shown.texture = texture
		PhotoLooks.set_picture(_card, texture)


func _exit_tree() -> void:
	if _avatars != null:
		_avatars.free()


## The record of flash `frame`: the third player crouches in the last frame.
func _record(frame: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for player: Array in PLAYERS:
		var peer := player[0] as int
		var row := {
			"peer": peer,
			"colour": peer - 1,
			"position": BOOTH_AT + (player[1] as Vector3),
			"facing": (player[2] as Vector3).normalized(),
			"crouched": frame == FRAMES - 1 and peer == 3,
			"sneaking": false,
			"posed": false,
			"limp": false,
		}
		rows.append(row)
	return rows


## The players standing in the booth, for the flash and the print (the record's last rows).
func _bodies(mode: GameMode) -> void:
	var character_set: CharacterSet = null
	if _avatars != null:
		character_set = _avatars.character
	for row: Dictionary in _record(0):
		var colour := BodyColours.of(row["colour"] as int)
		PuppetBodies.make(row, self, mode.player_rules, character_set, colour)


func _fold(event: MatchEvent) -> void:
	var fields := event.to_dict()
	_model.fold(event.event_name(), fields)
	_book.fold(event.event_name(), fields)
	_views.on_event(event.event_name(), fields)


func _room() -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(10, 0.1, 10)
	var view := MeshInstance3D.new()
	view.mesh = floor_mesh
	view.position = Vector3(0, -0.05, 0)
	add_child(view)
	var box_mesh := BoxMesh.new()
	box_mesh.size = BOOTH_BOX
	var box := MeshInstance3D.new()
	box.mesh = box_mesh
	box.position = BOOTH_AT + Vector3(0.5, BOOTH_BOX.y * 0.5, -2.5)
	add_child(box)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.6
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.4, 0.4, 0.45)
	add_child(environment)
