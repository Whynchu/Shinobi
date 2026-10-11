## An enemy's behaviour, layered over the same combat data the player uses.
##
## Deliberately *not* a subclass of the player's machine. GDD 9.4 describes
## enemies as having a distinctive silhouette, two to five readable actions,
## approach and retreat behaviour, a response to guard pressure, a clear stagger
## rule and a contextual weakness - authored decision trees or utility scoring
## with enforced turn-taking. None of that is the player's input buffer and
## seven cancel windows, and forcing it into the same machine would give every
## enemy a phantom combo system (see Docs/ARCHITECTURE.md, decision 1).
##
## What it does share with the player is `AttackTable`: the same timing data,
## the same sweep geometry, the same hit resolution. An enemy's overhead slam
## and the player's first light are described by the same kind of record, which
## is what lets one balancing sheet cover both (GDD 16).
class_name EnemyMachine
extends Combatant

enum State {
	IDLE,        ## out of contact, waiting
	APPROACH,    ## closing to attack range
	RETREAT,     ## backing off, usually after being blocked
	WINDUP,      ## the tell. GDD 5.4: this is what makes the attack fair.
	ACTIVE,      ## the strike itself
	RECOVER,     ## the punishable window
	STAGGER,     ## posture broken or hit hard; cannot act
	DEAD,
}

## How an enemy picks what to do next. A full utility scorer is the target for
## Gate C; this is the authored subset that Gate A needs.
@export var aggro_range := 6.0
## Distance the enemy tries to hold while approaching.
@export var preferred_range := 1.8
@export var move_speed := 3.2
@export var turn_rate := 540.0

## Ticks to wait between decisions. Without a floor, an enemy re-decides every
## tick and jitters on the spot instead of committing.
@export var decision_interval := 12

## This enemy may only start a new attack when the group's budget allows it.
## GDD 9.4: "swarms may threaten from different positions, but lethal offscreen
## overlap needs limits". The world owns the budget; this is the request.
@export var attack_priority := 0

var state: State = State.IDLE
var state_ticks := 0
var decision_cooldown := 0

var moveset: Moveset = null

## Attacks this enemy knows, in the order it prefers to use them. Keeping the
## order authored rather than random is what makes an encounter learnable,
## which GDD 9.3 requires of the Moon Shogun specifically and applies
## everywhere else by the same logic.
var repertoire: Array[AttackTable] = []

var _move: AttackTable = null
var _tick := 0
var _advance_applied := 0.0
var _blade_prev: Array = []
var _blade_now: Array = []

## Set by the world each tick: how many enemies are currently committed to an
## attack. Enemies respect it so a group pressures rather than dogpiles.
var group_attackers := 0

## Whether this enemy currently holds an attack slot.
var is_attacker := false


## Whether the current swing has already connected. An active window spans
## several ticks and the blade stays in contact across them; without this flag a
## single swing would register a hit on every tick it is live.
var swing_hit := false

func _init(p_position := Vector3.ZERO, p_yaw := 0.0, p_moveset: Moveset = null) -> void:
	super(p_position, p_yaw)
	moveset = p_moveset if p_moveset != null else Moveset.new()


func hp_ratio() -> float:
	return hp_fraction()


## Distance to the player on the ground plane. Aggro and spacing are measured
## horizontally; vertical offset is handled by the attack's own active window.
func distance_to(target: Vector3) -> float:
	return SimMath.flat_distance(position, target)


func invulnerable() -> bool:
	return _move != null and _move.is_invulnerable(_tick)


func active_move() -> AttackTable:
	return _move


## Ticks elapsed in the current move. The world reads this to decide whether an
## attack's active window is open, rather than reaching into the machine.
func move_tick() -> int:
	return _tick


## Is this enemy presenting a tell right now? GDD 5.4: "Enemy attacks must
## communicate origin, direction, timing and counterplay through windup pose,
## sound and slash arc. Color may reinforce a tell but must never be the sole
## cue." So the windup must be a real, observable period, not a formality.
func telegraphing() -> bool:
	return state == State.WINDUP


func blade_sweep() -> Array:
	if _blade_prev.size() < 2 or _blade_now.size() < 2:
		return []
	return [_blade_prev, _blade_now]


func blade_radius() -> float:
	return _move.blade_radius if _move != null else 0.0


