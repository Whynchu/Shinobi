## Shared combatant core: the things both the player and every enemy have.
##
## This holds resources and reaction state only. It does not decide when an
## attack starts or what a move's windows are; that belongs to the attack table
## and to whichever action machine is driving this combatant. Keeping the two
## apart is deliberate: a player needs an input buffer and cancel windows,
## an enemy needs an authored windup script, and neither should be forced to
## carry the other's machinery (see Docs/ARCHITECTURE.md, decision 1).
class_name Combatant
extends RefCounted

## What happened when a hit was offered to this combatant. GDD 5.1 requires
## every attack to have a legible answer; these are the answers.
enum Outcome {
	IGNORED,       ## already dead, or the attack was never live
	DODGED,        ## i-frames: the attack passed through
	PERFECT_DODGE, ## dodged inside the narrower perfect-dodge window
	JUMPED,        ## a low sweep passed underneath
	GUARDED,       ## absorbed at reduced cost
	TIMED_GUARD,   ## guarded inside the timing window: little stamina cost, posture damage
	GUARD_BROKEN,  ## guarding drained the resource; stance broken
	HIT,           ## took damage
	KILLED,        ## took damage and died
}

## Where this combatant is. Yaw 0 faces +Z and positive yaw turns toward +X,
## the same convention the camera and the authored blade sweeps use (see
## SimMath). Declared here rather than inherited, because this is a RefCounted
## and not a Node.
var position := Vector3.ZERO
var yaw := 0.0

## Times 60 Hz has not run at full speed yet, so stamina cannot regenerate.
var stamina_regen_delay := 0

## Set while a posture break is unavailable, so a chain of light hits cannot
## hold an enemy in an unbroken stagger forever (GDD 5.3, "immunity rules
## prevent stun-lock loops on elites and bosses").
var posture_immunity := 0

## Whether this combatant currently has an unbroken posture meter.
var posture_broken := false

## Ticks left in the signposted finisher opening created by a posture break.
var finisher_ticks := 0

## Ticks the attacker and target freeze together on contact (GDD 5.1).
var hit_stop := 0

## Set by whichever machine is driving this combatant; consulted by the
## presentation layer to pick the right reaction animation.
var last_outcome: Outcome = Outcome.IGNORED

var max_hp := Tuning.MAX_HP
var hp := Tuning.MAX_HP
var max_stamina := Tuning.MAX_STAMINA
var stamina := Tuning.MAX_STAMINA
var max_posture := Tuning.PLAYER_POSTURE_THRESHOLD
var posture := 0.0

var dead := false

## Timed guard still has this many ticks of its window left in which to reward
## a defender (GDD 5.2, TIMED_GUARD_WINDOW_TICKS).
var timed_guard_ticks := 0

## A guard that has already connected can be answered for this many ticks.
var guard_counter_ticks := 0

## Extra posture relief applied while this combatant is holding a guard up.
var posture_relief_per_sec := 0.0


func _init(p_position := Vector3.ZERO, p_yaw := 0.0) -> void:
	position = p_position
	yaw = p_yaw
	hp = max_hp
	stamina = max_stamina
	posture = 0.0
	reset_reactions()


## Everything that resets when a run restarts or a combatant respawns. Position
## and resources are handled by the caller.
func reset_reactions() -> void:
	dead = false
	posture = 0.0
	posture_broken = false
	posture_immunity = 0
	finisher_ticks = 0
	hit_stop = 0
	stamina_regen_delay = 0
	timed_guard_ticks = 0
	guard_counter_ticks = 0
	last_outcome = Outcome.IGNORED


func hp_fraction() -> float:
	return 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)


func stamina_fraction() -> float:
	return 0.0 if max_stamina <= 0.0 else clampf(stamina / max_stamina, 0.0, 1.0)


func posture_fraction() -> float:
	return 0.0 if max_posture <= 0.0 else clampf(posture / max_posture, 0.0, 1.0)


## Yaw 0 faces +Z; positive yaw turns toward +X. Matches the convention the
## camera and the authored sweeps both use.
func facing() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func left() -> Vector3:
	var f := facing()
	return Vector3(f.z, 0.0, -f.x)


## Spend stamina and start the regen delay (GDD 5.2: a 0.65 s delay prevents
## immediate full uptime). Returns the amount actually spent, which may be less
## than asked when the bar runs dry.
func spend_stamina(amount: int) -> int:
	var before := stamina
	stamina = maxf(0.0, stamina - float(amount))
	stamina_regen_delay = Tuning.STAMINA_REGEN_DELAY_TICKS
	return int(round(before - stamina))


func has_stamina(amount: int) -> bool:
	return stamina >= float(amount)


## Regenerate. `regen_per_sec` is zero while an action is committed to; the
## delay gate is what stops attack-dodge-attack from being free.
func tick_resources(regen_per_sec := Tuning.STAMINA_REGEN_PER_SEC) -> void:
	if stamina_regen_delay > 0:
		stamina_regen_delay -= 1
	elif regen_per_sec > 0.0 and stamina < max_stamina:
		stamina = minf(max_stamina, stamina + regen_per_sec * Tuning.DT)

	if posture_immunity > 0:
		posture_immunity -= 1
	if finisher_ticks > 0:
		finisher_ticks -= 1
	if timed_guard_ticks > 0:
		timed_guard_ticks -= 1
	if guard_counter_ticks > 0:
		guard_counter_ticks -= 1
	if hit_stop > 0:
		hit_stop -= 1

	if posture_relief_per_sec > 0.0 and not posture_broken:
		posture = maxf(0.0, posture - posture_relief_per_sec * Tuning.DT)


