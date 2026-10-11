## The seeded route graph (GDD 8).
##
## GDD 8.4 is the requirement this file exists to satisfy: "Each run has a
## reproducible seed controlling route, room selection, encounters and reward
## offers. Record seed plus build and room-clear logs for bug reproduction."
## Every decision made here is therefore a pure function of the run seed, the
## authored room catalogue and nothing else - no clock, no global RNG, no
## dictionary iteration order, no unseeded generator. Give it a seed and a
## different process and it returns the same run, which is what makes
## `seed: 8413` a usable thing to paste into a bug report.
##
## ## What the graph actually is
##
## A *graph*, deliberately not a line and not a tree. GDD 8.2 requires "branch
## choices that preview risk and reward" and GDD 3.3's pacing beat is
## "standard fight -> route choice -> standard fight or event". The shape used
## here is a backbone with rejoining pockets:
##
##     entrance -> [tutorial] -> opener -> n1 -> FORK -+-> A -+-> n4 -> ...
##                                              \-> B -/
##
## Both pockets rejoin at the same next node, so the structure has genuinely
## converging edges rather than being a line with a decorative detour.
##
## One consequence is a design constraint rather than an accident:
## **every path through an act contains the same number of encounters.** Each
## backbone slot is either one encounter, or a fork whose pockets hold exactly
## one encounter between them, so a risky branch costs risk and not length, and
## a player who takes every quiet option cannot finish an act below GDD 3.2's
## "5-7 encounters before boss". GDD 8.2's weights decide which node *type*
## lands in a pocket; they never decide an act's length.
##
## ## Injected versus rolled
##
## GDD 8.2: "Boss, entrance and tutorial nodes are injected separately" and
## "First room of each act is fixed." So entrance, tutorial, the fixed opener,
## the forks, the guaranteed build reward, the guaranteed recovery and the boss
## are placed by construction; only the remaining node *types* are rolled from
## the weight table. Guarantees that can be outvoted by a dice roll are not
## guarantees, so the guarantees are structural - the act's length is planned
## around them rather than repaired after the fact.
##
## ## Layering
##
## Node-free and engine-free, like `src/sim/` (Docs/ARCHITECTURE.md, section 2).
## The one dependency is `RoomCatalog`, which is read-only data, mirroring
## `SimWorld`'s dependency on `SimLevel`: the world holds a level and asks it
## questions. `RoomCatalog` never refers back here, so there is no cycle.
class_name RunGraph
extends RefCounted


## Node types. STANDARD_COMBAT onward match RunTuning.ROLLABLE_KINDS' ordinals;
## ENTRANCE, TUTORIAL, CHOICE and BOSS are structural and are injected, never
## rolled (GDD 8.2).
enum Kind { ENTRANCE, TUTORIAL, STANDARD_COMBAT, ELITE, NARRATIVE, FORGE, HEALING, MERCHANT, CHOICE, BOSS }

## Risk bands a node or a branch option is advertised in. GDD 8.2 requires branch
## choices to "preview risk and reward", and a preview that can disagree with
## reality is worse than none, because the player decides on a promise. So risk
## here is *derived* from the assigned room and the node type, never declared and
## hoped for - see `risk_of`.
enum Risk { LOW, MODERATE, HIGH }


## One option at a fork.
class Choice extends RefCounted:
	var index := 0
	var label := ""
	## Preview only, and copied from the node this option actually leads to, so
	## the map the player read and the room they get are one fact stated twice.
	var risk: RunGraph.Risk = RunGraph.Risk.LOW
	var reward_preview := ""
	var next_id: StringName = &""


## One node in the route graph.
class RouteNode extends RefCounted:
	var id: StringName = &""
	var act := 0

	## Position among the act's encounter slots. -1 for injected structural
	## nodes, which have no position in the pacing.
	var ordinal := -1
	var kind: RunGraph.Kind = RunGraph.Kind.STANDARD_COMBAT

	## Authored room, or `&""` when the act has no catalogue content yet.
	var room_id: StringName = &""
	## The encounter socket this node was populated with, or `&""` (GDD 8.1:
	## "populates them from curated enemy budgets").
	var spawn_pattern_id: StringName = &""

	## Successors. More than one means the graph reaches two ways from here; a
	## node every path passes has exactly one.
	var next: Array[StringName] = []

	## Counts toward GDD 3.2's "Encounters before boss".
	var is_encounter := false

	## On every path from the act's entry to its boss. Computed once the act
	## exists rather than assumed, because the only reliable way to know whether
	## a room can be skipped is to try to reach the boss without it.
	var mandatory := false

	## Mandatory *and* hard. Driven by the authored difficulty budget, not only
	## by the node being an elite: "no two consecutive mandatory high-difficulty
	## nodes" (GDD 8.2) is a statement about what the player is asked to
	## survive, and two hand-authored budget-4 rooms in a row is exactly that.
	var high_difficulty := false
	var risk: RunGraph.Risk = RunGraph.Risk.LOW

	## The filter this node's room was chosen under. Kept on the node so a test
	## - and the catalogue itself - can prove the assignment honoured it rather
	## than trusting the generator that produced it.
	var required_region: StringName = &""
	var budget_band: Array = []
	## How far the room filter had to be relaxed. Zero everywhere in a correctly
	## sized catalogue; non-zero is a content signal, not a seed artefact.
	var room_widened := 0
	var room_missing := false

	## Fixed rooms are assigned by role, never rolled (GDD 8.2's fixed first
	## room, GDD 8.3's handcrafted boss arenas).
	var fixed_room := false

	## Set on a node inside a fork pocket - the part of the graph a player can
	## decline, which is what makes the fork a choice.
	var in_pocket := false

	## Placed by construction rather than rolled. GDD 8.2: "Boss, entrance and
	## tutorial nodes are injected separately", plus the fixed opener, the forks,
	## the guaranteed build reward and recovery, and the combat room that stands
	## in behind a rolled service or story stop. Marked rather than inferred,
	## because GDD 8.2's weight table is only checkable against the nodes that
	## were actually rolled.
	var injected := false

	## The GDD 8.2 ordinal the dice produced for this node, or -1 if none did.
	## `kind` can differ from it: a rolled shrine becomes a stop in front of a
	## combat room, and the room the player actually walks into is the stop.
	var rolled := -1

	var choices: Array[RunGraph.Choice] = []


