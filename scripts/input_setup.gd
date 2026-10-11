## Registers the input actions in code rather than in project.godot.
##
## Doing it here keeps the bindings in version control next to the thing that
## reads them, and makes the mapping legible: GDD 4.1 lists a gamepad layout and
## says remapping is a requirement, so the bindings are expected to move, and a
## table that reads as code is far easier to re-map than project.godot's event
## serialisation.
##
## Keyboard defaults follow GDD 4.1's gamepad semantics, notably that the dodge
## button is a tap for a roll and a hold for a sprint.
class_name InputSetup
extends RefCounted


## Action name -> GDD 4.1's gamepad control.
const LABELS := {
	&"shinobi_left": "Left stick",
	&"shinobi_right": "Left stick",
	&"shinobi_forward": "Left stick",
	&"shinobi_back": "Left stick",
	&"shinobi_light": "RB / left mouse",
	&"shinobi_heavy": "RT (hold to charge) / right mouse",
	&"shinobi_guard": "LB / middle mouse",
	&"shinobi_dodge": "B (tap dodge, hold sprint) / space",
	&"shinobi_jump": "A / shift",
	&"shinobi_lock": "R3 / tab",
	&"shinobi_crouch": "L3 / C",
	&"shinobi_walk": "Left Alt / left stick tilt",
	&"shinobi_restart": "Space / A after death",
	&"shinobi_interact": "X / E",
	&"shinobi_tool": "Y / Q",
	&"shinobi_flask": "D-pad up / R",
}


## Register every action, plus the camera axis. Safe to call more than once.
static func install() -> void:
	_axes()
	_keys_and_buttons()
	_camera()


## WASD and the left stick. Deadzone is left at the engine default; the
## simulation applies its own stick deadzone separately, because the two answer
## different questions (this one removes electrical noise, that one decides when
## the character is walking rather than running).
static func _axes() -> void:
	_bind_axis(&"shinobi_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis(&"shinobi_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis(&"shinobi_forward", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis(&"shinobi_back", JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis(&"shinobi_camera_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_axis(&"shinobi_camera_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_axis(&"shinobi_camera_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_axis(&"shinobi_camera_down", JOY_AXIS_RIGHT_Y, 1.0)


static func _keys_and_buttons() -> void:
	_key(&"shinobi_left", KEY_A)
	_key(&"shinobi_right", KEY_D)
	_key(&"shinobi_forward", KEY_W)
	_key(&"shinobi_back", KEY_S)

	# GDD 4.1: RB is the light attack, RT the heavy one. RB is a button; RT is an
	# axis on almost every pad, so it is bound as one. Binding RT to a button
	# index is the classic way to get an unbound heavy attack on PC with a
	# controller plugged in.
	_button(&"shinobi_light", JOY_BUTTON_RIGHT_SHOULDER)
	_mouse(&"shinobi_light", MOUSE_BUTTON_LEFT)

	_bind_axis(&"shinobi_heavy", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_mouse(&"shinobi_heavy", MOUSE_BUTTON_RIGHT)

	_button(&"shinobi_guard", JOY_BUTTON_LEFT_SHOULDER)
	_mouse(&"shinobi_guard", MOUSE_BUTTON_MIDDLE)
	_key(&"shinobi_guard", KEY_V)

	# Tap to roll, hold to sprint. Handled by the simulation, which is the only
	# place that knows the difference matters.
	_button(&"shinobi_dodge", JOY_BUTTON_B)
	_key(&"shinobi_dodge", KEY_SPACE)

	_button(&"shinobi_jump", JOY_BUTTON_A)
	_key(&"shinobi_jump", KEY_SHIFT)

	_button(&"shinobi_lock", JOY_BUTTON_RIGHT_STICK)
	_key(&"shinobi_lock", KEY_TAB)

	_button(&"shinobi_crouch", JOY_BUTTON_LEFT_STICK)
	_key(&"shinobi_crouch", KEY_C)

	# Deliberate walk. GDD 4.2 asks for walk as a distinct gait; holding a
	# modifier is the least surprising binding, and GDD 14 wants hold/toggle
	# offered as an option.
	_key(&"shinobi_walk", KEY_ALT)

	# Restart after death. Bound to the dodge button so it is under the thumb
	# that is already there, per GDD 3.4's fast restart.
	_key(&"shinobi_restart", KEY_SPACE)
	_button(&"shinobi_restart", JOY_BUTTON_A)

	_button(&"shinobi_interact", JOY_BUTTON_X)
	_key(&"shinobi_interact", KEY_E)

	_button(&"shinobi_tool", JOY_BUTTON_Y)
	_key(&"shinobi_tool", KEY_Q)

	_button(&"shinobi_flask", JOY_BUTTON_DPAD_UP)
	_key(&"shinobi_flask", KEY_R)


static func _camera() -> void:
	_mouse_motion(&"shinobi_camera_left")
	_mouse_motion(&"shinobi_camera_right")
	_mouse_motion(&"shinobi_camera_up")
	_mouse_motion(&"shinobi_camera_down")


static func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, Tuning.STICK_DEADZONE)


static func _key(action: StringName, keycode: Key) -> void:
	_ensure(action)
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	InputMap.action_add_event(action, e)


static func _mouse(action: StringName, button: MouseButton) -> void:
	_ensure(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


static func _button(action: StringName, button: JoyButton, _unused := false) -> void:
	_ensure(action)
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


static func _bind_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)


static func _mouse_motion(action: StringName) -> void:
	_ensure(action)
	var e := InputEventMouseMotion.new()
	e.relative = Vector2.ZERO
	InputMap.action_add_event(action, e)