    // ============================================================================
    //  THREE NEW COASTER ELEMENTS  (Track member functions)
    // ============================================================================
    //  ADD these member-var declarations to the Track struct (drop near the other
    //  element-state blocks, ~line 68 of coaster_track.cpp):
    //
    //    // pretzel-loop state (teardrop vertical loop, planar F-U)
    //    Vector3 pzF{}, pzBase{};         float pzR = 30, pzDrift = 0; int pzSteps = 26;
    //    // stengel-dive state (airtime camelback that over-tips past vertical at the apex)
    //    Vector3 sdF{}, sdSide{}, sdBase{}; float sdH = 12, sdSpan = 0; int sdSteps = 13;
    //    // banana-roll state (long low arch with one slow 360 roll -> 0g winder)
    //    Vector3 brF{}, brSide{}, brBase{}; float brH = 18, brSpan = 0, brDir = 1; int brSteps = 26;
    //
    //  VERIFIED METRICS (standalone harness, genV=70 nominal; swept 45..95):
    //    PRETZEL: entry/exit heading +F; 1 inversion; max height ~75m; spacing ratio
    //             1.75; sustained +g ~5.5g bottom -> ~7g crest (target 6-7). [hottest
    //             positive-g element -> add to isHardInversion(), speed-gated]
    //    STENGEL: entry/exit heading +F; 0 inversions; apex over-tips to up.y~-0.27
    //             (~106deg bank, past vertical); ejector airtime ~ -0.3g at the crest;
    //             spacing ratio 1.04. [floaty -> NOT gated]
    //    BANANA:  entry/exit heading +F; 1 inversion; low arch ~21m; sustained ~0g
    //             through the slow roll (felt vert g 0..+0.8, hangtime over the invert);
    //             spacing ratio 1.11. [floaty inversion -> NOT gated]
    // ----------------------------------------------------------------------------

    // ---------------------------------------------------------------- PRETZEL LOOP
    //  Teardrop vertical loop, planar in the F-U plane. UPRIGHT at the entry/exit
    //  (the loop bottom, so it connects cleanly to the level drop), ONE inversion over
    //  the crest. Teardrop radius is WIDE at the bottom (entry/exit, fastest -> keep +g
    //  sane) and TIGHTER at the crest, the real-loop g profile -> highest SUSTAINED
    //  positive g of any element. A net forward drift keeps the two legs from overlapping.
    void initPretzel() {
        mode = M_PRETZEL;
        pzF    = headingVec();
        pzSide = Vector3Normalize(Vector3CrossProduct(WUP, pzF));
        if (rnd01() < 0.5f) pzSide = Vector3Scale(pzSide, -1.0f);   // sweep either way
        pzBase = gpos;
        // SPEED-DICTATES-SIZE teardrop-loop bottom radius (up to 1.30x record at speed); the
        // bigger-at-speed bottom keeps g near target while the crest stays fast.
        { float bt; pzR = invRFor(M_PRETZEL, bt); pzR *= frnd(0.85f, 1.0f); }   // SPEED-SIZE + per-element size variety
        pzDrift = pzR * 1.5f;                        // forward creep so the descending leg doesn't sit on the ascending one
        pzLat   = pzR * frnd(1.4f, 1.9f);            // LATERAL sweep so the loop veers off the entry line (was planar -> sat 1:1 on the existing track)
        pzSteps = 26;
        remain  = pzSteps;
    }
    Vector3 stepPretzel() {
        int   i = pzSteps - remain;                 // 0..pzSteps-1
        float t = (float)(i + 1) / (float)pzSteps;  // (0..1]
        float ang = 2.0f * PI * t;                  // 0 at bottom entry -> 2*PI at bottom exit
        // teardrop radius: WIDE at the bottom (ang~0,2PI), TIGHTER at the crest (ang~PI)
        float Rs  = 1.0f - 0.22f * (0.5f * (1.0f - cosf(ang)));   // 1.0 bottom -> 0.78 crest
        float R   = pzR * Rs;
        // climb UP and over: up = R*(1-cos(ang)) (0 at bottom, ~2R at crest)
        float fwd = pzDrift * t + R * sinf(ang);                 // forward swing + net creep
        float up  = R * (1.0f - cosf(ang));                      // rises to the crest, back to 0
        // lateral sweep, eased so velocity is 0 at entry AND exit (clean forward
        // heading both ends) -> the loop veers clear of the lead-in track line.
        float lat = pzLat * 0.5f * (1.0f - cosf(PI * t));
        gpos = { pzBase.x + pzF.x * fwd + pzSide.x * lat,
                 pzBase.y + up,
                 pzBase.z + pzF.z * fwd + pzSide.z * lat };
        // rider up = inward normal (toward loop centre): UP at the bottom (ang~0),
        // DOWN at the crest (ang~PI) -> single inversion over the top.
        Vector3 upv = Vector3Normalize(Vector3{ pzF.x * (-sinf(ang)), cosf(ang), pzF.z * (-sinf(ang)) });
        if (--remain <= 0) { gyaw = atan2f(pzF.x, pzF.z); enterDrop(irnd(2, 4)); }
        return upv;
    }

    // ---------------------------------------------------------------- STENGEL DIVE
    //  A true Stengel dive drop (Werner Stengel's signature element): the train noses
    //  over a short crest, OVER-BANKS PAST VERTICAL (rolls ~100-130deg) and DIVES down a
    //  steep plunge while TWISTING continuously through the descent, then rolls back upright
    //  and eases level at a LOWER exit. The defining feel is the twisting over-banked plunge
    //  (you fall sideways/diving), not an airtime camelback. 0 inversions (the bank passes
    //  vertical but the path doesn't loop). Sized so peak g stays inside +10/-7.5 at the
    //  entry speed: the bottom pull-out is the +g lever (lengthen the dive as v rises), the
    //  crest tip-over the -g lever; both are eased (raised cosines, zero slope at the seams).
    void initStengel() {
        mode = M_STENGEL;
        sdF    = headingVec();
        sdSide = Vector3Normalize(Vector3CrossProduct(WUP, sdF));
        if (rnd01() < 0.5f) sdSide = Vector3Scale(sdSide, -1.0f); // dive/twist either way
        sdBase = gpos;
        float v   = Clamp(genV, 40.0f, 95.0f);
        // dive depth: a real, steep plunge, clamped to the height available above terrain
        // (keep ~14m exit clearance) so it never clips the ground. Realistic dive-drop scale.
        float avail = sdBase.y - groundTopAt(sdBase.x, sdBase.z) - 14.0f;
        sdDrop    = Clamp(0.55f * v, 30.0f, 55.0f);            // ~30-55m steep plunge (realistic dive-drop)
        sdDrop    = fminf(sdDrop, fmaxf(avail, 10.0f));
        // SIZE THE DIVE LENGTH for the bottom-pull-out g at the ENTRY SPEED (geometry, not a
        // speed cap): the dive plunges -sdDrop then eases level over the second half via a
        // raised cosine, whose bottom curvature kappa ~ sdDrop*(PI/Ld)^2 (Ld = dive run). Felt
        // +g = 1 + v^2*kappa/GRAV. Solve Ld so the bottom holds ~gBot, then total length = Ld
        // plus a short crest. Faster entry -> longer dive (stays in-envelope), never a brake.
        const float gBot = 6.5f;                               // target bottom pull-out g (well under +10)
        float Ld  = PI * v * sqrtf(sdDrop / ((gBot - 1.0f) * GRAV));
        int   diveSteps = Clamp((int)(Ld / SEG_LEN), 8, 22);
        int   crestSteps = 4;                                  // short nose-over crest, dive dominates
        sdSteps   = crestSteps + diveSteps;
        sdCrestT  = (float)crestSteps / (float)sdSteps;        // crest fraction (rest is the diving twist)
        float L   = sdSteps * SEG_LEN;
        // crest hop: small, sized for a gentle ejector tip-over (~-1.5g, inside -7.5) over the
        // short crest. kappa_crest ~ sdH*(PI/Lc)^2; keep it modest so the DIVE is the feature.
        float Lc  = crestSteps * SEG_LEN;
        sdH       = Clamp(2.0f * GRAV * Lc * Lc / (v * v * PI * PI), 5.0f, 14.0f);
        sdSpan    = L * 0.22f;                                 // moderate lateral traverse (the dive veers off-line)
        remain    = sdSteps;
    }
    Vector3 stepStengel() {
        int   i = sdSteps - remain;
        float t = (float)(i + 1) / (float)sdSteps;  // (0..1]
        float tc  = sdCrestT;                        // crest fraction, then the diving twist
        float L   = sdSteps * SEG_LEN;
        float ff  = L * t;                           // forward advances uniformly
        // vertical: rise to +sdH at the crest (gentle ejector tip-over), then DIVE to -sdDrop
        // at the exit. Both halves are raised cosines with zero slope at the crest AND exit,
        // so the nose-over and the bottom pull-out are eased (no g-spike at either seam).
        float fU;
        if (t < tc) fU = sdH * 0.5f * (1.0f - cosf(PI * (t / tc)));                              // 0 -> +sdH
        else        fU = sdH - (sdH + sdDrop) * 0.5f * (1.0f - cosf(PI * ((t - tc) / (1.0f - tc)))); // +sdH -> -sdDrop
        float fS  = sdSpan * 0.5f * (1.0f - cosf(PI * t));       // eased lateral traverse 0 -> sdSpan
        gpos = { sdBase.x + sdF.x * ff + sdSide.x * fS,
                 sdBase.y + fU,
                 sdBase.z + sdF.z * ff + sdSide.z * fS };
        // heading swings toward sdSide (the dive veers off the entry line); banking axis from it
        Vector3 H = Vector3Normalize(Vector3{
            sdF.x + sdSide.x * (sdSpan / L) * PI * 0.5f * sinf(PI * t),
            0,
            sdF.z + sdSide.z * (sdSpan / L) * PI * 0.5f * sinf(PI * t) });
        // OVER-BANKED TWIST: the bank rolls PAST vertical and TWISTS continuously through the
        // whole dive (a raised-cosine bank that ramps from upright at entry, overshoots ~125deg
        // through the plunge, and rolls back upright by the exit) — the defining Stengel feel of
        // diving sideways. Eased at both ends so the entry/exit seams carry no roll-rate jolt.
        float beta = 2.18f * 0.5f * (1.0f - cosf(2.0f * PI * t));   // 0 -> ~125deg over-bank at mid-dive -> 0
        Vector3 latAx = Vector3Normalize(Vector3CrossProduct(H, WUP));
        float sgn = (Vector3CrossProduct(H, WUP).x * sdSide.x +
                     Vector3CrossProduct(H, WUP).z * sdSide.z) >= 0 ? 1.0f : -1.0f;
        Vector3 upv = Vector3Normalize(Vector3Add(Vector3Scale(WUP, cosf(beta)),
                                                  Vector3Scale(latAx, sinf(beta) * sgn)));
        if (--remain <= 0) { gyaw = atan2f(H.x, H.z); enterDrop(irnd(2, 3)); }
        return upv;
    }

    // ---------------------------------------------------------------- BANANA ROLL
    //  Long, low, gentle arch with a single slow 360deg roll over the whole element
    //  -> sustained ~0g hangtime through a drawn-out inversion. 1 inversion. Lots of
    //  lateral traverse makes spacing easy.
    void initBanana() {
        mode = M_BANANA;
        brF    = headingVec();
        brSide = Vector3Normalize(Vector3CrossProduct(WUP, brF));
        brDir  = (rnd01() < 0.5f) ? 1.0f : -1.0f;
        brBase = gpos;
        brSteps = 26;
        float v = Clamp(genV, 40.0f, 95.0f);
        // Keep it LOW and gentle (reads as a long arch, not a hill): a modest hump.
        // It still gives sustained hangtime because the slow roll keeps the rider near
        // weightless through the inverted middle; we don't need a full freefall arch.
        brH    = Clamp(0.35f * v, 22.0f, 28.0f);     // low crest (~22-28m)
        brH    = fminf(brH, maxClearH());            // energy-budget cap -> the slow 0g roll keeps gliding, never stalls
        brSpan = Clamp(1.9f * v, 90.0f, 170.0f);     // significant lateral traverse
        remain = brSteps;
    }
    Vector3 stepBanana() {
        int   i = brSteps - remain;
        float t = (float)(i + 1) / (float)brSteps;  // (0..1]
        float L  = brSteps * SEG_LEN;
        float ff = L * t;                            // uniform forward
        // ease the lateral in and out (smoothstep) so entry/exit headings ~ +F and the
        // mid-element heading is the most turned -> gentle banana sweep, no entry kink
        float es = t * t * (3.0f - 2.0f * t);        // smoothstep 0..1
        float fS = brSpan * es * brDir;
        float fU = brH * (1.0f - (2.0f * t - 1.0f) * (2.0f * t - 1.0f));  // low parabolic arch
        gpos = { brBase.x + brF.x * ff + brSide.x * fS,
                 brBase.y + fU,
                 brBase.z + brF.z * ff + brSide.z * fS };
        // heading = local ground tangent: forward + d(fS)/d(ff)*side. d(es)/dt = 6t(1-t).
        float dlat = brSpan * (6.0f * t * (1.0f - t)) / L * brDir;   // lateral slope per forward metre
        Vector3 H = Vector3Normalize(Vector3{
            brF.x + brSide.x * dlat, 0,
            brF.z + brSide.z * dlat });
        float beta = 2.0f * PI * t * brDir;          // one slow full roll
        Vector3 latAx = Vector3Normalize(Vector3CrossProduct(H, WUP));
        Vector3 upv = Vector3Normalize(Vector3Add(Vector3Scale(WUP, cosf(beta)),
                                                  Vector3Scale(latAx, sinf(beta))));
        if (--remain <= 0) { gyaw = atan2f(H.x, H.z); enterDrop(irnd(2, 3)); }
        return upv;
    }
