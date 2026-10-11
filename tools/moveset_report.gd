## Prints the balancing sheet for a moveset, straight from the simulation data.
##
##     godot --headless --path . --script res://tools/moveset_report.gd
##
## GDD 16 asks design and engineering to keep one shared sheet for action
## timings, damage, stagger thresholds and trigger rates. This prints it from
## the same `AttackTable` resources the simulation runs, so the sheet cannot
## drift from the game - which is the usual way a shared sheet stops being
## shared.
##
## Add `--check` to exit non-zero on any data problem, which is what CI runs.
extends SceneTree


func _init() -> void:
	var checking := false
	for arg in OS.get_cmdline_args():
		if arg == "--check":
			checking = true

	print("")
	print("SHINOBI: Blade & Loop -- moveset report")
	print("  simulation %d Hz, animation %d fps (1 animation frame = %.1f ticks)"
		% [Tuning.TICK_HZ, Tuning.ANIMATION_FPS,
		   float(Tuning.TICK_HZ) / float(Tuning.ANIMATION_FPS)])
	print("")

	var sets := {
		"katana": Fixtures.katana(),
		"dummy (enemy)": Fixtures.dummy_enemy(),
	}

	var total_problems := 0
	for label in sets:
		var moveset: Moveset = sets[label]
		print("  %s" % label)
		print("  %s" % "-".repeat(118))
		for line in moveset.report():
			print("  " + line)
		var problems := moveset.validate()
		if problems.is_empty():
			print("  no data problems")
		else:
			total_problems += problems.size()
			for p in problems:
				print("  PROBLEM  %s" % p)
		print("")

	print("  %d data problem(s) across %d movesets" % [total_problems, sets.size()])
	print("")

	if checking and total_problems > 0:
		quit(1)
	else:
		quit(0)