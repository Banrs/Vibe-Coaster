#ifndef MINECOASTER_RENDER_FX_CPP
#define MINECOASTER_RENDER_FX_CPP

static const char *SHADOW_VS =
    "#version 330\n"
    "in vec3 vertexPosition; in vec2 vertexTexCoord; in vec3 vertexNormal; in vec4 vertexColor;\n"
    "uniform mat4 mvp;\n"
    "out vec2 fragTexCoord; out vec4 fragColor; out vec3 fragNormal; out vec3 fragWorld;\n"
    "void main(){\n"
    "  vec4 wp = vec4(vertexPosition,1.0);\n"
    "  fragWorld = wp.xyz;\n"
    "  fragTexCoord = vertexTexCoord; fragColor = vertexColor;\n"
    "  fragNormal = normalize(vertexNormal);\n"
    "  gl_Position = mvp*vec4(vertexPosition,1.0);\n"
    "}\n";
static const char *SHADOW_FS =
    "#version 330\n"
    "in vec2 fragTexCoord; in vec4 fragColor; in vec3 fragNormal; in vec3 fragWorld;\n"
    "uniform sampler2D texture0; uniform vec4 colDiffuse;\n"
    "uniform vec3 lightDir; uniform vec3 viewPos;\n"
    "uniform vec3 sunCol; uniform vec3 skyCol; uniform vec3 groundCol;\n"
    "uniform float uTime;\n"

    "uniform float fogEnd; uniform vec3 fogCol;\n"
    // Anisotropic highlight for the running rails. railTangent is the rail's own
    // world-space tangent (its long axis), updated every sample as the track is
    // drawn -- cheap to set with a plain uniform since it only steers the
    // highlight's *direction*, and nearby samples' tangents are nearly
    // identical, so it's harmless if a rail's quads actually flush to the GPU
    // slightly before/after this value is updated to its own exact sample.
    // Which fragments the effect applies to is decided independently and
    // exactly, from fragTexCoord (below) -- a genuinely per-vertex signal that
    // survives rlgl's immediate-mode batching, unlike an on/off mask uniform
    // would (rails, ties, spine and bolts share one atlas+shader and get
    // interleaved into the same draw calls, so a mask flag couldn't be scoped
    // to just the rail quads without forcing a GPU flush around every one of
    // the ~1000+ rail samples drawn per frame).
    "uniform vec3 railTangent; uniform vec2 railUVRange;\n"
    // The main gameplay pass now renders into an offscreen linear-HDR target
    // (see PostFX below / main.cpp) that tonemaps + gamma-encodes once,
    // centrally, in a single composite pass -- so by default this shader
    // outputs straight linear HDR color (still lit/fogged, just not
    // tonemapped/gamma-encoded/saturated). The path-trace preview (KEY_T live
    // mode) and the offline path-trace --shot capture still composite this
    // shader's decorative-overlay draws (rails, ties, station dressing)
    // directly onto an already-tonemapped LDR backbuffer with no post pass of
    // their own -- for those two call sites main.cpp sets legacyTonemap=1 so
    // this shader falls back to doing its own inline tonemap+gamma+saturation
    // exactly as before.
    "uniform float legacyTonemap;\n"
    "out vec4 finalColor;\n"

    // Cascaded shadow maps: 3 cascades (near/mid/far), each its own ortho box +
    // texture, so near-field shadows get far more texel density than a single
    // map could afford at this render distance, while the far cascade still
    // reaches out to the edge of the generated terrain ring.
    "uniform mat4 lightVP0; uniform mat4 lightVP1; uniform mat4 lightVP2;\n"
    "uniform sampler2D shadowMap0; uniform sampler2D shadowMap1; uniform sampler2D shadowMap2;\n"
    "uniform vec2 shadowTexel0; uniform vec2 shadowTexel1; uniform vec2 shadowTexel2;\n"
    // Each cascade's normalized [0,1] depth-buffer range covers a different span
    // of world metres (near cascades are tight/shallow, far cascades deep) -- a
    // single normalized bias would be either too small (acne) on the far
    // cascade or too large (peter-panning) on the near one, so bias is computed
    // in world metres then converted per-cascade via its own inverse depth range.
    "uniform float invRange0; uniform float invRange1; uniform float invRange2;\n"
    "uniform float cascadeSplit0; uniform float cascadeSplit1;\n"
    // The cascades are centred on the train/focus point P (see ShadowSys::computeLightVP),
    // NOT the camera -- cascade SELECTION must use distance from that same point, or any
    // shot where the camera sits away from the train (orbit/free-look/elevated views) picks
    // the wrong cascade (or falls outside all of them, going flat/shadowless) even though
    // the fragment is well within a cascade's actual coverage box.
    "uniform vec3 shadowFocus;\n"

    "const vec2 PD12[12] = vec2[12](\n"
    "  vec2(-0.326,-0.406),vec2(-0.840,-0.074),vec2(-0.696, 0.457),vec2(-0.203, 0.621),\n"
    "  vec2( 0.962,-0.195),vec2( 0.473,-0.480),vec2( 0.519, 0.767),vec2( 0.185,-0.893),\n"
    "  vec2( 0.507, 0.064),vec2( 0.896, 0.412),vec2(-0.322,-0.933),vec2(-0.792,-0.598));\n"
    "float pcfTap(sampler2D sm, vec2 texel, vec3 p, float bias){\n"
    "  float ang = fract(sin(dot(fragWorld.xz, vec2(12.9898,78.233)))*43758.5453)*6.2831853;\n"
    "  float ca=cos(ang), sa=sin(ang); mat2 rot=mat2(ca,-sa,sa,ca);\n"
    "  vec2 o = texel*1.4;\n"
    "  float s=0.0;\n"
    "  for(int i=0; i<12; i++){\n"
    "    vec2 tap = p.xy + rot*PD12[i]*o;\n"
    "    if(tap.x<0.0||tap.x>1.0||tap.y<0.0||tap.y>1.0) s += 1.0;\n"
    "    else s += (p.z-bias > texture(sm, tap).r) ? 0.0 : 1.0;\n"
    "  }\n"
    "  return s*(1.0/12.0);\n"
    "}\n"
    // Bias tuned in world metres (matches the old single-map 1.4-3.2 m range,
    // now comfortably clearing the ~1 m terrain height steps regardless of
    // which cascade is sampled); converted to each cascade's normalized units
    // by the caller via invRangeN.
    "float worldBias(float NoL){ return clamp(1.4 + 1.75*(1.0-NoL), 1.4, 3.2); }\n"
    // Split per-cascade so every call site passes a compile-time-known cascade --
    // no runtime idx branch (the old single shadowCascade(idx,N) re-tested idx on
    // every call even though callers always pass a literal 0/1/2).
    "float shadowCascade0(vec3 N){\n"
    "  float NoL = max(dot(N,lightDir),0.0);\n"
    "  vec4 lp = lightVP0*vec4(fragWorld,1.0); vec3 p = lp.xyz/lp.w; p = p*0.5+0.5;\n"
    "  if(p.z<=0.0||p.z>1.0||p.x<0.0||p.x>1.0||p.y<0.0||p.y>1.0) return 1.0;\n"
    "  return pcfTap(shadowMap0, shadowTexel0, p, worldBias(NoL)*invRange0);\n"
    "}\n"
    "float shadowCascade1(vec3 N){\n"
    "  float NoL = max(dot(N,lightDir),0.0);\n"
    "  vec4 lp = lightVP1*vec4(fragWorld,1.0); vec3 p = lp.xyz/lp.w; p = p*0.5+0.5;\n"
    "  if(p.z<=0.0||p.z>1.0||p.x<0.0||p.x>1.0||p.y<0.0||p.y>1.0) return 1.0;\n"
    "  return pcfTap(shadowMap1, shadowTexel1, p, worldBias(NoL)*invRange1);\n"
    "}\n"
    "float shadowCascade2(vec3 N){\n"
    "  float NoL = max(dot(N,lightDir),0.0);\n"
    "  vec4 lp = lightVP2*vec4(fragWorld,1.0); vec3 p = lp.xyz/lp.w; p = p*0.5+0.5;\n"
    "  if(p.z<=0.0||p.z>1.0||p.x<0.0||p.x>1.0||p.y<0.0||p.y>1.0) return 1.0;\n"
    "  return pcfTap(shadowMap2, shadowTexel2, p, worldBias(NoL)*invRange2);\n"
    "}\n"
    // Select cascade by focus-XZ distance (matches the fog/culling convention
    // used elsewhere in this shader), soft-blending across a band near each
    // split so the cascade seam is never a visible hard line. Right at each
    // band's inner/outer edge t is ~0 or ~1 and the far/near tap contributes
    // negligibly -- skip it there so the common case (deep inside a cascade,
    // or barely past a blend edge) never pays for a second full 12-tap PCF.
    "float shadow(vec3 N){\n"
    "  float d = length(shadowFocus.xz - fragWorld.xz);\n"
    "  float band0 = cascadeSplit0*0.85, band1 = cascadeSplit1*0.85;\n"
    "  if(d < band0) return shadowCascade0(N);\n"
    "  if(d < cascadeSplit0){\n"
    "    float t = (d-band0)/max(cascadeSplit0-band0,0.001);\n"
    "    if(t < 0.02) return shadowCascade0(N);\n"
    "    if(t > 0.98) return shadowCascade1(N);\n"
    "    return mix(shadowCascade0(N), shadowCascade1(N), t);\n"
    "  }\n"
    "  if(d < band1) return shadowCascade1(N);\n"
    "  if(d < cascadeSplit1){\n"
    "    float t = (d-band1)/max(cascadeSplit1-band1,0.001);\n"
    "    if(t < 0.02) return shadowCascade1(N);\n"
    "    if(t > 0.98) return shadowCascade2(N);\n"
    "    return mix(shadowCascade1(N), shadowCascade2(N), t);\n"
    "  }\n"
    "  return shadowCascade2(N);\n"
    "}\n"

    "vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0); }\n"
    "vec3 toLinear(vec3 c){ return pow(c, vec3(2.2)); }\n"

    "float wh2(vec2 p){ return fract(sin(dot(p,vec2(41.3,289.1)))*43758.5453); }\n"
    "float wvn(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);\n"
    "  return mix(mix(wh2(i),wh2(i+vec2(1,0)),f.x), mix(wh2(i+vec2(0,1)),wh2(i+vec2(1,1)),f.x), f.y); }\n"

    // Analytic sky-gradient reflection sample, tinted toward the sun near R==lightDir.
    // Originally lived only inside waterShade (duplicated inline); factored out so the
    // new metal-reflection term below (bare iron/gold "sheen" surfaces) can reuse the
    // exact same sky approximation water already uses, instead of a second copy.
    "vec3 skyReflect(vec3 R){\n"
    "  float ry = clamp(R.y, 0.0, 1.0);\n"
    "  vec3 skyZen  = vec3(0.24, 0.46, 0.86);\n"
    "  vec3 skyHorz = vec3(0.52, 0.70, 0.92);\n"
    "  vec3 sky = mix(skyHorz, skyZen, pow(ry, 0.45));\n"
    "  float sunGlow = pow(max(dot(R, lightDir), 0.0), 8.0);\n"
    "  return mix(sky, sunCol*0.55, 0.30*sunGlow);\n"
    "}\n"
    "vec3 waterShade(vec3 baseCol, float rawSh, float foam){\n"
    "  vec3 V = normalize(viewPos - fragWorld);\n"
    "  vec2 w = fragWorld.xz;\n"

    "  float t = uTime;\n"
    "  float wdist = length(viewPos.xz - w);\n"
    "  float amp = 1.0 / (1.0 + wdist*0.018);\n"
    "  float nx = 0.032*sin(w.x*0.55 + w.y*0.31 + t*1.3)\n"
    "           + 0.022*sin(w.y*1.07 - t*0.9)\n"
    "           + 0.014*sin((w.x+w.y)*0.83 + t*1.7);\n"
    "  float nz = 0.032*sin(w.y*0.55 + w.x*0.31 - t*1.1)\n"
    "           + 0.022*sin(w.x*1.07 + t*0.8)\n"
    "           + 0.014*sin((w.x-w.y)*0.83 - t*1.5);\n"
    "  nx += (wvn(w*1.6 + t*0.25)-0.5)*0.028;\n"
    "  nz += (wvn(w*1.6 - t*0.21)-0.5)*0.028;\n"
    "  vec3 N = normalize(vec3(nx*amp, 1.0, nz*amp));\n"
    "  float NoV = max(dot(N, V), 0.0);\n"

    "  float fres = clamp(0.02 + 0.98*pow(1.0 - NoV, 5.0), 0.02, 0.62);\n"
    "  fres *= (1.0 - foam*0.65);\n"

    "  vec3 body = toLinear(baseCol);\n"
    "  float ndlW = max(dot(N, lightDir), 0.0);\n"
    "  vec3 deep = body * (0.62 + 0.46*ndlW*mix(0.4,1.0,rawSh)) + groundCol*0.04;\n"

    "  vec3 R = reflect(-V, N);\n"
    "  vec3 refl = skyReflect(R);\n"
    "  vec3 col = mix(deep, refl, fres);\n"

    "  vec3 H = normalize(lightDir + V);\n"
    "  float glint = pow(max(dot(N,H),0.0), 200.0)*rawSh;\n"
    "  col += sunCol*glint*1.6;\n"

    "  if(foam > 0.001){\n"
    "    float lace = wvn(w*2.3 + t*0.6)*0.6 + wvn(w*5.1 - t*0.4)*0.4;\n"
    "    float froth = smoothstep(0.45, 0.95, lace) * foam;\n"
    "    col = mix(col, vec3(0.92,0.96,0.98), clamp(froth*0.85, 0.0, 0.8));\n"
    "  }\n"
    "  return col;\n"
    "}\n"
    "void main(){\n"
    "  vec4 tex = texture(texture0, fragTexCoord);\n"
    "  vec3 base = tex.rgb*fragColor.rgb*colDiffuse.rgb;\n"

    "  if(fragColor.a < 0.72 && normalize(fragNormal).y > 0.80 && base.b > base.r*1.15){\n"
    "    float rawShW = shadow(vec3(0.0,1.0,0.0));\n"

    "    float foam = smoothstep(0.62, 0.70, fragColor.a);\n"
    "    vec3 wcol = waterShade(base, rawShW, foam);\n"
    "    if(legacyTonemap > 0.5){\n"
    "      wcol = aces(wcol*0.94);\n"
    "      wcol = pow(wcol, vec3(1.0/2.2));\n"
    "    }\n"
    "    float wa = mix(0.90, 0.96, foam);\n"

    "    if(fogEnd > 0.0){\n"
    "      float d = length(viewPos.xz - fragWorld.xz);\n"
    "      float fog = clamp((d - fogEnd*0.55)/(fogEnd*0.40), 0.0, 1.0);\n"
    "      wcol = mix(wcol, fogCol, fog);\n"
    "      wa = mix(wa, 0.0, fog);\n"
    "    }\n"
    "    finalColor = vec4(wcol, wa);\n"
    "    return;\n"
    "  }\n"
    "  vec3 albedo = toLinear(base);\n"
    "  float maxB = max(max(base.r, base.g), base.b);\n"
    "  float minB = min(min(base.r, base.g), base.b);\n"
    "  float maxA = max(max(albedo.r, albedo.g), albedo.b);\n"
    "  float minA = min(min(albedo.r, albedo.g), albedo.b);\n"
    "  float pale = smoothstep(0.50, 0.86, maxA) * (1.0-smoothstep(0.08, 0.26, maxA-minA));\n"
    "  float sheen = smoothstep(0.40, 0.82, maxB) * (1.0-smoothstep(0.10, 0.34, maxB-minB));\n"
    "  albedo = mix(albedo, albedo*vec3(0.76,0.83,0.91), pale*0.42);\n"
    "  vec3 N = normalize(fragNormal);\n"
    "  float ndl = max(dot(N,lightDir),0.0);\n"
    "  float rawSh = shadow(N);\n"
    "  float sh = mix(0.18, 1.0, rawSh);\n"
    "  vec3 direct = sunCol*1.02*ndl*sh;\n"

    "  float up   = clamp( N.y*0.5+0.5, 0.0, 1.0);\n"
    "  float down = clamp(-N.y, 0.0, 1.0);\n"
    "  vec3 skyFill   = skyCol   * (0.62 + 0.55*up);\n"
    "  vec3 bounce    = groundCol* (0.50 + 1.40*down);\n"
    "  vec3 ambient   = (skyFill + bounce) * (0.52 + 0.22*rawSh);\n"
    "  vec3 V = normalize(viewPos-fragWorld);\n"
    "  vec3 H = normalize(lightDir+V);\n"
    "  float NoH = max(dot(N,H),0.0);\n"
    "  float spec = (pow(NoH, 56.0)*(0.18 + 0.36*sheen) + pow(NoH, 18.0)*0.045*sheen)*rawSh*ndl;\n"
    "  float rim = pow(1.0-clamp(dot(N,V),0.0,1.0),3.6)*sheen*0.055*mix(0.35,1.0,rawSh);\n"
    // Anisotropic (Ward-style) highlight for the running rails: machined/rolled
    // steel is brushed lengthwise (the atlas T_IRON texture already bakes in a
    // horizontal brush-noise pattern), so its highlight should stretch along
    // the rail rather than form the round Blinn-Phong blob every other surface
    // gets. Project the rail tangent into the surface's own tangent plane (T),
    // derive the bitangent (B), then use the classic Ward anisotropic exponent
    // split (tight across the rail, long along it) so the glint reads as a
    // streak that slides along the rail as the camera moves, not a dot.
    "  float aniso = 0.0;\n"
    "  if(fragTexCoord.x > railUVRange.x && fragTexCoord.x < railUVRange.y){\n"
    "    vec3 tproj = railTangent - N*dot(railTangent,N);\n"
    // On the rail's end-cap faces N is nearly parallel to the tangent, so the
    // in-plane projection collapses to ~0 length -- skip the (undefined,
    // NaN-prone) normalize there; those faces are tiny and rare enough that
    // falling back to the isotropic spec/rim terms alone is unnoticeable.
    "    if(dot(tproj,tproj) > 1e-5){\n"
    "      vec3 T = normalize(tproj);\n"
    "      vec3 B = cross(N, T);\n"
    "      float HoT = dot(H,T), HoB = dot(H,B);\n"
    "      float axSharp = 5.0, axLong = 120.0;\n"
    "      float e = (HoT*HoT)*axLong + (HoB*HoB)*axSharp;\n"
    "      aniso = pow(NoH, e*0.02) * rawSh * ndl;\n"
    "    }\n"
    "  }\n"
    "  vec3 col = albedo*(ambient + direct) + sunCol*(spec + aniso*0.85) + skyCol*rim;\n"
    // Metal reflection: bare iron/gold surfaces (rails, spine, ties, trim -- anything
    // the existing `sheen` mask already flags as "shiny", the same mask spec/rim already
    // use) get a sky reflection blended in via Fresnel, reusing skyReflect() from
    // waterShade above rather than a second copy of the sky approximation. Blended
    // (mix), not additive, so it stays energy-conserving and doesn't feed spurious
    // extra brightness into the post-process bloom threshold. METAL_REFLECT_STRENGTH
    // caps the blend well under 1 (max ~0.30 at full sheen and grazing angle) -- a
    // hint of reflectivity, not a mirror finish.
    "  if(sheen > 0.001){\n"
    "    const float METAL_REFLECT_STRENGTH = 0.35;\n"
    "    vec3 Rm = reflect(-V, N);\n"
    "    vec3 metalRefl = skyReflect(Rm);\n"
    "    float NoV2 = max(dot(N,V), 0.0);\n"
    "    float fresM = clamp(0.04 + 0.96*pow(1.0-NoV2, 5.0), 0.04, 0.85);\n"
    "    col = mix(col, metalRefl, sheen*fresM*METAL_REFLECT_STRENGTH);\n"
    "  }\n"
    "  if(legacyTonemap > 0.5){\n"
    "    col = aces(col*0.94);\n"
    "    col = pow(col, vec3(1.0/2.2));\n"
    "    float lum = dot(col, vec3(0.299,0.587,0.114));\n"
    "    col = mix(vec3(lum), col, 1.10);\n"
    "  }\n"

    "  if(fogEnd > 0.0){\n"
    "    float d = length(viewPos.xz - fragWorld.xz);\n"
    "    float fog = clamp((d - fogEnd*0.55)/(fogEnd*0.40), 0.0, 1.0);\n"
    "    col = mix(col, fogCol, fog);\n"
    "  }\n"
    "  finalColor = vec4(col, tex.a*fragColor.a*colDiffuse.a);\n"
    "}\n";

