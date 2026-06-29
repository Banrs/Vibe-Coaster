#version 450
// Mesh fragment stage — physically based: Cook-Torrance GGX specular +
// Fresnel-Schlick + Lambert diffuse for one directional sun, plus a cheap
// hemispherical ambient (diffuse IBL stand-in), distance fog and ACES.
//
// Material is currently constant (matte, dielectric) since the voxel world has
// no albedo/roughness/metallic textures yet; those plug into `rough`/`metal`/F0
// here once a G-buffer + material textures land.
layout(location = 0) in vec3 vWorldPos;
layout(location = 1) in vec3 vNormal;
layout(location = 2) in vec3 vColor;

layout(push_constant) uniform PC {
    mat4 viewProj;
    vec4 sunDir;     // xyz dir
    vec4 camPos;     // xyz pos, w = fog end
} pc;

layout(location = 0) out vec4 outColor;

const float PI = 3.14159265359;

float D_GGX(float NoH, float a){
    float a2 = a*a;
    float d = (NoH*NoH)*(a2-1.0)+1.0;
    return a2/(PI*d*d);
}
float G_SchlickGGX(float NoX, float k){ return NoX/(NoX*(1.0-k)+k); }
float G_Smith(float NoV, float NoL, float rough){
    float k = (rough+1.0); k = (k*k)/8.0;            // direct-light remap
    return G_SchlickGGX(NoV,k)*G_SchlickGGX(NoL,k);
}
vec3 F_Schlick(float cosT, vec3 F0){
    return F0 + (1.0-F0)*pow(clamp(1.0-cosT,0.0,1.0), 5.0);
}
vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), 0.0, 1.0); }

void main() {
    vec3 N = normalize(vNormal);
    vec3 V = normalize(pc.camPos.xyz - vWorldPos);
    vec3 L = normalize(pc.sunDir.xyz);
    vec3 H = normalize(V + L);

    vec3  albedo = pow(vColor, vec3(2.2));   // biome colors are sRGB -> linear
    float rough  = 0.82;                     // matte voxels (tunable per-material later)
    float metal  = 0.0;
    vec3  F0 = mix(vec3(0.04), albedo, metal);

    float NoL = max(dot(N,L), 0.0);
    float NoV = max(dot(N,V), 1e-4);
    float NoH = max(dot(N,H), 0.0);
    float VoH = max(dot(V,H), 0.0);

    // Cook-Torrance specular
    float D = D_GGX(NoH, rough*rough);
    float G = G_Smith(NoV, NoL, rough);
    vec3  F = F_Schlick(VoH, F0);
    vec3  spec = (D*G*F) / (4.0*NoV*NoL + 1e-4);

    vec3 kd = (vec3(1.0)-F) * (1.0-metal);
    vec3 diffuse = kd * albedo / PI;

    vec3 sunRad = vec3(3.4, 3.1, 2.7);                  // HDR sun radiance
    vec3 Lo = (diffuse + spec) * sunRad * NoL;

    // hemispherical ambient (diffuse IBL stand-in until split-sum IBL lands)
    vec3 sky = vec3(0.34,0.45,0.66), ground = vec3(0.16,0.15,0.13);
    vec3 amb = mix(ground, sky, clamp(N.y*0.5+0.5,0.0,1.0)) * albedo;
    vec3 c = Lo + amb;

    // distance fog (toward a linear sky tone). Output stays LINEAR HDR; the post
    // pass does exposure + ACES + gamma.
    float d = length(vWorldPos - pc.camPos.xyz);
    float fogEnd = max(pc.camPos.w, 1.0);
    float fog = clamp((d - fogEnd*0.65)/(fogEnd*0.35), 0.0, 1.0); fog *= fog;
    vec3 skyLin = vec3(0.18, 0.34, 0.85);
    c = mix(c, skyLin, fog*0.75);

    outColor = vec4(c, 1.0);
}
