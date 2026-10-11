## One authored combat move.
##
## This is the GDD 13.3 "ActionData" record: a source-agnostic move definition
## carrying startup / active / recovery, cancel windows, stamina, reach and
## movement. It is a Resource so moves are authored and rebalanced in the
## Inspector rather than in code, which is how GDD 16's "one shared balancing
## sheet" becomes a thing that actually exists.
##
## Every window is an integer count of 60 Hz simulation ticks. Because the
## simulation is fixed-step, `tick >= active_from and tick < active_to` is an
## exact comparison with no floating-point drift.
##
## Hitboxes are authored as a coarse sweep through the blade's local-space
## poses rather than baked from an animation clip. See Docs/ARCHITECTURE.md for
## why: it keeps the simulation independent of animation playback, and it lets
## a designer make a weapon reach deliberately further than it looks, which is
## a normal action-game tool.
@tool
class_name AttackTable
extends Resource

## Where a number came from. GDD 13.2 requires the production prototype to be
## independently runnable with rights-cleared original content, and GDD 17
## lists "documented provenance" as the mitigation for asset/legal dependency.
## Anything marked ESTIMATE is a value we chose, not one we measured, and it is
## expected to move during playtesting.
enum Provenance { ORIGINAL, ESTIMATE }

## What kind of move this is.
##
## The state machine dispatches on this rather than on the move's id string. A
## dictionary keyed by move name works right up until someone renames a move,
## and then it fails at runtime instead of at load time, which in a simulation
## that must be verifiable headless is the worst possible failure mode.
enum Family {
	LIGHT,      ## part of a chain
	HEAVY,      ## committed single swing
	CHARGE,     ## the held wind-up that resolves into heavy or charged heavy
	DODGE,      ## the escape itself
	REACTION,   ## being hit; indexed by hurt_level
	UTILITY,    ## landings, guard breaks, anything with no offence of its own
}


## Stable identifier, used by tests and telemetry (GDD 18 links every result to
## a move).
@export var id: StringName = &""

@export var family: Family = Family.LIGHT

@export var provenance: Provenance = Provenance.ORIGINAL

## Free text for the balancing sheet. Explain why a value is what it is.
@export_multiline var note: String = ""


# --- Timing (GDD 5.1: anticipation, active contact, recovery) ------------------

## Ticks the action runs for in total, including recovery.
@export_range(1, 600, 1, "or_greater") var total_ticks: int = 40

## Start of the active contact window. Everything before this is anticipation,
## and the player must be able to read it (GDD 5.4).
@export_range(0, 600, 1) var active_from: int = 12

## End of the active contact window, exclusive.
@export_range(0, 600, 1) var active_to: int = 16

## Earliest tick at which a queued input may cancel this action. GDD 5.2: "permit
## one queued attack near the end of recovery but never a dozen prebuffered
## inputs". Keeping this close to active_to is what makes a chain feel
## responsive rather than laggy; keeping it far from it is what gives a heavy
## attack its commitment.
@export_range(0, 600, 1) var cancel_from: int = 18

## Earliest tick at which the action starts listening for the next input at all.
## Presses before this are dropped rather than queued (GDD 5.2, buffers).
@export_range(0, 600, 1) var input_from: int = 6


# --- Cost and effect ----------------------------------------------------------

## GDD 5.2 gives light attacks a range rather than a single value, because chain
## position changes the price. Charged attacks cost more.
@export_range(0, 200, 1) var stamina_cost: int = 14

@export_range(0, 500, 1) var damage: int = 20

## Posture is a separate axis from health (GDD 5.3). Fills the target's posture
## meter; a full meter opens a finisher.
@export_range(0, 500, 1) var posture_damage: int = 14

## Ticks both attacker and target freeze on contact. GDD 5.1: "weapon hit-stop
## and short pose exaggeration make successful contact legible".
@export_range(0, 60, 1) var hit_stop_ticks: int = 4

## Extra posture damage when the defender is guarding rather than dodging.
@export_range(0, 500, 1) var guard_damage: int = 22

## A timed guard inside Tuning.TIMED_GUARD_WINDOW_TICKS before contact converts
## this into posture damage instead of health damage (GDD 5.3).
@export_range(0, 500, 1) var timed_guard_posture: int = 18


# --- Defence ------------------------------------------------------------------

## Invulnerability window, [iframes_from, iframes_to). -1 means the move grants
## no invulnerability; a dodge fills these (GDD 5.2).
@export_range(-1, 600, 1) var iframes_from: int = -1
@export_range(-1, 600, 1) var iframes_to: int = -1

