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

// Two-tap value noise for slow overcast mottling.
static float atmosphereValueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = atmosphereHash(i);
    float b = atmosphereHash(i + float2(1.0, 0.0));
    float c = atmosphereHash(i + float2(0.0, 1.0));
    float d = atmosphereHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float3 atmosphereMix3(float3 a, float3 b, float t) {
    return mix(a, b, atmosphereSaturate(t));
}

// Approximate sRGB <-> linear so palette blends stay clean in the mid-band
// instead of going muddy.
static float3 atmosphereToLinear(float3 c) {
    return c * c;
}

static float3 atmosphereToDisplay(float3 c) {
    return sqrt(max(c, float3(0.0)));
}

static float3 atmosphereBaseSky(float horizon, float sunElevation, float cloudDensity, float precipitation, float snow, float thunder, float haze, float moonGlow) {
    float elevationDegrees = sunElevation * 57.2957795;
    float h = atmosphereSmoothstep(0.0, 1.0, horizon);

    // Palette endpoints are authored in sRGB; blend them in linear space.
    float3 day = atmosphereMix3(atmosphereToLinear(float3(0.20, 0.48, 0.86)), atmosphereToLinear(float3(0.68, 0.84, 0.95)), h);
    float3 golden = atmosphereMix3(atmosphereToLinear(float3(0.38, 0.56, 0.84)), atmosphereToLinear(float3(0.98, 0.66, 0.48)), h * 0.92);
    float3 twilight = atmosphereMix3(atmosphereToLinear(float3(0.05, 0.08, 0.22)), atmosphereToLinear(float3(0.30, 0.17, 0.33)), h * 0.60);
    float3 night = atmosphereMix3(atmosphereToLinear(float3(0.022, 0.040, 0.095)), atmosphereToLinear(float3(0.042, 0.052, 0.11)), h);

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

    color = atmosphereToDisplay(color);

    // Weather post-ops, unchanged from the original sRGB tuning.
    float gray = dot(color, float3(0.299, 0.587, 0.114));
    color = atmosphereMix3(color, float3(gray), cloudDensity * 0.38 + haze * 0.22);
    color *= 1.0 - precipitation * 0.36 - thunder * 0.30;
    color += float3(0.02, 0.025, 0.035) * haze;
    color = atmosphereMix3(color, float3(0.72, 0.78, 0.84), snow * 0.18);

    // A bright moon lifts a clear night sky toward blue-grey.
    float nightFactor = 1.0 - atmosphereSmoothstep(-12.0, -6.0, elevationDegrees);
    color += float3(0.012, 0.016, 0.032) * (moonGlow * nightFactor);

    return clamp(color, 0.0, 1.0);
}

[[ stitchable ]] half4 atmosphereSky(
    float2 position,
    float2 size,
    float time,
    float sunElevation,
    float cloudDensity,
    float precipitation,
    float snow,
    float thunder,
    float haze,
    float turbidity,
    float sunX,
    float moonGlow
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float horizon = atmosphereSaturate(uv.y);
    float3 color = atmosphereBaseSky(horizon, sunElevation, cloudDensity, precipitation, snow, thunder, haze, moonGlow);

    float elevationDegrees = sunElevation * 57.2957795;

    // Warm horizon band tied to the sun's proximity to the horizon:
    // builds through golden hour, peaks at sunset, lingers as afterglow
    // until ~-10°, and is absent at midday and through the night.
    float sunsetBand = atmosphereSmoothstep(-10.0, -2.0, elevationDegrees)
        * (1.0 - atmosphereSmoothstep(6.0, 16.0, elevationDegrees));
    float horizonBand = exp(-abs(horizon - 0.78) * 6.0);

    // The glow concentrates around the sun's screen azimuth (same mapping
    // as SunView), with a cool rose afterglow on the anti-solar side.
    float dx = uv.x - sunX;
    float lobe = exp(-dx * dx * 6.0);
    float horizonGlow = horizonBand * (0.10 + turbidity * 0.14) * sunsetBand;
    color += float3(1.0, 0.62, 0.42) * horizonGlow * (0.35 + 0.65 * lobe);
    color += float3(0.42, 0.26, 0.38) * horizonBand * sunsetBand * 0.07 * (1.0 - lobe);

    // Subtle circumsolar brightening so clear daytime skies aren't a flat
    // ramp. Anchored where SunView draws the sun (y ≈ 0.08 of the screen).
    float dayBand = atmosphereSmoothstep(6.0, 18.0, elevationDegrees);
    float2 sunDelta = float2(uv.x - sunX, (uv.y - 0.08) * (safeSize.y / safeSize.x));
    float circumsolar = exp(-dot(sunDelta, sunDelta) * 7.0);
    color += float3(0.16, 0.15, 0.11) * circumsolar * dayBand
        * (0.55 + 0.45 * turbidity) * (1.0 - cloudDensity * 0.85);

    // Slow large-scale mottling so overcast skies aren't a flat ramp.
    float2 noiseUV = uv * float2(3.0, 2.2);
    float mottle = atmosphereValueNoise(noiseUV + float2(time * 0.010, 0.0)) * 0.65
        + atmosphereValueNoise(noiseUV * 2.1 - float2(time * 0.016, time * 0.005)) * 0.35;
    color *= 1.0 + (mottle - 0.5) * 0.085 * cloudDensity;

    // Lightning: brief hash-triggered flashes, brighter toward the zenith.
    // Only animates while a storm timeline drives `time`.
    float bucket = floor(time * 3.0);
    float strike = step(0.965, atmosphereHash(float2(bucket, 17.0)));
    float decay = 1.0 - fract(time * 3.0);
    float flash = strike * decay * decay * thunder;
    color += float3(0.85, 0.90, 1.0) * flash * (0.30 + 0.40 * (1.0 - horizon));

    float dither = atmosphereHash(position + float2(time * 31.0, time * 17.0)) / 255.0;
    color += dither;
    return half4(half3(clamp(color, 0.0, 1.0)), 1.0h);
}
