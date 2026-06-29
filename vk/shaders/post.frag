#version 450
// Post: composite HDR + bloom, exposure, ACES tonemap, gamma. Output is the
// final 8-bit image (blitted to the swapchain or copied to a PPM).
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 outColor;
layout(set = 0, binding = 0) uniform sampler2D hdr;
layout(set = 0, binding = 1) uniform sampler2D bloom;
layout(push_constant) uniform PC { float exposure; float bloomStrength; vec2 pad; } pc;

vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), 0.0, 1.0); }

void main(){
    vec3 c = texture(hdr, uv).rgb;
    c += texture(bloom, uv).rgb * pc.bloomStrength;
    c = aces(c * pc.exposure);
    c = pow(c, vec3(1.0/2.2));
    outColor = vec4(c, 1.0);
}
