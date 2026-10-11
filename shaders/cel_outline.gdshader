// Inverted-hull outline for a cel_surface.gdshader surface.
//
// GDD 11.2: "Outlines should be thin and distance-stable or omitted where
// environmental edges already read." That sentence is the whole specification,
// and each half of it drives a decision here.
//
// "Thin": the default is two pixels, and the pixels-are-the-unit answer is what
// makes "thin" mean the same thing on a chibi ninja's nose and on a roof ridge.
//
// "Distance-stable": the offset below is measured in pixels and is computed
// entirely in clip space, so the line keeps the same weight whether the surface
// is two metres away or twenty. It is the reason this is not the usual
// `VERTEX += NORMAL * thickness`: a world-space hull thickens as the surface
// comes towards the camera and thins as it goes away, which on an arena with a
// following camera means the outline of the thing the player is fighting pulses
// for the whole fight. GDD 5.4 makes the silhouette the thing being read, so a
// pulsing silhouette is not a cosmetic problem. A world-space mode is still
// offered for anyone who wants it, and it is off by default.
//
// "Omitted where environmental edges already read": this is why outlines are a
// separate material rather than a switch inside cel_surface.gdshader. Two
// pixels of ink around a wall the player can already see the edge of only costs
// contrast, and contrast is the budget GDD 11.3 spends on the actors.
//
// How to apply: same mesh, same transform, child node, back-draw material.
//
//     var outline := MeshInstance3D.new()
//     outline.mesh = body.mesh
//     outline.material_override = CelPalette.outline_material(2.0)
//     outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
//     body.add_child(outline)
//
// cull_front is what makes this an inverted hull: the near faces are discarded,
// so the shell is only visible where it pokes out past the silhouette of the
// surface underneath it. blend_mix rather than a solid line means
// outline_strength = 0 genuinely removes the outline instead of drawing it in
// black, which is what "omitted" has to mean to be authorable.
//
// `unshaded` so the ink keeps the colour it was authored with instead of being
// lit; an outline that darkens in shadow reads as dirt.
shader_type spatial;
render_mode cull_front, unshaded, blend_mix, depth_draw_never, fog_disabled, shadows_disabled;

// GDD 11.3's deep indigo, the "shadow anchor". Not black: a pure black outline
// on a bright, warm palette reads as a rendering artefact, and an outline that
// is lighter than a deep shadow loses the silhouette it exists to protect.
uniform vec4 outline_color : source_color = vec4(0.156863, 0.231373, 0.341176, 1.0);

// 0 draws nothing. Because the hull blends rather than writes depth, this is a
// true off switch and not a very faint line.
uniform float outline_strength : hint_range(0.0, 1.0) = 1.0;

// Line width in pixels. This is the distance-stable reading of GDD 11.2.
uniform float outline_width_px : hint_range(0.0, 16.0) = 2.0;

// Floor for the pixel width. At long range a two-pixel line on a distant
// character aliases away entirely; this is the budgeted answer, and it is
// separate from outline_width_px so that raising the base width does not
// silently thicken far-away geometry.
uniform float min_width_px : hint_range(0.0, 4.0) = 0.0;

// Line width in metres. Above 0 this replaces the pixel width and switches to a
// world-space hull: constant physical thickness, so the line thins with
// distance. Left at 0 by default because "distance-stable" means it should not.
uniform float outline_world_width : hint_range(0.0, 0.25) = 0.0;


void vertex() {
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_position;

	if (outline_world_width > 0.0) {
		// Constant physical thickness, expanded along the view-space normal so
		// the shell is a shell rather than a screen-aligned billboard.
		view_position.xyz += view_normal * outline_world_width;
		clip = PROJECTION_MATRIX * view_position;
	} else {
		// Screen-space offset. One pixel is 2.0 / VIEWPORT_SIZE in normalised
		// device coordinates; multiplying by clip.w converts an NDC offset back
		// into the clip-space offset that produces it, which is what makes the
		// result independent of depth.
		//
		// The direction is the view-space normal projected to the screen plane.
		// Where that projection degenerates - a face pointing straight at the
		// camera - there is no silhouette to grow, so the offset is zero rather
		// than amplified from numerical noise, which is what the naive
		// normalize() does there.
		//
		// (`projected`, not `flat`: `flat` is an interpolation qualifier in the
		// shading language and using it as a variable name stops the shader
		// compiling. That was found by the checker in tests/test_art.gd, which
		// is the argument for having one.)
		vec2 projected = view_normal.xy;
		float len = length(projected);
		vec2 direction = len > 1e-4 ? projected / len : vec2(0.0);
		float px = max(outline_width_px, min_width_px);
		clip.xy += direction * (px * 2.0 / max(VIEWPORT_SIZE.y, 1.0)) * clip.w;
	}

	POSITION = clip;
}


void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = clamp(outline_strength, 0.0, 1.0) * outline_color.a;
}