## A low sweep passes underneath a character that is airborne. This is the
## mechanic that makes jumping a real answer rather than a universal one
## (GDD 5.4: each major attack has at least one consistent answer).
@export var is_low_sweep: bool = false

## For Family.REACTION moves, how hard this reaction is. GDD 5.3 names four:
## a small flinch, a medium stagger, a heavy stagger and a knockdown.
@export var hurt_level: Tuning.HurtLevel = Tuning.HurtLevel.NONE

## For Family.REACTION moves, i-frames granted by getting up from a knockdown.
## A character on the floor must be able to recover rather than being finished.
@export_range(0, 600, 1) var getup_iframes: int = 0


# --- Movement curve (GDD 13.3) ------------------------------------------------

## Metres the character is carried forward along its facing, spread evenly
## across the active window. This is what gives a swing weight without needing a
## baked root-motion track: a heavy travels, a light barely moves, and the
## difference is one number a designer can see and change.
@export_range(-4.0, 4.0, 0.01) var advance_m: float = 0.0

## Metres of lift applied over the active window, for rising moves. Zero for
## anything that stays on the ground.
@export_range(0.0, 4.0, 0.01) var rise_m: float = 0.0

## How far forward this move has travelled by `tick`, used to integrate a
## constant rate per tick rather than recomputing from a curve.
func advance_at(tick: int) -> float:
	if advance_m == 0.0:
		return 0.0
	var span := active_to - active_from
	if span <= 0:
		return 0.0
	var u := clampf(float(tick - active_from) / float(span), 0.0, 1.0)
	return advance_m * u


# --- Reach and sweep ----------------------------------------------------------

## Thickness of the hit capsule around the blade, metres.
@export_range(0.01, 1.0, 0.01) var blade_radius: float = 0.14

## The blade's path through the active window, in the character's own space:
## left / up / forward for both the hilt and the tip, so six floats per sample.
##
## Two samples describe a straight swing; three or more describe a compound arc.
## Interpolated across [active_from, active_to]. See BladePose for the axes and
## for why these are authored rather than baked from an animation.
@export var sweep: Array[BladePose] = []

## Inspector convenience: which ready-made arc the preset button applies.
@export var sweep_preset: BladePose.Preset = BladePose.Preset.HORIZONTAL_SLASH

@export_tool_button("Apply sweep preset", "Animation") var _apply_preset := _apply_sweep_preset


func _apply_sweep_preset() -> void:
	sweep = BladePose.from_preset(sweep_preset)
	notify_property_list_changed()


# --- Chaining (GDD 5.3) -------------------------------------------------------

## Position in this move's chain. Used for telemetry and for the cost ramp.
@export_range(0, 8, 1) var chain_index: int = 0

## The move that follows when the chain is continued. Null ends the chain.
@export var chain_next: AttackTable = null

## This move may only be entered by cancelling into it out of another move, so
## a chain cannot be started from neutral by skipping its opener.
@export var requires_chain: bool = false


# --- Derived ------------------------------------------------------------------

## Anticipation length in ticks.
var startup_ticks: int:
	get: return active_from

## Active contact length in ticks.
var active_ticks: int:
	get: return maxi(0, active_to - active_from)

## Recovery length in ticks.
var recovery_ticks: int:
	get: return maxi(0, total_ticks - active_to)

func has_invulnerability() -> bool:
	return iframes_from >= 0 and iframes_to > iframes_from


func is_active(tick: int) -> bool:
	return tick >= active_from and tick < active_to


func is_invulnerable(tick: int) -> bool:
	return has_invulnerability() and tick >= iframes_from and tick < iframes_to


func can_cancel(tick: int) -> bool:
	return tick >= cancel_from


func listens_for_input(tick: int) -> bool:
	return tick >= input_from


## How far in front of the character this move's blade actually gets.
##
## This, not `max_reach`, is the number that decides whether an attack can
## connect. `max_reach` is a radial distance from the character's origin, and a
## wind-up pose with the blade raised overhead scores high on it while being
## unable to touch anything in front - a heavy chop measured radially reads as a
## 2.6 m weapon that in fact only reaches about a metre.
func forward_reach() -> float:
	var furthest := 0.0
	for pose in sweep:
		if pose == null:
			continue
		furthest = maxf(furthest, maxf(pose.tip.z, pose.hilt.z))
	return furthest


