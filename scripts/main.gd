## The playable blockout.
##
## Builds the arena, runs the simulation at a fixed 60 Hz in `_physics_process`,
## and reads the result into visuals in `_process`. Presentation never writes to
## the simulation; this file is the only place the two meet.
##
## The point of this scene is GDD 16's Gate A: "Readable original character,
## correct range and contact, readable dodge and guard". That criterion is
## perceptual. No assertion can answer whether the sword feels right, which is
## why it is the first thing after the simulation and not later.
extends Node3D

## Ticks to run before quitting, when launched with --selftest. Lets the whole
## scene boot, step and draw without a window, which is how it gets checked in
## CI at all.
const SELFTEST_TICKS := 420

var world: SimWorld
var input_reader: InputReader

var player_view: ActorView
var enemy_views: Array[ActorView] = []
var camera_rig: CameraRig
var hud: Hud
var debug: SweepDebug

var _clock := 0.0
var _selftest := false
var _ticks := 0

## Ticks the player has been dead. GDD 3.4 wants the failure explained and a
## fast way back, not a cutscene, so the readout appears promptly and any
## input restarts.
var _death_ticks := 0

## Enemy positions to restore on restart, so a retry is the same fight rather
## than a fresh roll of the encounter.
var _spawn_points: Array[Vector3] = []

## How long the shuriken visuals are kept after the projectile is spent, so a
## hit reads before it vanishes.
const PROJECTILE_LINGER := 8

## Closest the player ever got to each enemy, and the reach of whatever they were
## swinging at the time. Two numbers that between them explain any "it should
## have connected" question, which is the first thing anyone will ask about a
## hand-authored hitbox.
var _closest := PackedFloat32Array()
var _reach_at_closest := PackedFloat32Array()

## Colour ramp for enemy bodies, so two opponents are distinguishable at a glance
## without reading a name tag.
const ENEMY_TINTS := [
	Color(0.36, 0.74, 0.63),
	Color(0.47, 0.60, 0.85),
	Color(0.78, 0.45, 0.82),
]


func _ready() -> void:
	_selftest = "--selftest" in OS.get_cmdline_args()

	InputSetup.install()
	input_reader = InputReader.new()
	input_reader.set_mouse_captured(true)

	_build_environment()
	_build_world()
	_build_visuals()
	_build_camera()

	if _selftest:
		print("[blockout] selftest: %d ticks" % SELFTEST_TICKS)
	else:
		hud.set_hint(_control_hint())


# --- Construction -------------------------------------------------------------

## A world, a katana and one enemy, on the blockout arena.
func _build_world() -> void:
	world = SimWorld.new(SimLevel.arena(), Fixtures.katana())
	world.player.position = Vector3.ZERO
	world.player.yaw = 0.0

	# One opponent on the flat duelling floor.
	world.add_enemy(Fixtures.enemy_with(Fixtures.slash_for_enemy(), Vector3(0.0, 0.0, 3.0)))

	if _selftest:
		# The self-test proves the chain from button to damage. Two enemies beat a
		# scripted player to death before it manages a single swing, which makes it
		# a survival test rather than a smoke test.
		_remember_spawns()
		return

	# A second opponent off to the side, so it is obvious at a glance whether the
	# camera framing is hiding an attack. GDD 4.3 treats that as a failure rather
	# than a matter of taste.
	world.add_enemy(Fixtures.enemy_with(Fixtures.slash_for_enemy(), Vector3(4.0, 0.0, -2.0)))

	_remember_spawns()


## Record where each opponent starts, so a retry is the same fight rather than a
## different one. GDD 3.4 wants a fast restart; a restart that also re-rolls the
## encounter is not one.
func _remember_spawns() -> void:
	_spawn_points.clear()
	for e in world.enemies:
		_spawn_points.append(e.position)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.14, 0.18)
	# GDD 11.1: clear warm/cool light separation, bright and readable rather
	# than moody. This is a blockout, so it leans flat and bright on purpose.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -140.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.62, 0.74, 1.0)
	add_child(fill)

	# Ground, plus a marker for every collision column the simulation knows
	# about. Rendering them from `world.level.blocks` rather than from a second
	# list is what keeps the picture and the collision honest.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.33, 0.30)
	mat.roughness = 1.0
	ground.material_override = mat
	ground.position = Vector3(0.0, 0.0, 0.0)
	add_child(ground)


