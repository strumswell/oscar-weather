#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Fast single-pass atmosphere for Oscar's background. The hash/noise approach is
// adapted from the MIT-licensed shader reference in /shader by Felix Westin.

static float atmosphereSaturate(float value) {
    return clamp(value, 0.0, 1.0);
}

static float atmosphereSmoothstep(float edge0, float edge1, float value) {
    float x = atmosphereSaturate((value - edge0) / (edge1 - edge0));
    return x * x * (3.0 - 2.0 * x);
}

static float atmosphereHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float3 atmosphereMix3(float3 a, float3 b, float t) {
    return mix(a, b, atmosphereSaturate(t));
}

static float3 atmosphereBaseSky(float horizon, float sunElevation, float cloudDensity, float precipitation, float snow, float thunder, float haze) {
    float elevationDegrees = sunElevation * 57.2957795;
    float h = atmosphereSmoothstep(0.0, 1.0, horizon);

    float3 day = atmosphereMix3(float3(0.20, 0.48, 0.86), float3(0.68, 0.84, 0.95), h);
    float3 golden = atmosphereMix3(float3(0.38, 0.56, 0.84), float3(0.98, 0.66, 0.48), h * 0.92);
    float3 twilight = atmosphereMix3(float3(0.05, 0.08, 0.22), float3(0.18, 0.13, 0.34), h * 0.60);
    float3 night = atmosphereMix3(float3(0.022, 0.040, 0.095), float3(0.042, 0.052, 0.11), h);

    float3 color;
    if (elevationDegrees >= 6.0) {
        color = day;
    } else if (elevationDegrees >= 0.0) {
        color = atmosphereMix3(golden, day, atmosphereSmoothstep(0.0, 6.0, elevationDegrees));
    } else if (elevationDegrees >= -6.0) {
        color = atmosphereMix3(twilight, golden, atmosphereSmoothstep(-6.0, 0.0, elevationDegrees));
    } else {
        color = atmosphereMix3(night, twilight, atmosphereSmoothstep(-18.0, -6.0, elevationDegrees));
    }

    float gray = dot(color, float3(0.299, 0.587, 0.114));
    color = atmosphereMix3(color, float3(gray), cloudDensity * 0.38 + haze * 0.22);
    color *= 1.0 - precipitation * 0.36 - thunder * 0.30;
    color += float3(0.02, 0.025, 0.035) * haze;
    color = atmosphereMix3(color, float3(0.72, 0.78, 0.84), snow * 0.18);

    return clamp(color, 0.0, 1.0);
}

[[ stitchable ]] half4 atmosphereSky(
    float2 position,
    float2 size,
    float time,
    float sunElevation,
    float phase,
    float cloudDensity,
    float precipitation,
    float snow,
    float thunder,
    float haze,
    float turbidity
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float horizon = atmosphereSaturate(uv.y);
    float3 color = atmosphereBaseSky(horizon, sunElevation, cloudDensity, precipitation, snow, thunder, haze);

    float horizonGlow = exp(-abs(horizon - 0.78) * 6.0) * (0.08 + turbidity * 0.12) * phase;
    color += float3(1.0, 0.62, 0.42) * horizonGlow;

    float dither = atmosphereHash(position + float2(time * 31.0, time * 17.0)) / 255.0;
    color += dither;
    return half4(half3(clamp(color, 0.0, 1.0)), 1.0h);
}