static const char *DEPTH_VS =
    "#version 330\n"
    "in vec3 vertexPosition; uniform mat4 mvp;\n"
    "void main(){ gl_Position = mvp*vec4(vertexPosition,1.0); }\n";
static const char *DEPTH_FS =
    "#version 330\n"
    "void main(){}\n";

static const int SHADOW_CASCADES = 3;
// Cascade half-extents (world m): near/mid/far. The terrain ring generates out
// to TERRA_R=256 m around the camera (main.cpp, 16 chunks @ 16 m/chunk), so
// the far cascade is sized to use nearly all of that footprint rather than
// reaching past ground that will never exist.
static const float SHADOW_CASCADE_R[SHADOW_CASCADES] = { 32.0f, 100.0f, 245.0f };
// Depth-pass draw-call cull radius per cascade: box half-diagonal (R*sqrt2)
// plus a safety margin, mirroring the old single-map SHADOW_CULL_R pattern.
static const float SHADOW_CASCADE_CULL_R[SHADOW_CASCADES] = {
    SHADOW_CASCADE_R[0] * 1.42f + 15.0f,
    SHADOW_CASCADE_R[1] * 1.42f + 15.0f,
    SHADOW_CASCADE_R[2] * 1.42f + 15.0f,
};

struct ShadowSys {
    Shader lit{}, depth{};
    unsigned int fbo[SHADOW_CASCADES] = {0,0,0};
    unsigned int depthTex[SHADOW_CASCADES] = {0,0,0};
    int SM[SHADOW_CASCADES] = { 2048, 1536, 1024 };   // near cascade keeps full res; far cascade doesn't need it
    int locLightVP[SHADOW_CASCADES]   = {-1,-1,-1};
    int locShadowMap[SHADOW_CASCADES] = {-1,-1,-1};
    int locShadowTexel[SHADOW_CASCADES] = {-1,-1,-1};
    int locInvRange[SHADOW_CASCADES]  = {-1,-1,-1};
    int locCascadeSplit0=-1, locCascadeSplit1=-1, locShadowFocus=-1;
    int locLightDir=-1, locViewPos=-1;
    int locSun=-1, locSky=-1, locGround=-1, locDepthMVP=-1, locTime=-1;
    int locFogEnd=-1, locFogCol=-1;
    int locRailTangent=-1, locRailUVRange=-1;
    int locLegacyTonemap=-1;
    Matrix lightVP[SHADOW_CASCADES]{};
    float invRange[SHADOW_CASCADES]{};
    Vector3 focus{};   // last point cascades were centred on -- shaders must select cascades by distance from THIS, not the camera

