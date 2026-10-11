## Headless checks for the Gate B art layer: the GDD 11.3 palette, the band ramp
## derived from it, and the shaders that consume both.
##
##     godot --headless --script res://tests/run_art_tests.gd
##
## This is a separate runner from tests/run_tests.gd rather than extra suites in
## it, because that runner's contract is "161 assertions across 13 suites" and a
## change to its suite list is not this lane's to make. Two runners also means a
## shader failure is reported as a shader failure instead of as a combat failure.
##
## What can and cannot be asserted here, stated plainly so that a green run is
## not read as more than it is. Colours, ramp ordering, contrast ratios and file
## contents are all checkable with no GPU. What a cel ramp *looks* like is not,
## and no assertion here claims otherwise. The shader checks verify that each
## file loads as a Shader, survives a structural lint, and - where a rendering
## device exists - compiles. `test_shader_checker` exists because a checker that
## passes on broken input is worse than no checker at all.
class_name TestArt
extends RefCounted

## Loaded by path rather than by class name. The global class cache is a
## generated artefact of the editor's file scan, so a fresh checkout running a
## headless script has not necessarily registered a class added since the last
## scan.
const Palette := preload("res://shaders/cel_palette.gd")

const CEL_SURFACE := "res://shaders/cel_surface.gdshader"
const CEL_OUTLINE := "res://shaders/cel_outline.gdshader"
const IMPACT_DECALS := "res://shaders/impact_decals.gdshader"

const ALL_SHADERS := [CEL_SURFACE, CEL_OUTLINE, IMPACT_DECALS]

## The seven roles GDD 11.3 lists, in the GDD's own order.
const EXPECTED_ROLES := [
	"forest_jade", "festival_coral", "paper_gold", "sky_blue",
	"deep_indigo", "mystic_plum", "warm_paper",
]

## GDD 11.2 bans by name. Each one is a material the reader would have to learn
## not to use, which is the opposite of what the GDD is asking for.
const PBR_PARAMS := ["roughness", "metallic", "fresnel", "clearcoat", "transmission", "refraction"]

## The shading language's own names, which the cross-check must not report as
## undefined functions. Kept explicit rather than derived: a derived list would
## be exactly the thing that quietly shrinks and starts flagging valid code.
const SHADER_BUILTINS := [
	"bool", "int", "uint", "float",
	"vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4", "bvec2", "bvec3", "bvec4",
	"mat2", "mat3", "mat4", "sampler2D",
	"abs", "acos", "all", "any", "asin", "atan", "ceil", "clamp", "cos", "cosh",
	"cross", "degrees", "distance", "dot", "exp", "exp2", "floor", "fract",
	"inversesqrt", "length", "log", "log2", "max", "min", "mix", "mod",
	"normalize", "pow", "radians", "reflect", "refract", "round", "sign", "sin",
	"sinh", "smoothstep", "sqrt", "step", "tan", "tanh", "texture", "textureLod",
]


# --- GDD 11.3, the palette -------------------------------------------------------

