#version 450
// G-buffer write: three render targets sampled by the deferred lighting + SS passes.
//   0  albedo            (RGBA8)    rgb = surface colour, a = unused
//   1  normal+roughness  (RGBA16F)  rgb = world normal,  a = roughness
//   2  position+flag     (RGBA16F)  rgb = world position, a = 1 (geometry present)
layout(location = 0) in vec3 vWorldPos;
layout(location = 1) in vec3 vNormal;
layout(location = 2) in vec3 vColor;

layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormalRough;
layout(location = 2) out vec4 outPositionFlag;

void main(){
    outAlbedo       = vec4(vColor, 1.0);
    outNormalRough  = vec4(normalize(vNormal), 0.82);   // fixed roughness for now
    outPositionFlag = vec4(vWorldPos, 1.0);
}
