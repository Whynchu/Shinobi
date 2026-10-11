## Combat behaviour tests.
##
## These are the reason the simulation is a Node-free library rather than a set
## of scripts hanging off a character scene. Every one of them runs with no
## window, no renderer and no scene tree, which is what lets a balance change be
## checked in a second rather than by launching the game and swinging a sword.
##
## The assertions are mostly about *exact tick counts*, because that is what a
## 60 Hz integer frame base buys: GDD 5.2's "12 frames of dodge invulnerability"
## is testable as "ticks 2 through 12", not as a tolerance.
class_name CombatTests
extends RefCounted


# --- Helpers ------------------------------------------------------------------

## A world on flat ground with the player at the origin facing +Z, which is
## yaw 0 under the project's convention.
static func world() -> SimWorld:
	return SimWorld.new(SimLevel.flat(), Fixtures.katana())


static func run(w: SimWorld, input: CombatInput, ticks: int) -> void:
	for i in ticks:
		w.step(input)
		input.clear_edges()


## Is the player currently playing the move with this id?
##
## Moves are compared by id rather than by reference. Every call to
## `Fixtures.light_one()` builds a fresh AttackTable, so `world().player.move ==
## Fixtures.light_one()` is always false even when both describe the same move.
static func playing(p: AttackTable, expected_id: StringName) -> bool:
	return p != null and p.id == expected_id


static func press_light() -> CombatInput:
	var i := CombatInput.new()
	i.light.press()
	return i


static func held(buttons: Array) -> CombatInput:
	var i := CombatInput.new()
	for b in buttons:
		if b == &"light":
			i.light.press()
		elif b == &"heavy":
			i.heavy.press()
		elif b == &"guard":
			i.guard.press()
		elif b == &"jump":
			i.jump.press()
		elif b == &"dodge":
			i.dodge.press()
	return i


# --- Timing data --------------------------------------------------------------

static func test_timing(h: TestHarness) -> void:
	h.suite("Attack timing is exact integer ticks on the 60 Hz base")

	var l1 := Fixtures.light_one()
	# GDD 5.2: light startup 11-17, active 3-6, recovery 16-24.
	h.between(l1.active_from, 11, 17, "light startup inside the GDD 5.2 band")
	h.between(l1.active_ticks, 3, 6, "light active window inside the GDD 5.2 band")
	h.between(l1.recovery_ticks, 16, 24, "light recovery inside the GDD 5.2 band")

	# GDD 5.2 gives 12 frames of dodge invulnerability.
	var d := Fixtures.dodge()
	h.eq_int(d.iframes_to - d.iframes_from, Tuning.DODGE_IFRAMES_TO - Tuning.DODGE_IFRAMES_FROM,
		"dodge grants the GDD 5.2 twelve frames of invulnerability")
	h.eq_int(Tuning.TIMED_GUARD_WINDOW_TICKS, 6, "timed guard window is six frames")

	# The base rate itself.
	h.eq_int(Tuning.TICK_HZ, 60, "simulation runs at 60 Hz")
	h.between(Tuning.DODGE_IFRAMES_FROM, 2, Tuning.DODGE_IFRAMES_TO,
		"the dodge window is open and non-empty")

	# Converted to seconds, the authored figures mean what a designer expects.
	h.eq_float(Tuning.DT * 12.0, 0.2, "twelve frames is 0.2 s at 60 Hz")
	h.eq_float(Tuning.DT * 6.0, 0.1, "six frames is 0.1 s at 60 Hz")

	# Windows are half-open, so a move's active window is exactly its length.
	h.ok(l1.is_active(l1.active_from), "the active window opens on its first tick")
	h.ok(not l1.is_active(l1.active_to), "the active window closes on the stated tick")
	h.ok(l1.is_active(l1.active_to - 1), "the last active tick is inside the window")

	# Animation runs at half the tick rate, and the conversion is exact.
	h.eq_float(Tuning.ticks_to_anim_frames(2.0), 1.0, "two ticks is one animation frame")
	h.eq_float(Tuning.anim_frames_to_ticks(1.0), 2.0, "one animation frame is two ticks")


# --- Buffered input -----------------------------------------------------------

