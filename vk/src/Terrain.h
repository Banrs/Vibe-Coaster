// Terrain.h — renderer-agnostic world generation, ported from the base game
// (terrainH / biome palette in ../../src/main.cpp + pathtrace.cpp). Produces a
// triangle mesh (positions + normals + colors) the Vulkan renderer uploads once.
#pragma once
#include "Math.h"
#include <vector>
#include <cstdint>

struct Vertex { Vec3 pos; Vec3 nrm; Vec3 col; };
struct Mesh   { std::vector<Vertex> verts; std::vector<uint32_t> idx; };

namespace world {

static const float WATER_Y   = 30.0f;
static const float TERRA_MAX  = 320.0f;

static inline float clampf(float v,float a,float b){ return v<a?a:(v>b?b:v); }
static inline float smooth01(float a,float b,float x){ float t=clampf((x-a)/(b-a),0,1); return t*t*(3-2*t); }
static inline float hashf(int x,int z){
    uint32_t h=(uint32_t)x*374761393u+(uint32_t)z*668265263u; h=(h^(h>>13))*1274126177u; h^=h>>16;
    return (h&0xffffff)/16777215.0f;
}
static inline float vnoise(float x,float z){
    int xi=(int)floorf(x),zi=(int)floorf(z); float xf=x-xi,zf=z-zi;
    xf=xf*xf*(3-2*xf); zf=zf*zf*(3-2*zf);
    float a=hashf(xi,zi),b=hashf(xi+1,zi),c=hashf(xi,zi+1),d=hashf(xi+1,zi+1);
    return a+(b-a)*xf+(c-a)*zf+(a-b-c+d)*xf*zf;
}
static inline float fbm(float x,float z,int o){ float a=0,amp=1,fr=1,n=0; for(int i=0;i<o;i++){a+=amp*vnoise(x*fr,z*fr);n+=amp;amp*=0.5f;fr*=2;} return a/n; }
static inline float ridgef(float x,float z,int o){ float a=0,amp=1,fr=1,n=0; for(int i=0;i<o;i++){float v=1.0f-fabsf(vnoise(x*fr,z*fr)*2-1);a+=amp*v*v;n+=amp;amp*=0.5f;fr*=2;} return a/n; }

static inline int terrainH(float x,float z){
    float warpX=(vnoise(x*0.0011f+17.5f,z*0.0011f+91.0f)-0.5f)*220.0f;
    float warpZ=(vnoise(x*0.0011f+53.0f,z*0.0011f+11.5f)-0.5f)*220.0f;
    float wx=x+warpX,wz=z+warpZ;
    float c=fbm(wx*0.0015f+0.5f,wz*0.0015f+0.5f,3);
    float e=fbm(wx*0.0040f+31.7f,wz*0.0040f+12.3f,2);
    float pv=ridgef(wx*0.0048f+5.0f,wz*0.0048f+9.0f,3);
    float det=fbm(wx*0.020f,wz*0.020f,2);
    float mesaMask=smooth01(0.58f,0.82f,fbm(wx*0.0010f+101.0f,wz*0.0010f+44.0f,2));
    float basin=smooth01(0.72f,0.94f,1.0f-ridgef(wx*0.0022f+3.7f,wz*0.0022f+8.1f,2));
    float mountainRegion=smooth01(0.50f,0.84f,fbm(wx*0.00085f+9.0f,wz*0.00085f+73.0f,2));
    float valleyMask=smooth01(0.62f,0.90f,ridgef(wx*0.0017f+61.0f,wz*0.0017f+19.0f,2));
    float midHill=fbm(wx*0.008f+32.0f,wz*0.008f+77.0f,3)-0.5f;
    float base=24.0f+powf(c,1.30f)*150.0f;
    float mAmp=powf(1.0f-e,1.62f);
    float mtn=powf(pv,2.36f)*mAmp*(92.0f+142.0f*mountainRegion);
    float h=base+mtn+(det-0.5f)*14.0f+midHill*22.0f;
    h+=powf(pv,5.0f)*smooth01(0.48f,0.92f,mountainRegion)*(42.0f+46.0f*(1.0f-e));
    h-=basin*(22.0f+48.0f*(1.0f-c));
    h-=valleyMask*(1.0f-mesaMask)*(8.0f+18.0f*(1.0f-c));
    float terraceStep=5.0f+8.0f*vnoise(wx*0.0018f+211.0f,wz*0.0018f+37.0f);
    float terraced=floorf(h/terraceStep)*terraceStep+(det-0.5f)*3.0f;
    h=h+(terraced-h)*mesaMask*0.58f;
    h+=mesaMask*smooth01(0.35f,0.70f,c)*18.0f;
    if(h<1)h=1; if(h>TERRA_MAX)h=TERRA_MAX;
    return (int)h;
}

static inline Vec3 biomeColor(float wx,float wz,int h){
    bool beach=(h+1.0f)<=WATER_Y+0.6f;
    float bio=vnoise(wx*0.0045f+91.3f,wz*0.0045f+23.1f);
    float humid=fbm(wx*0.0028f+44.0f,wz*0.0028f+108.0f,2);
    float temp=fbm(wx*0.0019f+12.0f,wz*0.0019f+204.0f,2);
    Vec3 cap={130/255.0f,206/255.0f,102/255.0f};               // grass
    if(h>=260)      cap={204/255.0f,214/255.0f,224/255.0f};
    else if(h>=158) cap={128/255.0f,138/255.0f,146/255.0f};
    else if(beach)  cap={242/255.0f,228/255.0f,184/255.0f};
    else if(humid<0.23f&&temp>0.42f) cap={214/255.0f,196/255.0f,108/255.0f};
    else if(humid>0.72f&&bio<0.72f)  cap={76/255.0f,176/255.0f,92/255.0f};
    else if(bio<0.34f){}
    else if(bio<0.58f) cap={118/255.0f,206/255.0f,108/255.0f};
    else if(bio<0.78f) cap={210/255.0f,202/255.0f,132/255.0f};
    else cap={112/255.0f,150/255.0f,112/255.0f};
    float s=0.89f+0.13f*hashf((int)floorf(wx)*5+1,(int)floorf(wz)*5+2);
    return cap*s;
}

// One flat-shaded quad (a,b,c,d CCW) with an explicit face normal + color.
inline void addQuad(Mesh& out, Vec3 a, Vec3 b, Vec3 c, Vec3 d, Vec3 n, Vec3 col){
    uint32_t base=(uint32_t)out.verts.size();
    out.verts.push_back({a,n,col}); out.verts.push_back({b,n,col});
    out.verts.push_back({c,n,col}); out.verts.push_back({d,n,col});
    out.idx.insert(out.idx.end(), { base,base+1,base+2, base,base+2,base+3 });
}

// Build a *blocky* (voxel) terrain surface over a (2*half)^2 area of 1 m cells,
// matching the base game's look: each cell is a flat-topped block (cap quad at
// its integer height) plus vertical side faces dropping only to the lower
// neighbour. Faces are flat-normal, so the result reads as cubes, and nothing
// below a neighbour's surface is ever built (never-visible = not drawn).
inline void buildTerrain(float cx, float cz, float half, float /*step*/, Mesh& out){
    out.verts.clear(); out.idx.clear();
    int R = (int)half;
    int ox = (int)floorf(cx), oz = (int)floorf(cz);
    for(int dz=-R; dz<=R; dz++) for(int dx=-R; dx<=R; dx++){
        float wx=(float)(ox+dx), wz=(float)(oz+dz);
        int h=terrainH(wx,wz);
        float top=(float)h+1.0f;
        Vec3 cap=biomeColor(wx,wz,h);
        Vec3 body=cap*0.6f;                       // darker sides read as cube faces
        float xm=wx-0.5f, xp=wx+0.5f, zm=wz-0.5f, zp=wz+0.5f;

        addQuad(out, {xm,top,zm},{xp,top,zm},{xp,top,zp},{xm,top,zp}, {0,1,0}, cap);

        int hpx=terrainH(wx+1,wz), hnx=terrainH(wx-1,wz);
        int hpz=terrainH(wx,wz+1), hnz=terrainH(wx,wz-1);
        if(h>hpx){ float b=(float)hpx+1.0f; addQuad(out, {xp,b,zm},{xp,top,zm},{xp,top,zp},{xp,b,zp}, { 1,0,0}, body); }
        if(h>hnx){ float b=(float)hnx+1.0f; addQuad(out, {xm,b,zm},{xm,top,zm},{xm,top,zp},{xm,b,zp}, {-1,0,0}, body); }
        if(h>hpz){ float b=(float)hpz+1.0f; addQuad(out, {xm,b,zp},{xp,b,zp},{xp,top,zp},{xm,top,zp}, {0,0, 1}, body); }
        if(h>hnz){ float b=(float)hnz+1.0f; addQuad(out, {xm,b,zm},{xp,b,zm},{xp,top,zm},{xm,top,zm}, {0,0,-1}, body); }
    }
}

// Flat water surface quad at WATER_Y over the same area.
inline void appendWater(float cx, float cz, float half, Mesh& out){
    uint32_t base=(uint32_t)out.verts.size();
    Vec3 wn={0,1,0}, wc={0.20f,0.42f,0.55f};
    out.verts.push_back({ Vec3{cx-half,WATER_Y,cz-half}, wn, wc });
    out.verts.push_back({ Vec3{cx+half,WATER_Y,cz-half}, wn, wc });
    out.verts.push_back({ Vec3{cx-half,WATER_Y,cz+half}, wn, wc });
    out.verts.push_back({ Vec3{cx+half,WATER_Y,cz+half}, wn, wc });
    out.idx.insert(out.idx.end(), { base,base+2,base+1, base+1,base+2,base+3 });
}

} // namespace world
