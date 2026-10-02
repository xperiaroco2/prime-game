class_name MousePointer
extends RefCounted
## The mouse pointer as the game captures and frees it (ARCHITECTURE §4.7): Input.mouse_mode. A
## headless run keeps no mouse mode (Input.mouse_mode reads visible whatever was set, probed on
## 4.7.2), so a test gives Game a subclass that remembers what was asked.


## Captures the pointer for looking around (`on`), or frees it for clicking.
func capture(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
