class_name UiPrefs
extends RefCounted
## The reduced-motion switch every screen's code reads (#289): the Toy press is instant under it
## (ToyPress reads `press_duration_reduced_ms`), and the screens make the connecting spinner half
## speed and the pre game, post game and End fades cuts (the screen issues). It defaults from the
## system's setting; Settings > Accessibility sets and stores it (#491). Large text is GameUi's
## theme swap (GameUi.set_large_text). Static, so a test that sets it calls reset() after.

static var reduced_motion := DisplayServer.accessibility_should_reduce_animation()


## Back to the system's setting.
static func reset() -> void:
	reduced_motion = DisplayServer.accessibility_should_reduce_animation()
