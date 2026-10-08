#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// A soft diagonal highlight sweeping across the layer every few seconds. The
/// highlight scales with the sampled alpha, so gaps between items stay dark.
[[ stitchable ]] half4 shine(float2 position, SwiftUI::Layer layer, float2 size, float time) {
    half4 color = layer.sample(position);
    float diagonal = (position.x + position.y) / (size.x + size.y);
    float sweep = fract(time / 5.0) * 1.8 - 0.4;
    half band = half(smoothstep(0.1, 0.0, abs(diagonal - sweep)));
    return color + half4(half3(band * 0.35h) * color.a, 0.0h);
}

/// Wraps the layer around a reel drum: rows bunch up towards the top and
/// bottom edge the way a cylinder turns away from the viewer. `angle` is how
/// far the drum turns between the centre and the edge of the window.
[[ stitchable ]] float2 reelDrum(float2 position, float2 size, float angle) {
    float halfHeight = size.y * 0.5;
    float onScreen = clamp((position.y - halfHeight) / halfHeight, -1.0, 1.0);
    float theta = asin(onScreen * sin(angle));
    return float2(position.x, halfHeight + halfHeight * theta / sin(angle));
}

/// Smears the layer along y only, like a strip moving too fast to read.
[[ stitchable ]] half4 reelBlur(float2 position, SwiftUI::Layer layer, float amount) {
    half4 sum = 0.0h;
    for (int i = -4; i <= 4; i++) {
        sum += layer.sample(position + float2(0.0, amount * float(i) / 4.0));
    }
    return sum / 9.0h;
}
