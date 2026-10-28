shader_type canvas_item;
render_mode unshaded;
// Original single-pass aperture-grille treatment, inspired by CRT displays.
// Keep screen UVs unchanged so mouse targets match the displayed interface.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

vec3 linear_sample(vec2 uv) {
	return pow(max(texture(screen_texture, uv).rgb, vec3(0.0)), vec3(2.2));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 center = linear_sample(uv);
	vec3 horizontal = (linear_sample(uv + vec2(pixel.x, 0.0))
		+ linear_sample(uv - vec2(pixel.x, 0.0))) * 0.5;
	vec3 base = mix(center, horizontal, 0.16);
	vec3 glow = base * 0.24;
	glow += (linear_sample(uv + vec2(pixel.x * 3.0, 0.0))
		+ linear_sample(uv - vec2(pixel.x * 3.0, 0.0))) * 0.14;
	glow += (linear_sample(uv + vec2(0.0, pixel.y * 2.0))
		+ linear_sample(uv - vec2(0.0, pixel.y * 2.0))) * 0.14;
	glow += (linear_sample(uv + pixel * vec2(2.0, 2.0))
		+ linear_sample(uv + pixel * vec2(-2.0, 2.0))
		+ linear_sample(uv + pixel * vec2(2.0, -2.0))
		+ linear_sample(uv - pixel * vec2(2.0, 2.0))) * 0.05;

	// Integer output-pixel pitch avoids the half-pixel cosine cancellation
	// and keeps scanlines visible at both windowed and high-DPI resolutions.
	float line_pitch = clamp(floor(1.0 / (pixel.y * 270.0) + 0.5), 2.0, 8.0);
	float distance_to_beam = abs(mod(floor(FRAGCOORD.y), line_pitch) - floor(line_pitch * 0.5)) / (line_pitch * 0.5);
	float brightness = dot(base, vec3(0.2126, 0.7152, 0.0722));
	float beam_width = mix(0.48, 0.82, sqrt(clamp(brightness, 0.0, 1.0)));
	float beam = 0.28 + 0.95 * exp2(-2.3 * pow(distance_to_beam / beam_width, 2.0));

	float mask_pitch = max(1.0, floor(1.0 / (pixel.y * 800.0)));
	float channel = mod(floor(FRAGCOORD.x / mask_pitch), 3.0);
	vec3 grille = vec3(0.60);
	if (channel < 1.0) grille.r = 1.45;
	else if (channel < 2.0) grille.g = 1.45;
	else grille.b = 1.45;
	vec3 color = base * beam * grille * 1.22;
	color += max(glow - vec3(0.012), vec3(0.0)) * 0.22;
	vec2 edge = (uv - vec2(0.5)) * 2.0;
	float vignette = 1.0 - 0.18 * smoothstep(0.25, 1.5, dot(edge, edge));
	COLOR = vec4(pow(clamp(color * vignette, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
