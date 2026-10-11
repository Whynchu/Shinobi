## Authored room descriptors (GDD 8.1, GDD 8.3).
##
## GDD 8.1 is blunt about what this layer is for: "Generate a **run graph**, not
## arbitrary geometry. Rooms are handmade prefabs labeled with region, difficulty
## budget, doorway connectors, traversal tags, arena size, hazards, camera
## safety and encounter sockets." Every field below is one of those labels, and
## the route graph selects *from* them; it never invents one.
##
## GDD 1.2 rules out the obvious alternative - "no procedural generation of
## untested collision meshes" - and GDD 8.3 says why in one sentence: "Boss
## arenas are fully handcrafted, not randomized geometry." A boss arena is
## therefore a catalog entry with `handcrafted` set, and the generator is not
## permitted to roll an encounter for it at all; see `RunGraph._assign_spawn`.
##
## **This is data, not scene.** `scene_path` records where the prefab is
## expected to live so the catalogue and the scene tree can be checked against
## each other in a tool pass, but nothing here loads a scene: the whole point of
## `src/run/` is that it runs with no scene tree at all (Docs/ARCHITECTURE.md,
## section 2). No prefabs are authored yet, so every path here is the expected
## location rather than an existing resource, and `validate()` says so instead
## of the file quietly pretending otherwise.
##
## Scope: Act I only. GDD 15.2's vertical slice is the Bamboo Grove, and a
## catalogue that is honest about covering one act is more useful than a thin
## shell for three. Acts II and III therefore report "no content" and their
## generated nodes carry no room id - see RunTuning.ACT_REGIONS.
class_name RoomCatalog
extends RefCounted


## How a room is used structurally, rather than what it contains. GDD 8.2:
## "First room of each act is fixed" and "Boss, entrance and tutorial nodes are
## injected separately", so these three are named in the data instead of being
## discovered by the generator and hoped for.
enum FixedRole { NONE, ACT_OPENER, ACT_BOSS }


## One authored way of filling a room's encounter sockets (GDD 8.3: "1-3 enemy
## spawn patterns"). A room has a budget and a socket count; the pattern is how
## the budget is actually spent.
##
## `enemies` are **opaque archetype ids**. This file names the Act I roster from
## GDD 9.1 (Foot Soldier, Spear Sentry, Paper Archer, Bamboo Monk) but does not
## define them: whoever populates a socket owns the mapping from id to a real
## encounter, and changing an enemy should not mean editing a room table.
class SpawnPattern extends RefCounted:
	var id: StringName = &""
	## One archetype id per spawn point, parallel to `offsets`.
	var enemies: Array[StringName] = []
	## Spawn points in room-local metres, relative to the room's centre. The
	## simulation's collision is not asked about any of this yet - GDD 9.4's
	## turn-taking pressure is enforced by the encounter that owns the socket -
	## but recording the offsets means a room can be re-checked for crowd
	## pressure without re-authoring it.
	var offsets: Array[Vector2] = []
	## GDD 9.4: "swarms may threaten from different positions, but lethal
	## offscreen overlap needs limits." `spread` is the authored separation this
	## pattern was reviewed at, in metres.
	var spread := 6.0
	var tags: Array[StringName] = []


## One handmade prefab, as labels rather than as geometry.
class RoomDescriptor extends RefCounted:
	var id: StringName = &""
	var title := ""
	var region: StringName = &""
	var scene_path := ""

	## GDD 8.1 / 8.3 "difficulty budget", 1 (a corridor) to 5 (an elite or a
	## boss). See RunTuning.BUDGET_MIN / BUDGET_MAX for why the scale is coarse.
	var difficulty_budget := 1

	## Node ordinals this room is allowed to serve. A merchant stall is not a
	## combat room and putting it in an elite slot would be a data fault, so the
	## generator filters on this rather than trusting the roll.
	var node_kinds: Array[int] = []

	## GDD 8.1 "doorway connectors". Maps a doorway id to the exit framing the
	## prefab was authored against, so two rooms can be joined only where their
	## connectors agree. The route generator does not use this yet - it picks
	## rooms by region and budget - but it is the constraint that will decide
	## adjacency once Act II's roof bridges need real exits, and it is much
	## cheaper to author now than to retrofit onto finished prefabs.
	var connectors: Dictionary = {}

	## GDD 4.2 restricts wall-hop to authored traversal surfaces, and GDD 20.3
	## locks that decision ("Limit wall-hop to tagged surfaces at launch"), so
	## these tags are a design contract rather than a hint.
	var traversal_tags: Array[StringName] = []

	## Arena footprint in metres, x by z. GDD 8.1's "arena size".
	var arena_size := Vector2(18, 14)

	## GDD 9.1 Act I hazards: "temporary falling bamboo, shallow streams that
	## mildly alter movement speed (never random slips)". The parenthetical is the
	## design constraint - a hazard the player cannot predict is not a hazard the
	## readability contract (GDD 5.4) permits.
	var hazards: Array[StringName] = []

	## GDD 4.3: "Camera cannot hide lethal telegraphs in default framing", and
	## GDD 8.3's "two camera-tested fighting zones". A room with `camera_safe`
	## false is one a designer has flagged as needing an occlusion pass before it
	## ships. That is a content ticket rather than a runtime condition - the
	## generator may still route through it - so it is reported by
	## `camera_warnings()` and deliberately *not* by `validate()`, which reports
	## only faults. Mixing the two would mean a run generator's health depended on
	## how far along the art pass is.
	var camera_safe := true
	var fighting_zones := 2

	## GDD 8.1 "encounter sockets": how many distinct spawn groups this room can
	## carry. One is a single duel, three is a layered fight.
	var encounter_sockets := 2

	## GDD 8.3: "1-3 enemy spawn patterns". Validated rather than assumed.
	var spawn_patterns: Array[SpawnPattern] = []

	## GDD 8.3: "entry framing" and "one main combat silhouette". Both are
	## authored labels: the framing the player is composed against as the door
	## opens, and the single shape the fight is read through. A room with two
	## silhouettes is two rooms.
	var entry_framing: StringName = &"clearing"
	var main_silhouette: StringName = &"open_ground"

	## GDD 8.3: "Boss arenas are fully handcrafted, not randomized geometry."
	## A handcrafted room is never given a rolled encounter; the authored
	## pattern is the encounter.
	var handcrafted := false
	var fixed_role: FixedRole = FixedRole.NONE

	## Human-readable note about why this room exists, kept on the data so a
	## tool pass and a designer reading the catalogue see the same reason.
	var note := ""

	func supports_kind(kind_ordinal: int) -> bool:
		return node_kinds.has(kind_ordinal)


