## Headless test entry point.
##
##     godot --headless --script res://tests/run_tests.gd
##
## This is the equivalent of `cargo test` in the project the GDD references, and
## it exists for the same reason: the simulation is a plain library that can be
## stepped with no window, no renderer and no scene tree, so a change to combat
## timing is verifiable in about a second. GDD 13.4 asks for automated coverage
## of attack windows, guard break, stagger immunity and seeded routes; this is
## where those live.
extends SceneTree

## Written to as well as stdout, and flushed after every suite. stdout is
## block-buffered when piped, so a run that hangs in a later suite would
## otherwise lose everything and leave no clue which suite was responsible.
const LOG_PATH := "user://test_progress.log"


var _log: FileAccess


func _note(message: String) -> void:
	print(message)
	if _log != null:
		_log.store_line(message)
		_log.flush()


func _init() -> void:
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)

	_note("")
	_note("SHINOBI: Blade & Loop -- simulation tests")
	_note("  tick rate %d Hz, animation %d fps, %.4f s per tick"
		% [Tuning.TICK_HZ, Tuning.ANIMATION_FPS, Tuning.DT])

	var h := TestHarness.new()

	var suites := [
		["timing", func() -> void: CombatTests.test_timing(h)],
		["buffer", func() -> void: CombatTests.test_buffer(h)],
		["stamina", func() -> void: CombatTests.test_stamina(h)],
		["dodge", func() -> void: CombatTests.test_dodge(h)],
		["reach", func() -> void: CombatTests.test_reach(h)],
		["one_hit_per_swing", func() -> void: CombatTests.test_one_hit_per_swing(h)],
		["sweep", func() -> void: CombatTests.test_sweep(h)],
		["guard", func() -> void: CombatTests.test_guard(h)],
		["posture", func() -> void: CombatTests.test_posture(h)],
		["low_sweep", func() -> void: CombatTests.test_low_sweep(h)],
		["verbs", func() -> void: CombatTests.test_verbs(h)],
		["sweep_data", func() -> void: CombatTests.test_sweep_data(h)],
		["determinism", func() -> void: CombatTests.test_determinism(h)],
	]

	## Optionally run one suite: --suite=<name>
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