## The player's action state machine.
##
## Written from GDD 4.2 (movement) and 5.3 (offence, defence, stagger). It is
## not a translation of any other project's code: the MIT-licensed Elden Ring
## study named in GDD 13.1 was read for structural ideas, and no Elden Ring data
## appears anywhere in this project (GDD 1.2, 17).
##
## Rules this file is built around, all traceable to the GDD:
##
##   * Fixed 60 Hz. Every window is an integer tick count, so window tests are
##     exact comparisons rather than float comparisons that drift (GDD 5.2).
##   * One buffered request, newest wins. GDD 5.2: "permit one queued attack
##     near the end of recovery but never a dozen prebuffered inputs."
##   * A press before the current move opens its input window is dropped, not
##     banked. This is the mechanism that stops mashing from queueing attacks
##     during a long animation.
##   * Inputs are still read while hit-stopped. A swing freezes the world's
##     motion; it does not deafen the player.
##
## This class uses no engine type beyond Vector3 and holds no node references,
## which is what lets identical code run inside a scene tree and inside a
## headless test with no window at all.
class_name PlayerMachine
extends Combatant

enum State {
	GROUND,  ## free to start a new action
	ACTION,  ## committed to a move; `tick` counts through it
	AIR,     ## off the ground
	DEAD,
}

## The single buffered request.
enum Req { NONE, LIGHT, HEAVY, DODGE, JUMP }

var moveset: Moveset

var state: State = State.GROUND

## Ticks elapsed in the current move.
var tick := 0

## The move being performed. Null in GROUND and AIR.
var move: AttackTable = null

# --- Locomotion ---------------------------------------------------------------

var speed := 0.0
var move_dir := Vector3(0.0, 0.0, 1.0)
var sprinting := false
var crouching := false
var guarding := false
var in_contact := false

## Cardinal direction of the current dodge or jump, for presentation and for
## picking the right authored move.
var last_cardinal: CombatInput.Cardinal = CombatInput.Cardinal.FRONT

var locked := false
var lock_position := Vector3.ZERO

# --- Consumables (GDD 5.2, 6.1) ------------------------------------------------

## Healing flasks remaining this run. Reset on every run: GDD 3.4 wipes
## consumables with the build on death.
var flask_charges := Tuning.FLASK_CHARGES

## Ninja tool charges remaining this run.
var tool_charges := Tuning.TOOL_CHARGES

## Ticks until another flask may be drunk.
var flask_lock := 0

## Ticks until another tool may be thrown.
var tool_lock := 0

# --- Buffered input -----------------------------------------------------------

var _buffered: Req = Req.NONE

# --- Dodge / sprint button ----------------------------------------------------

var _dodge_hold := 0
var _dodge_armed := false
## Sprinting ran the bar dry; the button must be released before sprinting again.
var _sprint_spent := false

# --- Air ----------------------------------------------------------------------

var velocity_y := 0.0
var velocity_horizontal := Vector3.ZERO
var _takeoff_y := 0.0
var _peak_y := 0.0
## A jump attack may only come out once per jump.
var _air_attack_used := false
## Set while a jump attack is committed, so gravity keeps running underneath it.
var _in_air_move := false

# --- Root motion bookkeeping --------------------------------------------------

## How much of `move.advance_m` has been integrated so far, so forward travel is
## applied once per tick rather than recomputed from the start each tick.
var _advance_applied := 0.0

## Blade pose in world space at each end of the tick, for swept hit detection.
var _blade_prev: Array = []
var _blade_now: Array = []


## Whether the current swing has already connected with something.
##
## An active window spans several ticks, and the blade is in contact with the
## target on more than one of them. Without this flag every one of those ticks
## would register as a fresh hit, so a six-tick heavy would deal six swings'
## worth of damage. Set by the simulation when a hit lands, cleared when a move
## begins.
var swing_hit := false


