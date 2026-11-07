shader_type spatial;
// block.gdshader that can fade out (`fade`), for falling debris. A separate
// shader so the solid blocks stay out of the transparent pass.

#define FADE
#include "res://shaders/block.gdshaderinc"
