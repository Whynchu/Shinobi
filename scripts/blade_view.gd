## Draws a blade as a mesh between two world-space points.
##
## This exists to make hand-authored sweeps visible. The blade is placed from
## exactly the pose the simulation is testing against, so what is on screen is
## the hitbox rather than a decoration next to it. GDD 16's Gate A fails on
## "animations/hitboxes disagree"; the cheapest way to never reach that state is
## to make disagreement impossible to author.
class_name BladeView
extends MeshInstance3D

const THICKNESS := 0.07

var _body: MeshInstance3D
var _guard: MeshInstance3D

## Colour of the blade. Distinguishing the player's weapon from an enemy's by
## hue is a blockout affordance only; the shipped game distinguishes by shape,
## which GDD 5.4 requires anyway ("color may reinforce a tell but must never be
## the sole cue").
var blade_tint := Color(0.85, 0.88, 0.95):
	set(value):
		blade_tint = value
		var mat := _body.material_override as StandardMaterial3D if _body else null
		if mat != null:
			mat.albedo_color = value


func _init() -> void:
	_body = MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(THICKNESS, 1.0, THICKNESS * 1.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = blade_tint
	mat.metallic = 0.6
	mat.roughness = 0.25
	_body.mesh = blade
	_body.material_override = mat
	_body.top_level = true
	add_child(_body)

	_guard = MeshInstance3D.new()
	var guard := BoxMesh.new()
	guard.size = Vector3(0.16, 0.04, 0.16)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.25, 0.22, 0.30)
	_guard.mesh = guard
	_guard.material_override = gmat
	_guard.top_level = true
	add_child(_guard)


## Place the blade so it spans `hilt` to `tip`.
func set_pose(hilt: Vector3, tip: Vector3) -> void:
	var span := tip - hilt
	var length := span.length()
	if length < 1e-4:
		hide_blade()
		return
	show()

	# The box is authored one metre long on Y. Scaling the basis by `length`
	# scales its Y column, which points along the blade, so the mesh spans
	# exactly hilt to tip. Setting `scale` separately would overwrite the basis.
	var basis := _basis_from_y(span.normalized()).scaled(Vector3(1.0, length, 1.0))
	_body.global_transform = Transform3D(basis, hilt + span * 0.5)
	_guard.global_transform = Transform3D(_basis_from_y(span.normalized()), hilt)


func hide_blade() -> void:
	_body.hide()
	_guard.hide()


## A basis whose local +Y points along `direction`, with an arbitrary but stable
## choice of roll. Godot has no direct helper for this, and the swing arc is
## authored in a left/up/forward frame rather than a fully oriented one, so the
## roll has to be picked rather than inherited.
static func _basis_from_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var reference := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)