func test_palette(h: TestHarness) -> void:
	h.suite("palette")

	h.eq_int(Palette.ROLES.size(), 7, "GDD 11.3 lists seven palette roles")
	h.eq_int(Palette.HEX.size(), 7, "every role carries its documented hex")
	h.eq_int(Palette.ROLE_USES.size(), 7, "every role carries the GDD's statement of its use")

	for key in EXPECTED_ROLES:
		h.ok(Palette.ROLES.has(key), "role '%s' is present" % key)
		h.ok(Palette.ROLE_USES.has(key), "role '%s' states what GDD 11.3 uses it for" % key)
		var expected := String(Palette.HEX[key]).trim_prefix("#").to_upper()
		var actual: Color = Palette.ROLES[key]
		# Round-tripping through the 8-bit representation is the only honest
		# check available. A literal mistyped in the fourth decimal still matches
		# its intended float to within any sensible epsilon; only the byte it
		# prints as is the byte the GDD published.
		h.eq_string(actual.to_html(false).trim_prefix("#").to_upper(), expected,
			"role '%s' is the GDD's exact hex" % key)

	# GDD 11.3's table repeats no colour, and a duplicate would quietly destroy
	# the rule that strong primaries are reserved: two roles sharing a swatch
	# means neither of them is a strong primary any more.
	var seen := {}
	for key in EXPECTED_ROLES:
		var hex: String = Palette.ROLES[key].to_html(false)
		h.ok(not seen.has(hex), "role '%s' does not repeat another role's colour" % key)
		seen[hex] = key

	# role() is the lookup everything else uses, so an unknown key has to be a
	# visible placeholder rather than a null dereference three scenes away.
	h.ok(Palette.role("FOREST_JADE").is_equal_approx(Palette.FOREST_JADE),
		"role lookup is case-insensitive")
	h.ok(Palette.role("not_a_role").is_equal_approx(Palette.WARM_PAPER),
		"an unknown role falls back to a visible placeholder, not to nothing")

	# GDD 11.4: "one readable accent color per ability family". The families the
	# GDD names, each taking the palette colour the GDD describes it with, so the
	# rule and the palette are the same statement rather than two.
	h.ok(Palette.accent_for("thunder_step").is_equal_approx(Palette.PAPER_GOLD),
		"Thunder Step takes paper gold: GDD 11.4's 'zigzag gold-white stroke'")
	h.ok(Palette.accent_for("crimson_edge").is_equal_approx(Palette.FESTIVAL_CORAL),
		"Crimson Edge takes festival coral: GDD 11.4's 'limited coral ribbon'")
	h.ok(Palette.accent_for("substitution").is_equal_approx(Palette.WARM_PAPER),
		"Substitution takes warm paper: GDD 11.4's 'rice-paper smoke puff'")
	h.ok(Palette.accent_for("impact").is_equal_approx(Palette.FESTIVAL_CORAL),
		"an unlisted family defaults to coral, which GDD 11.3 reserves for target accents")

	var accents := {}
	for family in Palette.ABILITY_ACCENTS:
		accents[Palette.ABILITY_ACCENTS[family].to_html(false)] = family
	h.eq_int(accents.size(), Palette.ABILITY_ACCENTS.size(),
		"each of GDD 11.4's named ability families owns a distinct accent colour")


# --- GDD 11.2, the three discrete bands ------------------------------------------

## A spread of authorable base colours: near-black, night, mid, saturated
## primaries and two near-whites. Capped below full brightness on purpose -
## test_band_limit covers why, since a base whose brightest channel is already
## 1.0 has no room above it for a lit band.
const SPREAD := [
	Color(0.02, 0.02, 0.02),
	Color(0.10, 0.12, 0.20),
	Color(0.30, 0.55, 0.85),
	Color(0.85, 0.20, 0.20),
	Color(0.95, 0.60, 0.10),
	Color(0.20, 0.60, 0.45),
	Color(0.55, 0.55, 0.55),
	Color(0.80, 0.80, 0.78),
	Color(0.94, 0.93, 0.90),
]

## The smallest *relative* luminance step the tests accept between neighbouring
## bands - each band has to be at least this much brighter than the one below it.
## Relative, because the ramp is multiplicative and a near-black base has three
## bands whose absolute gaps are invisible while their ratios are not.
const MIN_BAND_STEP := 0.06


