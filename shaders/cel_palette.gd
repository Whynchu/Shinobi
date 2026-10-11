## GDD 11.3 core palette, and the cel shading ramp derived from it.
##
## The seven colours below are the GDD's own table, copied exactly. GDD 11.3 is
## [PROPOSED] but GDD 11.1 ([LOCKED]) is what fixes them in place: "Bright
## GameCube-era stylization ... readable cel shading ... clear warm/cool light
## separation." Every colour and every constant here is written from that table
## and from reasoning about how it will behave under the shaders in this folder.
## Nothing is traced from another game's art; see NOTICE.md.
##
## Why a script and not a resource file: GDD 11.3 encodes *roles*, not just
## swatches, and a role is what the rest of the game actually needs. "Banners,
## scarves, target accents" is a statement about where a colour is allowed to
## appear, which a bare hex in a material cannot carry. GDD 11.3's second rule -
## "Keep backgrounds slightly lower contrast than the actor/target pair" - is the
## one GDD 5.4's readability contract leans on hardest, so it gets a helper
## rather than being left to taste.
class_name CelPalette
extends RefCounted

# --- The GDD 11.3 table, verbatim ---------------------------------------------
#
# Written with the hex the GDD prints, so a reviewer can diff this block against
# the table in the GDD without translating anything. tests/test_art.gd asserts
# each one round-trips back to the exact eight-bit value GDD 11.3 lists, so a
# typo here fails CI rather than shipping.

## Forest jade. GDD 11.3: "Large nature masses".
const FOREST_JADE := Color("#58BDA0")

## Festival coral. GDD 11.3: "Banners, scarves, target accents". This is the
## accent the game is allowed to spend on the thing the player must look at.
const FESTIVAL_CORAL := Color("#E85E50")

## Paper gold. GDD 11.3: "Lanterns, reward highlights".
const PAPER_GOLD := Color("#F6C86C")

## Sky blue. GDD 11.3: "Atmospheric depth and water".
const SKY_BLUE := Color("#79C7DD")

## Deep indigo. GDD 11.3: "Roofs, night and shadow anchor". The word "anchor"
## is doing real work: this is the colour shadows are pulled toward, which is
## why shadow_anchor exists below.
const DEEP_INDIGO := Color("#283B57")

## Mystic plum. GDD 11.3: "Late-game night magic". Deliberately the one colour
## that is neither warm nor cool, so a magic effect built on it cannot be
## mistaken for the festival coral the target accents use.
const MYSTIC_PLUM := Color("#624D91")

## Warm paper. GDD 11.3: "UI base, dialogue and pale surfaces".
const WARM_PAPER := Color("#F5EFDF")

## Role key -> colour. The keys are the GDD's own role names, lowercased and
## underscored, and are what the rest of the game should pass around.
const ROLES := {
	"forest_jade": FOREST_JADE,
	"festival_coral": FESTIVAL_CORAL,
	"paper_gold": PAPER_GOLD,
	"sky_blue": SKY_BLUE,
	"deep_indigo": DEEP_INDIGO,
	"mystic_plum": MYSTIC_PLUM,
	"warm_paper": WARM_PAPER,
}

## Role key -> the hex exactly as GDD 11.3 prints it. Kept beside ROLES so a
## documentation fix and a code fix cannot drift apart silently.
const HEX := {
	"forest_jade": "#58BDA0",
	"festival_coral": "#E85E50",
	"paper_gold": "#F6C86C",
	"sky_blue": "#79C7DD",
	"deep_indigo": "#283B57",
	"mystic_plum": "#624D91",
	"warm_paper": "#F5EFDF",
}

## GDD 11.3: "Strong primary colors are reserved for navigation, factions,
## major abilities and impact." That is a rule about *placement*, and it only
## holds if the palette can say what a colour is for. These are the roles the
## GDD's own table assigns, quoted so the reservation travels with the colour.
const ROLE_USES := {
	"forest_jade": "large nature masses",
	"festival_coral": "banners, scarves, target accents",
	"paper_gold": "lanterns, reward highlights",
	"sky_blue": "atmospheric depth and water",
	"deep_indigo": "roofs, night and shadow anchor",
	"mystic_plum": "late-game night magic",
	"warm_paper": "UI base, dialogue and pale surfaces",
}


