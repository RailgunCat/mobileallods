shader_type canvas_item;

uniform sampler2D scene : hint_screen_texture, filter_nearest;
uniform float brightness = 0.45;

void fragment() {
	vec3 rgb = texture(scene, SCREEN_UV).rgb;
	float gray = (rgb.r + rgb.g + rgb.b) / 3.0;
	COLOR = vec4(vec3(gray * brightness), 1.0);
}
