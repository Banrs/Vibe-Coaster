// T_RAIL is texturally identical to T_IRON (same brushed-metal generator below) but gets
// its own atlas slot so the fragment shader can tell "this quad is a running rail" from
// fragTexCoord alone -- a texcoord-range check is a genuinely per-vertex signal (unlike a
// plain uniform, which rlgl's immediate-mode batching can't scope to a handful of draw
// calls without forcing extra batch flushes), so this needs zero new per-frame draw calls.
enum Tile { T_WHITE, T_GRAIN, T_GRASS, T_PLANK, T_LOG, T_LEAF, T_GOLD, T_IRON, T_RAIL, TILE_N };
static Texture2D gAtlas;

static Texture2D makeAtlas() {
    const int TW = 16, W = TILE_N * TW, H = TW;
    Color *pix = (Color *)RL_MALLOC(W * H * sizeof(Color));

    auto tnoise = [&](int seed, float fx, float fy, float fr) -> float {

        float gx = fx * fr, gy = fy * fr;
        int x0 = (int)floorf(gx), y0 = (int)floorf(gy);
        float sx = gx - x0, sy = gy - y0;
        sx = sx*sx*(3-2*sx); sy = sy*sy*(3-2*sy);
        int xa = ((x0 % (int)fr) + (int)fr) % (int)fr, xb = (xa + 1) % (int)fr;
        int ya = ((y0 % (int)fr) + (int)fr) % (int)fr, yb = (ya + 1) % (int)fr;
        float a = hashf(seed*97 + xa, ya), b = hashf(seed*97 + xb, ya);
        float c = hashf(seed*97 + xa, yb), d = hashf(seed*97 + xb, yb);
        return a + (b-a)*sx + (c-a)*sy + (a-b-c+d)*sx*sy;
    };
    for (int t = 0; t < TILE_N; t++) {
        for (int y = 0; y < TW; y++) {
            for (int x = 0; x < TW; x++) {
                float r1 = hashf(t * 131 + x, y * 3 + 1);
                float r2 = hashf(t * 131 + (x / 2) * 2, ((y / 2) * 2) * 3 + 1);
                float fx = x / 16.0f, fy = y / 16.0f;
                int v = 255;
                switch (t) {
                    case T_WHITE: v = 255; break;
                    case T_GRAIN: {
                        float grain = tnoise(t, fx, fy, 8.0f);
                        float fine  = tnoise(t+50, fx, fy, 16.0f);
                        v = 210 + (int)(40 * grain) + (int)(14 * fine) - 7;
                        if (r2 < 0.16f) v -= 34;
                        else if (r1 > 0.93f) v += 14;

                        float crack = fabsf((fx + 0.18f*sinf(fy*9.0f)) - 0.5f);
                        if (crack < 0.045f && fine > 0.35f) v -= 26;
                    } break;
                    case T_GRASS: {
                        float clump = tnoise(t, fx, fy, 4.0f);
                        v = 198 + (int)(46 * clump);

                        float blade = hashf(x*7 + 13, (y/3)*5);
                        if (blade > 0.82f) v += 22 + (int)(16*r1);
                        else if (r1 < 0.22f) v -= 30;
                        if ((y > 11) && r1 < 0.40f) v -= 12;
                    } break;
                    case T_PLANK: {
                        int row = y / 4;
                        float grain = tnoise(t + row*3, fx, fy, 8.0f);
                        if ((y & 3) == 3) v = 158;
                        else if (((x + row * 5) & 7) == 0 && (y & 3) == 1) v = 176;
                        else v = 210 + (int)(40 * grain);
                    } break;
                    case T_LOG: {
                        float bark = tnoise(t, fx, fy*0.4f, 8.0f);
                        v = 190 + (int)(54 * bark) + (int)(12 * r1) - 6;
                        float kx = fx - 0.62f, ky = fy - 0.34f;
                        if (kx*kx + ky*ky < 0.010f) v -= 40;
                    } break;
                    case T_LEAF: {
                        float clump = tnoise(t, fx, fy, 4.0f);
                        float fine  = tnoise(t+11, fx, fy, 16.0f);
                        v = 196 + (int)(54 * clump) + (int)(18 * fine);
                        if (clump < 0.30f) v -= 36;
                        else if (clump > 0.82f) v += 14;
                    } break;
                    case T_GOLD: {
                        int dx = x > 8 ? x - 8 : 8 - x, dy = y > 8 ? y - 8 : 8 - y;
                        if (x == 0 || x == 15 || y == 0 || y == 15) v = 232;
                        else if (dx + dy < 4) v = 255;
                        else v = 204 + (int)(32 * r1);
                    } break;
                    case T_IRON: case T_RAIL: {
                        // T_RAIL intentionally reuses T_IRON's exact formula (hashed on the
                        // real tile index t, which differs, so the noise phase isn't
                        // identical pixel-for-pixel, but the brushed-metal look matches).
                        float brush = tnoise(t, fx*0.25f, fy, 16.0f);
                        v = 222 + (int)(30 * brush) - ((y == 8 || y == 9) ? 28 : 0);
                        if (r1 > 0.96f) v += 10;
                    } break;
                }
                v = v < 0 ? 0 : (v > 255 ? 255 : v);
                pix[y * W + t * TW + x] = Color{ (unsigned char)v, (unsigned char)v, (unsigned char)v, 255 };
            }
        }
    }
    Image img = { pix, W, H, 1, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };
    Texture2D tx = LoadTextureFromImage(img);
    UnloadImage(img);
    SetTextureFilter(tx, TEXTURE_FILTER_POINT);
    return tx;
}

