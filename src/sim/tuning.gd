## Central tuning constants for the simulation.
##
## Every value here traces to a numbered table in the GDD so that balance work
## has one home. Two clock conventions are used deliberately and must not be
## mixed up:
##
##   * TICKS  - simulation ticks. The simulation runs at exactly 60 per second
##              (GDD 5.2). Windows, i-frames and durations are integer tick
##              counts, so window tests are exact integer comparisons.
##   * PER_SEC - continuous rates in units per second, multiplied by DT when
##              integrated. Never round these to ticks; doing so is how
##              regeneration rates drift away from their authored value.
##
## Animation is authored at 30 fps and sampled independently (GDD 5.2: "Visual
## rendering and animation sampling can run independently so long as attack
## windows remain deterministic"). Two animation frames therefore span one
## simulation tick; see ANIMATION_FPS and ticks_to_anim_frames.
class_name Tuning
extends RefCounted

## Simulation rate. Must match physics/common/physics_ticks_per_second.
const TICK_HZ := 60

## Fixed timestep, seconds. The simulation never integrates a variable dt.
const DT := 1.0 / float(TICK_HZ)

## Animation authoring rate. Two animation frames per simulation tick.
const ANIMATION_FPS := 30

## Convert a tick count to an animation-frame position, for sampling clips.
static func ticks_to_anim_frames(ticks: int) -> float:
	return float(ticks) * (float(ANIMATION_FPS) / float(TICK_HZ))

## Convert an animation-frame position back to ticks.
static func anim_frames_to_ticks(frames: float) -> float:
	return frames * (float(TICK_HZ) / float(ANIMATION_FPS))


# --- Character baseline (GDD 5.2) ---------------------------------------------

const MAX_HP := 100.0
const MAX_STAMINA := 100.0

## Stamina per second, gated by STAMINA_REGEN_DELAY_TICKS after any spend.
const STAMINA_REGEN_PER_SEC := 24.0

## GDD 5.2: "0.65 sec - Prevent immediate full uptime".
const STAMINA_REGEN_DELAY_TICKS := 39

## GDD 5.5: 5 basic dodges or 6-8 lights before depletion. With DODGE_COST and
## LIGHT_COST below, 5 dodges and 7 lights land inside that description.
const DODGE_COST := 20
const BACKSTEP_COST := 12
const JUMP_COST := 8

## GDD 5.2 gives light attacks a range because chain position changes cost.
const LIGHT_COST_MIN := 12
const LIGHT_COST_MAX := 16
const HEAVY_COST := 24
const CHARGED_HEAVY_COST := 32

## GDD 5.2: "Standard dodge invulnerability - 12 frames - Tune against visible
## attack arcs". On the 60 Hz base that is 12 ticks, or 0.2 s.
const DODGE_IFRAMES_FROM := 2
const DODGE_IFRAMES_TO := 12

## GDD 5.2: "Timed guard input window - 6 frames before contact". 6 ticks.
## GDD 5.3 requires this as a new system, layered on dodging rather than
## replacing it (see Docs/ARCHITECTURE.md, decision 2).
const TIMED_GUARD_WINDOW_TICKS := 6

## How long after a successful guard a counter is offered.
const GUARD_COUNTER_TICKS := 20

## GDD 5.2: "Player posture threshold - Repeated unsuccessful guarding can
## break stance". Stance break when the meter fills.
const PLAYER_POSTURE_THRESHOLD := 100.0

## Posture relief per second while guarding successfully.
const PLAYER_POSTURE_RELIEF_PER_SEC := 30.0

## Stamina drained per second by sprinting. Applies only while an enemy is
## hostile: running between rooms should be free.
const SPRINT_DRAIN_PER_SEC := 11.0

## GDD 5.2 healing flask: two charges, +35 HP.
const FLASK_CHARGES := 2
const FLASK_HEAL := 35.0

## Ticks after drinking a flask during which no new flask can be started. The
## charge count is the real constraint (GDD 5.2); this only exists so the drink
## reads as a deliberate act rather than a free button mash.
const FLASK_LOCK_TICKS := 30

## GDD 6.1: ninja tools are limited-charge gadgets used with Y. Charges refresh
## at room rewards and rest nodes, so this is a per-run count, not a saved one.
const TOOL_CHARGES := 5

## Shuriken. Cheaper and faster than any melee option, which is the point: it is
## chip damage that buys a repositioning, not a damage source to build around.
## ESTIMATE - these are ours, not the GDD's.
const TOOL_DAMAGE := 12
const TOOL_POSTURE_DAMAGE := 4
const TOOL_SPEED := 22.0
const TOOL_RADIUS := 0.12
const TOOL_LIFE_TICKS := 90

## GDD 6.1 gives shuriken, smoke bombs and caltrops. Smoke and caltrops need
## status effects and area logic that does not exist yet; shuriken alone proves
## the pipeline. The others are separate work, not extra parameters.

## GDD 5.2: base active-art recharge 10-16 s. GDD 6.4: scrolls expire at run
## end, so this is a per-run timer, not saved.
const ACTIVE_ART_RECHARGE_TICKS := 600


# --- Locomotion (GDD 4.2) ------------------------------------------------------

