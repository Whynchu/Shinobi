## One position of the blade during a swing.
##
## A pose is where the hilt is and where the tip is, both in the character's own
## space rather than world space. Authoring in local space is what makes a move
## portable: the same slash works regardless of where the character is standing
## or which way it is facing, and rotating it is a rotation of the character, not
## an edit to every frame of the swing.
##
## ## Axes
##
##   X - the character's LEFT
##   Y - up
##   Z - forward, the way it faces
##
## X is left rather than right because a swing reads left-to-right the same way
## a player expects, and because `Combatant.left()` is the vector these values
## are scaled along. It is the one axis worth getting wrong-by-heart, so it is
## stated here and on every field.
##
## ## Why hand-authored rather than baked
##
## The alternative is sampling a blade bone out of an animation clip. That ties
## reach rigidly to the motion, which is not obviously right for an original
## chibi rig, and it makes changing a number mean re-exporting an animation.
## Authored poses keep the simulation independent of playback, recalibrate the
## moment proportions change, and let a weapon deliberately reach further than it
## looks - which GDD 5.4's "hitboxes follow visual sweeps closely" leaves room
## for and most action games rely on.
##
## A move with two poses describes a straight swing. Three or more describe a
## compound arc. `AttackTable` interpolates between them across the active
## window.
@tool
class_name BladePose
extends Resource

## Where the blade is gripped.
@export var hilt := Vector3(0.0, 1.0, 0.1)

## Where the blade ends.
@export var tip := Vector3.ZERO

## Seconds / ticks of the active window this pose sits at, 0 to 1. Authored
## implicitly by list order, so this is only for reading: the inspector shows
## the ordered list, and the position within it is what matters.
@export var weight := 1.0


func _init(p_hilt := Vector3(0.0, 1.0, 0.1), p_tip := Vector3.ZERO) -> void:
	hilt = p_hilt
	tip = p_tip


## Length of the blade this pose implies, in metres. A moving character should
## keep this roughly constant across the whole sweep; if it does not, the arc is
## bending rather than swinging, which is usually a mistake.
func blade_length() -> float:
	return hilt.distance_to(tip)


## How far the tip gets from the character's origin, ignoring the hilt.
func tip_reach() -> float:
	return Vector3(tip.x, tip.y, tip.z).length()


static func make(p_hilt: Vector3, p_tip: Vector3) -> BladePose:
	return BladePose.new(p_hilt, p_tip)


## Blend two poses' hilt and tip, returned as `[hilt, tip]`.
##
## Returns a plain Array rather than a BladePose on purpose: this runs once per
## tick per attacker, and allocating a Resource on the hot path is exactly the
## kind of garbage that makes a GDScript simulation stutter later.
static func blend(a: BladePose, b: BladePose, t: float) -> Array:
	if a == null:
		return [] if b == null else [b.hilt, b.tip]
	if b == null:
		return [a.hilt, a.tip]
	return [a.hilt.lerp(b.hilt, t), a.tip.lerp(b.tip, t)]


## Ready-made arcs, so a move starts from a sensible shape instead of two zeros.
##
## Every preset takes a **blade length** and derives the reach from it. Getting
## that ordering right matters more than it looks:
##
##   * Blade length is physically bounded - a katana is about a metre, and no
##     amount of animation can make it longer. Reach is not bounded, but it is
##     *consequential*: a preset parameterised by reach has to stretch the blade
##     to achieve it. Asking for a 1.6 m overhead reach from a hilt close to the
##     body silently produces a 2.1 m weapon.
##   * So reach is a *consequence*, printed by the moveset report. A designer
##     lengthens the blade or edits the poses until the reach looks right, with
##     the number visible rather than guessed.
##
## These are starting points to adjust, not fixed values.

## A pose whose tip sits `length` metres from the hilt along `direction`.
static func _swing(hilt: Vector3, direction: Vector3, length: float) -> BladePose:
	var d := direction
	if d.length_squared() < 1e-6:
		d = Vector3(0.0, 0.0, 1.0)
	return make(hilt, hilt + d.normalized() * length)


## A level horizontal slash, travelling across the body from one side to the
## other. The bread-and-butter katana swing. Reach is roughly `blade + 0.1`.
static func horizontal_slash(blade := 1.25, height := 1.0, lateral := 0.45) -> Array[BladePose]:
	return [
		_swing(Vector3(lateral, height, 0.1), Vector3(0.0, 0.0, 1.0), blade),
		_swing(Vector3(-lateral, height, 0.1), Vector3(0.0, 0.0, 1.0), blade),
	]


## An overhead chop, raised behind the head and brought down in front. The tip
## travels down as well as forward, so its forward reach is well under the blade
## length.
static func overhead_chop(blade := 1.15) -> Array[BladePose]:
	return [
		_swing(Vector3(0.0, 1.55, 0.0), Vector3(0.0, 0.9, -0.4), blade),
		_swing(Vector3(0.0, 1.20, 0.2), Vector3(0.0, -0.75, 0.65), blade),
	]


## A low sweep, passing below the knee line so a jump clears it and a dodge's
## i-frames are not the answer (GDD 5.4: every major attack needs a consistent
## answer, and they should not all have the same one).
static func low_sweep(blade := 1.20, height := 0.85, lateral := 0.4) -> Array[BladePose]:
	var dir := Vector3(0.0, -0.45, 0.9)
	return [
		_swing(Vector3(lateral, height, 0.2), dir, blade),
		_swing(Vector3(-lateral, height, 0.2), dir, blade),
	]


## A straight thrust, reaching forward with almost no lateral travel. The one arc
## where standing beside it should genuinely miss, and the preset with the most
## reach per metre of blade.
##
## The wind-up cocks the blade backwards rather than retracting it. A thrust
## that shortens to extend reads as the weapon growing, and `validate()` would
## rightly complain - the blade is the same length in both poses, only its
## direction changes.
static func thrust(blade := 1.35, height := 1.1) -> Array[BladePose]:
	var hilt := Vector3(0.0, height, 0.25)
	return [
		_swing(hilt, Vector3(0.0, -0.25, -0.6), blade),
		_swing(hilt, Vector3(0.0, 0.0, 1.0), blade),
	]


## A rising diagonal, used for jump attacks that gain a little lift.
static func rising_slash(blade := 1.15) -> Array[BladePose]:
	return [
		_swing(Vector3(0.35, 0.55, 0.1), Vector3(0.0, 0.55, 0.85), blade),
		_swing(Vector3(-0.35, 1.35, 0.1), Vector3(0.0, 0.35, 0.95), blade),
	]


## Every preset, for an inspector dropdown.
enum Preset { HORIZONTAL_SLASH, OVERHEAD_CHOP, LOW_SWEEP, THRUST, RISING_SLASH }

static func from_preset(which: Preset, blade := 1.25) -> Array[BladePose]:
	match which:
		Preset.OVERHEAD_CHOP: return overhead_chop(blade)
		Preset.LOW_SWEEP: return low_sweep(blade)
		Preset.THRUST: return thrust(blade)
		Preset.RISING_SLASH: return rising_slash(blade)
		_: return horizontal_slash(blade)