#version 450
// Deferred lighting: reads the G-buffer + shadow map + AO and produces LINEAR HDR.
// Background texels (G-buffer flag == 0) pass through to the sky colour already in
// the HDR target — this pass discards them so the sky/clouds remain.
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform U {
    mat4 viewProj;
    mat4 lightVP;
    vec4 sunDir;     // xyz
    vec4 camPos;     // xyz, w = fog end
} u;
layout(set = 0, binding = 1) uniform sampler2D shadowMap;
layout(set = 0, binding = 2) uniform sampler2D gAlbedo;
layout(set = 0, binding = 3) uniform sampler2D gNormalRough;
layout(set = 0, binding = 4) uniform sampler2D gPosition;
layout(set = 0, binding = 5) uniform sampler2D ssaoTex;

const float PI = 3.14159265359;
float D_GGX(float NoH, float a){ float a2=a*a; float d=(NoH*NoH)*(a2-1.0)+1.0; return a2/(PI*d*d); }
float G_SchlickGGX(float NoX, float k){ return NoX/(NoX*(1.0-k)+k); }
float G_Smith(float NoV, float NoL, float r){ float k=(r+1.0); k=(k*k)/8.0; return G_SchlickGGX(NoV,k)*G_SchlickGGX(NoL,k); }
vec3  F_Schlick(float c, vec3 F0){ return F0 + (1.0-F0)*pow(clamp(1.0-c,0.0,1.0),5.0); }

float sampleShadow(vec4 lp, float ndl){
    vec3 p = lp.xyz / lp.w;
    vec2 suv = p.xy * 0.5 + 0.5;
    if(suv.x<0.0||suv.x>1.0||suv.y<0.0||suv.y>1.0||p.z>1.0) return 1.0;
    float bias = max(0.0030*(1.0-ndl), 0.0009);
    vec2 texel = 1.0 / vec2(textureSize(shadowMap,0));
    float vis = 0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++){
        float d = texture(shadowMap, suv + vec2(x,y)*texel).r;
        vis += (p.z - bias > d) ? 0.0 : 1.0;
    }
    return vis / 9.0;
}

void main(){
    vec4 pf = texture(gPosition, uv);
    if(pf.a < 0.5){ discard; }                       // background: keep the sky

    vec3 wp = pf.xyz;
    vec4 nr = texture(gNormalRough, uv);
    vec3 N  = normalize(nr.xyz);
    float rough = nr.a;
    vec3 baseCol = texture(gAlbedo, uv).rgb;
    float ao = texture(ssaoTex, uv).r;

    vec3 V = normalize(u.camPos.xyz - wp);
    vec3 L = normalize(u.sunDir.xyz);
    vec3 H = normalize(V + L);

    vec3  albedo = pow(baseCol, vec3(2.2));
    float metal = 0.0;
    vec3  F0 = mix(vec3(0.04), albedo, metal);

    float NoL=max(dot(N,L),0.0), NoV=max(dot(N,V),1e-4), NoH=max(dot(N,H),0.0), VoH=max(dot(V,H),0.0);
    float D=D_GGX(NoH,rough*rough), G=G_Smith(NoV,NoL,rough);
    vec3  F=F_Schlick(VoH,F0);
    vec3  spec=(D*G*F)/(4.0*NoV*NoL+1e-4);
    vec3  kd=(vec3(1.0)-F)*(1.0-metal);
    vec3  diffuse=kd*albedo/PI;

    vec4 lightPos = u.lightVP * vec4(wp, 1.0);
    float shadow = sampleShadow(lightPos, NoL);
    vec3 sunRad = vec3(3.4,3.1,2.7);
    vec3 Lo = (diffuse + spec) * sunRad * NoL * shadow;

    vec3 sky=vec3(0.34,0.45,0.66), ground=vec3(0.16,0.15,0.13);
    vec3 amb = mix(ground, sky, clamp(N.y*0.5+0.5,0.0,1.0)) * albedo * ao;
    vec3 c = Lo + amb;

    float d = length(wp - u.camPos.xyz);
    float fogEnd = max(u.camPos.w, 1.0);
    float fog = clamp((d - fogEnd*0.65)/(fogEnd*0.35), 0.0, 1.0); fog *= fog;
    c = mix(c, vec3(0.18,0.34,0.85), fog*0.75);

    outColor = vec4(c, 1.0);
}