## Offer an incoming hit. Returns what happened.
##
## `move` is the attack that connected. `from` is where the attacker was.
## `guarding` and `timed_guard` are supplied by the machine driving this
## combatant, because whether a guard is up and whether it was timed are
## state-machine questions rather than resource questions.
##
## `invulnerable` is likewise passed in: the window lives on the move being
## played, not on the body.
func receive_hit(move: AttackTable, from: Vector3, guarding: bool, timed_guard: bool) -> Outcome:
	if dead:
		last_outcome = Outcome.IGNORED
		return last_outcome

	# The guard counter window, then the timed guard window, then a plain guard.
	# Timing is checked before anything else so that a perfectly-timed guard is
	# never downgraded by an incidental overlap.
	if guarding and timed_guard:
		add_posture(move.timed_guard_posture)
		stamina = maxf(0.0, stamina - float(move.stamina_cost) * 0.25)
		stamina_regen_delay = Tuning.STAMINA_REGEN_DELAY_TICKS
		timed_guard_ticks = 0
		guard_counter_ticks = Tuning.GUARD_COUNTER_TICKS
		return _finish(Outcome.TIMED_GUARD)

	if guarding:
		var cost := int(round(float(move.stamina_cost) * Tuning.GUARD_STAMINA_MULTIPLIER))
		stamina -= float(cost)
		stamina_regen_delay = Tuning.STAMINA_REGEN_DELAY_TICKS
		if stamina <= 0.0:
			stamina = 0.0
			# Standing in a guard with no stamina left is how stance breaks
			# (GDD 5.2, PLAYER_POSTURE_THRESHOLD).
			hp -= float(move.damage) * Tuning.GUARD_DAMAGE_TAKEN
			guard_counter_ticks = 0
			return _finish(Outcome.GUARD_BROKEN if not _died() else Outcome.KILLED)
		add_posture(move.guard_damage)
		guard_counter_ticks = Tuning.GUARD_COUNTER_TICKS
		hp -= float(move.damage) * Tuning.GUARD_DAMAGE_TAKEN
		return _finish(Outcome.GUARDED if not _died() else Outcome.KILLED)

	# An unguarded hit. Posture damage still applies alongside health damage,
	# so guarding is worth doing even when health is plentiful (GDD 5.3).
	add_posture(move.posture_damage)
	hp -= float(move.damage)
	if _died():
		return _finish(Outcome.KILLED)
	return _finish(Outcome.HIT)


## Fill the posture meter. Returns true if this hit caused a break.
##
## A broken meter opens a short, clearly signposted finisher (GDD 5.3). It
## cannot re-break while `posture_immunity` is running, which is the rule that
## stops a light-attack chain from stun-locking an elite.
func add_posture(amount: int) -> bool:
	if amount <= 0 or posture_broken or posture_immunity > 0:
		return false
	posture = minf(max_posture, posture + float(amount))
	if posture >= max_posture:
		posture_broken = true
		finisher_ticks = 60
		posture_immunity = 60
		return true
	return false


func recover_posture() -> void:
	posture = 0.0
	posture_broken = false
	posture_immunity = 0
	finisher_ticks = 0


## The defender's answer to an incoming hit, given the machine's current state.
##
## This decides only whether the attack was avoided at all. Damage resolution is
## `receive_hit`'s job. Separating them keeps the ordering honest: if an attack
## was dodged there is no damage question to answer, and if it was not, the
## guard question is the only thing left.
##
## Ordered most-specific first, because GDD 5.1 makes legibility the contract:
## each of these is a distinct, learnable response to a distinct player action.
## `invulnerable` is the i-frame window of the action currently being played.
static func evaluate_evade(
		move: AttackTable, airborne: bool, invulnerable: bool, clearance: float
) -> bool:
	if invulnerable:
		return true
	# A low sweep only misses if the character is genuinely off the ground.
	# A roll's i-frames do not help here, which is what makes sweep a distinct
	# answer to dodge.
	if move.is_low_sweep and airborne and clearance > Tuning.JUMP_CLEARANCE:
		return true
	return false


## Whether a dodge landed inside the perfect-dodge window rather than merely
## inside the i-frame span (GDD 5.3). Returns an Outcome so the caller can
## report DODGED or PERFECT_DODGE distinctly to the player and to telemetry.
static func evaluate_perfect_dodge(
		move: AttackTable, tick: int, dodging: bool, invulnerable: bool
) -> Outcome:
	if not dodging or not invulnerable:
		return Outcome.HIT
	var started := move.iframes_from
	var perfect_to := started + Tuning.PERFECT_DODGE_TICKS
	if tick >= started and tick < perfect_to:
		return Outcome.PERFECT_DODGE
	return Outcome.DODGED


func _finish(outcome: Outcome) -> Outcome:
	last_outcome = outcome
	return outcome


func _died() -> bool:
	if hp <= 0.0:
		hp = 0.0
		dead = true
		return true
	return false