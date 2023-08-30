shader_type canvas_item;
uniform float common_alpha = 0.7;
uniform vec3 border_collie = vec3(1.0, 0.5, 0.5);

void fragment(){
	COLOR = texture(TEXTURE, UV);
	COLOR.a = common_alpha;
	float oppositeU = 1.0-UV.x;
	float oppositeV = 1.0-UV.y;
	float limitU = 0.01;
	float limitV = 0.04;
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
		COLOR.rgb = border_collie;
		COLOR.a =horizontal_alpha*vertical_alpha*common_alpha;

	}
}