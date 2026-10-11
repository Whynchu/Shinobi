## The combat HUD.
##
## GDD 11.5: a small health / stamina HUD, and "never cover combat with large
## decorations". So this is four thin bars in a corner and nothing else. No
## health numbers, because GDD 5.1 asks for readability through shapes and
## silhouettes rather than through instrumentation.
##
## The posture bar is the one addition, and it is only shown while the meter is
## non-empty: GDD 5.3 wants a posture break to be "clearly signposted", which
## means appearing when it matters rather than sitting there permanently.
class_name Hud
extends Control

const BAR_WIDTH := 190.0
const BAR_HEIGHT := 12.0

var _health: ColorRect
var _stamina: ColorRect
var _posture: ColorRect
var _flasks: Label
var _tools: Label
var _hint: Label
var _death: Panel
var _death_text: Label

## GDD 11.3 palette, kept in one place so the HUD and the shaders agree.
const COLOR_HEALTH := Color(0.91, 0.37, 0.31)
const COLOR_STAMINA := Color(0.58, 0.85, 0.62)
const COLOR_POSTURE := Color(0.96, 0.78, 0.42)
const COLOR_INK := Color(0.96, 0.94, 0.87)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_health = _bar(Color(0.16, 0.12, 0.14, 0.85), 0.0, COLOR_HEALTH)
	_stamina = _bar(Color(0.12, 0.18, 0.13, 0.85), 26.0, COLOR_STAMINA)
	_posture = _bar(Color(0.18, 0.15, 0.08, 0.85), 52.0, COLOR_POSTURE)

	_flasks = Label.new()
	_flasks.text = ""
	_flasks.position = Vector2(14.0, 74.0)
	_flasks.add_theme_color_override("font_color", COLOR_INK)
	_flasks.add_theme_font_size_override("font_size", 15)
	add_child(_flasks)

	_tools = Label.new()
	_tools.text = ""
	_tools.position = Vector2(14.0, 92.0)
	_tools.add_theme_color_override("font_color", COLOR_INK)
	_tools.add_theme_font_size_override("font_size", 15)
	add_child(_tools)

	_hint = Label.new()
	_hint.position = Vector2(14.0, 118.0)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.73, 0.66))
	_hint.add_theme_font_size_override("font_size", 13)
	add_child(_hint)

	_build_death_panel()


## GDD 3.4: "Death immediately reveals cause, collected rewards and progress,
## then returns to a fast dojo restart. No mandatory long death cutscene."
##
## So the readout is a panel the player dismisses, not a sequence they wait
## through. It is hidden unless dead.
func _build_death_panel() -> void:
	_death = Panel.new()
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.06, 0.82)
	_death.add_theme_stylebox_override("panel", style)
	_death.visible = false
	add_child(_death)

	_death_text = Label.new()
	_death_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_text.add_theme_color_override("font_color", Color(0.95, 0.90, 0.82))
	_death_text.add_theme_font_size_override("font_size", 20)
	_death.add_child(_death_text)


## One bar: a dark trough with a coloured fill whose right edge is driven by
## ratio. The fill is a child of the trough with its left edge pinned, so
## scaling it never moves the origin.
func _bar(trough_color: Color, top: float, fill_color: Color) -> ColorRect:
	var trough := ColorRect.new()
	trough.color = trough_color
	trough.position = Vector2(14.0, top)
	trough.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	add_child(trough)

	var fill := ColorRect.new()
	fill.color = fill_color
	trough.add_child(fill)
	_fill(fill, 1.0, fill_color)
	return fill


## Drive a fill from the left. The fill spans [0, ratio] of its trough, so the
## bar empties towards the left and the remaining colour is always the leading
## edge - which is what a player reads first.
func _fill(rect: ColorRect, ratio: float, color: Color) -> void:
	var r := clampf(ratio, 0.0, 1.0)
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_bottom = 1.0
	rect.anchor_right = r
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_bottom = 0.0
	# At zero, pull the right edge fully outside so no sliver of colour shows.
	rect.offset_right = 0.0 if r > 0.0 else -BAR_WIDTH
	rect.color = color


## Pull the HUD from simulation state.
func sync(player: Combatant, flask_charges: int, tool_charges := -1, death_text := "") -> void:
	_fill(_health, player.hp_fraction(), COLOR_HEALTH)
	_fill(_stamina, player.stamina_fraction(), COLOR_STAMINA)

	# GDD 5.3: the posture meter appears when it matters and is hidden when it
	# is not, so the player learns to look for it rather than ignoring a bar that
	# is always there.
	var show_posture := player.posture > 0.5
	_posture.visible = show_posture
	if show_posture:
		var color := COLOR_POSTURE
		if player.posture_broken:
			color = Color(1.0, 0.95, 0.8)
		_fill(_posture, player.posture_fraction(), color)

	# Charges are shown as counts, and go blank when spent rather than showing a
	# zero - so the player can see at a glance what they have left to spend.
	_flasks.text = "" if flask_charges <= 0 else "flask  x%d" % flask_charges
	if tool_charges >= 0:
		_tools.text = "" if tool_charges <= 0 else "shuriken  x%d" % tool_charges

	_death.visible = death_text != ""
	if death_text != "":
		_death_text.text = death_text


## Short control reminder. GDD 14 wants remappable prompts in menus; this is the
## blockout's stand-in and says so rather than pretending to be final.
func set_hint(text: String) -> void:
	_hint.text = text