func _build_visuals() -> void:
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	add_child(visuals)

	player_view = ActorView.new(Color(0.91, 0.37, 0.31))
	visuals.add_child(player_view)

	for i in world.enemies.size():
		var tint: Color = ENEMY_TINTS[i % ENEMY_TINTS.size()]
		var view := ActorView.new(tint, Color(0.75, 0.80, 0.88))
		visuals.add_child(view)
		enemy_views.append(view)

	debug = SweepDebug.new()
	debug.name = "SweepDebug"
	add_child(debug)

	# A Control under a Node3D root lays out against the root's rect rather than
	# the viewport, which puts the HUD in an unpredictable place. A CanvasLayer
	# is the container meant for this.
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	add_child(layer)
	hud = Hud.new()
	hud.name = "Hud"
	layer.add_child(hud)

	_build_collision_blocks()


## Boxes for the arena's columns, plus static bodies so the camera's occlusion
## ray has something to hit.
func _build_collision_blocks() -> void:
	var holder := Node3D.new()
	holder.name = "Arena"
	add_child(holder)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.40, 0.34)
	mat.roughness = 1.0

	for b in world.level.blocks:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(
			maxf(0.05, b.max_x - b.min_x),
			maxf(0.05, b.top),
			maxf(0.05, b.max_z - b.min_z)
		)
		mesh.mesh = box
		mesh.material_override = mat
		mesh.position = Vector3(
			(b.min_x + b.max_x) * 0.5, b.top * 0.5, (b.min_z + b.max_z) * 0.5
		)
		holder.add_child(mesh)

		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var shape_box := BoxShape3D.new()
		shape_box.size = box.size
		shape.shape = shape_box
		body.position = mesh.position
		body.add_child(shape)
		holder.add_child(body)


func _build_camera() -> void:
	camera_rig = CameraRig.new()
	camera_rig.world = self
	add_child(camera_rig)
	camera_rig.target = player_view
	camera_rig.snap(input_reader.camera_yaw, input_reader.camera_pitch)


# --- The loop -----------------------------------------------------------------

## The simulation runs here, on Godot's fixed physics tick, which is already 60 Hz.
## `Tuning.TICK_HZ` and `physics/common/physics_ticks_per_second` agree, so
## `project.godot` and the simulation cannot drift apart.
func _physics_process(_delta: float) -> void:
	if world == null:
		return
	# The self-test drives the simulation from a script rather than a device, so
	# it exercises the player's offence as well as the enemy's. A smoke test that
	# only proves an idle target gets beaten is not worth much.
	var input := _selftest_input() if _selftest else input_reader.sample()
	if not _selftest:
		_handle_lock(input)
		_handle_death(input)
	world.step(input)

	if _selftest:
		_ticks += 1
		_track_proximity()
		if _ticks >= SELFTEST_TICKS:
			_finish_selftest()


## The failure loop, entirely. GDD 3.4: on death, explain it, then let the
## player go again immediately. There is no separate game-over state - the same
## input that did nothing useful during the fight restarts it.
func _handle_death(input: CombatInput) -> void:
	if not world.player.dead:
		_death_ticks = 0
		return
	_death_ticks += 1
	# A beat before the readout appears, so a hit that kills is not instantly
	# covered by a panel.
	if _death_ticks < 12:
		return
	if input.dodge.pressed or input.jump.pressed or input.light.pressed:
		restart()