## Clear per-swing bookkeeping. Called whenever a new move starts.
func _clear_swing() -> void:
	swing_hit = false


func _init(p_position := Vector3.ZERO, p_yaw := 0.0, p_moveset: Moveset = null) -> void:
	super(p_position, p_yaw)
	moveset = p_moveset if p_moveset != null else Moveset.new()


## Return to a run-ready state. Called on respawn and on dojo restart; GDD 3.4
## requires a fast restart with no long death sequence.
func reset_for_run(p_position := Vector3.ZERO) -> void:
	reset_reactions()
	position = p_position
	hp = max_hp
	stamina = max_stamina
	state = State.GROUND
	tick = 0
	move = null
	speed = 0.0
	sprinting = false
	crouching = false
	guarding = false
	velocity_y = 0.0
	velocity_horizontal = Vector3.ZERO
	_buffered = Req.NONE
	_dodge_hold = 0
	_dodge_armed = false
	_sprint_spent = false
	_blade_prev = []
	_blade_now = []
	flask_charges = Tuning.FLASK_CHARGES
	tool_charges = Tuning.TOOL_CHARGES
	flask_lock = 0
	tool_lock = 0


# --- Consumables ---------------------------------------------------------------

## Drink a healing flask (GDD 5.2: two charges, +35 HP).
##
## Refused at full health rather than wasted. Making a player spend a limited
## charge on a full bar is a punishment for not looking at the HUD, and GDD 5.1
## wants the player reading their own state rather than the interface.
func drink_flask() -> bool:
	if state == State.DEAD or flask_lock > 0 or flask_charges <= 0:
		return false
	if hp >= max_hp:
		return false
	flask_charges -= 1
	flask_lock = Tuning.FLASK_LOCK_TICKS
	hp = minf(max_hp, hp + Tuning.FLASK_HEAL)
	# Drinking out of a stagger is not free.
	state = State.GROUND
	move = null
	tick = 0
	_clear_swing()
	return true


## Throw the equipped ninja tool (GDD 6.1). Returns the projectile, or null if
## there is nothing to throw with.
##
## Thrown along the camera's yaw rather than the character's facing, because a
## thrown tool that goes where the player is looking is the one thing that makes
## shuriken feel like aiming rather than flailing. The yaw is passed in rather
## than read from a remembered input, because the world calls this before the
## player machine has sampled anything this tick.
func throw_tool(cam_yaw: float) -> Projectile:
	if state == State.DEAD or tool_lock > 0 or tool_charges <= 0:
		return null
	tool_charges -= 1
	tool_lock = Tuning.FLASK_LOCK_TICKS
	var direction := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	if direction.length_squared() < 1e-6:
		direction = facing()
	var p := Projectile.new(
		position + direction * 0.4 + Vector3.UP * Tuning.CHARACTER_HEIGHT * 0.55,
		direction.normalized() * Tuning.TOOL_SPEED
	)
	p.damage = Tuning.TOOL_DAMAGE
	p.posture_damage = Tuning.TOOL_POSTURE_DAMAGE
	p.radius = Tuning.TOOL_RADIUS
	p.life = Tuning.TOOL_LIFE_TICKS
	p.from_player = true
	return p


# --- Queries the rest of the simulation uses -----------------------------------

func airborne() -> bool:
	return state == State.AIR


## Invulnerable right now. The i-frame window belongs to the move being played,
## not to the body, so a move without one grants nothing.
func invulnerable() -> bool:
	return move != null and move.is_invulnerable(tick)


## Inside the perfect-dodge window rather than merely inside the full i-frame
## span. GDD 5.3: a perfect dodge can trigger scroll effects, so it has to be
## distinguishable from any ordinary successful dodge.
func perfect_dodge() -> bool:
	if move == null or not move.has_invulnerability():
		return false
	var perfect_to := move.iframes_from + Tuning.PERFECT_DODGE_TICKS
	return tick >= move.iframes_from and tick < perfect_to


