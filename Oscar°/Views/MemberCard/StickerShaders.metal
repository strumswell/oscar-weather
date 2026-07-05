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

struct StickerPeelGeometry {
    float2 origin;
    float2 size;
    float2 safeAnchor;
    float2 foldDirection;
    float2 foldTangent;
    float foldLine;
    float anchorProjection;
    float peelExtent;
    float progress;
};

static StickerPeelGeometry stickerPeelGeometry(float4 contentBounds, float2 anchor, float progress) {
    StickerPeelGeometry geometry;
    geometry.origin = contentBounds.xy;
    geometry.size = max(contentBounds.zw, float2(1.0));
    geometry.safeAnchor = clamp(anchor, geometry.origin, geometry.origin + geometry.size);
    geometry.progress = saturate(progress);

    const float2 anchorUV = (geometry.safeAnchor - geometry.origin) / geometry.size;
    geometry.foldDirection = normalize(anchorUV - float2(0.5) + float2(0.001));
    geometry.foldTangent = float2(-geometry.foldDirection.y, geometry.foldDirection.x);
    geometry.anchorProjection = dot(anchorUV - float2(0.5), geometry.foldDirection);

    const float peelTravel = max(geometry.anchorProjection * 0.48 * smoothstep(0.0, 1.0, geometry.progress), 0.001);
    geometry.foldLine = geometry.anchorProjection - peelTravel;
    geometry.peelExtent = max(peelTravel, 0.001);
    return geometry;
}

static bool stickerPeelInsideContent(float2 position, StickerPeelGeometry geometry) {
    return position.x >= geometry.origin.x && position.y >= geometry.origin.y &&
           position.x <= geometry.origin.x + geometry.size.x &&
           position.y <= geometry.origin.y + geometry.size.y;
}

[[ stitchable ]] half4 stickerPeelCutout(float2 position, SwiftUI::Layer layer, float4 bounds, float4 contentBounds, float2 anchor, float progress) {
    half4 original = layer.sample(position);
    const StickerPeelGeometry geometry = stickerPeelGeometry(contentBounds, anchor, progress);

    if (geometry.progress < 0.001 || !stickerPeelInsideContent(position, geometry) || original.a < 0.002h) {
        return original;
    }

    const float2 uv = (position - geometry.origin) / geometry.size;
    const float projection = dot(uv - float2(0.5), geometry.foldDirection);
    const float distFromFold = projection - geometry.foldLine;

    if (distFromFold <= 0.0) {
        const float shadowDistance = saturate(-distFromFold / max(geometry.peelExtent * 0.22, 0.001));
        const float foldShadow = (1.0 - shadowDistance) * geometry.progress * 0.08;
        return half4(half3(float3(original.rgb) * (1.0 - foldShadow)), original.a);
    }

    return half4(0.0h);
}

[[ stitchable ]] half4 stickerPeelBackside(float2 position, SwiftUI::Layer layer, float4 bounds, float4 contentBounds, float2 anchor, float progress) {
    const StickerPeelGeometry geometry = stickerPeelGeometry(contentBounds, anchor, progress);

    if (geometry.progress < 0.001 || !stickerPeelInsideContent(position, geometry)) {
        return half4(0.0h);
    }

    const float2 uv = (position - geometry.origin) / geometry.size;
    const float projection = dot(uv - float2(0.5), geometry.foldDirection);
    const float distFromFold = projection - geometry.foldLine;

    if (distFromFold >= 0.0) {
        return half4(0.0h);
    }

    const float foldedDepth = saturate((-distFromFold) / geometry.peelExtent);
    if (foldedDepth > 1.0) {
        return half4(0.0h);
    }

    const float reflectedProjection = geometry.foldLine - distFromFold;
    float2 reflectedUV = uv + geometry.foldDirection * (reflectedProjection - projection);

    const float curl = sin(foldedDepth * 3.1415927) * 0.032 * geometry.progress;
    reflectedUV += geometry.foldTangent * curl;

    const float2 samplePosition = geometry.origin + reflectedUV * geometry.size;
    if (!stickerPeelInsideContent(samplePosition, geometry)) {
        return half4(0.0h);
    }

    const half4 source = layer.sample(samplePosition);
    if (source.a < 0.02h) {
        return half4(0.0h);
    }

    const float edgeFade = smoothstep(0.0, 0.08, foldedDepth) * (1.0 - smoothstep(0.78, 1.0, foldedDepth));
    const float foldHighlight = (1.0 - smoothstep(0.0, 0.18, foldedDepth)) * 0.14;
    const float farTranslucency = mix(0.9, 0.38, foldedDepth);
    const float3 backsideColor = mix(float3(1.0), float3(0.86, 0.9, 0.94), foldedDepth * 0.62) + foldHighlight;
    const float alpha = float(source.a) * edgeFade * farTranslucency * geometry.progress;

    return half4(half3(saturate(backsideColor)), half(alpha));
}