## Longest the blade gets from the character's origin, over the whole sweep,
## measured radially. Useful for drawing and for a conservative range bound;
## prefer `forward_reach` when asking whether an attack will connect.
func max_reach() -> float:
	var longest := 0.0
	for pose in sweep:
		if pose == null:
			continue
		longest = maxf(longest, maxf(pose.tip_reach(), pose.hilt.length()))
	return longest


## How far the blade tip travels along its path, in metres. This is the number
## that decides whether a swing *reads* as a swing: a large lateral travel with a
## small reach reads as a flourish, and a large reach with almost no travel reads
## as a poke.
func sweep_arc_length() -> float:
	if sweep.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(sweep.size() - 1):
		var a: BladePose = sweep[i]
		var b: BladePose = sweep[i + 1]
		if a == null or b == null:
			continue
		total += a.tip.distance_to(b.tip)
	return total


## The blade at `tick` as `[hilt, tip]` in the character's local space.
##
## Returns empty when there is no authored sweep. That is a data error rather
## than a runtime condition, and `validate()` is where it gets reported - a move
## with no sweep simply cannot hit anything, which would otherwise show up as a
## combatant mysteriously taking no damage.
func blade_at(tick: int) -> Array:
	if sweep.is_empty():
		return []
	var span := active_to - active_from
	var u := 0.0
	if span > 0:
		u = clampf(float(tick - active_from) / float(span), 0.0, 1.0)
	var scaled := u * float(sweep.size() - 1)
	var i := clampi(int(floor(scaled)), 0, sweep.size() - 1)
	var j := clampi(i + 1, 0, sweep.size() - 1)
	return BladePose.blend(sweep[i], sweep[j], scaled - float(i))


## Does this move have to connect to be worth anything?
##
## A dodge, a landing, a reaction and a charge wind-up all legitimately have no
## active window and no sweep. Only offence has to be able to hit, and treating
## the others as errors turns the validator into noise that gets ignored.
func is_offensive() -> bool:
	return family == Family.LIGHT or family == Family.HEAVY


## Everything wrong with this move's data, as readable strings. Empty when sound.
##
## Run over a whole moveset at author time and in CI. GDD 16's first gate is
## "animations/hitboxes disagree", and a move with a broken window or a missing
## sweep is the data-side version of that failure - cheap to catch here, and
## very expensive to diagnose from a screenshot or from a combatant
## mysteriously taking no damage.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var must_connect := is_offensive()

	# Windows that matter for every move, offence or not.
	if total_ticks <= 0:
		problems.append("total_ticks is not positive; the move would never end")
	if input_from < 0:
		problems.append("input window is negative")
	if cancel_from < input_from:
		problems.append("cancel window (%d) opens before input is heard (%d)"
			% [cancel_from, input_from])
	if has_invulnerability() and iframes_to > total_ticks:
		problems.append("i-frames end (%d) after the move ends (%d)"
			% [iframes_to, total_ticks])

	if must_connect:
		if active_to <= active_from:
			problems.append("active window is empty; this attack can never connect")
		elif active_to > total_ticks:
			problems.append("active window (%d..%d) runs past the end of the move (%d)"
				% [active_from, active_to, total_ticks])
		if cancel_from < active_to:
			problems.append("cancel window (%d) opens before the swing lands (%d); the attack can be interrupted before it connects"
				% [cancel_from, active_to])
		if damage <= 0 and posture_damage <= 0:
			problems.append("an attack that deals neither damage nor posture damage")
		if sweep.is_empty():
			problems.append("no sweep authored; this attack can never hit anything")

	# Sweep geometry, for anything that has one.
	for i in sweep.size():
		var pose := sweep[i]
		if pose == null:
			problems.append("sweep entry %d is empty" % i)
		elif pose.blade_length() < 0.05:
			problems.append("sweep entry %d has no blade between hilt and tip" % i)

	if sweep.size() >= 2:
		# A swing that changes the blade's own length is bending the weapon
		# rather than moving it, which is almost always an authoring slip.
		var lengths: Array[float] = []
		for pose in sweep:
			if pose != null:
				lengths.append(pose.blade_length())
		# Array.min/max return Variant, so these need explicit float types.
		var lo: float = lengths.min()
		var hi: float = lengths.max()
		if hi > 0.0 and (hi - lo) / hi > 0.25:
			problems.append(
				"blade length varies by more than a quarter across the sweep (%.2f to %.2f); the weapon is stretching"
				% [lo, hi]
			)

	return problems