static bool gVoxelBatchOpen = false;

static void beginVoxelBatch() {
    if (!gVoxelBatchOpen) {
        rlSetTexture(gAtlas.id);
        rlBegin(RL_QUADS);
        gVoxelBatchOpen = true;
    }
}
static void endVoxelBatch() {
    if (gVoxelBatchOpen) {
        rlEnd();
        gVoxelBatchOpen = false;
    }
}

static thread_local bool gCapture = false;

// Terrain vertices are captured into fixed-size 16x16 world buckets. Bucket identity is
// stable across recentering, so unchanged overlap can remain resident while the worker
// builds only newly exposed bands and track-carve dirt.
static const float TERRAIN_BUCKET = 16.0f;   // world units per draw-culling bucket (16x16, MC-style)

// Raylib's UploadMesh reads these arrays but retains their pointers, and its
// UnloadMesh releases them with RL_FREE.  Growing capture data with the same
// allocator lets a finished bucket transfer ownership straight into Mesh;
// the former std::vector staging arrays were copied wholesale into a second
// set of RL_MALLOC buffers on the render thread just before every upload.
template <typename T>
struct CaptureBuffer {
    T *ptr = nullptr;
    size_t count = 0, capacity = 0;

    CaptureBuffer() = default;
    CaptureBuffer(const CaptureBuffer &) = delete;
    CaptureBuffer &operator=(const CaptureBuffer &) = delete;
    CaptureBuffer(CaptureBuffer &&other) noexcept
        : ptr(other.ptr), count(other.count), capacity(other.capacity) {
        other.ptr=nullptr; other.count=other.capacity=0;
    }
    CaptureBuffer &operator=(CaptureBuffer &&other) noexcept {
        if(this==&other) return *this;
        RL_FREE(ptr);
        ptr=other.ptr; count=other.count; capacity=other.capacity;
        other.ptr=nullptr; other.count=other.capacity=0;
        return *this;
    }
    ~CaptureBuffer() { RL_FREE(ptr); }

    void push_back(T value) {
        if(count==capacity) {
            const size_t next=capacity ? capacity*2 : 512;
            void *grown=RL_REALLOC(ptr,next*sizeof(T));
            if(!grown) std::abort();
            ptr=(T *)grown; capacity=next;
        }
        ptr[count++]=value;
    }
    size_t size() const { return count; }
    T *release() {
        T *out=ptr;
        ptr=nullptr; count=capacity=0;
        return out;
    }
};

struct CapBucket {
    CaptureBuffer<float> pos, uv, nrm;
    CaptureBuffer<unsigned char> col;
    Vector3 bmin{ 1e9f, 1e9f, 1e9f }, bmax{ -1e9f, -1e9f, -1e9f };
    int64_t key = 0;
};
// NOT thread_local: exactly like the flat arrays this replaces, only the single in-flight
// worker thread ever writes here (gated by TerrainMesh::building), and the main thread only
// reads it after worker.join() in finish() -- the same single-writer contract as before.
static std::unordered_map<int64_t, CapBucket> gCapBuckets;