# --- The three-band ramp (GDD 11.2) -------------------------------------------
#
# GDD 11.2: "Shading: 2-3 discrete diffuse bands, broad shadow shapes". Three
# bands are authored here and cel_surface.gdshader quantizes to the same three
# points, so the palette and the shader cannot disagree about what "lit" means.
#
# The ramp is expressed as gains on the authored base colour rather than as
# three separately authored colours. Two reasons. First, one authored colour per
# material keeps GDD 11.3's palette authoritative - there is no second, private
# set of shading colours to keep in sync. Second, a scalar gain cannot cross
# itself, so lit >= mid >= shadow holds for *any* base colour by construction
# rather than by tuning, which is what makes the test in tests/test_art.gd able
# to state it as an invariant instead of a sample.
#
# MID_GAIN is 1.0 on purpose: the colour an artist picks in the material
# inspector is the colour the mid band shows. Nothing else in the frame is a
# "reference" version of that surface.

const LIT_GAIN := 1.25
const MID_GAIN := 1.0
const SHADOW_GAIN := 0.6

## How far of the excess the lit band bleeds into white when a pale base clips.
## 1.0 bleeds exactly enough to stay in gamut; 0.0 would hard-clip, which turns
## a pale base into a flat wash of its brightest channel and destroys the step
## between lit and mid. Warm paper is the case that needs this - test_band_limit
## asserts the ordering survives it, and test_band_ramp asserts the pale end of
## the palette still has three visible bands.
const HOT_BLEED := 1.0

## GDD 11.3 calls deep indigo the "shadow anchor". bands_anchored() blends the
## shadow band toward it; the strength is deliberately modest, because a strong
## anchor turns every shadow in the game the same hue and the eye stops reading a
## shadow as a shadow and starts reading it as a colour.
const SHADOW_ANCHOR_BLEND := 0.35


## One material's three bands.
class Bands:
	extends RefCounted

	var lit: Color
	var mid: Color
	var shadow: Color

	func _init(p_lit: Color, p_mid: Color, p_shadow: Color) -> void:
		lit = p_lit
		mid = p_mid
		shadow = p_shadow

	## True when the bands are three genuinely different values in the right order.
	##
	## Measured as a *ratio*, not as an absolute luminance gap, because the ramp
	## is multiplicative. A near-black base has three bands whose absolute
	## luminance differences are microscopic and whose visible difference is not,
	## and an absolute threshold would reject exactly the deep-shadow colours
	## GDD 11.2 asks for. The measure is WCAG relative luminance, because a raw
	## channel sum says nothing about how much brighter one of these looks.
	func is_ordered(min_step := 0.06) -> bool:
		var y_lit := _luma(lit)
		var y_mid := _luma(mid)
		var y_shadow := _luma(shadow)
		return y_lit >= y_mid * (1.0 + min_step) and y_mid >= y_shadow * (1.0 + min_step)

	## Kept as a local helper rather than calling the outer class, because an
	## inner class calling back into its own script by name is a self-reference
	## the parser has to resolve while the script is still being defined.
	func _luma(c: Color) -> float:
		return 0.2126 * linearise(c.r) + 0.7152 * linearise(c.g) + 0.0722 * linearise(c.b)

	func linearise(channel: float) -> float:
		if channel <= 0.04045:
			return channel / 12.92
		return pow((channel + 0.055) / 1.055, 2.4)


## Scale one channel-triple by `gain`, bleeding into white rather than
## clipping. Monotone in `gain` for every input, which is the whole point: it
## is what lets bands() promise lit >= mid >= shadow without testing every
## colour anyone might ever author.
static func _ramp(base: Color, gain: float) -> Color:
	var r := base.r * gain
	var g := base.g * gain
	var b := base.b * gain
	var top := maxf(r, maxf(g, b))
	if top <= 1.0:
		return Color(r, g, b, base.a)
	var t: float = ((top - 1.0) / top) * HOT_BLEED
	return Color(
		clampf(r + (1.0 - r) * t, 0.0, 1.0),
		clampf(g + (1.0 - g) * t, 0.0, 1.0),
		clampf(b + (1.0 - b) * t, 0.0, 1.0),
		base.a
	)


## The three discrete bands GDD 11.2 asks for, derived from one authored colour.
static func bands(base: Color) -> Bands:
	return Bands.new(
		_ramp(base, LIT_GAIN),
		_ramp(base, MID_GAIN),
		_ramp(base, SHADOW_GAIN)
	)


## True when blending the shadow band toward deep indigo keeps it darker than
## the mid band for this base.
##
## This is measured rather than looked up in a table of thresholds, because the
## failure it prevents is the one thing the ramp promises never happens: an
## anchored shadow that ends up brighter than the lit side of the same surface.
## A base very close to black is the case that breaks it - its shadow band is
## nearly zero, and any blend toward a visible colour raises it. Deriving a
## constant for that would mean restating the gains in three places and hoping
## all three stay in step; this measures the real band instead.
static func shadow_anchor_is_safe(base: Color) -> bool:
	var plain := bands(base)
	var anchored := plain.shadow.lerp(DEEP_INDIGO, SHADOW_ANCHOR_BLEND)
	return relative_luminance(anchored) < relative_luminance(plain.mid)