static func test_buffer(h: TestHarness) -> void:
	h.suite("Buffered input: one slot, newest wins, early presses dropped")

	var l1 := Fixtures.light_one()
	var l2 := Fixtures.light_two()

	# A press starts the chain.
	var w := world()
	w.step(press_light())
	h.ok(playing(w.player.move, &"katana_light_1"), "a light press starts the first light attack")
	h.eq_int(w.player.state, PlayerMachine.State.ACTION, "the player is committed")

	# A press before the input window opens is dropped outright: the move is
	# still light one and no request is waiting. This is what stops a player
	# banking five attacks during a long animation.
	var early := world()
	early.step(press_light())
	for i in maxi(1, l1.input_from - 1):
		early.step(press_light())
	h.ok(playing(early.player.move, &"katana_light_1"),
		"mashing before the input window does not queue")
	h.eq_int(early.player._buffered, PlayerMachine.Req.NONE,
		"and leaves nothing buffered behind")

	# Only the newest request survives: one slot, overwritten, never a queue.
	var over := world()
	over.step(press_light())
	over.player._buffered = PlayerMachine.Req.LIGHT
	over.player._buffered = PlayerMachine.Req.JUMP
	h.eq_int(over.player._buffered, PlayerMachine.Req.JUMP,
		"a second request overwrites the first rather than queueing behind it")

	# The cancel window, not the input window, is what advances the chain.
	var chain := world()
	chain.step(press_light())
	h.ok(playing(chain.player.move, &"katana_light_1"), "the chain opens on light one")

	# Press repeatedly *before* the cancel frame. The request is held in the
	# single slot and cannot advance the chain early.
	while playing(chain.player.move, &"katana_light_1") and chain.player.tick < l1.cancel_from - 1:
		chain.step(press_light())
	h.ok(playing(chain.player.move, &"katana_light_1"),
		"a press before the cancel frame cannot skip ahead")

	# Now press exactly at the cancel frame.
	while playing(chain.player.move, &"katana_light_1") and chain.player.tick < l1.cancel_from:
		chain.step(CombatInput.new())
	chain.step(press_light())
	chain.step(CombatInput.new())
	h.ok(playing(chain.player.move, &"katana_light_2"),
		"pressing at the cancel frame advances to light two")

	# A move flagged requires_chain cannot be opened cold from neutral.
	var gated := Fixtures.light_one()
	gated.requires_chain = true
	var gated_world := world()
	gated_world.player.moveset.light_chain = [gated]
	gated_world.step(press_light())
	h.ok(gated_world.player.move == null,
		"a chain opener that requires a chain cannot be started from neutral")


# --- Stamina ------------------------------------------------------------------