static inline int64_t terrainBucketKey(float x, float z) {
    int bx = (int)floorf(x / TERRAIN_BUCKET) + 100000;
    int bz = (int)floorf(z / TERRAIN_BUCKET) + 100000;
    return ((int64_t)bx << 32) | (uint32_t)bz;
}
static inline int terrainBucketX(int64_t key) {
    return (int)(int32_t)((uint64_t)key >> 32) - 100000;
}
static inline int terrainBucketZ(int64_t key) {
    return (int)(int32_t)(uint32_t)key - 100000;
}
// Set ONCE per primitive (by emitCubeTex, from the shape's own centre) before it emits any
// vertices -- capVert must NOT recompute a bucket per vertex: a cube straddling a bucket
// boundary would then split its own triangles across two chunk meshes and tear a gap in
// both of them at every chunk seam.
static thread_local CapBucket *gCapBucket = nullptr;
// Keep every primitive produced by one heightfield cell (surface, walls and
// decorations) in that cell's stable world bucket.  A jittered tree may cross a
// bucket boundary; splitting it into the neighbouring incremental replacement
// would otherwise leave a partial chunk behind.
static thread_local int64_t gCaptureBucketOverride = INT64_MIN;

static inline void capVert(float x, float y, float z, float u, float v,
                           float nx, float ny, float nz, Color c) {
    CapBucket &b = *gCapBucket;
    b.pos.push_back(x); b.pos.push_back(y); b.pos.push_back(z);
    b.uv.push_back(u);  b.uv.push_back(v);
    b.nrm.push_back(nx); b.nrm.push_back(ny); b.nrm.push_back(nz);
    b.col.push_back(c.r); b.col.push_back(c.g); b.col.push_back(c.b); b.col.push_back(c.a);
    if (x < b.bmin.x) b.bmin.x = x; if (x > b.bmax.x) b.bmax.x = x;
    if (y < b.bmin.y) b.bmin.y = y; if (y > b.bmax.y) b.bmax.y = y;
    if (z < b.bmin.z) b.bmin.z = z; if (z > b.bmax.z) b.bmax.z = z;
}
// Emit two independent voxel triangles. The former four-corner indexed optimization
// corrupted atlas interpolation on several drivers and made track/terrain faces look joined.
// The six vertices already form a non-indexed triangle list, so a second sequential index
// array only duplicated staging/upload work without sharing a single vertex.
static inline void capQuad(float nx, float ny, float nz,
                           float ax, float ay, float az, float au, float av, Color ac,
                           float bx, float by, float bz, float bu, float bv, Color bc,
                           float cx, float cy, float cz, float cu, float cv, Color cc,
                           float dx, float dy, float dz, float du, float dv, Color dc) {
    capVert(ax, ay, az, au, av, nx, ny, nz, ac);
    capVert(bx, by, bz, bu, bv, nx, ny, nz, bc);
    capVert(cx, cy, cz, cu, cv, nx, ny, nz, cc);
    capVert(ax, ay, az, au, av, nx, ny, nz, ac);
    capVert(cx, cy, cz, cu, cv, nx, ny, nz, cc);
    capVert(dx, dy, dz, du, dv, nx, ny, nz, dc);
}

struct TerrainChunk { Mesh mesh{}; Vector3 center{}; float radius = 0.0f; int64_t key = 0; };

struct TerrainMesh {
    using WaterBuckets=std::unordered_map<int64_t,std::vector<Vector3>>;

    std::vector<TerrainChunk> chunks;
    WaterBuckets liveWaterBuckets;
    bool live = false;
    int keyCx = INT_MIN, keyCz = INT_MIN;
    std::thread worker;
    bool building = false;
    std::atomic<bool> ready{false};   // worker sets when the CPU build has finished
    int  pendCx = 0, pendCz = 0;

    // Upload-spreading state (see finish()): once the worker's CPU build is done, GPU
    // uploads for the (possibly hundreds of) new chunk buckets are throttled to a few per
    // frame instead of all at once, to avoid a large fps spike on every rebuild.
    std::vector<CapBucket> pendingBuckets;
    std::vector<TerrainChunk> pendingChunks;
    std::unordered_set<int64_t> pendingBuildKeys;
    std::unordered_set<int64_t> pendingDesiredKeys;
    std::unordered_set<int64_t> pendingCarveKeys;
    std::unordered_set<int64_t> lastCarveKeys;
    WaterBuckets pendingWaterBuckets;
    bool rebuildAll = true;
    size_t uploadCursor = 0;
    // UploadMesh is synchronous, so an already-visible world drains a rebuild
    // over several frames while retaining its old resident overlap.
    static const int UPLOAD_BUDGET = 20;