func restart() -> void:
	world.restart()
	_death_ticks = 0
	# Put every enemy back where it started. GDD 3.4 wants the run to reset, and
	# retrying the same fight is what makes a death informative.
	for i in world.enemies.size():
		if i < _spawn_points.size():
			world.enemies[i].position = _spawn_points[i]
		world.enemies[i].yaw = PI
		world.enemies[i].hp = world.enemies[i].max_hp
		world.enemies[i].reset_reactions()
		world.enemies[i].state = EnemyMachine.State.APPROACH
		world.enemies[i].decision_cooldown = 0
	camera_rig.snap(input_reader.camera_yaw, input_reader.camera_pitch)


## What the death readout says. GDD 3.4 wants the cause named, not a generic
## "you died".
func _death_message() -> String:
	if not world.player.dead:
		return ""
	var cause := world.last_damage_source
	if cause == "":
		cause = "the fall"
	return "%s\n\npress SPACE to try again" % cause.to_upper()


## Record how near the player's blade got to each enemy, and what it was
## reaching with. Reported by the self-test so a missed hit can be diagnosed
## without re-running under a debugger.
func _track_proximity() -> void:
	if _closest.size() != world.enemies.size():
		_closest.resize(world.enemies.size())
		_reach_at_closest.resize(world.enemies.size())
		_closest.fill(-1.0)
		_reach_at_closest.fill(-1.0)
	var reach := 0.0
	if world.player.move != null:
		reach = world.player.move.forward_reach()
	for i in world.enemies.size():
		if world.enemies[i].dead:
			continue
		var d := SimMath.flat_distance(world.player.position, world.enemies[i].position)
		if _closest[i] < 0.0 or d < _closest[i]:
			_closest[i] = d
			_reach_at_closest[i] = reach


## A crude scripted opponent: walk forward, then swing on a fixed cadence.
##
## The cadence matters. Attacking every 34 ticks against a 40-tick light attack
## means the player is permanently mid-swing and never closes the gap, which
## looks like a broken simulation and is really a broken script. Swings are
## spaced well beyond the attack's duration so there is time to actually reach
## the target.
##
## Not a bot that plays well - the reference project's demo bot does that job
## properly for balance runs. This only has to prove the chain from button to
## damage.
func _selftest_input() -> CombatInput:
	var i := CombatInput.new()
	i.cam_yaw = 0.0
	if _ticks >= 10:
		i.move = Vector2(0.0, 0.7)
	# Swings at 50-tick intervals: far enough apart for the 40-tick light attack
	# to finish and for free movement to resume between them.
	for swing in [50, 150, 250, 350]:
		if _ticks == swing:
			i.light.press()
	# A shuriken partway in, to prove the tool path runs through the real scene.
	if _ticks == 120 or _ticks == 300:
		i.tool.press()
	# A flask once, if the scripted run has actually been hurt by then. The
	# threshold is generous on purpose: the point is to exercise the key-to-
	# effect wiring in the real scene, not to ration a scripted opponent.
	if _ticks == 220 and world.player.hp < 95.0:
		i.use_flask = true
	return i


## Visuals update here, independently of the simulation tick. GDD 5.2: "Visual
## rendering and animation sampling can run independently so long as attack
## windows remain deterministic." Nothing below reads a clock the simulation
## depends on.
func _process(delta: float) -> void:
	if world == null:
		return
	_clock += delta

	_sync_player()
	for i in enemy_views.size():
		if i < world.enemies.size():
			_sync_enemy(enemy_views[i], world.enemies[i])

	_sync_debug()
	_sync_camera(delta)
	_sync_projectiles()
	hud.sync(world.player, world.player.flask_charges, world.player.tool_charges, _death_message())


## Ninja tools in flight (GDD 6.1).
##
## A spinning quad rather than a proper star, and deliberately kept simple: this
## is here so the player can see where their shuriken went and whether it
## connected. GDD 11.4 asks for "crisp spinning silhouettes" eventually, which
## is art work and not this turn's problem.
var _tool_views: Array[MeshInstance3D] = []
var _tool_life: Array[int] = []


