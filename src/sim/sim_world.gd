## The simulation world: one fixed 60 Hz tick of everything.
##
## This is the only place where a hit is actually resolved. The machines decide
## what they intend and expose the blade's swept path; this file decides whether
## the blade reached anything and applies the consequences.
##
## It holds no engine type beyond Vector3 and no node references, so the same
## `step` runs in the game, in a test, and in a headless balance run that plays
## thousands of matches with nothing drawn (GDD 18).
class_name SimWorld
extends RefCounted

var level: SimLevel
var player: PlayerMachine
var enemies: Array[EnemyMachine] = []

## Thrown ninja tools in flight (GDD 6.1).
var projectiles: Array[Projectile] = []

## Where the player starts a run, and where a restart puts them back.
var spawn := Vector3.ZERO

## Lock-on state (GDD 4.3). The simulation only needs to know whether a target
## is held and where it is; cycling is the presentation layer's business.
var locked := false
var lock_target: EnemyMachine = null

## How many enemies may be mid-attack at once. GDD 9.4 requires turn-taking
## pressure rather than dogpiling. One is the safe default; a group director can
## raise it for a scripted encounter.
var attack_slots := 1

## Structured combat events, oldest first. GDD 18 requires every result to be
## linkable to a seed and a loadout, so these are records rather than log
## strings: the HUD can format them and telemetry can aggregate them without
## parsing English.
var events: Array[Dictionary] = []

## Total ticks elapsed. Everything time-based in a run derives from this.
var ticks := 0


func _init(p_level: SimLevel = null, p_moveset: Moveset = null) -> void:
	level = p_level if p_level != null else SimLevel.flat()
	player = PlayerMachine.new(spawn, 0.0, p_moveset)


func add_enemy(enemy: EnemyMachine) -> EnemyMachine:
	enemies.append(enemy)
	return enemy


## Reset the player to a run-ready state and clear everything transient.
##
## GDD 3.4: on death, build, currency and tool charges vanish, and the player
## returns to a *fast* dojo restart with no mandatory cutscene. So this is the
## whole of the failure loop - there is no separate death screen state to unwind.
func restart() -> void:
	player.reset_for_run(spawn)
	projectiles.clear()
	events.clear()
	ticks = 0
	release_lock()


## The last thing that killed the player, for the death readout GDD 3.4 asks
## for ("Death immediately reveals cause"). Null while alive.
var last_damage_source := ""


func _read_damage_source(move: AttackTable) -> void:
	last_damage_source = String(move.id)


func has_valid_lock() -> bool:
	return locked and lock_target != null and not lock_target.dead


func lock_position() -> Vector3:
	return lock_target.position if lock_target != null else Vector3.ZERO


func acquire_lock(target: EnemyMachine) -> bool:
	if target == null or target.dead:
		return false
	if SimMath.flat_distance(player.position, target.position) > Tuning.LOCK_ON_RANGE:
		return false
	lock_target = target
	locked = true
	return true


func release_lock() -> void:
	locked = false
	lock_target = null


# --- The tick -----------------------------------------------------------------

## Advance the entire world by exactly one tick.
func step(inp: CombatInput) -> void:
	ticks += 1

	_update_lock()

	# Consumables are handled before the state machine, so a flask can rescue
	# the player out of a stagger and a tool can be thrown mid-recovery. GDD 5.2
	# makes the flask a resource for multi-room routes, so it cannot be
	# something the player has to be in a neutral state to use.
	if inp.use_flask:
		player.drink_flask()
	if inp.tool.pressed:
		var thrown := player.throw_tool(inp.cam_yaw)
		if thrown != null:
			projectiles.append(thrown)

	player.in_contact = _player_in_contact()
	player.step(inp, level, has_valid_lock(), lock_position())

	_resolve_player_attacks()

	for e in enemies:
		if not e.dead:
			e.step(level, player.position, 1)

	_resolve_enemy_attacks()
	_step_projectiles()
	_separate_bodies()


func _step_projectiles() -> void:
	var survivors: Array[Projectile] = []
	for p in projectiles:
		var from := p.position
		p.step()
		if p.spent:
			continue
		# A thrown tool uses the same swept-segment test as a blade: at 22 m/s
		# it covers over a third of a metre per tick, so a single point check
		# would let it pass through a thin target.
		if p.from_player:
			for e in enemies:
				if e.dead or e.invulnerable():
					continue
				var body := body_capsule(e.position)
				if HitGeometry.capsules_touch(
					from, p.position, p.radius, body[0], body[1], Tuning.BODY_RADIUS
				):
					p.hit_combatant = e
					e.receive_hit(_tool_move(), p.position, false, false)
					p.spent = true
					_emit("tool_hit_enemy", {
						"enemy": e.get_instance_id(), "damage": p.damage, "enemy_hp": e.hp,
					})
					break
		else:
			var body := body_capsule(player.position)
			if not player.dead and HitGeometry.capsules_touch(
				from, p.position, p.radius, body[0], body[1], Tuning.BODY_RADIUS
			):
				p.hit_combatant = player
				player.receive_hit(_tool_move(), p.position, false, false)
				p.spent = true
		if not p.spent:
			survivors.append(p)
	projectiles = survivors