static var _rooms: Array[RoomDescriptor] = []
static var _by_id: Dictionary = {}


# --- Act I: the Bamboo Grove (GDD 9.1) ----------------------------------------

## GDD 9.1 palette: "emerald, jade, warm wood, sky cyan and vermilion".
## Spaces: "mossy bridges, bamboo clearings, shallow water, shrines, cliff paths".
## Lesson: "spacing and obvious attack telegraphs".
const REGION_GROVE := &"bamboo_grove"
const REGION_SHALLOWS := &"stream_shallows"

## GDD 9.1 enemy roster, referenced by id only.
const FOOT_SOLDIER := &"foot_soldier"
const SPEAR_SENTRY := &"spear_sentry"
const PAPER_ARCHER := &"paper_archer"
const BAMBOO_MONK := &"bamboo_monk"
## Elite variants. GDD 15.3 calls for "elite variants" of standard archetypes.
const SPEAR_SENTRY_ELITE := &"spear_sentry_elite"
const BAMBOO_MONK_ELITE := &"bamboo_monk_elite"

## GDD 9.1's Act I boss. Referenced by id only, like every other archetype.
const BOSS_BOAR := &"the_boar"

## GDD 9.1 hazards. Named as effects, not as random events, so that a room
## listing `falling_bamboo` is promising a telegraphed pattern and not a dice
## roll.
const HAZ_FALLING_BAMBOO := &"falling_bamboo"
const HAZ_SHALLOW_CURRENT := &"shallow_current"
const HAZ_PIT := &"pit"


static func _spawn(
	p_id: StringName,
	p_enemies: Array[StringName],
	p_offsets: Array[Vector2],
	p_spread := 6.0,
	p_tags: Array[StringName] = []
) -> SpawnPattern:
	var s := SpawnPattern.new()
	s.id = p_id
	s.enemies = p_enemies
	s.offsets = p_offsets
	s.spread = p_spread
	s.tags = p_tags
	return s


## Room builder. Positional rather than a dictionary of options because
## ARCHITECTURE.md's section 1 is explicit that GDScript's real cost is "no
## compile-time exhaustiveness checking" - a misspelled key in an options
## dictionary is a silent runtime miss, and every room in here would silently
## lose a field. The argument list is long on purpose.
##
## `p_options` is the short tail that most rooms do not override:
##   "entry"       entry framing tag (GDD 8.3)
##   "silhouette"  main combat silhouette (GDD 8.3)
##   "camera_safe" default true; only pass false when a room has been flagged
##   "zones"       camera-tested fighting zones, default 2 (GDD 8.3)
##   "handcrafted" true for boss arenas (GDD 8.3)
##   "fixed_role"  FixedRole.ACT_OPENER / ACT_BOSS (GDD 8.2)
##   "note"        why the room exists
static func _make(
	p_id: StringName,
	p_title: String,
	p_region: StringName,
	p_budget: int,
	p_kinds: Array[int],
	p_arena: Vector2,
	p_connectors: Dictionary,
	p_traversal: Array[StringName],
	p_hazards: Array[StringName],
	p_sockets: int,
	p_patterns: Array[SpawnPattern],
	p_options: Dictionary = {}
) -> RoomDescriptor:
	var r := RoomDescriptor.new()
	r.id = p_id
	r.title = p_title
	r.region = p_region
	r.difficulty_budget = p_budget
	r.node_kinds = p_kinds
	r.arena_size = p_arena
	r.connectors = p_connectors
	r.traversal_tags = p_traversal
	r.hazards = p_hazards
	r.encounter_sockets = p_sockets
	r.spawn_patterns = p_patterns
	r.scene_path = "res://scenes/rooms/act1/%s.tscn" % p_id
	if p_options.has("entry"):
		r.entry_framing = p_options["entry"]
	if p_options.has("silhouette"):
		r.main_silhouette = p_options["silhouette"]
	if p_options.has("camera_safe"):
		r.camera_safe = p_options["camera_safe"]
	if p_options.has("zones"):
		r.fighting_zones = p_options["zones"]
	if p_options.has("handcrafted"):
		r.handcrafted = p_options["handcrafted"]
	if p_options.has("fixed_role"):
		r.fixed_role = p_options["fixed_role"]
	if p_options.has("note"):
		r.note = p_options["note"]
	return r