static func test_stamina(h: TestHarness) -> void:
	h.suite("Stamina is charged up front and delayed before it returns")

	var w := world()
	var l1: AttackTable = w.player.moveset.light_chain[0]
	h.eq_float(w.player.stamina, Tuning.MAX_STAMINA, "a fresh run starts full")

	w.step(press_light())
	h.eq_float(w.player.stamina, Tuning.MAX_STAMINA - l1.stamina_cost,
		"the attack costs stamina when it starts")

	# GDD 5.2: 0.65 s delay before regeneration.
	var regen_delay := Tuning.STAMINA_REGEN_DELAY_TICKS
	w.player.state = PlayerMachine.State.GROUND
	w.player.move = null
	for i in regen_delay:
		w.step(CombatInput.new())
	h.eq_float(w.player.stamina, Tuning.MAX_STAMINA - l1.stamina_cost,
		"stamina does not return during the delay")

	# Then it does.
	run(w, CombatInput.new(), 30)
	h.ok(w.player.stamina > Tuning.MAX_STAMINA - l1.stamina_cost,
		"stamina regenerates once the delay has passed")

	# GDD 5.2: five dodges' worth. The dodge commits on *release* (GDD 4.1: tap to
	# dodge, hold to sprint), so the cost lands on the release tick.
	#
	# Regen is suppressed with a long delay so these can assert exact prices.
	# Stamina returns 24/sec, which is 0.4 per tick, and asserting absolutes
	# against a moving bar would make these tests fail every time the regen rate
	# is retuned. Regeneration is covered on its own above.
	var w2 := world()
	w2.player.stamina = 60.0
	w2.player.stamina_regen_delay = 1 << 20
	var inp := CombatInput.new()
	inp.dodge.press()
	w2.step(inp)
	inp.clear_edges()
	h.ok(not playing(w2.player.move, &"katana_dodge"),
		"pressing the dodge button does not dodge yet")
	inp.dodge.release()
	w2.step(inp)
	h.ok(playing(w2.player.move, &"katana_backstep"),
		"releasing with no direction is a backstep, not a dodge (GDD 4.2)")
	h.eq_float(w2.player.stamina, 60.0 - Tuning.BACKSTEP_COST, "a backstep costs the backstep price")

	# With a direction held, the same release is a full dodge.
	var w3 := world()
	w3.player.stamina = 60.0
	w3.player.stamina_regen_delay = 1 << 20
	var inp3 := CombatInput.new()
	inp3.move = Vector2(0.0, 1.0)
	inp3.cam_yaw = 0.0
	inp3.dodge.press()
	w3.step(inp3)
	inp3.clear_edges()
	inp3.dodge.release()
	w3.step(inp3)
	h.ok(playing(w3.player.move, &"katana_dodge"), "releasing with a direction is a dodge")
	h.eq_float(w3.player.stamina, 60.0 - Tuning.DODGE_COST, "a dodge costs the dodge price")

	# GDD 5.2: about five basic dodges. With the authored cost, the bar should
	# run out at five, not six or seven.
	h.ok(Tuning.MAX_STAMINA / float(Tuning.DODGE_COST) <= 5.5,
		"the stated stamina budget buys about five dodges")

	# No stamina, no dodge.
	var w4 := world()
	w4.player.stamina = 5.0
	w4.player.stamina_regen_delay = 1 << 20
	var inp4 := CombatInput.new()
	inp4.move = Vector2(0.0, 1.0)
	inp4.dodge.press()
	w4.step(inp4)
	inp4.clear_edges()
	inp4.dodge.release()
	w4.step(inp4)
	h.ok(w4.player.move == null, "a dodge with insufficient stamina does not start")
	h.eq_float(w4.player.stamina, 5.0, "stamina is untouched by a dodge that cannot start")


# --- Dodge and invulnerability ------------------------------------------------

static func test_dodge(h: TestHarness) -> void:
	h.suite("Dodge invulnerability is a real window, not a duration")

	var d := Fixtures.dodge()
	h.ok(d.is_invulnerable(d.iframes_from), "invulnerable on the first i-frame tick")
	h.ok(d.is_invulnerable(d.iframes_to - 1), "invulnerable on the last i-frame tick")
	h.ok(not d.is_invulnerable(d.iframes_to), "not invulnerable on the tick after")
	h.ok(not d.is_invulnerable(d.iframes_from - 1), "not invulnerable before the window")

	# GDD 5.3: a perfect dodge is narrower than the full window, and scrolls key
	# off it, so the two must be distinguishable.
	var w := world()
	var inp := CombatInput.new()
	inp.dodge.press()
	w.step(inp)
	inp.clear_edges()
	inp.dodge.release()
	w.step(inp)
	w.player.tick = d.iframes_from
	h.ok(w.player.invulnerable(), "the player is invulnerable inside the dodge window")
	h.ok(w.player.perfect_dodge(), "and inside the perfect window at the start")
	w.player.tick = d.iframes_from + Tuning.PERFECT_DODGE_TICKS
	h.ok(w.player.invulnerable(), "still invulnerable just past the perfect window")
	h.ok(not w.player.perfect_dodge(), "but no longer a perfect dodge")


# --- Hit registration ---------------------------------------------------------