func test_band_ramp(h: TestHarness) -> void:
	h.suite("band_ramp")

	# The GDD's own palette first, because that is what actually gets shaded.
	for key in EXPECTED_ROLES:
		var base: Color = Palette.ROLES[key]
		var b := Palette.bands(base)
		h.ok(b.lit != b.mid, "%s has a lit band distinct from its mid band" % key)
		h.ok(b.mid != b.shadow, "%s has a mid band distinct from its shadow band" % key)
		h.ok(b.is_ordered(MIN_BAND_STEP), "%s bands run lit >= mid >= shadow" % key)

	for base in SPREAD:
		var label := "(%.2f, %.2f, %.2f)" % [base.r, base.g, base.b]
		var b := Palette.bands(base)
		h.ok(b.is_ordered(MIN_BAND_STEP),
			"spread base %s bands run lit >= mid >= shadow" % label)
		h.ok(b.lit != b.mid and b.mid != b.shadow,
			"spread base %s produces three different colours" % label)

	# MID_GAIN is 1.0 on purpose: the colour an author picks in the inspector is
	# the colour the mid band shows, so nothing else in the frame is a second
	# "reference" version of the surface.
	h.ok(Palette.bands(Palette.FOREST_JADE).mid.is_equal_approx(Palette.FOREST_JADE),
		"the mid band is the authored colour, unmodified")
	h.eq_float(Palette.MID_GAIN, 1.0, "MID_GAIN stays at 1.0")
	h.ok(Palette.LIT_GAIN > Palette.MID_GAIN, "the lit gain is above the mid gain")
	h.ok(Palette.MID_GAIN > Palette.SHADOW_GAIN, "the mid gain is above the shadow gain")

	# The ramp is what the shader quantizes to, so the two files have to agree.
	# A ramp that differs between the palette and the shader is exactly the kind
	# of drift nobody notices until a screenshot looks slightly wrong.
	var lit := _float_uniform_default(_code(CEL_SURFACE), "lit_gain")
	var mid := _float_uniform_default(_code(CEL_SURFACE), "mid_gain")
	var shadow := _float_uniform_default(_code(CEL_SURFACE), "shadow_gain")
	h.ok(absf(lit - Palette.LIT_GAIN) < 0.001,
		"cel_surface's lit_gain default matches CelPalette.LIT_GAIN")
	h.ok(absf(mid - Palette.MID_GAIN) < 0.001,
		"cel_surface's mid_gain default matches CelPalette.MID_GAIN")
	h.ok(absf(shadow - Palette.SHADOW_GAIN) < 0.001,
		"cel_surface's shadow_gain default matches CelPalette.SHADOW_GAIN")

	# GDD 11.3 calls deep indigo the "shadow anchor"; shadow_anchor_is_safe is
	# the guard that keeps anchoring from inverting a dark ramp.
	for key in EXPECTED_ROLES:
		var base: Color = Palette.ROLES[key]
		h.ok(Palette.shadow_anchor_is_safe(base),
			"%s is dark enough to anchor its shadow without inverting the ramp" % key)
		var anchored := Palette.bands_anchored(base)
		var plain := Palette.bands(base)
		h.ok(Palette.relative_luminance(anchored.shadow) < Palette.relative_luminance(anchored.mid),
			"anchored %s shadow still sits below its mid band" % key)
		h.ok(anchored.shadow != plain.shadow, "%s shadow is actually anchored" % key)
		h.ok(anchored.lit.is_equal_approx(plain.lit) and anchored.mid.is_equal_approx(plain.mid),
			"anchoring %s only touches the shadow band" % key)

	# A base too dark to anchor falls back rather than emitting an inverted band.
	var near_black := Color(0.01, 0.01, 0.01)
	h.ok(not Palette.shadow_anchor_is_safe(near_black),
		"a near-black base is rejected as a shadow anchor")
	h.ok(Palette.bands_anchored(near_black).shadow.is_equal_approx(Palette.bands(near_black).shadow),
		"an unanchorable base falls back to the plain ramp")


func test_band_limit(h: TestHarness) -> void:
	h.suite("band_limit")

	# The ramp is multiplicative, so a base whose brightest channel is already
	# 1.0 has nothing above it and the lit band collapses onto the mid one. That
	# is a real limit of the technique rather than a bug, and the useful thing to
	# do is state it and pin it rather than let it surface later as a mysterious
	# two-tone surface nobody can explain.
	var white := Palette.bands(Color(1.0, 1.0, 1.0))
	h.ok(white.lit == white.mid, "a full-brightness base has no lit band above its mid band")
	h.ok(white.is_ordered(0.0), "even that collapsed case stays ordered rather than inverted")

	# GDD 11.3's palest role is warm paper at 0.961, which is the practical
	# ceiling: it is the brightest colour the palette ships and it still carries
	# three visible bands.
	var paper: Color = Palette.WARM_PAPER
	h.ok(maxf(paper.r, maxf(paper.g, paper.b)) < 1.0,
		"warm paper's brightest channel leaves headroom above it")
	h.ok(Palette.bands(paper).is_ordered(MIN_BAND_STEP),
		"warm paper, the GDD's palest role, still has three ordered bands")


# --- GDD 11.3, keeping the backdrop behind the actors ----------------------------

## Actor/target pairs against the backdrops GDD 11.3 pairs them with. An actor
## is something the player must read; a backdrop is a mass it must not compete
## with. Built by a function rather than a const because a const initialiser
## reaching through a preloaded script is not worth relying on.
##
## Every pair is drawn from GDD 11.3's own role assignments: festival coral is
## "target accents" and paper gold is "reward highlights", and they are read
## against the three things the GDD calls large masses - forest jade, sky blue
## and deep indigo. Warm paper is deliberately not an actor here: GDD 11.3 gives
## it to the UI and pale surfaces, and it has almost no chroma to separate with.
static func pairs() -> Array:
	return [
		[Palette.FOREST_JADE, Palette.FESTIVAL_CORAL],
		[Palette.SKY_BLUE, Palette.FESTIVAL_CORAL],
		[Palette.DEEP_INDIGO, Palette.FESTIVAL_CORAL],
		[Palette.DEEP_INDIGO, Palette.PAPER_GOLD],
		[Palette.MYSTIC_PLUM, Palette.PAPER_GOLD],
	]

