// Real coaster-world terrain: heightfield ported VERBATIM from the raylib sim
// (mythostest/src/main.cpp terrainH/groundTopAt) -> visible-face voxel mesh.
#pragma once
#include "math.h"
#include <vector>
#include <cmath>
#include <algorithm>
#include <dispatch/dispatch.h>   // GCD: parallel terrain height sampling

struct MeshVertex {
    float pos[3];
    float normal[3];
    float albedo[3];
    float tile;        // TILE CLASS for the in-shader 16x16 procedural texture (see TileClass)
};

// Texture tile class carried per face -> the RT shader reproduces the software game's
// 16x16 procedural atlas (src/main.cpp makeAtlas) as albedo-detail modulation. One id
// per material look; grass TOP vs dirt SIDE is a per-face split (real Minecraft block).
enum TileClass {
    TILE_GRASS = 0,   // turf TOP: clumps + upright blades + bright sunlit tips (T_GRASS)
    TILE_DIRT  = 1,   // dirt SIDE / body: granular + pebbles + faint cracks (T_GRAIN)
    TILE_SAND  = 2,   // beach sand: finer granular, low contrast (T_GRAIN)
    TILE_ROCK  = 3,   // stone: granular + pebbles + cracks, harder contrast (T_GRAIN)
    TILE_SNOW  = 4,   // snow cap: faint sparkle speckle, very low contrast
    TILE_LEAF  = 5,   // foliage: clumpy with darker gaps (T_LEAF)
    TILE_WOOD  = 6,   // bark: vertical fibre streaks + knot (T_LOG)
    TILE_WATER = 7,   // water: untextured (shader skips)
};

// --- sim constants (ported from main.cpp) ---
static const float TERRA_MAX = 320.0f;
static const float WATER_Y   = 30.0f;

