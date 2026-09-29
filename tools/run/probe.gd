extends SceneTree
## Smoke-test script for `tools/run.py run`: behaves as its first user argument says.
##   godot --headless -s res://tools/run/probe.gd -- <mode> [more args]
## Prints its mode, arguments, display server and PRIME_INSTANCE first. Modes:
##   ok (default)   prints PROBE ok and the user arguments, exits 0
##   exit <n>       exits with code n
##   error          push_error, then exits 0 (the runner must still fail on the ERROR line)
##   script-error   calls a method on null (a SCRIPT ERROR line), then exits 0
##   hang           never quits (the runner must kill it at --seconds)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "ok"
	print(
		(
			"PROBE mode=%s args=%s display=%s instance=%s"
			% [mode, args, DisplayServer.get_name(), OS.get_environment("PRIME_INSTANCE")]
		)
	)
	match mode:
		"ok":
			print("PROBE ok")
			quit(0)
		"exit":
			quit(int(args[1]) if args.size() > 1 else 1)
		"error":
			push_error("PROBE deliberate error")
			quit(0)
		"script-error":
			quit(0)
			var missing: Node = null
			print(missing.get_name())
		"hang":
			print("PROBE hanging")
		_:
			push_error("PROBE unknown mode '%s'" % mode)
			quit(2)