    // Keep recenter steps comfortably inside the unchanged 320 m visible ring.
    static const int REBUILD_CELLS = 56;
    bool needsRebuild(int cx, int cz) const {
        if (building) return false;
        return !live || abs(cx - keyCx) >= REBUILD_CELLS || abs(cz - keyCz) >= REBUILD_CELLS;
    }

    template <class VisitFn>
    void forEachPendingCell(int ccx,int ccz,VisitFn &&visit) const {
        const int ringX0=ccx-TERRA_R,ringX1=ccx+TERRA_R;
        const int ringZ0=ccz-TERRA_R,ringZ1=ccz+TERRA_R;
        for(int64_t key:pendingBuildKeys) {
            const float worldX0=terrainBucketX(key)*TERRAIN_BUCKET;
            const float worldZ0=terrainBucketZ(key)*TERRAIN_BUCKET;
            int cx0=(int)ceilf(worldX0/CELL-0.5f);
            int cx1=(int)ceilf((worldX0+TERRAIN_BUCKET)/CELL-0.5f)-1;
            int cz0=(int)ceilf(worldZ0/CELL-0.5f);
            int cz1=(int)ceilf((worldZ0+TERRAIN_BUCKET)/CELL-0.5f)-1;
            cx0=std::max(cx0,ringX0); cx1=std::min(cx1,ringX1);
            cz0=std::max(cz0,ringZ0); cz1=std::min(cz1,ringZ1);
            for(int cz=cz0;cz<=cz1;++cz)
                for(int cx=cx0;cx<=cx1;++cx)
                    visit(key,cx,cz,
                          cx*CELL+CELL*0.5f,
                          cz*CELL+CELL*0.5f);
        }
    }

    void captureWaterCell(int64_t key,Vector3 cell) {
        auto found=pendingWaterBuckets.find(key);
        if(found==pendingWaterBuckets.end()) {
            std::vector<Vector3> cells;
            cells.reserve((size_t)(TERRAIN_BUCKET/CELL)*(size_t)(TERRAIN_BUCKET/CELL));
            found=pendingWaterBuckets.emplace(key,std::move(cells)).first;
        }
        found->second.push_back(cell);
    }

    void prepareIncrementalKeys(int cx, int cz,
                                const std::unordered_set<int64_t> &carveKeys) {
        pendingBuildKeys.clear();
        pendingDesiredKeys.clear();
        pendingCarveKeys = carveKeys;
        rebuildAll = !live;

        std::unordered_set<int64_t> resident;
        resident.reserve(chunks.size() * 2 + 1);
        for (const TerrainChunk &chunk : chunks) resident.insert(chunk.key);

        const float effectiveR = TERRA_R * CELL * (0.70f + 0.27f * 0.97f);
        const float halfDiag = TERRAIN_BUCKET * 0.72f;
        const int bx0 = (int)floorf((cx * CELL - effectiveR) / TERRAIN_BUCKET);
        const int bx1 = (int)floorf((cx * CELL + effectiveR) / TERRAIN_BUCKET);
        const int bz0 = (int)floorf((cz * CELL - effectiveR) / TERRAIN_BUCKET);
        const int bz1 = (int)floorf((cz * CELL + effectiveR) / TERRAIN_BUCKET);
        for (int bx = bx0; bx <= bx1; ++bx) {
            for (int bz = bz0; bz <= bz1; ++bz) {
                float wx = (bx + 0.5f) * TERRAIN_BUCKET;
                float wz = (bz + 0.5f) * TERRAIN_BUCKET;
                float newD = hypotf(wx - cx * CELL, wz - cz * CELL);
                if (newD > effectiveR + halfDiag) continue;
                int64_t key = terrainBucketKey(wx, wz);
                pendingDesiredKeys.insert(key);
                if (rebuildAll || resident.count(key) == 0)
                    pendingBuildKeys.insert(key);
                else {
                    // Edge buckets were clipped against the old circular fog ring.
                    // Regenerate the narrow boundary band when its center moves.
                    float oldD = hypotf(wx - keyCx * CELL, wz - keyCz * CELL);
                    if (fabsf(newD - effectiveR) < 1.5f * TERRAIN_BUCKET ||
                        fabsf(oldD - effectiveR) < 1.5f * TERRAIN_BUCKET)
                        pendingBuildKeys.insert(key);
                }
            }
        }
        pendingBuildKeys.insert(lastCarveKeys.begin(), lastCarveKeys.end());
        pendingBuildKeys.insert(carveKeys.begin(), carveKeys.end());
    }