static func test_reach(h: TestHarness) -> void:
	h.suite("A weapon only hits when its blade reaches the target")

	# GDD 5.1: "standing outside range or beside a thrust must miss."
	var near := world()
	var close_enemy := Fixtures.stationary_enemy(Vector3(0.0, 0.0, 1.5))
	near.add_enemy(close_enemy)
	run(near, press_light(), 30)
	h.ok(close_enemy.hp < close_enemy.max_hp, "a target inside reach takes the hit")

	# The same swing at the same tick, but standing further off.
	var far := world()
	var far_enemy := Fixtures.stationary_enemy(Vector3(0.0, 0.0, 3.0))
	far.add_enemy(far_enemy)
	run(far, press_light(), 30)
	h.eq_float(far_enemy.hp, far_enemy.max_hp, "a target out of reach is not hit")

	# GDD 5.1: "beside a thrust must miss". The same swing, with the target
	# directly beside the character rather than in front.
	var side := world()
	var side_enemy := Fixtures.stationary_enemy(Vector3(1.5, 0.0, 0.0))
	side.add_enemy(side_enemy)
	run(side, press_light(), 30)
	h.eq_float(side_enemy.hp, side_enemy.max_hp,
		"a target beside the swing is not hit by a forward slash")


static func test_sweep(h: TestHarness) -> void:
	h.suite("The blade is swept across the tick, so a fast swing cannot tunnel")

	# A thin target straddling x = 0.5, and a blade that travels from x = 0.4 to
	# x = 0.6 entirely within one tick. Sampling only at the two ends of the
	# tick never gets near it; the blade passes clean over the top. Sampling
	# between the ends catches it dead centre.
	var body_a := Vector3(0.5, 1.0, 0.45)
	var body_b := Vector3(0.5, 1.0, 0.55)
	var start_pose := [Vector3(0.4, 1.0, 0.5), Vector3(0.4, 1.0, 0.5)]
	var end_pose := [Vector3(0.6, 1.0, 0.5), Vector3(0.6, 1.0, 0.5)]

	var one_sample := HitGeometry.sweep_touches(
		start_pose, end_pose, body_a, body_b, 0.01, 0.01, 1
	)
	h.ok(not one_sample,
		"one sample per tick steps straight over the target and misses")

	var swept := HitGeometry.sweep_touches(
		start_pose, end_pose, body_a, body_b, 0.01, 0.01, Tuning.SWEEP_SUBSTEPS
	)
	h.ok(swept, "sweeping between the ends of the tick catches it")

	# And the sweep is symmetric: the same crossing in the other direction hits.
	h.ok(HitGeometry.sweep_touches(
		end_pose, start_pose, body_a, body_b, 0.01, 0.01, Tuning.SWEEP_SUBSTEPS
	), "a sweep catches the crossing regardless of direction")

	# A blade that stays clear must still miss, however finely it is sampled.
	h.ok(not HitGeometry.sweep_touches(
		[Vector3(0.0, 1.0, 0.5), Vector3(0.0, 1.0, 0.5)],
		[Vector3(0.4, 1.0, 0.5), Vector3(0.4, 1.0, 0.5)],
		body_a, body_b, 0.01, 0.01, Tuning.SWEEP_SUBSTEPS
	), "a blade that stops short never registers a hit")

	# The analytic primitive itself, on the shapes the closed form gets wrong.
	h.eq_float(HitGeometry.segment_distance(
		Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)
	), 1.0, "parallel segments, offset on one axis")
	h.eq_float(HitGeometry.segment_distance(
		Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 2, 0)
	), 1.0, "a point-segment against a perpendicular segment")
	h.eq_float(HitGeometry.segment_distance(
		Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 5), Vector3(0, 0, 6)
	), 5.0, "two degenerate points")
	h.eq_float(HitGeometry.segment_distance(
		Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)
	), 1.0, "collinear, disjoint segments")


# --- Defence ------------------------------------------------------------------

