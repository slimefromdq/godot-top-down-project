shader_type canvas_item;

// Applied to actor bodies by VisualsComponent. flash_* drives hit flashes,
// tint_* drives status colours and target highlighting.

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec3 tinted = mix(base.rgb, tint_color.rgb, tint_color.a);
	COLOR = vec4(mix(tinted, flash_color.rgb, flash_amount), base.a);
}