## "The player accelerates quickly but still has weight."
const WALK_SPEED := 2.2
const RUN_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_WALK_SPEED := 1.8
const CROUCH_RUN_SPEED := 3.0

const ACCEL_PER_SEC := 26.0
const DECEL_PER_SEC := 34.0

## Stick magnitude below which the character walks instead of runs.
const WALK_TILT := 0.55
const STICK_DEADZONE := 0.1

## GDD 4.1: "B tap / hold - Dodge/backstep / sprint". The dodge button commits
## to a roll on release, and holding it past this many ticks is a sprint
## instead. Roughly a fifth of a second, which is long enough to mean "I meant
## to roll" and short enough that a sprint is never an accident.
const SPRINT_HOLD_TICKS := 10

## Degrees to radians. Godot 4 has no global `DEG` constant, and a simulation
## that states its own conversion is easier to check than one that hopes for a
## built-in. Turn rates are authored in degrees because that is how a designer
## reads them; the simulation integrates in radians.
const DEG_TO_RAD := PI / 180.0

## Degrees per second.
const TURN_FREE := 1080.0
const TURN_SPRINT := 480.0
const TURN_LOCKED := 720.0

## Height the character steps up or down without leaving the ground.
const STEP_HEIGHT := 0.35


# --- Lock-on (GDD 4.3) --------------------------------------------------------

## Locked-on locomotion faces the target and enables strafing (GDD 4.2).
const LOCK_ON_RANGE := 15.0
const LOCK_BREAK_RANGE := 22.0

## How close an enemy must be for the player to count as "in contact". Only
## then does sprinting drain stamina (GDD 5.2's stamina economy is a combat
## budget, not a movement tax).
const AGGRO_CONTACT_RANGE := 12.0


# --- Air ----------------------------------------------------------------------

## GDD 5.2 does not specify jump or fall figures, so these are ours and are
## marked as such in every balancing sheet. Tuned for a chibi ninja roughly
## 1.6 m tall: high enough to clear a crate, quick enough that jumping is a
## movement option rather than a commitment.
const GRAVITY_PER_SEC := 24.0
const JUMP_VELOCITY := 7.0
const TERMINAL_VELOCITY := 25.0

## Fall damage starts here and is fatal at FALL_DEATH. Tuned so the blockout
## arena's staircase can be set to exercise both thresholds.
const FALL_DAMAGE_START := 4.0
const FALL_DEATH := 12.0
## Fraction of max health lost per metre between the two thresholds.
const FALL_DAMAGE_PER_METRE := 0.06


# --- Charge (GDD 5.3) ---------------------------------------------------------

## Ticks the heavy button must be held before the committed, charged swing is
## released. Past this the charge resolves into `charged_heavy`; releasing
## earlier gives the uncharged swing instead, so the player chooses between the
## two by when they let go rather than by which button they pressed.
const CHARGE_TICKS := 40


# --- Hit registration ---------------------------------------------------------

## A fast swing moves the blade tip a third of a metre in one tick. One check
## per tick would let the blade pass straight through a thin target between
## checks, so each tick is sampled at several sub-steps and any sub-step that
## touches registers the hit. This is the single most important number in the
## file: set it to 1 and hits start tunnelling.
const SWEEP_SUBSTEPS := 5


# --- Damage reaction ----------------------------------------------------------

## GDD 5.3: "small flinch, medium stagger, heavy stagger and knockdown;
## immunity rules prevent stun-lock loops on elites and bosses."
enum HurtLevel { NONE, FLINCH, STAGGER, HEAVY_STAGGER, KNOCKDOWN }

## Fraction of incoming damage that passes a raised guard, and the stamina
## cost multiplier of guarding rather than eating a hit.
const GUARD_DAMAGE_TAKEN := 0.0
const GUARD_STAMINA_MULTIPLIER := 1.0

## GDD 5.3: perfect dodge is a narrower window than the full i-frame span.
const PERFECT_DODGE_TICKS := 4

## How far the character's feet must clear the ground for a low sweep to pass
## underneath. Below this, jumping does not answer a sweep, which keeps jump a
## real decision rather than a universal answer (GDD 5.4).
const JUMP_CLEARANCE := 0.35

## Characters are solid (GDD 5.4: attacks cannot secretly reach far beyond
## their visible blade; bodies likewise cannot interpenetrate).
const BODY_RADIUS := 0.4

## Combat events retained for the HUD and telemetry before the oldest are
## dropped. Bounded so a long fight cannot grow the array without limit.
const MAX_EVENTS := 256

## Height of a character's body, feet to crown. GDD 11.2 puts the hero at
## 2.75-3.25 heads tall and chibi, so this is short and deliberately so: a
## capsule this size reads clearly on screen at the combat camera distance
## GDD 4.3 asks for, and a taller one would make low sweeps ambiguous.
const CHARACTER_HEIGHT := 1.6


static func hurt_level_name(level: HurtLevel) -> String:
	match level:
		Tuning.HurtLevel.FLINCH: return "flinch"
		Tuning.HurtLevel.STAGGER: return "stagger"
		Tuning.HurtLevel.HEAVY_STAGGER: return "heavy stagger"
		Tuning.HurtLevel.KNOCKDOWN: return "knockdown"
		_: return "none"