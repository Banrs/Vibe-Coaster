static Sound makeCoinSound() {
    const int sr = 44100; const float dur = 0.22f;
    int n = (int)(sr * dur);
    short *d = (short *)RL_MALLOC(n * sizeof(short));
    float ph = 0;
    for (int i = 0; i < n; i++) {
        float t = (float)i / sr;
        float f = (t < 0.06f) ? 987.8f : 1318.5f;
        ph += 2 * PI * f / sr;
        float env = expf(-t * 11.0f) * fminf(t / 0.004f, 1.0f);
        d[i] = (short)(sinf(ph) * env * 11000);
    }
    Wave w = { (unsigned)n, 44100, 16, 1, d };
    Sound s = LoadSoundFromWave(w);
    RL_FREE(d);
    return s;
}
static Sound makeClackSound() {
    const int sr = 44100; const float dur = 0.05f;
    int n = (int)(sr * dur);
    short *d = (short *)RL_MALLOC(n * sizeof(short));
    float y = 0;
    for (int i = 0; i < n; i++) {
        float t = (float)i / sr;
        float x = frnd(-1, 1);
        y += 0.45f * (x - y);
        d[i] = (short)(y * expf(-t * 110.0f) * 9000);
    }
    Wave w = { (unsigned)n, 44100, 16, 1, d };
    Sound s = LoadSoundFromWave(w);
    RL_FREE(d);
    return s;
}
static Sound makeWhooshSound() {
    const int sr = 44100; const float dur = 0.8f;
    int n = (int)(sr * dur);
    short *d = (short *)RL_MALLOC(n * sizeof(short));
    float y = 0;
    for (int i = 0; i < n; i++) {
        float t = (float)i / sr;
        float p = t / dur;
        float x = frnd(-1, 1);

        float cut = 0.05f + 0.30f * sinf(PI * p);
        y += cut * (x - y);
        float env = powf(sinf(PI * p), 1.3f);
        d[i] = (short)(y * env * 17000);
    }
    Wave w = { (unsigned)n, 44100, 16, 1, d };
    Sound s = LoadSoundFromWave(w);
    RL_FREE(d);
    return s;
}

static volatile float g_windVol   = 0.0f;
static volatile float g_rumbleVol = 0.0f;
static void windCallback(void *buffer, unsigned int frames) {
    short *d = (short *)buffer;
    static uint32_t ar = 0x9e3779b9u;
    static float lp = 0, hp = 0, rmb = 0, sm = 0, smR = 0;
    float target = g_windVol, targetR = g_rumbleVol;
    for (unsigned int i = 0; i < frames; i++) {
        sm  += (target  - sm)  * 0.0006f;
        smR += (targetR - smR) * 0.0006f;
        ar ^= ar << 13; ar ^= ar >> 17; ar ^= ar << 5;
        float white = ((int)(ar & 0xffff) - 32768) / 32768.0f;
        lp  += 0.06f * (white - lp);
        hp  += 0.40f * (white - hp);
        rmb += 0.012f * (white - rmb);
        float wind   = (lp * 0.65f + hp * 0.35f) * sm * sm;
        float rumble = rmb * 4.0f * smR;
        int v = (int)((wind * 27000.0f) + (rumble * 30000.0f));
        d[i] = (short)(v < -32768 ? -32768 : (v > 32767 ? 32767 : v));
    }
}
static void textSh(const char *s, int x, int y, int size, Color c) {
    DrawText(s, x + 2, y + 2, size, Color{ 20, 20, 30, 200 });
    DrawText(s, x, y, size, c);
}

static void hudPanel(float x, float y, float w, float h, Color fill = Color{ 18, 22, 34, 168 }) {
    Rectangle r = { x, y, w, h };
    DrawRectangleRounded(r, 0.32f, 6, fill);
    DrawRectangleRoundedLines(r, 0.32f, 6, Color{ 150, 168, 200, 70 });
    DrawRectangleRounded(Rectangle{ x + 5, y + 3, w - 10, 2 }, 1.0f, 3, Color{ 220, 232, 255, 36 });
}

// HONEST HUD ELEMENT NAMES -- the ONE shared diagnosis both renderers use (user: names are
// often fake, e.g. SPLASHDOWN shown on non-low, non-water track). The generator's tag says
// what an element was MEANT to be; terrain feedback can bend the built shape (a DIP held high
// by its valley-guard floor, a DROP forced up a rising hillside), so the banner is diagnosed
// from the ACTUAL local geometry: tag + pitch (tangent.y) + track height vs ground/water.
//   - SPLASHDOWN only when genuinely SKIMMING WATER (over a water tile, within ~3 m of the
//     surface -- just above the wheel-spray window, so the label and the spray particles
//     appear together). A DIP over dry land is a DIP; one held high relabels by pitch.
//   - M_TURN reads BANKED TURN: the overbanked variants were removed from generation
//     (bankT=0, bank hard-clamped below vertical), so "OVERBANKED" was a fake name too.
// groundY must be the caller's groundTopAt(x,z), which floors at WATER_Y -- over water it
// returns exactly WATER_Y, which is the water test used here. Rehomed here from
// coaster_track.cpp at migration step 6; the mapped v2::Tag bytes arrive as M_* SegModes.
static const char* rideElemName(unsigned char tag, float pitch, float trackY, float groundY,
                                bool &special) {
    special = false;
    float alt = trackY - groundY;
    bool overWater = submergedGround(groundY);
    const char* byPitch = (pitch > 0.12f) ? "CLIMB" : (pitch < -0.12f) ? "DROP" : "AIRTIME";
    switch (tag) {
        case M_LAUNCH: return "LAUNCH";
        case M_BOOST:  return "BOOSTER";
        case M_CLIMB:  return (pitch < -0.12f) ? "DROP" : "TOP HAT";
        case M_DROP:   return byPitch;   // the signature cliff dive now has its own tag (M_CLIFFDIVE), so a tall DROP is no longer relabelled
        case M_HILLS:  return "AIRTIME HILL";
        case M_TURN:   return "BANKED TURN";
        case M_HELIX:  return "HELIX";
        case M_SCURVE: return "S-CURVE";
        case M_DIVE:   return (pitch > 0.12f) ? "CLIMB" : "DIVE TURN";
        case M_BANKAIR:return "BANKED AIRTIME";
        case M_WAVE:   return "WAVE TURN";
        case M_DIP:
            if (overWater && trackY - WATER_Y < 3.0f) return "SPLASHDOWN";
            if (alt < 12.0f)                          return "DIP";
            return byPitch;   // a dip its valley guard kept high isn't visibly a dip at all
        case M_LOOP:     special = true; return "VERTICAL LOOP";
        case M_ROLL:     special = true; return "CORKSCREW";
        case M_IMMEL:    special = true; return "IMMELMANN";
        case M_STALL:    special = true; return "ZERO-G STALL";
        case M_DIVELOOP: special = true; return "DIVE LOOP";
        case M_COBRA:    special = true; return "COBRA ROLL";
        case M_HEARTLINE:special = true; return "HEARTLINE ROLL";
        case M_WINGOVER: special = true; return "WING-OVER";
        case M_PRETZEL:  special = true; return "PRETZEL LOOP";
        case M_STENGEL:  special = true; return "STENGEL DIVE";
        case M_BANANA:   special = true; return "BANANA ROLL";
        case M_CLIFFDIVE:special = true; return "SIGNATURE CLIFF DIVE";
        default: return nullptr;   // FLAT/STATION: no banner
    }
}
