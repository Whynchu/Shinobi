## Headless entry point for the run-generation suite.
##
##     godot --headless --path . --script res://tests/run_run_tests.gd
##
## Modelled on `tests/run_tests.gd`, deliberately identical in shape: a SceneTree
## entry, a written-and-flushed log beside stdout, a suite list, and a non-zero
## exit on failure. The last point is the one that matters. ARCHITECTURE.md
## records that the runner "exits 2 when no assertions ran", because without it
## a test file that does not compile reports "0 assertions passed" and exits 0 -
## which already happened once in this project, silently, with every suite
## no-opping.
##
## It is a separate file rather than extra entries in `run_tests.gd` because that
## file belongs to the combat lane. Gate D's evidence should be runnable on its
## own, and a lane should not have to be integrated before it can be checked.
extends SceneTree

## Written to as well as stdout, and flushed after every suite: stdout is
## block-buffered when piped, so a run that hangs later would otherwise lose
## everything and leave no clue which suite was responsible.
const LOG_PATH := "user://test_run_progress.log"


var _log: FileAccess


func _note(message: String) -> void:
	print(message)
	if _log != null:
		_log.store_line(message)
		_log.flush()


func _init() -> void:
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)

	_note("")
	_note("SHINOBI: Blade & Loop -- run generation tests")
	_note("  GDD 8: seeded route graph, eligible room pools, rewards")
	_note("  catalogue: %d authored rooms, %d sweep seeds"
		% [RoomCatalog.room_ids().size(), TestRun.SWEEP_SEEDS])

	var h := TestHarness.new()

	var suites := [
		["seeded_routes", func() -> void: TestRun.test_seeded_routes(h)],
		["act_shape", func() -> void: TestRun.test_act_shape(h)],
		["constraints", func() -> void: TestRun.test_constraints(h)],
		["room_selection", func() -> void: TestRun.test_room_selection(h)],
		["forks", func() -> void: TestRun.test_forks(h)],
		["weights", func() -> void: TestRun.test_weights(h)],
		["reward_offers", func() -> void: TestRun.test_reward_offers(h)],
		["director", func() -> void: TestRun.test_director(h)],
		["determinism", func() -> void: TestRun.test_determinism_isolation(h)],
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
