// Short-lived impact graphic: a slash crescent or a starburst, drawn on a quad.
//
// GDD 11.4: "Impacts use graphic starbursts, slash crescents, brief hit-stop,
// limited particles and one readable accent color per ability family. Avoid
// enormous bloom plumes that conceal enemy windups. ... Make effects
// parameterized by world scale and duration, with per-ability readability
// caps."
//
// Every clause in that sentence is a constraint this file is built around, and
// three of them are enforced in the shader rather than left to the caller,
// because a discipline that depends on every future author remembering it is not
// a discipline:
//
//   * "Avoid enormous bloom plumes that conceal enemy windups." The size cap
//     below is not advisory. The shader discards any fragment further from the
//     centre than max_size_m, so an over-scaled quad draws a clipped effect and
//     not a bigger one. You cannot author a plume that hides a windup with this
//     material.
//   * The blend mode is additive, so the effect can brighten what is behind it
//     and can never darken or hide it. Structural, not stylistic.
//   * The effect is gone by the end of its lifetime. Past `life_ticks` the
//     fragment is discarded outright, so the decal cannot linger into the next
//     attack and stack up.
//
// GDD 5.4 is why all three exist: enemy attacks must communicate "origin,
// direction, timing and counterplay", and an effect that covers the frame
// competes with the one thing the player has to read.
//
// How to apply: a QuadMesh whose node is scaled so quad_world_size matches its
// real width in metres, with age_ticks advanced each frame.
//
//     var fx := MeshInstance3D.new()
//     fx.mesh = QuadMesh.new()
//     fx.mesh.size = Vector2.ONE * quad_world_size
//     fx.material_override = CelPalette.impact_material(CelPalette.accent_for("crimson_edge"))
//     fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
//     fx.set_meta("age_ticks", 0.0)
//
// Accent colours come from CelPalette.accent_for(), which is where GDD 11.4's
// "one readable accent color per ability family" is actually resolved into
// GDD 11.3's palette. One family, one colour, chosen by looking it up rather
// than by remembering which hue goes with which scroll.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// GDD 11.4: "one readable accent color per ability family".
uniform vec4 accent_color : source_color = vec4(0.909804, 0.368627, 0.313725, 1.0);

// 0 starburst, 1 slash crescent. The two forms GDD 11.4 names, and the only two
// this material can draw.
uniform int shape = 1;

// --- Duration ------------------------------------------------------------------

// GDD 11.2's clock, GDD 5.2's: the simulation runs at 60 ticks per second, so a
// lifetime in ticks is the same number the combat data uses. An impact that
// lasts longer than the attack that caused it is decoration, not feedback.
uniform float life_ticks : hint_range(1.0, 60.0) = 8.0;

// Advanced by the spawner, not by TIME. A decal that reads the clock cannot know
// when it was born, and one that guesses is wrong for every decal that was not
// spawned on a frame boundary.
uniform float age_ticks : hint_range(0.0, 120.0) = 0.0;

// --- World scale and the readability cap ------------------------------------------

// The quad's full width in metres. Needed because the cap below is a
// measurement in the world, and UV is not.
uniform float quad_world_size : hint_range(0.05, 20.0) = 1.0;

// The radius the effect is drawn at.
uniform float size_m : hint_range(0.01, 20.0) = 0.8;

// The per-ability readability cap GDD 11.4 asks for. The effective radius is
// min(size_m, max_size_m), applied as a hard discard, so this is a ceiling the
// shader enforces rather than a number an author is trusted to respect. A
// character is roughly 1.6 m tall (Tuning.CHARACTER_HEIGHT); an impact wider
// than the target it is reporting on has stopped being feedback.
uniform float max_size_m : hint_range(0.05, 4.0) = 1.2;

// The other half of the cap: an additive plume at full opacity over a bright
// arena is a white hole, which conceals whatever it covers just as effectively
// as a dark one.
uniform float alpha_cap : hint_range(0.0, 1.0) = 0.85;

// --- Shape ---------------------------------------------------------------------

// Slash crescent: half opening, in turns of a full circle. A slash reads as a
// slash because it is an arc with ends, not a ring.
uniform float arc_opening : hint_range(0.05, 1.0) = 0.42;
uniform float crescent_radius : hint_range(0.1, 0.95) = 0.62;
uniform float crescent_thickness : hint_range(0.01, 0.6) = 0.22;