## Shuriken damage is expressed through an AttackTable so enemies, reactions,
## hit-stop and telemetry all work exactly as they do for a swing. Built once
## and reused; it is immutable in practice.
var _tool_move_cache: AttackTable = null


func _tool_move() -> AttackTable:
	if _tool_move_cache == null:
		var m := AttackTable.new()
		m.id = &"shuriken"
		m.family = AttackTable.Family.LIGHT
		m.total_ticks = 1
		m.active_from = 0
		m.active_to = 1
		m.stamina_cost = 0
		m.damage = Tuning.TOOL_DAMAGE
		m.posture_damage = Tuning.TOOL_POSTURE_DAMAGE
		m.hit_stop_ticks = 2
		m.provenance = AttackTable.Provenance.ESTIMATE
		_tool_move_cache = m
	return _tool_move_cache


func _update_lock() -> void:
	if lock_target == null:
		return
	# GDD 4.3: losing a target should not leave the camera pointed at a corpse.
	if lock_target.dead:
		release_lock()
		return
	if locked and SimMath.flat_distance(player.position, lock_target.position) > Tuning.LOCK_BREAK_RANGE:
		release_lock()


## Does any enemy count as in contact? Only then does sprinting cost stamina.
func _player_in_contact() -> bool:
	for e in enemies:
		if not e.dead and SimMath.flat_distance(player.position, e.position) <= Tuning.AGGRO_CONTACT_RANGE:
			return true
	return false


# --- Hit resolution -----------------------------------------------------------

## A combatant's body as a vertical segment, inflated by the body radius.
##
## Exposed so the debug view can draw exactly what the test uses. A hitbox that
## disagrees with what is on screen is GDD 16's first gate failure,
## "animations/hitboxes disagree".
static func body_capsule(at: Vector3) -> Array:
	var r := Tuning.BODY_RADIUS
	return [at + Vector3.UP * r, at + Vector3.UP * (Tuning.CHARACTER_HEIGHT - r)]


func _resolve_player_attacks() -> void:
	var move := player.move
	if move == null or player.swing_hit or not move.is_active(player.tick):
		return
	var sweep := player.blade_sweep()
	if sweep.size() < 2:
		return

	for e in enemies:
		if e.dead or e.invulnerable():
			continue
		var body := body_capsule(e.position)
		if HitGeometry.sweep_touches(
			sweep[0], sweep[1], body[0], body[1], Tuning.BODY_RADIUS,
			move.blade_radius, Tuning.SWEEP_SUBSTEPS
		):
			# One swing connects once. The blade stays in contact for the rest of
			# the active window, and without this every one of those ticks would
			# register as another hit.
			player.swing_hit = true
			_register_player_hit(e, move)
			return  # one hit per swing


func _resolve_enemy_attacks() -> void:
	var body := body_capsule(player.position)
	for e in enemies:
		if e.dead or e.swing_hit:
			continue
		var move := e.active_move()
		if move == null or not move.is_active(e.move_tick()):
			continue
		var sweep := e.blade_sweep()
		if sweep.size() < 2:
			continue
		if HitGeometry.sweep_touches(
			sweep[0], sweep[1], body[0], body[1], Tuning.BODY_RADIUS,
			move.blade_radius, Tuning.SWEEP_SUBSTEPS
		):
			e.swing_hit = true
			_register_enemy_hit(e, move)


func _register_player_hit(enemy: EnemyMachine, move: AttackTable) -> void:
	# Enemies do not guard; they have reactions instead.
	var outcome := enemy.receive_hit(move, player.position, false, false)

	# Hit-stop freezes both sides (GDD 5.1: hit-stop makes contact legible).
	player.hit_stop = move.hit_stop_ticks
	enemy.hit_stop = move.hit_stop_ticks

	if outcome == Combatant.Outcome.KILLED:
		enemy.kill()
		if lock_target == enemy:
			release_lock()
		_emit("enemy_defeated", {"enemy": enemy.get_instance_id(), "move": String(move.id)})
		return

	var level_hint := _reaction_level_for(move)
	enemy.take_hit(player.position, level_hint)

	var broke := enemy.posture_broken
	if broke:
		enemy.on_posture_break()

	_emit("player_hit_enemy", {
		"enemy": enemy.get_instance_id(),
		"move": String(move.id),
		"damage": move.damage,
		"posture": move.posture_damage,
		"posture_broken": broke,
		"enemy_hp": enemy.hp,
	})