func guard_counter_ready() -> bool:
	return guard_counter_ticks > 0


## How high the feet are above the ground. This, not "is airborne", is what
## decides whether a low sweep passes underneath: a character mid-dodge is off
## the ground but not clear of a sweep.
func clearance(level: SimLevel) -> float:
	return maxf(0.0, position.y - level.height(position.x, position.z))


## The blade's swept path across the tick that just ended, as
## `[pose_at_start_of_tick, pose_at_end_of_tick]`, where a pose is
## `[hilt, tip]` in world space. Empty when nothing is swinging.
##
## Sweeping rather than sampling once is not optional. A fast swing covers a
## third of a metre of blade travel in one tick, so a single test would let it
## pass through a target entirely between samples and the attack would silently
## whiff (GDD 18 tracks whiffs as a balance signal, so a tunnelling bug would
## surface there as data rather than as a bug).
func blade_sweep() -> Array:
	if _blade_prev.size() < 2 or _blade_now.size() < 2:
		return []
	return [_blade_prev, _blade_now]


func blade_radius() -> float:
	return move.blade_radius if move != null else 0.0


## Whether a new move may be committed right now. Shared by the buffer-drain
## paths and by the tests, so the rule lives in exactly one place.
func can_commit() -> bool:
	return stamina > 0.0 and state != State.DEAD


# --- The tick -----------------------------------------------------------------

## Advance by exactly one tick.
func step(inp: CombatInput, level: SimLevel, target_locked: bool, target_position: Vector3) -> void:
	note_input(inp)
	locked = target_locked
	if target_locked:
		lock_position = target_position

	# Buttons are read even while frozen. Hit-stop pauses the world's motion,
	# not the player's ability to ask for something.
	_read_buttons(inp)

	if hit_stop > 0:
		hit_stop -= 1
		_update_blade()
		return

	if flask_lock > 0:
		flask_lock -= 1
	if tool_lock > 0:
		tool_lock -= 1

	tick_resources(Tuning.STAMINA_REGEN_PER_SEC if _may_regen() else 0.0)

	match state:
		State.GROUND:
			_step_ground(inp, level)
		State.ACTION:
			_step_action(inp, level)
		State.AIR:
			_step_air(inp, level)
		State.DEAD:
			pass

	_update_blade()


## Stamina recovers only while the player is not spending it. That single
## condition is what makes "five dodges in a row" a resource decision rather
## than a free action (GDD 5.2).
func _may_regen() -> bool:
	return state == State.GROUND and not sprinting


func _read_buttons(inp: CombatInput) -> void:
	# GDD 4.1: the dodge button rolls on release and sprints on hold.
	if inp.dodge.pressed:
		_dodge_hold = 0
		_dodge_armed = true
	if inp.dodge.held:
		_dodge_hold += 1
	if inp.dodge.released:
		if _dodge_armed and _dodge_hold < Tuning.SPRINT_HOLD_TICKS:
			_push(Req.DODGE)
		_dodge_armed = false
		_dodge_hold = 0
		_sprint_spent = false

	# Everything else is heard only once the current move opens its input
	# window. Presses before that are dropped rather than banked, which is how
	# GDD 5.2's "never a dozen prebuffered inputs" is enforced rather than
	# merely intended.
	if not _listening():
		return
	if inp.jump.pressed:
		_push(Req.JUMP)
	if inp.heavy.pressed:
		_push(Req.HEAVY)
	if inp.light.pressed:
		_push(Req.LIGHT)


## One slot, newest wins. An earlier request is overwritten, not queued behind.
func _push(request: Req) -> void:
	_buffered = request


func _take_buffered() -> Req:
	var r := _buffered
	_buffered = Req.NONE
	return r


func _listening() -> bool:
	if state == State.GROUND:
		return true
	return move != null and move.listens_for_input(tick)


# --- Ground -------------------------------------------------------------------

