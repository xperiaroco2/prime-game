extends SceneTree
## Spike (#15): prints the microphones Godot sees, one per line, without starting any of them, so
## a name can be passed to spike/walk/launch.ps1 -MicDevice. Needs a real audio driver:
##   <godot console exe> --display-driver headless --rendering-driver dummy --audio-driver WASAPI
##       --path . -s res://spike/voice/list_mics.gd


func _init() -> void:
	print("MICS driver=%s default='%s'" % [AudioServer.get_driver_name(), AudioServer.input_device])
	for device in AudioServer.get_input_device_list():
		print("MIC %s" % device)
	quit(0)