    void init() {
        lit   = LoadShaderFromMemory(SHADOW_VS, SHADOW_FS);
        depth = LoadShaderFromMemory(DEPTH_VS, DEPTH_FS);
        const char *vpNames[SHADOW_CASCADES]    = { "lightVP0", "lightVP1", "lightVP2" };
        const char *mapNames[SHADOW_CASCADES]   = { "shadowMap0", "shadowMap1", "shadowMap2" };
        const char *texelNames[SHADOW_CASCADES] = { "shadowTexel0", "shadowTexel1", "shadowTexel2" };
        const char *rangeNames[SHADOW_CASCADES] = { "invRange0", "invRange1", "invRange2" };
        for (int i = 0; i < SHADOW_CASCADES; i++) {
            locLightVP[i]     = GetShaderLocation(lit, vpNames[i]);
            locShadowMap[i]   = GetShaderLocation(lit, mapNames[i]);
            locShadowTexel[i] = GetShaderLocation(lit, texelNames[i]);
            locInvRange[i]    = GetShaderLocation(lit, rangeNames[i]);
        }
        locCascadeSplit0 = GetShaderLocation(lit, "cascadeSplit0");
        locCascadeSplit1 = GetShaderLocation(lit, "cascadeSplit1");
        locShadowFocus   = GetShaderLocation(lit, "shadowFocus");
        locLightDir    = GetShaderLocation(lit, "lightDir");
        locViewPos     = GetShaderLocation(lit, "viewPos");
        locSun         = GetShaderLocation(lit, "sunCol");
        locSky         = GetShaderLocation(lit, "skyCol");
        locGround      = GetShaderLocation(lit, "groundCol");
        locTime        = GetShaderLocation(lit, "uTime");
        locFogEnd      = GetShaderLocation(lit, "fogEnd");
        locFogCol      = GetShaderLocation(lit, "fogCol");
        locRailTangent = GetShaderLocation(lit, "railTangent");
        locRailUVRange = GetShaderLocation(lit, "railUVRange");
        locLegacyTonemap = GetShaderLocation(lit, "legacyTonemap");
        for (int i = 0; i < SHADOW_CASCADES; i++) {
            fbo[i] = rlLoadFramebuffer();
            rlEnableFramebuffer(fbo[i]);
            depthTex[i] = rlLoadTextureDepth(SM[i], SM[i], false);
            rlFramebufferAttach(fbo[i], depthTex[i], RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0);
            if (!rlFramebufferComplete(fbo[i])) TraceLog(LOG_WARNING, "SHADOW: cascade %d framebuffer is incomplete, shadows may be disabled", i);
            rlDisableFramebuffer();
        }
    }

