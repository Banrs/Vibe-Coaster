static Vector3 orthoUp(Vector3 fwd, Vector3 upHint) {
    Vector3 up = Vector3Subtract(upHint, Vector3Scale(fwd, Vector3DotProduct(upHint, fwd)));
    if (Vector3Length(up) < 1e-3f) {
        Vector3 ref = (fabsf(fwd.y) < 0.9f) ? Vector3{ 0, 1, 0 } : Vector3{ 1, 0, 0 };
        up = Vector3Subtract(ref, Vector3Scale(fwd, Vector3DotProduct(ref, fwd)));
    }
    return Vector3Normalize(up);
}

static void pushFrame(Vector3 P, Vector3 fwd, Vector3 up) {
    fwd = Vector3Normalize(fwd);
    if (!(fwd.x == fwd.x) || Vector3Length(fwd) < 0.5f) fwd = Vector3{ 0, 0, 1 };
    up = orthoUp(fwd, up);
    Vector3 right = Vector3CrossProduct(up, fwd);
    float rl = Vector3Length(right);
    right = (rl < 1e-3f) ? Vector3{ 1, 0, 0 } : Vector3Scale(right, 1.0f / rl);
    Matrix m = {
        right.x, up.x, fwd.x, P.x,
        right.y, up.y, fwd.y, P.y,
        right.z, up.z, fwd.z, P.z,
        0,       0,    0,     1,
    };
    rlPushMatrix();
    float16 mf = MatrixToFloatV(m);
    rlMultMatrixf(mf.v);
}
static void popFrame() { rlPopMatrix(); }

static inline Vector3 vlerp(Vector3 a, Vector3 b, float s) {
    return { a.x + (b.x - a.x) * s, a.y + (b.y - a.y) * s, a.z + (b.z - a.z) * s };
}

static Vector3 catmull(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t) {
    const float A = 0.5f;
    float t0 = 0.0f;
    float t1 = t0 + powf(fmaxf(Vector3Distance(p0, p1), 1e-3f), A);
    float t2 = t1 + powf(fmaxf(Vector3Distance(p1, p2), 1e-3f), A);
    float t3 = t2 + powf(fmaxf(Vector3Distance(p2, p3), 1e-3f), A);
    float tt = t1 + (t2 - t1) * t;
    Vector3 A1 = vlerp(p0, p1, (tt - t0) / (t1 - t0));
    Vector3 A2 = vlerp(p1, p2, (tt - t1) / (t2 - t1));
    Vector3 A3 = vlerp(p2, p3, (tt - t2) / (t3 - t2));
    Vector3 B1 = vlerp(A1, A2, (tt - t0) / (t2 - t0));
    Vector3 B2 = vlerp(A2, A3, (tt - t1) / (t3 - t1));
    return vlerp(B1, B2, (tt - t1) / (t2 - t1));
}

// Centripetal Catmull-Rom is a good plan-view spline, but it may overshoot a vertical
// extremum when the surrounding control-point spacing changes.  That is particularly
// visible on a fast coaster as a tiny extra hump/valley between two otherwise deliberate
// elements.  Use a monotone cubic only for the elevation channel: it remains C1 at every
// control point, preserves the authored height at crests and valleys, and cannot invent an
// extra vertical reversal between p1 and p2.
static float monotoneHermiteY(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t) {
    float h0 = fmaxf(Vector3Distance(p1, p0), 1e-3f);
    float h1 = fmaxf(Vector3Distance(p2, p1), 1e-3f);
    float h2 = fmaxf(Vector3Distance(p3, p2), 1e-3f);
    float d0 = (p1.y - p0.y) / h0;
    float d1 = (p2.y - p1.y) / h1;
    float d2 = (p3.y - p2.y) / h2;

    // Weighted harmonic means are the Fritsch-Carlson monotonicity-preserving tangents.
    // A sign change is a real crest/trough, so its tangent must be zero rather than letting
    // Catmull-Rom carry slope through the extremum and create a micro-element.
    auto tangent = [](float left, float right, float hl, float hr) {
        if (left * right <= 0.0f) return 0.0f;
        float w1 = 2.0f * hr + hl;
        float w2 = hr + 2.0f * hl;
        return (w1 + w2) / (w1 / left + w2 / right);
    };
    float m1 = tangent(d0, d1, h0, h1);
    float m2 = tangent(d1, d2, h1, h2);
    float u  = Clamp(t, 0.0f, 1.0f);
    float u2 = u * u, u3 = u2 * u;
    return (2.0f*u3 - 3.0f*u2 + 1.0f) * p1.y +
           (u3 - 2.0f*u2 + u) * h1 * m1 +
           (-2.0f*u3 + 3.0f*u2) * p2.y +
           (u3 - u2) * h1 * m2;
}

static float septicC3(float p0, float p1, float p2, float p3, float t) {
    // Interpolating seventh-order Hermite span. Adjacent spans share position,
    // tangent and curvature; assigning the same zero curvature derivative at
    // every knot also makes jerk continuous (C3). Unlike a smoothing B-spline
    // it still passes through every authored point, so it does not turn the
    // coaster into a predictive projectile trace.
    float m1 = 0.5f * (p2 - p0), m2 = 0.5f * (p3 - p1);
    float a1 = p2 - 2.0f * p1 + p0, a2 = p3 - 2.0f * p2 + p1;
    float c0 = p1, c1 = m1, c2 = 0.5f * a1, c3 = 0.0f;
    float P = p2 - (c0 + c1 + c2 + c3);
    float V = m2 - (c1 + 2.0f*c2 + 3.0f*c3);
    float A = a2 - (2.0f*c2 + 6.0f*c3);
    float J = -6.0f*c3;
    float B = V - 4.0f*P;
    float C = 0.5f * (A - 12.0f*P - 8.0f*B);
    float D = J - 24.0f*P - 36.0f*B;
    float c7 = (D - 24.0f*C) / 6.0f;
    float c6 = C - 3.0f*c7;
    float c5 = B - 2.0f*c6 - 3.0f*c7;
    float c4 = P - c5 - c6 - c7;
    float u = Clamp(t, 0.0f, 1.0f);
    return (((((((c7*u + c6)*u + c5)*u + c4)*u + c3)*u + c2)*u + c1)*u + c0);
}

static Vector3 trackSpline(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t,
                           bool useC2 = true) {
    if (useC2) {
        // One interpolation family owns x, y and z.  Blending Catmull into
        // plan view and switching to monotone Hermite only at vertical
        // extrema made each channel carry a different derivative at the same
        // control-point joint—the visible stitched roll/flat-block defect.
        return {septicC3(p0.x, p1.x, p2.x, p3.x, t),
                septicC3(p0.y, p1.y, p2.y, p3.y, t),
                septicC3(p0.z, p1.z, p2.z, p3.z, t)};
    }
    return catmull(p0, p1, p2, p3, t);
}
