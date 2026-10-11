## Visual representation of one simulation actor.
##
## Reads simulation state and never writes it. That one-way rule is what lets
## the simulation run headless with no scene tree at all, and it is why this
## class has no setters: if the view could tell the simulation anything, the
## tests would start depending on a renderer.
##
## The blockout rig is primitives - GDD 11.2's chibi proportions (about three
## heads tall) rather than a final mesh. Nothing here is meant to be shipped;
## the point is that a human can see whether the sword feels right.
class_name ActorView
extends Node3D

const BODY_COLOR := Color(0.91, 0.37, 0.31)

var body: MeshInstance3D
var head: MeshInstance3D
var blade: BladeView

## Vertical offset for the visual body. The simulation's origin is at the feet,
## which is also what `body_capsule` assumes, so the mesh sits on top of it
## rather than around it.
var body_height := Tuning.CHARACTER_HEIGHT


func _init(tint := BODY_COLOR, blade_tint := Color(0.85, 0.88, 0.95)) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.9

	body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = Tuning.BODY_RADIUS
	# Godot's CapsuleMesh height is the total including both caps, so the
	# straight section is height - 2 * radius.
	capsule.height = body_height
	body.mesh = capsule
	body.material_override = mat
	body.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(body)

	head = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = Tuning.BODY_RADIUS * 0.72
	sphere.height = sphere.radius * 2.0
	head.mesh = sphere
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = tint.lightened(0.25)
	head.material_override = head_mat
	head.position = Vector3(0.0, body_height + Tuning.BODY_RADIUS * 0.55, 0.0)
	add_child(head)

	blade = BladeView.new()
	blade.blade_tint = blade_tint
	add_child(blade)


## Point the actor at its simulation position and facing.
func sync_from(machine: Combatant) -> void:
	global_position = machine.position
	# Yaw 0 faces +Z in the simulation; a Node3D's -Z is forward, so the visual
	# is turned to match rather than the simulation being bent to suit the engine.
	rotation.y = machine.yaw + PI


## Flash the body colour. Used for hit-stop and for landing a hit, which is how
## GDD 5.1's "weapon hit-stop and short pose exaggeration make successful
## contact legible" is expressed without an animation yet.
func set_flash(amount: float) -> void:
	var mat := body.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = amount > 0.01
	mat.emission = Color(1.0, 0.85, 0.6)
	mat.emission_energy_multiplier = amount


## Sink the body and tilt it, for a knockdown. A blockout stand-in for a real
## reaction animation.
func set_posture(reaction: Tuning.HurtLevel, amount: float) -> void:
	var c := clampf(amount, 0.0, 1.0)
	match reaction:
		Tuning.HurtLevel.KNOCKDOWN:
			body.rotation.x = deg_to_rad(80.0) * c
			body.position.y = body_height * 0.5 - body_height * 0.35 * c
			head.position.y = body_height * 0.2
		Tuning.HurtLevel.HEAVY_STAGGER, Tuning.HurtLevel.STAGGER:
			body.rotation.x = deg_to_rad(22.0) * c
			head.position.y = body_height + Tuning.BODY_RADIUS * 0.55 - body_height * 0.12 * c
		_:
			body.rotation.x = 0.0
			body.position.y = body_height * 0.5
			head.position.y = body_height + Tuning.BODY_RADIUS * 0.55


## Idle motion, so a standing character is not a statue. Deliberately subtle:
## GDD 11.1 asks for readable silhouettes, and a bouncing blockout would make it
## harder to judge a swing arc, not easier.
func set_idle_bob(t: float, amount: float) -> void:
	body.position.y = body_height * 0.5 + sin(t * 2.2) * 0.02 * amount
	head.position.y = body_height + Tuning.BODY_RADIUS * 0.55 + sin(t * 2.2 + 0.6) * 0.012 * amount


## Clear any flash or pose set last frame.
func reset_pose() -> void:
	set_flash(0.0)
	set_posture(Tuning.HurtLevel.NONE, 0.0)