## A thrown ninja tool in flight.
##
## GDD 6.1's shuriken. Modelled as a swept segment from where it was to where it
## now is, tested against body capsules by exactly the same primitive that tests
## a blade - so a thrown tool cannot tunnel through a thin target at 22 m/s, which
## is a long way to travel in one 60 Hz tick.
##
## Deliberately not a physics body. The same reasoning as the blade applies: a
## deterministic geometric query is what the rest of the combat model is built
## on, and mixing a physics projectile into it would make thrown tools the one
## part of combat that behaves differently from everything else.
class_name Projectile
extends RefCounted

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var damage := 0
var posture_damage := 0
var radius := Tuning.TOOL_RADIUS

## Ticks left before it fizzles. Bounded so a tool thrown into empty space does
## not live forever.
var life := Tuning.TOOL_LIFE_TICKS

## Whether this belongs to the player. Decides who it can hit.
var from_player := true

## Cleared once it has connected or expired, so the world can drop it.
var spent := false

## Filled by the world on the tick it connects, for telemetry and VFX.
var hit_combatant: Combatant = null


func _init(p_position := Vector3.ZERO, p_velocity := Vector3.ZERO) -> void:
	position = p_position
	velocity = p_velocity


## Advance one tick. `from` is where the tool was at the start of it, which is
## the start of the segment the world tests.
func step() -> void:
	if spent:
		return
	position += velocity * Tuning.DT
	life -= 1
	if life <= 0:
		spent = true


## The segment this tool swept across the tick that just ran.
func segment(from: Vector3) -> Array:
	return [from, position]


## Speed is constant, so "should this tool be able to reach that distance at
## all" is answerable without stepping it. Used by enemy decision-making and by
## the aim assist in tests.
func can_reach(target: Vector3) -> bool:
	return global_position_distance(target) <= velocity.length() * Tuning.DT * float(life)


func global_position_distance(target: Vector3) -> float:
	return position.distance_to(target)


func is_alive() -> bool:
	return not spent