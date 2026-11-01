shader_type canvas_item;
// Solid-colour silhouette of a texture: keeps the alpha, throws away the colours.
uniform vec4 ink : source_color = vec4(0.12, 0.07, 0.04, 1.0);

void fragment() {
	COLOR = vec4(ink.rgb, texture(TEXTURE, UV).a * ink.a);
}