func _register_enemy_hit(enemy: EnemyMachine, move: AttackTable) -> void:
	if player.dead:
		return

	# Defence resolves before damage, and in a fixed order. GDD 5.1 makes the
	# legible answer to each attack part of the contract, so the order here is
	# the order the player is taught: evade, then jump, then guard, then eat it.
	if player.invulnerable():
		var dodging := player.move != null and player.move.has_invulnerability()
		var evaded := Combatant.evaluate_perfect_dodge(move, player.tick, dodging, true)
		if evaded == Combatant.Outcome.PERFECT_DODGE:
			# GDD 5.3: a perfect dodge is a distinct, signposted outcome, because
			# scrolls key off it. It also freezes the swing briefly so the player
			# sees that something happened.
			player.hit_stop = maxf(player.hit_stop, move.hit_stop_ticks)
			_emit("perfect_dodge", {"enemy": enemy.get_instance_id(), "move": String(move.id)})
		else:
			_emit("dodged", {"enemy": enemy.get_instance_id(), "move": String(move.id)})
		return

	if move.is_low_sweep and player.airborne() and player.clearance(level) > Tuning.JUMP_CLEARANCE:
		_emit("jumped_sweep", {"enemy": enemy.get_instance_id(), "move": String(move.id)})
		return

	# GDD 5.3: pressing guard inside the window converts the hit into posture
	# damage. The counter that follows is conditional, not automatic.
	var timed := player.guarding and player.timed_guard_ticks > 0
	var outcome := player.receive_hit(move, enemy.position, player.guarding, timed)

	player.hit_stop = move.hit_stop_ticks
	enemy.hit_stop = move.hit_stop_ticks

	if outcome == Combatant.Outcome.KILLED:
		player.kill()
		_read_damage_source(move)
		_emit("player_defeated", {
			"enemy": enemy.get_instance_id(), "move": String(move.id),
			"cause": last_damage_source,
		})
		return

	if outcome == Combatant.Outcome.HIT and player.moveset != null:
		player.begin_reaction(player.moveset.reaction_for(_reaction_level_for(move)))

	_emit("enemy_hit_player", {
		"enemy": enemy.get_instance_id(),
		"move": String(move.id),
		"outcome": Combatant.Outcome.keys()[outcome],
		"player_hp": player.hp,
		"player_stamina": player.stamina,
		"posture": player.posture,
	})


## Map a move's posture damage onto a reaction strength. GDD 5.3 names four:
## a small flinch, a medium stagger, a heavy stagger and a knockdown.
static func _reaction_level_for(move: AttackTable) -> Tuning.HurtLevel:
	if move.posture_damage >= 30:
		return Tuning.HurtLevel.KNOCKDOWN
	if move.posture_damage >= 22:
		return Tuning.HurtLevel.HEAVY_STAGGER
	if move.posture_damage >= 14:
		return Tuning.HurtLevel.STAGGER
	return Tuning.HurtLevel.FLINCH


# --- Bodies -------------------------------------------------------------------

## Characters are solid. You cannot roll through an enemy, and two enemies
## cannot occupy one spot. Without this a dodge would pass through a target and
## then the sword would connect anyway, which reads as the game lying about
## whether the dodge worked.
func _separate_bodies() -> void:
	for e in enemies:
		if not e.dead:
			_separate_from_enemy(e)
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			if not enemies[i].dead and not enemies[j].dead:
				_separate_enemies(enemies[i], enemies[j])


func _separate_from_enemy(e: EnemyMachine) -> void:
	var away := Vector3(player.position.x - e.position.x, 0.0, player.position.z - e.position.z)
	var push := _push_apart(away)
	if push == Vector3.ZERO:
		return
	# Move both parties apart by the same amount, so neither is shoved through
	# the other and neither is left overlapping after the correction.
	player.position = level.slide(player.position, push)
	e.position = level.slide(e.position, -push)


func _separate_enemies(a: EnemyMachine, b: EnemyMachine) -> void:
	var away := Vector3(a.position.x - b.position.x, 0.0, a.position.z - b.position.z)
	var push := _push_apart(away)
	if push == Vector3.ZERO:
		return
	a.position = level.slide(a.position, push)
	b.position = level.slide(b.position, -push)


## How far along `away` two bodies must shift to reach the minimum separation.
## Returns zero when they are already far enough apart.
func _push_apart(away: Vector3) -> Vector3:
	var min_sep := Tuning.BODY_RADIUS * 2.0
	var dist := away.length()
	if dist >= min_sep:
		return Vector3.ZERO
	if dist < 1e-4:
		# Exactly coincident: pick a consistent direction rather than dividing
		# by zero, so the pair separates instead of sticking together.
		return Vector3(0.0, 0.0, min_sep)
	return away / dist * (min_sep - dist)


# --- Events -------------------------------------------------------------------

func _emit(kind: String, data: Dictionary) -> void:
	data["kind"] = kind
	data["tick"] = ticks
	events.append(data)
	while events.size() > Tuning.MAX_EVENTS:
		events.remove_at(0)


## Events since the last drain, then cleared. The HUD drains this so that
## pausing cannot replay a hit twice.
func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events.duplicate()
	events.clear()
	return out