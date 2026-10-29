#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

static float memberCardHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float memberCardNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = memberCardHash(i);
    float b = memberCardHash(i + float2(1.0, 0.0));
    float c = memberCardHash(i + float2(0.0, 1.0));
    float d = memberCardHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float memberCardFbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * memberCardNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

[[ stitchable ]] half4 memberCardMaterial(float2 position, half4 color, float kind, float amount) {
    float grain = memberCardHash(floor(position * 2.0)) - 0.5;
    float detail = 0.0;
    if (kind > 0.5 && kind < 1.5) {
        detail = (memberCardNoise(float2(position.x * 0.015, position.y * 1.4)) - 0.5) * 1.1;
    } else if (kind > 1.5) {
        detail = (step(0.5, fract((position.x + position.y) / 3.5)) - 0.5) * 0.5;
    }
    float delta = (grain + detail) * amount;
    return half4(color.rgb + half3(delta) * color.a, color.a);
}

[[ stitchable ]] half4 memberCardInk(float2 position, SwiftUI::Layer layer, float seed, float scale) {
    float2 p = position / max(scale, 0.01);
    float2 wobble = float2(memberCardNoise(p * 0.9 + seed), memberCardNoise(p * 0.9 + seed + 17.0)) - 0.5;
    half4 ink = layer.sample(position + wobble * 0.7 * scale);
    float speck = saturate(memberCardFbm(p * 0.95 + seed * 3.1) * 3.6 - 0.55);
    float press = mix(0.6, 1.0, saturate(memberCardFbm(p * 0.05 + seed * 0.7) * 2.4 - 0.15));
    return ink * half(speck * press);
}

[[ stitchable ]] half4 memberCardPaper(float2 position, half4 color) {
    float grain = memberCardHash(floor(position * 3.0)) - 0.5;
    float tooth = memberCardFbm(position * 0.55) - 0.5;
    float cloud = memberCardFbm(position * 0.018 + 11.0) - 0.5;
    float delta = grain * 0.022 + tooth * 0.035 + cloud * 0.05;
    return half4(color.rgb + half3(delta) * color.a, color.a);
}