## As bands(), with the shadow band pulled toward GDD 11.3's deep indigo so
## shadows are hue-anchored rather than merely darker. Falls back to the plain
## ramp for a base too dark to anchor, because an inverted band is worse than an
## unanchored one.
static func bands_anchored(base: Color) -> Bands:
	var plain := bands(base)
	if not shadow_anchor_is_safe(base):
		return plain
	plain.shadow = plain.shadow.lerp(DEEP_INDIGO, SHADOW_ANCHOR_BLEND)
	return plain


# --- Keeping the backdrop behind the actors (GDD 11.3) ------------------------
#
# GDD 11.3: "Keep backgrounds slightly lower contrast than the actor/target
# pair." GDD 5.4 then makes the whole combat readability contract depend on it:
# if the backdrop wins the contrast fight, the windup the player is supposed to
# read disappears into scenery. So this is a helper rather than a convention.
#
# What "lower contrast" can honestly mean here is worth writing down, because
# the naive version of it is false. Pulling a backdrop toward a fixed neutral
# always lowers its luminance contrast against an actor that sits on the *near*
# side of that neutral, and always *raises* it against one on the far side. No
# single neutral does both. So the two things this actually guarantees, for any
# colour at all, are:
#
#   * the backdrop gives up chroma, while the actor keeps its own;
#   * the backdrop's value walks toward the atmosphere neutral.
#
# The second is what the GDD means in practice on a cel-shaded arena, because on
# a flat, banded image the thing that separates a figure from a mass behind it
# is colour, not luminance. GDD 11.3 itself sets the two ends of the scale -
# festival coral and paper gold are the accents the player is meant to look at,
# forest jade, sky blue and deep indigo are the masses behind them - and
# background() moves the backdrop toward the dark end while the actor stays at
# the bright, saturated end. tests/test_art.gd pins the direction that holds,
# pins the direction that does not, and says so in the test names.

## How much of a colour's saturation a backdrop gives up. The largest single
## effect, and on this palette the one that matters: a desaturated backdrop
## stops competing with a saturated actor no matter what its luminance does.
const BACKGROUND_DESATURATE := 0.55

## How far a backdrop's value is pulled toward the atmosphere neutral.
## Desaturating alone leaves a backdrop exactly as loud as the actors in every
## way that the eye judges on a cel-shaded image.
const BACKGROUND_PULL := 0.22

## The value every backdrop is pulled toward: GDD 11.3's deep indigo - already
## the palette's "night and shadow anchor" - taken almost all the way down to
## grey. Distance in this game's palette is dark and cool, and reusing a colour
## the GDD has already given a meaning to beats inventing a new one.
static func background_base() -> Color:
	return desaturate(DEEP_INDIGO, 0.85)


## Godot 4.7's Color has no desaturate(), so the HSV saturation channel is what
## this goes through. Keeping the value and hue and dropping only saturation is
## what makes the result "less vivid" rather than "a different colour", which is
## the distinction GDD 11.3's sentence is about.
static func desaturate(c: Color, amount: float) -> Color:
	var keep := clampf(1.0 - amount, 0.0, 1.0)
	return Color.from_hsv(c.h, c.s * keep, c.v, c.a)


## HSV saturation, 0.0 to 1.0. Wrapped rather than reached for inline so callers
## do not have to remember whether Color exposes a getter for it.
static func saturation(c: Color) -> float:
	return c.s


## HSV value, the brightness a backdrop's value is measured against.
static func value_of(c: Color) -> float:
	return c.v


## A backdrop colour: its chroma drained and its value walked toward the
## atmosphere neutral. `strength` scales both moves from a full treatment down to
## none, which is how a room tunes how far back it wants to sit.
##
## The order matters and is not incidental. Pulling the value first and
## desaturating second means the saturation scale and the value pull cannot
## fight each other, and it is what makes the two guarantees above exact rather
## than approximate: the result's saturation is `c.s * (1 - DESATURATE)` and its
## value is `lerp(c.v, neutral.v, PULL)`, for any input.
static func background(c: Color, strength := 1.0) -> Color:
	var k := clampf(strength, 0.0, 1.0)
	var neutral := background_base()
	var chroma := c.s * (1.0 - BACKGROUND_DESATURATE * k)
	var value := lerpf(c.v, neutral.v, BACKGROUND_PULL * k)
	return Color.from_hsv(c.h, chroma, value, c.a)


