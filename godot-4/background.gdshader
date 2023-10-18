shader_type canvas_item;

void fragment(){
	vec4 tcol = texture(TEXTURE, UV);
	COLOR = tcol;
}