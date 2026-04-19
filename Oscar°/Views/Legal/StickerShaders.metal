#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

[[ stitchable ]] half4 stickerPlasticSheen(float2 position, SwiftUI::Layer layer, float4 bounds) {
    const float2 size = max(bounds.zw, float2(1.0));
    const float2 uv = position / size;

    half4 color = layer.sample(position);
    if (color.a <= 0.001h) {
        return color;
    }

    const float diagonal = saturate(1.0 - abs((uv.x * 0.92 + uv.y * 1.08) - 0.74) * 3.1);
    const float narrowSpecular = pow(diagonal, 4.2) * 0.28;
    const float hotspot = pow(saturate(1.0 - distance(uv, float2(0.33, 0.23)) * 2.35), 6.0) * 0.14;

    const float edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    const float rim = pow(saturate(1.0 - (edgeDistance * 4.7)), 1.55) * 0.12;
    const float faceShade = (smoothstep(0.08, 0.95, uv.y) * 0.06) + (smoothstep(0.0, 1.0, uv.x) * 0.03);
    const float depth = pow(saturate(1.0 - edgeDistance * 3.2), 2.2) * 0.06;
    const float alpha = float(color.a);

    float3 rgb = float3(color.rgb);
    rgb *= (1.0 - faceShade);
    rgb *= (1.0 - depth);
    rgb += (narrowSpecular + hotspot) * 0.95;
    rgb += rim;

    return half4(half3(saturate(rgb)), color.a * half(alpha));
}

[[ stitchable ]] float2 stickerPeelLift(float2 position, float4 bounds, float4 contentBounds, float2 anchor, float progress) {
    const float2 contentOrigin = contentBounds.xy;
    const float2 contentSize = max(contentBounds.zw, float2(1.0));
    const float clampedProgress = saturate(progress);
    const float2 safeAnchor = clamp(anchor, contentOrigin, contentOrigin + contentSize);

    if (position.x < contentOrigin.x || position.y < contentOrigin.y ||
        position.x > contentOrigin.x + contentSize.x || position.y > contentOrigin.y + contentSize.y) {
        return position;
    }

    const float2 windowSize = max(contentSize * 0.34, float2(18.0));
    const float2 windowOrigin = max(contentOrigin, safeAnchor - windowSize);
    const float2 local = (position - windowOrigin) / windowSize;
    const float cornerX = saturate(local.x);
    const float cornerY = saturate(local.y);
    const float insideWindow = step(windowOrigin.x, position.x) * step(windowOrigin.y, position.y);
    const float peelMask = insideWindow * pow(cornerX * cornerY, 1.3);
    const float curvature = sin(peelMask * 1.5707964);
    const float distanceFade = saturate(1.0 - (distance(position, safeAnchor) / length(windowSize)));
    const float influence = curvature * distanceFade;
    const float liftAmount = 13.0 * clampedProgress;
    const float horizontalCurl = 9.0 * clampedProgress;

    float2 displaced = position;
    displaced.y -= influence * liftAmount;
    displaced.x -= influence * horizontalCurl;
    return displaced;
}