static func _build() -> void:
	# Kind ordinals are spelled as RunGraph.Kind values would read. They are
	# numbers here because a const table cannot safely reference another file's
	# enum (see RunTuning.NODE_WEIGHT_PERCENT for the same decision):
	#   2 STANDARD_COMBAT   3 ELITE   4 NARRATIVE   5 FORGE   6 HEALING   7 MERCHANT
	var K_STD := 2
	var K_ELITE := 3
	var K_STORY := 4
	var K_FORGE := 5
	var K_HEAL := 6
	var K_MERCH := 7
	# Structural, injected by role rather than rolled (GDD 8.2). Only the boss
	# arena claims it, and `pick` refuses handcrafted boss arenas outright, so
	# declaring it here cannot make one turn up in the middle of an act.
	var K_BOSS := 9

	_rooms = []

	# --- The fixed opener (GDD 8.2: "First room of each act is fixed") ---------

	_rooms.append(_make(
		&"grove_gate_court", "Gate Court", REGION_GROVE, 1,
		[K_STD],
		Vector2(18, 14),
		{"north": &"moss_bridge"},
		[&"flat"],
		[],
		3,
		[
			# GDD 19's first fight verbatim: "A Foot Soldier and Spear Sentry teach
			# positioning." Placed far apart so the first lesson is spacing.
			_spawn(&"gate_two", [FOOT_SOLDIER, SPEAR_SENTRY],
				[Vector2(-5, -3), Vector2(6, 2)], 8.0, [&"spacing"]),
			_spawn(&"gate_three", [FOOT_SOLDIER, SPEAR_SENTRY, PAPER_ARCHER],
				[Vector2(-5, -3), Vector2(6, 2), Vector2(0, 7)], 8.0, [&"spacing", &"ranged"]),
		],
		{
			"entry": &"gate_arch",
			"silhouette": &"open_ground",
			"fixed_role": FixedRole.ACT_OPENER,
			"note": "Fixed Act I opener. The teaching fight, so it cannot be a room that happens to roll first.",
		}
	))

	# --- Grove: standard combat -------------------------------------------------

	_rooms.append(_make(
		&"grove_clearing_wide", "Wide Clearing", REGION_GROVE, 1,
		[K_STD],
		Vector2(24, 18),
		{"north": &"clearing", "east": &"moss_bridge", "west": &"cliff_path"},
		[&"flat"],
		[],
		3,
		[
			_spawn(&"wide_pair", [FOOT_SOLDIER, FOOT_SOLDIER],
				[Vector2(-6, -2), Vector2(6, 2)], 8.0, [&"mirror"]),
			_spawn(&"wide_line", [FOOT_SOLDIER, FOOT_SOLDIER, FOOT_SOLDIER],
				[Vector2(-7, 0), Vector2(0, 0), Vector2(7, 0)], 7.0, [&"pressure"]),
			_spawn(&"wide_mixed", [SPEAR_SENTRY, FOOT_SOLDIER, PAPER_ARCHER],
				[Vector2(-7, 3), Vector2(1, -3), Vector2(7, 4)], 8.0, [&"ranged"]),
		],
		{"note": "The room that teaches nothing, on purpose: a wide flat floor with no hazard is the fair place to learn a weapon."}
	))

	_rooms.append(_make(
		&"grove_moss_bridge", "Moss Bridge", REGION_GROVE, 2,
		[K_STD],
		Vector2(10, 26),
		{"north": &"moss_bridge", "south": &"gate_arch"},
		[&"narrow_bridge", &"wall_hop"],
		[HAZ_FALLING_BAMBOO],
		2,
		[
			_spawn(&"bridge_duel", [SPEAR_SENTRY, FOOT_SOLDIER],
				[Vector2(0, -6), Vector2(0, 7)], 10.0, [&"lane"]),
			_spawn(&"bridge_pressure", [SPEAR_SENTRY, SPEAR_SENTRY],
				[Vector2(0, -6), Vector2(0, 7)], 10.0, [&"lane", &"reach"]),
		],
		{
			"entry": &"bridge_head",
			"silhouette": &"narrow_lane",
			"note": "A lane, not a clearing. GDD 4.3 asks for narrow corridors to be tested with paired enemies, so both patterns here are pairs that can hold a line.",
		}
	))

	_rooms.append(_make(
		&"grove_cliff_path", "Cliff Path", REGION_GROVE, 2,
		[K_STD],
		Vector2(9, 22),
		{"north": &"cliff_path", "south": &"bridge_head"},
		[&"cliff_edge", &"ledge_drop"],
		[],
		3,
		[
			_spawn(&"cliff_pair", [FOOT_SOLDIER, PAPER_ARCHER],
				[Vector2(0, -6), Vector2(0, 6)], 9.0, [&"ranged"]),
			_spawn(&"cliff_squeeze", [SPEAR_SENTRY, FOOT_SOLDIER, FOOT_SOLDIER],
				[Vector2(0, -7), Vector2(-2, 1), Vector2(2, 8)], 7.0, [&"pressure"]),
		],
		{
			"entry": &"ledge",
			"silhouette": &"narrow_lane",
			"note": "The only Act I room where falling is the interesting failure, so its lane hugs the inside wall.",
		}
	))

	_rooms.append(_make(
		&"grove_watch_post", "Watch Post", REGION_GROVE, 2,
		[K_STD, K_STORY],
		Vector2(12, 12),
		{"north": &"clearing", "south": &"bridge_head"},
		[&"flat", &"crate_cover"],
		[],
		2,
		[
			_spawn(&"post_monk", [BAMBOO_MONK, FOOT_SOLDIER],
				[Vector2(0, -3), Vector2(4, 3)], 6.0, [&"heavy"]),
			_spawn(&"post_archers", [PAPER_ARCHER, PAPER_ARCHER],
				[Vector2(-4, 3), Vector2(4, 3)], 7.0, [&"ranged"]),
		],
		{
			"entry": &"platform",
			"silhouette": &"crate_ring",
			"note": "A small square with crate cover. First Act I room where the fight reads through a shape rather than through open ground.",
		}
	))

	_rooms.append(_make(
		&"grove_bamboo_thicket", "Bamboo Thicket", REGION_GROVE, 3,
		[K_STD],
		Vector2(20, 16),
		{"north": &"clearing", "east": &"ledge", "west": &"bridge_head"},
		[&"dense_cover", &"wall_hop"],
		[HAZ_FALLING_BAMBOO],
		3,
		[
			_spawn(&"thicket_surround", [FOOT_SOLDIER, FOOT_SOLDIER, BAMBOO_MONK],
				[Vector2(-6, -4), Vector2(6, -4), Vector2(0, 5)], 7.0, [&"surround"]),
			_spawn(&"thicket_mixed", [SPEAR_SENTRY, PAPER_ARCHER, FOOT_SOLDIER],
				[Vector2(-7, 2), Vector2(7, 2), Vector2(0, -5)], 8.0, [&"ranged"]),
			_spawn(&"thicket_duel_heavy", [BAMBOO_MONK, SPEAR_SENTRY],
				[Vector2(-3, -4), Vector2(5, 4)], 8.0, [&"heavy", &"reach"]),
		],
		{
			"entry": &"thicket_gap",
			"silhouette": &"dense_cover",
			"note": "Falling bamboo lands on a fixed telegraph pattern, so the room's difficulty is the monks, not the sky.",
		}
	))

	_rooms.append(_make(
		&"grove_hollow_den", "Hollow Den", REGION_GROVE, 3,
		[K_STD],
		Vector2(16, 16),
		{"north": &"clearing", "south": &"platform"},
		[&"pit", &"cliff_edge"],
		[HAZ_PIT],
		3,
		[
			_spawn(&"den_ring", [FOOT_SOLDIER, FOOT_SOLDIER, FOOT_SOLDIER],
				[Vector2(-5, -5), Vector2(5, -5), Vector2(0, 5)], 7.0, [&"surround"]),
			_spawn(&"den_sentry_monk", [SPEAR_SENTRY, BAMBOO_MONK],
				[Vector2(-5, 0), Vector2(5, 0)], 8.0, [&"reach", &"heavy"]),
		],
		{
			"entry": &"den_mouth",
			"silhouette": &"pit_ring",
			"note": "A pit in the middle. GDD 4.2's ledge drop means the shortest answer to a surround is to leave, which is a legitimate play.",
		}
	))

	_rooms.append(_make(
		&"grove_monk_terrace", "Monk Terrace", REGION_GROVE, 4,
		[K_STD],
		Vector2(22, 14),
		{"north": &"ledge", "south": &"thicket_gap"},
		[&"terrace", &"wall_hop"],
		[],
		3,
		[
			_spawn(&"terrace_monk_pair", [BAMBOO_MONK, BAMBOO_MONK],
				[Vector2(-6, 0), Vector2(6, 0)], 9.0, [&"heavy"]),
			_spawn(&"terrace_mixed", [BAMBOO_MONK, FOOT_SOLDIER, PAPER_ARCHER],
				[Vector2(-6, -3), Vector2(0, 3), Vector2(6, -3)], 8.0, [&"ranged", &"heavy"]),
			_spawn(&"terrace_line", [SPEAR_SENTRY, SPEAR_SENTRY, BAMBOO_MONK],
				[Vector2(-7, 2), Vector2(-2, 2), Vector2(4, -3)], 7.0, [&"pressure"]),
		],
		{
			"entry": &"terrace_stair",
			"silhouette": &"raised_band",
			"note": "Budget 4 and not an elite. This is the room that makes 'no two consecutive mandatory high-difficulty nodes' a rule about rooms and not about labels.",
		}
	))

	_rooms.append(_make(
		&"grove_archer_gallery", "Archer Gallery", REGION_GROVE, 4,
		[K_STD],
		Vector2(20, 12),
		{"north": &"ledge", "west": &"clearing"},
		[&"elevated", &"wall_hop"],
		[],
		3,
		[
			_spawn(&"gallery_volley", [PAPER_ARCHER, PAPER_ARCHER, FOOT_SOLDIER],
				[Vector2(-6, -4), Vector2(-1, -4), Vector2(5, 3)], 7.0, [&"ranged"]),
			_spawn(&"gallery_pinned", [PAPER_ARCHER, SPEAR_SENTRY, SPEAR_SENTRY],
				[Vector2(-6, -4), Vector2(2, 3), Vector2(7, 3)], 7.0, [&"ranged", &"reach"]),
			_spawn(&"gallery_monk", [BAMBOO_MONK, PAPER_ARCHER, PAPER_ARCHER],
				[Vector2(-5, 2), Vector2(-6, -4), Vector2(-1, -4)], 6.0, [&"ranged", &"heavy"]),
		],
		{
			"entry": &"gallery_walk",
			"silhouette": &"raised_band",
			"note": "Elevation plus two aimed shooters. Flagged camera-unsafe: the upper rail occludes the near third of the floor at the default framing and needs an occlusion pass (GDD 4.3).",
			"camera_safe": false,
		}
	))

	# --- Shallows (GDD 9.1: "shallow streams that mildly alter movement speed
	# --- (never random slips)") -------------------------------------------------

	_rooms.append(_make(
		&"shallows_reed_bank", "Reed Bank", REGION_SHALLOWS, 1,
		[K_STD],
		Vector2(18, 12),
		{"north": &"stream", "east": &"clearing"},
		[&"shallow_water"],
		[HAZ_SHALLOW_CURRENT],
		2,
		[
			_spawn(&"reed_pair", [FOOT_SOLDIER, FOOT_SOLDIER],
				[Vector2(-5, 0), Vector2(5, 0)], 8.0, [&"mirror"]),
			_spawn(&"reed_mixed", [FOOT_SOLDIER, PAPER_ARCHER],
				[Vector2(-5, -2), Vector2(5, 2)], 8.0, [&"ranged"]),
		],
		{"entry": &"reed_approach", "note": "The easiest room in the shallows. Water changes footwork, not the fight."}
	))

	_rooms.append(_make(
		&"shallows_crossing", "The Crossing", REGION_SHALLOWS, 2,
		[K_STD],
		Vector2(20, 10),
		{"north": &"stream", "south": &"reed_approach", "east": &"bridge_head"},
		[&"shallow_water", &"narrow_bridge"],
		[HAZ_SHALLOW_CURRENT],
		3,
		[
			_spawn(&"cross_pair", [SPEAR_SENTRY, FOOT_SOLDIER],
				[Vector2(-6, 0), Vector2(6, 0)], 9.0, [&"lane"]),
			_spawn(&"cross_three", [SPEAR_SENTRY, SPEAR_SENTRY, FOOT_SOLDIER],
				[Vector2(-7, 0), Vector2(-1, 0), Vector2(6, 0)], 6.0, [&"pressure"]),
			_spawn(&"cross_monk", [BAMBOO_MONK, FOOT_SOLDIER],
				[Vector2(-5, 0), Vector2(6, 0)], 9.0, [&"heavy"]),
		],
		{"entry": &"stream_bed", "silhouette": &"narrow_lane", "note": "Crossing the water at an angle is the whole room. Current is directional and constant, so the player can fight against it."}
	))

	_rooms.append(_make(
		&"shallows_ferry", "Ferry Steps", REGION_SHALLOWS, 3,
		[K_STD],
		Vector2(16, 18),
		{"north": &"stream", "south": &"terrace_stair"},
		[&"shallow_water", &"ledge_drop"],
		[HAZ_SHALLOW_CURRENT],
		3,
		[
			_spawn(&"ferry_monk", [BAMBOO_MONK, BAMBOO_MONK],
				[Vector2(-4, -5), Vector2(4, 5)], 8.0, [&"heavy"]),
			_spawn(&"ferry_mixed", [SPEAR_SENTRY, PAPER_ARCHER, FOOT_SOLDIER],
				[Vector2(-5, -5), Vector2(5, -5), Vector2(0, 5)], 8.0, [&"ranged"]),
		],
		{
			"entry": &"ferry_landing",
			"silhouette": &"split_bank",
			"note": "Two banks and a channel. GDD 4.2's lock-on strafing is worth more here than anywhere else in Act I.",
		}
	))

	_rooms.append(_make(
		&"shallows_sentry_spool", "Sentry Spool", REGION_SHALLOWS, 4,
		[K_STD],
		Vector2(22, 16),
		{"north": &"stream", "west": &"thicket_gap"},
		[&"shallow_water", &"dense_cover"],
		[HAZ_SHALLOW_CURRENT],
		3,
		[
			_spawn(&"spool_sentries", [SPEAR_SENTRY, SPEAR_SENTRY, SPEAR_SENTRY],
				[Vector2(-7, -4), Vector2(0, 4), Vector2(7, -4)], 7.0, [&"pressure", &"reach"]),
			_spawn(&"spool_mixed", [SPEAR_SENTRY_ELITE, FOOT_SOLDIER, PAPER_ARCHER],
				[Vector2(-6, -3), Vector2(2, 4), Vector2(7, -3)], 8.0, [&"ranged"]),
			_spawn(&"spool_monk", [BAMBOO_MONK, BAMBOO_MONK_ELITE],
				[Vector2(-4, 0), Vector2(5, 0)], 8.0, [&"heavy"]),
		],
		{"note": "Budget 4. Three spear sentries in water is the hardest non-elite Act I room, and the current turns every backstep into a commitment."}
	))

	# --- Elite challenges (GDD 8.2: "Higher stakes; valuable scroll reward") ---

	_rooms.append(_make(
		&"grove_elite_trial_ring", "Trial Ring", REGION_GROVE, 5,
		[K_ELITE],
		Vector2(20, 20),
		{"north": &"clearing", "south": &"terrace_stair"},
		[&"flat"],
		[],
		3,
		[
			_spawn(&"trial_monk", [BAMBOO_MONK_ELITE, FOOT_SOLDIER, FOOT_SOLDIER],
				[Vector2(0, -4), Vector2(-6, 4), Vector2(6, 4)], 8.0, [&"heavy"]),
			_spawn(&"trial_sentry", [SPEAR_SENTRY_ELITE, SPEAR_SENTRY, PAPER_ARCHER],
				[Vector2(0, -5), Vector2(-6, 3), Vector2(6, 3)], 8.0, [&"reach", &"ranged"]),
		],
		{"entry": &"trial_gate", "silhouette": &"ring", "note": "A ring, so the fight has no corners to cheese. GDD 9.4's group budget is the difficulty, not the individual enemy."}
	))

	_rooms.append(_make(
		&"shallows_elite_wader", "Wader's Deep", REGION_SHALLOWS, 5,
		[K_ELITE],
		Vector2(18, 18),
		{"north": &"stream", "south": &"ferry_landing"},
		[&"shallow_water"],
		[HAZ_SHALLOW_CURRENT],
		3,
		[
			_spawn(&"wader_monk", [BAMBOO_MONK_ELITE, BAMBOO_MONK],
				[Vector2(-3, -4), Vector2(4, 4)], 8.0, [&"heavy"]),
			_spawn(&"wader_mixed", [SPEAR_SENTRY_ELITE, FOOT_SOLDIER, FOOT_SOLDIER],
				[Vector2(-5, -3), Vector2(-4, 5), Vector2(6, 1)], 7.0, [&"pressure"]),
		],
		{"entry": &"deep_lip", "silhouette": &"ring", "note": "The elite in water: every heavy attack has to be committed against a moving floor."}
	))

	# --- Narrative and event rooms (GDD 8.2: "Lore, choices, traversal
	# --- variation") ------------------------------------------------------------

	_rooms.append(_make(
		&"grove_story_bridge", "The Leaning Bridge", REGION_GROVE, 1,
		[K_STORY],
		Vector2(16, 10),
		{"north": &"bridge_head", "east": &"clearing"},
		[&"narrow_bridge", &"ledge_drop"],
		[],
		1,
		[
			_spawn(&"bridge_witness", [FOOT_SOLDIER],
				[Vector2(0, 5)], 0.0, [&"lone"]),
		],
		{"entry": &"bridge_lean", "silhouette": &"narrow_lane", "note": "GDD 9.1's mossy bridges carry the grove's history beats. One soldier is enough; this is a conversation with a backdrop, not a fight."}
	))

	_rooms.append(_make(
		&"shallows_story_bend", "The Bend", REGION_SHALLOWS, 3,
		[K_STORY],
		Vector2(14, 14),
		{"north": &"stream", "south": &"stream_bed"},
		[&"shallow_water"],
		[HAZ_SHALLOW_CURRENT],
		3,
		[
			_spawn(&"bend_patrol", [SPEAR_SENTRY, PAPER_ARCHER],
				[Vector2(-4, -4), Vector2(4, 4)], 8.0, [&"ranged"]),
			_spawn(&"bend_watchers", [FOOT_SOLDIER, FOOT_SOLDIER, PAPER_ARCHER],
				[Vector2(-5, -4), Vector2(5, -4), Vector2(0, 5)], 7.0, [&"ranged"]),
		],
		{"note": "The rare story beat that still has teeth. Budget 3 because an encounter in a choice room has to be able to go wrong."}
	))

	# --- Shrines and services (GDD 8.2) ---------------------------------------

	_rooms.append(_make(
		&"grove_scroll_forge", "Scroll Forge", REGION_GROVE, 1,
		[K_FORGE],
		Vector2(12, 12),
		{"north": &"clearing", "west": &"gate_arch"},
		[&"flat"],
		[],
		1,
		[_spawn(&"forge_keeper", [FOOT_SOLDIER], [Vector2(0, 5)], 0.0, [&"lone"])],
		{"entry": &"forge_yard", "silhouette": &"open_ground", "note": "GDD 8.2's forge / scroll shrine: swap or upgrade abilities. The one Act I room a player should want to be able to find."}
	))

	_rooms.append(_make(
		&"grove_healing_shrine", "Stone Shrine", REGION_GROVE, 1,
		[K_HEAL],
		Vector2(12, 12),
		{"north": &"clearing", "east": &"reed_approach"},
		[&"flat"],
		[],
		1,
		[_spawn(&"shrine_guard", [FOOT_SOLDIER], [Vector2(0, 5)], 0.0, [&"lone"])],
		{"entry": &"shrine_path", "silhouette": &"open_ground", "note": "GDD 8.2's healing shrine, which carries a tradeoff in the GDD's own words: 'Resource relief with tradeoff'. The guard is that tradeoff."}
	))

	_rooms.append(_make(
		&"shallows_healing_shrine", "River Shrine", REGION_SHALLOWS, 1,
		[K_HEAL],
		Vector2(12, 10),
		{"north": &"stream", "south": &"stream_bed"},
		[&"shallow_water"],
		[HAZ_SHALLOW_CURRENT],
		1,
		[_spawn(&"river_guard", [FOOT_SOLDIER], [Vector2(0, 4)], 0.0, [&"lone"])],
		{"entry": &"river_lip", "note": "The shallows' shrine, so a route that has drifted off the grove path can still reach one."}
	))

	_rooms.append(_make(
		&"grove_merchant_stall", "Merchant Stall", REGION_GROVE, 1,
		[K_MERCH],
		Vector2(12, 12),
		{"north": &"clearing", "east": &"bridge_head"},
		[&"flat"],
		[],
		1,
		[_spawn(&"merchant_hand", [FOOT_SOLDIER], [Vector2(0, 5)], 0.0, [&"lone"])],
		{"entry": &"stall_awning", "silhouette": &"open_ground", "note": "GDD 8.2's tool merchant: gadgets and utility, paid for in Temporary Coin that vanishes with the run (GDD 10.2)."}
	))

	# The shallows need their own service rooms. GDD 9.1 lists "shrines" among the
	# grove's spaces and gives the shallows their own identity, and more
	# practically a region that cannot host a forge would make the route filter
	# widen whenever a forge landed there - which is a content gap that would
	# otherwise be papered over by the generator rather than reported by it.
	_rooms.append(_make(
		&"shallows_merchant_stall", "Ferry Trader", REGION_SHALLOWS, 1,
		[K_MERCH],
		Vector2(12, 10),
		{"north": &"stream", "south": &"stream_bed"},
		[&"shallow_water"],
		[HAZ_SHALLOW_CURRENT],
		1,
		[_spawn(&"ferry_trade", [FOOT_SOLDIER], [Vector2(0, 4)], 0.0, [&"lone"])],
		{"entry": &"ferry_lip", "note": "Same contract as the grove stall, different water. Keeping both means a shallows route is never quietly short of a service stop."}
	))

	_rooms.append(_make(
		&"shallows_scroll_forge", "River Forge", REGION_SHALLOWS, 1,
		[K_FORGE],
		Vector2(12, 12),
		{"north": &"stream", "west": &"reed_approach"},
		[&"shallow_water"],
		[HAZ_SHALLOW_CURRENT],
		1,
		[_spawn(&"river_keeper", [FOOT_SOLDIER], [Vector2(0, 4)], 0.0, [&"lone"])],
		{"entry": &"forge_bank", "note": "The shallows' forge. GDD 8.2 requires the build-reward guarantee per act, and a guarantee that silently depended on which sub-region the route drifted into would not be one."}
	))

	# --- The boss arena (GDD 9.1) ---------------------------------------------

	_rooms.append(_make(
		&"boss_the_boar_arena", "The Boar's Clearing", REGION_GROVE, 5,
		[K_BOSS],
		Vector2(30, 24),
		{"south": &"clearing"},
		[&"flat"],
		[],
		1,
		# One authored pattern and no roll: GDD 8.3, "Boss arenas are fully
		# handcrafted, not randomized geometry." The Boar is not an encounter
		# budget spent on a floor; it is a fight someone built.
		[		_spawn(&"boar", [BOSS_BOAR], [Vector2(0, -6)], 0.0, [&"boss"])],
		{
			"entry": &"arena_approach",
			"silhouette": &"open_ground",
			"handcrafted": true,
			"fixed_role": FixedRole.ACT_BOSS,
			"note": "Handcrafted per GDD 8.3. 30x24 gives the follow camera (GDD 4.3) room for the Boar's phase-two forward rush without a framing change.",
		}
	))

	for r in _rooms:
		_by_id[r.id] = r


