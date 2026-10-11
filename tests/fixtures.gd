## Test fixtures: a katana moveset built to the GDD's published figures.
##
## These are not the shipping values. They are the GDD 5.2 numbers written down
## as data so the tests can assert on exact tick counts, which is the whole
## point of choosing a 60 Hz integer frame base: "light attack startup 11-17
## frames" becomes "this move's active window opens on tick 13", and that is
## checkable rather than a matter of taste.
##
## Two conventions worth knowing when editing:
##
##   * `active_from == active_to` means *no active window*. A dodge, a landing,
##     a reaction and a charge wind-up all legitimately cannot connect, and
##     `AttackTable.validate()` only insists on a live window for offence.
##   * `cancel_from` must not open before a move's blade lands. A move that can
##     be interrupted before it connects is a real balance bug, not a style
##     choice, and the validator reports it.
class_name Fixtures
extends RefCounted


# --- Blade sweeps -------------------------------------------------------------
# Thin aliases over the presets, so a test reads as a move rather than as a
# pile of coordinates.

static func horizontal_slash(blade := 1.25) -> Array[BladePose]:
	return BladePose.horizontal_slash(blade)


static func overhead_chop(blade := 1.15) -> Array[BladePose]:
	return BladePose.overhead_chop(blade)


static func low_sweep(blade := 1.20) -> Array[BladePose]:
	return BladePose.low_sweep(blade)


# --- The katana ---------------------------------------------------------------

static func light_one() -> AttackTable:
	var m := AttackTable.new()
	m.id = &"katana_light_1"
	m.family = AttackTable.Family.LIGHT
	m.chain_index = 0
	m.total_ticks = 40
	m.active_from = 13
	m.active_to = 16
	m.cancel_from = 22
	m.input_from = 4
	m.stamina_cost = Tuning.LIGHT_COST_MIN
	m.damage = 18
	m.posture_damage = 14
	m.hit_stop_ticks = 4
	m.guard_damage = 20
	m.timed_guard_posture = 16
	m.advance_m = 0.15
	m.sweep = horizontal_slash()
	m.provenance = AttackTable.Provenance.ESTIMATE
	return m


static func light_two() -> AttackTable:
	var m := light_one()
	m.id = &"katana_light_2"
	m.chain_index = 1
	m.active_from = 12
	m.active_to = 15
	m.cancel_from = 21
	m.stamina_cost = Tuning.LIGHT_COST_MIN + 1
	m.damage = 20
	m.advance_m = 0.18
	return m


static func light_three() -> AttackTable:
	var m := light_one()
	m.id = &"katana_light_3"
	m.chain_index = 2
	m.active_from = 17
	m.active_to = 23
	m.cancel_from = 33
	m.total_ticks = 52
	m.stamina_cost = Tuning.LIGHT_COST_MAX
	m.damage = 26
	m.posture_damage = 18
	m.advance_m = 0.30
	m.chain_next = null
	return m


static func heavy() -> AttackTable:
	var m := AttackTable.new()
	m.id = &"katana_heavy"
	m.family = AttackTable.Family.HEAVY
	m.total_ticks = 62
	m.active_from = 22
	m.active_to = 27
	m.cancel_from = 44
	m.input_from = 4
	m.stamina_cost = Tuning.HEAVY_COST
	m.damage = 38
	m.posture_damage = 30
	m.hit_stop_ticks = 7
	m.guard_damage = 36
	m.timed_guard_posture = 24
	m.advance_m = 0.45
	m.sweep = overhead_chop()
	return m


static func charged_heavy() -> AttackTable:
	var m := heavy()
	m.id = &"katana_charged_heavy"
	m.total_ticks = 74
	m.active_from = 28
	m.active_to = 34
	m.cancel_from = 56
	m.stamina_cost = Tuning.CHARGED_HEAVY_COST
	m.damage = 62
	m.posture_damage = 48
	m.advance_m = 0.7
	return m


## The wind-up that plays while the heavy button is held. It has no active
## window: it is purely a commitment, and it resolves one way or the other
## depending on whether the player lets go before CHARGE_TICKS.
static func heavy_charge() -> AttackTable:
	var m := AttackTable.new()
	m.id = &"katana_charge"
	m.family = AttackTable.Family.CHARGE
	m.total_ticks = 50
	m.active_from = 0
	m.active_to = 0
	m.cancel_from = 8
	m.input_from = 2
	m.stamina_cost = 0
	m.advance_m = 0.0
	return m


## GDD 5.2: 12 frames of invulnerability, which on the 60 Hz base is ticks 2
## through 12. The window opens two ticks in so a roll has a visible wind-up
## before it becomes invulnerable, which is what makes it readable rather than a
## free pass.
static func dodge() -> AttackTable:
	var m := AttackTable.new()
	m.id = &"katana_dodge"
	m.family = AttackTable.Family.DODGE
	m.total_ticks = 34
	m.active_from = 0  # no active window
	m.active_to = 0
	m.cancel_from = 20
	m.input_from = 10
	m.iframes_from = 2
	m.iframes_to = 12
	m.stamina_cost = 0  # charged separately as Tuning.DODGE_COST
	m.advance_m = 2.6
	return m


static func backstep() -> AttackTable:
	var m := dodge()
	m.id = &"katana_backstep"
	m.advance_m = -1.8
	return m


static func jump_attack() -> AttackTable:
	var m := AttackTable.new()
	m.id = &"katana_jump_attack"
	m.family = AttackTable.Family.LIGHT
	m.total_ticks = 36
	m.active_from = 14
	m.active_to = 20
	m.cancel_from = 26
	m.input_from = 6
	m.stamina_cost = 16
	m.damage = 24
	m.posture_damage = 20
	m.advance_m = 0.1
	m.sweep = BladePose.rising_slash(1.15)
	return m