    template <class EmitFn>
    void dispatch(EmitFn &&emit, int cx, int cz,
                  const std::unordered_set<int64_t> &carveKeys) {
        prepareIncrementalKeys(cx, cz, carveKeys);
        pendCx = cx; pendCz = cz; building = true;
        ready = false;
        gCapBuckets.clear();
        pendingWaterBuckets.clear();

        worker = std::thread([this, emit = std::forward<EmitFn>(emit)]() mutable {
            gCapture = true;
            emit();
            gCapture = false;
            ready = true;
        });
    }

    void uploadOne(CapBucket &b) {
        if (!pendingDesiredKeys.count(b.key)) return;
        int vcount = (int)(b.pos.size() / 3);
        if (vcount == 0) return;
        if(b.pos.size()!=(size_t)vcount*3 ||
           b.uv.size()!=(size_t)vcount*2 ||
           b.nrm.size()!=(size_t)vcount*3 ||
           b.col.size()!=(size_t)vcount*4) std::abort();
        TerrainChunk c{};
        c.mesh.vertexCount   = vcount;
        c.mesh.triangleCount = vcount / 3;
        c.mesh.vertices  = b.pos.release();
        c.mesh.texcoords = b.uv.release();
        c.mesh.normals   = b.nrm.release();
        c.mesh.colors    = b.col.release();
        UploadMesh(&c.mesh, false);
        c.center = Vector3Scale(Vector3Add(b.bmin, b.bmax), 0.5f);
        c.radius = Vector3Distance(c.center, b.bmax) + 0.5f;
        c.key = b.key;
        pendingChunks.push_back(c);
    }

    // block=false: poll — once the worker's CPU build is done, upload a handful of chunks
    // per call (spread across frames) so the main thread never stalls on hundreds of
    // UploadMesh calls at once; the previous chunks stay visible the whole time. block=true:
    // finish everything synchronously now (first build / screenshot modes, where complete
    // chunks must exist immediately). Shutdown/reset use discardPending() and never upload
    // work that is about to be thrown away.
    void finish(bool block = false) {
        if (!building) return;
        if (uploadCursor == 0 && pendingBuckets.empty()) {
            // Not yet past the CPU-build stage: wait for (or poll) the worker.
            if (!block && !ready.load()) return;
            if (worker.joinable()) worker.join();
            pendingBuckets.reserve(gCapBuckets.size());
            for (auto &kv : gCapBuckets) {
                kv.second.key = kv.first;
                pendingBuckets.push_back(std::move(kv.second));
            }
            gCapBuckets.clear();
            pendingChunks.clear();
            pendingChunks.reserve(pendingBuckets.size());
            uploadCursor = 0;
        }

        int budget = (block || !live) ? (int)pendingBuckets.size() : UPLOAD_BUDGET;
        size_t end = uploadCursor + (size_t)budget;
        if (end > pendingBuckets.size()) end = pendingBuckets.size();
        for (; uploadCursor < end; uploadCursor++) uploadOne(pendingBuckets[uploadCursor]);
        if (uploadCursor < pendingBuckets.size()) return;   // more to upload next frame

        // Merge atomically. A requested rebuild is authoritative even when it
        // emits no geometry (for example an old clipped edge bucket that moved
        // fully outside the cell-level ring). Retaining an old chunk merely
        // because no replacement was uploaded left stale terrain/carve walls.
        std::vector<TerrainChunk> merged;
        merged.reserve(chunks.size() + pendingChunks.size());
        for (TerrainChunk &c : chunks) {
            if (pendingDesiredKeys.count(c.key) &&
                !pendingBuildKeys.count(c.key))
                merged.push_back(c);
            else
                UnloadMesh(c.mesh);
        }
        for (TerrainChunk &c : pendingChunks) merged.push_back(c);

        for(auto it=liveWaterBuckets.begin();it!=liveWaterBuckets.end();) {
            if(pendingDesiredKeys.count(it->first) &&
               !pendingBuildKeys.count(it->first)) ++it;
            else it=liveWaterBuckets.erase(it);
        }
        for(auto &entry:pendingWaterBuckets)
            if(pendingDesiredKeys.count(entry.first) && !entry.second.empty())
                liveWaterBuckets.insert_or_assign(entry.first,std::move(entry.second));

        chunks = std::move(merged);
        live = !chunks.empty();
        pendingBuckets.clear(); pendingChunks.clear(); uploadCursor = 0;
        pendingWaterBuckets.clear();
        lastCarveKeys = std::move(pendingCarveKeys);
        pendingBuildKeys.clear(); pendingDesiredKeys.clear(); pendingCarveKeys.clear();
        rebuildAll = false;
        keyCx = pendCx; keyCz = pendCz;
        building = false;
    }

