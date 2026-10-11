## Headless entry point for the Gate B art tests.
##
##     godot --headless --script res://tests/run_art_tests.gd
##
##     --suite=<name>   run one suite
##
## Add `--check-only` for a parse-and-quit pass. Worth knowing about: ARCHITECTURE.md
## records that a script which fails to compile *hangs* instead of exiting, so
## while iterating on a suite file use --check-only (which exits) and only run the
## suite for real once it parses:
##
##     godot --headless --path . --script res://tests/run_art_tests.gd --check-only
##
## Deliberately separate from tests/run_tests.gd. That runner's contract is
## "161 assertions across 13 suites" and its suite list belongs to whoever owns
## the simulation; adding to it from this lane would mean editing a file this
## lane does not own, and on a shared branch that edit is a conflict. Two
## runners also keep the failure messages honest - a shader that will not parse
## is reported as a shader failure, not as a combat failure.
##
## The exit codes come from TestHarness and mean the same thing they mean there:
## 0 all passed, 1 an assertion failed, 2 no assertions ran (which is what a
## suite file that does not compile looks like), 3 fewer suites ran than were
## selected.
##
## As ARCHITECTURE.md records, a script that fails to compile hangs rather than
## exiting, so any CI invocation needs an external timeout.
extends SceneTree

## Preloaded by path rather than referenced by class name. The global class
## cache is a generated artefact of the editor's file scan, so a fresh checkout
## running a headless script has not necessarily registered a class added since
## the last scan - and a parse error here is the hang ARCHITECTURE.md warns about.
const ArtSuite := preload("res://tests/test_art.gd")
const Harness := preload("res://tests/harness.gd")

## Written to as well as stdout, and flushed after every suite, for the same
## reason tests/run_tests.gd does it: stdout is block-buffered when piped, so a
## hang in a later suite would otherwise lose everything.
const LOG_PATH := "user://art_test_progress.log"

var _log: FileAccess


func _note(message: String) -> void:
	print(message)
	if _log != null:
		_log.store_line(message)
		_log.flush()


func _init() -> void:
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)

	_note("")
	_note("SHINOBI: Blade & Loop -- art tests (Gate B)")
	_note("  renderer: %s" % _renderer_note())
	_note("  shaders:")
	for path in ArtSuite.ALL_SHADERS:
		var problem: String = ArtSuite.shader_problem(path)
		_note("    %-38s %s" % [path, "ok" if problem.is_empty() else "PROBLEM: " + problem])

	var art := ArtSuite.new()
	var h := Harness.new()

	var suites := [
		["palette", func() -> void: art.test_palette(h)],
		["band_ramp", func() -> void: art.test_band_ramp(h)],
		["band_limit", func() -> void: art.test_band_limit(h)],
		["background", func() -> void: art.test_background(h)],
		["shader_files", func() -> void: art.test_shader_files(h)],
		["materials", func() -> void: art.test_material_factories(h)],
		["shader_checker", func() -> void: art.test_shader_checker(h)],
	]

	var only := ""
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--suite="):
			only = arg.substr(8)

	var selected: Array = []
	for entry in suites:
		if only == "" or only == entry[0]:
			selected.append(entry)
	h.suites_expected = selected.size()

	for entry in selected:
		var name: String = entry[0]
		_note("  ... running %s" % name)
		(entry[1] as Callable).call()

	_note("")
	h.summary()
	_note("")
	if _log != null:
		_log.close()
	quit(h.exit_code())


## Whether this run handed the shaders to a real renderer or to the headless
## stand-in. Worth printing: the compile step behaves differently in the two, and
## a reader should not have to know which one they are looking at.
##
## The dummy driver is not a no-op for shaders - it runs the shading language and
## refuses anything that will not build, it just draws nothing - so the compile
## check in tests/test_art.gd is real under `--headless`.
##
## Expect shader errors on stderr during a green run. That is
## `test_shader_checker` compiling a deliberately broken shader to prove the
## checker can fail; without it, the passing check above would mean nothing.
func _renderer_note() -> String:
	if RenderingServer.get_rendering_device() == null:
		return "dummy (headless): shaders are parsed and compiled, nothing is drawn"
	return "live rendering device"