func _step_ground(inp: CombatInput, level: SimLevel) -> void:
	if _buffered != Req.NONE:
		var request := _take_buffered()
		if _try_start(request, inp):
			return

	# Crouch follows the button rather than toggling on it. A level-triggered
	# toggle flips once per tick the button is held, so holding crouch makes the
	# character crouch and stand sixty times a second. GDD 14 wants a toggle
	# option, which belongs in the input layer where the press edge lives.
	crouching = inp.crouch

	# Sprinting only costs stamina in contact with an enemy. Running between
	# rooms should be free, or players learn to walk everywhere.
	var was_sprinting := sprinting
	sprinting = (
		inp.dodge.held
		and _dodge_hold >= Tuning.SPRINT_HOLD_TICKS
		and inp.is_wishing()
		and not _sprint_spent
		and stamina > 0.0
	)
	if sprinting:
		crouching = false
		if in_contact:
			stamina = maxf(0.0, stamina - Tuning.SPRINT_DRAIN_PER_SEC * Tuning.DT)
			if stamina <= 0.0:
				sprinting = false
				_sprint_spent = true

	# Guard. Pressing opens the timed window; merely holding does not. That
	# distinction is the whole of timed guard (GDD 5.3).
	if inp.guard.held and not sprinting:
		if inp.guard.pressed:
			timed_guard_ticks = Tuning.TIMED_GUARD_WINDOW_TICKS
		guarding = true
		posture_relief_per_sec = Tuning.PLAYER_POSTURE_RELIEF_PER_SEC
	else:
		guarding = false
		posture_relief_per_sec = 0.0

	_step_locomotion(inp, level, was_sprinting)


func _step_locomotion(inp: CombatInput, level: SimLevel, _was_sprinting: bool) -> void:
	var wish := inp.wish_direction()
	var wishing := inp.is_wishing()
	var walking := inp.walk or inp.stick_tilt() < Tuning.WALK_TILT

	var target_speed := 0.0
	if wishing:
		if sprinting:
			target_speed = Tuning.SPRINT_SPEED
		elif crouching:
			target_speed = Tuning.CROUCH_WALK_SPEED if walking else Tuning.CROUCH_RUN_SPEED
		elif walking:
			target_speed = Tuning.WALK_SPEED
		else:
			target_speed = Tuning.RUN_SPEED

	var rate := Tuning.ACCEL_PER_SEC if target_speed > speed else Tuning.DECEL_PER_SEC
	speed = move_toward(speed, target_speed, rate * Tuning.DT)
	speed = clampf(speed, 0.0, Tuning.SPRINT_SPEED)

	if not inp.is_wishing():
		move_dir = facing()
	elif locked and not sprinting:
		# Locked on: keep facing the target and strafe around it (GDD 4.2).
		var to := lock_position - position
		to.y = 0.0
		if to.length_squared() > 1e-6:
			yaw = SimMath.turn_towards(yaw, atan2(to.x, to.z), Tuning.TURN_LOCKED * Tuning.DEG_TO_RAD * Tuning.DT)
		move_dir = wish
	else:
		yaw = SimMath.turn_towards(
			yaw,
			atan2(wish.x, wish.z),
			(Tuning.TURN_SPRINT if sprinting else Tuning.TURN_FREE) * Tuning.DEG_TO_RAD * Tuning.DT
		)
		move_dir = facing()

	position = level.slide(position, move_dir * speed * Tuning.DT)

	# Walking off a ledge starts a fall rather than leaving the character
	# hanging with no state.
	var ground := level.height(position.x, position.z)
	if position.y - ground > Tuning.STEP_HEIGHT:
		_enter_air(false, move_dir * speed)
	else:
		position.y = ground


# --- Action -------------------------------------------------------------------

