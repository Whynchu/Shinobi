// Cel-shaded surface for characters and environment. GDD 11.1 (LOCKED):
// "Bright GameCube-era stylization ... readable cel shading ... clear warm/cool
// light separation." GDD 11.2: "Shading: 2-3 discrete diffuse bands, broad
// shadow shapes, minimal roughness detail, subtle ambient fill and selective
// rim lights for silhouettes. Outlines should be thin and distance-stable or
// omitted where environmental edges already read. No heavy PBR reflections or
// high-frequency terrain detail."
//
// Pair with cel_outline.gdshader, which is the inverted hull that goes with
// this surface. They are two materials on purpose: GDD 11.2 says outlines may
// be "omitted where environmental edges already read", which is only possible
// if the outline is something an author chooses to add rather than a mode a
// surface is forced into. Build both through CelPalette so the band gains here
// and the ramp in cel_palette.gd cannot drift apart.
//
// Outlines are NOT applied from this shader. render_mode is fixed at compile
// time, and an inverted hull needs cull_front while a lit surface needs
// cull_back. Cramming both into one file with cull_disabled would double the
// fragment cost of every surface in the arena to serve an effect most
// environment geometry should not have.
//
// Deliberately absent, per GDD 11.2's "no heavy PBR reflections" and "minimal
// roughness detail": there is no roughness parameter, no metalness, no
// environment reflection and no specular lobe. `specular_disabled` is a render
// mode rather than a parameter precisely so that no amount of inspector
// tweaking can put a highlight back on a chibi ninja.
//
// The ramp is computed here and written to DIFFUSE_LIGHT, not to ALBEDO. That
// is not a style preference. GDD 5.4 needs enemy silhouettes to stay readable
// against a lit arena, which means several lights in the same frame (a warm key
// and a cool fill is what GDD 11.1 asks for). ALBEDO is read-only inside light()
// and is shared by every light, so writing the band there would leave the last
// light processed deciding the colour of the surface and make the band depend
// on light order. DIFFUSE_LIGHT is per-light, so each light contributes its own
// band and they accumulate the way a painter stacks passes.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled, fog_disabled;

// --- The authored surface colour (GDD 11.3) -----------------------------------

// One colour from GDD 11.3's table. This is the MID band: what you see where
// the surface faces the key light without being squarely in it. Keep it white
// unless a scene wants every surface tinted by one multiplier.
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Multiplies the final band colour. GDD 11.2 allows textures "where used" to
// "emphasize purposeful painted accents", which is a modulation job, not a
// replacement for base_color.
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Fold per-vertex colour into the albedo. Off by default because a primitive
// with no colour array has no vertex colour to read, and the default then
// depends on engine internals rather than on anything this file states.
uniform bool use_vertex_color = false;

// --- The band ramp --------------------------------------------------------------

// GDD 11.2 asks for "2-3 discrete diffuse bands". Two gives the flat,
// poster-like read the GDD's GameCube reference implies; three is the default
// because it is what "broad shadow shapes" needs - with two bands there is no
// middle and the terminator lands wherever the light lands.
uniform int band_count : hint_range(2, 3) = 3;

// How wide the edge of a band is, in band units. GDD 11.2's rule is that the
// diffuse term is quantized and NOT smoothed into a gradient, so this is a
// hairline for antialiasing the terminator, not a look. Anything above about
// 0.15 turns the ramp back into the gradient the GDD rules out.
uniform float band_softness : hint_range(0.0, 0.25) = 0.05;

// The three stops. These are gains on base_color, not three separately authored
// colours, and they are the same numbers as CelPalette.LIT_GAIN / MID_GAIN /
// SHADOW_GAIN. tests/test_art.gd parses these literals out of this file and
// asserts they still match, because a ramp that differs between the palette and
// the shader is the kind of drift nobody notices until a screenshot looks
// slightly wrong.
uniform float lit_gain : hint_range(1.0, 2.0) = 1.25;
uniform float mid_gain : hint_range(0.5, 1.5) = 1.0;
uniform float shadow_gain : hint_range(0.0, 1.0) = 0.6;

// How far of the excess a pale base bleeds into white rather than clipping.
// Mirrors CelPalette.HOT_BLEED, which is fixed at 1.0 and derived in the
// comments there; a hard clip would turn warm paper's lit band into a flat
// wash and remove the step between lit and mid.
uniform float hot_bleed : hint_range(0.0, 1.0) = 1.0;

// N.L remapped before it is quantized. GDD 11.1 wants a bright, cheerful read
// rather than a moody one, so a little wrap keeps the terminator off the
// darkest values. Kept small: at 1.0 the shadow band disappears entirely.
uniform float light_wrap : hint_range(0.0, 0.5) = 0.12;

// Scales the key light's contribution. The GDD wants bright, not clipped.
uniform float light_gain : hint_range(0.0, 2.0) = 1.0;

// Ceiling on how much one light can push a band, so a strong sun does not push
// every lit surface past white and flatten the ramp.
uniform float light_energy_max : hint_range(0.1, 3.0) = 1.2;

// --- Ambient fill (GDD 11.2) ----------------------------------------------------