    void discardPending() {
        // The CPU emitter cannot be abandoned while it still writes gCapBuckets or
        // references its captured build inputs. Join it, then discard its result without
        // spending any time or VRAM on UploadMesh().
        if (worker.joinable()) worker.join();
        ready = false;
        gCapBuckets.clear();
        for (TerrainChunk &chunk : pendingChunks) UnloadMesh(chunk.mesh);
        pendingChunks.clear();
        pendingBuckets.clear();
        pendingWaterBuckets.clear();
        pendingBuildKeys.clear(); pendingDesiredKeys.clear(); pendingCarveKeys.clear();
        lastCarveKeys.clear(); rebuildAll = true;
        uploadCursor = 0;
        building = false;
        pendCx = pendCz = 0;
        keyCx = keyCz = INT_MIN;
    }

    void reset() {
        discardPending();
        for (TerrainChunk &chunk : chunks) UnloadMesh(chunk.mesh);
        chunks.clear();
        liveWaterBuckets.clear();
        live = false;
    }

    void shutdown() {
        reset();
        // Release retained CPU capacity as well; unlike a ride reset, shutdown cannot
        // benefit from reusing it.
        std::vector<CapBucket>().swap(pendingBuckets);
        std::vector<TerrainChunk>().swap(pendingChunks);
        WaterBuckets().swap(pendingWaterBuckets);
        WaterBuckets().swap(liveWaterBuckets);
    }
};
static TerrainMesh gTerrainMesh;
static Material gTerrainMat{};

static unsigned char gAOTop = 255, gAOBot = 255;
static inline void aoColor(Color c, float k) {
    rlColor4ub((unsigned char)(c.r * k), (unsigned char)(c.g * k),
               (unsigned char)(c.b * k), c.a);
}

static inline Color capCol(Color c, float k) {
    return Color{ (unsigned char)(c.r * k), (unsigned char)(c.g * k),
                  (unsigned char)(c.b * k), c.a };
}
// Per-face bit mask so callers (the terrain heightfield) can emit only the faces that
// are actually exposed to air, instead of every face of a fully-buried cube.
enum { CFACE_PZ = 1, CFACE_NZ = 2, CFACE_PY = 4, CFACE_NY = 8, CFACE_PX = 16, CFACE_NX = 32,
       CFACE_ALL = 63 };
