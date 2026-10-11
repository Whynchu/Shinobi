## Draws the simulation's collision shapes and authored sweeps in the world.
##
## This is the tool that makes Decision 4 - hand-authored blade sweeps - a
## workable authoring choice rather than a leap of faith. What you see here is
## not an approximation of the hitbox; it is the same data the hit test uses,
## at the same resolution the sweep test samples it.
##
## Three things are drawn:
##
##   * The player's full authored sweep, faded, for every move that could start.
##     This is how you judge an arc before committing to it.
##   * The live sweep of whatever move is playing right now, bright.
##   * Each combatant's body capsule, which is the other half of the query.
##
## GDD 16's Gate A fails on "animations/hitboxes disagree". Watching the two
## side by side is the cheapest way to never reach that state.
class_name SweepDebug
extends Node3D

const SAMPLE_STEP := 2  ## draw every Nth tick of a move's window

var enabled := true
var show_authored := true

var _idle: StandardMaterial3D
var _live: StandardMaterial3D
var _body: StandardMaterial3D

## Rebuilt each frame rather than pooled; there are at most a few hundred
## segments and this runs only while the blockout is open.
var _idle_segments: Array[MeshInstance3D] = []
var _live_segments: Array[MeshInstance3D] = []


func _init() -> void:
	_idle = _unlit(Color(0.45, 0.78, 1.0, 0.28))
	_live = _unlit(Color(1.0, 0.86, 0.35, 0.95))
	_body = _unlit(Color(0.98, 0.42, 0.38, 0.30))


static func _unlit(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# GDD 14 wants an independently configurable flashes option; the debug view
	# follows the same idea by being a separate toggle rather than an always-on
	# overlay.
	m.no_depth_test = false
	return m


## Show the whole authored sweep of a move, faded, in world space.
func draw_authored(move: AttackTable, origin: Vector3, facing: float) -> void:
	if not enabled or not show_authored or move == null:
		return
	var f := Vector3(sin(facing), 0.0, cos(facing))
	var span := move.active_to - move.active_from
	if span <= 0:
		return
	for tick in range(move.active_from, move.active_to, SAMPLE_STEP):
		var pose := move.blade_at(tick)
		if pose.size() < 2:
			continue
		var world_pose := HitGeometry.to_world(pose, origin, f)
		_idle_segments.append(_segment(world_pose[0], world_pose[1], 0.025, _idle))


## Show the live sweep: the blade's path across the tick that just ran.
func draw_live(sweep: Array) -> void:
	if not enabled or sweep.size() < 2:
		return
	var from: Array = sweep[0]
	var to: Array = sweep[1]
	if from.size() < 2 or to.size() < 2:
		return
	# Sub-step the same way the hit test does, so the drawn path is exactly the
	# path that was searched. Drawing a smooth line where the test samples five
	# points would be a lie about what the collision code does.
	var steps := Tuning.SWEEP_SUBSTEPS
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a: Vector3 = from[0].lerp(to[0], t0)
		var b: Vector3 = from[1].lerp(to[1], t0)
		var a2: Vector3 = from[0].lerp(to[0], t1)
		var b2: Vector3 = from[1].lerp(to[1], t1)
		_live_segments.append(_segment(a, a2, 0.05, _live))
		_live_segments.append(_segment(b, b2, 0.05, _live))


## Show a combatant's body capsule: the volume an attack has to reach.
func draw_body(at: Vector3, tint := Color(0.98, 0.42, 0.38, 0.30)) -> void:
	if not enabled:
		return
	var capsule := SimWorld.body_capsule(at)
	_live_segments.append(_segment(capsule[0], capsule[1], Tuning.BODY_RADIUS * 0.9, _body))


## Clear everything drawn last frame.
func clear() -> void:
	for s in _idle_segments:
		s.queue_free()
	for s in _live_segments:
		s.queue_free()
	_idle_segments.clear()
	_live_segments.clear()


func _segment(a: Vector3, b: Vector3, width: float, material: Material) -> MeshInstance3D:
	var span := b - a
	var length := span.length()
	var mi := MeshInstance3D.new()
	mi.material_override = material
	if length < 1e-4:
		# Degenerate: the two points coincide, so there is no axis to build a
		# basis from. A small sphere reads correctly as a point sample.
		var sphere := SphereMesh.new()
		sphere.radius = width
		sphere.height = width * 2.0
		mi.mesh = sphere
		mi.position = a
	else:
		var box := BoxMesh.new()
		box.size = Vector3(width, length, width)
		mi.mesh = box
		mi.transform = Transform3D(
			BladeView._basis_from_y(span.normalized()).scaled(Vector3(1.0, length, 1.0)),
			a + span * 0.5
		)
	# Must be in the tree before a transform can be interpreted as a placement.
	add_child(mi)
	return mi