// GDD 11.2: "subtle ambient fill". The point is stated in the same sentence as
// the bands, so it is not optional decoration: a shadow that falls to black
// stops reading as a shadow and starts reading as a hole in the model, which is
// exactly what makes a chibi silhouette unreadable.
uniform vec4 ambient_sky : source_color = vec4(0.62, 0.7, 0.78, 1.0);
uniform vec4 ambient_bounce : source_color = vec4(0.72, 0.62, 0.48, 1.0);
uniform float ambient_fill : hint_range(0.0, 1.0) = 0.16;

// Hemisphere split between the two. GDD 11.1 asks for "clear warm/cool light
// separation"; the cool sky above and the warm bounce below is where that lives
// now that the sun's own colour is not tinting the bands.

// --- Rim light (GDD 11.2) ---------------------------------------------------------

// GDD 11.2: "selective rim lights for silhouettes". Selective means authored,
// not automatic: set this to 0 on environment surfaces whose edges already read
// against their neighbours, which is the second half of the same GDD sentence.
uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_start : hint_range(0.0, 1.0) = 0.55;


float cel_band(float ndl) {
	float levels = max(float(band_count), 2.0);
	float scaled = clamp(ndl, 0.0, 1.0) * levels;
	float whole = floor(scaled);
	// The discrete part is the whole number of bands stepped through. The
	// fractional part is added scaled by band_softness, so it can only ever
	// shave a hairline off the edge of a band. It cannot spread into a
	// gradient, because it is multiplied by a value the author is told to keep
	// below 0.15.
	float discrete = whole / (levels - 1.0);
	float edge = (scaled - whole) * (band_softness / levels);
	return clamp(discrete + edge, 0.0, 1.0);
}


vec3 cel_step(vec3 base, float gain) {
	vec3 scaled = base * gain;
	float top = max(scaled.r, max(scaled.g, scaled.b));
	if (top <= 1.0) {
		return scaled;
	}
	// Bleed the excess into white instead of clipping. Monotone in gain, which
	// is what keeps lit >= mid >= shadow for every base colour rather than for
	// the ones somebody happened to test.
	float t = ((top - 1.0) / top) * hot_bleed;
	return clamp(scaled + (vec3(1.0) - scaled) * t, vec3(0.0), vec3(1.0));
}


vec3 cel_ramp(float t) {
	vec3 shadow_col = cel_step(base_color.rgb, shadow_gain);
	vec3 mid_col = cel_step(base_color.rgb, mid_gain);
	vec3 lit_col = cel_step(base_color.rgb, lit_gain);
	vec3 lower = mix(shadow_col, mid_col, clamp(t * 2.0, 0.0, 1.0));
	return mix(lower, lit_col, clamp(t * 2.0 - 1.0, 0.0, 1.0));
}


void light() {
	// NORMAL and LIGHT are both view space, so this needs no matrix.
	float ndl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	ndl = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);

	// ATTENUATION is documented as "attenuation based on distance or shadow",
	// and LIGHT_COLOR already carries the light's colour, energy and the PI the
	// physically-based path divides by. Dividing PI back out is what makes the
	// band respond to cast shadows at all: without it the shadowed side of a
	// character would still carry full key light and GDD 11.2's "broad shadow
	// shapes" would be the shape of the terminator and nothing else.
	float energy = ATTENUATION * dot(LIGHT_COLOR, vec3(0.2126, 0.7152, 0.0722)) / PI;
	energy = clamp(energy * light_gain, 0.0, light_energy_max);

	// The light's own colour is deliberately dropped here. GDD 11.3 wants the
	// palette to decide what colour a surface is, and a tinted key light would
	// quietly repaint every band in the arena. The warm/cool separation GDD 11.1
	// asks for is carried by the ambient hemisphere and the rim below instead,
	// where an author can point it at GDD 11.3's colours directly.
	DIFFUSE_LIGHT = cel_ramp(cel_band(ndl)) * energy;

	// GDD 11.2 forbids the specular lobe. `specular_disabled` above already
	// removes it; this is the same statement at the point of use, so a reader
	// does not have to go looking for what replaced it.
	SPECULAR_LIGHT = vec3(0.0);
}


void fragment() {
	vec3 paint = albedo_tint.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	ALBEDO = paint;

	// Ambient comes from EMISSION rather than the environment because
	// `ambient_light_disabled` is set above: the scene's WorldEnvironment still
	// works for everything else, but the bands need to be lifted by an amount
	// an author can name. An engine ambient multiplied in on top of the ramp
	// would lift the lit band and the shadow band by the same amount and wash
	// out the very steps this shader exists to draw.
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = world_normal.y * 0.5 + 0.5;
	EMISSION = mix(ambient_bounce.rgb, ambient_sky.rgb, up) * ambient_fill;

	// The rim is a smoothstep on purpose. GDD 11.2's no-gradient rule is about
	// the diffuse ramp, where a gradient destroys the band. A rim is a
	// selection - "which pixels are close enough to the silhouette to catch the
	// light" - and a hard edge there reads as an outline bug rather than as a
	// deliberate shape.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(rim_start, 1.0, 1.0 - facing);
	EMISSION += rim_color.rgb * rim * rim_strength;
}