## Everything one act generated.
class Act extends RefCounted:
	var index := 0
	## Creation order, which is also generation order and therefore stable for a
	## given seed. Nothing here ever depends on dictionary ordering.
	var nodes: Array[RunGraph.RouteNode] = []
	var entry_id: StringName = &""
	var boss_id: StringName = &""
	var forks: Array[StringName] = []

	## Encounters on every path through the act, and the value GDD 3.2 bounds.
	## Verified against the built graph rather than assumed from the draw.
	var path_encounter_count := 0
	var mandatory_encounter_count := 0

	## Times the room filter had to be relaxed. Should be zero everywhere.
	var room_widened := 0

	func node(id: StringName) -> RunGraph.RouteNode:
		for n in nodes:
			if n.id == id:
				return n
		return null


var acts: Array[Act] = []
var seed_value := 0

## Guarantees that failed to be met, in prose. A generator that repairs its own
## mistakes silently is a generator nobody can audit, so this is empty by
## construction and reported rather than fixed up if it is ever not.
var problems: Array[String] = []

var _by_id: Dictionary = {}
## Rooms used so far in each act, so the generator prefers one the player has not
## already been sent through. GDD 15.3 plans 25-35 templates reused through
## curated variations, so repetition is expected - only worth avoiding.
var _used_rooms: Array = []


# --- Seed plumbing (GDD 8.4) --------------------------------------------------

## 2^64's golden-ratio constant, signed. Written as a decimal because GDScript
## rejects a hex literal above int64 max - `0x9E3779B97F4A7C15` is a parse
## error, and a file that fails to parse *hangs* instead of exiting
## (Docs/ARCHITECTURE.md, "Running the checks"), which is a miserable way to
## discover it.
const GOLDEN_GAMMA := -7046029254386353131

## FNV-1a offset basis. A local hash rather than the engine's `String.hash()`
## because this value ends up in a bug report: it must not be free to change
## between engine versions and silently invalidate every recorded seed.
const FNV_OFFSET := 2166136261


## Stable hash of a string. Node ids are hashed to salt the per-node RNG
## streams, so one node's encounter does not depend on how many rolls happened
## before it.
static func hash_text(text: String) -> int:
	var h := FNV_OFFSET
	for i in text.length():
		h = ((h ^ text.unicode_at(i)) * 16777619) & 0x7FFFFFFFFFFFFFFF
	return h


## SplitMix-style avalanche over a seed and a salt. Wrapping arithmetic on int64
## is well defined in GDScript, and masking to 63 bits keeps the result
## non-negative, which an RNG seed wants.
static func mix_seed(base: int, salt: int) -> int:
	var h := (base ^ (salt * GOLDEN_GAMMA)) & 0x7FFFFFFFFFFFFFFF
	h = (h ^ (h >> 30)) * GOLDEN_GAMMA
	h = (h ^ (h >> 27)) * GOLDEN_GAMMA
	h = (h ^ (h >> 31)) & 0x7FFFFFFFFFFFFFFF
	return h


