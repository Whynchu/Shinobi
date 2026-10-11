## Reads the engine's input into a `CombatInput` the simulation understands.
##
## The boundary between presentation and simulation. Nothing downstream of here
## knows what a key or a button is, which is why the same `step` runs from a
## controller, from a keyboard, from the demo bot, and from the headless tests.
##
## Edge detection (pressed / held / released) happens here rather than in the
## simulation, because "was this pressed on this tick" is a question about the
## input device's sampling rate, not about the game.
class_name InputReader
extends RefCounted

## How far the camera can be looked vertically, radians from horizontal.
const PITCH_LIMIT := deg_to_rad(62.0)

## Full stick deflection, expressed as the mouse motion it is equivalent to.
## One number, so a pad and a mouse feel like the same sensitivity.
const STICK_LOOK_PIXELS := 320.0

## Mouse look sensitivity, radians per pixel of motion. GDD 4.3 requires this to
## be adjustable; GDD 14 requires an invert option.
var look_sensitivity := 0.0035
var invert_y := false

## Where the camera is looking. Read-only to the simulation: it only needs the
## yaw to interpret the movement stick.
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(-12.0)

## Whether the pointer is captured and mouse input should be acted on.
var mouse_captured := false

## Deliberate walk rather than run (GDD 4.2). GDD 14 asks for this to be
## offerable as a toggle as well as a hold; hold is the blockout's default.
var walk_held := false
var walk_as_toggle := false

## Set while a light stick tilt counts as walking (GDD 4.1 maps tilt to it).
const WALK_TILT := Tuning.WALK_TILT

var _walk_latched := false

var _input := CombatInput.new()
var _pending_look := Vector2.ZERO
var _was := {}


func _init() -> void:
	for action in [&"shinobi_light", &"shinobi_heavy", &"shinobi_guard",
			&"shinobi_dodge", &"shinobi_jump", &"shinobi_tool"]:
		_was[action] = false


## Add relative look from the mouse, in pixels. Call from `_unhandled_input`.
func add_mouse_look(relative: Vector2) -> void:
	if not mouse_captured:
		return
	_pending_look += relative


## Capture or release the mouse.
func set_mouse_captured(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


## Sample every device and produce this tick's input.
func sample() -> CombatInput:
	var i := _input
	# Edges must be rebuilt every tick. `_button` only ever *sets* them, so
	# without this a `pressed` from one tick would still be set on the next,
	# where nothing happened - and the simulation would see a phantom press.
	i.clear_edges()

	i.move = Vector2(
		Input.get_axis(&"shinobi_left", &"shinobi_right"),
		Input.get_axis(&"shinobi_back", &"shinobi_forward")
	)
	# A stick pushed to the corner should not be 1.41x faster than one pushed
	# straight forward. The simulation clamps speed anyway; clamping here keeps
	# the reported stick tilt honest.
	if i.move.length() > 1.0:
		i.move = i.move.normalized()

	i.cam_yaw = camera_yaw
	i.crouch = Input.is_action_pressed(&"shinobi_crouch")
	i.walk = _walking(i)

	_button(i.light, &"shinobi_light")
	_button(i.heavy, &"shinobi_heavy")
	_button(i.guard, &"shinobi_guard")
	_button(i.dodge, &"shinobi_dodge")
	_button(i.jump, &"shinobi_jump")
	_button(i.tool, &"shinobi_tool")

	i.lock = Input.is_action_just_pressed(&"shinobi_lock")
	i.use_flask = Input.is_action_just_pressed(&"shinobi_flask")

	_update_look()
	return i


## Whether the player wants to walk this tick.
##
## Two routes, both from GDD 4.1 and 4.2: the modifier key, or a light enough
## stick tilt. The tilt route is what makes a controller comfortable without a
## face button, and it is the same threshold the simulation uses to tell a walk
## from a run, so the two can never disagree about what counts as walking.
func _walking(i: CombatInput) -> bool:
	var by_key := Input.is_action_pressed(&"shinobi_walk")
	var by_tilt := i.stick_tilt() < WALK_TILT and i.move.length() > Tuning.STICK_DEADZONE
	var wanted := by_key or by_tilt

	if walk_as_toggle:
		if wanted and not _walk_latched:
			_walk_latched = not _walk_latched
		return _walk_latched
	return wanted


## Advance the look angles from whatever look input arrived this tick.
func _update_look() -> void:
	var stick := Vector2(
		Input.get_axis(&"shinobi_camera_left", &"shinobi_camera_right"),
		Input.get_axis(&"shinobi_camera_up", &"shinobi_camera_down")
	)
	var pixels := _pending_look + stick * STICK_LOOK_PIXELS
	_pending_look = Vector2.ZERO

	camera_yaw = wrapf(camera_yaw - pixels.x * look_sensitivity, -PI, PI)

	var pitch_delta := pixels.y * look_sensitivity
	if invert_y:
		pitch_delta = -pitch_delta
	camera_pitch = clampf(camera_pitch - pitch_delta, -PITCH_LIMIT, PITCH_LIMIT)


## Fill one button's held / pressed / released from an action.
func _button(target: CombatInput.ButtonState, action: StringName) -> void:
	var was: bool = _was[action]
	var now := Input.is_action_pressed(action)
	if now and not was:
		target.pressed = true
	elif was and not now:
		target.released = true
	target.held = now
	_was[action] = now