    // Fills lightVP[]/invRange[] for all cascades, centred on `focus` (the
    // camera/train focus point) along the fixed sun direction. Each cascade's
    // eye distance and far plane scale with its own half-extent so the box is
    // always fully contained regardless of sun elevation.
    void computeLightVP(Vector3 f) {
        focus = f;
        for (int i = 0; i < SHADOW_CASCADES; i++) {
            float R = SHADOW_CASCADE_R[i];
            float eyeDist = R * 2.2f + 40.0f;
            float nearP = 4.0f;
            float farP  = eyeDist + R * 1.8f;
            Vector3 eye = Vector3Add(focus, Vector3Scale(g_sunDir, eyeDist));
            Matrix view = MatrixLookAt(eye, focus, Vector3{ 0, 1, 0 });
            Matrix proj = MatrixOrtho(-R, R, -R, R, nearP, farP);
            lightVP[i] = MatrixMultiply(view, proj);
            invRange[i] = 1.0f / (farP - nearP);
        }
    }
};
static ShadowSys gShadow;

static const char *SKY_VS =
    "#version 330\n"
    "in vec3 vertexPosition; in vec2 vertexTexCoord;\n"
    "uniform mat4 mvp;\n"
    "uniform vec2 resolution;\n"
    "out vec2 uv;\n"
    "void main(){ uv = vertexPosition.xy/resolution; gl_Position = mvp*vec4(vertexPosition,1.0); }\n";