static func test_guard(h: TestHarness) -> void:
	h.suite("Guard absorbs, timed guard rewards, posture punishes")

	var chop := Fixtures.heavy()

	# An unguarded hit costs health.
	var c := Combatant.new()
	c.max_hp = 100.0
	c.hp = 100.0
	var outcome := c.receive_hit(chop, Vector3.ZERO, false, false)
	h.eq_int(outcome, Combatant.Outcome.HIT, "an unguarded hit lands")
	h.ok(c.hp < 100.0, "and costs health")

	# A guard costs stamina instead.
	var g := Combatant.new()
	g.max_hp = 100.0
	g.hp = 100.0
	g.max_stamina = 100.0
	g.stamina = 100.0
	var guarded := g.receive_hit(chop, Vector3.ZERO, true, false)
	h.eq_int(guarded, Combatant.Outcome.GUARDED, "a guard absorbs the hit")
	h.eq_float(g.hp, 100.0, "a guarded hit costs no health")
	h.ok(g.stamina < 100.0, "but costs stamina")

	# GDD 5.3: a timed guard converts the hit into posture damage.
	var t := Combatant.new()
	t.max_posture = 100.0
	var timed := t.receive_hit(chop, Vector3.ZERO, true, true)
	h.eq_int(timed, Combatant.Outcome.TIMED_GUARD, "a timed guard is a distinct outcome")
	h.eq_float(t.hp, 100.0, "a timed guard costs no health")
	h.ok(t.posture > 0.0, "and contributes posture damage")
	h.ok(t.guard_counter_ticks > 0, "and offers a counter")
	h.ok(t.stamina > 0.0, "and costs far less stamina than a plain guard")


static func test_posture(h: TestHarness) -> void:
	h.suite("Posture breaks open a finisher, and cannot be re-broken immediately")

	var c := Combatant.new()
	c.max_posture = 50.0
	var heavy := Fixtures.heavy()

	var broke := false
	for i in 10:
		var did := c.add_posture(heavy.posture_damage)
		if did:
			broke = true
			break
	h.ok(broke, "enough posture damage breaks the meter")
	h.ok(c.posture_broken, "the meter reads as broken")
	h.ok(c.finisher_ticks > 0, "a finisher opening is signposted")

	# GDD 5.3: "immunity rules prevent stun-lock loops". The break cannot chain
	# straight into another break.
	var chained := c.add_posture(heavy.posture_damage)
	h.ok(not chained, "a second break is refused while the immunity runs")
	h.eq_float(c.posture, c.max_posture, "and the meter does not refill past its maximum")

	# A small hit cannot break it at all while broken.
	h.ok(not c.add_posture(1), "no posture damage lands while already broken")


static func test_low_sweep(h: TestHarness) -> void:
	h.suite("A low sweep is answered by jumping, not by dodging")

	var sweep := Fixtures.dummy_enemy().heavy
	sweep.is_low_sweep = true
	h.ok(sweep.is_low_sweep, "the sweep is flagged low")

	# Airborne and clear: the sweep passes underneath.
	var air := Combatant.new()
	h.eq_bool(Combatant.evaluate_evade(sweep, true, false, 0.9), true,
		"a character clear of the ground avoids the sweep")
	# Airborne but barely off the floor: it does not.
	h.eq_bool(Combatant.evaluate_evade(sweep, true, false, 0.1), false,
		"a character who has barely left the floor does not clear it")
	# Rolling: i-frames help, but they are a different answer.
	h.eq_bool(Combatant.evaluate_evade(sweep, false, true, 0.0), true,
		"invulnerability answers a sweep too, but it is a different answer")

	# A normal attack is not dodged by being airborne.
	var chop := Fixtures.heavy()
	h.eq_bool(Combatant.evaluate_evade(chop, true, false, 0.9), false,
		"jumping does not answer an overhead")


static func test_one_hit_per_swing(h: TestHarness) -> void:
	h.suite("A swing connects once, not once per tick of its active window")

	# The blade stays inside the target for the whole active window, so without a
	# per-swing guard a six-tick attack deals six swings' worth of damage. This
	# is the bug that made a stand-in target lose 100 HP in half a second.
	var move: AttackTable = Fixtures.slash_for_enemy()
	var w := world()
	var e := Fixtures.stationary_enemy(Vector3(0.0, 0.0, 1.5))
	w.add_enemy(e)

	# Give the player enough health to survive the whole window, so the test
	# measures damage rather than surviving.
	w.player.max_hp = 100000.0
	w.player.hp = 100000.0

	w.step(press_light())
	run(w, CombatInput.new(), 45)

	h.eq_int(e.last_outcome, Combatant.Outcome.HIT, "the swing connected")
	h.eq_float(e.max_hp - e.hp, float(move.damage),
		"exactly one move's damage was dealt across the whole active window")

	# And the same from the enemy's side. The enemy gets to take as many swings
	# as it likes over this window, so the invariant to check is that the total
	# damage is exactly one move's worth per registered hit - not that it swung
	# a particular number of times.
	var w2 := world()
	w2.player.max_hp = 100000.0
	w2.player.hp = 100000.0
	w2.player.max_stamina = 100000.0
	w2.player.stamina = 100000.0
	w2.add_enemy(Fixtures.enemy_with(move, Vector3(0.0, 0.0, 1.4)))
	run(w2, CombatInput.new(), 90)

	var landed := 0
	for ev in w2.events:
		if ev["kind"] == "enemy_hit_player":
			landed += 1
	h.ok(landed > 0, "the enemy landed at least one swing")
	h.eq_float(w2.player.max_hp - w2.player.hp, float(move.damage * landed),
		"the enemy deals exactly one move's damage per registered hit")