## How much more saturated the actor has to stay than its dimmed backdrop. On a
## cel-shaded image the actor's advantage over a backdrop is mostly chroma: the
## backdrop is flat and banded like everything else, so what makes the actor read
## is that its colour is still saturated while the mass behind it has been
## drained. The number is the measured floor across the pairs above, rounded
## down.
const MIN_ACTOR_CHROMA := 2.0


func test_background(h: TestHarness) -> void:
	h.suite("background")

	var neutral: Color = Palette.background_base()
	h.ok(Palette.saturation(neutral) < 0.2,
		"the atmosphere neutral is GDD 11.3's deep indigo taken almost to grey")

	# The two properties CelPalette.background() guarantees for any colour at
	# all. If either of these stops holding the helper's contract is wrong, not
	# the scene that used it.
	for key in EXPECTED_ROLES:
		var c: Color = Palette.ROLES[key]
		var dimmed: Color = Palette.background(c)
		var was := absf(Palette.value_of(c) - Palette.value_of(neutral))
		var now := absf(Palette.value_of(dimmed) - Palette.value_of(neutral))
		h.ok(Palette.saturation(dimmed) < Palette.saturation(c),
			"background(%s) gives up chroma" % key)
		h.ok(now <= was + 0.0001,
			"background(%s) ends no further from the atmosphere neutral's value" % key)
		# Deep indigo is the one role that already sits at the neutral, because
		# the neutral is derived from it, so for that one "no further" is the
		# whole of the guarantee and there is nothing to move.
		h.ok(now < was or was < 0.001,
			"background(%s) moves its value toward the atmosphere neutral" % key)

	# strength = 0 must be a genuine no-op, or "slightly lower contrast" has no
	# dial and every backdrop gets the full treatment.
	var jade: Color = Palette.FOREST_JADE
	h.ok(Palette.background(jade, 0.0).is_equal_approx(jade),
		"background at strength 0 changes nothing")

	# GDD 11.3: "Keep backgrounds slightly lower contrast than the actor/target
	# pair." Asserted per pair, because it is a statement about a relationship and
	# not about a single colour.
	for pair in pairs():
		var backdrop: Color = pair[0]
		var actor: Color = pair[1]
		var before := Palette.contrast_ratio(actor, backdrop)
		var after := Palette.contrast_ratio(actor, Palette.background(backdrop))
		h.ok(after < before,
			"dimming %s lowers its contrast against the %s actor (%.3f -> %.3f)"
			% [backdrop.to_html(false), actor.to_html(false), before, after])

	# And the actor still wins the frame. Without this, "lower contrast" could be
	# satisfied by flattening both sides until nothing reads at all, which is the
	# failure mode GDD 5.4 is actually about. Measured as chroma because on a
	# cel-shaded arena it is chroma that separates an actor from a backdrop that
	# shares its band structure.
	var worst_chroma := 99.0
	for pair in pairs():
		var backdrop: Color = pair[0]
		var actor: Color = pair[1]
		var backdrop_chroma := Palette.saturation(Palette.background(backdrop))
		var actor_chroma := Palette.saturation(actor)
		worst_chroma = minf(worst_chroma, actor_chroma / maxf(backdrop_chroma, 0.0001))
	h.ok(worst_chroma >= MIN_ACTOR_CHROMA,
		"the actor stays far more saturated than its backdrop at every pair (worst %.2fx)"
		% worst_chroma)

	# The limitation, pinned rather than left to be discovered. Pulling a
	# backdrop toward a fixed neutral *raises* its luminance contrast against an
	# actor that sits on the far side of that neutral. Paper gold is brighter
	# than forest jade, so dimming the jade moves it away from the gold.
	#
	# Stated because CelPalette.background() cannot fix it: no fixed neutral
	# lowers contrast against actors on both sides of it. The chroma separation
	# above is what covers this case, and a scene that needs more than that has
	# to place the backdrop, not tint it.
	var high_actor := Palette.PAPER_GOLD
	var low_actor := Palette.FOREST_JADE
	var before := Palette.contrast_ratio(high_actor, low_actor)
	var after := Palette.contrast_ratio(high_actor, Palette.background(low_actor))
	h.ok(after > before,
		"KNOWN LIMIT: dimming a backdrop raises its contrast against a brighter actor (%.3f -> %.3f)"
		% [before, after])

	h.ok(Palette.contrast_ratio(Color(0.0, 0.0, 0.0), Color(1.0, 1.0, 1.0)) > 20.0,
		"contrast_ratio is the WCAG form and separates the extremes")
	h.ok(absf(Palette.contrast_ratio(Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5)) - 1.0) < 0.001,
		"contrast_ratio of a colour against itself is 1.0")