static const char *SKY_FS =
    "#version 330\n"
    "in vec2 uv; out vec4 finalColor;\n"
    "uniform vec3 camDir; uniform vec3 camRight; uniform vec3 camUp;\n"
    "uniform float tanHalfFovY; uniform float aspect;\n"
    "uniform vec3 sunDir; uniform vec3 camPos;\n"
    "const vec3 ZENITH  = vec3(0.045, 0.26, 0.74);\n"
    "const vec3 MIDSKY  = vec3(0.16, 0.50, 0.95);\n"
    "const vec3 HORIZON = vec3(0.52, 0.74, 1.00);\n"
    "const vec3 HAZE    = vec3(1.00, 0.78, 0.50);\n"

    "const vec3 GROUND  = vec3(0.64, 0.72, 0.80);\n"
    // Sky is only ever drawn into the offscreen HDR scene target (see PostFX)
    // -- no inline tonemap/gamma here anymore; the single composite pass at
    // the end of the frame handles that once for the whole image, so the sun
    // disc/corona/shafts stay properly over-bright (>1.0) for bloom to pick up.
    "float h13(vec3 p){ p=fract(p*0.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }\n"
    "float vn3(vec3 x){ vec3 i=floor(x), f=fract(x); f=f*f*(3.0-2.0*f);\n"
    "  return mix(mix(mix(h13(i+vec3(0,0,0)),h13(i+vec3(1,0,0)),f.x), mix(h13(i+vec3(0,1,0)),h13(i+vec3(1,1,0)),f.x),f.y),\n"
    "             mix(mix(h13(i+vec3(0,0,1)),h13(i+vec3(1,0,1)),f.x), mix(h13(i+vec3(0,1,1)),h13(i+vec3(1,1,1)),f.x),f.y), f.z); }\n"
    "float cloudDens(vec3 p){\n"
    "  float cb=300.0, ct=470.0; float hf=(p.y-cb)/(ct-cb);\n"
    "  if(hf<0.0||hf>1.0) return 0.0;\n"
    "  hf = smoothstep(0.0,0.32,hf)*smoothstep(1.0,0.5,hf);\n"
    "  vec3 q=p*0.0013;\n"
    "  float base = vn3(q*4.0+3.1)*0.6 + vn3(q*8.0)*0.3 + vn3(q*16.0)*0.15;\n"
    "  return smoothstep(0.62,0.95, base) * hf;\n"
    "}\n"
    "vec4 cloudVolume(vec3 ro, vec3 rd, vec3 sun, float lift){\n"

    "  float cb=300.0, ct=470.0;\n"
    "  float t0=(cb-ro.y)/rd.y, t1=(ct-ro.y)/rd.y;\n"
    "  float tn=max(min(t0,t1),0.0), tf=max(t0,t1);\n"
    "  if(tf<=tn) return vec4(0.0);\n"
    "  const float DMAX=4200.0;\n"
    "  float distFade = 1.0 - smoothstep(DMAX*0.72, DMAX, tn);\n"
    "  if(distFade <= 0.0) return vec4(0.0);\n"
    "  tf=min(tf,tn+1500.0);\n"
    "  const int N=14; float dt=(tf-tn)/float(N);\n"
    "  float t=tn+dt*h13(vec3(gl_FragCoord.xy,1.0));\n"
    "  float trans=1.0; vec3 acc=vec3(0.0);\n"
    "  vec3 sunC=mix(vec3(1.0,0.85,0.70), vec3(1.0,0.97,0.92), lift);\n"
    "  vec3 ambC=vec3(0.60,0.67,0.80);\n"
    "  for(int i=0;i<N;i++){\n"
    "    vec3 p=ro+rd*t; float d=cloudDens(p);\n"
    "    if(d>0.01){\n"
    "      float ld=cloudDens(p+sun*42.0)+cloudDens(p+sun*95.0)*0.6;\n"
    "      float sh=exp(-ld*1.5);\n"
    "      vec3 cc=ambC + sunC*sh*1.6;\n"
    "      float a=clamp(d*0.9,0.0,1.0);\n"
    "      acc+=trans*a*cc; trans*=(1.0-a);\n"
    "      if(trans<0.03) break;\n"
    "    }\n"
    "    t+=dt;\n"
    "  }\n"
    "  return vec4(acc, (1.0-trans)*distFade);\n"
    "}\n"
    "void main(){\n"
    "  vec2 ndc = uv*2.0-1.0;\n"
    "  vec3 dir = normalize(camDir + camRight*ndc.x*tanHalfFovY*aspect + camUp*(-ndc.y)*tanHalfFovY);\n"
    "  vec3 sun = normalize(sunDir);\n"
    "  float sunLift = smoothstep(-0.12, 0.55, sun.y);\n"

    "  float h = clamp(dir.y*0.5+0.5, 0.0, 1.0);\n"
    "  float skyT = smoothstep(0.03, 0.92, h);\n"
    "  vec3 col = mix(HORIZON, MIDSKY, smoothstep(0.0, 0.55, skyT));\n"
    "  col = mix(col, ZENITH, smoothstep(0.34, 1.0, skyT));\n"

    "  float airMass = exp(-max(dir.y,0.0)*2.6);\n"
    "  col = mix(col, HORIZON, airMass*0.22);\n"
    "  float horizon = exp(-abs(dir.y)*4.2);\n"
    "  col += HORIZON*horizon*0.22;\n"
    "  col += HAZE*horizon*(0.10 + 0.20*(1.0-sunLift));\n"

    "  float sunAz = clamp(dot(normalize(dir.xz), normalize(sun.xz)), 0.0, 1.0);\n"
    "  vec3 lowHaze = mix(GROUND, GROUND*vec3(1.05,1.0,0.93), sunAz*0.6);\n"
    "  col = mix(lowHaze, col, smoothstep(-0.16, 0.06, dir.y));\n"

    "  float mu = clamp(dot(dir, sun), -1.0, 1.0);\n"
    "  float forward = max(mu, 0.0);\n"

    "  float rayleigh = 0.55 + 0.45*mu*mu;\n"
    "  col *= rayleigh;\n"
    "  vec3 sunTint = mix(vec3(1.0,0.62,0.32), vec3(1.0,0.90,0.70), sunLift);\n"

    "  float mieSharp = pow(forward, 22.0);\n"
    "  float mieBroad = pow(forward, 5.0);\n"
    "  col += sunTint*mieSharp*(0.42 + 0.36*horizon);\n"
    "  col += sunTint*mieBroad*(0.10 + 0.16*(1.0-sunLift));\n"

    "  float viewSun = max(dot(camDir, sun), 0.0);\n"
    "  float lookGate = smoothstep(0.55, 0.96, viewSun);\n"

    "  vec3 ref = (abs(sun.y) > 0.94) ? vec3(1.0,0.0,0.0) : vec3(0.0,1.0,0.0);\n"
    "  vec3 sr = normalize(cross(ref, sun));\n"
    "  vec3 su = cross(sun, sr);\n"
    "  vec2 sunPlane = vec2(dot(dir, sr), dot(dir, su));\n"
    "  float a = atan(sunPlane.y, sunPlane.x);\n"
    "  float r = length(sunPlane);\n"
    "  float streaks = pow(0.5+0.5*sin(a*13.0 + sin(a*5.0)*1.7), 4.0);\n"
    "  float shafts = streaks*smoothstep(0.72, 0.995, forward)*smoothstep(0.68, 0.08, r);\n"
    "  col += sunTint*shafts*(0.26 + 0.30*horizon)*sunLift*lookGate;\n"

    "  float bar = exp(-pow(sunPlane.y*9.0,2.0)) * smoothstep(0.5,0.0,r);\n"
    "  col += sunTint*bar*0.22*lookGate;\n"
    "  float ghost = exp(-pow((r-0.16)*10.0,2.0)) + 0.6*exp(-pow((r-0.34)*7.0,2.0));\n"
    "  col += sunTint*ghost*0.05*lookGate;\n"

    "  float disc = smoothstep(0.99950, 0.99986, mu);\n"
    "  float corona = pow(forward, 96.0);\n"
    "  col += vec3(1.0,0.93,0.74)*corona*0.58*sunLift*mix(0.4,1.0,lookGate);\n"
    "  col = mix(col, vec3(1.0,0.94,0.78), disc*0.78*sunLift);\n"
    "  col += vec3(1.0,0.97,0.84)*disc*1.15*sunLift;\n"

    "  vec4 cl = cloudVolume(camPos, dir, sun, sunLift);\n"
    "  col = col*(1.0-cl.a) + cl.rgb;\n"
    "  finalColor = vec4(max(col, 0.0), 1.0);\n"
    "}\n";

