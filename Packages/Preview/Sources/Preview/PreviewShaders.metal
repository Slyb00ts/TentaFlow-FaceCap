// =============================================================================
// Plik: PreviewShaders.metal
// Opis: Shadery vertex + fragment dla podglądu avatara (Gouraud + eye_sphere).
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float3 worldPos;
};

// ---------------------------------------------------------------------------
// Vertex
// ---------------------------------------------------------------------------

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                              constant float4x4& mvp [[buffer(1)]],
                              constant float4x4& model [[buffer(2)]]) {
    VertexOut out;
    out.position = mvp * float4(in.position, 1.0);
    out.worldPos = (model * float4(in.position, 1.0)).xyz;
    // Normal transform: zakładamy jednorodne skalowanie – model3x3 wystarczy.
    out.normal = normalize((model * float4(in.normal, 0.0)).xyz);
    out.uv = in.uv;
    return out;
}

// ---------------------------------------------------------------------------
// Fragment: Gouraud (pojedyncze światło kierunkowe + ambient 0.2)
// ---------------------------------------------------------------------------

fragment float4 fragment_gouraud(VertexOut in [[stage_in]],
                                  texture2d<float> albedo [[texture(0)]],
                                  sampler s [[sampler(0)]],
                                  constant float3& lightDir [[buffer(0)]]) {
    float ndotl = max(dot(in.normal, -normalize(lightDir)), 0.0);
    float3 tex = albedo.sample(s, in.uv).rgb;
    float3 col = tex * (0.2 + 0.8 * ndotl);
    return float4(col, 1.0);
}

// ---------------------------------------------------------------------------
// Fragment: eye sphere (sklera biała, iris kolorowa, specular highlight)
// ---------------------------------------------------------------------------

fragment float4 fragment_eye(VertexOut in [[stage_in]],
                              constant float3& lightDir [[buffer(0)]],
                              constant float3& irisColor [[buffer(1)]]) {
    float ndotl = max(dot(in.normal, -normalize(lightDir)), 0.0);
    float3 viewDir = normalize(float3(0.0, 0.0, 1.0));
    float3 reflectDir = reflect(normalize(lightDir), in.normal);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
    // UV 0..1 – środek (0.5,0.5). Iris to krążek w obrębie radius.
    float distFromCenter = length(in.uv - float2(0.5));
    float3 base = mix(irisColor, float3(1.0), smoothstep(0.15, 0.25, distFromCenter));
    float3 col = base * (0.3 + 0.7 * ndotl) + float3(spec);
    return float4(col, 1.0);
}

// ---------------------------------------------------------------------------
// Fragment: flat color (dla meshy bez tekstury: teeth / mouth_cavity / tongue)
// ---------------------------------------------------------------------------

fragment float4 fragment_flat(VertexOut in [[stage_in]],
                               constant float3& lightDir [[buffer(0)]],
                               constant float3& baseColor [[buffer(1)]]) {
    float ndotl = max(dot(in.normal, -normalize(lightDir)), 0.0);
    float3 col = baseColor * (0.2 + 0.8 * ndotl);
    return float4(col, 1.0);
}
