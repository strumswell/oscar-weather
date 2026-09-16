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
