class_name LaunchOptions
extends RefCounted
## The command line after -- (ARCHITECTURE §4.7): the game and tools/run/headless_session.gd read
## it alike.
##   --host [--local]    host a session; --local listens on 127.0.0.1 only, else on every interface
##   --join=<address>    join that host
##   --port=<p>          the UDP port (default DEFAULT_PORT)
##   --stop-file=<path>  stop cleanly once this file exists (the runner's Ctrl+C and --seconds)
##   --alive-file=<path> stop once this file is gone or ALIVE_SECONDS old: the runner touches it
##                       every second, so a killed runner leaves no session running
##   --no-replay         the host writes no replay (the runner's selftest)
## With neither --host nor --join the game shows its main menu; the headless session refuses that.

## A placeholder, "not a decision".
const DEFAULT_PORT := 24600
const HOST_ARG := "--host"
const LOCAL_ARG := "--local"
const JOIN_ARG := "--join="
const PORT_ARG := "--port="
const STOP_ARG := "--stop-file="
const ALIVE_ARG := "--alive-file="
const NO_REPLAY_ARG := "--no-replay"
const LOCALHOST := "127.0.0.1"
const EVERY_INTERFACE := "*"
## A host, the game's or the headless session's, prints this once it listens; the runner starts
## the local clients when it reads it (tools/runner/hostjoin.py).
const HOSTING := "session: hosting"
## The runner touches its alive file every second; this much older means it was killed.
const ALIVE_SECONDS := 10

var hosting := false
var joining := false
var port := DEFAULT_PORT
var address := ""
var bind := EVERY_INTERFACE
var stop_file := ""
var alive_file := ""
var replay := true
## What is wrong with the arguments; empty when nothing is.
var problem := ""


## The options in `args`; with `menu_allowed` off, one of --host and --join is required.
static func parse(args: PackedStringArray, menu_allowed := false) -> LaunchOptions:
	var options := LaunchOptions.new()
	options.problem = options._read(args, menu_allowed)
	return options


## Whether the runner asked to stop: its stop file exists.
func stop_requested() -> bool:
	return not stop_file.is_empty() and FileAccess.file_exists(stop_file)


## Whether the runner was killed (an agent's command timeout, a closed terminal): its alive file
## is gone or stale, and nobody would stop this process.
func runner_gone() -> bool:
	if alive_file.is_empty():
		return false
	if not FileAccess.file_exists(alive_file):
		return true
	var age := int(Time.get_unix_time_from_system()) - FileAccess.get_modified_time(alive_file)
	return age > ALIVE_SECONDS


func _read(args: PackedStringArray, menu_allowed: bool) -> String:
	var local := false
	for arg in args:
		if arg == HOST_ARG:
			hosting = true
		elif arg == LOCAL_ARG:
			local = true
		elif arg.begins_with(JOIN_ARG):
			joining = true
			address = arg.trim_prefix(JOIN_ARG)
		elif arg.begins_with(PORT_ARG):
			var text := arg.trim_prefix(PORT_ARG)
			port = text.to_int() if text.is_valid_int() else 0
			if port < 1 or port > 65535:
				return "%s takes a port between 1 and 65535, got '%s'" % [PORT_ARG, text]
		elif arg.begins_with(STOP_ARG):
			stop_file = arg.trim_prefix(STOP_ARG)
		elif arg.begins_with(ALIVE_ARG):
			alive_file = arg.trim_prefix(ALIVE_ARG)
		elif arg == NO_REPLAY_ARG:
			replay = false
		else:
			return "unknown argument '%s'" % arg
	bind = LOCALHOST if local else EVERY_INTERFACE
	return _check(menu_allowed, local)


func _check(menu_allowed: bool, local: bool) -> String:
	if hosting and joining:
		return "give either %s or %s<address>, not both" % [HOST_ARG, JOIN_ARG]
	if not hosting and not joining and not menu_allowed:
		return "give either %s or %s<address>" % [HOST_ARG, JOIN_ARG]
	if joining and address.is_empty():
		return "%s needs the host's address" % JOIN_ARG
	if local and not hosting:
		return "%s is for the host only" % LOCAL_ARG
	return ""
