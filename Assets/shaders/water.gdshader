shader_type canvas_item;

// Лёгкая анимация воды: синусоидальное искажение UV + мерцающие блики.
// Дёшево по стоимости — только fragment(), без доп. текстур шума.

uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float wave_strength : hint_range(0.0, 0.05) = 0.012;
uniform float sparkle_strength : hint_range(0.0, 0.5) = 0.18;

void fragment() {
	vec2 uv = UV;
	uv.x += sin(uv.y * 18.0 + TIME * wave_speed) * wave_strength;
	uv.y += cos(uv.x * 14.0 + TIME * wave_speed * 0.8) * wave_strength;

	vec4 tex_color = texture(TEXTURE, uv);

	float sparkle = sin(uv.x * 40.0 + TIME * 1.3) * sin(uv.y * 37.0 - TIME * 1.1);
	sparkle = pow(clamp(sparkle, 0.0, 1.0), 6.0) * sparkle_strength;

	COLOR = vec4(tex_color.rgb + sparkle, tex_color.a) * COLOR;
}