func _step_action(_inp: CombatInput, level: SimLevel) -> void:
	if move == null:
		state = State.GROUND
		return

	_resolve_charge()

	var previous := tick
	tick += 1

	_apply_advance(level, previous)

	# A jump attack commits to a move but does not stop the fall, so gravity
	# keeps integrating underneath it and the character still lands.
	if _in_air_move:
		velocity_y = maxf(velocity_y - Tuning.GRAVITY_PER_SEC * Tuning.DT, -Tuning.TERMINAL_VELOCITY)
		position.y += velocity_y * Tuning.DT
		_peak_y = maxf(_peak_y, position.y)
		if position.y <= level.height(position.x, position.z):
			position.y = level.height(position.x, position.z)
			_in_air_move = false
			_land()
			return

	if move == null:
		state = State.GROUND
		return

	# A buffer only cashes out once the move opens its cancel window.
	if _buffered != Req.NONE and move.can_cancel(tick):
		var request := _take_buffered()
		if _resolve_cancel(request):
			return

	if tick >= move.total_ticks:
		_end_action()
		state = State.GROUND


## A charged heavy resolves both ways once the charge window opens: letting go
## early gives the uncharged swing, holding past CHARGE_TICKS gives the charged
## one. The player chooses by *when they release*, not by a separate button
## (GDD 5.2 lists one heavy button).
func _resolve_charge() -> void:
	if move == null or move.family != AttackTable.Family.CHARGE:
		return
	if _heavy_held and tick >= Tuning.CHARGE_TICKS and moveset.charged_heavy != null:
		if stamina_has(moveset.charged_heavy.stamina_cost):
			_begin(moveset.charged_heavy)
	elif not _heavy_held and tick >= move.cancel_from and moveset.heavy != null:
		if stamina_has(moveset.heavy.stamina_cost):
			_begin(moveset.heavy)


## Integrating `advance_m` once per tick keeps a swing's forward travel tied to
## the simulation clock rather than to an animation. That is what makes the
## reach a designer reads in the table the reach the player actually gets.
func _apply_advance(level: SimLevel, _previous: int) -> void:
	if move == null:
		_advance_applied = 0.0
		return
	var want := move.advance_at(tick)
	var delta := want - _advance_applied
	if delta != 0.0:
		position = level.slide(position, facing() * delta)
	_advance_applied = want


func _resolve_cancel(request: Req) -> bool:
	match request:
		Req.DODGE:
			return _try_start(Req.DODGE, _last_input)
		Req.JUMP:
			return _try_start(Req.JUMP, _last_input)
		Req.LIGHT:
			var next: AttackTable = null
			if move != null and move.family == AttackTable.Family.LIGHT:
				next = moveset.next_light(move)
			else:
				next = moveset.first_light()
			# A move flagged requires_chain may only be entered from inside a
			# chain, so the opening swing cannot be skipped.
			if next != null and (not next.requires_chain or _in_light_chain()):
				return _begin(next)
		Req.HEAVY:
			if guard_counter_ready() and moveset.guard_counter != null:
				return _begin(moveset.guard_counter)
			return _try_start(Req.HEAVY, _last_input)
	return false


func _in_light_chain() -> bool:
	return move != null and move.family == AttackTable.Family.LIGHT


func _end_action() -> void:
	move = null
	tick = 0
	speed = 0.0
	_advance_applied = 0.0
	_in_air_move = false


# --- Starting actions ---------------------------------------------------------

## The input snapshot from the most recent tick, kept so that a cancel
## resolving several ticks after the press still knows what direction the
## player was pointing when they asked for it.
var _last_input: CombatInput
var _heavy_held := false


func _try_start(request: Req, inp: CombatInput) -> bool:
	if moveset == null:
		return false

	match request:
		Req.DODGE:
			return _start_dodge(inp)
		Req.JUMP:
			return _start_jump(inp)
		Req.LIGHT:
			var first := moveset.first_light()
			if first == null or first.requires_chain:
				return false
			return _begin(first)
		Req.HEAVY:
			if guard_counter_ready() and moveset.guard_counter != null:
				return _begin(moveset.guard_counter)
			# The charge move if there is one, otherwise the plain swing.
			var heavy_move: AttackTable = moveset.heavy_charge if moveset.heavy_charge != null else moveset.heavy
			if heavy_move == null:
				return false
			_heavy_held = true
			return _begin(heavy_move)
	return false