# --- Measuring contrast --------------------------------------------------------
#
# GDD 14 asks for "color-vision-conscious scroll rarity and attack indicators",
# and GDD 11.3 asks for "color-vision-simulation passes" on screenshots. Both
# need a number rather than an opinion, so the WCAG 2.1 contrast ratio is here:
# it is linearised, it is defined for exactly this job, and it is reproducible
# outside this repository.

## WCAG relative luminance: the sRGB channels are linearised before weighting,
## because weighting gamma-encoded values is the single most common way a
## contrast number is quietly wrong.
static func relative_luminance(c: Color) -> float:
	return 0.2126 * _linearise(c.r) + 0.7152 * _linearise(c.g) + 0.0722 * _linearise(c.b)


static func _linearise(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


## WCAG contrast ratio, 1.0 for identical colours and rising without bound.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


# --- Roles and ability accents --------------------------------------------------

## The colour for a role name. Unknown names return warm paper rather than
## crashing: a mistyped role should produce a visible placeholder, not a null
## dereference three scenes away from the mistake.
static func role(name: String) -> Color:
	return ROLES.get(name.to_lower(), WARM_PAPER)


## GDD 11.4: "one readable accent color per ability family". The families are
## the ones the GDD names, and each takes the palette colour the GDD describes
## it with, so the rule and the palette agree instead of the rule being one
## sentence and the colours another. Anything unlisted falls back to festival
## coral, which GDD 11.3 reserves for "target accents" - the safest possible
## default for something the player has to notice.
const ABILITY_ACCENTS := {
	"substitution": WARM_PAPER,
	"thunder_step": PAPER_GOLD,
	"crimson_edge": FESTIVAL_CORAL,
	"shuriken": SKY_BLUE,
}


static func accent_for(ability_family: String) -> Color:
	return ABILITY_ACCENTS.get(ability_family.to_lower(), FESTIVAL_CORAL)


# --- Material factories ----------------------------------------------------------
#
# GDD 13.3 lists "Presentation: cel shader, particles, impact effects" as a
# module. These three functions are that module's authoring entry point, kept
# next to the palette so a material cannot be built with a colour that is not in
# GDD 11.3. Scripts/ and scenes/ own *placing* them; this lane owns the resources
# and the shaders.

const SURFACE_SHADER := "res://shaders/cel_surface.gdshader"
const OUTLINE_SHADER := "res://shaders/cel_outline.gdshader"
const IMPACT_SHADER := "res://shaders/impact_decals.gdshader"

## Shadow casting is switched off for outline hulls and impact decals. It is a
## property of the GeometryInstance3D, not of the Material - Godot 4's
## ShaderMaterial has no `cast_shadow` at all - so callers apply this to the
## node. Exposed here so the value lives with the shaders that need it rather
## than being retyped at every call site.
##
## A hull is a shell, not a solid: letting it cast a shadow would draw the same
## silhouette twice, once in ink and once in shade.
const NO_SHADOW := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A cel material for one authored base colour. The three gains are pushed in
## explicitly from this file rather than left at the shader's defaults, so the
## ramp a material uses is the ramp the palette documents even if somebody edits
## a default later.
static func surface_material(base: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := load(SURFACE_SHADER) as Shader
	if sh != null:
		mat.shader = sh
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("lit_gain", LIT_GAIN)
	mat.set_shader_parameter("mid_gain", MID_GAIN)
	mat.set_shader_parameter("shadow_gain", SHADOW_GAIN)
	return mat


## The inverted-hull outline for a surface. Defaults to GDD 11.3's deep indigo:
## an outline that is not darker than the thing it outlines stops separating
## the silhouette, which is the only job GDD 11.2 gives it. Set
## `node.cast_shadow = NO_SHADOW` on the hull node.
static func outline_material(width_px := 2.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := load(OUTLINE_SHADER) as Shader
	if sh != null:
		mat.shader = sh
	mat.set_shader_parameter("outline_color", DEEP_INDIGO)
	mat.set_shader_parameter("outline_width_px", width_px)
	return mat


## A short-lived impact quad. `shape` is 0 for a starburst and 1 for a slash
## crescent, the two forms GDD 11.4 names. Set `node.cast_shadow = NO_SHADOW`
## on the quad node.
static func impact_material(accent: Color, shape := 1, duration_ticks := 8) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := load(IMPACT_SHADER) as Shader
	if sh != null:
		mat.shader = sh
	mat.set_shader_parameter("accent_color", accent)
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("life_ticks", float(duration_ticks))
	return mat