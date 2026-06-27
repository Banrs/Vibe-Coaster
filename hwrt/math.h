// Minimal vector/matrix math for the renderer.
#pragma once
#include <cmath>

struct float3 {
    float x, y, z;
};

static inline float3 vec3(float x, float y, float z) { return {x, y, z}; }
static inline float3 operator+(float3 a, float3 b) { return {a.x+b.x, a.y+b.y, a.z+b.z}; }
static inline float3 operator-(float3 a, float3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline float3 operator*(float3 a, float s)   { return {a.x*s, a.y*s, a.z*s}; }
static inline float3 operator*(float s, float3 a)   { return {a.x*s, a.y*s, a.z*s}; }
static inline float  dot(float3 a, float3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static inline float3 cross(float3 a, float3 b) {
    return {a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x};
}
static inline float  length(float3 a) { return std::sqrt(dot(a, a)); }
static inline float3 normalize(float3 a) {
    float l = length(a);
    return l > 0 ? a * (1.0f / l) : a;
}

// Camera state shared between CPU and GPU (uploaded as a uniform buffer).
struct CameraUniforms {
    float origin[3];      float _pad0;
    float forward[3];     float _pad1;
    float right[3];       float _pad2;
    float up[3];          float _pad3;
    float sunDir[3];      float _pad4;
    float tanHalfFov;     // tan(fov/2)
    float aspect;         // width/height
    unsigned int width;
    unsigned int height;
    unsigned int frame;   // animates cloud drift / per-frame sampling
    unsigned int _pad5[3];
};
