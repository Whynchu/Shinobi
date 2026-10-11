## One tick of player input.
##
## The simulation is fed these, not the engine. Whatever produced them - a
## controller, a keyboard, the demo bot that drives headless balance runs, or a
## test - the simulation cannot tell the difference, which is the property that
## makes GDD 8.4's "procedural randomization must not compromise deterministic
## combat tests" achievable.
##
## Each button distinguishes held from pressed from released because GDD 5.2
## needs all three separately: a tap-versus-hold dodge, a charged heavy attack
## that depends on a release, and a guard whose *press* timing is the whole
## point of timed guard.
class_name CombatInput
extends RefCounted


class ButtonState extends RefCounted:
	var held := false
	## Went down during this tick.
	var pressed := false
	## Came up during this tick.
	var released := false

	func clear_edges() -> void:
		pressed = false
		released = false

	func press() -> void:
		held = true
		pressed = true

	func release() -> void:
		held = false
		released = true


## Movement stick, x right and y forward, in camera space.
var move := Vector2.ZERO

## Yaw the camera is looking along. Movement is interpreted relative to this so
## that pushing forward always means "away from the camera".
var cam_yaw := 0.0

var light := ButtonState.new()
var heavy := ButtonState.new()
var guard := ButtonState.new()
var dodge := ButtonState.new()
var jump := ButtonState.new()
var tool := ButtonState.new()
var art := ButtonState.new()

var crouch := false
var lock := false

## Deliberate walk rather than run.
var walk := false

## Consumables and meta actions. These do not enter combat state; they are
## carried here so that a single input snapshot covers a whole tick.
var cycle_tool := false
var use_flask := false


func clear_edges() -> void:
	light.clear_edges()
	heavy.clear_edges()
	guard.clear_edges()
	dodge.clear_edges()
	jump.clear_edges()
	tool.clear_edges()
	art.clear_edges()
	cycle_tool = false
	use_flask = false


func stick_tilt() -> float:
	return clampf(move.length(), 0.0, 1.0)


## Where the stick is asking to go, in world space. Zero means "no input":
## values inside the deadzone are treated as no input rather than as a tiny
## drift, so the character does not creep when the stick is resting.
func wish_direction() -> Vector3:
	if move.length() < Tuning.STICK_DEADZONE:
		return Vector3.ZERO
	var forward := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var right := Vector3(-forward.z, 0.0, forward.x)
	return (forward * move.y + right * move.x).normalized()


func is_wishing() -> bool:
	return move.length() >= Tuning.STICK_DEADZONE


## Front, back, left and right as the player would name them.
enum Cardinal { FRONT, BACK, LEFT, RIGHT }

## Which of those a world-space yaw corresponds to, relative to the character's
## own facing.
##
## GDD 4.2 wants locked-on dodges and jumps to go four ways and keep facing the
## target, rather than turning freely. Quantising to four directions is what
## makes that readable and what lets each one have its own authored move.
static func cardinal_relative(from_yaw: float, to_yaw: float) -> Cardinal:
	var off := wrapf(to_yaw - from_yaw, PI, -PI)
	if absf(off) <= PI * 0.25:
		return Cardinal.FRONT
	if absf(off) >= PI * 0.75:
		return Cardinal.BACK
	return Cardinal.LEFT if off > 0.0 else Cardinal.RIGHT
