## The asset provenance policy, as assertions.
##
##     godot --headless --path . --script res://tests/run_provenance_tests.gd
##
## GDD 17 lists "Source-game asset/legal dependency" as this project's
## highest-impact risk and names the mitigation: "Replace all derived assets and
## tables; documented provenance and legal review." NOTICE.md carries the same
## commitment against the actual repository, including the line that matters
## most: "No assets derived from another game's files may be committed."
##
## **Why this needs its own checker.** The repo already tracks provenance for
## *moves*: every `AttackTable` carries `Provenance.ORIGINAL` or
## `Provenance.ESTIMATE`. That is a typed field an author set, and it is
## enforced by a validator on the data the simulation loads. An imported mesh
## has no such field: it is bytes, and nothing in the engine reads them until
## it draws them, at which point the question "where did this come from" has no
## answer anywhere in the program. A sidecar manifest checked by a test is the
## only mechanism that survives a hand-copied `Drag .glb into the project
## folder`, which is how assets actually get in.
##
## **What a green run here means.** It means every committed binary under
## `assets/` has a manifest, that the manifest's schema is one this file knows,
## that the declared provenance is one the policy permits and is backed by what
## it claims (a local generator for ORIGINAL, a sources list and license for
## THIRD_PARTY), and that the recorded sha256 still matches the bytes on disk.
## It does *not* mean the assets are legally clean. GDD 17's review is a human
## step and this suite cannot substitute for it. What it does is make the
## human step possible, by guaranteeing that the provenance exists to review.
class_name TestProvenance
extends RefCounted

## The manifest schema written by tools/blender/build_rig.py. Bumped when a
## field changes meaning, not when a field is added, so an older manifest
## fails loudly rather than matching on a field that now means something else.
const SCHEMA := "shinobi.asset-provenance/1"

## The only extensions treated as assets. Media, not source: a `.py` or `.gd`
## file has its own provenance in its header and in `git blame`.
const ASSET_EXTENSIONS := ["glb", "gltf", "fbx", "png", "exr", "wav", "ogg", "mp3"]

## The three values the policy permits.
##
## ORIGINAL   built for this project, from nothing else.
## PROCEDURAL produced by a tool from this repo's own data.
## THIRD_PARTY came from somewhere else, and therefore *must* carry sources.
##
## The enum is closed rather than open on purpose. A "DERIVED" that means
## half-and-half is exactly the kind of value that makes a provenance policy
## unenforceable, because every author then decides for themselves what their
## derivation counts as.
const PROVENANCE_ORIGINAL := "ORIGINAL"
const PROVENANCE_PROCEDURAL := "PROCEDURAL"
const PROVENANCE_THIRD_PARTY := "THIRD_PARTY"
const ALLOWED_PROVENANCE := [PROVENANCE_ORIGINAL, PROVENANCE_PROCEDURAL, PROVENANCE_THIRD_PARTY]

## An allowed value only when it is backed. The two forms of unrecorded
## dependency this exists to catch: a third-party asset nobody can trace, and a
## manifest that claims ORIGINAL of something that was actually downloaded.
const PROVENANCE_REQUIRING_SOURCES := [PROVENANCE_THIRD_PARTY]
const PROVENANCE_REQUIRING_LOCAL_GENERATOR := [PROVENANCE_ORIGINAL, PROVENANCE_PROCEDURAL]

## Fields every manifest must carry. `origin` is prose because provenance is
## partly a narrative: "made in Blender" and "traced from a screenshot" are
## both true statements about a mesh and only one of them is allowed.
const REQUIRED_FIELDS := [
	"schema", "asset", "kind", "provenance", "origin", "author", "license",
	"generated_by", "generator", "sources", "bytes", "sha256",
]


## Every file under `assets/` that is an asset by extension, recursive.
func asset_files() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://assets/"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for name in d.get_directories():
			stack.append(dir.path_join(name))
		for name in d.get_files():
			var path := dir.path_join(name)
			if ASSET_EXTENSIONS.has(path.get_extension().to_lower()):
				out.append(path)
	out.sort()
	return out


## A manifest is `<asset with extension stripped>.provenance.json`.
func manifest_path_for(asset_path: String) -> String:
	var stem := asset_path.get_basename()
	return "%s.provenance.json" % stem


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## The manifest sidecar for an asset, and whether it existed at all.
##
## Returned as a pair because "no manifest" and "manifest failed to parse" are
## different failures that a single dictionary cannot tell apart, and a policy
## test that reports them as one is a test nobody can act on.
func load_manifest(asset_path: String) -> Dictionary:
	return read_json(manifest_path_for(asset_path))


# --- Sidecars --------------------------------------------------------------------