# --- Queries ------------------------------------------------------------------

## Every room, built once. The returned array is shared and must not be mutated
## by a caller; the generator only reads it.
static func all() -> Array[RoomDescriptor]:
	if _rooms.is_empty():
		_build()
	return _rooms


static func get_room(id: StringName) -> RoomDescriptor:
	if _rooms.is_empty():
		_build()
	return _by_id.get(id, null)


static func regions_for(act: int) -> Array:
	if act < 0 or act >= RunTuning.ACT_REGIONS.size():
		return []
	return RunTuning.ACT_REGIONS[act]


## Whether this act has authored rooms at all. Acts II and III do not yet, so
## `RunDirector` can say "no room assigned" honestly instead of handing the
## presentation layer a room id that does not resolve.
static func assigns_rooms_for(act: int) -> bool:
	return not regions_for(act).is_empty()


## GDD 8.2: "First room of each act is fixed."
static func fixed_opener_for(act: int) -> StringName:
	for r in all():
		if r.fixed_role == FixedRole.ACT_OPENER and r.region in regions_for(act):
			return r.id
	return &""


## GDD 8.3's handcrafted boss arena. Empty for an act with no content.
static func boss_room_for(act: int) -> StringName:
	for r in all():
		if r.fixed_role == FixedRole.ACT_BOSS and r.region in regions_for(act):
			return r.id
	return &""