## Advance one tick. `target_position` is the player.
func step(level: SimLevel, target_position: Vector3, dt_ticks: int) -> void:
	if dead:
		return

	if hit_stop > 0:
		hit_stop -= 1
		_update_blade()
		return

	tick_resources()
	decision_cooldown = maxi(0, decision_cooldown - 1)
	state_ticks += 1

	var to_target := SimMath.flat_direction(position, target_position)
	var dist := SimMath.flat_distance(position, target_position)
	if dist > 1e-4:
		yaw = SimMath.turn_towards(yaw, SimMath.yaw_of(to_target), turn_rate * Tuning.DEG_TO_RAD * Tuning.DT)

	match state:
		State.IDLE:
			if dist <= aggro_range:
				_set_state(State.APPROACH)
		State.APPROACH:
			_approach(level, to_target, dist)
		State.RETREAT:
			position = level.slide(position, -to_target * move_speed * Tuning.DT)
			if dist > preferred_range * 1.6 or state_ticks > 45:
				_set_state(State.APPROACH)
		State.WINDUP:
			_tick += 1
			if _move != null and _tick >= _move.active_from:
				_set_state(State.ACTIVE)
		State.ACTIVE:
			_tick += 1
			_apply_advance(level)
			if _move != null and _tick >= _move.active_to:
				_set_state(State.RECOVER)
		State.RECOVER:
			_tick += 1
			if _move == null or _tick >= _move.total_ticks:
				_finish_move()
				_set_state(State.APPROACH)
		State.STAGGER:
			# GDD 5.3: immunity rules prevent stun-lock loops, so a stagger runs
			# for a bounded time and the enemy always comes back out of it.
			if _move == null or _tick >= _move.total_ticks:
				_finish_move()
				_set_state(State.APPROACH)
		State.DEAD:
			pass

	_update_blade()


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_ticks = 0


func _approach(level: SimLevel, to_target: Vector3, dist: float) -> void:
	# GDD 9.4: enemies need approach and retreat behaviour, not a beeline. Back
	# off once the posture meter is nearly full, so a pressured enemy backs off
	# rather than trading into a finisher.
	if posture_fraction() > 0.7 and dist < preferred_range:
		_set_state(State.RETREAT)
		return

	if decision_cooldown <= 0 and dist <= aggro_range and group_attackers < 1:
		decision_cooldown = decision_interval
		if _try_begin_attack(dist):
			return

	if dist > preferred_range * 0.8:
		position = level.slide(position, to_target * move_speed * Tuning.DT)
		var ground := level.height(position.x, position.z)
		if position.y - ground <= Tuning.STEP_HEIGHT:
			position.y = ground


func _try_begin_attack(dist: float) -> bool:
	for move in repertoire:
		if move == null:
			continue
		# Only start an attack whose reach actually reaches the player. Starting
		# a swing that cannot connect is how an enemy ends up looking broken.
		if move.forward_reach() + Tuning.BODY_RADIUS < dist:
			continue
		_move = move
		_tick = 0
		_advance_applied = 0.0
		swing_hit = false
		is_attacker = true
		_set_state(State.WINDUP)
		return true
	return false


func _apply_advance(level: SimLevel) -> void:
	if _move == null:
		return
	var want := _move.advance_at(_tick)
	var delta := want - _advance_applied
	if delta != 0.0:
		position = level.slide(position, facing() * delta)
	_advance_applied = want


func _finish_move() -> void:
	_move = null
	_tick = 0
	_advance_applied = 0.0
	swing_hit = false
	is_attacker = false
	_blade_now = []
	_blade_prev = []


## React to being hit. Chooses the reaction from the hit's strength and the
## side it came from, per GDD 5.3.
func take_hit(from: Vector3, level_hint: Tuning.HurtLevel) -> AttackTable:
	var reaction: AttackTable = null
	if moveset != null:
		reaction = moveset.reaction_for(level_hint)
	if reaction != null:
		_move = reaction
		_tick = 0
		_advance_applied = 0.0
		is_attacker = false
		_set_state(State.STAGGER)
	return reaction


## A posture break (GDD 5.3). The enemy is opened up rather than stunned
## outright, so a big boss can be broken without its phase being trivialised.
func on_posture_break() -> void:
	_finish_move()
	_set_state(State.STAGGER)


## Put the enemy down. Not guarded on `dead`: `receive_hit` already set the
## flag while resolving damage, so an early return here would skip the state
## change and leave a corpse still cycling attacks.
func kill() -> void:
	hp = 0.0
	dead = true
	_finish_move()
	_set_state(State.DEAD)


func _update_blade() -> void:
	_blade_prev = _blade_now if _blade_now.size() >= 2 else []
	if _move == null or not _move.is_active(_tick):
		_blade_now = []
		return
	var pose := _move.blade_at(_tick)
	if pose.size() < 2:
		_blade_now = []
		return
	_blade_now = HitGeometry.to_world(pose, position, facing())