# --- Controls -----------------------------------------------------------------

static func test_verbs(h: TestHarness) -> void:
	h.suite("Every bound control actually does something")

	# The blockout shipped with flask, tool, interact and walk bound to keys and
	# read by nothing. This suite is the guard against that class of dead
	# binding: each verb has to produce an observable change in the world.

	# Walk: a light tilt and a run tilt must produce different speeds.
	var slow := world()
	var fast := world()
	var walk_input := CombatInput.new()
	walk_input.move = Vector2(0.0, 0.3)
	walk_input.cam_yaw = 0.0
	run(slow, walk_input, 30)

	var run_input := CombatInput.new()
	run_input.move = Vector2(0.0, 0.9)
	run_input.cam_yaw = 0.0
	run(fast, run_input, 30)

	h.ok(slow.player.position.z < fast.player.position.z,
		"a light tilt walks and a full tilt runs (%.2f m vs %.2f m)"
			% [slow.player.position.z, fast.player.position.z])
	h.ok(absf(slow.player.position.z - Tuning.WALK_SPEED / Tuning.TICK_HZ * 30.0) < 0.6,
		"walking covers about WALK_SPEED")

	# Walk must also be reachable by modifier, not only by tilt.
	var key_walk := world()
	var kw := CombatInput.new()
	kw.move = Vector2(0.0, 0.9)
	kw.cam_yaw = 0.0
	kw.walk = true
	run(key_walk, kw, 30)
	h.ok(key_walk.player.position.z < fast.player.position.z,
		"holding the walk modifier walks even with the stick pushed forward")

	# Flask: heals, spends a charge, and is refused at full health.
	var f := world()
	f.player.hp = 40.0
	var fi := CombatInput.new()
	fi.use_flask = true
	f.step(fi)
	fi.clear_edges()
	h.eq_float(f.player.hp, 40.0 + Tuning.FLASK_HEAL, "a flask heals")
	h.eq_int(f.player.flask_charges, Tuning.FLASK_CHARGES - 1, "and spends a charge")

	var full := world()
	var full_i := CombatInput.new()
	full_i.use_flask = true
	full.step(full_i)
	h.eq_int(full.player.flask_charges, Tuning.FLASK_CHARGES,
		"a flask is refused at full health rather than wasted")

	# Charges are finite, and an empty flask is refused rather than free.
	var poor := world()
	poor.player.hp = 40.0
	poor.player.flask_charges = 1
	var pi := CombatInput.new()
	pi.use_flask = true
	poor.step(pi)
	h.eq_int(poor.player.flask_charges, 0, "the last charge is spent")
	h.eq_float(poor.player.hp, 40.0 + Tuning.FLASK_HEAL, "and it heals")

	poor.player.hp = 40.0
	poor.player.flask_lock = 0
	pi.clear_edges()
	pi.use_flask = true
	poor.step(pi)
	h.eq_float(poor.player.hp, 40.0, "an empty flask does nothing")
	h.eq_int(poor.player.flask_charges, 0, "and is still empty")

	# A flask can rescue the player out of a reaction, or it is not a resource
	# you can actually spend when you need it.
	var staggered := world()
	staggered.player.hp = 40.0
	staggered.player.begin_reaction(Fixtures.reaction(Tuning.HurtLevel.STAGGER))
	h.ok(staggered.player.state == PlayerMachine.State.ACTION, "player is staggered")
	var si := CombatInput.new()
	si.use_flask = true
	staggered.step(si)
	h.eq_float(staggered.player.hp, 40.0 + Tuning.FLASK_HEAL,
		"a flask can be drunk out of a stagger")
	h.eq_int(staggered.player.state, PlayerMachine.State.GROUND,
		"and clears the stagger")

	# Tool: thrown, spends a charge, and actually connects.
	var t := world()
	var target := Fixtures.stationary_enemy(Vector3(0.0, 0.0, 4.0), 200.0)
	t.add_enemy(target)
	var ti := CombatInput.new()
	ti.tool.press()
	t.step(ti)
	ti.clear_edges()
	h.eq_int(t.projectiles.size(), 1, "the tool button throws a shuriken")
	h.eq_int(t.player.tool_charges, Tuning.TOOL_CHARGES - 1, "and spends a charge")

	run(t, CombatInput.new(), 40)
	h.ok(target.hp < target.max_hp, "the shuriken reaches and damages a target ahead")
	h.eq_int(t.projectiles.size(), 0, "and is cleaned up once spent")

	# A tool thrown away from from everything eventually expires rather than
	# living forever.
	var miss := world()
	miss.add_enemy(Fixtures.stationary_enemy(Vector3(0.0, 0.0, -6.0), 200.0))
	var mi := CombatInput.new()
	mi.tool.press()
	miss.step(mi)
	mi.clear_edges()
	run(miss, CombatInput.new(), Tuning.TOOL_LIFE_TICKS + 5)
	h.eq_int(miss.projectiles.size(), 0, "an unspent tool expires")

	# Crouch: a real, separate gait.
	var crouch := world()
	var ci := CombatInput.new()
	ci.crouch = true
	ci.move = Vector2(0.0, 0.9)
	ci.cam_yaw = 0.0
	run(crouch, ci, 20)
	h.ok(crouch.player.crouching, "crouch toggles on")
	h.ok(crouch.player.position.z < fast.player.position.z,
		"and crouching is slower than running")

	# Guard: holds, and opens the timed window on press.
	var g := world()
	var gi := CombatInput.new()
	gi.guard.press()
	g.step(gi)
	gi.clear_edges()
	h.ok(g.player.guarding, "guard holds")
	h.ok(g.player.timed_guard_ticks > 0, "and pressing it opens the timed-guard window")

	# Jump: leaves the ground.
	var j := world()
	var ji := CombatInput.new()
	ji.jump.press()
	j.step(ji)
	h.eq_int(j.player.state, PlayerMachine.State.AIR, "jump leaves the ground")
	h.ok(j.player.velocity_y > 0.0, "with upward velocity")

	# Death and restart: the whole failure loop, with no terminal state.
	var d := world()
	d.player.kill()
	h.ok(d.player.dead, "the player can die")
	d.restart()
	h.ok(not d.player.dead, "restart revives")
	h.eq_float(d.player.hp, d.player.max_hp, "and restores health")
	h.eq_int(d.player.flask_charges, Tuning.FLASK_CHARGES, "and refills flasks")
	h.eq_int(d.player.tool_charges, Tuning.TOOL_CHARGES, "and refills tools")
	h.eq_int(d.player.state, PlayerMachine.State.GROUND, "and returns to the ground")
	h.ok(d.player.can_commit(), "and can act again")

	# GDD 3.4: death wipes the run's temporaries, so a retry is a clean build.
	var dirty := world()
	dirty.player.tool_charges = 1
	dirty.player.hp = 3.0
	dirty.projectiles.append(Projectile.new(Vector3.ZERO, Vector3.FORWARD))
	dirty.restart()
	h.eq_int(dirty.projectiles.size(), 0, "restart clears tools in flight")
	h.ok(dirty.player.can_commit(), "and the player can act after restarting")


