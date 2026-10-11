## Level collision, as the simulation sees it.
##
## The simulation asks a level two questions and nothing else: how high is the
## ground here, and may the character move this way from there. Everything about
## how that is answered is deliberately not the simulation's business.
##
## This file is the analytic implementation, used by the headless tests and by
## a blockout arena. The shipped game supplies a physics-backed implementation of
## the same two methods (GDD 13.3 keeps presentation and simulation apart), which
## is what lets Act II's roof bridges and Act III's causeways be authored without
## the tests needing a scene tree. See Docs/ARCHITECTURE.md, decision 3.
class_name SimLevel
extends RefCounted

## An axis-aligned column rising from y = 0. Enough for ledges, crates, daises
## and stairs: the shapes that determine whether a dodge, a fall or a jump
## behaves correctly, which is what the simulation actually needs to know.
class Block extends RefCounted:
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	var top := 0.0

	func _init(p_min_x := 0.0, p_max_x := 0.0, p_min_z := 0.0, p_max_z := 0.0, p_top := 0.0) -> void:
		min_x = p_min_x
		max_x = p_max_x
		min_z = p_min_z
		max_z = p_max_z
		top = p_top

	func contains(x: float, z: float) -> bool:
		return x >= min_x and x <= max_x and z >= min_z and z <= max_z


var blocks: Array[Block] = []

## Ground height under a point. Columns stack by taking the highest top that
## contains the point.
func height(x: float, z: float) -> float:
	var h := 0.0
	for b in blocks:
		if b.contains(x, z) and b.top > h:
			h = b.top
	return h


## Move `pos` horizontally, sliding along anything too tall to step onto.
##
## Tries the whole move first, then the two component moves. A character
## approaching a wall at an angle therefore ends up flush against it rather than
## sticking at the point where the diagonal first grazed the corner, which is
## the difference between movement that feels solid and movement that feels like
## it is catching on geometry.
func slide(pos: Vector3, delta: Vector3) -> Vector3:
	var reach := pos.y + Tuning.STEP_HEIGHT
	var x := pos.x + delta.x
	var z := pos.z + delta.z

	if _open(x, z, reach):
		return Vector3(x, pos.y, z)
	if _open(x, pos.z, reach):
		return Vector3(x, pos.y, pos.z)
	if _open(pos.x, z, reach):
		return Vector3(pos.x, pos.y, z)
	return pos


func _open(x: float, z: float, reach: float) -> bool:
	return height(x, z) <= reach


## Clear, flat ground. The default for tests that are about combat rather than
## traversal.
static func flat() -> SimLevel:
	return SimLevel.new()


## A blockout arena covering the traversal cases the simulation has to get
## right: something too tall to step onto, something low enough to jump onto,
## a wall to run along, a gap, a dais with two steppable tiers, pillars to fight
## around, and a staircase past every fall-damage threshold.
##
## Everything is placed *outside* the middle nine metres. The centre is the
## duelling floor and has to be genuinely flat - a crate that happens to span the
## spawn point makes the player spawn two and a half metres in the air and quietly
## breaks every combat test that uses this level.
static func arena() -> SimLevel:
	var l := SimLevel.new()

	# A climb: three crates stepping up to a wall, far on one side.
	l.add_box(-15.0, -11.0, -3.0, 3.0, 1.0)    # too tall to step onto
	l.add_box(-18.0, -15.0, -3.0, 3.0, 1.8)    # a step up
	l.add_box(-21.0, -18.0, -3.0, 3.0, 2.6)    # and another

	# A wall narrow enough to run along, with a platform across a gap from it.
	l.add_box(-23.0, -22.0, -9.0, 9.0, 2.6)
	l.add_box(-24.0, -19.0, 12.0, 17.0, 2.6)

	# A two-tier dais, each tier low enough to step onto.
	l.add_box(11.0, 15.0, -9.0, -6.0, 0.3)
	l.add_box(11.5, 15.0, -8.5, -6.0, 0.6)

	# A row of pillars to fight around, kept out of the duelling floor.
	for x in [10.0, 13.0, 16.0, 19.0]:
		l.add_box(x, x + 1.0, 2.0, 3.0, 3.5)

	# A staircase climbing past every fall-damage threshold.
	var rise := 0.12
	var run := 0.5
	var steps := 40
	for i in steps:
		var x := 9.0 + float(i) * run
		l.add_box(x, x + run, 12.0, 15.0, float(i + 1) * rise)

	return l


func add_box(p_min_x: float, p_max_x: float, p_min_z: float, p_max_z: float, p_top: float) -> Block:
	var b := Block.new(p_min_x, p_max_x, p_min_z, p_max_z, p_top)
	blocks.append(b)
	return b