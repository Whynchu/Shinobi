## Analytic hit geometry.
##
## Hitting things in this game is a geometric query, not a physics query
## (GDD 5.1: "A weapon only hits when its collision volume reaches the target;
## standing outside range or beside a thrust must miss"). GDD 5.4 tightens
## this: "Hitboxes follow visual sweeps closely; attacks cannot secretly reach
## far beyond their visible blade."
##
## So a hit is: does the blade segment, swept across this tick, come within
## `blade_radius` of the target's body segment? That is computed directly.
## Physics bodies are not involved, which keeps the answer deterministic and
## keeps it identical whether the game is running or the tests are running
## headless with no scene tree at all.
class_name HitGeometry
extends RefCounted


## Closest approach between two line segments, and the points where it happens.
##
## Handles the degenerate cases the textbook solution skips: a segment reduced
## to a point (a hilt at the swing's centre) and two segments lying parallel to
## each other, which is exactly what happens when a blade is held still
## directly in front of a target.
static func closest_points(
		a_from: Vector3, a_to: Vector3, b_from: Vector3, b_to: Vector3
) -> Array:
	var u := a_to - a_from
	var v := b_to - b_from
	var w := a_from - b_from

	var a := u.dot(u)
	var e := v.dot(v)
	var f := v.dot(w)

	var s := 0.0
	var t := 0.0

	if a <= _EPS and e <= _EPS:
		# Both segments are points; nothing to solve.
		return [a_from, b_from]

	if a <= _EPS:
		# The blade is a point: find where it meets the other segment.
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := u.dot(w)
		if e <= _EPS:
			# The target is a point.
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := u.dot(v)
			var denom := a * e - b * b
			if denom >= _EPS:
				# Not parallel: solve for the two closest parameters.
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			# Parallel segments leave `s` at 0 and take the clamped path below.
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)

	return [a_from + u * s, b_from + v * t]


## Shortest distance between two line segments.
static func segment_distance(
		a_from: Vector3, a_to: Vector3, b_from: Vector3, b_to: Vector3
) -> float:
	var p := closest_points(a_from, a_to, b_from, b_to)
	return p[0].distance_to(p[1])


## Do two capsules touch? A capsule is a segment inflated by a radius, so the
## test is whether the segments come within the sum of the radii.
static func capsules_touch(
		a_from: Vector3, a_to: Vector3, a_radius: float,
		b_from: Vector3, b_to: Vector3, b_radius: float
) -> bool:
	return segment_distance(a_from, a_to, b_from, b_to) <= a_radius + b_radius


## Move a blade pose from the character's local space into the world.
##
## Local space is left / up / forward rather than world axes, so an authored
## sweep reads the way the move reads ("starts over the left shoulder") instead
## of the way the engine stores it. See BladePose.
static func to_world(pose: Array, origin: Vector3, facing: Vector3) -> Array:
	if pose.size() < 2:
		return []
	var right := Vector3(-facing.z, 0.0, facing.x)
	var hilt: Vector3 = pose[0]
	var tip: Vector3 = pose[1]
	return [
		origin + right * hilt.x + Vector3.UP * hilt.y + facing * hilt.z,
		origin + right * tip.x + Vector3.UP * tip.y + facing * tip.z,
	]


## Does the blade hit the target at any point during this tick?
##
## `tick_start` and `tick_end` are the blade's world-space poses at the two
## ends of the tick. `substeps` samples between them. A fast swing covers real
## distance in one tick, so a single test at the tick boundary would let the
## blade pass straight through a target between samples and the attack would
## silently whiff (GDD 18 tracks "attack whiffs" as a balance metric, so a
## tunnelling bug would show up there as data rather than as a bug).
static func sweep_touches(
		blade_start: Array, blade_end: Array,
		body_from: Vector3, body_to: Vector3, body_radius: float,
		blade_radius: float, substeps: int
) -> bool:
	if blade_start.size() < 2 or blade_end.size() < 2:
		return false
	var steps := maxi(1, substeps)
	var a0: Vector3 = blade_start[0]
	var b0: Vector3 = blade_start[1]
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var a := a0.lerp(blade_end[0], t)
		var b := b0.lerp(blade_end[1], t)
		if capsules_touch(a, b, blade_radius, body_from, body_to, body_radius):
			return true
	return false


## Same sweep, but reports where it touched. Used by the debug view and by
## telemetry to prove a hit landed at the visually expected spot (GDD 5.4).
static func sweep_contact(
		blade_start: Array, blade_end: Array,
		body_from: Vector3, body_to: Vector3, body_radius: float,
		blade_radius: float, substeps: int
) -> Vector3:
	if blade_start.size() < 2 or blade_end.size() < 2:
		return Vector3.INF
	var steps := maxi(1, substeps)
	var a0: Vector3 = blade_start[0]
	var b0: Vector3 = blade_start[1]
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var a := a0.lerp(blade_end[0], t)
		var b := b0.lerp(blade_end[1], t)
		var p := closest_points(a, b, body_from, body_to)
		if p[0].distance_to(p[1]) <= blade_radius + body_radius:
			return p[0]
	return Vector3.INF


const _EPS := 1e-8