# --- Authored data ------------------------------------------------------------

static func test_sweep_data(h: TestHarness) -> void:
	h.suite("Authored sweeps and move data are self-consistent")

	# Every preset must produce a constant-length blade. This is the check that
	# catches a weapon silently stretching across a swing, which is easy to
	# author by hand and reads as a hitbox that does not match the animation.
	for preset in BladePose.Preset.values():
		for blade in [0.8, 1.15, 1.6]:
			var poses := BladePose.from_preset(preset, blade)
			h.ok(poses.size() >= 2, "preset %d produces at least two poses" % preset)
			var lengths: Array[float] = []
			for p in poses:
				lengths.append(p.blade_length())
			var lo: float = lengths.min()
			var hi: float = lengths.max()
			h.ok(
				hi > 0.0 and (hi - lo) / hi <= 0.25,
				"preset %d holds a constant blade length at %.2fm (%.3f to %.3f)"
					% [preset, blade, lo, hi]
			)

	# Reaches must be sane for a one-and-a-bit-metre ninja, not merely
	# self-consistent. Forward reach is what decides whether an attack connects.
	var katana := Fixtures.katana()
	for move in katana.all_moves():
		if not move.is_offensive():
			continue
		h.ok(move.forward_reach() > 0.5 and move.forward_reach() < 3.0,
			"%s reaches a plausible distance (%.2f m)" % [move.id, move.forward_reach()])

	# The whole katana family must validate clean, and so must the enemy set.
	h.eq_int(katana.validate().size(), 0,
		"the katana family has no data problems: %s" % str(katana.validate()))
	h.eq_int(Fixtures.dummy_enemy().validate().size(), 0,
		"the enemy family has no data problems: %s" % str(Fixtures.dummy_enemy().validate()))

	# The validator must actually catch things, or "no problems" means nothing.
	# A move that can be interrupted before its blade lands is a real bug.
	var bad := Fixtures.light_one()
	bad.cancel_from = 1
	h.ok(bad.validate().size() > 0, "a move cancellable before it lands is reported")

	var no_sweep := Fixtures.light_one()
	no_sweep.sweep = []
	h.ok(no_sweep.validate().size() > 0, "an attack with no sweep is reported")

	var bad_window := Fixtures.light_one()
	bad_window.active_to = bad_window.active_from
	h.ok(bad_window.validate().size() > 0, "an empty active window is reported")

	# And a dodge is not an offence, so it is not flagged for having no window.
	var d := Fixtures.dodge()
	h.ok(not d.is_offensive(), "a dodge is not offence")
	h.eq_int(d.validate().size(), 0, "a dodge with no active window is not a problem")

	# The chain must be walkable from its first move.
	h.ok(katana.first_light() != null, "the katana has an opener")
	h.ok(katana.next_light(katana.light_chain[0]) == katana.light_chain[1],
		"light one continues to light two")
	h.ok(katana.next_light(katana.light_chain[1]) == katana.light_chain[2],
		"light two continues to light three")

	# A looping chain would let a player hold the button forever.
	var loop_a := Fixtures.light_one()
	var loop_b := Fixtures.light_two()
	loop_a.chain_next = loop_b
	loop_b.chain_next = loop_a
	var looping := Moveset.new()
	looping.light_chain = [loop_a, loop_b]
	h.ok(looping.validate().size() > 0, "a light chain that loops back is reported")

	# The balancing sheet must render without exploding, since CI reads it.
	h.ok(katana.report().size() == katana.all_moves().size(),
		"the moveset report has one line per move")


# --- Determinism --------------------------------------------------------------

static func test_determinism(h: TestHarness) -> void:
	h.suite("The same inputs produce the same world")

	# GDD 8.4: procedural randomisation must not compromise deterministic combat
	# tests, and GDD 13.4 asks for combat tests that are reproducible.
	var script := [
		[&"light"], [&"none"], [&"light"], [&"none"], [&"dodge"],
		[&"none"], [&"guard"], [&"none"], [&"heavy"], [&"none"],
		[&"light"], [&"none"], [&"none"], [&"dodge"], [&"none"],
	]

	var fingerprint := func() -> String:
		var w := world()
		var e := Fixtures.stationary_enemy(Vector3(0.0, 0.0, 1.4))
		w.add_enemy(e)
		for step in script:
			w.step(held(step))
		return "%s|%.4f|%.4f|%s" % [
			str(w.player.position.snappedf(0.0001)),
			w.player.hp, e.hp, str(w.events.size())
		]

	h.eq_string(fingerprint.call(), fingerprint.call(),
		"two identical scripted runs agree exactly")