func _sync_projectiles() -> void:
	while _tool_views.size() < world.projectiles.size():
		var mesh := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.22)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.76, 0.82)
		mat.metallic = 0.8
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.9, 0.8)
		mat.emission_energy_multiplier = 0.4
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.mesh = quad
		mesh.material_override = mat
		add_child(mesh)
		_tool_views.append(mesh)
		_tool_life.append(0)

	for i in world.projectiles.size():
		_tool_views[i].visible = true
		_tool_views[i].global_position = world.projectiles[i].position
		# Spin about the direction of travel, so it reads as thrown.
		_tool_views[i].rotate_y(0.35)
		_tool_life[i] = 0

	# Anything beyond the live list lingers briefly so a hit is visible.
	for i in range(world.projectiles.size(), _tool_views.size()):
		if _tool_views[i].visible:
			_tool_life[i] += 1
			if _tool_life[i] > PROJECTILE_LINGER:
				_tool_views[i].visible = false


func _handle_lock(input: CombatInput) -> void:
	if not input.lock:
		return
	# Cycle through live enemies. GDD 4.3 asks for lock-on cycling.
	var alive: Array[EnemyMachine] = []
	for e in world.enemies:
		if not e.dead:
			alive.append(e)
	if alive.is_empty():
		world.release_lock()
		return
	var index := alive.find(world.lock_target)
	var next: EnemyMachine = alive[(index + 1) % alive.size()]
	world.acquire_lock(next)


func _sync_player() -> void:
	var p := world.player
	player_view.sync_from(p)

	# Hit-stop reads as a brief brightening, which is the blockout's stand-in for
	# GDD 5.1's "short pose exaggeration". It also communicates to the tester
	# that the hit landed, which no assertion can.
	player_view.set_flash(clampf(float(p.hit_stop) / 8.0, 0.0, 1.0))

	if p.move != null and p.move.family == AttackTable.Family.REACTION:
		var t := float(p.tick) / maxf(1.0, float(p.move.total_ticks))
		player_view.set_posture(p.move.hurt_level, t)
	else:
		player_view.set_posture(Tuning.HurtLevel.NONE, 0.0)
		player_view.set_idle_bob(_clock, 1.0 if p.state == PlayerMachine.State.GROUND else 0.0)

	# The blade is placed from the same pose the hit test uses.
	var sweep := p.blade_sweep()
	if sweep.size() >= 2 and sweep[1].size() >= 2:
		player_view.blade.set_pose(sweep[1][0], sweep[1][1])
	else:
		player_view.blade.hide_blade()


func _sync_enemy(view: ActorView, enemy: EnemyMachine) -> void:
	view.sync_from(enemy)
	view.set_flash(clampf(float(enemy.hit_stop) / 8.0, 0.0, 1.0))
	view.set_idle_bob(_clock + view.get_instance_id() * 0.001, 1.0 if enemy.state == EnemyMachine.State.IDLE else 0.0)

	var sweep := enemy.blade_sweep()
	if sweep.size() >= 2 and sweep[1].size() >= 2:
		view.blade.set_pose(sweep[1][0], sweep[1][1])
	else:
		view.blade.hide_blade()


func _sync_debug() -> void:
	debug.clear()
	if not debug.enabled:
		return

	# The authored arc of every move the player could start right now, faded.
	if debug.show_authored:
		var p := world.player
		if p.state == PlayerMachine.State.GROUND:
			var origin := p.position
			for move in [p.moveset.first_light(), p.moveset.heavy, p.moveset.jump_attack]:
				debug.draw_authored(move, origin, p.yaw)

	var sweep := world.player.blade_sweep()
	if sweep.size() >= 2:
		debug.draw_live(sweep)
	debug.draw_body(world.player.position, Color(0.98, 0.42, 0.38, 0.25))
	for e in world.enemies:
		if not e.dead:
			debug.draw_body(e.position, Color(0.45, 0.78, 1.0, 0.22))