// --- terrain noise, ported VERBATIM from mythostest/src/main.cpp ---
static inline float t_Clamp(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
static float smooth01(float a, float b, float x) {
    float t = t_Clamp((x - a) / (b - a), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}
static float hashf(int x, int z) {
    uint32_t h = (uint32_t)x * 374761393u + (uint32_t)z * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= h >> 16;
    return (h & 0xffffff) / 16777215.0f;
}
static float vnoise(float x, float z) {
    int xi = (int)floorf(x), zi = (int)floorf(z);
    float xf = x - xi, zf = z - zi;
    xf = xf * xf * (3 - 2 * xf);
    zf = zf * zf * (3 - 2 * zf);
    float a = hashf(xi, zi), b = hashf(xi + 1, zi);
    float c = hashf(xi, zi + 1), d = hashf(xi + 1, zi + 1);
    return a + (b - a) * xf + (c - a) * zf + (a - b - c + d) * xf * zf;
}
static float fbm(float x, float z, int oct) {
    float a = 0, amp = 1, fr = 1, norm = 0;
    for (int i = 0; i < oct; i++) { a += amp * vnoise(x * fr, z * fr); norm += amp; amp *= 0.5f; fr *= 2.0f; }
    return a / norm;
}
static float ridgef(float x, float z, int oct) {
    float a = 0, amp = 1, fr = 1, norm = 0;
    for (int i = 0; i < oct; i++) {
        float n = 1.0f - fabsf(vnoise(x * fr, z * fr) * 2.0f - 1.0f);
        a += amp * n * n; norm += amp; amp *= 0.5f; fr *= 2.0f;
    }
    return a / norm;
}
static int terrainH(float x, float z) {
    float warpX = (vnoise(x * 0.0011f + 17.5f, z * 0.0011f + 91.0f) - 0.5f) * 220.0f;
    float warpZ = (vnoise(x * 0.0011f + 53.0f, z * 0.0011f + 11.5f) - 0.5f) * 220.0f;
    float wx = x + warpX, wz = z + warpZ;

    float c   = fbm(wx * 0.0015f + 0.5f,  wz * 0.0015f + 0.5f, 3);
    float e   = fbm(wx * 0.0040f + 31.7f, wz * 0.0040f + 12.3f, 2);
    float pv  = ridgef(wx * 0.0048f + 5.0f, wz * 0.0048f + 9.0f, 3);
    float det = fbm(wx * 0.020f, wz * 0.020f, 2);
    float mesaMask = smooth01(0.58f, 0.82f, fbm(wx * 0.0010f + 101.0f, wz * 0.0010f + 44.0f, 2));
    float basin    = smooth01(0.72f, 0.94f, 1.0f - ridgef(wx * 0.0022f + 3.7f, wz * 0.0022f + 8.1f, 2));
    float mountainRegion = smooth01(0.50f, 0.84f, fbm(wx * 0.00085f + 9.0f, wz * 0.00085f + 73.0f, 2));
    float valleyMask = smooth01(0.62f, 0.90f, ridgef(wx * 0.0017f + 61.0f, wz * 0.0017f + 19.0f, 2));

    float midHill = fbm(wx * 0.008f + 32.0f, wz * 0.008f + 77.0f, 3) - 0.5f;
    float base = 24.0f + powf(c, 1.30f) * 150.0f;
    float mAmp = powf(1.0f - e, 1.62f);
    float mtn  = powf(pv, 2.36f) * mAmp * (92.0f + 142.0f * mountainRegion);
    float h = base + mtn + (det - 0.5f) * 14.0f + midHill * 22.0f;
    h += powf(pv, 5.0f) * smooth01(0.48f, 0.92f, mountainRegion) * (42.0f + 46.0f * (1.0f - e));

    h -= basin * (22.0f + 48.0f * (1.0f - c));
    h -= valleyMask * (1.0f - mesaMask) * (8.0f + 18.0f * (1.0f - c));
    float terraceStep = 5.0f + 8.0f * vnoise(wx * 0.0018f + 211.0f, wz * 0.0018f + 37.0f);
    float terraced = floorf(h / terraceStep) * terraceStep + (det - 0.5f) * 3.0f;
    h = h + (terraced - h) * mesaMask * 0.58f;
    h += mesaMask * smooth01(0.35f, 0.70f, c) * 18.0f;
    if (h < 1) h = 1; if (h > TERRA_MAX) h = TERRA_MAX;
    return (int)h;
}
static float groundTopAt(float x, float z) {
    return fmaxf((float)terrainH(x, z) + 1.0f, WATER_Y);
}

// ---------------------------------------------------------------------------
// BIOME SYSTEM — ported 1:1 from src/main.cpp's per-column biome pick (~line 2132).
// Humidity/temperature/bio noise + height select a biome, which sets the surface
// CAP colour, the COLUMN (dirt body) colour, and the tree TYPE + per-area DENSITY.
// Renderer-agnostic (pure function of world x,z + column height) so it ports cleanly
// to DXR/Vulkan. treeType: -1 none, 0 oak, 1 birch, 2 spruce, 3 acacia.
// ---------------------------------------------------------------------------
struct Biome {
    float3 cap;        // surface cap colour
    float3 col;        // dirt/body column colour
    int    treeType;   // -1 none, 0 oak, 1 birch, 2 spruce, 3 acacia
    float  treeDen;    // per-area tree density (probability per m^2-ish)
};
static inline float3 rgb8(int r, int g, int b) {
    return vec3(r / 255.0f, g / 255.0f, b / 255.0f);
}
static Biome biomeAt(float wx, float wz, int h, bool beach) {
    Biome bm;
    bm.treeType = -1; bm.treeDen = 0.0f;
    // Biome-selection noise: ~150m biome regions so SEVERAL distinct biomes are visible at
    // once within the (closer, 380m) render horizon -- the software's very-low freq made one
    // biome fill the whole view ("only green plains"); too-high freq fragments it. This is the
    // middle ground: coherent regions, but multiple per view.
    float bio   = vnoise(wx * 0.0070f + 91.3f, wz * 0.0070f + 23.1f);
    float humid = fbm(wx * 0.0045f + 44.0f,  wz * 0.0045f + 108.0f, 2);
    float temp  = fbm(wx * 0.0030f + 12.0f,  wz * 0.0030f + 204.0f, 2);
    float3 capC = rgb8(130, 206, 102);   // GRASS
    float3 colC = rgb8(158, 116,  82);   // DIRT
    bool grassCap = true;
    // wobble the altitude bands so grass->stone->snow is an IRREGULAR coastline, not a
    // dead-flat contour line. ±~22m of noisy threshold offset breaks the hard band edge.
    int hb = h + (int)((fbm(wx*0.030f + 7.3f, wz*0.030f + 5.1f, 2) - 0.5f) * 44.0f);
    if (hb >= 252)      { capC = rgb8(204,214,224); colC = rgb8(132,140,154); grassCap = false; } // snowcap
    else if (hb >= 152) { capC = rgb8(128,138,146); colC = rgb8(108,116,126); grassCap = false; } // high stone
    else if (beach)    { capC = rgb8(242,228,184); grassCap = false; }                            // sand
    else if (humid < 0.23f && temp > 0.42f) { capC = rgb8(214,196,108); colC = rgb8(162,126,72); grassCap = false; bm.treeType = 3; bm.treeDen = 0.003f; } // dry scrub
    else if (humid > 0.72f && bio < 0.72f)  { capC = rgb8( 76,176, 92); colC = rgb8(118, 96,72);                  bm.treeType = 0; bm.treeDen = 0.032f; } // lush woodland
    else if (bio < 0.34f) {                                                                        bm.treeType = 0; bm.treeDen = 0.007f; } // plains
    else if (bio < 0.58f) { capC = rgb8(118,206,108);                                              bm.treeType = 1; bm.treeDen = 0.022f; } // forest
    else if (bio < 0.78f) { capC = rgb8(210,202,132);                                              bm.treeType = 3; bm.treeDen = 0.004f; } // savanna
    else                  { capC = rgb8(112,150,112); colC = rgb8(118,104,86);                     bm.treeType = 2; bm.treeDen = 0.010f; } // cool spruce/tundra
    // tycoon-style soft ground patches: a low-freq tint nudges grass between lush and
    // sun-bleached so the land never reads flat (only on grass-capped biomes).
    if (grassCap) {
        float patch = vnoise(wx * 0.03f + 7.7f, wz * 0.03f + 4.2f);
        float3 lush = rgb8(96,188,96), dry = rgb8(196,206,120);
        float3 mix  = lush + (dry - lush) * patch;
        capC = capC + (mix - capC) * 0.35f;
    }
    bm.cap = capC; bm.col = colC;
    return bm;
}

// Visible-face voxel mesh over a rectangular world region centred on the
// coaster. Heights come from the real terrainH(); a flat water plane fills
// any cell whose ground sits below WATER_Y.
struct Terrain {
    std::vector<MeshVertex> verts; // 3 verts per triangle, flat-shaded
    float originX, originZ;        // world coords of cell (0,0)
    float cell;                    // world units per cell (xz and y voxel)
    int   gridN;
    float worldSize;
};

// pushQuad as two CCW triangles into a vertex vector. `tile` selects the in-shader
// 16x16 procedural texture for this face (defaults to dirt for legacy call sites).
static void pushQuad(std::vector<MeshVertex>& out, float3 a, float3 b, float3 c, float3 d,
                     float3 n, float3 albedo, float tile = (float)TILE_DIRT) {
    float3 ps[6] = {a, b, c, a, c, d};
    for (int i = 0; i < 6; i++) {
        MeshVertex v;
        v.pos[0]=ps[i].x; v.pos[1]=ps[i].y; v.pos[2]=ps[i].z;
        v.normal[0]=n.x; v.normal[1]=n.y; v.normal[2]=n.z;
        v.albedo[0]=albedo.x; v.albedo[1]=albedo.y; v.albedo[2]=albedo.z;
        v.tile = tile;
        out.push_back(v);
    }
}

// Axis-aligned box centred at (cx,cy,cz) with full extents (w,h,l). Six flat
// quads with explicit outward normals (used for tree trunks/canopies). `tile`
// applies to all six faces (trunk = WOOD, canopy = LEAF).
static void pushVoxBox(std::vector<MeshVertex>& out, float cx, float cy, float cz,
                       float w, float h, float l, float3 a, float tile = (float)TILE_DIRT) {
    float x0=cx-w*0.5f, x1=cx+w*0.5f, y0=cy-h*0.5f, y1=cy+h*0.5f, z0=cz-l*0.5f, z1=cz+l*0.5f;
    pushQuad(out, vec3(x0,y0,z1),vec3(x1,y0,z1),vec3(x1,y1,z1),vec3(x0,y1,z1), vec3(0,0,1),  a, tile); // +z
    pushQuad(out, vec3(x1,y0,z0),vec3(x0,y0,z0),vec3(x0,y1,z0),vec3(x1,y1,z0), vec3(0,0,-1), a, tile); // -z
    pushQuad(out, vec3(x1,y0,z1),vec3(x1,y0,z0),vec3(x1,y1,z0),vec3(x1,y1,z1), vec3(1,0,0),  a, tile); // +x
    pushQuad(out, vec3(x0,y0,z0),vec3(x0,y0,z1),vec3(x0,y1,z1),vec3(x0,y1,z0), vec3(-1,0,0), a, tile); // -x
    pushQuad(out, vec3(x0,y1,z1),vec3(x1,y1,z1),vec3(x1,y1,z0),vec3(x0,y1,z0), vec3(0,1,0),  a, tile); // +y
    pushQuad(out, vec3(x0,y0,z0),vec3(x1,y0,z0),vec3(x1,y0,z1),vec3(x0,y0,z1), vec3(0,-1,0), a, tile); // -y
}

// A simple low-poly voxel tree (trunk + a couple of canopy boxes) sitting on the
// ground top (cx, topY, cz). Type 0 oak, 1 birch, 2 spruce. Deliberately
// tree-ONLY (no flowers/rocks/mushrooms) and only 3-4 boxes each so the RT
// triangle load stays modest.
static void pushTree(std::vector<MeshVertex>& out, float cx, float topY, float cz, int type, float vr) {
    // Minecraft-style tree built ONLY from 1x1x1 grid-aligned blocks. cx,cz = cell
    // CENTRE, topY = terrain top face (integer metres). Every block is a unit cube
    // centred at (cx+dx, topY+0.5+dy, cz+dz) for INTEGER dx,dy,dz -> it snaps to the
    // 1m grid, sits FLUSH on the ground (no half-block float), and never overlaps a
    // neighbour (the trunk column is skipped wherever a leaf would sit on it).
    auto blk = [&](int dx, int dy, int dz, float3 c, float tile) {
        pushVoxBox(out, cx + (float)dx, topY + 0.5f + (float)dy, cz + (float)dz, 1.0f, 1.0f, 1.0f, c, tile);
    };
    int hv = (vr > 0.5f) ? 1 : 0;                          // +1 block height variation
    if (type == 3) {                                       // acacia: tall trunk + flat umbrella canopy (savanna/scrub)
        float3 bark = vec3(0.42f,0.30f,0.18f), lf = vec3(0.50f,0.56f,0.24f);  // warm bark, dry yellow-green canopy
        int H = 5 + hv;
        for (int i = 0; i < H; i++) blk(0, i, 0, bark, (float)TILE_WOOD);
        int t = H;                                         // flat canopy sits on top of the trunk
        for (int dx = -1; dx <= 1; dx++) for (int dz = -1; dz <= 1; dz++)   // 3x3 flat core
            blk(dx, t, dz, lf, (float)TILE_LEAF);
        blk( 2,t,0,lf,(float)TILE_LEAF); blk(-2,t,0,lf,(float)TILE_LEAF);   // + arms -> broad flat umbrella
        blk( 0,t,2,lf,(float)TILE_LEAF); blk( 0,t,-2,lf,(float)TILE_LEAF);
        blk( 0,t+1,0,lf,(float)TILE_LEAF);                                  // small crown bump
    } else if (type == 2) {                                // spruce: narrow conifer
        float3 bark = vec3(0.30f,0.22f,0.14f), lf = vec3(0.20f,0.37f,0.24f);
        int H = 6 + hv;
        for (int i = 0; i < H; i++) blk(0, i, 0, bark, (float)TILE_WOOD);
        int t = H - 1;
        for (int d = -1; d <= 1; d += 2) { blk(d,t-3,0,lf,(float)TILE_LEAF); blk(0,t-3,d,lf,(float)TILE_LEAF);   // skirt (plus)
                                           blk(d,t-2,0,lf,(float)TILE_LEAF); blk(0,t-2,d,lf,(float)TILE_LEAF); }  // mid  (plus)
        for (int d = -1; d <= 1; d += 2) { blk(d,t-1,0,lf,(float)TILE_LEAF); blk(0,t-1,d,lf,(float)TILE_LEAF); }  // upper (plus)
        blk(0, t,   0, lf, (float)TILE_LEAF);                                        // tip above trunk
        blk(0, t+1, 0, lf, (float)TILE_LEAF);
    } else {                                               // oak / birch: column + bushy crown
        bool birch = (type == 1);
        float3 bark = birch ? vec3(0.80f,0.78f,0.72f) : vec3(0.40f,0.27f,0.15f);
        float3 lf   = birch ? vec3(0.42f,0.60f,0.30f) : vec3(0.28f,0.50f,0.20f);
        int H = (birch ? 5 : 4) + hv;
        for (int i = 0; i < H; i++) blk(0, i, 0, bark, (float)TILE_WOOD);
        int t = H - 1;
        // 3x3 ring straddling the top trunk block (trunk holds the centre), then a
        // 3x3-minus-corners layer, then a single cap -> compact crown, zero overlap.
        for (int dx = -1; dx <= 1; dx++) for (int dz = -1; dz <= 1; dz++) {
            if (dx == 0 && dz == 0) continue;              // trunk occupies the centre here
            blk(dx, t, dz, lf, (float)TILE_LEAF);
        }
        for (int dx = -1; dx <= 1; dx++) for (int dz = -1; dz <= 1; dz++) {
            if (abs(dx) == 1 && abs(dz) == 1) continue;    // clip corners -> round crown
            blk(dx, t + 1, dz, lf, (float)TILE_LEAF);
        }
        blk(0, t + 2, 0, lf, (float)TILE_LEAF);            // cap
    }
}

// Mesh an N x N cell region. centerX/centerZ are the world center; `cell` is the
// voxel size in world units (height snapped to that grid for the blocky look).
// cps/ncps (optional) are the track control points used to keep trees clear of
// the coaster.
//
// GREEDY MESHED: at 1m blocks the per-cell quad approach explodes the triangle
// count, so coplanar same-albedo top faces (and same-height side-wall runs) are
// merged into the largest possible rectangles. Only EXPOSED faces are emitted
// (a side wall only where the neighbour is lower), and shared interior faces
// between two solid voxels are never generated at all.
static Terrain buildTerrain(float centerX, float centerZ, int N = 220, float cell = 6.0f,
                            const float3* cps = nullptr, int ncps = 0) {
    Terrain t;
    t.gridN = N;
    t.cell = cell;
    t.worldSize = N * cell;
    t.originX = centerX - t.worldSize * 0.5f;
    t.originZ = centerZ - t.worldSize * 0.5f;

    auto worldX = [&](int x) { return t.originX + x * cell; };
    auto worldZ = [&](int z) { return t.originZ + z * cell; };

    // Sample heights (in voxel units) once per cell. terrainH is heavy multi-octave
    // noise and at 1m blocks there are N*N (~0.5M) cells, so sample the rows in
    // parallel across cores (GCD) — this is the dominant rebuild cost. Run at UTILITY
    // QoS so the OS preempts it for the higher-priority render thread (the rebuild
    // runs on a worker; starving the frame loop with USER_INITIATED caused hitches).
    std::vector<int> H(N * N);
    {
        int* Hp = H.data();
        float ox = t.originX, oz = t.originZ, cl = cell;
        dispatch_apply((size_t)N, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                       ^(size_t z) {
            for (int x = 0; x < N; x++) {
                float wx = ox + x * cl + cl * 0.5f, wz = oz + (int)z * cl + cl * 0.5f;
                Hp[z * N + x] = (int)floorf((float)terrainH(wx, wz) / cl + 0.5f);
            }
        });
    }
    auto h_at = [&](int x, int z) -> int {
        if (x < 0 || z < 0 || x >= N || z >= N) return 0;
        return H[z * N + x];
    };

    int waterLvl = (int)floorf(WATER_Y / cell + 0.5f);

    float3 grass = vec3(0.22f, 0.42f, 0.15f);
    float3 grassHi = vec3(0.24f, 0.44f, 0.16f);   // near-identical; grain adds variation
    float3 dirt  = vec3(0.36f, 0.25f, 0.15f);
    float3 rock  = vec3(0.40f, 0.39f, 0.40f);
    float3 snow  = vec3(0.90f, 0.92f, 0.96f);
    float3 sand  = vec3(0.76f, 0.69f, 0.46f);
    float3 water = vec3(0.16f, 0.34f, 0.46f);

    int snowLvl = (int)(200.0f / cell);
    int rockLvl = (int)(150.0f / cell);

    // albedo class id per cell (so the greedy pass merges only matching faces).
    // 0 sand, 1 snow, 2 rock, 3 grass, 4 grassHi. Precomputed ONCE into AC[] so the
    // greedy extension loops are O(1) lookups, not 5 h_at calls each (rebuild speed).
    std::vector<unsigned char> AC(N * N);
    for (int z = 0; z < N; z++)
        for (int x = 0; x < N; x++) {
            int h = H[z * N + x];
            int slope = std::abs(h - h_at(x-1,z)) + std::abs(h - h_at(x+1,z)) +
                        std::abs(h - h_at(x,z-1)) + std::abs(h - h_at(x,z+1));
            unsigned char c;
            if      (h <= waterLvl + 1)         c = 0;
            else if (h >= snowLvl)              c = 1;
            else if (h >= rockLvl || slope >= 6) c = 2;
            else                                c = ((x ^ z) & 1) ? 3 : 4;
            AC[z * N + x] = c;
        }
    auto albClass = [&](int x, int z) -> int { return AC[z * N + x]; };
    float3 classAlb[5] = { sand, snow, rock, grass, grassHi };

    // --- trees on flat-ish grass cells (deterministic, track-cleared) ---
    // (unchanged: still per-cell; trees are sparse so they don't blow the budget)
    for (int z = 0; z < N; z++) {
        for (int x = 0; x < N; x++) {
            int h = h_at(x, z);
            int slope = std::abs(h - h_at(x-1,z)) + std::abs(h - h_at(x+1,z)) +
                        std::abs(h - h_at(x,z-1)) + std::abs(h - h_at(x,z+1));
            int ac = albClass(x, z);
            bool isGrass = (ac == 3 || ac == 4);
            if (cps && isGrass && h < snowLvl && slope < 4) {
                float wcx = worldX(x) + cell * 0.5f, wcz = worldZ(z) + cell * 0.5f;
                float topY = h * cell;
                int ax = (int)floorf(wcx / cell), az = (int)floorf(wcz / cell);
                // per-AREA density (independent of cell size, so finer terrain
                // doesn't multiply the tree count and blow up the triangle budget).
                // Thinned (0.07->0.028->0.013) so trees scatter sparsely (open grassland
                // with stands of trees, not a wall-to-wall forest) and stay a small RT cost.
                float dens = 0.013f * (cell / 6.0f) * (cell / 6.0f);
                if (hashf(ax * 7 + 1, az * 7 + 3) < dens) {
                    bool clear = true;                            // keep a corridor clear of track
                    for (int k = 0; k < ncps; k++) {
                        float dx = cps[k].x - wcx, dz = cps[k].z - wcz;
                        if (dx*dx + dz*dz < 49.0f) { clear = false; break; }
                    }
                    if (clear) {
                        float r2 = hashf(ax * 3 + 5, az * 9 + 2);
                        int type = (h > rockLvl - 6) ? 2 : (r2 < 0.30f ? 1 : 0);   // spruce up high
                        float s  = 1.3f + hashf(ax * 5 + 7, az * 5 + 1) * 0.9f;    // realistic tree height (~8-13m)
                        pushTree(t.verts, wcx, topY, wcz, type, s);
                    }
                }
            }
        }
    }

    // --- GREEDY top faces: merge runs of cells sharing (height, albedo class) ---
    std::vector<char> done(N * N, 0);
    for (int z = 0; z < N; z++) {
        for (int x = 0; x < N; x++) {
            if (done[z * N + x]) continue;
            int h = h_at(x, z), ac = albClass(x, z);
            // extend in +x while same height + albedo
            int w = 1;
            while (x + w < N && !done[z * N + x + w] &&
                   h_at(x + w, z) == h && albClass(x + w, z) == ac) w++;
            // extend in +z while the whole [x, x+w) row matches
            int d = 1;
            for (; z + d < N; d++) {
                bool ok = true;
                for (int k = 0; k < w; k++)
                    if (done[(z + d) * N + x + k] || h_at(x + k, z + d) != h ||
                        albClass(x + k, z + d) != ac) { ok = false; break; }
                if (!ok) break;
            }
            for (int dz = 0; dz < d; dz++)
                for (int dx = 0; dx < w; dx++) done[(z + dz) * N + x + dx] = 1;

            float topY = h * cell;
            float x0 = worldX(x), x1 = worldX(x + w);
            float z0 = worldZ(z), z1 = worldZ(z + d);
            pushQuad(t.verts, vec3(x0, topY, z0), vec3(x1, topY, z0),
                     vec3(x1, topY, z1), vec3(x0, topY, z1), vec3(0, 1, 0), classAlb[ac]);
        }
    }

    // --- GREEDY side walls: one direction at a time, merge equal (top,bottom) runs ---
    // -x / +x walls run along z; -z / +z walls run along x.
    auto wallX = [&](int sign) {              // sign = -1 (face -x) or +1 (face +x)
        for (int x = 0; x < N; x++) {
            for (int z = 0; z < N; ) {
                int h = h_at(x, z), nb = h_at(x + sign, z);
                if (nb >= h) { z++; continue; }
                int run = 1;
                while (z + run < N && h_at(x, z + run) == h && h_at(x + sign, z + run) == nb) run++;
                float y0 = (float)(nb + 1) * cell, y1 = (float)(h + 1) * cell;
                float zz0 = worldZ(z), zz1 = worldZ(z + run);
                float wx = (sign < 0) ? worldX(x) : worldX(x + 1);
                if (sign < 0)
                    pushQuad(t.verts, vec3(wx,y0,zz0), vec3(wx,y0,zz1), vec3(wx,y1,zz1), vec3(wx,y1,zz0),
                             vec3(-1,0,0), dirt);
                else
                    pushQuad(t.verts, vec3(wx,y0,zz1), vec3(wx,y0,zz0), vec3(wx,y1,zz0), vec3(wx,y1,zz1),
                             vec3(1,0,0), dirt);
                z += run;
            }
        }
    };
    auto wallZ = [&](int sign) {              // sign = -1 (face -z) or +1 (face +z)
        for (int z = 0; z < N; z++) {
            for (int x = 0; x < N; ) {
                int h = h_at(x, z), nb = h_at(x, z + sign);
                if (nb >= h) { x++; continue; }
                int run = 1;
                while (x + run < N && h_at(x + run, z) == h && h_at(x + run, z + sign) == nb) run++;
                float y0 = (float)(nb + 1) * cell, y1 = (float)(h + 1) * cell;
                float xx0 = worldX(x), xx1 = worldX(x + run);
                float wz = (sign < 0) ? worldZ(z) : worldZ(z + 1);
                if (sign < 0)
                    pushQuad(t.verts, vec3(xx1,y0,wz), vec3(xx0,y0,wz), vec3(xx0,y1,wz), vec3(xx1,y1,wz),
                             vec3(0,0,-1), dirt);
                else
                    pushQuad(t.verts, vec3(xx0,y0,wz), vec3(xx1,y0,wz), vec3(xx1,y1,wz), vec3(xx0,y1,wz),
                             vec3(0,0,1), dirt);
                x += run;
            }
        }
    };
    wallX(-1); wallX(+1); wallZ(-1); wallZ(+1);

    // --- GREEDY water surface: merge runs of submerged cells (h < waterLvl) ---
    std::fill(done.begin(), done.end(), 0);
    for (int z = 0; z < N; z++) {
        for (int x = 0; x < N; x++) {
            if (done[z * N + x] || h_at(x, z) >= waterLvl) continue;
            int w = 1;
            while (x + w < N && !done[z * N + x + w] && h_at(x + w, z) < waterLvl) w++;
            int d = 1;
            for (; z + d < N; d++) {
                bool ok = true;
                for (int k = 0; k < w; k++)
                    if (done[(z + d) * N + x + k] || h_at(x + k, z + d) >= waterLvl) { ok = false; break; }
                if (!ok) break;
            }
            for (int dz = 0; dz < d; dz++)
                for (int dx = 0; dx < w; dx++) done[(z + dz) * N + x + dx] = 1;
            float wy = WATER_Y;
            float x0 = worldX(x), x1 = worldX(x + w), z0 = worldZ(z), z1 = worldZ(z + d);
            pushQuad(t.verts, vec3(x0, wy, z0), vec3(x1, wy, z0), vec3(x1, wy, z1), vec3(x0, wy, z1),
                     vec3(0, 1, 0), water);
        }
    }
    return t;
}

// ===========================================================================
// INCREMENTAL CHUNK MESHER
// ---------------------------------------------------------------------------
// Mesh a SINGLE fixed-size terrain chunk keyed to ABSOLUTE world cell coords, so
// the ring can re-mesh only the edge strips that scrolled into view (and drop the
// ones that left) instead of re-meshing the whole multi-million-tri ring on every
// re-centre. A chunk covers cells [cellX0, cellX0+M) x [cellZ0, cellZ0+M) at 1m.
//
// SEAM HANDLING: heights are sampled over an (M+2)x(M+2) grid with a 1-cell border
// of padding, but tops/walls/water/trees are emitted ONLY for the inner MxM cells.
// The padding gives the border cells their TRUE neighbour heights (which live in the
// adjacent chunk) so side walls at chunk boundaries are emitted correctly. Wall
// ownership is unambiguous: a wall between cell A (higher) and neighbour B (lower)
// is emitted only by A's chunk (B's chunk sees nb>=h and skips it) -> every seam
// wall appears exactly once, no holes, no double walls. Because heights come from
// the deterministic terrainH() and trees are world-cell-keyed, a chunk meshes
// identically no matter which ring re-centre brought it into view -> no popping.
// `serial`: sample heights on the CALLING thread instead of fanning out across all
// cores via dispatch_apply. The live ring re-centre meshes its new chunks on a
// background worker; if that worker grabs every core (dispatch_apply) it briefly
// starves the render thread -> a frame-time spike right after each re-centre. Serial
// sampling keeps the worker to one core so the render keeps its cores and stays smooth.
// The sync init/--shot path passes serial=false for the fastest one-off build.
static void buildTerrainChunk(std::vector<MeshVertex>& out,
                              int cellX0, int cellZ0, int M, float cell,
                              const float3* cps, int ncps,
                              const unsigned char* cpsKind = nullptr, bool serial = false) {
    const int P = M + 2;                       // padded grid (1-cell border each side)
    float ox = cellX0 * cell, oz = cellZ0 * cell;
    auto worldX = [&](int x) { return ox + x * cell; };   // x in [0,M] indexes inner-cell world
    auto worldZ = [&](int z) { return oz + z * cell; };

    // Sample padded heights: padded index (px,pz) maps to inner cell (px-1, pz-1).
    std::vector<int> H(P * P);
    {
        int* Hp = H.data();
        auto sampleRow = [&](int pz) {
            for (int px = 0; px < P; px++) {
                float wx = ox + (px - 1) * cell + cell * 0.5f;
                float wz = oz + (pz - 1) * cell + cell * 0.5f;
                Hp[pz * P + px] = (int)floorf((float)terrainH(wx, wz) / cell + 0.5f);
            }
        };
        if (serial) { for (int pz = 0; pz < P; pz++) sampleRow(pz); }
        else dispatch_apply((size_t)P, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                            ^(size_t pz) { sampleRow((int)pz); });
    }
    // h_at takes INNER cell coords (0..M-1 valid; -1 and M reach into the padding).
    auto h_at = [&](int x, int z) -> int { return H[(z + 1) * P + (x + 1)]; };

    // --- TRACK CARVE -------------------------------------------------------------
    // Bore a clean, NARROW channel under the coaster so hills can't poke up through
    // the track, WITHOUT trenching the whole landscape. Control points are ~14m apart
    // (SEG_LEN), so a per-POINT disc either leaves gaps between points (terrain pokes
    // through) or, if widened to bridge the gap, gouges a huge swath. Instead we carve
    // along each track SEGMENT (a swept disc / capsule): for every cell we find the
    // nearest segment, take the track height INTERPOLATED at the closest point, and if
    // the terrain sits above that height minus head clearance we lower the column to it.
    // The floor FOLLOWS the track height along the run -> a believable continuous channel
    // that hugs the spline, not a flat trench. Runs over the PADDED grid so seam walls
    // stay consistent; pure function of (cell, track pts) so adjacent chunks agree.
    // `carved[]` marks inner cells so no tree/decoration sits on a bored column.
    const float CARVE_R   = 6.5f;     // horizontal half-width of the bored channel (m): widened 4->6.5 so the train + its swing on banked sections clears the channel walls where the track passes through terrain (the carve looked "broken" = train clipping the too-tight 4m channel)
    const float CARVE_R2  = CARVE_R * CARVE_R;
    const float HEAD_CLR  = 4.0f;     // carved floor this far below the track (m): 2.5->4 so the train body/wheels never clip the channel floor
    std::vector<char> carved(M * M, 0);
    if (cps && ncps > 0) {
        // prune to track SEGMENTS (k -> k+1) whose capsule can touch this padded chunk.
        float minWX = ox - cell, maxWX = ox + (M + 1) * cell;
        float minWZ = oz - cell, maxWZ = oz + (M + 1) * cell;
        std::vector<float3> segA, segB;     // endpoints of nearby segments
        segA.reserve(64); segB.reserve(64);
        for (int k = 0; k + 1 < ncps; k++) {
            float3 a = cps[k], b = cps[k + 1];
            // skip the long teleport between disjoint exported runs (segment far longer
            // than a normal SEG_LEN step would carve a giant false channel).
            float sdx = b.x - a.x, sdz = b.z - a.z;
            if (sdx*sdx + sdz*sdz > 30.0f * 30.0f) continue;
            float loX = fminf(a.x, b.x), hiX = fmaxf(a.x, b.x);
            float loZ = fminf(a.z, b.z), hiZ = fmaxf(a.z, b.z);
            if (hiX < minWX - CARVE_R || loX > maxWX + CARVE_R ||
                hiZ < minWZ - CARVE_R || loZ > maxWZ + CARVE_R) continue;
            segA.push_back(a); segB.push_back(b);
        }
        if (!segA.empty()) {
            int* Hp = H.data();
            const float3* pa = segA.data();
            const float3* pb = segB.data();
            int ns = (int)segA.size();
            for (int pz = 0; pz < P; pz++) {
                float wz = oz + (pz - 1) * cell + cell * 0.5f;
                for (int px = 0; px < P; px++) {
                    float wx = ox + (px - 1) * cell + cell * 0.5f;
                    float bestD2 = CARVE_R2, floorY = 1e9f;
                    for (int k = 0; k < ns; k++) {
                        // closest point on segment a->b to (wx,wz), in the XZ plane
                        float ex = pb[k].x - pa[k].x, ez = pb[k].z - pa[k].z;
                        float ee = ex*ex + ez*ez;
                        float t = ee > 1e-6f ? ((wx - pa[k].x)*ex + (wz - pa[k].z)*ez) / ee : 0.0f;
                        t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
                        float cx = pa[k].x + ex*t, cz = pa[k].z + ez*t;
                        float dx = cx - wx, dz = cz - wz, d2 = dx*dx + dz*dz;
                        if (d2 < bestD2) { bestD2 = d2; floorY = pa[k].y + (pb[k].y - pa[k].y)*t; }
                    }
                    if (floorY > 1e8f) continue;                // no track segment over this cell
                    int floorLvl = (int)floorf((floorY - HEAD_CLR) / cell);
                    if (Hp[pz * P + px] > floorLvl) {
                        Hp[pz * P + px] = floorLvl;             // lower the column to the channel floor
                        int ix = px - 1, iz = pz - 1;           // mark inner cells as carved
                        if (ix >= 0 && ix < M && iz >= 0 && iz < M) carved[iz * M + ix] = 1;
                    }
                }
            }
        }

        // --- HELIX coil interiors: a tight coil encloses a wide disc the per-point
        // carve above can't reach (its centre is > CARVE_R from any coil rail), so a
        // hill pokes up through the open lattice ("massive stone in the middle of
        // helixes"). Port of the software TASK-2a: for each contiguous M_HELIX run,
        // flatten the WHOLE coil disc down to just under the lowest coil. ---
        if (cpsKind) {
            for (int a = 0; a < ncps; ) {
                if (cpsKind[a] != /*M_HELIX*/10) { a++; continue; }
                int b = a; while (b + 1 < ncps && cpsKind[b + 1] == 10) b++;
                if (b - a >= 3) {
                    float axX = 0, axZ = 0, loY = 1e9f; int n = 0;
                    for (int i = a; i <= b; i++) { axX += cps[i].x; axZ += cps[i].z; n++;
                        if (cps[i].y < loY) loY = cps[i].y; }
                    axX /= n; axZ /= n;
                    float radMax = 0;
                    for (int i = a; i <= b; i++) {
                        float rx = cps[i].x - axX, rz = cps[i].z - axZ;
                        float r = sqrtf(rx*rx + rz*rz); if (r > radMax) radMax = r;
                    }
                    float coilR = radMax + 1.0f, coilR2 = coilR * coilR;
                    int   clampLvl = (int)floorf((loY - HEAD_CLR) / cell);
                    int* Hp = H.data();
                    for (int pz = 0; pz < P; pz++) {
                        float wz = oz + (pz - 1) * cell + cell * 0.5f;
                        for (int px = 0; px < P; px++) {
                            float wx = ox + (px - 1) * cell + cell * 0.5f;
                            float dx = wx - axX, dz = wz - axZ;
                            if (dx*dx + dz*dz > coilR2) continue;
                            if (Hp[pz * P + px] > clampLvl) {
                                Hp[pz * P + px] = clampLvl;
                                int ix = px - 1, iz = pz - 1;
                                if (ix >= 0 && ix < M && iz >= 0 && iz < M) carved[iz * M + ix] = 1;
                            }
                        }
                    }
                }
                a = b + 1;
            }
        }
    }

    int waterLvl = (int)floorf(WATER_Y / cell + 0.5f);
    int snowLvl = (int)(200.0f / cell);
    int rockLvl = (int)(150.0f / cell);

    // --- per-cell BIOME (cap colour + column colour + tree type/density). Ported from
    // src/main.cpp's per-column biome pick. The cap colour varies continuously (patch
    // tint), so a QUANTIZED 16-level packed key is computed for greedy-merge equality —
    // same-biome neighbours still merge into big runs, distinct biomes split. Stone/snow
    // and high-slope cells override to the rock/snow look. Keyed to world coords so the
    // biome is identical no matter which chunk meshes a cell (no seam mismatch).
    int MM = M * M;
    std::vector<float3>   capCol(MM), colCol(MM);
    std::vector<uint32_t> capKey(MM);
    std::vector<char>     capTree(MM);     // tree type (-1..3)
    std::vector<float>    capDen(MM);
    std::vector<unsigned char> capTile(MM), colTile(MM);  // per-cell TOP / SIDE texture class
    float3 rockC = vec3(0.40f, 0.39f, 0.40f), snowC = vec3(0.90f, 0.92f, 0.96f);
    // Classify a surface colour into a texture TileClass. Grass = green-dominant; snow =
    // bright + cool; rock = de-saturated grey; sand/dry-earth = warm. Used for both the
    // cap (TOP) and the column (SIDE) so a grass block shows a green grassy top and a
    // dirt-grain side, like real Minecraft. (Reads off the biomeAt output, no new noise.)
    auto classifyTile = [](float3 c, bool sideFace) -> unsigned char {
        float lum = (c.x + c.y + c.z) * (1.0f/3.0f);
        float mx = fmaxf(c.x, fmaxf(c.y, c.z));
        float mn = fminf(c.x, fminf(c.y, c.z));
        float sat = (mx > 1e-4f) ? (mx - mn) / mx : 0.0f;
        if (sat < 0.10f && lum > 0.78f) return TILE_SNOW;            // bright + grey -> snow
        if (sat < 0.14f)               return TILE_ROCK;            // de-saturated grey -> stone
        if (c.y > c.x && c.y > c.z)    return sideFace ? TILE_DIRT : TILE_GRASS; // green cap = grass top, dirt side
        if (c.z < c.y && lum > 0.70f && c.y > 0.62f) return TILE_SAND;          // bright warm pale -> sand
        return TILE_DIRT;                                           // dry earth / dirt body
    };
    for (int z = 0; z < M; z++)
        for (int x = 0; x < M; x++) {
            int h = h_at(x, z);
            int slope = std::abs(h - h_at(x-1,z)) + std::abs(h - h_at(x+1,z)) +
                        std::abs(h - h_at(x,z-1)) + std::abs(h - h_at(x,z+1));
            bool beach = (h <= waterLvl + 1);
            float wx = worldX(x) + cell * 0.5f, wz = worldZ(z) + cell * 0.5f;
            Biome bm = biomeAt(wx, wz, h, beach);
            // exposed high stone / steep slopes read as rock (overrides the biome cap).
            // The rock LINE wobbles with the same noise as biomeAt's bands so grass->stone
            // is an irregular edge, not a dead-flat contour. Steep slopes still always rock.
            int rockWob = rockLvl + (int)((fbm(wx*0.030f + 7.3f, wz*0.030f + 5.1f, 2) - 0.5f) * 44.0f);
            if (h < snowLvl && h < 260 && (h >= rockWob || slope >= 6) && !beach) {
                bm.cap = rockC; bm.col = vec3(0.36f,0.25f,0.15f); bm.treeType = -1;
            }
            int idx = z * M + x;
            capCol[idx] = bm.cap; colCol[idx] = bm.col;
            capTree[idx] = (char)bm.treeType; capDen[idx] = bm.treeDen;
            // beach cells get a SAND top regardless of the warm-cap classifier; the cap
            // classifier handles everything else (grass / rock / snow / dry dirt).
            capTile[idx] = beach ? (unsigned char)TILE_SAND : classifyTile(bm.cap, false);
            colTile[idx] = beach ? (unsigned char)TILE_SAND : classifyTile(bm.col, true);
            uint32_t qr = (uint32_t)(t_Clamp(bm.cap.x,0,1) * 15.0f + 0.5f);
            uint32_t qg = (uint32_t)(t_Clamp(bm.cap.y,0,1) * 15.0f + 0.5f);
            uint32_t qb = (uint32_t)(t_Clamp(bm.cap.z,0,1) * 15.0f + 0.5f);
            capKey[idx] = (qr << 8) | (qg << 4) | qb;
        }
    auto keyAt = [&](int x, int z) -> uint32_t { return capKey[z * M + x]; };
    float3 water = vec3(0.16f, 0.34f, 0.46f);

    // --- trees (deterministic, world-cell-keyed, track-cleared) — biome drives TYPE + DENSITY
    for (int z = 0; z < M; z++)
        for (int x = 0; x < M; x++) {
            int h = h_at(x, z);
            int slope = std::abs(h - h_at(x-1,z)) + std::abs(h - h_at(x+1,z)) +
                        std::abs(h - h_at(x,z-1)) + std::abs(h - h_at(x,z+1));
            int tt = capTree[z * M + x];
            float den = capDen[z * M + x];
            if (cps && tt >= 0 && den > 0.0f && h < snowLvl && slope < 4 && !carved[z * M + x]) {
                int ax = cellX0 + x, az = cellZ0 + z;
                // ONE tree per TGxTG node so canopies never touch (open grass + stands of trees).
                const int TG = 8;   // denser node grid (was 11) -> more trees, fuller stands
                // per-node prob from per-area biome density (raised from 0.45 cap/0.5 scale ->
                // 0.9/0.85: noticeably denser forests/woodland while keeping biome variation).
                float nodeDen = fminf(den * (float)(TG * TG), 0.9f) * 0.85f;
                if (ax % TG == 0 && az % TG == 0 && hashf(ax * 7 + 1, az * 7 + 3) < nodeDen) {
                    // scatter by an INTEGER cell offset (0..3), plant on the TARGET cell and read
                    // ITS height -> the trunk lands on a whole 1m block, FLUSH, no fractional float.
                    // surface = cell TOP = (h+1)*cell (matches groundTopAt + the SW renderer).
                    int tx = x + (int)(hashf(ax*3+1, az*7+5) * 4.0f);
                    int tz = z + (int)(hashf(ax*5+9, az*3+2) * 4.0f);
                    if (tx < M && tz < M && !carved[tz*M + tx]) {
                        float twx = worldX(tx) + cell * 0.5f, twz = worldZ(tz) + cell * 0.5f;
                        float tTopY = (float)(h_at(tx, tz) + 1) * cell;
                        bool clear = true;
                        for (int k = 0; k < ncps; k++) {
                            float dx = cps[k].x - twx, dz = cps[k].z - twz;
                            if (dx*dx + dz*dz < 49.0f) { clear = false; break; }
                        }
                        if (clear) {
                            // biome drives the tree TYPE directly now (no collapse): oak in
                            // plains/woodland, birch in forest, spruce in tundra, acacia in
                            // savanna/scrub — Minecraft-style per-biome variety.
                            pushTree(out, twx, tTopY, twz, tt, hashf(ax*5+7, az*5+1));
                        }
                    }
                }
            }
        }

    // --- GREEDY top faces over the inner MxM cells (merge on height + quantized cap key) ---
    std::vector<char> done(M * M, 0);
    for (int z = 0; z < M; z++)
        for (int x = 0; x < M; x++) {
            if (done[z * M + x]) continue;
            int h = h_at(x, z); uint32_t ac = keyAt(x, z);
            int w = 1;
            while (x + w < M && !done[z * M + x + w] &&
                   h_at(x + w, z) == h && keyAt(x + w, z) == ac) w++;
            int d = 1;
            for (; z + d < M; d++) {
                bool ok = true;
                for (int k = 0; k < w; k++)
                    if (done[(z + d) * M + x + k] || h_at(x + k, z + d) != h ||
                        keyAt(x + k, z + d) != ac) { ok = false; break; }
                if (!ok) break;
            }
            for (int dz = 0; dz < d; dz++)
                for (int dx = 0; dx < w; dx++) done[(z + dz) * M + x + dx] = 1;
            float topY = (float)(h + 1) * cell;   // surface = cell TOP (matches groundTopAt + SW)
            float x0 = worldX(x), x1 = worldX(x + w), z0 = worldZ(z), z1 = worldZ(z + d);
            pushQuad(out, vec3(x0, topY, z0), vec3(x1, topY, z0),
                     vec3(x1, topY, z1), vec3(x0, topY, z1), vec3(0, 1, 0),
                     capCol[z * M + x], (float)capTile[z * M + x]);
        }

    // --- GREEDY side walls (neighbours may be in the padding -> seam walls correct) ---
    auto wallX = [&](int sign) {
        for (int x = 0; x < M; x++)
            for (int z = 0; z < M; ) {
                int h = h_at(x, z), nb = h_at(x + sign, z);
                if (nb >= h) { z++; continue; }
                int run = 1;
                while (z + run < M && h_at(x, z + run) == h && h_at(x + sign, z + run) == nb) run++;
                float y0 = (float)(nb + 1) * cell, y1 = (float)(h + 1) * cell;
                float zz0 = worldZ(z), zz1 = worldZ(z + run);
                float wx = (sign < 0) ? worldX(x) : worldX(x + 1);
                float3 bc = colCol[z * M + x]; float bt = (float)colTile[z * M + x];
                if (sign < 0)
                    pushQuad(out, vec3(wx,y0,zz0), vec3(wx,y0,zz1), vec3(wx,y1,zz1), vec3(wx,y1,zz0), vec3(-1,0,0), bc, bt);
                else
                    pushQuad(out, vec3(wx,y0,zz1), vec3(wx,y0,zz0), vec3(wx,y1,zz0), vec3(wx,y1,zz1), vec3(1,0,0), bc, bt);
                z += run;
            }
    };
    auto wallZ = [&](int sign) {
        for (int z = 0; z < M; z++)
            for (int x = 0; x < M; ) {
                int h = h_at(x, z), nb = h_at(x, z + sign);
                if (nb >= h) { x++; continue; }
                int run = 1;
                while (x + run < M && h_at(x + run, z) == h && h_at(x + run, z + sign) == nb) run++;
                float y0 = (float)(nb + 1) * cell, y1 = (float)(h + 1) * cell;
                float xx0 = worldX(x), xx1 = worldX(x + run);
                float wz = (sign < 0) ? worldZ(z) : worldZ(z + 1);
                float3 bc = colCol[z * M + x]; float bt = (float)colTile[z * M + x];
                if (sign < 0)
                    pushQuad(out, vec3(xx1,y0,wz), vec3(xx0,y0,wz), vec3(xx0,y1,wz), vec3(xx1,y1,wz), vec3(0,0,-1), bc, bt);
                else
                    pushQuad(out, vec3(xx0,y0,wz), vec3(xx1,y0,wz), vec3(xx1,y1,wz), vec3(xx0,y1,wz), vec3(0,0,1), bc, bt);
                x += run;
            }
    };
    wallX(-1); wallX(+1); wallZ(-1); wallZ(+1);

    // --- GREEDY water surface over submerged inner cells ---
    std::fill(done.begin(), done.end(), 0);
    for (int z = 0; z < M; z++)
        for (int x = 0; x < M; x++) {
            if (done[z * M + x] || h_at(x, z) >= waterLvl) continue;
            int w = 1;
            while (x + w < M && !done[z * M + x + w] && h_at(x + w, z) < waterLvl) w++;
            int d = 1;
            for (; z + d < M; d++) {
                bool ok = true;
                for (int k = 0; k < w; k++)
                    if (done[(z + d) * M + x + k] || h_at(x + k, z + d) >= waterLvl) { ok = false; break; }
                if (!ok) break;
            }
            for (int dz = 0; dz < d; dz++)
                for (int dx = 0; dx < w; dx++) done[(z + dz) * M + x + dx] = 1;
            float x0 = worldX(x), x1 = worldX(x + w), z0 = worldZ(z), z1 = worldZ(z + d);
            pushQuad(out, vec3(x0, WATER_Y, z0), vec3(x1, WATER_Y, z0),
                     vec3(x1, WATER_Y, z1), vec3(x0, WATER_Y, z1), vec3(0, 1, 0), water, (float)TILE_WATER);
        }
}
