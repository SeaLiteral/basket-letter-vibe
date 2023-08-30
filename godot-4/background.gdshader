shader_type canvas_item;

void fragment(){
	vec4 tcol = texture(TEXTURE, UV);
	COLOR = tcol;
	float greyscale = (COLOR.r + COLOR.g + COLOR.b) / 3.0;
	float largest_channel = tcol.r;
	float smallest_channel= tcol.g;
	if (tcol.g>largest_channel){
		largest_channel = tcol.g;
		smallest_channel = tcol.r;
	}
	if (tcol.b>largest_channel){
		largest_channel = tcol.b;
	}
	else if (tcol.b<smallest_channel){
		smallest_channel = tcol.b;
	}
	float channel_difference = largest_channel-smallest_channel;
	float saturation_change = 1.2;
	float darken = 0.1*channel_difference;
	vec3 lighting = vec3(1.0, 1.0, 1.0);
	COLOR.r = clamp(lighting.r*(greyscale+(tcol.r-greyscale)*saturation_change-darken), 0.0, 1.0);
	COLOR.g = clamp(lighting.g*(greyscale+(tcol.g-greyscale)*saturation_change-darken), 0.0, 1.0);
	COLOR.b = clamp(lighting.b*(greyscale+(tcol.b-greyscale)*saturation_change-darken), 0.0, 1.0);
	
}