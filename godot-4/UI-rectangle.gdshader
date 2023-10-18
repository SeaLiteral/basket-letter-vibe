shader_type canvas_item;
uniform float common_alpha = 0.7;
uniform vec3 border_collie = vec3(1.0, 0.5, 0.5);
uniform vec3 background_color = vec3(1.0, 1.0, 1.0);
uniform vec2 border_limits = vec2(0.01, 0.04);
uniform float corner_alpha = 0.0;
uniform float color_bleed = 0.0;

void fragment(){
	COLOR = vec4 (background_color, common_alpha);
	float oppositeU = 1.0-UV.x;
	float oppositeV = 1.0-UV.y;
	float limitU = border_limits.x;
	float limitV = border_limits.y;
	float factorU = 1.0/limitU;
	float factorV = 1.0/limitV;
	float horizontal_alpha = 1.0;
	float vertical_alpha = 1.0;
	if (UV.x<limitU){
		horizontal_alpha = UV.x*factorU;
	}
	else if (oppositeU<limitU){
		horizontal_alpha = oppositeU*factorU;
	}
	if (UV.y<limitV){
		vertical_alpha = UV.y*factorV;
	}
	else if (oppositeV<limitV){
		vertical_alpha = oppositeV*factorV;
	}
	if (horizontal_alpha+vertical_alpha<2.0){
		
		vec3 new_color = mix (background_color, border_collie, 1.0-(horizontal_alpha*vertical_alpha));
		COLOR.rgb = mix (new_color, border_collie, 1.0-color_bleed);
		COLOR.a = mix(corner_alpha, common_alpha, horizontal_alpha*vertical_alpha);

	}
}