func stamina_has(cost: int) -> bool:
	return stamina >= float(cost)


func _start_dodge(inp: CombatInput) -> bool:
	if moveset.dodge == null:
		return false
	if not stamina_has(Tuning.DODGE_COST):
		return false

	if not inp.is_wishing():
		# No direction given: GDD 4.2 lists backstep separately from dodge.
		if moveset.backstep == null:
			return false
		last_cardinal = CombatInput.Cardinal.BACK
		_begin(moveset.backstep, Tuning.BACKSTEP_COST)
		return true

	var toward := atan2(inp.wish_direction().x, inp.wish_direction().z)
	if locked:
		# Locked on, square up so the character keeps facing its target
		# (GDD 4.2). Free dodges turn the character to face where it goes.
		last_cardinal = CombatInput.cardinal_relative(yaw, toward)
		match last_cardinal:
			CombatInput.Cardinal.FRONT: yaw = toward
			CombatInput.Cardinal.BACK: yaw = toward + PI
			CombatInput.Cardinal.LEFT: yaw = toward + PI * 0.5
			CombatInput.Cardinal.RIGHT: yaw = toward - PI * 0.5
	else:
		last_cardinal = CombatInput.Cardinal.FRONT
		yaw = toward

	_begin(moveset.dodge, Tuning.DODGE_COST)
	return true


func _start_jump(inp: CombatInput) -> bool:
	if moveset == null:
		return false
	if not stamina_has(Tuning.JUMP_COST):
		return false
	spend_stamina(Tuning.JUMP_COST)
	_takeoff_y = position.y
	_peak_y = position.y
	_air_attack_used = false
	_in_air_move = false
	move = null
	tick = 0
	state = State.AIR
	guarding = false
	sprinting = false
	speed = 0.0
	velocity_y = Tuning.JUMP_VELOCITY
	velocity_horizontal = Vector3.ZERO
	if inp.is_wishing():
		var w := inp.wish_direction()
		yaw = atan2(w.x, w.z)
	return true


## Commit to `m`, paying stamina up front. GDD 5.2's costs are per-attack, and
## charging them at the start is what stops a player beginning a move they
## cannot afford the rest of.
func _begin(m: AttackTable, cost_override := -1) -> bool:
	if m == null:
		return false
	var cost := cost_override if cost_override >= 0 else m.stamina_cost
	if not stamina_has(cost):
		return false
	spend_stamina(cost)
	move = m
	tick = 0
	_clear_swing()
	_advance_applied = 0.0
	_in_air_move = false
	state = State.ACTION
	guarding = false
	sprinting = false
	speed = 0.0
	posture_relief_per_sec = 0.0
	return true


## Begin a reaction to being hit. Kept separate from `_begin` so that being hit
## is never mistaken for choosing to attack, and so reaction moves are exempt
## from the stamina gate.
func begin_reaction(reaction: AttackTable) -> void:
	if reaction == null:
		return
	move = reaction
	tick = 0
	_clear_swing()
	_advance_applied = 0.0
	state = State.ACTION
	guarding = false
	sprinting = false
	speed = 0.0
	_buffered = Req.NONE


# --- Air ----------------------------------------------------------------------

func _enter_air(jumped: bool, carry: Vector3) -> void:
	state = State.AIR
	move = null
	tick = 0
	_peak_y = position.y
	_air_attack_used = false
	guarding = false
	sprinting = false
	if jumped:
		velocity_y = Tuning.JUMP_VELOCITY
		velocity_horizontal = Vector3.ZERO
	else:
		velocity_y = 0.0
		velocity_horizontal = carry


