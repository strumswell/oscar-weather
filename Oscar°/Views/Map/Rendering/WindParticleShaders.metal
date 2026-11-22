#include <metal_stdlib>
using namespace metal;

struct WindParams {
    float4 color;
    float2 viewportPixels;
    float halfWidth;
    float depth;
    float decay;
    float samplePhase;
    float tailLength;
};

struct WindVOut {
    float4 position [[position]];
    float alpha;
    float across;
};

vertex WindVOut wind_particle_vs(uint vid [[vertex_id]],
                                 uint iid [[instance_id]],
                                 const device float2* points [[buffer(0)]],
                                 const device float* alphas [[buffer(1)]],
                                 constant WindParams& p [[buffer(2)]]) {
    int count = int(p.tailLength) + 1;
    int i = int(vid / 2);
    float side = (vid & 1) ? 1.0 : -1.0;
    const device float2* tail = points + iid * uint(count);
    float2 halfViewport = p.viewportPixels * 0.5;
    float2 here = tail[i] * halfViewport;
    float2 dir = (tail[min(i + 1, count - 1)] - tail[max(i - 1, 0)]) * halfViewport;
    float len = length(dir);
    float2 normal = len > 1e-3 ? float2(-dir.y, dir.x) / len : float2(0.0);
    float age = i == 0 ? 0.0 : float(i - 1) + p.samplePhase;
    float fade = pow(p.decay, age) * saturate((p.tailLength - age) / 8.0);

    WindVOut out;
    out.position = float4((here + normal * side * p.halfWidth) / halfViewport, p.depth, 1.0);
    out.alpha = alphas[iid] * fade;
    out.across = side * p.halfWidth;
    return out;
}

fragment half4 wind_particle_fs(WindVOut in [[stage_in]],
                                constant WindParams& p [[buffer(0)]]) {
    float a = p.color.a * in.alpha * saturate(p.halfWidth - abs(in.across));
    return half4(half3(p.color.rgb * a), half(a));
}
