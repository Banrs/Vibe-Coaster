// CoasterTrack.h — drives the *real* physics-driven generator from
// ../../src/coaster_track.cpp (compiled via GameCompat.h) and turns its control
// points into rail/spine/tie/support/train box meshes for the Vulkan renderer.
#pragma once
#include "GameCompat.h"
#include "Track.h"                       // world::addBox / addQuad / Mesh / Vec3
#include "../../src/coaster_track.cpp"   // struct Track (+ coaster_elements_ext.cpp)
#include <cstdio>

namespace world {

inline Vec3 v3(Vector3 p){ return Vec3{p.x,p.y,p.z}; }

// Generate a long circuit and report stats (length / ride time / element mix).
inline void genLongTrack(::Track& trk, int targetPoints){
    trk.reset();
    int guard=0;
    while((int)trk.cp.size() < targetPoints && guard++ < 200000)
        trk.ensureAhead((float)trk.cp.size() + 8.0f);

    float L = trk.arc.empty() ? 0.0f : trk.arc.back();
    int counts[M_COUNT] = {0};
    for(unsigned char k : trk.kind) if(k < M_COUNT) counts[k]++;
    const char* NM[M_COUNT] = {"FLAT","CLIMB","DROP","HILLS","TURN","LOOP","ROLL","STATION",
        "DIP","LAUNCH","HELIX","BOOST","IMMEL","SCURVE","DIVE","BANKAIR","WAVE","STALL",
        "DIVELOOP","COBRA","WINGOVER","HEARTLINE","PRETZEL","STENGEL","BANANA"};
    printf("[track] %d points, %.0f m of track  (~%.0f s ride at 62.5 m/s / 225 km/h)\n",
           (int)trk.cp.size(), L, L/62.5f);
    printf("[track] elements:");
    for(int k=0;k<M_COUNT;k++) if(counts[k] && k!=M_FLAT && k!=M_CLIMB && k!=M_DROP)
        printf(" %s=%d", NM[k], counts[k]);
    printf("\n");
}

// Build rail/spine/tie/support/train geometry for the portion of the track that
// lies within the rendered terrain patch [cx±half, cz±half].
inline void buildTrackMesh(const ::Track& trk, Mesh& out, float cx, float cz, float half){
    Vec3 steel{0.72f,0.75f,0.80f}, tie{0.42f,0.30f,0.20f}, spine{0.78f,0.16f,0.30f},
         post{0.46f,0.48f,0.52f};
    const float gauge=1.2f;
    int N=(int)trk.cp.size();
    auto inPatch=[&](Vector3 p){ return fabsf(p.x-cx)<=half && fabsf(p.z-cz)<=half; };

    for(int i=1;i<N-1;i++){
        Vector3 P=trk.cp[i]; if(!inPatch(P)) continue;
        Vector3 T=Vector3Normalize(Vector3Subtract(trk.cp[i+1], trk.cp[i-1]));
        Vector3 U=Vector3Normalize(trk.up[i]);
        Vector3 R=Vector3Normalize(Vector3CrossProduct(T,U));
        U=Vector3Normalize(Vector3CrossProduct(R,T));          // re-orthogonalize
        Vec3 vT=v3(T), vU=v3(U), vR=v3(R), C=v3(P);
        float segLen=Vector3Distance(P, trk.cp[i+1])*0.5f + 0.06f;

        addBox(out, C + vR*( gauge*0.5f), vR,vU,vT, 0.12f,0.12f,segLen, steel);
        addBox(out, C + vR*(-gauge*0.5f), vR,vU,vT, 0.12f,0.12f,segLen, steel);
        addBox(out, C + vU*(-0.35f),      vR,vU,vT, 0.18f,0.30f,segLen, spine);
        if((i&3)==0) addBox(out, C + vU*(-0.18f), vR,vU,vT, gauge*0.7f,0.10f,0.22f, tie);
        if((i%18)==0){
            float g=groundTopAt(P.x,P.z); float h=P.y-0.4f-g;
            if(h>1.0f) addBox(out, Vec3{P.x, g+h*0.5f, P.z},
                              Vec3{1,0,0},Vec3{0,1,0},Vec3{0,0,1}, 0.35f,h*0.5f,0.35f, post);
        }
    }

    // train: a few cars near the start
    Vec3 carBody{0.92f,0.20f,0.28f}, carDark{0.12f,0.13f,0.16f};
    for(int car=0; car<4 && 5+car*3 < N-1; car++){
        int i=5+car*3;
        Vector3 P=trk.cp[i]; if(!inPatch(P)) continue;
        Vector3 T=Vector3Normalize(Vector3Subtract(trk.cp[i+1], trk.cp[i]));
        Vector3 U=Vector3Normalize(trk.up[i]);
        Vector3 R=Vector3Normalize(Vector3CrossProduct(T,U)); U=Vector3Normalize(Vector3CrossProduct(R,T));
        Vec3 vT=v3(T),vU=v3(U),vR=v3(R), C=v3(P)+vU*0.55f;
        addBox(out,C,vR,vU,vT, 1.0f,0.6f,1.7f, carBody);
        addBox(out,C+vU*0.7f,vR,vU,vT, 0.75f,0.35f,1.0f, carDark);
    }
}

// Centroid of the first K control points (terrain/camera focus).
inline Vec3 trackFocus(const ::Track& trk, int K){
    Vec3 c{0,0,0}; int n=0;
    for(int i=0;i<K && i<(int)trk.cp.size(); i++){ c=c+v3(trk.cp[i]); n++; }
    return n? c*(1.0f/n) : Vec3{0,0,0};
}

} // namespace world
