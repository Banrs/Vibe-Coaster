#version 450
// Base mesh vertex stage — world meshes (terrain, track, train) share this.
layout(location = 0) in vec3 inPos;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec3 inColor;

layout(push_constant) uniform PC {
    mat4 viewProj;
    vec4 sunDir;     // xyz = sun direction, w unused
    vec4 camPos;     // xyz = camera position, w = fog end
} pc;

layout(location = 0) out vec3 vWorldPos;
layout(location = 1) out vec3 vNormal;
layout(location = 2) out vec3 vColor;

void main() {
    vWorldPos = inPos;
    vNormal   = inNormal;
    vColor    = inColor;
    gl_Position = pc.viewProj * vec4(inPos, 1.0);
}
