shader_type canvas_item;

void fragment(){
	vec4 tcol = texture(TEXTURE, UV);
	float main_shape = tcol.r;
	float decoration = tcol.b;
	float middle = min (main_shape, decoration);
	float middle_signed = middle-0.5;
	middle = clamp(0.5 + 8.0*middle_signed, 0.0, 1.0);
	COLOR = vec4 (main_shape, middle, middle, tcol.a);
	COLOR.r = middle;
}