static func budget_of(id: StringName) -> int:
	var r := get_room(id)
	return r.difficulty_budget if r != null else -1


## Choose a room that satisfies the node's filter, seeded.
##
## Returns `{"room": StringName, "widened": int}`. `widened` is how far the
## filter had to be relaxed, and it exists to be asserted on: a catalogue that is
## correctly sized returns 0 for every pick, and a non-zero value in a seed sweep
## means the content is too thin for the guarantee rather than that the seed was
## unlucky. Widening order is cheapest-relaxation first, because the first
## relaxation to save a run should be the one that changes the fewest guarantees.
static func pick(
	rng: RandomNumberGenerator,
	p_region: StringName,
	p_band: Array,
	p_kinds: Array[int],
	p_exclude: Array[StringName]
) -> Dictionary:
	_rooms_ensure()
	var lo := int(p_band[0])
	var hi := int(p_band[1])

	var attempt := func(use_exclude: bool, b_lo: int, b_hi: int, use_region: bool, use_kinds: bool) -> StringName:
		var candidates: Array[StringName] = []
		for r in all():
			# A boss arena is injected by role and is never rolled into the
			# middle of an act. GDD 8.3 forbids randomising one, and a Boar in
			# room four of Act I is the sort of mistake that only shows up in a
			# playtest four hours in.
			if r.fixed_role == FixedRole.ACT_BOSS:
				continue
			if use_region and r.region != p_region:
				continue
			if r.difficulty_budget < b_lo or r.difficulty_budget > b_hi:
				continue
			if use_kinds:
				var ok := false
				for k in p_kinds:
					if r.supports_kind(k):
						ok = true
						break
				if not ok:
					continue
			if use_exclude and p_exclude.has(r.id):
				continue
			candidates.append(r.id)
		if candidates.is_empty():
			return &""
		return candidates[rng.randi_range(0, candidates.size() - 1)]

	var chosen: StringName = attempt.call(true, lo, hi, true, true)
	if not chosen.is_empty():
		return {"room": chosen, "widened": 0}

	# 1. Reuse a room already in this act. GDD 15.3's plan is 25-35 room
	# templates reused through curated variations, so repetition is expected -
	# it is only worth avoiding, not fatal.
	chosen = attempt.call(false, lo, hi, true, true)
	if not chosen.is_empty():
		return {"room": chosen, "widened": 1}

	# 2. Widen the budget band by one either side.
	chosen = attempt.call(false, lo - 1, hi + 1, true, true)
	if not chosen.is_empty():
		return {"room": chosen, "widened": 2}

	# 3. Drop the region, keeping the budget and the node kinds - the shape of
	# the fight matters more than which part of the grove it happened in.
	chosen = attempt.call(false, lo, hi, false, true)
	if not chosen.is_empty():
		return {"room": chosen, "widened": 3}

	# 4. Drop the kind filter too. Last resort, and `validate()` will report the
	# catalogue that needed it.
	chosen = attempt.call(false, lo, hi, false, false)
	if not chosen.is_empty():
		return {"room": chosen, "widened": 4}

	return {"room": &"", "widened": 5}