struct SkySys {
    Shader sh{};
    int locCamDir=-1, locCamRight=-1, locCamUp=-1, locTan=-1, locAspect=-1, locSun=-1, locRes=-1, locCamPos=-1;
    void init() {
        sh = LoadShaderFromMemory(SKY_VS, SKY_FS);
        locCamDir   = GetShaderLocation(sh, "camDir");
        locCamRight = GetShaderLocation(sh, "camRight");
        locCamUp    = GetShaderLocation(sh, "camUp");
        locTan      = GetShaderLocation(sh, "tanHalfFovY");
        locAspect   = GetShaderLocation(sh, "aspect");
        locSun      = GetShaderLocation(sh, "sunDir");
        locRes      = GetShaderLocation(sh, "resolution");
        locCamPos   = GetShaderLocation(sh, "camPos");
    }
};
static SkySys gSky;

// ---------------------------------------------------------------------------
// Post-processing: a single offscreen linear-HDR scene target (sky + opaque +
// water all render into this instead of the backbuffer) followed by one
// fullscreen composite pass: bloom add -> vignette -> chromatic aberration ->
// film grain/dither -> ACES tonemap + gamma + saturation. This replaces the 3
// duplicated inline tonemap copies that used to live in SHADOW_FS's opaque
// and water branches and in SKY_FS -- now there is exactly one.
//
// Bloom is kept cheap on purpose (this is a software rasterizer sandbox and a
// prior pass already had to fight hard for a double-digit-percent frame-time
// win): the bright-pass extraction happens directly at a downsampled
// resolution (1/BLOOM_DOWNSCALE per axis, so 1/16th the pixel count) and the
// blur is a small 5-tap separable pass at that same low resolution -- never a
// full-res or large-kernel blur.
//
// All tuning knobs are named constants here so they're easy to dial back:
//
// BLOOM_THRESHOLD is expressed in POST-tonemap luma (0..1), not raw linear
// HDR magnitude: ordinary sunlit terrain/track already sits at a linear HDR
// magnitude of ~1-3 in this engine (that's exactly the range the old inline
// aces(col*0.94) curve was designed to compress down to a pleasant ~0.75-0.95
// display value), so a raw-linear threshold anywhere near 1.0 caught nearly
// everything lit by the sun and bloomed the whole frame into a haze. Running
// the same aces() curve inside the bright-pass first and thresholding its
// *output* isolates only the pixels that would render at the very top of the
// display range -- the sun disc, hard specular glints, bright sky near the
// sun -- regardless of how big the underlying linear HDR value actually is.
static const float BLOOM_THRESHOLD    = 0.965f;  // post-tonemap luma above this feeds bloom (near-saturated highlights only)
static const float BLOOM_INTENSITY    = 0.22f;   // additive strength of the blurred bright-pass once composited back
static const float VIGNETTE_STRENGTH  = 0.16f;   // 0 = off; darkening only reaches the far corners, kept subtle
static const float CHROMATIC_ABERRATION_STRENGTH = 0.0020f; // per-channel radial UV offset scale -- barely perceptible by design
static const float FILM_GRAIN_STRENGTH = 0.012f; // additive grain/dither amplitude, applied pre-tonemap
static const int   BLOOM_DOWNSCALE    = 4;       // bloom buffers render at 1/4 x 1/4 resolution (1/16th the pixels)

// Shared fullscreen-quad vertex shader: derives a plain pixel-space UV in
// [0,1] from vertexPosition (mirrors SKY_VS's trick), assuming the caller
// always draws a DrawRectangle(0,0,resolution.x,resolution.y,...) while this
// shader is active.
static const char *POST_VS =
    "#version 330\n"
    "in vec3 vertexPosition; in vec2 vertexTexCoord;\n"
    "uniform mat4 mvp;\n"
    "uniform vec2 resolution;\n"
    "out vec2 uv;\n"
    "void main(){ uv = vertexPosition.xy/resolution; gl_Position = mvp*vec4(vertexPosition,1.0); }\n";

// NOTE on the flip: every custom offscreen target here (scene HDR target,
// bloom buffers) is written via raylib's BeginTextureMode, which uses a
// top-left-origin pixel convention for rasterization -- but when that same
// texture is later *sampled* with texture(), GL's bottom-left-origin sampling
// convention means the image reads back upside-down unless corrected. uv (as
// produced by POST_VS above) is also top-left-origin, so every sample of one
// of our own render targets flips V: texture(tex, vec2(uv.x, 1.0-uv.y)).
// (Blur's symmetric +/- taps don't care about this sign, so it skips the flip
// on its step direction and only flips the base sample.)

static const char *BRIGHTPASS_FS =
    "#version 330\n"
    "in vec2 uv; out vec4 finalColor;\n"
    "uniform sampler2D sceneTex; uniform vec2 srcTexel; uniform float uThreshold;\n"
    "vec3 sampleFlip(vec2 u){ return texture(sceneTex, vec2(u.x, 1.0-u.y)).rgb; }\n"
    // Same aces() curve as the composite pass's final tonemap -- used here
    // only to measure "how close to display-white would this pixel end up",
    // not to actually tonemap the bloom contribution itself.
    "vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0); }\n"
    "void main(){\n"
    // 4-tap box average of the full-res scene texture (source-texel footprint
    // around this low-res texel's centre) -- cheap anti-alias for the
    // downsample so thin bright details (rail glints) don't shimmer once blurred.
    "  vec3 c = sampleFlip(uv + srcTexel*vec2(-0.5,-0.5))\n"
    "         + sampleFlip(uv + srcTexel*vec2( 0.5,-0.5))\n"
    "         + sampleFlip(uv + srcTexel*vec2(-0.5, 0.5))\n"
    "         + sampleFlip(uv + srcTexel*vec2( 0.5, 0.5));\n"
    "  c *= 0.25;\n"
    // Threshold on POST-tonemap luma, not raw linear magnitude: ordinary
    // sunlit terrain/track already sits at linear HDR ~1-3 in this engine (see
    // BLOOM_THRESHOLD's comment above), so thresholding the raw value bloomed
    // almost the entire frame. Measuring "where would this land on the
    // display curve" isolates only near-saturated highlights.
    "  vec3 tm = aces(c*0.94);\n"
    "  float lum = max(max(tm.r,tm.g),tm.b);\n"
    "  float knee = (1.0-uThreshold)*0.5 + 1e-4;\n"
    "  float soft = clamp(lum - uThreshold + knee, 0.0, 2.0*knee);\n"
    "  soft = (soft*soft) / (4.0*knee);\n"
    "  float contrib = max(soft, lum - uThreshold);\n"
    "  c *= contrib / max(lum, 1e-4);\n"
    "  finalColor = vec4(max(c, 0.0), 1.0);\n"
    "}\n";

