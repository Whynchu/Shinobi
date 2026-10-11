## Enforcement of the asset provenance policy for Blender-sourced assets.
##
##     godot --headless --path . --script res://tests/run_provenance_tests.gd
##
## GDD 17 names the single highest-impact risk to this project:
##
##     "Source-game asset/legal dependency | Blocks independent distribution |
##      Replace all derived assets and tables; documented provenance and legal review"
##
## and GDD 13.2 requires the prototype to be "independently runnable without
## generated Elden Ring assets". NOTICE.md records the same commitment for this
## repository: no asset derived from another game's files may be committed.
##
## This suite is where that becomes a gate rather than a paragraph. A manifest
## nobody checks is provenance as a comment, and the point of this file is that
## a comment is not a policy.
##
## The policy, stated so it can be enforced:
##
##   1. Every binary asset under `assets/` has a `<name>.provenance.json`.
##   2. That manifest names a schema this suite knows.
##   3. Its `provenance` is one of the values the policy allows. THIRD_PARTY is
##      legal to *have*, but only with a `sources` list and a license, so the
##      derivation is traceable; a manifest claiming THIRD_PARTY with no sources
##      is an unrecorded dependency, which is the thing GDD 17 is about.
##   4. The recorded sha256 matches the bytes on disk. An asset edited and
##      re-saved without regenerating its manifest is a stale manifest, and a
##      stale manifest is worse than a missing one because it still claims to be
##      true.
##   5. The ORIGINAL claim is not just asserted: it has to point at a generator
##      in this repository. A manifest whose origin is a URL that happens to
##      still resolve is not an original asset.
##
## Deliberately does not run in `run_tests.gd`. That runner belongs to the
## simulation lane, and its "161 assertions across 13 suites" contract is not
## this lane's to extend. Separate runners also mean an asset problem is
## reported as an asset problem rather than as a combat failure.
extends SceneTree

const ProvenanceSuite := preload("res://tests/test_provenance.gd")
const Harness := preload("res://tests/harness.gd")

const LOG_PATH := "user://provenance_test_progress.log"

var _log: FileAccess


func _note(message: String) -> void:
	print(message)
	if _log != null:
		_log.store_line(message)
		_log.flush()


func _init() -> void:
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)

	_note("")
	_note("SHINOBI: Blade & Loop -- asset provenance (GDD 17, NOTICE.md)")
	_note("  every asset under assets/ carries a checked manifest")
	_note("  THIRD_PARTY requires a sources list; ORIGINAL requires a local generator")

	var p := ProvenanceSuite.new()
	var h := Harness.new()

	var suites := [
		["sidecars", func() -> void: p.test_sidecars_exist(h)],
		["schema", func() -> void: p.test_schema_and_fields(h)],
		["provenance_values", func() -> void: p.test_provenance_values(h)],
		["original_local", func() -> void: p.test_original_is_local(h)],
		["hashes", func() -> void: p.test_hashes_match(h)],
		["negative", func() -> void: p.test_the_checker_can_fail(h)],
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