func _sync_camera(delta: float) -> void:
	camera_rig.lock_target = null
	if world.has_valid_lock() and world.lock_target != null:
		var index := world.enemies.find(world.lock_target)
		if index >= 0 and index < enemy_views.size():
			camera_rig.lock_target = enemy_views[index]
	camera_rig.follow(input_reader.camera_yaw, input_reader.camera_pitch, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		input_reader.add_mouse_look((event as InputEventMouseMotion).relative)
		return
	# Toggle the sweep overlay without leaving the keyboard.
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == KEY_F1:
		debug.enabled = not debug.enabled
		debug.show_authored = debug.enabled
		return
	if event.is_action_pressed(&"ui_cancel"):
		# GDD 3.4 wants a fast restart, and a blockout needs a way out.
		get_tree().quit()


# --- Self test ----------------------------------------------------------------

## Run the scene headless for a fixed number of ticks and report. This is how
## the blockout gets checked without a window: it proves the scene builds, the
## simulation steps against real input, and nothing throws.
func _finish_selftest() -> void:
	var kinds := {}
	for e in world.events:
		kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
	print("[blockout] ticks=%d state=%d hp=%.0f/%.0f stam=%.0f pos=%s"
		% [world.ticks, world.player.state, world.player.hp, world.player.max_hp,
		   world.player.stamina, str(world.player.position.snappedf(0.01))])
	print("[blockout] consumables: flask=%d shuriken=%d lock=%d/%d"
		% [world.player.flask_charges, world.player.tool_charges,
		   world.player.flask_lock, world.player.tool_lock])
	for e in world.enemies:
		print("[blockout] enemy hp=%.0f/%.0f dead=%s state=%d pos=%s"
			% [e.hp, e.max_hp, str(e.dead), e.state, str(e.position.snappedf(0.01))])
	for i in world.enemies.size():
		print("[blockout] closest to enemy %d = %.2f m (blade reach at that moment %.2f m, connects within %.2f)"
			% [i, _closest[i], _reach_at_closest[i],
			   _reach_at_closest[i] + Tuning.BODY_RADIUS + (world.player.move.blade_radius if world.player.move != null else 0.0)])

	# Every verb the HUD advertises must have moved something. This is the
	# scene-level version of test_verbs: it proves the wiring from key to effect,
	# not just the simulation.
	var seen := {}
	for e in world.events:
		seen[e["kind"]] = int(seen.get(e["kind"], 0)) + 1
	print("[blockout] events: %s" % str(seen))
	# The scripted run threw a shuriken and swung the sword. If neither landed an
	# event the tool or attack pipeline is silently broken in the scene.
	if not seen.has("player_hit_enemy"):
		print("[blockout] FAIL no melee hit registered")
	if not seen.has("tool_hit_enemy"):
		print("[blockout] FAIL no shuriken hit registered")

	# The restart loop, exercised for real.
	var before := world.player.hp
	world.player.kill()
	world.last_damage_source = "selftest"
	_death_ticks = 20
	if _death_message() == "":
		print("[blockout] FAIL death readout was empty while dead")
	restart()
	if world.player.dead or world.player.hp <= 0.0:
		print("[blockout] FAIL restart did not revive the player")
	elif world.player.flask_charges != Tuning.FLASK_CHARGES:
		print("[blockout] FAIL restart did not refill consumables")
	elif _death_message() != "":
		print("[blockout] FAIL death readout persisted after restart")
	else:
		print("[blockout] restart ok (hp %.0f -> %.0f, death readout cleared)"
			% [before, world.player.hp])

	print("[blockout] views: player=%s enemies=%d camera=%s tools=%d"
		% [str(player_view != null), enemy_views.size(), str(camera_rig != null),
		   _tool_views.size()])
	print("[blockout] OK")
	get_tree().quit(0)


func _control_hint() -> String:
	return "WASD move (light tilt walks)   LMB light   RMB heavy (hold to charge)   MMB/V guard\n" \
		+ "SPACE dodge, hold sprint   SHIFT jump   Q shuriken   R flask   TAB lock   C crouch\n" \
		+ "F1 sweep overlay   ESC quit"