static const char *BLUR_FS =
    "#version 330\n"
    "in vec2 uv; out vec4 finalColor;\n"
    "uniform sampler2D srcTex; uniform vec2 texelStep;\n"
    "void main(){\n"
    "  vec2 suv = vec2(uv.x, 1.0-uv.y);\n"
    // Small-radius separable 5-tap Gaussian (sigma ~1 texel of the already-
    // downsampled bloom buffer) -- deliberately not a large-kernel blur.
    "  vec3 c = texture(srcTex, suv).rgb * 0.398943;\n"
    "  c += (texture(srcTex, suv+texelStep).rgb     + texture(srcTex, suv-texelStep).rgb)     * 0.242036;\n"
    "  c += (texture(srcTex, suv+texelStep*2.0).rgb + texture(srcTex, suv-texelStep*2.0).rgb) * 0.060626;\n"
    "  finalColor = vec4(max(c, 0.0), 1.0);\n"
    "}\n";

static const char *COMPOSITE_FS =
    "#version 330\n"
    "in vec2 uv; out vec4 finalColor;\n"
    "uniform sampler2D sceneTex; uniform sampler2D bloomTex;\n"
    "uniform float uBloomIntensity, uVignette, uCA, uGrain, uTime;\n"
    // Same aces() curve/constants as the old inline copies (SHADOW_FS's
    // opaque+water branches used *0.94 before this curve; that's the constant
    // kept here -- SKY_FS used a slightly different *1.08 pre-scale, now
    // unified to the single canonical value since the whole frame shares one
    // exposure/tonemap from this point on).
    "vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0); }\n"
    "float hashN(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233)))*43758.5453); }\n"
    "void main(){\n"
    "  vec2 d = uv - 0.5;\n"
    "  float r2 = dot(d,d);\n"
    // Chromatic aberration: tiny per-channel radial UV offset, growing with
    // (distance from centre)^2 so it stays essentially invisible near the
    // middle of the frame and only barely shows at the extreme edges.
    "  vec2 caOff = d * uCA * r2;\n"
    "  vec2 uvR = vec2(uv.x + caOff.x, 1.0 - (uv.y + caOff.y));\n"
    "  vec2 uvG = vec2(uv.x,           1.0 -  uv.y);\n"
    "  vec2 uvB = vec2(uv.x - caOff.x, 1.0 - (uv.y - caOff.y));\n"
    "  vec3 col;\n"
    "  col.r = texture(sceneTex, uvR).r;\n"
    "  col.g = texture(sceneTex, uvG).g;\n"
    "  col.b = texture(sceneTex, uvB).b;\n"
    // Bloom add (bloomTex is the small blurred bright-pass buffer; GL's own
    // bilinear filtering upsamples it back to full res for free here).
    "  vec3 bloomCol = texture(bloomTex, uvG).rgb;\n"
    "  col += bloomCol * uBloomIntensity;\n"
    // Vignette: subtle radial darkening that only really bites past ~35% of
    // the half-diagonal, i.e. the outer corners, not the whole frame.
    "  float vig = 1.0 - uVignette*smoothstep(0.15, 0.75, sqrt(r2));\n"
    "  col *= vig;\n"
    // Film grain / dither: tiny per-pixel, per-frame noise. Subtle enough to
    // read as grain rather than static, and doubles as banding-reduction
    // dither for the point-filtered/no-mipmap procedural textures.
    "  float grain = (hashN(gl_FragCoord.xy + fract(uTime)*997.13) - 0.5) * uGrain;\n"
    "  col += grain;\n"
    "  col = max(col, 0.0);\n"
    "  col = aces(col*0.94);\n"
    "  col = pow(col, vec3(1.0/2.2));\n"
    "  float lum = dot(col, vec3(0.299,0.587,0.114));\n"
    "  col = mix(vec3(lum), col, 1.10);\n"
    "  finalColor = vec4(clamp(col, 0.0, 1.0), 1.0);\n"
    "}\n";

struct PostFX {
    Shader brightpass{}, blur{}, composite{};
    int locBP_Res=-1, locBP_SrcTexel=-1, locBP_Thresh=-1, locBP_SceneTex=-1;
    int locBL_Res=-1, locBL_TexelStep=-1, locBL_SrcTex=-1;
    int locCP_Res=-1, locCP_BloomI=-1, locCP_Vignette=-1, locCP_CA=-1, locCP_Grain=-1, locCP_Time=-1;
    int locCP_SceneTex=-1, locCP_BloomTex=-1;

    RenderTexture2D sceneRT{};
    RenderTexture2D bloomRT[2]{};
    int sceneW=0, sceneH=0, bloomW=0, bloomH=0;

    // Mirrors pathtrace.cpp's gPT.accum/gPT.rtBuf low-level pattern (manual
    // rlLoadFramebuffer/rlLoadTexture/rlFramebufferAttach rather than
    // LoadRenderTexture) so the whole scene stays in a half-float linear HDR
    // buffer without clipping bright values before the bloom bright-pass runs.
    static void makeColorTarget(RenderTexture2D &rt, int w, int h, bool withDepth) {
        rt = RenderTexture2D{};
        rt.id = rlLoadFramebuffer();
        rlEnableFramebuffer(rt.id);
        rt.texture.id = rlLoadTexture(NULL, w, h, RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16, 1);
        rt.texture.width = w; rt.texture.height = h; rt.texture.mipmaps = 1;
        rt.texture.format = PIXELFORMAT_UNCOMPRESSED_R16G16B16A16;
        rlFramebufferAttach(rt.id, rt.texture.id, RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D, 0);
        if (withDepth) {
            rt.depth.id = rlLoadTextureDepth(w, h, false);
            rt.depth.width = w; rt.depth.height = h;
            rlFramebufferAttach(rt.id, rt.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0);
        } else {
            rt.depth.id = 0;
        }
        if (!rlFramebufferComplete(rt.id)) TraceLog(LOG_WARNING, "POSTFX: framebuffer incomplete (%dx%d)", w, h);
        rlDisableFramebuffer();
        SetTextureFilter(rt.texture, TEXTURE_FILTER_BILINEAR);
        // Chromatic aberration's radial UV offset pushes samples slightly outside [0,1]
        // near the screen edges -- rlLoadTexture defaults to REPEAT wrap, so without this
        // those samples wrap around and pick up the OPPOSITE edge of the frame instead of
        // clamping, producing a colored fringe down the left/right/top/bottom borders
        // (confirmed visually: a magenta fringe down the left edge before this fix).
        SetTextureWrap(rt.texture, TEXTURE_WRAP_CLAMP);
    }

