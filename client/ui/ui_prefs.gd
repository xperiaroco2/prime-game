class_name UiPrefs
extends RefCounted
## The reduced-motion switch every screen's code reads (#289): the Toy press is instant under it
## (ToyPress reads `press_duration_reduced_ms`), and the screens make the connecting spinner half
## speed and the pre game, post game and End fades cuts (the screen issues). It defaults from the
## system's setting; Settings > Accessibility sets and stores it (#491). Large text is GameUi's
## theme swap (GameUi.set_large_text). Static, so a test that sets it calls reset() after.

static var reduced_motion: bool = system_reduced_motion()


## The system's setting as a bool. DisplayServer answers 1 (on), 0 (off) or -1 (unknown: Linux,
## the Steam Deck, a headless run), and -1 is truthy in GDScript, so only 1 means on.
static func system_reduced_motion() -> bool:
	return from_system_answer(DisplayServer.accessibility_should_reduce_animation())


## Maps DisplayServer's answer (1, 0 or -1) to the switch: on only for 1.
static func from_system_answer(answer: int) -> bool:
	return answer == 1


## Back to the system's setting.
static func reset() -> void:
	reduced_motion = system_reduced_motion()