## A generator for one decision class of one run.
##
## The first salt is the stream class (RunTuning.STREAM_*) and the second
## identifies what is being decided - an act index, or a node id. Splitting them
## is deliberate; see RunTuning's note on the stream constants. Every generator
## in this lane comes from here, so there is exactly one place to audit for an
## unseeded RNG.
static func stream(base_seed: int, stream_class: int, scope: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix_seed(mix_seed(base_seed, stream_class), hash_text(str(scope)))
	return rng


## The only nondeterminism in the lane, and it lives deliberately outside
## generation. GDD 8.4 wants every run to have a reproducible seed, so the seed
## is something the caller owns: the game asks the system for one when the player
## starts a run, and a test passes a literal. Nothing below this line may call
## it. Time rather than the global RNG so that even this does not perturb any
## `randi()` elsewhere in the process.
static func system_seed() -> int:
	var t := int(Time.get_unix_time_from_system() * 1000000.0) ^ int(Time.get_ticks_usec())
	return mix_seed(t, 0x53454544)


# --- Classification -----------------------------------------------------------

## Does this node type count toward GDD 3.2's "Encounters before boss"? Only the
## two fight types do. A shrine, a merchant or a story beat is time in the run
## but not an encounter, and counting it would let a well-stocked act reach its
## boss having fought three times.
static func kind_is_encounter(kind: Kind) -> bool:
	return kind == Kind.STANDARD_COMBAT or kind == Kind.ELITE


## GDD 8.2: "Elite challenge - Higher stakes; valuable scroll reward" and
## "Forge / scroll shrine - Swap/upgrade abilities." Those are the two node types
## where a build changes, so they are what the per-act build-reward guarantee
## counts. A standard combat room's reward is currency, not a build.
static func kind_grants_build_reward(kind: Kind) -> bool:
	return kind == Kind.ELITE or kind == Kind.FORGE


## GDD 8.2: "Healing shrine - Resource relief with tradeoff."
static func kind_recovers(kind: Kind) -> bool:
	return kind == Kind.HEALING


## The reward a node or branch option advertises - GDD 8.2's own "Function"
## column, so the map a player reads says what the design document says.
static func reward_preview_for(kind: Kind) -> String:
	match kind:
		Kind.ELITE: return "valuable scroll reward"
		Kind.FORGE: return "swap or upgrade a scroll"
		Kind.HEALING: return "recover health and flask charges"
		Kind.MERCHANT: return "buy tools with temporary coin"
		Kind.NARRATIVE: return "lore, and a small boon"
		Kind.STANDARD_COMBAT: return "coin and a room clear"
		Kind.BOSS: return "clan seal and moon ink"
		_: return "travel"


## Risk derived from the data, never declared. An elite is high by definition. A
## standard combat room is high once its authored budget reaches
## RunTuning.HIGH_DIFFICULTY_BUDGET, which is what lets a hand-authored budget-4
## room count toward GDD 8.2's rule. Everything else is a room the player can
## walk through without being tested.
static func risk_of(node: RunGraph.RouteNode) -> Risk:
	match node.kind:
		Kind.ELITE:
			return Risk.HIGH
		Kind.STANDARD_COMBAT:
			var budget := RoomCatalog.budget_of(node.room_id)
			if budget >= RunTuning.HIGH_DIFFICULTY_BUDGET:
				return Risk.HIGH
			if budget <= 2:
				return Risk.LOW
			return Risk.MODERATE
		Kind.BOSS:
			return Risk.HIGH
		_:
			return Risk.LOW


## Kind for an ordinal. GDScript enums are not callable as constructors, and
## the weight table is deliberately keyed by ordinal rather than by name (see
## RunTuning.NODE_WEIGHT_PERCENT), so somewhere the two have to meet. This is
## that place, and it is total rather than best-effort so a bad ordinal shows up
## as a named node type instead of a silently wrong run.
static func kind_from_ordinal(ordinal: int) -> Kind:
	var k: Kind = Kind.ENTRANCE
	match ordinal:
		0: k = Kind.ENTRANCE
		1: k = Kind.TUTORIAL
		2: k = Kind.STANDARD_COMBAT
		3: k = Kind.ELITE
		4: k = Kind.NARRATIVE
		5: k = Kind.FORGE
		6: k = Kind.HEALING
		7: k = Kind.MERCHANT
		8: k = Kind.CHOICE
		9: k = Kind.BOSS
		_: k = Kind.ENTRANCE
	return k


static func kind_name(kind: Kind) -> String:
	match kind:
		Kind.ENTRANCE: return "entrance"
		Kind.TUTORIAL: return "tutorial"
		Kind.STANDARD_COMBAT: return "combat"
		Kind.ELITE: return "elite"
		Kind.NARRATIVE: return "event"
		Kind.FORGE: return "forge"
		Kind.HEALING: return "healing"
		Kind.MERCHANT: return "merchant"
		Kind.CHOICE: return "fork"
		Kind.BOSS: return "boss"
		_: return "unknown"


static func risk_name(risk: Risk) -> String:
	match risk:
		Risk.LOW: return "low"
		Risk.MODERATE: return "moderate"
		_: return "high"


# --- Generation ---------------------------------------------------------------

## Generate a whole run from a seed. The single entry point: nothing else in this
## lane mutates a graph.
static func generate(p_seed: int) -> RunGraph:
	var g := RunGraph.new()
	g.seed_value = p_seed
	g._used_rooms.resize(RunTuning.ACT_COUNT)
	var no_rooms: Array[StringName] = []
	for act_index in RunTuning.ACT_COUNT:
		g._used_rooms[act_index] = no_rooms.duplicate()
	for act_index in RunTuning.ACT_COUNT:
		g._build_act(act_index)
	g._resolve_mandatory()
	g._verify()
	return g


func node(id: StringName) -> RunGraph.RouteNode:
	return _by_id.get(id, null)


func act(index: int) -> Act:
	if index < 0 or index >= acts.size():
		return null
	return acts[index]


func _new_node(act_index: int, kind: Kind, ordinal: int, in_pocket := false, injected := false) -> RunGraph.RouteNode:
	var a := acts[act_index]
	var n := RunGraph.RouteNode.new()
	n.act = act_index
	n.kind = kind
	n.ordinal = ordinal
	n.in_pocket = in_pocket
	n.injected = injected
	n.id = StringName("a%d_n%d" % [act_index, a.nodes.size()])
	n.is_encounter = kind_is_encounter(kind)
	a.nodes.append(n)
	_by_id[n.id] = n
	return n


func _link(from_id: StringName, to_id: StringName) -> void:
	# An empty id means "there is nothing on this side of the join". After a fork
	# there genuinely is: the fork's successors are its pockets, and the join
	# happens at the far end of a pocket rather than at the fork.
	if from_id.is_empty() or to_id.is_empty():
		return
	var from: RunGraph.RouteNode = _by_id.get(from_id, null)
	if from != null:
		from.next.append(to_id)


func _note_room_used(n: RunGraph.RouteNode) -> void:
	if not n.room_id.is_empty():
		(_used_rooms[n.act] as Array).append(n.room_id)


## Assign an authored room under the node's filter, from a stream keyed on the
## node rather than on the roll order, so adding a room to the catalogue cannot
## shift the shape of the route.
func _assign_room(n: RunGraph.RouteNode, band: Array) -> void:
	n.budget_band = band
	if not RoomCatalog.assigns_rooms_for(n.act):
		n.room_missing = true
		return
	var rng := stream(seed_value, RunTuning.STREAM_ROOM, int(hash_text(String(n.id))))
	var result := RoomCatalog.pick(rng, n.required_region, band, [int(n.kind)], _used_rooms[n.act])
	var room_id: StringName = result["room"]
	n.room_id = room_id
	n.room_widened = int(result["widened"])
	if n.room_id.is_empty():
		n.room_missing = true
	else:
		_note_room_used(n)


## Populate an encounter socket (GDD 8.1: "populates them from curated enemy
## budgets"). GDD 8.3 forbids randomising a boss arena, so a handcrafted room
## takes its authored pattern and no roll happens at all - the arena's fight is
## somebody's authored work, not a sample from a list.
func _assign_spawn(n: RunGraph.RouteNode) -> void:
	if n.room_id.is_empty() or not n.is_encounter:
		return
	var room := RoomCatalog.get_room(n.room_id)
	if room != null and room.handcrafted:
		n.spawn_pattern_id = RoomCatalog.authored_spawn(n.room_id)
		return
	var rng := stream(seed_value, RunTuning.STREAM_ENCOUNTER, int(hash_text(String(n.id))))
	var avoid: Array[StringName] = []
	for other in acts[n.act].nodes:
		if other == n or other.spawn_pattern_id.is_empty():
			continue
		if other.room_id == n.room_id:
			avoid.append(other.spawn_pattern_id)
	n.spawn_pattern_id = RoomCatalog.pick_spawn(rng, n.room_id, avoid)


# --- One act ------------------------------------------------------------------

func _build_act(act_index: int) -> void:
	var rng := stream(seed_value, RunTuning.STREAM_STRUCTURE, act_index)
	var a := Act.new()
	a.index = act_index
	acts.append(a)

	var lo: int = RunTuning.ACT_ENCOUNTER_MIN[act_index]
	var hi: int = RunTuning.ACT_ENCOUNTER_MAX[act_index]
	## Encounters on *every* path through the act. GDD 3.2's band.
	var encounter_target := rng.randi_range(lo, hi)
	a.path_encounter_count = encounter_target

	# --- Plan the act before building it ------------------------------------
	#
	# GDD 8.2's guarantees are structural, not repairs. Planning first means the
	# guaranteed build reward and the guaranteed recovery occupy slots of their
	# own, the encounter budget is exact, and nothing has to be converted after
	# the fact - which matters, because converting a combat room into a shrine
	# would quietly hand the act an encounter short of its floor.
	var tail_encounters := encounter_target - 1  # the fixed opener is one of them
	var branch_slots := _branch_slots(rng, tail_encounters)

	# Step plan. An entry is {"branch": ordinal}, {"service": Kind} for a
	# guaranteed non-encounter node, or {"encounter": ordinal} for a rolled slot.
	var steps: Array = []
	for i in tail_encounters:
		if branch_slots.has(i):
			steps.append({"branch": i})
		else:
			steps.append({"encounter": i})

	# GDD 8.2: "each act guarantees at least one build reward and one recovery
	# opportunity before its boss", and GDD 3.3's cadence ends "recovery -> boss".
	# Both are unconditional and occupy slots of their own; a second shrine is
	# then left to the weight roll, which is what makes finding one a gift
	# rather than a rule.
	if RunTuning.BUILD_REWARD_AND_RECOVERY_ARE_GUARANTEED:
		var forge_at := maxi(1, steps.size() - 2)
		steps.insert(forge_at, {"service": Kind.FORGE})
		steps.append({"service": Kind.HEALING})

	# --- Injected: entrance (GDD 8.2) ---------------------------------------
	var entry := _new_node(act_index, Kind.ENTRANCE, -1, false, true)
	a.entry_id = entry.id
	var cursor: StringName = entry.id

	# --- Injected: tutorial (GDD 8.2, GDD 14) --------------------------------
	if RunTuning.TUTORIAL_ACTS[act_index]:
		var tutorial := _new_node(act_index, Kind.TUTORIAL, -1, false, true)
		_link(cursor, tutorial.id)
		cursor = tutorial.id

	# --- Slot 0: the fixed opener (GDD 8.2: "First room of each act is fixed")
	var opener := _new_node(act_index, Kind.STANDARD_COMBAT, 0, false, true)
	_finalise_fixed(opener, RoomCatalog.fixed_opener_for(act_index))
	_assign_spawn(opener)
	_link(cursor, opener.id)
	cursor = opener.id
	var prev_high := _mark_high(opener)

	# --- The planned backbone -----------------------------------------------
	#
	# `pending_merge` holds the tails of the previous step's pockets. They rejoin
	# here, which is what makes the shape a graph with converging edges rather
	# than a line: both branches of a fork arrive at the same next node.
	var pending_merge: Array[StringName] = []
	for step in steps:
		if step.has("branch"):
			var ordinal: int = step["branch"]
			var fork := _new_node(act_index, Kind.CHOICE, ordinal, false, true)
			_link(cursor, fork.id)
			for tail in pending_merge:
				_link(tail, fork.id)
			pending_merge = _build_fork(fork, ordinal, tail_encounters, rng)
			a.forks.append(fork.id)
			# Deliberately no successor for the fork itself. Attaching the next
			# backbone node to the fork would add a third edge that steps over
			# both pockets, and the player could walk past the very choice they
			# were offered. The join is between the pocket tails and the next
			# node, which is what makes the shape a graph with converging edges
			# instead of a line with a detour.
			cursor = &""
			# A fork is a doorway between two mandatory nodes, so the
			# back-to-back rule cannot straddle it. A pocket head is *not*
			# mandatory - the other pocket is right there - so resetting here is
			# what the rule means rather than a loophole in it.
			prev_high = false
			continue

		var pair: Array
		if step.has("service"):
			var kind: Kind = step["service"]
			pair = _service_node(act_index, kind, tail_encounters, rng)
		else:
			var enc_ordinal: int = step["encounter"]
			pair = _encounter_node(act_index, enc_ordinal, tail_encounters, prev_high, rng)
		var head_id: StringName = pair[0]
		var tail_id: StringName = pair[1]
		_link(cursor, head_id)
		for tail in pending_merge:
			_link(tail, head_id)
		var joined: Array[StringName] = []
		pending_merge = joined
		# The chain continues from the *tail*. A stop-then-fight step has two
		# nodes and only the second of them leads onwards; attaching the next
		# node to the first as well would give a shrine two exits and quietly
		# turn every stop into a fork the player never chose.
		cursor = tail_id
		prev_high = _mark_high(_by_id[tail_id])

	# --- Injected: boss (GDD 8.2, GDD 8.3) ----------------------------------
	var boss := _new_node(act_index, Kind.BOSS, tail_encounters, false, true)
	_finalise_fixed(boss, RoomCatalog.boss_room_for(act_index))
	_link(cursor, boss.id)
	for tail in pending_merge:
		_link(tail, boss.id)
	a.boss_id = boss.id
	_mark_high(boss)

	for n2 in a.nodes:
		a.room_widened += n2.room_widened


## A room assigned by structural role rather than through the filter: GDD 8.2's
## fixed first room, and GDD 8.3's handcrafted boss arena. An act with no
## authored catalogue yet simply has none and says so, rather than inventing one.
func _finalise_fixed(n: RunGraph.RouteNode, room_id: StringName) -> void:
	n.fixed_room = true
	var room := RoomCatalog.get_room(room_id)
	if room == null:
		n.room_missing = true
		return
	n.room_id = room_id
	n.required_region = room.region
	n.budget_band = [room.difficulty_budget, room.difficulty_budget]
	if n.kind == Kind.BOSS:
		# A boss is not one of GDD 3.2's "encounters before boss"; it is what
		# comes after them, and counting it would let an act reach it early.
		n.is_encounter = false
		# GDD 8.3: the arena's fight is authored, so it is recorded from the room
		# rather than rolled. A boss node with no pattern here would be a boss
		# arena the generator had decided it was allowed to rearrange.
		n.spawn_pattern_id = RoomCatalog.authored_spawn(room_id)
	_note_room_used(n)


## A guaranteed non-encounter step: the forge and the healing shrine. Head and
## tail are the same node, because a stop that is not in front of a fight is
## exactly what "recovery before a boss" means.
func _service_node(act_index: int, kind: Kind, total: int, rng: RandomNumberGenerator) -> Array:
	var n := _new_node(act_index, kind, total, false, true)
	n.required_region = RunTuning.roll_region(rng, act_index)
	_assign_room(n, RunTuning.band_for(total, total, int(kind)).duplicate())
	_mark_high(n)
	return [n.id, n.id]


## One rolled encounter slot. Returns `[head, tail]`.
##
## GDD 8.2's weight table puts non-fight node types in the mix - a shrine, a
## merchant, a story beat - and those still occupy a slot in the act's pacing.
## So a slot is **one encounter, optionally behind a non-encounter stop**: if the
## roll produces a service or story node it becomes the stop and an ordinary
## combat room follows it; if the roll produces a fight the slot is just that
## fight. Either way the slot spends exactly one encounter, which is what keeps
## GDD 3.2's band true on every path rather than on average. It also keeps the
## weights honest - a 10% story beat becomes "a story beat, then a fight", not
## "a story beat instead of a fight".
##
## `prev_high` carries GDD 8.2's "no two consecutive mandatory high-difficulty
## nodes" forward, and it is enforced in two ways because the rule can be broken
## two ways. An ELITE is high whatever room it lands in, so when the previous
## mandatory node was already high the roll is drawn from the weight table with
## the elite weight removed - renormalised, not re-rolled, so the relative
## distribution of the remaining types is exactly GDD 8.2's. A standard combat
## room can become high purely by being a hand-authored budget-4 room, and the
## dice do not get to override that, so its budget band is capped instead.
func _encounter_node(
	act_index: int,
	ordinal: int,
	total: int,
	prev_high: bool,
	rng: RandomNumberGenerator
) -> Array:
	var rolled: Kind = RunTuning.roll_kind(rng, prev_high)
	var region := RunTuning.roll_region(rng, act_index)

	var fight: Kind = rolled
	var stop: Kind = NO_STOP
	if not kind_is_encounter(rolled):
		fight = Kind.STANDARD_COMBAT
		stop = rolled

	# The budget cap applies to the slot's *fight*, wherever it sits - behind a
	# stop or standing alone. Capping only the stop-then-fight case was a real
	# bug once and would be again: the constraint is about what the player has
	# to survive, not about which shape the slot took.
	var fight_band := RunTuning.band_for(ordinal, total, int(fight)).duplicate()
	if prev_high:
		fight_band[1] = mini(int(fight_band[1]), RunTuning.HIGH_DIFFICULTY_BUDGET - 1)
		if int(fight_band[1]) < int(fight_band[0]):
			fight_band[0] = RunTuning.HIGH_DIFFICULTY_BUDGET - 1

	var tail_node: RunGraph.RouteNode = null
	var head_node: RunGraph.RouteNode = null
	if stop == NO_STOP:
		head_node = _new_node(act_index, fight, ordinal)
		head_node.rolled = int(rolled)
		head_node.required_region = region
		_assign_room(head_node, fight_band)
		tail_node = head_node
	else:
		head_node = _new_node(act_index, stop, ordinal)
		head_node.rolled = int(rolled)
		head_node.required_region = region
		_assign_room(head_node, RunTuning.band_for(ordinal, total, int(stop)).duplicate())
		tail_node = _new_node(act_index, fight, ordinal, false, true)
		tail_node.required_region = region
		_assign_room(tail_node, fight_band)
		_link(head_node.id, tail_node.id)
	_mark_high(head_node)
	_assign_spawn(head_node)
	_mark_high(tail_node)
	_assign_spawn(tail_node)

	return [head_node.id, tail_node.id]


## Which of the act's tail encounter slots become forks.
##
## Excludes the opener (a fixed room, and the fight that teaches) and leaves room
## for the forge and the recovery tail. GDD 3.3 wants the fork *after* the first
## standard fight, so slot 0 of the tail - the room straight after the opener -
## is eligible too; the roll simply will not always take it.
func _branch_slots(rng: RandomNumberGenerator, tail_encounters: int) -> Array[int]:
	var pool: Array[int] = []
	for i in tail_encounters:
		pool.append(i)
	if pool.is_empty():
		var none: Array[int] = []
		return none
	var want := rng.randi_range(
		RunTuning.MIN_BRANCHES_PER_ACT,
		mini(RunTuning.MAX_BRANCHES_PER_ACT, pool.size())
	)
	# Fisher-Yates on a local array. `Array.shuffle()` would be shorter and
	# wrong: it uses the *global* RNG, which would make the route depend on
	# whatever else in the process ran first (GDD 8.4).
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out: Array[int] = []
	for i in want:
		out.append(pool[i])
	out.sort()
	return out


## GDD 3.3's fork, in GDD 19's words: "A lantern sign points left to an elite
## trial and right to a merchant. Player takes the elite."
##
## Each profile pairs a harder set of *fights* with a calmer one. Two rules keep
## a pocket honest:
##
##   1. **A pocket always contains exactly one encounter.** Its fight is drawn
##      from the encounter kinds only. A pocket of pure services would make the
##      encounter count on that path lower than on the other, and GDD 3.2's band
##      has to hold on every path rather than on the average one. So the merchant
##      in GDD 19 is a *stop on* the calm branch rather than the whole branch -
##      which is also why the calm option stays worth taking.
##   2. **The advertised risk and reward are read off the node the option actually
##      leads to**, not from the profile, so a preview cannot disagree with the
##      room the player walks into.
##
## Row layout: [fight kinds, stop kinds] for option 0, then the same for option
## 1. An empty stop list means that option goes straight to its fight, which is
## what makes "left to an elite trial" read the way GDD 19 wrote it.
const FORK_PROFILES := [
	[[3], [], [2], [5, 6, 7, 4]],
	[[3, 2], [6], [2], [5, 7]],
	[[2], [5, 6, 7, 4], [2], []],
]

## Fork option labels, by node kind ordinal. GDD 8.2's names for the node types.
const FORK_LABELS := {
	3: "elite trial",
	2: "combat room",
	4: "story beat",
	5: "scroll forge",
	6: "healing shrine",
	7: "merchant stall",
}

## Sentinel for "this option has no stop". ENTRANCE is injected structurally and
## is never a pocket node, so it cannot collide with a real kind.
const NO_STOP := Kind.ENTRANCE


func _build_fork(fork: RunGraph.RouteNode, ordinal: int, total: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var profile: Array = FORK_PROFILES[rng.randi_range(0, FORK_PROFILES.size() - 1)]
	var tails: Array[StringName] = []

	for i in RunTuning.BRANCH_OPTIONS:
		var fight_kinds: Array = profile[i * 2]
		var stop_kinds: Array = profile[i * 2 + 1]
		var fight: Kind = int(fight_kinds[rng.randi_range(0, fight_kinds.size() - 1)])

		# An optional non-encounter stop in front of the fight. GDD 3.3 asks for
		# "short traversal beats and environmental reveals" so a route does not
		# read as an arena playlist. It can never be a second encounter: this
		# pocket spends exactly one, and the act's per-path encounter count
		# depends on that being true.
		var stop: Kind = NO_STOP
		if not stop_kinds.is_empty() and rng.randf() < RunTuning.POCKET_SERVICE_CHANCE:
			stop = int(stop_kinds[rng.randi_range(0, stop_kinds.size() - 1)])

		var first: Kind = fight if stop == NO_STOP else stop
		var first_node := _new_node(fork.act, first, ordinal, true)
		first_node.required_region = RunTuning.roll_region(rng, fork.act)
		_assign_room(first_node, RunTuning.band_for(ordinal, total, int(first)).duplicate())
		_mark_high(first_node)
		_assign_spawn(first_node)

		var tail := first_node
		if first != fight:
			# The pocket's fight sits behind the stop. The preview still names
			# what the player enters first, because that is the door they are
			# being offered. The fight itself is injected: it is the slot's one
			# encounter, not something the dice chose.
			var body := _new_node(fork.act, fight, ordinal, true, true)
			body.required_region = first_node.required_region
			_assign_room(body, RunTuning.band_for(ordinal, total, int(fight)).duplicate())
			_mark_high(body)
			_link(first_node.id, body.id)
			_assign_spawn(body)
			tail = body

		var choice := Choice.new()
		choice.index = i
		choice.next_id = first_node.id
		choice.label = String(FORK_LABELS.get(int(first), "path"))
		choice.risk = first_node.risk
		choice.reward_preview = reward_preview_for(first)
		fork.choices.append(choice)
		# The fork's own successors are the pocket heads. The pocket *tails* are
		# what rejoin the backbone, and that link is made by the caller once the
		# next backbone node exists.
		_link(fork.id, first_node.id)
		tails.append(tail.id)

	return tails


## Compute `risk` and `high_difficulty`. `mandatory` is filled in later by
## `_resolve_mandatory`, once the whole act exists; risk is a property of the data
## and is known immediately.
func _mark_high(n: RunGraph.RouteNode) -> bool:
	n.risk = risk_of(n)
	n.high_difficulty = n.risk == Risk.HIGH
	return n.high_difficulty


# --- Mandatory-node resolution ------------------------------------------------

## After the act exists, work out which nodes are unavoidable: remove each in
## turn and see whether the boss is still reachable. This is the honest answer,
## and the only one that stays correct when a pocket grows a node.
func _resolve_mandatory() -> void:
	for a in acts:
		var boss: RunGraph.RouteNode = _by_id.get(a.boss_id, null)
		if boss == null:
			continue
		for n in a.nodes:
			if n.id == a.entry_id or n.id == a.boss_id:
				n.mandatory = true
				continue
			n.mandatory = not _reachable_without(a, n.id)
		var mandatory_encounters := 0
		for n in a.nodes:
			if n.mandatory and n.is_encounter:
				mandatory_encounters += 1
		a.mandatory_encounter_count = mandatory_encounters


func _reachable_without(a: Act, blocked: StringName) -> bool:
	var seen: Dictionary = {}
	var stack: Array[StringName] = [a.entry_id]
	while not stack.is_empty():
		var id: StringName = stack.pop_back()
		if id == blocked or seen.has(id):
			continue
		seen[id] = true
		if id == a.boss_id:
			return true
		var n: RunGraph.RouteNode = _by_id.get(id, null)
		if n == null:
			continue
		for next_id in n.next:
			stack.append(next_id)
	return false


# --- Verification -------------------------------------------------------------

## Check every guarantee GDD 8.2 makes about the built act and report rather than
## repair. A generator that silently fixes its own mistakes is a generator nobody
## can audit, and the whole point of this layer is that a run is a thing you can
## check.
func _verify() -> void:
	for a in acts:
		if _by_id.get(a.boss_id, null) == null:
			problems.append("act %d: no boss node" % a.index)

		var bosses := 0
		var builds := 0
		var recoveries := 0
		for n in a.nodes:
			if n.kind == Kind.BOSS:
				bosses += 1
			if n.id == a.boss_id:
				continue
			if kind_grants_build_reward(n.kind):
				builds += 1
			if kind_recovers(n.kind):
				recoveries += 1
		if bosses != 1:
			problems.append("act %d: %d boss nodes, expected exactly 1" % [a.index, bosses])
		if builds < 1:
			problems.append("act %d: no build reward before the boss (GDD 8.2)" % a.index)
		if recoveries < 1:
			problems.append("act %d: no recovery opportunity before the boss (GDD 8.2)" % a.index)
		if a.forks.is_empty():
			problems.append("act %d: no branch choice (GDD 8.2)" % a.index)

		var listing := paths_in_act(a.index, 256)
		if listing["truncated"]:
			problems.append("act %d: more than 256 distinct paths" % a.index)
		var counts: Array = []
		for path in listing["paths"]:
			counts.append(encounters_on(path))
		for c in counts:
			if c < int(RunTuning.ACT_ENCOUNTER_MIN[a.index]) or c > int(RunTuning.ACT_ENCOUNTER_MAX[a.index]):
				problems.append("act %d: a path has %d encounters, outside GDD 3.2's %d-%d"
					% [a.index, c, RunTuning.ACT_ENCOUNTER_MIN[a.index], RunTuning.ACT_ENCOUNTER_MAX[a.index]])
			if c != a.path_encounter_count:
				problems.append("act %d: path has %d encounters but the act claims %d"
					% [a.index, c, a.path_encounter_count])

	problems.append_array(high_difficulty_violations())
	if RunTuning.AVOID_BACK_TO_BACK_ELITES:
		problems.append_array(back_to_back_elites())
	problems.append_array(_preview_mismatches())


## A fork option's advertised risk and reward must match the node it leads to.
## This is the assertion behind "branch choices must preview risk and reward"
## (GDD 8.2): a preview that can disagree with the room is not a preview.
func _preview_mismatches() -> Array[String]:
	var out: Array[String] = []
	for a in acts:
		for n in a.nodes:
			for c in n.choices:
				var target: RunGraph.RouteNode = _by_id.get(c.next_id, null)
				if target == null:
					out.append("%s option %d leads nowhere" % [n.id, c.index])
					continue
				if c.risk != target.risk:
					out.append("%s option %d advertises %s but leads to a %s node"
						% [n.id, c.index, risk_name(c.risk), risk_name(target.risk)])
				if c.reward_preview != reward_preview_for(target.kind):
					out.append("%s option %d advertises '%s' but leads to a %s node"
						% [n.id, c.index, c.reward_preview, kind_name(target.kind)])
	return out


## GDD 8.2: "no two consecutive mandatory high-difficulty nodes", checked over
## every edge of the graph rather than over a linear sequence, so a fork cannot
## hide a violation behind its own ordering.
func high_difficulty_violations() -> Array[String]:
	var out: Array[String] = []
	for a in acts:
		for n in a.nodes:
			if not n.mandatory or not n.high_difficulty:
				continue
			for next_id in n.next:
				var m: RunGraph.RouteNode = _by_id.get(next_id, null)
				if m == null:
					continue
				if m.mandatory and m.high_difficulty:
					out.append("act %d: %s (%s) -> %s (%s) are consecutive mandatory high-difficulty nodes"
						% [a.index, n.id, kind_name(n.kind), m.id, kind_name(m.kind)])
	return out


## GDD 3.3: "Avoid two forced elites consecutively."
##
## Stricter in letter than the rule above but weaker in reach, and it is checked
## separately rather than folded in, because the two say different things. This
## one only sees elite *labels*; the rule above also catches two budget-4 rooms
## that happen to be standard combats. Keeping both means a regression in either
## has its own message, and the pair of them is what GDD 3.3 and GDD 8.2 asked
## for between them.
func back_to_back_elites() -> Array[String]:
	var out: Array[String] = []
	for a in acts:
		for n in a.nodes:
			if not n.mandatory or n.kind != Kind.ELITE:
				continue
			for next_id in n.next:
				var m: RunGraph.RouteNode = _by_id.get(next_id, null)
				if m != null and m.mandatory and m.kind == Kind.ELITE:
					out.append("act %d: %s -> %s are consecutive forced elites (GDD 3.3)"
						% [a.index, n.id, m.id])
	return out


# --- Path inspection (for tests and for the map screen) -----------------------

## Enumerate simple paths from an act's entry to its boss, each as a list of node
## ids. Capped, because a future act with many forks could make this factorial;
## `truncated` says when the cap bit, so a caller can never mistake a capped
## answer for a complete one.
func paths_in_act(act_index: int, limit := 64) -> Dictionary:
	var a := act(act_index)
	if a == null:
		var empty: Array = []
		return {"paths": empty, "truncated": false}
	var out: Array = []
	var truncated := false
	var start_acc: Array = []
	var stack: Array = [{"id": a.entry_id, "acc": start_acc}]
	while not stack.is_empty():
		if out.size() >= limit:
			truncated = true
			break
		var frame: Dictionary = stack.pop_back()
		var acc: Array = (frame["acc"] as Array).duplicate()
		var id: StringName = frame["id"]
		acc.append(id)
		if id == a.boss_id:
			out.append(acc)
			continue
		var n: RunGraph.RouteNode = _by_id.get(id, null)
		if n == null:
			continue
		# Pushed in reverse so the pop order, and therefore the order of `out`,
		# is a function of the graph rather than of stack mechanics.
		for i in range(n.next.size() - 1, -1, -1):
			var next_id: StringName = n.next[i]
			if acc.has(next_id):
				continue
			stack.append({"id": next_id, "acc": acc})
	return {"paths": out, "truncated": truncated}


## Encounters on one path, as GDD 3.2 counts them.
func encounters_on(path: Array) -> int:
	var count := 0
	for id in path:
		var n: RunGraph.RouteNode = _by_id.get(id, null)
		if n != null and n.is_encounter:
			count += 1
	return count


# --- Reporting ----------------------------------------------------------------

## A stable, printable identity for the run. GDD 8.4 wants the seed recorded with
## the build and room-clear logs; this is the other half - the route itself, in a
## form a tester can paste beside a crash. Creation order is deterministic for a
## given seed, so two runs of one seed produce byte-identical fingerprints, and
## two seeds that agree here really are the same route rather than a coincidence.
func fingerprint() -> String:
	var parts := PackedStringArray()
	parts.append("seed=%d" % seed_value)
	for a in acts:
		parts.append("act%d entry=%s boss=%s encounters=%d"
			% [a.index, a.entry_id, a.boss_id, a.path_encounter_count])
		for n in a.nodes:
			parts.append("  %s %s room=%s spawn=%s risk=%s mandatory=%s region=%s band=%s"
				% [n.id, kind_name(n.kind), n.room_id, n.spawn_pattern_id,
					risk_name(n.risk), str(n.mandatory), n.required_region, str(n.budget_band)])
			for c in n.choices:
				parts.append("    option %d %s risk=%s reward=%s next=%s"
					% [c.index, c.label, risk_name(c.risk), c.reward_preview, c.next_id])
	return "\n".join(parts)


## The graph as plain data, for a bug report or a save. Ids and ordinals are what
## a designer reads; the prefab behind each room id is a content question.
func to_dictionary() -> Dictionary:
	var acts_out: Array = []
	for a in acts:
		var nodes_out: Array = []
		for n in a.nodes:
			var choices_out: Array = []
			for c in n.choices:
				choices_out.append({
					"index": c.index,
					"label": c.label,
					"risk": risk_name(c.risk),
					"reward": c.reward_preview,
					"next": String(c.next_id),
				})
			nodes_out.append({
				"id": String(n.id),
				"kind": kind_name(n.kind),
				"ordinal": n.ordinal,
				"room": String(n.room_id),
				"spawn": String(n.spawn_pattern_id),
				"risk": risk_name(n.risk),
				"mandatory": n.mandatory,
				"high_difficulty": n.high_difficulty,
				"region": String(n.required_region),
				"room_missing": n.room_missing,
				"next": n.next.map(func(v: StringName) -> String: return String(v)),
				"choices": choices_out,
			})
		acts_out.append({
			"index": a.index,
			"entry": String(a.entry_id),
			"boss": String(a.boss_id),
			"forks": a.forks.map(func(v: StringName) -> String: return String(v)),
			"path_encounters": a.path_encounter_count,
			"mandatory_encounters": a.mandatory_encounter_count,
			"nodes": nodes_out,
		})
	return {"seed": seed_value, "acts": acts_out, "problems": problems}
