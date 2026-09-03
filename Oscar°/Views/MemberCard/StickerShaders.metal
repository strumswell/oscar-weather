#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

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
