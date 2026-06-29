#version 450
// Base mesh fragment stage — sun + hemispherical ambient + distance fog + ACES,
// matching the look of the original software renderer.
layout(location = 0) in vec3 vWorldPos;
layout(location = 1) in vec3 vNormal;
layout(location = 2) in vec3 vColor;

layout(push_constant) uniform PC {
    mat4 viewProj;
    vec4 sunDir;
    vec4 camPos;     // w = fog end
} pc;

layout(location = 0) out vec4 outColor;

vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), 0.0, 1.0); }

void main() {
    vec3 n   = normalize(vNormal);
    vec3 sun = normalize(pc.sunDir.xyz);
    float ndl = max(dot(n, sun), 0.0);

    vec3 albedo = pow(vColor, vec3(2.2));   // biome colors are sRGB -> linearize
    vec3 amb = mix(vec3(0.10,0.11,0.13), vec3(0.34,0.45,0.66), clamp(n.y*0.5+0.5,0.0,1.0));
    vec3 sunRad = vec3(1.45, 1.32, 1.12);
    vec3 c = albedo * (amb + sunRad * ndl);

    // gentle distance fog toward a sky tone, only near the far edge
    float d = length(vWorldPos - pc.camPos.xyz);
    float fogEnd = max(pc.camPos.w, 1.0);
    float fog = clamp((d - fogEnd*0.65) / (fogEnd*0.35), 0.0, 1.0); fog *= fog;
    vec3 sky = vec3(0.45, 0.62, 0.92);
    c = mix(c, sky, fog * 0.7);

    c = aces(c * 1.05);
    c = pow(c, vec3(1.0/2.2));
    outColor = vec4(c, 1.0);
}