static void emitCubeTex(int tile, Vector3 p, float w, float h, float l, Color c, unsigned mask = CFACE_ALL) {
    float x = p.x, y = p.y, z = p.z;
    float u0 = (tile * 16 + 0.5f) / (float)(TILE_N * 16);
    float u1 = (tile * 16 + 15.5f) / (float)(TILE_N * 16);
    float v0 = 0.5f / 16.0f, v1 = 15.5f / 16.0f;

    float kT = gAOTop / 255.0f, kB = gAOBot / 255.0f;
    if (gCapture) {
        // Route every vertex of THIS cube into the bucket keyed by the cube's own centre,
        // never per-vertex -- a cube that straddles a bucket boundary must still land as
        // one whole primitive in one chunk mesh, or the boundary vertices split across two
        // chunks and tear the shared triangles apart (visible gaps at chunk seams).
        int64_t key = gCaptureBucketOverride != INT64_MIN
                    ? gCaptureBucketOverride : terrainBucketKey(x, z);
        gCapBucket = &gCapBuckets[key];

        Color cB = capCol(c, kB), cT = capCol(c, kT);
        float xm = x - w/2, xp = x + w/2, ym = y - h/2, yp = y + h/2, zm = z - l/2, zp = z + l/2;

        #define CAPQ(nx,ny,nz, ax,ay,az,au,av,ac, bx,by,bz,bu,bv,bc, ccx,ccy,ccz,cu,cv,cc, dx,dy,dz,du,dv,dc) \
            capQuad(nx,ny,nz, ax,ay,az,au,av,ac, bx,by,bz,bu,bv,bc, ccx,ccy,ccz,cu,cv,cc, dx,dy,dz,du,dv,dc)
        if (mask & CFACE_PZ) CAPQ(0,0,1,  xm,ym,zp,u0,v1,cB,  xp,ym,zp,u1,v1,cB,  xp,yp,zp,u1,v0,cT,  xm,yp,zp,u0,v0,cT);
        if (mask & CFACE_NZ) CAPQ(0,0,-1, xm,ym,zm,u1,v1,cB,  xm,yp,zm,u1,v0,cT,  xp,yp,zm,u0,v0,cT,  xp,ym,zm,u0,v1,cB);
        if (mask & CFACE_PY) CAPQ(0,1,0,  xm,yp,zm,u0,v0,cT,  xm,yp,zp,u0,v1,cT,  xp,yp,zp,u1,v1,cT,  xp,yp,zm,u1,v0,cT);
        if (mask & CFACE_NY) CAPQ(0,-1,0, xm,ym,zm,u1,v0,cB,  xp,ym,zm,u0,v0,cB,  xp,ym,zp,u0,v1,cB,  xm,ym,zp,u1,v1,cB);
        if (mask & CFACE_PX) CAPQ(1,0,0,  xp,ym,zm,u1,v1,cB,  xp,yp,zm,u1,v0,cT,  xp,yp,zp,u0,v0,cT,  xp,ym,zp,u0,v1,cB);
        if (mask & CFACE_NX) CAPQ(-1,0,0, xm,ym,zm,u0,v1,cB,  xm,ym,zp,u1,v1,cB,  xm,yp,zp,u1,v0,cT,  xm,yp,zm,u0,v0,cT);
        #undef CAPQ
        return;
    }

    if (mask & CFACE_PZ) {
    rlNormal3f(0, 0, 1);
    aoColor(c, kB); rlTexCoord2f(u0, v1); rlVertex3f(x - w/2, y - h/2, z + l/2);
    aoColor(c, kB); rlTexCoord2f(u1, v1); rlVertex3f(x + w/2, y - h/2, z + l/2);
    aoColor(c, kT); rlTexCoord2f(u1, v0); rlVertex3f(x + w/2, y + h/2, z + l/2);
    aoColor(c, kT); rlTexCoord2f(u0, v0); rlVertex3f(x - w/2, y + h/2, z + l/2);
    }
    if (mask & CFACE_NZ) {
    rlNormal3f(0, 0, -1);
    aoColor(c, kB); rlTexCoord2f(u1, v1); rlVertex3f(x - w/2, y - h/2, z - l/2);
    aoColor(c, kT); rlTexCoord2f(u1, v0); rlVertex3f(x - w/2, y + h/2, z - l/2);
    aoColor(c, kT); rlTexCoord2f(u0, v0); rlVertex3f(x + w/2, y + h/2, z - l/2);
    aoColor(c, kB); rlTexCoord2f(u0, v1); rlVertex3f(x + w/2, y - h/2, z - l/2);
    }
    if (mask & CFACE_PY) {
    rlNormal3f(0, 1, 0);
    aoColor(c, kT); rlTexCoord2f(u0, v0); rlVertex3f(x - w/2, y + h/2, z - l/2);
    aoColor(c, kT); rlTexCoord2f(u0, v1); rlVertex3f(x - w/2, y + h/2, z + l/2);
    aoColor(c, kT); rlTexCoord2f(u1, v1); rlVertex3f(x + w/2, y + h/2, z + l/2);
    aoColor(c, kT); rlTexCoord2f(u1, v0); rlVertex3f(x + w/2, y + h/2, z - l/2);
    }
    if (mask & CFACE_NY) {
    rlNormal3f(0, -1, 0);
    aoColor(c, kB); rlTexCoord2f(u1, v0); rlVertex3f(x - w/2, y - h/2, z - l/2);
    aoColor(c, kB); rlTexCoord2f(u0, v0); rlVertex3f(x + w/2, y - h/2, z - l/2);
    aoColor(c, kB); rlTexCoord2f(u0, v1); rlVertex3f(x + w/2, y - h/2, z + l/2);
    aoColor(c, kB); rlTexCoord2f(u1, v1); rlVertex3f(x - w/2, y - h/2, z + l/2);
    }
    if (mask & CFACE_PX) {
    rlNormal3f(1, 0, 0);
    aoColor(c, kB); rlTexCoord2f(u1, v1); rlVertex3f(x + w/2, y - h/2, z - l/2);
    aoColor(c, kT); rlTexCoord2f(u1, v0); rlVertex3f(x + w/2, y + h/2, z - l/2);
    aoColor(c, kT); rlTexCoord2f(u0, v0); rlVertex3f(x + w/2, y + h/2, z + l/2);
    aoColor(c, kB); rlTexCoord2f(u0, v1); rlVertex3f(x + w/2, y - h/2, z + l/2);
    }
    if (mask & CFACE_NX) {
    rlNormal3f(-1, 0, 0);
    aoColor(c, kB); rlTexCoord2f(u0, v1); rlVertex3f(x - w/2, y - h/2, z - l/2);
    aoColor(c, kB); rlTexCoord2f(u1, v1); rlVertex3f(x - w/2, y - h/2, z + l/2);
    aoColor(c, kT); rlTexCoord2f(u1, v0); rlVertex3f(x - w/2, y + h/2, z + l/2);
    aoColor(c, kT); rlTexCoord2f(u0, v0); rlVertex3f(x - w/2, y + h/2, z - l/2);
    }
}