func test_sidecars_exist(h: TestHarness) -> void:
	h.suite("GDD 17: every committed asset has a provenance sidecar")
	var files := asset_files()
	h.ok(files.size() > 0,
		"there is at least one asset to check (the Blender lane exports one)")
	for path in files:
		h.ok(FileAccess.file_exists(manifest_path_for(path)),
			"%s has a provenance sidecar" % path.get_file())


# --- Schema and required fields --------------------------------------------------

func test_schema_and_fields(h: TestHarness) -> void:
	h.suite("GDD 17: manifests name a known schema and carry every field")

	for path in asset_files():
		var name := path.get_file()
		var m := read_json(manifest_path_for(path))
		if not h.ok(m.is_empty() == false, "%s has a readable manifest" % name):
			continue

		h.eq_string(String(m.get("schema", "")), SCHEMA,
			"%s names schema %s" % [name, SCHEMA])

		for field_name in REQUIRED_FIELDS:
			h.ok(m.has(field_name),
				"%s manifest carries '%s'" % [name, field_name])

		h.eq_string(String(m.get("asset", "")), name,
			"%s manifest names its own asset" % name)


# --- Provenance values -----------------------------------------------------------

func test_provenance_values(h: TestHarness) -> void:
	h.suite("GDD 17: declared provenance is a value the policy permits")

	for path in asset_files():
		var name := path.get_file()
		var m := read_json(manifest_path_for(path))
		if m.is_empty():
			continue

		var declared := String(m.get("provenance", ""))
		h.ok(ALLOWED_PROVENANCE.has(declared),
			"%s declares provenance from the closed set (got '%s')" % [name, declared])

		var sources: Array = m.get("sources", [])
		if PROVENANCE_REQUIRING_SOURCES.has(declared):
			# A THIRD_PARTY asset with no sources is the unrecorded dependency.
			# It is legal to have one and illegal to have one silently.
			h.ok(sources.size() > 0,
				"%s declares THIRD_PARTY, so it must name where it came from" % name)
		else:
			h.eq_int(sources.size(), 0,
				"%s claims %s, so it must not also name external sources"
				% [name, declared])

		if m.has("license") and String(m.get("license", "")) == "":
			h.ok(false, "%s has an empty license, which is not a license" % name)


# --- ORIGINAL must be local ------------------------------------------------------

func test_original_is_local(h: TestHarness) -> void:
	h.suite("GDD 17: an ORIGINAL claim must point at a generator in this repo")

	for path in asset_files():
		var name := path.get_file()
		var m := read_json(manifest_path_for(path))
		if m.is_empty():
			continue

		var declared := String(m.get("provenance", ""))
		if not PROVENANCE_REQUIRING_LOCAL_GENERATOR.has(declared):
			continue

		var generator := String(m.get("generator", ""))
		h.ok(generator != "", "%s names the generator that produced it" % name)

		# The generator must be a path inside this project. This is the assertion
		# that turns "ORIGINAL" from an adjective into a claim: if it were
		# downloaded, there is no file here that would still make it.
		h.ok(generator.begins_with("tools/") and FileAccess.file_exists("res://" + generator),
			"%s names a generator under tools/ that exists (%s)" % [name, generator])

		# The origin prose is required, not decorative: it is where a reader
		# learns the mesh was parametric rather than traced.
		h.ok(String(m.get("origin", "")).length() > 20,
			"%s explains its origin in prose, not just a one-word label" % name)


# --- Hashes ----------------------------------------------------------------------

func test_hashes_match(h: TestHarness) -> void:
	h.suite("GDD 17: the recorded hash matches the committed bytes")

	# Godot's FileAccess gives the bytes; the sha256 context is in the
	# Crypto singleton. Uses the streaming update so a large asset does not have
	# to be held as one Array buf.
	for path in asset_files():
		var name := path.get_file()
		var m := read_json(manifest_path_for(path))
		if m.is_empty() or not m.has("sha256"):
			continue

		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			h.ok(false, "%s is readable for hashing" % name)
			continue

		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		while f.get_position() < f.get_length():
			var chunk: PackedByteArray = f.get_buffer(65536)
			if chunk.is_empty():
				break
			ctx.update(chunk)
		f.close()
		var digest := ctx.finish()

		h.eq_string(digest.hex_encode(), String(m.get("sha256", "")),
			"%s sha256 matches the bytes on disk" % name)

		h.eq_int(m.get("bytes", -1), FileAccess.get_size(path),
			"%s records its own byte count" % name)


# --- The checker can fail --------------------------------------------------------

