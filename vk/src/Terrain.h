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

// Continuous Whittaker-style climate -> grass colour, à la Minecraft: temperature
// and humidity (low-frequency noise) select a colour by smooth interpolation, with
// elevation cooling (snow/rock up high) and beaches near water. No hard thresholds,
// so a single sample already transitions smoothly; biomeColor() then averages a
// neighbourhood (Minecraft's grass-colour blend) to erase any remaining seams.
static inline Vec3 climateColor(float wx, float wz, int h){
    float top = (float)h + 1.0f;
    float temp  = clampf(fbm(wx*0.0019f+12.0f, wz*0.0019f+204.0f, 3), 0.0f, 1.0f);
    float humid = clampf(fbm(wx*0.0028f+44.0f, wz*0.0028f+108.0f, 3), 0.0f, 1.0f);
    float warmth = clampf(temp - smooth01(70.0f,210.0f,(float)h)*0.55f, 0.0f, 1.0f); // height cools

    Vec3 plains ={130/255.f,206/255.f,102/255.f};
    Vec3 forest ={ 76/255.f,176/255.f, 92/255.f};
    Vec3 jungle ={ 96/255.f,188/255.f, 96/255.f};
    Vec3 savanna={210/255.f,202/255.f,132/255.f};
    Vec3 desert ={214/255.f,196/255.f,108/255.f};
    Vec3 taiga  ={112/255.f,150/255.f,112/255.f};
    Vec3 sand   ={242/255.f,228/255.f,184/255.f};
    Vec3 rock   ={120/255.f,124/255.f,130/255.f};
    Vec3 snow   ={224/255.f,232/255.f,240/255.f};

    Vec3 wetCol = lerp(forest, jungle, humid);
    Vec3 dryCol = lerp(savanna, desert, 1.0f - humid);
    Vec3 warmCol= lerp(dryCol, lerp(plains, wetCol, smooth01(0.40f,0.85f,humid)),
                       smooth01(0.25f,0.60f,humid));
    Vec3 coldCol= lerp(taiga, snow, smooth01(0.35f,0.05f,warmth));   // colder -> snow
    Vec3 c = lerp(coldCol, warmCol, smooth01(0.22f,0.50f,warmth));
    c = lerp(c, rock, smooth01(150.0f,200.0f,(float)h));            // high -> rock
    c = lerp(c, snow, smooth01(235.0f,290.0f,(float)h));            // higher -> snow
    c = lerp(c, sand, smooth01(WATER_Y+2.5f, WATER_Y+0.4f, top));   // beaches
    return c;
}

// Minecraft-style grass-colour blend: average the climate colour over a small
// neighbourhood so biome borders fade instead of stepping. Per-cell hash adds
// subtle grain like MC's noise.
static inline Vec3 biomeColor(float wx, float wz){
    Vec3 acc{0,0,0}; const float R=3.0f;
    for(int oz=-1; oz<=1; oz++) for(int ox=-1; ox<=1; ox++){
        float sx=wx+ox*R, sz=wz+oz*R;
        acc = acc + climateColor(sx, sz, terrainH(sx,sz));
    }
    Vec3 c = acc * (1.0f/9.0f);
    float s = 0.92f + 0.08f*hashf((int)floorf(wx)*5+1, (int)floorf(wz)*5+2);
    return c*s;
}

// One flat-shaded quad (a,b,c,d CCW) with an explicit face normal + color.
inline void addQuad(Mesh& out, Vec3 a, Vec3 b, Vec3 c, Vec3 d, Vec3 n, Vec3 col){
    uint32_t base=(uint32_t)out.verts.size();
    out.verts.push_back({a,n,col}); out.verts.push_back({b,n,col});
    out.verts.push_back({c,n,col}); out.verts.push_back({d,n,col});
    out.idx.insert(out.idx.end(), { base,base+1,base+2, base,base+2,base+3 });
}