// Starburst: number of rays and how hard they are cut between them.
uniform float ray_count : hint_range(3.0, 16.0) = 6.0;
uniform float ray_sharpness : hint_range(1.0, 24.0) = 8.0;
uniform float star_falloff : hint_range(0.5, 8.0) = 2.5;

// Rotations over the effect's whole life. Driven from lifetime progress rather
// than TIME, so the spin is the same whether the effect is played at 30 or
// 144 fps.
uniform float spin_turns : hint_range(-2.0, 2.0) = 0.15;

// Fraction of the lifetime spent fading in, and the fraction at which the fade
// out begins. The attack is over early and the effect takes longer to stop
// drawing attention than it took to appear.
uniform float fade_in : hint_range(0.01, 0.5) = 0.12;
uniform float fade_out_start : hint_range(0.2, 0.95) = 0.35;


float progress() {
	return clamp(age_ticks / max(life_ticks, 1.0), 0.0, 1.0);
}


float crescent(vec2 p, float t) {
	float radius = length(p);
	// atan's two-argument form returns -PI..PI; folding to 0..1 turns the arc
	// into a fraction of a circle rather than a fraction of PI, so the same
	// number means the same thing for every opening angle.
	float angle = atan(p.y, p.x) / TAU + 0.5;
	float across = abs(angle - 0.5) * 2.0;
	float t_across = clamp(across / max(arc_opening, 0.001), 0.0, 1.0);

	// The band walks inward as it leaves the centre of the arc, and thins as it
	// goes. Both tapers are what make the shape read as a blade passing rather
	// than as a ring drawn on screen.
	float centre = crescent_radius * (1.0 - 0.45 * t_across);
	float half_thickness = crescent_thickness * 0.5 * (1.0 - 0.85 * t_across);
	float d = abs(radius - centre) - half_thickness;

	float coverage = 1.0 - smoothstep(0.0, 0.02, d);
	// Fade the last few degrees of the arc instead of stopping it dead.
	coverage *= 1.0 - smoothstep(0.75, 1.0, t_across);
	// Nothing at the very centre of the quad either: the crescent is an arc,
	// and a dot in the middle of it is not part of the shape.
	coverage *= smoothstep(0.0, 0.05, radius);
	// Sweep outward over the effect's life, so it reads as the blade arriving
	// rather than as a decal appearing already finished.
	return coverage * smoothstep(0.0, 0.35, t + 0.1);
}


float starburst(vec2 p, float t) {
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float rays = floor(ray_count + 0.5);
	float spike = pow(abs(cos(angle * rays)), ray_sharpness);
	float radial = pow(clamp(1.0 - radius, 0.0, 1.0), star_falloff);
	// The centre stays solid and only the rays cut in, or the whole figure
	// pulses instead of holding a readable shape.
	float coverage = clamp(mix(1.0, spike, 0.8) * radial, 0.0, 1.0);
	return coverage * smoothstep(0.0, 0.25, t + 0.15);
}


void fragment() {
	float t = progress();

	// Short-lived means short-lived. This is checked before anything else so
	// that an over-long effect cannot draw even one frame past its lifetime.
	if (t >= 1.0) {
		discard;
	}

	float radius_world = min(size_m, max_size_m);
	float half_quad = max(quad_world_size * 0.5, 0.0001);
	vec2 p = UV * 2.0 - 1.0;

	// The cap, enforced. Everything outside the readability limit is thrown
	// away rather than drawn faintly.
	if (length(p) * half_quad > radius_world) {
		discard;
	}

	// Normalise so the shape always fills the permitted radius, whatever the
	// quad is scaled to. That is what makes the effect parameterized by world
	// scale in GDD 11.4's sense rather than by mesh size.
	float reach = max(radius_world / half_quad, 0.0001);
	vec2 q = p / reach;

	float angle = spin_turns * TAU * t;
	float s = sin(angle);
	float c = cos(angle);
	vec2 spun = vec2(c * q.x - s * q.y, s * q.x + c * q.y);

	float coverage = shape == 0 ? starburst(spun, t) : crescent(spun, t);

	float fade = smoothstep(0.0, max(fade_in, 0.001), t)
		* (1.0 - smoothstep(clamp(fade_out_start, 0.0, 0.98), 0.98, t));

	ALBEDO = accent_color.rgb;
	ALPHA = clamp(coverage * fade * accent_color.a, 0.0, alpha_cap);
}