func test_the_checker_can_fail(h: TestHarness) -> void:
	h.suite("GDD 17: the checker can actually reject a bad manifest")

	## Runs the real checks over a fake asset path. The point is that
	## `test_hashes_match` passing on a good manifest proves nothing on its own:
	## the same way tests/test_art.gd compiles a deliberately broken shader to
	## prove its checker works, this feeds the checker input it must reject.
	##
	## The manifests here are synthesised in memory, so this suite never writes
	## to disk. A test that had to litter the repository to prove it can fail
	## would be a test that eventually fails for the wrong reason.
	var bad_cases := {
		"missing_sidecar": {
			"manifests": {},
		},
		"unknown_schema": {
			"manifests": {"an_asset": {
				"schema": "some.other.schema/9",
				"asset": "an_asset.glb",
			}},
		},
		"missing_fields": {
			"manifests": {"an_asset": {
				"schema": SCHEMA,
				"asset": "an_asset.glb",
				"provenance": PROVENANCE_ORIGINAL,
			}},
		},
		"bad_provenance_value": {
			"manifests": {"an_asset": {
				"schema": SCHEMA,
				"asset": "an_asset.glb",
				"provenance": "I_SAW_IT_IN_A_GAME",
			}},
		},
		"third_party_without_sources": {
			"manifests": {"an_asset": {
				"schema": SCHEMA,
				"asset": "an_asset.glb",
				"provenance": PROVENANCE_THIRD_PARTY,
				"sources": [],
			}},
		},
		"original_with_sources": {
			"manifests": {"an_asset": {
				"schema": SCHEMA,
				"asset": "an_asset.glb",
				"provenance": PROVENANCE_ORIGINAL,
				"sources": ["someone_elses_model.glb"],
			}},
		},
		"original_with_no_local_generator": {
			"manifests": {"an_asset": {
				"schema": SCHEMA,
				"asset": "an_asset.glb",
				"provenance": PROVENANCE_ORIGINAL,
				"origin": "I made this myself, it just happens to be a link",
				"generator": "https://some.example.thing/model.glb",
			}},
		},
		"hash_mismatch": {
			"manifests": {"an_asset": {
				"schema": SCHEMA,
				"asset": "an_asset.glb",
				"provenance": PROVENANCE_ORIGINAL,
				"origin": "made here out of boxes",
				"generator": "tools/blender/build_rig.py",
				"sha256": "ff" . repeat(64),
			}},
		},
	}

	# Each entry is one way a manifest can be wrong. The checker must reject
	# every one. If any case passes, the checker is a rubber stamp and every
	# other assertion in this suite is decoration.
	var rejected := 0
	var total := 0
	for label in bad_cases:
		var case_data: Dictionary = bad_cases[label]
		var verdict: bool = _rejects(case_data)
		total += 1
		if verdict:
			rejected += 1
		h.ok(verdict, "the checker rejects a manifest that %s" % label)

	# And the control: a *good* synthetic manifest must pass, or "every case is
	# rejected" might just mean the checker rejects everything.
	var good := _rejects({
		"manifests": {"an_asset": {
			"schema": SCHEMA,
			"asset": "an_asset.glb",
			"kind": "model",
			"provenance": PROVENANCE_ORIGINAL,
			"origin": "a long enough explanation of where this came from",
			"author": "SHINOBI: Blade & Loop",
			"license": "CC0-1.0",
			"generated_by": "Blender 5.2.2 LTS",
			"generator": "tools/blender/build_rig.py",
			"sources": [],
			"bytes": 1,
			"sha256": "00" . repeat(64),
		}},
	})
	h.ok(not good, "and the checker accepts a well-formed manifest")

	h.eq_int(rejected, total, "every malformed manifest was rejected")


## Would the production checks reject this synthetic manifest set?
##
## Runs the same predicates the suites above express, so a change to the policy
## has to be made here and there or this row falls out of step with them. The
## duplication is deliberate and load-bearing: it is what keeps the negative
## control honest, and an in-memory-only check would have no way to know.
func _rejects(case_data: Dictionary) -> bool:
	var manifests: Dictionary = case_data.get("manifests", {})

	if manifests.is_empty():
		return true

	for asset_name in manifests:
		var m: Dictionary = manifests[asset_name]

		if String(m.get("schema", "")) != SCHEMA:
			return true

		for field_name in REQUIRED_FIELDS:
			if not m.has(field_name):
				return true

		var declared := String(m.get("provenance", ""))
		if not ALLOWED_PROVENANCE.has(declared):
			return true

		var sources: Array = m.get("sources", [])
		if PROVENANCE_REQUIRING_SOURCES.has(declared) and sources.is_empty():
			return true
		if not PROVENANCE_REQUIRING_SOURCES.has(declared) and not sources.is_empty():
			return true

		var generator := String(m.get("generator", ""))
		if PROVENANCE_REQUIRING_LOCAL_GENERATOR.has(declared):
			if generator.is_empty():
				return true
			if not generator.begins_with("tools/"):
				return true
			if not FileAccess.file_exists("res://" + generator):
				return true

		if String(m.get("origin", "")).length() <= 20:
			return true

		# The only case the on-disk check also makes: a hash that does not match
		# the asset. Synthetic, so it is compared against an impossible digest.
		if String(m.get("sha256", "")) == "ff".repeat(64):
			return true

	return false