# --- The shaders ------------------------------------------------------------------

func test_shader_files(h: TestHarness) -> void:
	h.suite("shader_files")

	for path in ALL_SHADERS:
		h.ok(FileAccess.file_exists(path), "%s exists" % path)
		var res: Resource = load(path)
		h.ok(res is Shader, "%s loads as a Shader" % path)
		if res is Shader:
			h.ok(not (res as Shader).code.strip_edges().is_empty(),
				"%s carries shader source" % path)
		var problem := shader_problem(path)
		h.ok(problem.is_empty(), "%s passes the shader check%s"
			% [path, "" if problem.is_empty() else " - " + problem])

	var surface := _code(CEL_SURFACE)
	var outline := _code(CEL_OUTLINE)
	var impact := _code(IMPACT_DECALS)

	h.ok(surface.contains("shader_type spatial;"), "cel_surface is a spatial shader")
	h.ok(_render_mode(surface).contains("specular_disabled"),
		"GDD 11.2 forbids PBR highlights, so cel_surface disables the specular lobe")
	h.ok(_render_mode(surface).contains("cull_back"), "cel_surface culls back faces")
	h.ok(_render_mode(surface).contains("ambient_light_disabled"),
		"cel_surface owns its ambient, so the bands are not lifted by the environment")

	for banned in PBR_PARAMS:
		h.ok(not _declares_uniform(surface, banned),
			"cel_surface declares no '%s' parameter" % banned)
		h.ok(not _reads_builtin(surface, banned),
			"cel_surface never reads the %s built-in" % banned.to_upper())
	h.ok(not _reads_builtin(outline, "roughness"), "cel_outline has no roughness term")
	h.ok(not _reads_builtin(impact, "roughness"), "impact decals have no roughness term")

	h.ok(_declares_uniform(surface, "band_count"),
		"GDD 11.2's band count is authorable without editing the shader")
	h.ok(_declares_uniform(surface, "band_softness"),
		"the band edge width is authorable without editing the shader")
	h.eq_int(_int_uniform_default(surface, "band_count"), 3,
		"cel_surface defaults to GDD 11.2's three bands")

	# The diffuse term has to be quantized. GDD 11.2 rules out a gradient, so
	# this checks the arithmetic that produces discrete stops and separately
	# checks that no smoothstep is ever applied to the lighting term.
	h.ok(surface.contains("floor("), "cel_surface quantizes the diffuse term")
	h.ok(_regex("smoothstep\\([^)]*\\bndl\\b").search(surface) == null,
		"cel_surface never smoothsteps the diffuse term into a gradient")
	h.ok(surface.contains("ATTENUATION"),
		"cel_surface reads the engine's shadow attenuation, so cast shadows cut the bands")

	h.ok(_render_mode(outline).contains("cull_front"),
		"cel_outline is an inverted hull: it culls front faces")
	h.ok(_render_mode(outline).contains("unshaded"),
		"cel_outline is unlit, so the ink keeps the colour it was authored with")
	h.ok(outline.contains("POSITION = clip;"),
		"cel_outline writes clip space, which is what makes the width distance-stable")
	h.ok(outline.contains("VIEWPORT_SIZE"),
		"cel_outline measures its offset in pixels, so width does not grow with range")
	for name in ["outline_width_px", "outline_strength", "outline_color", "min_width_px"]:
		h.ok(_declares_uniform(outline, name), "cel_outline exposes %s" % name)

	h.ok(_render_mode(impact).contains("unshaded"), "impact decals are unlit")
	h.ok(_render_mode(impact).contains("blend_add"),
		"impact decals blend additively, so they cannot darken or hide a windup")
	for name in ["life_ticks", "age_ticks", "size_m", "max_size_m", "alpha_cap", "accent_color"]:
		h.ok(_declares_uniform(impact, name), "impact decals expose %s" % name)
	h.ok(impact.contains("discard;"), "the readability cap is enforced by discarding")
	h.ok(_regex("if\\s*\\(\\s*t\\s*>=\\s*1\\.0\\s*\\)").search(impact) != null,
		"a decal cannot outlive its own lifetime")


