## Third-person follow camera.
##
## GDD 4.3: slightly elevated to protect the small character's silhouette, smooth
## follow, collision avoidance, and a lock-on that targets one enemy. Critically:
## "Prefer a fixed comfortable framing at base combat distance to dramatic
## cinematic zooms that conceal incoming attacks", and "Camera cannot hide lethal
## telegraphs in default framing".
##
## That last line is a hard constraint, not a preference. So this camera does not
## dolly, does not punch in on attacks, and keeps a fixed distance and height.
## Anything that would tighten the framing during a swing has to be earned later,
## against GDD 18's camera-failure metric.
class_name CameraRig
extends Camera3D

## Distance behind and above the target.
const DISTANCE := 4.6
const HEIGHT := 2.1

## How quickly the camera closes on its desired position. Higher is tighter.
## Deliberately not instantaneous: a camera that snaps reads as a cut.
const FOLLOW := 9.0

## How far the camera pulls in when geometry is between it and the target, and
## how quickly it returns.
const MIN_DISTANCE := 1.2
const OCCLUSION_SPEED := 16.0

var target: Node3D = null
var lock_target: Node3D = null

## Set by the blockout; used for the occlusion query.
var world: Node3D = null

var _distance := DISTANCE


func _ready() -> void:
	fov = 62.0
	near = 0.05
	far = 200.0


## Point the camera. `yaw` and `pitch` come from the input reader, because the
## simulation is told about the camera's yaw but never controls it.
func follow(yaw: float, pitch: float, delta: float) -> void:
	if target == null:
		return

	var focus := target.global_position + Vector3(0.0, Tuning.CHARACTER_HEIGHT * 0.55, 0.0)

	if lock_target != null:
		# Locked on: sit behind the target, framed on the pair. GDD 4.3 says
		# lock-on "softens lateral facing penalties"; that is a simulation
		# concern, and here it just keeps both fighters on screen.
		var to_pair := (lock_target.global_position - focus)
		yaw = atan2(-to_pair.x, -to_pair.z) + PI
		yaw = wrapf(yaw, -PI, PI)

	var offset := Vector3(
		sin(yaw) * cos(pitch),
		-sin(pitch),
		cos(yaw) * cos(pitch)
	)
	var desired := focus - offset * DISTANCE
	desired.y = focus.y + HEIGHT

	# Pull in when something is in the way, so a wall does not become the
	# player's whole view. GDD 4.3 asks for collision avoidance explicitly.
	var blocked := _occluded(focus, desired)
	var want := MIN_DISTANCE if blocked else DISTANCE
	_distance = move_toward(_distance, want, (OCCLUSION_SPEED if blocked else FOLLOW) * delta)

	var placed := focus - offset.normalized() * _distance
	placed.y = focus.y + HEIGHT * (_distance / DISTANCE)

	# Smooth follow on position, always aiming at the focus point.
	var weight := 1.0 - exp(-FOLLOW * delta)
	global_position = global_position.lerp(placed, weight)
	look_at(focus, Vector3.UP)


## Ray from the focus point out to where the camera wants to be. Returns true if
## something opaque is in the way.
func _occluded(from: Vector3, to: Vector3) -> bool:
	if world == null:
		return false
	var space := world.get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [target] if target != null else []
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()


## Snap straight to the framing, with no smoothing. Used on respawn and on
## dojo restart, where GDD 3.4 asks for a fast transition.
func snap(yaw: float, pitch: float) -> void:
	_distance = DISTANCE
	# The follow lerp approaches 1 as delta grows, so a large delta is a snap.
	follow(yaw, pitch, 100.0)