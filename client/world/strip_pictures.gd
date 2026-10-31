class_name StripPictures
extends Node3D
## The booth strips' pictures (#1397, ARCHITECTURE §4.7.62), rendered on this client from the
## session's FLASH records (BoothBook), as the photo's pictures are (§4.7.58). Nothing is rendered
## while a session runs or before a strip is asked for: the first texture_of of a printed session
## queues it, and then one frame renders a process frame in a SubViewport with its own World3D (no
## level, no live body: nothing of the hall can show, and no live camera sees the puppets), lit by
## its own light and backdrop, its Camera3D at StripLayout.camera_transform, a puppet per row
## (PuppetBodies, in the row's own colour at the flash, placed by StripLayout.local_row). After
## `drawn` the frame is read back (`reader`), the viewport freed; after the last frame StripLayout
## composes the strip, kept as one texture per session while BoothBook holds the session. Headless
## (`enabled` false) nothing renders. The light and backdrop are placeholders, "not a decision".

## The backdrop and the light. Placeholders in the Toy style.
const BACKDROP := Color(0.85, 0.82, 0.92)
const AMBIENT := Color(0.6, 0.6, 0.65)
const LIGHT_ENERGY := 1.2

var book: BoothBook
var mode: GameMode
## The live avatars' rules and character, which the puppets copy; null: the mode's rules.
var avatars: AvatarViews
## Whether pictures are rendered: never on a headless client.
var enabled := DisplayServer.get_name() != "headless"
## The signal a render waits for before it reads the frame back (tests inject their own).
var drawn: Signal = RenderingServer.frame_post_draw
## Reads a drawn SubViewport into an Image (tests inject one); unset: its texture's image.
var reader := Callable()

## The composed strips by session instance id.
var _strips: Dictionary[int, Strip] = {}
var _queue: Array[BoothBook.Session] = []
var _job: Job


## A composed strip.
class Strip:
	extends RefCounted
	var session: BoothBook.Session
	var texture: ImageTexture


## The session being rendered, a frame at a time.
class Job:
	extends RefCounted
	var session: BoothBook.Session
	var index := 0
	var images: Dictionary[int, Image] = {}
	var viewport: SubViewport
	var puppets: Array[RemotePlayerBody] = []


## Session `session`'s strip texture; null until it is composed (the first ask queues it, only
## once it printed).
func texture_of(session: BoothBook.Session) -> Texture2D:
	if session == null:
		return null
	var strip: Strip = _strips.get(session.get_instance_id())
	if strip != null and strip.session == session:
		return strip.texture
	if (
		enabled
		and session.state == BoothBook.State.PRINTED
		and not _queue.has(session)
		and (_job == null or _job.session != session)
	):
		_queue.append(session)
	return null


func has_picture(session: BoothBook.Session) -> bool:
	return session != null and _strips.has(session.get_instance_id())


## Strips composed and kept.
func count() -> int:
	return _strips.size()


## Sessions queued or in hand.
func pending() -> int:
	return _queue.size() + (1 if _job != null else 0)


## The frame render in hand's viewport, or null (tests).
func rendering() -> SubViewport:
	return _job.viewport if _job != null else null


## The frame render in hand's puppets (tests).
func puppets() -> Array[RemotePlayerBody]:
	return _job.puppets if _job != null else ([] as Array[RemotePlayerBody])


## Forgets every strip and render.
func clear() -> void:
	_queue.clear()
	if _job != null:
		_free(_job)
		_job = null
	_strips.clear()


func _process(_delta: float) -> void:
	if book == null:
		if _job != null or not _queue.is_empty() or not _strips.is_empty():
			clear()
		return
	for id: int in _strips.keys():
		if not book.holds(_strips[id].session):
			_strips.erase(id)
	for session: BoothBook.Session in _queue.duplicate():
		if not book.holds(session):
			_queue.erase(session)
	if _job != null and _job.viewport == null:
		if not book.holds(_job.session):
			_job = null
		else:
			_next_frame(_job)
	elif _job == null and not _queue.is_empty():
		var job := Job.new()
		job.session = _queue.pop_front()
		_job = job
		_next_frame(job)


## Renders the job's next frame with a record, or composes the strip after the last.
func _next_frame(job: Job) -> void:
	var frames := job.session.frame_count()
	while job.index < frames and job.session.record_of(job.index).is_empty():
		job.index += 1
	if job.index >= frames:
		var strip := Strip.new()
		strip.session = job.session
		strip.texture = ImageTexture.create_from_image(StripLayout.compose(frames, job.images))
		_strips[job.session.get_instance_id()] = strip
		_job = null
		return
	_start(job)


func _start(job: Job) -> void:
	var viewport := SubViewport.new()
	viewport.name = "StripFrame%d" % job.index
	viewport.size = StripLayout.FRAME_PX
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.own_world_3d = true
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKDROP
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.light_energy = LIGHT_ENERGY
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.fov = StripLayout.CAMERA_FOV_DEG
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	viewport.add_child(camera)
	camera.global_transform = StripLayout.camera_transform()
	camera.current = true
	var rules: PlayerRules = avatars.rules if avatars != null else null
	if rules == null and mode != null:
		rules = mode.player_rules
	var character: CharacterSet = avatars.character if avatars != null else null
	var rows := job.session.record_of(job.index)
	var view := StripLayout.view_of(rows)
	for row: Dictionary in rows:
		var local := StripLayout.local_row(row, view)
		var colour := BodyColours.of(row.get("colour", 0) as int)
		job.puppets.append(PuppetBodies.make(local, viewport, rules, character, colour))
	job.viewport = viewport
	_finish(job, viewport)


## Waits for the draw, keeps the frame, frees the render; nothing when the job was dropped.
func _finish(job: Job, viewport: SubViewport) -> void:
	await drawn
	if _job != job or job.viewport != viewport:
		return
	var image: Image = null
	if reader.is_valid():
		image = reader.call(viewport) as Image
	elif viewport.get_texture() != null:
		image = viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		job.images[job.index] = image
	_free(job)
	job.index += 1


func _free(job: Job) -> void:
	for puppet: RemotePlayerBody in job.puppets:
		if is_instance_valid(puppet):
			puppet.queue_free()
	job.puppets.clear()
	if is_instance_valid(job.viewport):
		job.viewport.queue_free()
	job.viewport = null