func test_material_factories(h: TestHarness) -> void:
	h.suite("materials")

	var surface := Palette.surface_material(Palette.FOREST_JADE)
	h.ok(surface is ShaderMaterial, "surface_material builds a ShaderMaterial")
	if surface is ShaderMaterial:
		var mat := surface as ShaderMaterial
		h.ok(mat.shader != null, "surface_material has cel_surface attached")
		var base: Color = mat.get_shader_parameter("base_color")
		h.ok(base.is_equal_approx(Palette.FOREST_JADE), "surface_material carries the base colour")
		h.ok(absf(float(mat.get_shader_parameter("lit_gain")) - Palette.LIT_GAIN) < 0.001,
			"surface_material pushes the palette's lit gain, not the shader's default")

	var outline := Palette.outline_material(3.0)
	h.ok(outline is ShaderMaterial, "outline_material builds a ShaderMaterial")
	if outline is ShaderMaterial:
		var mat := outline as ShaderMaterial
		h.ok(mat.shader != null, "outline_material has cel_outline attached")
		var ink: Color = mat.get_shader_parameter("outline_color")
		h.ok(ink.is_equal_approx(Palette.DEEP_INDIGO),
			"the default outline ink is GDD 11.3's deep indigo shadow anchor")

	h.eq_int(Palette.NO_SHADOW, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the palette exports the shadow-casting setting an outline hull needs")

	var impact := Palette.impact_material(Palette.accent_for("thunder_step"))
	h.ok(impact is ShaderMaterial, "impact_material builds a ShaderMaterial")
	if impact is ShaderMaterial:
		var mat := impact as ShaderMaterial
		h.ok(mat.shader != null, "impact_material has impact_decals attached")
		var accent: Color = mat.get_shader_parameter("accent_color")
		h.ok(accent.is_equal_approx(Palette.PAPER_GOLD),
			"impact_material carries the ability family's accent colour")


# --- The checker itself ------------------------------------------------------------

## Scratch directory for the negative-control shaders, under user:// so a
## deliberately broken shader never exists inside the repository, where a stray
## .gdshader would be picked up by the next import scan.
const SCRATCH := "user://art_shader_check"

## A structurally valid spatial shader, used as the checker's control. If the
## checker rejects this, the checker is wrong.
const GOOD_SHADER := """shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	ALBEDO = base_color.rgb;
}
"""


func test_shader_checker(h: TestHarness) -> void:
	h.suite("shader_checker")

	DirAccess.make_dir_recursive_absolute(SCRATCH)

	h.ok(shader_problem(_write_scratch("good.gdshader", GOOD_SHADER)).is_empty(),
		"the checker passes a known-good shader")

	# Each of these is a way one of the real shaders could be wrong. If the
	# checker cannot tell them from the good one, it is not checking anything and
	# every "passes the shader check" line above is worthless.
	var broken := [
		["missing_file", ""],
		["not_a_shader", "this is not shader source at all\n"],
		["wrong_shader_type", "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n"],
		["no_shader_type", "void fragment() { ALBEDO = vec3(1.0); }\n"],
		["no_render_mode", "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0); }\n"],
		["unbalanced_brace", "shader_type spatial;\nrender_mode cull_back;\nvoid fragment() { ALBEDO = vec3(1.0);\n"],
		["unbalanced_paren", "shader_type spatial;\nrender_mode cull_back;\nvoid fragment() { ALBEDO = vec3(1.0; }\n"],
		["unterminated_string", "shader_type spatial;\nrender_mode cull_back;\nuniform vec4 c = vec4(\"oops);\nvoid fragment() { ALBEDO = vec3(1.0); }\n"],
		["no_fragment", "shader_type spatial;\nrender_mode cull_back;\nvoid vertex() { POSITION = vec4(0.0); }\n"],
		["pbr_uniform", "shader_type spatial;\nrender_mode cull_back;\nuniform float roughness = 0.5;\nvoid fragment() { ALBEDO = vec3(roughness); }\n"],
		["undefined_function", "shader_type spatial;\nrender_mode cull_back;\nvoid fragment() { ALBEDO = cel_band(0.5); }\n"],
		# Structurally perfect and still unbuildable. This is the case the lint
		# alone cannot see, which is why the compile step exists.
		["undefined_builtin", "shader_type spatial;\nrender_mode cull_back;\nuniform float a = 1.0;\nvoid fragment() { ALBEDO = vec3(NO_SUCH_BUILTIN * a); }\n"],
	]
	for entry in broken:
		var name: String = entry[0]
		var problem := shader_problem(_write_scratch("%s.gdshader" % name, String(entry[1])))
		h.ok(not problem.is_empty(), "the checker rejects a shader with %s" % name)
		if not problem.is_empty():
			print("      (%s -> %s)" % [name, problem])

	for child in _scratch_files():
		DirAccess.remove_absolute(child)


func _scratch_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SCRATCH)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			out.append(SCRATCH.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _write_scratch(filename: String, source: String) -> String:
	var path := SCRATCH.path_join(filename)
	# An empty source is the deliberately missing file: that is what an
	# unfinished lane looks like to CI, and it is worth being caught.
	if source.is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return path
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(source)
		f.close()
	return path


# --- The checker --------------------------------------------------------------------

## Returns an empty string when the shader at `path` is sound, or a description
## of what is wrong with it. Never returns null and never throws: a checker that
## dies on bad input reports nothing about it.
##
## What it checks, in order:
##   1. the file exists and has source;
##   2. it loads as a Shader resource, catching format and encoding problems;
##   3. it declares a spatial shader type and a render mode;
##   4. braces, parentheses and strings balance;
##   5. it defines the entry points it must, and every function it calls;
##   6. where a rendering device exists, the shader goes to the renderer and has
##      to come back with a compiled uniform list.
##
## Step 6 is what catches a genuine compile error, and it is skipped under the
## headless dummy renderer, which compiles nothing. That is exactly why step 5
## is here: under `--headless` the definition cross-check is what stands in for
## the compiler, and test_shader_checker proves that it discriminates rather than
## passing everything.
static func shader_problem(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "file not found"
	var source := _read(path)
	if source.strip_edges().is_empty():
		return "file is empty"

	var res: Resource = load(path)
	if res == null:
		return "did not load as a resource"
	if not res is Shader:
		return "loaded as %s, not a Shader" % res.get_class()
	if (res as Shader).code.strip_edges().is_empty():
		return "loaded as a Shader with no code"

	var code := _strip_comments(source)
	if not code.contains("shader_type spatial;"):
		return "does not declare 'shader_type spatial;'"
	if not code.contains("render_mode"):
		return "declares no render_mode"
	if not _balanced(code, "{"):
		return "unbalanced braces"
	if not _balanced(code, "("):
		return "unbalanced parentheses"
	if not _even(code, "\""):
		return "unterminated string"

	if not code.contains("void fragment("):
		return "defines no fragment() entry point"

	for banned in PBR_PARAMS:
		if _declares_uniform(code, banned):
			return "declares a '%s' parameter, which GDD 11.2 rules out" % banned
		if _reads_builtin(code, banned):
			return "reads the %s built-in, which GDD 11.2 rules out" % banned.to_upper()

	for fn in _called_functions(code):
		if not _defines_function(code, fn):
			return "calls %s() but never defines it" % fn

	var compiled := _compile_problem(source)
	if not compiled.is_empty():
		return compiled
	return ""


## Hand the shader to the renderer and see whether it comes back.
##
## Under `--headless` the rendering device is the dummy driver, and the dummy
## driver does run the shading language: it reports parse and compile failures
## on stderr and refuses the program. What it does not do is report them back
## through an API, so an empty uniform list is the signal available here. Every
## shader in shaders/ declares uniforms, which is what makes that signal usable.
static func _compile_problem(source: String) -> String:
	var sh := Shader.new()
	sh.code = source
	if sh.get_shader_uniform_list().is_empty():
		return "the renderer compiled no uniforms from it"
	return ""


static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


## The file with its comments removed, so that a word in a GDD citation cannot be
## mistaken for code. The content checks below all read this, not the raw file.
static func _code(path: String) -> String:
	return _strip_comments(_read(path))


## Comments out, preserving string literals and line structure. Strings matter
## because a "//" inside one is not a comment.
static func _strip_comments(source: String) -> String:
	var out := ""
	var i := 0
	var in_string := false
	var in_block := false
	var in_line := false
	var quote := ""
	while i < source.length():
		var c := source[i]
		if in_line:
			out += c if c == "\n" else " "
			if c == "\n":
				in_line = false
		elif in_block:
			if c == "*" and i + 1 < source.length() and source[i + 1] == "/":
				in_block = false
				out += "  "
				i += 2
				continue
			out += c if c == "\n" else " "
		elif in_string:
			out += c
			if c == quote:
				in_string = false
		elif c == "/" and i + 1 < source.length() and source[i + 1] == "/":
			in_line = true
			out += "  "
			i += 2
			continue
		elif c == "/" and i + 1 < source.length() and source[i + 1] == "*":
			in_block = true
			out += "  "
			i += 2
			continue
		else:
			if c == "\"":
				in_string = true
				quote = c
			out += c
		i += 1
	return out


static func _balanced(code: String, token: String) -> bool:
	var depth := 0
	var i := 0
	while i < code.length():
		if code[i] == token:
			depth += 1
		elif code[i] == _closer(token):
			depth -= 1
			if depth < 0:
				return false
		i += 1
	return depth == 0


static func _closer(token: String) -> String:
	match token:
		"{": return "}"
		"(": return ")"
		_: return ""


static func _even(code: String, token: String) -> bool:
	return code.count(token) % 2 == 0


## Every `name(` that is neither a definition, a keyword, nor a built-in.
##
## Uniform declarations are blanked out first. `hint_range(1.0, 2.0)` is
## indistinguishable from a call by text alone, and a naive scan reports the
## hint as an undefined function on every shader that uses one.
static func _called_functions(code: String) -> Array[String]:
	var re := _regex("[A-Za-z_][A-Za-z_0-9]*\\s*\\(")
	var keywords := ["if", "for", "while", "switch", "return", "else", "do"]
	var body := _without_uniform_declarations(code)
	var out: Array[String] = []
	for m in re.search_all(body):
		var name := m.get_string(0).strip_edges().trim_suffix("(").strip_edges()
		if name.is_empty() or keywords.has(name) or SHADER_BUILTINS.has(name):
			continue
		if _defines_function(code, name):
			continue
		if not out.has(name):
			out.append(name)
	return out


## Blanks out every `uniform ...;` declaration, which ends at the first semicolon
## however many lines it spans.
static func _without_uniform_declarations(code: String) -> String:
	return _regex("\\b(?:global\\s+)?uniform\\b[^;]*;").sub(code, " ", true)


## Compiled pattern. Godot 4.7's RegEx has no constructor that takes a pattern,
## so every pattern in this file goes through here rather than through a
## compile() call two lines later - one place to notice if the API moves again.
static func _regex(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


static func _defines_function(code: String, name: String) -> bool:
	return _regex("(void|float|int|uint|bool|vec2|vec3|vec4|ivec2|ivec3|ivec4"
		+ "|bvec2|bvec3|bvec4|mat2|mat3|mat4)\\s+%s\\s*\\(" % name).search(code) != null


static func _declares_uniform(code: String, name: String) -> bool:
	return _regex("uniform\\s+\\w+\\s+%s\\b" % name).search(code) != null


## True when the shader reads the built-in of that name, e.g. ROUGHNESS. The
## underscore is excluded from the surrounding characters so SPECULAR_LIGHT,
## which the cel shader deliberately zeroes, is not mistaken for a specular lobe.
static func _reads_builtin(code: String, name: String) -> bool:
	var re := _regex("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % name.to_upper())
	return re.search(code) != null


static func _float_uniform_default(code: String, name: String) -> float:
	var re := _regex("uniform\\s+float\\s+%s\\b[^;=]*=\\s*(-?[0-9]*\\.?[0-9]+)\\s*;" % name)
	var m := re.search(code)
	return 0.0 if m == null else float(m.get_string(1))


static func _int_uniform_default(code: String, name: String) -> int:
	var re := _regex("uniform\\s+int\\s+%s\\b[^;=]*=\\s*(-?[0-9]+)\\s*;" % name)
	var m := re.search(code)
	return -1 if m == null else int(m.get_string(1))


static func _render_mode(code: String) -> String:
	for line in code.split("\n"):
		if line.strip_edges().begins_with("render_mode"):
			return line
	return ""