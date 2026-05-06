uniform float time;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform Texture2D<float> depthTex;
uniform SamplerState sampler;

[range(0.0, 1.0, 0.5)]
uniform float t;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
 float3 rgb=cameraTex.Sample(sampler,uv);
 float d=depthTex.Sample(sampler,uv);
 d=isnan(d)?0:d;
 rgb=lerp(float3(1),rgb,exp(-d));
 return float4(uv.x < t ? rgb : float3(d),1);
}