func _step_air(inp: CombatInput, level: SimLevel) -> void:
	# GDD 5.3 makes the jump attack a bridge between movement and melee. It may
	# only come out once per jump, and only from an actual jump, never from
	# walking off a ledge.
	if (
		not _air_attack_used
		and _buffered == Req.LIGHT
		and moveset != null
		and moveset.jump_attack != null
		and stamina_has(moveset.jump_attack.stamina_cost)
	):
		_buffered = Req.NONE
		_air_attack_used = true
		if _begin(moveset.jump_attack):
			# The swing commits, but the fall does not stop: `_in_air_move` keeps
			# gravity running for the duration so the character still comes down.
			_in_air_move = true

	velocity_y = maxf(velocity_y - Tuning.GRAVITY_PER_SEC * Tuning.DT, -Tuning.TERMINAL_VELOCITY)
	position.y += velocity_y * Tuning.DT
	_peak_y = maxf(_peak_y, position.y)

	position = level.slide(position, velocity_horizontal * Tuning.DT)

	var ground := level.height(position.x, position.z)
	if position.y <= ground:
		position.y = ground
		_land()
		return

	# Facing still follows the stick while airborne, so an air attack goes the
	# way the player is pointing rather than the way they took off.
	if inp.is_wishing():
		var w := inp.wish_direction()
		yaw = SimMath.turn_towards(yaw, atan2(w.x, w.z), Tuning.TURN_FREE * Tuning.DEG_TO_RAD * Tuning.DT)


func _land() -> void:
	var fall := _peak_y - position.y
	velocity_y = 0.0
	velocity_horizontal = Vector3.ZERO
	move = null
	tick = 0
	_in_air_move = false
	state = State.GROUND

	if fall >= Tuning.FALL_DEATH:
		kill()
		return

	if fall > Tuning.FALL_DAMAGE_START:
		var over := fall - Tuning.FALL_DAMAGE_START
		hp -= max_hp * (Tuning.FALL_DAMAGE_PER_METRE * over)
		if hp <= 0.0:
			hp = 0.0
			dead = true
			state = State.DEAD
			return

	# A landing always resolves into its own move when one is authored, so that
	# a player who lands from a jump has a defined recovery rather than an
	# instant return to free movement.
	if moveset != null and moveset.land_light != null:
		_begin(moveset.land_light)


## Put the player into the dead state.
##
## Deliberately does not early-return when `dead` is already set. `receive_hit`
## marks a combatant dead as part of resolving damage, so by the time a caller
## reaches this the flag is *already* true - and an `if dead: return` guard here
## would silently skip the state change, leaving a corpse that keeps walking and
## still accepts input.
func kill() -> void:
	hp = 0.0
	dead = true
	state = State.DEAD
	move = null
	tick = 0
	_in_air_move = false
	sprinting = false
	guarding = false
	_buffered = Req.NONE


# --- Blade --------------------------------------------------------------------

## Cache the blade pose at both ends of the tick so the world can sweep it
## against targets. Recomputed every tick from authored data rather than read
## off an animation, because the sweep is authored data (see AttackTable).
func _update_blade() -> void:
	_blade_prev = _blade_now if _blade_now.size() >= 2 else []

	if move == null or not move.is_active(tick):
		_blade_now = []
		return

	var pose := move.blade_at(tick)
	# blade_at returns [hilt, tip]. A shorter result means the move has no usable
	# sweep authored, which is a data error, not a runtime condition: see
	# AttackTable.validate().
	if pose.size() < 2:
		_blade_now = []
		return
	_blade_now = HitGeometry.to_world(pose, position, facing())


## Remembered so a cancel resolving several ticks after the press still knows
## which way the player was pointing when they asked.
func note_input(inp: CombatInput) -> void:
	_last_input = inp
	_heavy_held = inp.heavy.held