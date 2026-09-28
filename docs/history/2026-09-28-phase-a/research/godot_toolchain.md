# Godot 4.7 CLI toolchain for agent self-verification

## Summary

I verified everything against the local Godot 4.7.2 console exe in a scratch project, plus current primary sources: Godot 4.7 docs, GitHub releases and issues, and the Claude Code docs. The CLI is enough for self-verification. No MCP server is needed. Several traps would make naive checks pass on broken code or hang:

- `--import` exits 0 even when scripts have parse errors.
- `load()` returns a non-null script for files with parse errors.
- A runtime error before `quit()` in a `-s` script hangs the process forever. `push_error` and runtime errors never change the exit code.
- `-d` drops into an interactive `debug>` prompt and hangs.
- Warn-level warnings are invisible to `--check-only` unless `-d` is used, and `-d` hangs on parse errors.

What works:
- `--check-only -s res://file.gd` (about 0.3 s per file, exit 1 on error) is a reliable per-file check, but only after `--import` has built the `class_name` cache.
- Warnings set to level 2 in `project.godot` become real parse errors. The 4.7 `directory_rules` default already exempts `res://addons`.
- A project-wide check needs a small custom SceneTree script that uses `can_instantiate()` and an `OS.add_logger` Logger.
- gdtoolkit 4.5.0 is the latest release (2025-10) and has no commits since. It handles the 4.5+ syntax I tested (`@abstract`, variadic functions, typed dictionaries, `when` guards). It has open formatter-correctness issues, a concurrency race, and on Windows it writes CRLF.
- GdUnit4 6.2.1 works headless on 4.7.2 with `--ignoreHeadlessMode`. Exit codes: 0 pass, 100 fail, 101 orphans, 103 headless blocked, 105 script errors. It is fail-fast by default (use `-c`) and writes JUnit `results.xml`. Its console summary line can say PASSED wrongly (issue #1330).
- Screenshots work only in a windowed run (d3d12, vulkan and opengl3 all worked, even with the window minimized). Headless capture returns a null texture or hangs.
- Godot 4.7.2 is available for CI through setup-godot v2.4.2 (from godot-builds) and the godot-ci:4.7.2 image.
- There is no official GDScript LSP plugin. Claude Code runs every LSP server over stdio while Godot's LSP is TCP, so only small, unvetted community bridges exist.

## Facts (with verification)

- **godot_toolchain-01** [confirmed] Local engine reports version string '4.7.2.stable.official.ed1daf0bf'. GODOT_BIN points to D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe.  
  src: local-test: & $env:GODOT_BIN --version (local-test)
- **godot_toolchain-02** [confirmed] 4.7.2-stable was published 2026-08-18 on godotengine/godot and godotengine/godot-builds. Assets include Godot_v4.7.2-stable_win64.exe.zip, Godot_v4.7.2-stable_linux.x86_64.zip, Godot_v4.7.2-stable_export_templates.tpz and SHA512-SUMS.txt.  
  src: https://github.com/godotengine/godot/releases/tag/4.7.2-stable (repo)
- **godot_toolchain-03** [confirmed] Local 4.7.2 --help lists these flags:
- --headless ('--display-driver headless --audio-driver Dummy').
- --quit and --quit-after <int> (iterations).
- --log-file <file>.
- --write-movie <file>.
- --check-only [X] 'Only parse for errors and quit (use with --script)'.
- --import [E] 'Starts the editor, waits for any resources to be imported, and then quits'.
- --display-driver ['windows' ('vulkan','d3d12','opengl3','opengl3_angle','dummy'), 'headless' ('dummy')] and --audio-driver ['WASAPI','Dummy'].
- --no-header, --lsp-port, --dap-port, --dump-extension-api[-with-docs], --doctool.
In a local test, --log-file <path> captured push_error output together with its GDScript backtrace.  
  src: local-test: "$GODOT_BIN" --help ; "$GODOT_BIN" --headless --no-header --path . --log-file out/run.log -s res://tools/push_err.gd (local-test)
- **godot_toolchain-04** [confirmed] The official 4.7 command-line docs say:
- -s scripts 'must inherit from SceneTree or MainLoop'.
- --import 'Implies --editor and --quit'.
- '--headless command line argument is required on platforms that do not have GPU access (such as continuous integration)'.  
  src: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html (official-docs)
- **godot_toolchain-05** [confirmed] --check-only also works on non-MainLoop scripts. The script res://src/ok.gd extends RefCounted and exits 0. A parse error exits 1 and prints 'SCRIPT ERROR: Parse Error: <msg>' followed by 'at: GDScript::reload (res://file.gd:LINE)'. Godot 3 idioms fail with explicit messages, e.g. 'The "onready" keyword was removed in Godot 4. Use the "@onready" annotation instead.' Each process checks one script and takes about 300 ms.  
  src: local-test: "$GODOT_BIN" --headless --no-header --path . --check-only -s res://src/<file>.gd (local-test)
- **godot_toolchain-06** [confirmed] --check-only resolves class_name only through .godot/global_script_class_cache.cfg. In a fresh project it fails with 'Identifier "OkThing" not declared in the current scope' (exit 1), and after `--headless --import` the same file exits 0. A newly added class_name fails ('Could not find type "NewThing" in the current scope') until import is re-run.  
  src: local-test: "$GODOT_BIN" --headless --no-header --path . --check-only -s res://src/uses_class.gd (before/after --import) (local-test)
- **godot_toolchain-07** [confirmed] `--headless --path . --import` exited 0 and printed no script errors while the project contained 6 scripts with parse errors, so it is not a parse check. It generated the missing *.gd.uid files and the class cache, and took about 3.5 s on a tiny project.  
  src: local-test: "$GODOT_BIN" --headless --path . --import (local-test)
- **godot_toolchain-08** [corrected] load()/ResourceLoader.load() returns a non-null GDScript even for scripts with parse errors. A null-check-only checker reported 0 failures out of 9 files when 6 were broken. GDScript.can_instantiate() returned false for all 6 broken scripts and true for the valid ones. @abstract scripts also return false, so combine it with is_abstract().  
  src: local-test: "$GODOT_BIN" --headless --no-header --path . -s res://tools/check3.gd (local-test)
  - CORRECTED: load() returns a non-null GDScript for broken scripts, and can_instantiate() is false for them. On 4.7.2, however, can_instantiate() returns TRUE for valid @abstract scripts (is_abstract()=true). A broken @abstract script returns can_instantiate()=false and is_abstract()=false. The is_abstract() guard is therefore unnecessary but harmless.
  - note: The researcher's own check3.log contains no abstract scripts, so the abstract part was never tested.
  - evidence: local-test: -s tools/dbg_abs.gd on res://src/abstract_base.gd (can_inst=true, is_abstract=true) and res://src/abs_broken.gd (false/false)
- **godot_toolchain-09** [confirmed] A Logger subclass registered with OS.add_logger() captured 15 error events while loading the broken scripts. Its override was _log_error(function, file, line, code, rationale, editor_notify, error_type, script_backtraces: Array[ScriptBacktrace]). The docs say the callbacks run on other threads (use a Mutex) and must not call logging functions themselves.  
  src: https://docs.godotengine.org/en/stable/classes/class_logger.html ; local-test: "$GODOT_BIN" --headless --no-header --path . -s res://tools/check4.gd (official-docs)
- **godot_toolchain-10** [corrected] Exit codes of -s scripts:
- A runtime error in _initialize aborts that function, so quit() is never reached and the process runs until killed (timeout exit 124).
- A runtime error in _process prints the error and the process exits 0.
- push_error() followed by quit() exits 0.
- A parse error in the main -s script exits 1.
- An engine crash prints CrashHandlerException and exits 139 under Git Bash.  
  src: local-test: timeout 20 "$GODOT_BIN" --headless --no-header --path . -s res://tools/{rt_err,rt_err_proc,push_err,main_parse_err}.gd (local-test)
  - CORRECTED: These are confirmed: a runtime error in _initialize hangs (124), a runtime error in _process exits 0, push_error+quit exits 0, and a main-script parse error exits 1. Crash codes vary: a headless write-movie segfault gave 139 in Git Bash, OS.crash() gave 132 in Git Bash, and OS.crash() gave -1073741795 (0xC000001D) in PowerShell. Treat any code other than 0 or an expected code as a crash.
  - evidence: local-test: timeout 15 "$GODOT_BIN" --headless -s res://tools/rt/{rt_err,rt_err_proc,push_err,main_parse_err,crash}.gd ; PowerShell & $env:GODOT_BIN ... ; $LASTEXITCODE
- **godot_toolchain-11** [confirmed] With -d (local stdout debugger), a runtime or parse error opens 'Debugger Break ... debug>' and hangs even with stdin at /dev/null, including --check-only on a parse error. GdUnit4's runtest.cmd avoids this with `--remote-debug tcp://127.0.0.1:0`, which prints two harmless ERROR lines ('remote port number must be between 1 and 65535', 'Unable to connect to host 127.0.0.1:0').  
  src: local-test: timeout 30 "$GODOT_BIN" --headless -d --path . --check-only -s res://src/syntax_err.gd ; D:/prime-game/addons/gdUnit4/runtest.cmd (local-test)
- **godot_toolchain-12** [corrected] --check-only does not print Warn-level (1) warnings. With -d they print as 'WARNING: <msg> at: GDScript::reload (res://file.gd:LINE)' (exit 0), but -d hangs on parse errors, and -d with --remote-debug to port 0 suppresses them again. From the CLI, only Error-level (2) warnings are reliably visible to a machine.  
  src: local-test: "$GODOT_BIN" --headless --no-header [-d] [--remote-debug tcp://127.0.0.1:0] --path . --check-only -s res://src/warn_only.gd (local-test)
  - CORRECTED: --check-only alone does not print Warn-level warnings, and bare -d hangs on parse errors. However '-d --ignore-error-breaks' does NOT hang: a parse error exits 1 and a runtime error in _process exits 0. It also prints Warn-level warnings as 'WARNING: <msg> at: GDScript::reload (res://f.gd:L)' with exit 0, and delivers them to an OS.add_logger Logger as error_type=1 with code=<WARNING_NAME>. Warn-level warnings are therefore machine-visible from the CLI.
  - note: This removes the premise of recommendation 3 (binary policy).
  - evidence: local-test: "$GODOT_BIN" --headless -d --ignore-error-breaks --check-only -s res://src/{syntax_err,warn_only}.gd ; -s tools/wlog.gd ; https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html (--ignore-error-breaks)
- **godot_toolchain-13** [corrected] Warning settings in 4.7.2 are debug/gdscript/warnings/<name> with Ignore=0, Warn=1, Error=2, plus 'enable' (bool) and 'directory_rules' (Dictionary). There is no global 'treat warnings as errors' key.
- Default 0: untyped_declaration, inferred_declaration, unsafe_property_access, unsafe_method_access, unsafe_cast, unsafe_call_argument, return_value_discarded, missing_await.
- Default 2: inference_on_variant, native_method_override, get_node_default_without_onready, onready_with_export.
- Everything else is 1, including unsafe_void_return, integer_division, narrowing_conversion, unused_parameter, shadowed_variable, redundant_await, confusable_capture_reassignment and confusable_temporary_modification.  
  src: local-test: "$GODOT_BIN" --headless --path . -s res://dump_settings.gd (iterates ProjectSettings.get_property_list()) (local-test)
  - CORRECTED: Keys are debug/gdscript/warnings/<name> (0/1/2), plus the bools 'enable' and 'renamed_in_godot_4_hint' and the Dictionary 'directory_rules'. There is no treat-warnings-as-errors key. The default-0 and default-2 lists are exactly as stated, and everything else is 1.
  - evidence: local-test: -s tools/dump_settings.gd (ProjectSettings.get_property_list) ; https://docs.godotengine.org/en/stable/classes/class_projectsettings.html
- **godot_toolchain-14** [corrected] With [debug] gdscript/warnings/untyped_declaration=2 in project.godot, --check-only fails (exit 1) with 'Variable "x" has no static type. (Warning treated as error.)'. With unsafe_method_access=2, calling a method on a Variant fails with 'The method "do_thing()" is not present on the inferred type "Variant" ... (Warning treated as error.)'. `var y := a` with untyped `a` fails by default through inference_on_variant=2.  
  src: local-test: "$GODOT_BIN" --headless --no-header --path . --check-only -s res://src/untyped2.gd (local-test)
  - CORRECTED: untyped_declaration=2 and unsafe_method_access=2 produce the quoted '(Warning treated as error.)' failures. untyped_declaration also flags untyped parameters ('Parameter "a" has no static type'). `var y := a` with an UNTYPED `a` is a hard analyzer error ('Cannot infer the type of "y" variable because the value doesn't have a set type.') that fails even with inference_on_variant=0. inference_on_variant=2 governs the case where `a: Variant` is explicitly typed.
  - evidence: local-test: --check-only -s res://src/{untyped,unsafe_method,infer_variant,infer_hard_variant}.gd with and without [debug] overrides
- **godot_toolchain-15** [confirmed] debug/gdscript/warnings/directory_rules defaults to { "res://addons": 0 }, with the hint 'Exclude,Include' (0 = Exclude). The same untyped file passed --check-only under res://addons/fake/ and failed under res://src/.  
  src: https://docs.godotengine.org/en/stable/classes/class_projectsettings.html ; local-test: --check-only -s res://addons/fake/untyped_addon.gd (official-docs)
- **godot_toolchain-16** [corrected] Windowed screenshots work from the console exe on Windows. A SceneTree script that adds a scene, awaits a few process_frame, awaits RenderingServer.frame_post_draw, then calls root.get_viewport().get_texture().get_image().save_png(path) produced a correct 640x360 PNG. This worked with d3d12 (forward_plus), vulkan and opengl3 (gl_compatibility), and also after DisplayServer.window_set_mode(WINDOW_MODE_MINIMIZED).  
  src: local-test: "$GODOT_BIN" --no-header --path . [--rendering-driver d3d12|opengl3] --resolution 640x360 -s res://tools/shot.gd -- res://scenes/box.tscn <abs>/out/x.png 5 (local-test)
  - CORRECTED: A windowed (not minimized) SceneTree shot script produces a correct PNG at the requested --resolution. If the script calls window_set_mode(WINDOW_MODE_MINIMIZED), frame_post_draw never fires and the process hangs until the timeout. This happened with vulkan, d3d12 and opengl3, including with the researcher's own shot_min.gd. An off-screen window ('--position -30000,-30000') rendered a correct 640x360 image and does not cover the human's screen.
  - evidence: local-test: timeout 40 "$GODOT_BIN" --no-header --path . [--rendering-driver d3d12|opengl3] --resolution 640x360 -s res://tools/shot_min.gd -- res://scenes/box.tscn out/m.png 5 (rc=124 x3) ; same with --position -30000,-30000 and shot_plain.gd (rc=0, PNG verified)
- **godot_toolchain-17** [confirmed] Under --headless the viewport texture is null ('ERROR: Parameter "t" is null', empty Image), and awaiting RenderingServer.frame_post_draw never resumes, so the process hangs until the timeout.  
  src: local-test: timeout 60 "$GODOT_BIN" --headless --path . -s res://tools/shot.gd -- res://scenes/box.tscn out/headless.png 5 (local-test)
- **godot_toolchain-18** [confirmed] A windowed `--write-movie out/movie.png --fixed-fps 10 --quit-after 3 res://scenes/box.tscn` wrote movie00000000.png to movie00000002.png plus movie.wav. The frames were 1152x648 (project viewport size) even though --resolution 640x360 was passed. `--headless --write-movie` crashed with exit 139.  
  src: local-test: "$GODOT_BIN" --no-header --path . --resolution 640x360 --write-movie <abs>/out/movie.png --fixed-fps 10 --quit-after 3 res://scenes/box.tscn (local-test)
- **godot_toolchain-19** [confirmed] Files written inside the project tree get imported: --import created *.png.import and *.wav.import next to the outputs, plus .godot/imported entries. A folder containing an empty .gdignore was skipped.  
  src: local-test: "$GODOT_BIN" --headless --path . --import (out/ vs out2/.gdignore) (local-test)
- **godot_toolchain-20** [confirmed] `--headless --dump-extension-api-with-docs` writes extension_api.json (11.9 MB, 1.6 s) with header version 4.7.2 stable: 1036 classes, 38 builtin classes, 41 singletons. For example, Node has rpc_config and has no set_network_master.  
  src: local-test: cd <dir>; "$GODOT_BIN" --headless --no-header --dump-extension-api-with-docs (local-test)
- **godot_toolchain-21** [corrected] The 4.7 migration guide lists these GDScript breaking changes:
- Overrides of typed-return methods inherit the return type, so an explicit return is required.
- Setting a packed-array element no longer calls the whole property's setter.
- A RichTextLabel enum field was renamed.
It lists no CLI, headless, warning-setting, LSP or movie-maker breaking changes.  
  src: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html (official-docs)
  - CORRECTED: The three GDScript items are correct, and there are no CLI, headless, warning, LSP or movie-maker changes. The guide also lists items this project cares about: the AudioStreamPlayer2D/3D default area_mask changed from 1 to 0 (GH-107679, which matters for proximity voice and audio areas); Jolt Physics behaviour changes (WorldBoundaryShape3D sign, SoftBody3D mass, linear_stiffness, Area3D overlaps with SoftBody3D), and the project uses Jolt; mouse and keyboard device IDs changed to InputEvent.DEVICE_ID_MOUSE/KEYBOARD; AudioEffectSpectrumAnalyzer.tap_back_pos was removed; Object.is_class now takes a StringName.
  - evidence: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html ; https://github.com/godotengine/godot/pull/107679
- **godot_toolchain-22** [confirmed] gdtoolkit's latest release is 4.5.0 (2025-10-09), which added support for @abstract functions and variadic functions. Earlier releases added typed dictionaries (4.3.2), 'is not' (4.3.1) and guarded match branches (4.3.0). There have been no commits on master since 2025-10-10 (checked 2026-09-28).  
  src: https://github.com/Scony/godot-gdscript-toolkit/blob/master/CHANGELOG.md (changelog)
- **godot_toolchain-23** [confirmed] Local gdformat/gdlint 4.5.0 test on samples that are valid in Godot 4.7.2:
- Syntax covered: @abstract class_name and @abstract func, inner @abstract class, variadic '...rest: Array', Dictionary[String, int], match 'when' guard, r"raw" string, 'is not', @warning_ignore_start/@warning_ignore_restore, @export_tool_button.
- All samples parsed. The formatted output passed Godot --check-only again, and formatting was idempotent.
- gdformat rewrote a two-line '@abstract' + 'class_name X' into '@abstract class_name X', and 'class Impl extends Base:' into a two-line form.
- The default gdlint class-definitions-order flagged 'static var' placed after '@export var'.  
  src: local-test: "$GDTOOLKIT_DIR/gdformat.exe" --check --diff syn/*.gd ; "$GDTOOLKIT_DIR/gdlint.exe" syn/*.gd ; then --check-only on formatted copies (local-test)
- **godot_toolchain-24** [confirmed] Open gdtoolkit issues:
- #424: gdformat emits closing-paren indentation that Godot rejects after multiline lambdas (reporter verified against Godot 4.7).
- #428: concurrent gdlint and gdformat race on the grammar-cache makedirs ('Cannot open file ...: File exists').
- #395: excluded_directories is ignored when files are passed explicitly.
- #430: gdlint rejects an @abstract func ending with ';'.
- #419: off-by-one line length on @abstract func.
- #414: LF converted to CRLF on Windows.  
  src: https://github.com/Scony/godot-gdscript-toolkit/issues (issue)
- **godot_toolchain-25** [confirmed] On Windows, gdformat 4.5.0 writes a reformatted file with CRLF line endings (LF in, CRLF out). gdformat --check returns 0 on both the CRLF and LF variants.  
  src: local-test: printf LF file | gdformat lf.gd ; file lf.gd -> 'with CRLF line terminators' (local-test)
- **godot_toolchain-26** [confirmed] The default gdlintrc and gdformatrc (from --dump-default-config) exclude only .git. gdlint over addons/gdUnit4 reports 1101 problems, and gdformat --check would reformat 212 of 236 files.  
  src: local-test: gdlint addons/gdUnit4 ; gdformat --check addons/gdUnit4 ; gdlint --dump-default-config (local-test)
- **godot_toolchain-27** [confirmed] Timings on this machine: gdformat --check on one file is about 630 ms, gdlint on one file about 610 ms, and Godot --check-only about 300 ms. The full prototype PostToolUse hook (format, CR strip, lint, Godot check) takes about 1.7 to 2.0 s per .gd edit.  
  src: local-test: bash gd-post-edit.sh < {tool_input.file_path} payload (scratchpad/hookproto) (local-test)
- **godot_toolchain-28** [confirmed] GdUnit4 now lives at godot-gdunit-labs/gdUnit4. The latest release is v6.2.1 (2026-08-20). The README compatibility table for v6.2.x lists Godot v4.5 to v4.7.1; 4.7.2 is not listed, but local runs on 4.7.2 work. v6.2.1 fixed 'Stop the process loop before quitting the CI runner' and false-positive orphans for queue_free().  
  src: https://github.com/godot-gdunit-labs/gdUnit4/releases/tag/v6.2.1 (changelog)
- **godot_toolchain-29** [confirmed] GdUnit4 6.2.1 CLI options (GdUnitTestCIRunner.gd): -a/--add, -i/--ignore, -c/--continue (the default is fail-fast, stopping at the first failure), -conf/--config, -help, --help-advanced, -rd/--report-directory (default res://reports), -rc/--report-count (default 20), --info, --selftest, --ignoreHeadlessMode. Exit codes (GdUnitTestSessionRunner.gd): 0 success, 100 errors or failures, 101 warnings (orphans), 103 headless not supported, 104 Godot version not supported, 105 script errors detected during discovery.  
  src: local file: D:/prime-game/addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd and GdUnitTestSessionRunner.gd (GdUnit4 6.2.1); docs: https://godot-gdunit-labs.github.io/gdUnit4/latest/advanced_testing/cmd/ (repo)
- **godot_toolchain-30** [confirmed] Local GdUnit4 runs on 4.7.2 (about 2.3 s for a trivial suite):
- A failing assert exits 100, with JUnit at tools/out/gdunit/report_1/results.xml plus index.html.
- Running without --ignoreHeadlessMode exits 103.
- A suite with a parse error exits 105.
- A null dereference inside a test marks the test FAILED and exits 100, with or without -d.  
  src: local-test: "$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests -rd res://tools/out/gdunit -rc 1 (local-test)
- **godot_toolchain-31** [confirmed] GdUnit4 issue #1330 (open, 2026-09-17, Windows 11, Godot 4.7.1): a suite's 'Statistics' line prints PASSED even though a test in it failed. I reproduced it locally on 4.7.2 ('1 failures ... PASSED').  
  src: https://github.com/godot-gdunit-labs/gdUnit4/issues/1330 (issue)
- **godot_toolchain-32** [confirmed] runtest.cmd (6.2.1) takes the binary from --godot_binary or %GODOT_BIN% and runs '"<bin>" --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd <args>' without --headless (the runner window is minimized). It then runs a second headless GdUnitCopyLog pass and returns the first exit code.  
  src: local file: D:/prime-game/addons/gdUnit4/runtest.cmd (repo)
- **godot_toolchain-33** [confirmed] gdUnit4-action latest is v1.3.2 (2026-06-28).
- Inputs: godot-version (required), godot-status (stable), paths (required), version (default latest; 'installed' uses the committed addon), timeout (10 min), retries, arguments, warnings-as-errors, publish-report, upload-report, report-name (test-report.xml).
- It installs Godot into /home/runner/godot-linux and runs runtest.sh under xvfb-run with --display-driver x11 --rendering-driver opengl3, so it runs on Linux runners only.  
  src: https://github.com/godot-gdunit-labs/gdUnit4-action (repo)
- **godot_toolchain-34** [confirmed] chickensoft-games/setup-godot latest is v2.4.2 (2026-08-28, node24 action).
- It downloads from github.com/godotengine/godot-builds/releases, where 4.7.2-stable is present (2026-08-18).
- Inputs: version (major.minor.patch, e.g. 4.7.2), use-dotnet (defaults to true, so it must be set to false), include-templates (default false), cache (default true), path, downloads-path, bin-path.
- It exports GODOT4 and supports ubuntu, macos and windows runners.
- On Windows it selects the file ending in '_win64.exe', which is the GUI exe, not _console.exe.  
  src: https://github.com/chickensoft-games/setup-godot (action.yml, src/utils.ts, src/main.ts) (repo)
- **godot_toolchain-35** [confirmed] The barichello/godot-ci Docker image has tags 4.7.2 and mono-4.7.2 (pushed 2026-08-18), and the GitHub repo has a 4.7.2-stable release. Being a container, it only runs on Linux runners.  
  src: https://hub.docker.com/v2/repositories/barichello/godot-ci/tags ; https://github.com/abarichello/godot-ci/releases (repo)
- **godot_toolchain-36** [confirmed] Godot LSP defaults to port 6005 and DAP to 6006. The docs say 'a Godot instance must be running on your current project'. The relevant editor settings are network/language_server/remote_host, remote_port, use_thread, enable_smart_resolve, poll_limit_usec and show_native_symbols_in_editor, and --lsp-port overrides the port. The human's editor (PID 17248, '--path D:/prime-game --editor') is currently listening on 127.0.0.1:6005 and 127.0.0.1:6006.  
  src: https://docs.godotengine.org/en/stable/tutorials/editor/external_editor.html ; https://docs.godotengine.org/en/stable/classes/class_editorsettings.html ; local-test: Get-NetTCPConnection -State Listen (official-docs)
- **godot_toolchain-37** [confirmed] A headless editor LSP works on 4.7.2: `"$GODOT_BIN" --editor --headless --path . --lsp-port 6015` was listening within about 2 s. A minimal Node LSP client (initialize, then didOpen) received publishDiagnostics containing the Error-level items and also Warn-level warnings such as '(UNUSED_VARIABLE) ...', which --check-only does not show.  
  src: local-test: scratchpad/lsp_probe.js against port 6015 (local-test)
- **godot_toolchain-38** [confirmed] Claude Code's official code-intelligence plugins cover C/C++, C#, Go, Java, Kotlin, Liquid, Lua, PHP, Python, Ruby, Rust, Swift and TS/JS, with no GDScript. A custom .lsp.json supports command, extensionToLanguage, args, transport, env, initializationOptions, settings, workspaceFolder, startupTimeout, shutdownTimeout, restartOnCrash, maxRestarts and diagnostics. The docs say 'Claude Code accepts socket but runs every server over stdio', so Godot's TCP-only LSP needs a stdio bridge. Plugin LSP servers do not run in cloud sessions.  
  src: https://code.claude.com/docs/en/plugins/code-intelligence.md ; https://code.claude.com/docs/en/plugins/manifest-reference.md (official-docs)
- **godot_toolchain-39** [confirmed] The community GDScript LSP bridges are small and unvetted:
- code-xhyun/godot-lsp-stdio-bridge: 25 stars, MIT, last push 2026-02-03.
- Sods2/claude-code-gdscript-lsp: 7 stars, MIT, a Node bridge to port 6005 that needs a running editor or `godot --editor --headless --lsp-port 6005`.
- twaananen/claude-code-gdscript: 5 stars, MIT, auto-launches a per-project headless backend; LSP changes need a full Claude Code restart.  
  src: https://github.com/Sods2/claude-code-gdscript-lsp ; https://github.com/twaananen/claude-code-gdscript ; https://github.com/code-xhyun/godot-lsp-stdio-bridge (repo)
- **godot_toolchain-40** [confirmed] The most-starred Godot MCP server, Coding-Solo/godot-mcp (5858 stars), offers: launch editor, run project, capture debug output, stop, get version, list projects, scene management and UID management. All of these can be reproduced with the Godot CLI plus a task runner.  
  src: https://github.com/Coding-Solo/godot-mcp (repo)
- **godot_toolchain-41** [confirmed] Claude Code hooks:
- PostToolUse exit 2 shows stderr to Claude, but the tool call is not undone.
- Exit 0 stderr goes only to the debug log.
- The default command timeout is 600 s.
- On Windows the hook shell defaults to bash (Git Bash) unless 'shell': 'powershell' is set.
- ${CLAUDE_PROJECT_DIR} is available.
- Settings 'env' applies to 'every session and its subprocesses'.  
  src: https://code.claude.com/docs/en/hooks.md ; https://code.claude.com/docs/en/settings-reference.md (official-docs)
- **godot_toolchain-42** [corrected] Godot issue #123511 (closed with the 'archived' label, filed 2026-09-15 against 4.7.2 on Windows): a headless editor session that discovers a .gdextension for the first time crashes at shutdown (0xC0000005). The second identical run exits 0.  
  src: https://github.com/godotengine/godot/issues/123511 (issue)
  - CORRECTED: Issue #123511 was filed 2026-09-15 against v4.7.2.stable.steam (not the official build) with a custom godot-cpp extension. A maintainer closed it as not_planned about 2 hours later for not following the issue template and for suspected AI generation. The bug is unconfirmed; a single retry on a crash exit is still cheap insurance.
  - evidence: https://github.com/godotengine/godot/issues/123511

## Missed facts (from verifier)

- **mf-01** --check-only does not register autoload singletons. A script that references an autoload by name (e.g. `Bus.ping()` with [autoload] Bus="*res://auto/bus.gd") fails with 'SCRIPT ERROR: Compile Error: Identifier not found: Bus' and exit 1, even after --import. The same file loads fine in a `-s` SceneTree checker, because autoloads are registered there. The -s checker also INSTANTIATES the autoloads (their _init runs before _initialize and their _ready after), so autoload side effects run inside `check`.  
  src: local-test: scratchpad/fc: --check-only -s res://src/uses_autoload.gd (rc=1) vs -s res://tools/check/check_project.gd (not flagged, BUS_INIT/BUS_READY printed)
- **mf-02** '-d --ignore-error-breaks' gives Warn-level visibility without the debug> hang. Parse errors exit 1 and Warn-level warnings print as 'WARNING: ... at: GDScript::reload (res://f.gd:L)'. A Logger receives them as error_type=1, with the warning code (e.g. UNUSED_VARIABLE) in `code` and the message in `rationale`. EngineDebugger.is_active() is true in this mode.  
  src: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html (--ignore-error-breaks) ; local-test: -s tools/wlog.gd with -d --ignore-error-breaks
- **mf-03** A minimized Godot window does not draw, so awaiting RenderingServer.frame_post_draw hangs. This happened with vulkan, d3d12 and opengl3. Launching with an off-screen position ('--position -30000,-30000') renders normally and saved a correct PNG.  
  src: local-test: shot_min.gd rc=124 on 3 drivers; shot_plain.gd with --position -30000,-30000 rc=0
- **mf-04** gdtoolkit's excluded_directories matches bare directory names during os.walk (`dirnames[:] = [d for d in dirnames if d not in excluded_directories]`), so an entry like 'tools/out' never matches. gdlintrc and gdformatrc are found by searching upward from the process CWD, not from the file's location.  
  src: local file: C:/Users/xperi/AppData/Local/Programs/Python/Python314/Lib/site-packages/gdtoolkit/common/utils.py and linter/__main__.py (gdtoolkit 4.5.0); https://github.com/Scony/godot-gdscript-toolkit
- **mf-05** Claude Code passes Windows paths with backslashes in tool_input.file_path. In Git Bash, `sed -i 's/\r$//' 'C:\...\file.gd'` writes its temp file in the CWD. When the CWD is on another drive it fails with 'sed: cannot rename ./sedXXXX: Invalid cross-device link'. The proposed hook ignores that failure, so it exits 0 and the file keeps CRLF.  
  src: local-test: proposed gd-post-edit.sh with a Windows-path payload (scratch on C:, CWD D:\prime-game)
- **mf-06** extension_api.json has no GDScript-language surface: no @onready, @export_*, @rpc, @abstract, @warning_ignore_start annotations and no preload/range/len functions. `"$GODOT_BIN" --headless --doctool <dir>` (1.6 s, 1076 XML files, 6.6 MB) writes modules/gdscript/doc_classes/@GDScript.xml plus the full class docs. It also prints 'Deleting docs cache...', which removes %LOCALAPPDATA%\Godot\editor_doc_cache-4.7.res; that file is shared with the human's editor and is regenerated.  
  src: local-test: --dump-extension-api-with-docs (no @GDScript class) and --doctool (annotation list read from @GDScript.xml)
- **mf-07** Godot_v4.7.2-stable_win64_console.exe is a wrapper that starts Godot_v4.7.2-stable_win64.exe as a child process (seen in the Win32_Process parent/child tree). A Git Bash `timeout` kill of the wrapper also removed the child. Crash exit codes differ by shell: 132 or 139 in Git Bash, NTSTATUS negatives such as -1073741795 in PowerShell.  
  src: local-test: Get-CimInstance Win32_Process during a timed run; PowerShell $LASTEXITCODE after OS.crash()
- **mf-08** Headless editor runs (--import, --editor --headless for the LSP) read and write the per-user editor state shared with the human's GUI editor: %APPDATA%\Godot\editor_settings-4.7.tres was rewritten during these tests. Editor progress output is localized (Ukrainian on this machine). Engine and GDScript error lines stayed in English.  
  src: local-test: file mtimes in %APPDATA%\Godot and %LOCALAPPDATA%\Godot after headless runs; import1.log
- **mf-09** The installed Claude Code is 2.1.195, while the current hooks docs describe behaviour gated at v2.1.196 through v2.1.274. For example, 'Edit(src/**)' `if` semantics changed at v2.1.214, and tool_response.bashEditDiff needs v2.1.269. The docs also state that PostToolUse Edit|Write hooks do not fire when Bash rewrites a file.  
  src: https://code.claude.com/docs/en/hooks.md ; local: claude --version -> 2.1.195
- **mf-10** GdUnit4 warns that in headless mode Godot does not deliver InputEvents, so UI and input-simulation tests do not work headless. Its own runtest.cmd runs windowed (minimized) for this reason. Separately, C: has only 9.9 GB free (98% used); Godot user data, shader cache, temp and pip live there, while D: has 89 GB free.  
  src: local file: D:/prime-game/addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd (headless check message); local-test: df -h

## Options

### Parse check A: per-file --check-only
Loop `--headless --path . --check-only -s res://<file>.gd` over the changed files (hook) or all files (check), after `--import`.
- pros: Exact per-file exit code (0 or 1) and file:line messages; About 300 ms per file; no custom code; Works for any script type (RefCounted, Node, Resource)
- cons: One process per file: about 60 s for 200 files project-wide; Needs a fresh class cache (--import) for class_name references; Does not check .tscn/.tres references; Warn-level warnings invisible
### Parse check B: single-process project checker script
tools/check/check_project.gd (extends SceneTree) walks res:// (skipping addons, tools/out and itself). It load()s every .gd/.tscn/.tres, flags GDScript with !can_instantiate() && !is_abstract(), counts errors through an OS.add_logger Logger, and quits 1 on any error.
- pros: One Godot start for the whole project (seconds); Also catches broken scenes and resources (missing ext_resources, bad script refs); Logger-based: turns any ERROR into an exit code
- cons: Custom code the agent must maintain and test; Loading the running checker script itself crashed or hung in my test, so it must skip itself; Loading scenes may run tool scripts / _init side effects
### Warnings policy 1: binary (Error or Ignore)
Every warning the project cares about is set to 2 in project.godot; everything else is set to 0. No reliance on Warn level.
- pros: The agent sees and must fix exactly the rules that matter, in the hook, check and CI alike; No hidden warnings the agent silently ignores
- cons: The humans must pick the list; some warnings (unsafe_cast, integer_division, unused_parameter) create friction with idiomatic code; The editor loses gentle hints for humans
### Warnings policy 2: Error for typing rules, keep other defaults at Warn
Only untyped_declaration and the unsafe_* rules go to 2; leave the other defaults at 1.
- pros: Least churn; satisfies the KICKOFF 'untyped fails check' rule
- cons: Warn-level issues are invisible to the agent unless an LSP bridge or -d is used (-d hangs on parse errors)
### Screenshot 1: custom windowed shot.gd (minimized)
`"$GODOT_BIN" --path . --resolution WxH -s res://tools/shot/shot.gd -- <scene|state> <abs png> <frames>`, run non-headless with the project's d3d12 renderer. The window is minimized, the script awaits frame_post_draw and saves a PNG to tools/out/ (with .gdignore).
- pros: Tested on this machine with d3d12, vulkan and opengl3, even minimized; Can set up game state via user args before capturing; Same renderer the humans see
- cons: Needs a desktop session and GPU (not headless, not the CI default); Briefly creates a window on the human's desktop
### Screenshot 2: --write-movie PNG sequence
`--write-movie tools/out/shots/x.png --fixed-fps 10 --quit-after N <scene>`
- pros: No capture code; deterministic frame pacing
- cons: Output size followed the project viewport (1152x648), not --resolution; Also writes a .wav; crashes with --headless; hard to stage a specific game state
### CI 1: ubuntu-latest + setup-godot@v2 + runner 'verify'
Install 4.7.2 (use-dotnet: false) via chickensoft-games/setup-godot@v2 (v2.4.2), pip install gdtoolkit==4.5.0, then run the same task-runner 'verify' as locally with GODOT_BIN=$GODOT4; upload tools/out/gdunit/**/results.xml.
- pros: CI equals local verify (KICKOFF definition of done); Official godot-builds binaries, cached; exact version pin; Linux runner prints stdout natively and is cheapest
- cons: Linux vs Windows differences are not covered (voice GDExtension later); Must add a JUnit publisher step ourselves if wanted
### CI 2: gdUnit4-action and/or godot-ci container
Use godot-gdunit-labs/gdUnit4-action@v1 (godot-version 4.7.2, version: installed) for tests, or run jobs in barichello/godot-ci:4.7.2.
- pros: gdUnit4-action publishes JUnit reports out of the box, with retries and timeout; godot-ci image is pre-baked (fast start)
- cons: A second Godot install path that diverges from local verify; xvfb + opengl3 (different renderer) in the action; Linux only; More moving third-party parts
### Code intelligence: none at M0 vs community LSP bridge
Option A: rely on the PostToolUse hook (format, lint, check-only) and the check command for diagnostics. Option B: add a community .lsp.json bridge plugin (for example twaananen/claude-code-gdscript auto-launching a headless editor on its own port, or attach mode to the human's editor on 6005).
- pros: A: zero dependencies; already gives file:line errors after each edit; B: symbol navigation (definition, references) plus Warn-level diagnostics
- cons: A: no go-to-definition; Warn-level warnings invisible; B: unvetted 5-25 star projects; an extra headless editor on the same project dir contends for .godot/; restart needed; third-party dependency requires human approval
### MCP: none vs Godot MCP server
Option A: no MCP; all verification through the runner. Option B: Coding-Solo/godot-mcp or an editor-plugin MCP.
- pros: A: nothing to install; the runner is already scriptable, reviewable and runs in CI; B: editor-plugin MCPs can inject input into, and inspect, a live running game
- cons: A: no live-editor introspection; B: Coding-Solo mostly duplicates the CLI; editor-plugin MCPs add an addon to the repo and a second editor session; not usable in CI
### godot-api-checker design: compiler-first + pinned API dump
The strict-typed parser (--check-only with unsafe_* set to Error) already rejects unknown methods and properties on typed receivers and Godot 3 keywords. The read-only subagent (cheap model, tools: Read, Grep, Glob and one Bash command to query tools/out/api/extension_api.json generated by doctor) covers what the compiler cannot:
- string-based APIs: connect('sig'), call('m'), get_node paths, property names in .tscn/.tres, ProjectSettings keys, input actions
- @rpc modes
- 4.7 migration items
- Godot 3 idioms in comments or docs
- pros: Ground truth is the exact 4.7.2 API, not model memory; Small, cheap subagent scope
- cons: Needs a small query helper script (node or python); A 12 MB dump must live outside git (tools/out)

## Recommendation

For this project (two humans on Windows who write no code, GitHub Issues as the only moving state), I recommend the following.

1. **Verification is plain CLI plus one task runner. No MCP, no LSP plugin at M0.** Every Godot call runs under a hard timeout with a process-tree kill. Every harness script (check, bots, shot) registers an `OS.add_logger` Logger and quits non-zero on any error, because Godot's own exit codes do not reflect runtime errors or `push_error`, and an early error can hang the process. Never pass bare `-d`.

2. **`check` =**
   - `--headless --import`, retried once on a crash exit (for the future GDExtension),
   - then a single-process `check_project.gd`: `can_instantiate()` + Logger over all `.gd`, `.tscn` and `.tres`, skipping `addons/`, `tools/out/` and itself,
   - then `gdformat --check` + `gdlint` with `addons/` excluded.

3. **Warnings policy is binary:** each rule is either Error (2) or Ignore (0), because Warn is invisible to the agent. Minimum set at 2: `untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument`, and the defaults already at 2. The humans pick the rest (`unsafe_cast`, `unused_*`, `integer_division` and so on). Keep `directory_rules` at the default `{"res://addons": 0}`.

4. **PostToolUse hook for `.gd` edits** (bash, runs in Git Bash, about 2 s): skip `addons/`, then run sequentially:
   - `gdformat`, then strip CR,
   - `gdlint`,
   - `--check-only` on the file; on an 'not declared / Could not find type' error, run `--import` and retry once.

   Exit 2 with compact stderr on failure. Sequential order avoids gdtoolkit #428, and the Godot re-check catches gdformat #424.

5. **`test` =** `GdUnitCmdTool.gd` called directly with `--headless --ignoreHeadlessMode -c -rd res://tools/out/gdunit -rc 1`. Success is exit code 0 plus `results.xml`. Ignore the console PASSED/FAILED words (#1330). Whether exit 101 (orphans) fails the build is a human decision; I suggest yes.

6. **`shot` =** a custom windowed `shot.gd` using the project's d3d12 renderer. It minimizes the window, awaits `frame_post_draw`, saves to `tools/out/shots/` (the folder has a `.gdignore`), and refuses to run headless. Agents read the PNG back with the Read tool.

7. **CI =** ubuntu-latest + `chickensoft-games/setup-godot@v2` (4.7.2, `use-dotnet: false`) + `pip gdtoolkit==4.5.0`, running the same `verify` entry point. No Windows CI job until the voice GDExtension needs it; Windows minutes may cost money, so ask first.

8. **godot-api-checker =** a cheap-model, read-only subagent that relies on the compiler for typed API checks. It queries a `doctor`-generated 4.7.2 `extension_api.json` for the string-based and semantic cases.

9. **Agents work in git worktrees** so their `.godot/` cache and imports never collide with the human's open editor on `D:/prime-game`.

10. **Revisit a GDScript LSP bridge after M2** for symbol navigation. It needs human approval as a third-party dependency.

## Verifier critique of recommendation

The overall direction is sound, and most facts reproduce locally: a plain CLI plus one runner, hard timeouts, a Logger-based single-process checker, import before check, gdtoolkit with addons excluded, GdUnitCmdTool called directly, ubuntu CI with setup-godot, and no MCP or LSP at M0. Several load-bearing parts are wrong, though.

(1) Warnings policy. Recommendation 3 rests on 'Warn is invisible to the agent', which is false. '-d --ignore-error-breaks' shows Warn-level warnings with file, line and a machine-readable code, both on stdout and to a Logger, and it does not hang. The humans should get three options: binary (Error/Ignore); three-level, where check reports Warn items and fails only on Error; or three-level with a Warn budget.
Also, `var y := untyped` fails as a hard error regardless of inference_on_variant, and untyped_declaration=2 also forces typed parameters. Both belong in the rule text.

(2) The per-file hook is broken for real code. --check-only cannot see autoload singletons and fails with 'Compile Error: Identifier not found: <Autoload>', which the retry regex does not catch. It should call the -s checker in single-file mode instead (about 300-400 ms). Note that the checker instantiates autoloads, so autoloads must avoid side effects at startup (no network, mic or voice init), or the checker needs a guard.

(3) The shot design hangs. Minimizing stops rendering, so frame_post_draw never fires on any of the three drivers. Use '--position -30000,-30000' (verified) and keep the timeout.

(4) Hook robustness on Windows. CR stripping fails silently on backslash paths across drives; use cygpath -u. gdtoolkit reads its config from the CWD, so cd to the root first. CLAUDE_PROJECT_DIR is the session-start root, which is wrong for a file inside a worktree the session entered later; derive the root by walking up from the file to project.godot. The import retry (300 s) exceeds the hook timeout (120 s). sed -i rewrites the file on every edit even when nothing changed. Edits made through Bash bypass the hook entirely, so `check` stays the real gate.

(5) Tests. Headless GdUnit gets no InputEvents, so input and UI tests need a windowed, off-screen mode. Whether exit 101 (orphans) fails the build remains a human decision.

(6) api-checker. Add --doctool XML for @GDScript annotations and builtins. Seed it with the 4.7 behaviour changes the project actually hits: the AudioStreamPlayer2D/3D area_mask default change, Jolt changes and input device IDs.

(7) Worktrees are still right, but each one needs a cold --import (slow once LFS assets arrive). They do not isolate the shared %APPDATA%\Godot editor settings. C: has only 9.9 GB free.

(8) CI. setup-python and upload-artifact are at v7. LFS checkout consumes LFS bandwidth, which may cost money, so ask the humans. `verify` in CI must skip `shot`.

(9) Crash handling must accept both Git Bash codes (132/139) and PowerShell NTSTATUS codes.

(10) The evidence for #123511 is weak (closed as a template or AI-generated report on the Steam build). The retry is fine, but it should not be cited as a known engine bug.

Side effects of this fact-check, for transparency:
- sed briefly created and removed a temp file in D:\prime-game; nothing is left, but the directory mtime changed.
- The headless editor, import and doctool runs rewrote %APPDATA%\Godot\editor_settings-4.7.tres and regenerated %LOCALAPPDATA%\Godot\editor_doc_cache-4.7.res.
- A few windowed Godot windows appeared briefly.
- All other files were scratch files under scratchpad/fc.

## Concrete config (researcher)

PROPOSAL ONLY: nothing below has been applied to the repo.

=== 1. project.godot warnings (binary policy; the humans choose the optional lines) ===
[debug]

gdscript/warnings/untyped_declaration=2
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_call_argument=2
; optional, decide: unsafe_cast=2|0, missing_await=2, unused_variable=2, unused_local_constant=2,
; shadowed_variable=2, shadowed_variable_base_class=2, unreachable_code=2, standalone_expression=2,
; narrowing_conversion=2, int_as_enum_without_cast=2, redundant_await=2, unsafe_void_return=2,
; integer_division=0, return_value_discarded=0, inferred_declaration=0 (keeps `:=` idiomatic)
; keep default: gdscript/warnings/directory_rules={ "res://addons": 0 }

=== 2. Godot invocations used by the runner (each wrapped in timeout + tree kill) ===
# version pin (doctor)
"$GODOT_BIN" --version            # must start with 4.7.2.stable.official
# class cache / uid / imports (first step of check; retry once on crash exit)
"$GODOT_BIN" --headless --no-header --path . --import
# single-file parse check (hook)
"$GODOT_BIN" --headless --no-header --path . --check-only -s res://core/foo.gd
# project-wide check
"$GODOT_BIN" --headless --no-header --path . -s res://tools/check/check_project.gd
# unit tests (0 ok, 100 fail, 101 orphans, 103 headless blocked, 105 script errors)
"$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests -rd res://tools/out/gdunit -rc 1
#   -> tools/out/gdunit/report_1/results.xml (JUnit)
# screenshot (never headless; window minimized by the script)
"$GODOT_BIN" --no-header --path . --resolution 1280x720 -s res://tools/shot/shot.gd -- res://levels/rooms/lab.tscn "$PWD/tools/out/shots/lab.png" 10
# API ground truth for godot-api-checker (doctor, into gitignored dir)
(cd tools/out/api && "$GODOT_BIN" --headless --no-header --dump-extension-api-with-docs)
# lint (addons excluded via config AND via explicit path list, see gdtoolkit #395)
gdformat --check core server net client voice content levels tools tests
gdlint core server net client voice content levels tools tests

=== 3. tools/check/check_project.gd (sketch; its two techniques were tested separately) ===
extends SceneTree

const SKIP: PackedStringArray = ["res://addons", "res://tools/out", "res://tools/check", "res://.godot"]


class ErrorCounter:
	extends Logger
	var count: int = 0
	var _mutex: Mutex = Mutex.new()

	func _log_error(
		_function: String, _file: String, _line: int, _code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		count += 1
		_mutex.unlock()


func _initialize() -> void:
	var counter: ErrorCounter = ErrorCounter.new()
	OS.add_logger(counter)
	var files: PackedStringArray = []
	_collect("res://", files)
	var bad: PackedStringArray = []
	for path: String in files:
		var res: Resource = load(path)
		if res == null:
			bad.append(path)
		elif res is GDScript:
			var s: GDScript = res as GDScript
			if not s.can_instantiate() and not s.is_abstract():
				bad.append(path)
	OS.remove_logger(counter)
	for p: String in bad:
		printerr("CHECK FAIL ", p)
	print("check: files=%d failed=%d logged_errors=%d" % [files.size(), bad.size(), counter.count])
	quit(1 if (bad.size() > 0 or counter.count > 0) else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	if dir.trim_suffix("/") in SKIP:
		return
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension() in ["gd", "tscn", "tres"]:
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(dir.path_join(d), out)

=== 4. tools/hooks/gd-post-edit.sh (prototype tested in scratch, ~1.7-2.0 s) ===
#!/usr/bin/env bash
set -u
file="$(node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tool_input.file_path||"")}catch(e){}})')"
case "$file" in *.gd) ;; *) exit 0 ;; esac
root="${CLAUDE_PROJECT_DIR:-$PWD}"
rel="$(realpath --relative-to="$root" "$file")"
case "$rel" in addons/*|.godot/*|tools/out/*) exit 0 ;; esac
gt="${GDTOOLKIT_DIR:+$GDTOOLKIT_DIR/}"
rc=0; msg=""
if "${gt}gdformat" "$file" >/dev/null 2>&1; then sed -i 's/\r$//' "$file"; else msg+="gdformat could not parse $rel"$'\n'; rc=2; fi
if ! out="$("${gt}gdlint" "$file" 2>&1)"; then msg+="$out"$'\n'; rc=2; fi
check() { (cd "$root" && timeout 60 "${GODOT_BIN:-godot}" --headless --no-header --path . --check-only -s "res://$rel" 2>&1); }
if ! out="$(check)"; then
  if printf '%s' "$out" | grep -qE 'not declared in the current scope|Could not find type'; then
    (cd "$root" && timeout 300 "${GODOT_BIN:-godot}" --headless --no-header --path . --import >/dev/null 2>&1)
    out="$(check)" && out=""
  fi
  [ -n "$out" ] && { msg+="$(printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|at: GDScript')"$'\n'; rc=2; }
fi
[ "$rc" -ne 0 ] && printf '%s' "$msg" >&2
exit "$rc"

=== 5. .claude/settings.json hook entry ===
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/tools/hooks/gd-post-edit.sh\"",
            "timeout": 120,
            "statusMessage": "GDScript: format, lint, parse check"
          }
        ]
      }
    ]
  }
}

=== 6. gdlintrc / gdformatrc (repo root) ===
# gdlintrc: start from `gdlint --dump-default-config`, then set:
excluded_directories: !!set
  .git: null
  .godot: null
  addons: null
  tools/out: null
# gdformatrc
excluded_directories: !!set
  .git: null
  .godot: null
  addons: null
  tools/out: null
line_length: 100

=== 7. .gitignore additions ===
tools/out/*
!tools/out/.gdignore
reports/

=== 8. CI (.github/workflows/ci.yml, excerpt) ===
jobs:
  verify:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7        # v7 exists per GdUnit4 v6.2.0 notes; confirm latest major
        with: { lfs: true }
      - uses: chickensoft-games/setup-godot@v2   # v2.4.2
        with:
          version: 4.7.2
          use-dotnet: false
          include-templates: false
      - uses: actions/setup-python@v6
        with: { python-version: '3.12' }
      - run: pip install gdtoolkit==4.5.0
      - run: GODOT_BIN="$GODOT4" ./tools/run.sh verify
      - if: always()
        uses: actions/upload-artifact@v4   # confirm latest major
        with: { name: test-reports, path: tools/out/gdunit/**/results.xml }

## Config corrections (verifier)

Section 1 (project.godot warnings):
- The comment 'var y := a fails through inference_on_variant' is wrong for an untyped `a`: that is a hard analyzer error that fails even at 0.
- Add a three-level option alongside the binary one (see the critique).
- Note that untyped_declaration=2 also rejects untyped function parameters.
- The warning-level bools are 'enable' and 'renamed_in_godot_4_hint'.

Section 2 (invocations):
- The single-file parse check with `--check-only -s res://core/foo.gd` false-fails any script that references an autoload. Use `-s res://tools/check/check_project.gd -- res://core/foo.gd` in single-file mode instead.
- For Warn visibility, run the checker with `-d --ignore-error-breaks` (never bare -d).
- In the screenshot command, do not minimize. Pass `--position -30000,-30000` and keep a hard timeout.
- Crash detection must treat 132/139 (Git Bash) and negative NTSTATUS codes (PowerShell) as crashes.

Section 3 (check_project.gd):
- It works as written: 6 of 6 broken files were flagged, @abstract passed, and autoload references resolved.
- The `not s.is_abstract()` guard is unnecessary, because can_instantiate() is true for valid abstract scripts.
- ErrorCounter counts every _log_error, including error_type 1 warnings (push_warning, engine WARNINGs, and GDScript Warn items when run with -d). Filter on error_type, or split the counts and decide explicitly.
- It instantiates autoloads (their _init and _ready run).
- Accept file paths from OS.get_cmdline_user_args() so the hook can reuse it.

Section 4 (gd-post-edit.sh):
- Convert the path with `file=$(cygpath -u "$file")` before `sed -i`. With a backslash path, sed writes its temp file in the CWD and fails across drives ('Invalid cross-device link'), and the hook still exits 0.
- Strip CR only if the file contains \r.
- Derive root by walking up from the file to project.godot, not from CLAUDE_PROJECT_DIR, which is 'the project root where the session started' and is wrong for a file in a worktree entered later.
- `cd "$root"` before gdformat/gdlint so gdformatrc/gdlintrc are found; they are searched upward from the CWD.
- Replace the --check-only call with the single-file checker; the retry regex does not match 'Identifier not found' for autoloads.
- The inner `timeout 300` import exceeds the hook's own 120 s timeout. Raise the hook timeout or lower the import timeout, and report 'import timed out' explicitly.

Section 5 (settings.json):
- The matcher 'Edit|Write' is fine.
- The shell-form command is fine; the docs' quoting pattern is `"\"${CLAUDE_PROJECT_DIR}\"/tools/hooks/gd-post-edit.sh"`, or use the exec form `args` (available since 2.1.139).
- Consider an explicit "shell": "bash".

Section 6 (gdlintrc/gdformatrc):
- `tools/out: null` never matches, because gdtoolkit compares bare directory names. Use `out: null` (excludes every dir named 'out') or rely on explicit path lists.
- `gdlint --dump-default-config` writes ./gdlintrc and asserts if one already exists; it does not print to stdout.

Section 7 (.gitignore): OK.

Section 8 (CI):
- Use actions/setup-python@v7 (v7.0.0, 2026-07-20) and actions/upload-artifact@v7 (v7.0.1). actions/checkout@v7 is correct (v7.0.1).
- `lfs: true` consumes LFS bandwidth quota; ask the humans first because of cost.
- Ensure `verify` skips `shot` in CI.
- setup-godot also exports GODOT, not only GODOT4.

## Windows notes

- **Console exe spawns a child process.** `GODOT_BIN` is `Godot_v4.7.2-stable_win64_console.exe`. On every run it spawns `Godot_v4.7.2-stable_win64.exe` as a child that does the real work, so two processes exist per run. Timeouts must kill the whole tree (`taskkill /T /F /PID <pid>`, or a job object). Git Bash `timeout` cleaned up both in my tests. Killing only the wrapper from PowerShell may orphan the child (inferred).
- **The human's editor is open on the repo.** It runs as PID 17248 (`--path D:/prime-game --editor`) and listens on 127.0.0.1:6005 (LSP) and 6006 (DAP). If the agent runs `--import`, tests or shots in the same directory, both processes write `.godot/`. The editor may also pop 'files changed on disk' dialogs. Prefer git worktrees for agent sessions. Each worktree needs one cold `--import` (about 3.5 s on an empty project, longer with assets).
- **Rendering driver.** `project.godot` sets `rendering_device/driver.windows="d3d12"`. Windowed screenshots worked with d3d12, vulkan and opengl3 (compatibility renderer, which looks different). Minimizing the window via `DisplayServer.window_set_mode` still renders correctly. Headless cannot capture at all.
- **gdtoolkit on Windows.**
  - The exes live in the Python Scripts dir (`$GDTOOLKIT_DIR`), which is not on PATH; the runner and hook must use `$GDTOOLKIT_DIR`.
  - Python 3.14 works with gdtoolkit 4.5.0.
  - gdformat rewrites files with CRLF, so strip CR afterwards (the repo `.gitattributes` is `* text=auto eol=lf`).
  - Paths are printed with mixed separators (`addons/gdUnit4\src\...`).
- **Hook shell.** Hooks run under Git Bash by default on Windows (bash is installed), so a bash hook is portable to Linux CI. Use `"shell": "powershell"` only for `.ps1` hooks. Node 20 is on PATH and can parse the hook JSON; `jq` availability is unverified.
- **Localized editor output.** Editor progress output (`--import`) is in Ukrainian because of the editor locale. Engine error and warning messages stay in English, so log grepping for `SCRIPT ERROR`, `ERROR:` and `WARNING:` is safe.
- **Exit codes by shell.** Under Git Bash a Godot crash shows as 139 and a timeout as 124. Natively (PowerShell) a crash is -1073741819 (0xC0000005) per Godot issue #123511.
- **GdUnit4 `runtest.cmd`.** It opens a (minimized) window because it does not pass `--headless`. Call `GdUnitCmdTool.gd` directly with `--headless --ignoreHeadlessMode` for core tests. Use the windowed form only for UI-input tests.
- **setup-godot on Windows runners.** It installs the `_win64.exe` GUI exe, not the console one. Stdout capture on Windows CI is unverified, so prefer Linux CI.
- **Tooling note for agents.** When I wrote scripts through the Bash tool with heredocs, `\\` sequences were collapsed (a JS regex and a bash `${var//\\//}` were silently corrupted). Write script files with the Write tool instead of heredocs.

## Gotchas

- `--import` exits 0 even when scripts have parse errors. It builds the class cache and `.uid` files but is not a check.
- `load()` / `ResourceLoader.load()` return a non-null GDScript for scripts with parse errors. Use `can_instantiate()` (plus `is_abstract()`) or a Logger, never a null check.
- `--check-only` fails on valid code that references a `class_name` missing from `.godot/global_script_class_cache.cfg`. Run `--import` first, and re-import after adding or renaming a `class_name`.
- A runtime error inside `_initialize()` of a `-s` script skips `quit()`, so the process never exits. `push_error` and runtime errors never change the exit code. Always use a timeout plus a Logger or log scan.
- Bare `-d` hangs at an interactive `debug>` prompt on any script or parse error, even with stdin closed. GdUnit's workaround (`--remote-debug tcp://127.0.0.1:0`) emits two ERROR lines that log scanners must allowlist.
- Warn-level (1) GDScript warnings are invisible to `--check-only`. Only Error-level (2) is enforceable from the CLI; `-d` reveals them but hangs on parse errors.
- There is no global 'warnings as errors' switch in 4.7; each `debug/gdscript/warnings/<name>` must be set to 2. `exclude_addons` has been replaced by `directory_rules` (default `{"res://addons": 0}`).
- Headless screenshots are impossible: the viewport texture is null and awaiting `RenderingServer.frame_post_draw` hangs forever. `--headless --write-movie` crashes (exit 139).
- `--write-movie` output used the project viewport size (1152x648), not `--resolution`, and also wrote a `.wav`.
- Anything written under the project (screenshots, GdUnit reports under `res://reports`) gets imported by the editor and creates `.import` files. Put outputs in `tools/out/` with a `.gdignore`, and gitignore `reports/` or redirect with `-rd`.
- A project-wide checker that recursively loaded its own running SceneTree script (with `CACHE_MODE_IGNORE`) crashed or hung in my test. The checker must skip itself and `tools/check/` (exact cause inferred, not isolated).
- GdUnit4 CLI is fail-fast by default (stops at the first failure). Pass `-c` so agents see all failures in one run.
- GdUnit4 headless needs `--ignoreHeadlessMode`, otherwise it exits 103. InputEvent-based UI tests do not work headless.
- GdUnit4 #1330: the suite Statistics line can print PASSED for a failing suite. Parse the exit code and `results.xml`.
- GdUnit4 exit 101 means orphan nodes (warnings), not success. Decide whether `verify` treats it as a failure.
- gdtoolkit #424: gdformat can produce Godot-invalid indentation after multiline lambdas. Always run the Godot parse check after formatting, and revert or fix if it fails.
- gdtoolkit #428: running gdlint and gdformat concurrently can fail spuriously ('File exists'). Run them sequentially, including inside hooks.
- gdtoolkit #395: `excluded_directories` is ignored for explicit file paths, so the hook must skip `addons/` itself.
- gdtoolkit 4.5.0 has had no commits since 2025-10; any GDScript syntax newer than 4.5 may break it with no fix coming. gdlint's default class-definitions-order wants `static var` before `@export var`.
- The GdUnit4 README compatibility table stops at Godot 4.7.1; 4.7.2 works locally but is not officially listed.
- setup-godot's `use-dotnet` defaults to true. Forgetting `use-dotnet: false` installs the .NET build.
- Claude Code runs every plugin LSP server over stdio (`socket` transport is ignored). Godot's LSP is TCP-only, so any GDScript LSP plugin needs a bridge, and the human's editor already owns port 6005.
- A first headless editor or import run after adding a GDExtension may crash at shutdown (Godot #123511). Retry import once before failing (relevant to the voice addon in M1).

## Open questions

- Which GDScript warnings should be Error (2) versus Ignore (0) under a binary policy? Specifically unsafe_cast, inferred_declaration, return_value_discarded, unused_parameter, integer_division, missing_await, shadowed_*. This is a human decision.
- Should `verify` treat GdUnit4 exit 101 (orphan nodes) as a failure?
- Is it acceptable for `shot` and UI tests to open a (minimized) Godot window on the human's desktop, or should they run only on explicit request?
- Should agent sessions always work in git worktrees, isolating `.godot/` from the human's open editor, at the cost of one cold `--import` per worktree?
- Is a Windows CI job wanted before the voice GDExtension lands? GitHub Windows minutes may be billed at a higher rate on private repos, so it costs money and needs human approval. Whether setup-godot's GUI exe captures stdout on Windows runners is unverified.
- Should a GDScript LSP bridge (community plugin, third-party dependency) be revisited after M2 for symbol navigation? If yes, which one, and should it attach to the human's editor (port 6005) or auto-launch a headless backend on another port?
- Do the Claude desktop app (Code tab) hooks run with Git Bash and inherit `settings.local.json` env exactly as the CLI does? This needs verifying once in Phase B with the real hook.
- Is gdtoolkit 4.5.0 acceptable long-term given no commits since 2025-10, or should the humans approve a fallback (pin 4.5.0, keep Godot's parser as the authority, and drop gdformat if #424-type breakages become frequent)?
- Does the two-voip GDExtension trigger Godot #123511 (headless first-discovery crash) on this machine? Verify in the M1 spike.
- Orchestrator note: at the end of my run, a sibling agent's headless screenshot processes were still hanging (PIDs 5536 and 10544, command lines under `scratchpad/fc/proj`, `tools/shot.gd` with `--headless`). This matches the headless `frame_post_draw` hang documented here. I did not touch them.