static void drawCubeTexAOFace(int tile, Vector3 p, float w, float h, float l, Color c,
                          unsigned char aoTop, unsigned char aoBot, unsigned mask) {
    gAOTop = aoTop; gAOBot = aoBot;
    if (gCapture || gVoxelBatchOpen) {
        emitCubeTex(tile, p, w, h, l, c, mask);
    } else {
        rlSetTexture(gAtlas.id);
        rlBegin(RL_QUADS);
        emitCubeTex(tile, p, w, h, l, c, mask);
        rlEnd();
    }
    gAOTop = 255; gAOBot = 255;
}
static void drawCubeTexAO(int tile, Vector3 p, float w, float h, float l, Color c,
                          unsigned char aoTop, unsigned char aoBot) {
    drawCubeTexAOFace(tile, p, w, h, l, c, aoTop, aoBot, CFACE_ALL);
}
// Only emit the specified faces -- used by the terrain heightfield so a fully-buried cube
// face (hidden against an equal-or-taller neighbour, or facing straight down into the
// ground) is never generated at all, instead of generated and then merely hidden.
static void drawCubeTexFace(int tile, Vector3 p, float w, float h, float l, Color c, unsigned mask) {
    unsigned char aoBot = 255;
    if (h > 1.2f) aoBot = 196;
    drawCubeTexAOFace(tile, p, w, h, l, c, 255, aoBot, mask);
}
static void drawCubeTex(int tile, Vector3 p, float w, float h, float l, Color c) {

    unsigned char aoBot = 255;
    if (h > 1.2f) aoBot = 196;
    drawCubeTexAO(tile, p, w, h, l, c, 255, aoBot);
}

static void drawTiledBox(int tile, Vector3 p, float w, float h, float l, Color c, float blk = 2.0f) {
    int nx = (int)fmaxf(1.0f, roundf(w / blk));
    int ny = (int)fmaxf(1.0f, roundf(h / blk));
    int nz = (int)fmaxf(1.0f, roundf(l / blk));
    float sx = w / nx, sy = h / ny, sz = l / nz;
    float x0 = p.x - w * 0.5f + sx * 0.5f;
    float y0 = p.y - h * 0.5f + sy * 0.5f;
    float z0 = p.z - l * 0.5f + sz * 0.5f;
    for (int iz = 0; iz < nz; iz++)
        for (int iy = 0; iy < ny; iy++)
            for (int ix = 0; ix < nx; ix++)
                drawCubeTex(tile, Vector3{ x0 + ix * sx, y0 + iy * sy, z0 + iz * sz },
                            sx, sy, sz, c);
}