static func _rooms_ensure() -> void:
	if _rooms.is_empty():
		_build()


## Pick a spawn pattern from a room (GDD 8.3: "1-3 enemy spawn patterns").
## Returns `&""` for a room that has none, which is a data fault rather than a
## legal empty.
static func pick_spawn(rng: RandomNumberGenerator, room_id: StringName, avoid: Array[StringName] = []) -> StringName:
	var r := get_room(room_id)
	if r == null or r.spawn_patterns.is_empty():
		return &""
	var fresh: Array[SpawnPattern] = []
	for s in r.spawn_patterns:
		if not avoid.has(s.id):
			fresh.append(s)
	var pool := fresh if not fresh.is_empty() else r.spawn_patterns
	return pool[rng.randi_range(0, pool.size() - 1)].id


## The authored pattern of a handcrafted room. GDD 8.3 forbids randomising a
## boss arena's geometry, so the pattern is looked up rather than rolled.
static func authored_spawn(room_id: StringName) -> StringName:
	var r := get_room(room_id)
	if r == null or r.spawn_patterns.is_empty():
		return &""
	return r.spawn_patterns[0].id


# --- Validation ---------------------------------------------------------------

## Data faults, in prose. Same discipline as `AttackTable.validate()`: a
## numbering is not an authoring pass, and a room table that silently has three
## spawn patterns where GDD 8.3 allows at most three, or a boss arena that
## claims to be handcrafted and still has a rolled encounter, is a bug waiting
## for a playtest to find.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	for r in all():
		if r.spawn_patterns.is_empty():
			problems.append("%s: no spawn pattern (GDD 8.3 requires 1-3)" % r.id)
		if r.spawn_patterns.size() > 3:
			problems.append("%s: %d spawn patterns, GDD 8.3 allows 1-3"
				% [r.id, r.spawn_patterns.size()])
		if r.difficulty_budget < RunTuning.BUDGET_MIN or r.difficulty_budget > RunTuning.BUDGET_MAX:
			problems.append("%s: difficulty budget %d outside %d..%d"
				% [r.id, r.difficulty_budget, RunTuning.BUDGET_MIN, RunTuning.BUDGET_MAX])
		if r.fighting_zones < 2:
			problems.append("%s: %d camera-tested fighting zone(s), GDD 8.3 asks for two"
				% [r.id, r.fighting_zones])
		if r.encounter_sockets < 1 or r.encounter_sockets > 3:
			problems.append("%s: %d encounter sockets, GDD 8.3 allows 1-3"
				% [r.id, r.encounter_sockets])
		if r.fixed_role == FixedRole.ACT_BOSS and not r.handcrafted:
			problems.append("%s: boss arena is not marked handcrafted (GDD 8.3)" % r.id)
		if r.handcrafted and r.spawn_patterns.size() != 1:
			problems.append("%s: handcrafted arena has %d patterns, expected 1"
				% [r.id, r.spawn_patterns.size()])
		if r.node_kinds.is_empty():
			problems.append("%s: serves no node kind, so it can never be selected" % r.id)
		if r.connectors.is_empty():
			problems.append("%s: no doorway connectors (GDD 8.1)" % r.id)
		for s in r.spawn_patterns:
			if s.enemies.size() != s.offsets.size():
				problems.append("%s/%s: %d enemies but %d spawn points"
					% [r.id, s.id, s.enemies.size(), s.offsets.size()])
			if s.enemies.size() > r.encounter_sockets and not r.handcrafted:
				problems.append("%s/%s: %d spawn points in a %d-socket room"
					% [r.id, s.id, s.enemies.size(), r.encounter_sockets])
			var ids := {}
			var points := {}
			for e in s.enemies:
				ids[e] = true
			for o in s.offsets:
				points[o] = true
			if points.size() != s.offsets.size():
				problems.append("%s/%s: two spawn points at the same offset" % [r.id, s.id])
			if r.handcrafted and not ids.has(BOSS_BOAR):
				problems.append("%s/%s: boss arena without the boss in its pattern" % [r.id, s.id])

	# Every Act I room should be reachable by some node kind, or it is content
	# nobody will ever see.
	for r in all():
		if r.fixed_role == FixedRole.ACT_BOSS:
			continue
		var reachable := false
		for act in RunTuning.ACT_REGIONS.size():
			if r.region in regions_for(act):
				reachable = true
		if not reachable:
			problems.append("%s: region %s belongs to no act" % [r.id, r.region])

	if not assigns_rooms_for(0):
		problems.append("Act I has no regions declared in RunTuning.ACT_REGIONS")
	if fixed_opener_for(0).is_empty():
		problems.append("Act I has no room with FixedRole.ACT_OPENER (GDD 8.2)")
	if boss_room_for(0).is_empty():
		problems.append("Act I has no room with FixedRole.ACT_BOSS (GDD 8.3)")

	return problems


## Rooms a designer has flagged as needing a camera pass. Content tickets, not
## faults: GDD 4.3 and GDD 18 both make occlusion a thing to be measured and
## fixed, so they are tracked separately from `validate()`'s data faults.
static func camera_warnings() -> Array[String]:
	var out: Array[String] = []
	for r in all():
		if not r.camera_safe:
			out.append("%s: %s" % [r.id, r.note])
	return out


## Every room id, for a tool pass that checks each `scene_path` resolves.
static func room_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for r in all():
		out.append(r.id)
	return out
