shader_type spatial;
// Terreno da noite eterna: terra, grama morta, rocha nas encostas e cinza nos picos.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.021).r;
	float n2 = texture(noise_tex, wpos.xz * 0.17).r;
	float n3 = texture(noise_tex, wpos.xz * 0.9).r;
	float slope = 1.0 - wnorm.y;

	vec3 dirt  = mix(vec3(0.060, 0.047, 0.040), vec3(0.115, 0.088, 0.070), n2);
	vec3 grass = mix(vec3(0.050, 0.058, 0.036), vec3(0.105, 0.098, 0.055), n3);
	vec3 rock  = mix(vec3(0.090, 0.088, 0.095), vec3(0.200, 0.190, 0.200), n3);
	vec3 ash   = vec3(0.30, 0.29, 0.31);

	float g = smoothstep(0.42, 0.62, n1 + (n2 - 0.5) * 0.35);
	vec3 col = mix(dirt, grass, g);
	col = mix(col, rock, smoothstep(0.22, 0.42, slope + (n2 - 0.5) * 0.25));
	float peak = smoothstep(16.0, 30.0, wpos.y + n1 * 8.0) * (1.0 - smoothstep(0.35, 0.6, slope));
	col = mix(col, ash, peak);

	ALBEDO = col * (0.8 + 0.4 * n3);
	ROUGHNESS = mix(0.95, 0.75, smoothstep(0.3, 0.5, slope));
	SPECULAR = 0.3;
}