    void init(int w, int h) {
        sceneW = w; sceneH = h;
        bloomW = w / BLOOM_DOWNSCALE; if (bloomW < 1) bloomW = 1;
        bloomH = h / BLOOM_DOWNSCALE; if (bloomH < 1) bloomH = 1;

        makeColorTarget(sceneRT,    sceneW, sceneH, true);
        makeColorTarget(bloomRT[0], bloomW, bloomH, false);
        makeColorTarget(bloomRT[1], bloomW, bloomH, false);

        brightpass = LoadShaderFromMemory(POST_VS, BRIGHTPASS_FS);
        blur       = LoadShaderFromMemory(POST_VS, BLUR_FS);
        composite  = LoadShaderFromMemory(POST_VS, COMPOSITE_FS);

        locBP_Res      = GetShaderLocation(brightpass, "resolution");
        locBP_SrcTexel = GetShaderLocation(brightpass, "srcTexel");
        locBP_Thresh   = GetShaderLocation(brightpass, "uThreshold");
        locBP_SceneTex = GetShaderLocation(brightpass, "sceneTex");

        locBL_Res       = GetShaderLocation(blur, "resolution");
        locBL_TexelStep = GetShaderLocation(blur, "texelStep");
        locBL_SrcTex    = GetShaderLocation(blur, "srcTex");

        locCP_Res      = GetShaderLocation(composite, "resolution");
        locCP_BloomI   = GetShaderLocation(composite, "uBloomIntensity");
        locCP_Vignette = GetShaderLocation(composite, "uVignette");
        locCP_CA       = GetShaderLocation(composite, "uCA");
        locCP_Grain    = GetShaderLocation(composite, "uGrain");
        locCP_Time     = GetShaderLocation(composite, "uTime");
        locCP_SceneTex = GetShaderLocation(composite, "sceneTex");
        locCP_BloomTex = GetShaderLocation(composite, "bloomTex");

        float thr = BLOOM_THRESHOLD;
        SetShaderValue(brightpass, locBP_Thresh, &thr, SHADER_UNIFORM_FLOAT);
        float bloomI = BLOOM_INTENSITY, vig = VIGNETTE_STRENGTH,
              ca = CHROMATIC_ABERRATION_STRENGTH, gr = FILM_GRAIN_STRENGTH;
        SetShaderValue(composite, locCP_BloomI,   &bloomI, SHADER_UNIFORM_FLOAT);
        SetShaderValue(composite, locCP_Vignette, &vig,    SHADER_UNIFORM_FLOAT);
        SetShaderValue(composite, locCP_CA,       &ca,     SHADER_UNIFORM_FLOAT);
        SetShaderValue(composite, locCP_Grain,    &gr,     SHADER_UNIFORM_FLOAT);
    }

    // Sky + opaque + water all render between these two, into sceneRT instead
    // of the backbuffer, so their fragment shaders can stay in linear HDR.
    void beginScene() { BeginTextureMode(sceneRT); }
    void endScene()   { EndTextureMode(); }

    // Bloom extract+blur (cheap: low-res throughout) then the single
    // fullscreen composite pass, written to whatever framebuffer is currently
    // bound (the default backbuffer, from the main render loop) -- must run
    // before any HUD drawing so HUD text/icons never pick up bloom/vignette/
    // CA/grain.
    void resolve(int rw, int rh, float time) {
        static const int SCENE_UNIT = 15, BLOOM_UNIT = 16;
        rlDrawRenderBatchActive();

        // ---- bright-pass extract: full-res scene -> low-res bloomRT[0] ----
        BeginTextureMode(bloomRT[0]);
            rlDisableDepthTest(); rlDisableDepthMask();
            float bpRes[2] = { (float)bloomW, (float)bloomH };
            float srcTexel[2] = { 1.0f / sceneW, 1.0f / sceneH };
            SetShaderValue(brightpass, locBP_Res, bpRes, SHADER_UNIFORM_VEC2);
            SetShaderValue(brightpass, locBP_SrcTexel, srcTexel, SHADER_UNIFORM_VEC2);
            BeginShaderMode(brightpass);
                SetShaderValue(brightpass, locBP_SceneTex, &SCENE_UNIT, SHADER_UNIFORM_INT);
                rlActiveTextureSlot(SCENE_UNIT); rlEnableTexture(sceneRT.texture.id);
                rlActiveTextureSlot(0);
                DrawRectangle(0, 0, bloomW, bloomH, WHITE);
                rlDrawRenderBatchActive();
                rlActiveTextureSlot(SCENE_UNIT); rlDisableTexture(); rlActiveTextureSlot(0);
            EndShaderMode();
        EndTextureMode();

        // ---- separable blur, ping-ponged at the same low res ----
        auto blurPass = [&](RenderTexture2D &src, RenderTexture2D &dst, float dx, float dy) {
            BeginTextureMode(dst);
                float blRes[2] = { (float)bloomW, (float)bloomH };
                float step[2] = { dx / bloomW, dy / bloomH };
                SetShaderValue(blur, locBL_Res, blRes, SHADER_UNIFORM_VEC2);
                SetShaderValue(blur, locBL_TexelStep, step, SHADER_UNIFORM_VEC2);
                BeginShaderMode(blur);
                    SetShaderValue(blur, locBL_SrcTex, &SCENE_UNIT, SHADER_UNIFORM_INT);
                    rlActiveTextureSlot(SCENE_UNIT); rlEnableTexture(src.texture.id);
                    rlActiveTextureSlot(0);
                    DrawRectangle(0, 0, bloomW, bloomH, WHITE);
                    rlDrawRenderBatchActive();
                    rlActiveTextureSlot(SCENE_UNIT); rlDisableTexture(); rlActiveTextureSlot(0);
                EndShaderMode();
            EndTextureMode();
        };
        blurPass(bloomRT[0], bloomRT[1], 1.0f, 0.0f);
        blurPass(bloomRT[1], bloomRT[0], 0.0f, 1.0f);
        // Final blurred bloom now sits in bloomRT[0].

        // ---- final composite onto the currently-bound (default) framebuffer ----
        rlViewport(0, 0, rw, rh);
        rlSetMatrixProjection(MatrixOrtho(0, rw, rh, 0, 0.0, 1.0));
        rlSetMatrixModelview(MatrixIdentity());
        rlDisableDepthTest(); rlDisableDepthMask();
        float cpRes[2] = { (float)rw, (float)rh };
        SetShaderValue(composite, locCP_Res, cpRes, SHADER_UNIFORM_VEC2);
        SetShaderValue(composite, locCP_Time, &time, SHADER_UNIFORM_FLOAT);
        BeginShaderMode(composite);
            SetShaderValue(composite, locCP_SceneTex, &SCENE_UNIT, SHADER_UNIFORM_INT);
            SetShaderValue(composite, locCP_BloomTex, &BLOOM_UNIT, SHADER_UNIFORM_INT);
            rlActiveTextureSlot(SCENE_UNIT); rlEnableTexture(sceneRT.texture.id);
            rlActiveTextureSlot(BLOOM_UNIT); rlEnableTexture(bloomRT[0].texture.id);
            rlActiveTextureSlot(0);
            DrawRectangle(0, 0, rw, rh, WHITE);
            rlDrawRenderBatchActive();
            rlActiveTextureSlot(SCENE_UNIT); rlDisableTexture();
            rlActiveTextureSlot(BLOOM_UNIT); rlDisableTexture();
            rlActiveTextureSlot(0);
        EndShaderMode();
        // Leave depth test/mask disabled here, matching the state EndMode3D()
        // already leaves things in pre-existing code paths: nothing else this
        // frame (HUD, screenshot triggers) needs depth testing, and the next
        // frame's shadow-cascade pass re-enables both explicitly before it
        // needs them. The default framebuffer's own depth attachment is never
        // written by this pipeline any more (all 3-D geometry now depth-tests
        // against sceneRT's own depth texture instead), so its contents are
        // stale/undefined -- re-enabling depth test here would depth-test HUD
        // draws against that stale buffer for no benefit.
    }
};
static PostFX gPostFX;

#endif
