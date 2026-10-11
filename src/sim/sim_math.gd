## Small angle and vector helpers shared by the simulation.
##
## Separated out so that the turning convention lives in one readable place.
## The convention throughout is: yaw 0 faces +Z, positive yaw turns toward +X,
## and `atan2(x, z)` converts a direction to a yaw. The camera and the authored
## blade sweeps both use this, so a mismatch here would show up as the character
## turning the wrong way or a swing sweeping across its owner's back.
class_name SimMath
extends RefCounted


## Signed shortest angular distance from `from` to `to`, in radians, within
## (-PI, PI]. Always takes the short way round, including exactly opposite,
## which is the case a naive subtraction gets wrong.
static func angle_diff(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


## Yaw for a direction. Yaw 0 is +Z, which is what makes `atan2(x, z)` rather
## than `atan2(z, x)` correct here.
static func yaw_of(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


## Turn `from` toward `to` by at most `max_step` radians. Returns `from`
## unchanged if the goal is already within one step, so repeated calls
## converge without overshooting.
static func turn_towards(from: float, to: float, max_step: float) -> float:
	var diff := angle_diff(from, to)
	if absf(diff) <= max_step:
		return to
	return from + signf(diff) * max_step


## Turn `from` toward `to` by at most `max_step`, stopping exactly on the goal.
static func turn_towards_exact(from: float, to: float, max_step: float) -> float:
	return from + clampf(angle_diff(from, to), -max_step, max_step)


## Yaw of the vector `a - b`, ignoring height. Used for "which way is that
## target relative to me" questions where vertical offset is noise.
static func yaw_toward(from: Vector3, to: Vector3) -> float:
	var d := to - from
	d.y = 0.0
	return yaw_of(d)


## Horizontal distance, ignoring height. Lock-on and aggro ranges are measured
## on the ground plane, not through walls and floors.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()


## Direction from `from` toward `to` on the ground plane, normalised, or zero
## when the two are vertically stacked.
static func flat_direction(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	if d.length_squared() < 1e-12:
		return Vector3.ZERO
	return d.normalized()