// An oriented box: center C, orthonormal axes (R,U,F), half-extents (hr,hu,hf).
inline void addBox(Mesh& out, Vec3 C, Vec3 R, Vec3 U, Vec3 F,
                   float hr, float hu, float hf, Vec3 col){
    Vec3 r=R*hr, u=U*hu, f=F*hf;
    Vec3 c[8] = { C-r-u-f, C+r-u-f, C+r+u-f, C-r+u-f, C-r-u+f, C+r-u+f, C+r+u+f, C-r+u+f };
    auto quad=[&](int a,int b,int d,int e,Vec3 n){ addQuad(out,c[a],c[b],c[d],c[e],n,col); };
    quad(0,3,2,1, F*-1.0f); quad(4,5,6,7, F);
    quad(0,1,5,4, U*-1.0f); quad(3,7,6,2, U);
    quad(0,4,7,3, R*-1.0f); quad(1,2,6,5, R);
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
        Vec3 cap=biomeColor(wx,wz);
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

// Voxel trees, placed by biome density (ported from the base game's tree pass in
// main.cpp / pathtrace.cpp): a trunk of cubes + a leaf canopy blob.
inline void buildTrees(float cx, float cz, float half, Mesh& out){
    int R=(int)half; int ox=(int)floorf(cx), oz=(int)floorf(cz);
    Vec3 I{1,0,0}, J{0,1,0}, K{0,0,1};
    for(int dz=-R; dz<=R; dz++) for(int dx=-R; dx<=R; dx++){
        float wx=(float)(ox+dx), wz=(float)(oz+dz);
        int h=terrainH(wx,wz); float top=(float)h+1.0f;
        if(top<=WATER_Y+0.6f || h>=158) continue;          // no trees in water or high rock
        float bio  = vnoise(wx*0.0045f+91.3f, wz*0.0045f+23.1f);
        float humid= fbm(wx*0.0028f+44.0f, wz*0.0028f+108.0f, 2);
        float temp = fbm(wx*0.0019f+12.0f, wz*0.0019f+204.0f, 2);
        int type=-1; float den=0;
        if(humid<0.23f && temp>0.42f){ type=3; den=0.003f; }       // sparse savanna
        else if(humid>0.72f && bio<0.72f){ type=0; den=0.055f; }   // dense forest
        else if(bio<0.34f){ type=0; den=0.010f; }
        else if(bio<0.58f){ type=1; den=0.038f; }
        else if(bio<0.78f){ type=3; den=0.006f; }
        else { type=2; den=0.016f; }
        if(type<0) continue;
        if(hashf((int)floorf(wx)*9+7, (int)floorf(wz)*9+3) >= den) continue;
        Vec3 trunk, leaf;
        switch(type){
            case 0: trunk={0.49f,0.38f,0.24f}; leaf={0.42f,0.75f,0.38f}; break;
            case 1: trunk={0.84f,0.82f,0.76f}; leaf={0.44f,0.64f,0.32f}; break;  // birch
            case 2: trunk={0.32f,0.24f,0.16f}; leaf={0.25f,0.40f,0.25f}; break;  // taiga
            default:trunk={0.42f,0.32f,0.21f}; leaf={0.51f,0.56f,0.25f}; break;  // dry
        }
        float th = 3.0f + 2.0f*hashf((int)floorf(wx)*3+1, (int)floorf(wz)*5+2);  // trunk 3..5
        for(float ty=0; ty<th; ty+=1.0f)
            addBox(out, Vec3{wx, top+ty+0.5f, wz}, I,J,K, 0.34f,0.5f,0.34f, trunk);
        float cy = top + th;                                    // canopy base
        for(int ly=0; ly<=3; ly++) for(int lx=-2; lx<=2; lx++) for(int lz=-2; lz<=2; lz++){
            float rad = 2.4f - ly*0.55f;
            if(lx*lx + lz*lz > rad*rad) continue;
            addBox(out, Vec3{wx+lx, cy+ly+0.5f, wz+lz}, I,J,K, 0.5f,0.5f,0.5f, leaf);
        }
    }
}

} // namespace world