static func land_light() -> AttackTable:
	var m := AttackTable.new()
	m.id = &"katana_land"
	m.family = AttackTable.Family.UTILITY
	m.total_ticks = 14
	m.active_from = 0  # no active window
	m.active_to = 0
	m.cancel_from = 8
	m.stamina_cost = 0
	return m


## A reaction, indexed by strength. GDD 5.3: flinch, stagger, heavy stagger,
## knockdown.
static func reaction(level: Tuning.HurtLevel) -> AttackTable:
	var m := AttackTable.new()
	m.id = StringName("reaction_%s" % Tuning.hurt_level_name(level))
	m.family = AttackTable.Family.REACTION
	m.hurt_level = level
	match level:
		Tuning.HurtLevel.FLINCH:
			m.total_ticks = 16
		Tuning.HurtLevel.STAGGER:
			m.total_ticks = 34
		Tuning.HurtLevel.HEAVY_STAGGER:
			m.total_ticks = 58
		Tuning.HurtLevel.KNOCKDOWN:
			m.total_ticks = 76
			m.getup_iframes = 24
		_:
			m.total_ticks = 16
	m.active_from = 0  # no active window
	m.active_to = 0
	# A reaction cannot be interrupted. GDD 5.3 wants a stagger to actually last
	# so the player has a real window to punish; cancelling out of one turns
	# being hit into noise.
	m.input_from = 0
	m.cancel_from = m.total_ticks
	m.stamina_cost = 0
	return m


static func _reactions() -> Dictionary:
	return {
		Tuning.HurtLevel.FLINCH: reaction(Tuning.HurtLevel.FLINCH),
		Tuning.HurtLevel.STAGGER: reaction(Tuning.HurtLevel.STAGGER),
		Tuning.HurtLevel.HEAVY_STAGGER: reaction(Tuning.HurtLevel.HEAVY_STAGGER),
		Tuning.HurtLevel.KNOCKDOWN: reaction(Tuning.HurtLevel.KNOCKDOWN),
	}


## The full GDD 5.2 katana: three-hit light chain, heavy, charged heavy, dodge,
## backstep, jump attack, landing, and all four reactions.
static func katana() -> Moveset:
	var l1 := light_one()
	var l2 := light_two()
	var l3 := light_three()
	l1.chain_next = l2
	l2.chain_next = l3

	var s := Moveset.new()
	s.light_chain = [l1, l2, l3]
	s.heavy = heavy()
	s.charged_heavy = charged_heavy()
	s.heavy_charge = heavy_charge()
	s.dodge = dodge()
	s.backstep = backstep()
	s.jump_attack = jump_attack()
	s.land_light = land_light()
	s.hurt = _reactions()
	return s


# --- Enemies ------------------------------------------------------------------

## A single attacker with one telegraphed overhead chop. Enough to exercise hit
## registration from the enemy side.
static func dummy_enemy() -> Moveset:
	var chop := AttackTable.new()
	chop.id = &"dummy_overhead"
	chop.family = AttackTable.Family.HEAVY
	chop.total_ticks = 70
	chop.active_from = 26
	chop.active_to = 32
	chop.cancel_from = 46
	chop.stamina_cost = 0
	chop.damage = 20
	chop.posture_damage = 18
	chop.hit_stop_ticks = 5
	chop.guard_damage = 24
	chop.timed_guard_posture = 20
	chop.sweep = overhead_chop(1.3)

	var sweep := AttackTable.new()
	sweep.id = &"dummy_sweep"
	sweep.family = AttackTable.Family.HEAVY
	sweep.total_ticks = 70
	sweep.active_from = 26
	sweep.active_to = 32
	sweep.cancel_from = 46
	sweep.is_low_sweep = true
	sweep.stamina_cost = 0
	sweep.damage = 16
	sweep.posture_damage = 12
	sweep.sweep = low_sweep()

	var s := Moveset.new()
	s.heavy = chop
	s.hurt = _reactions()
	return s


## An enemy wired to attack `move` whenever it is in range.
static func enemy_with(move: AttackTable, at := Vector3(0.0, 0.0, 1.5)) -> EnemyMachine:
	var e := EnemyMachine.new(at, PI, dummy_enemy())
	e.moveset = dummy_enemy()
	e.repertoire = [move]
	e.aggro_range = 40.0
	e.preferred_range = 1.5
	return e


## An enemy that stands exactly where it is put and never attacks.
##
## Range tests need a target that holds still: an ordinary enemy walks in and
## closes the distance on its own, which is correct behaviour but makes "does
## the blade reach this far" impossible to measure.
static func stationary_enemy(at := Vector3(0.0, 0.0, 1.5), hp := 120.0) -> EnemyMachine:
	var e := EnemyMachine.new(at, 0.0, dummy_enemy())
	e.moveset = dummy_enemy()
	e.repertoire = []
	e.preferred_range = 1000.0  # never closes the gap
	e.aggro_range = 0.0         # never attacks
	e.max_hp = hp
	e.hp = hp
	return e


static func slash_for_enemy() -> AttackTable:
	var m := AttackTable.new()
	m.id = &"enemy_slash"
	m.family = AttackTable.Family.HEAVY
	m.total_ticks = 60
	m.active_from = 20
	m.active_to = 26
	m.cancel_from = 40
	m.damage = 18
	m.posture_damage = 14
	m.sweep = horizontal_slash(1.4)
	return m