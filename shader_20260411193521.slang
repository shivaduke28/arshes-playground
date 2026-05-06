uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
 float3 rgb=cameraTex.Sample(sampler,uv);
 rgb=pow(rgb,float3(7.0/5,1,8.0/5));
 return float4(rgb,1);
}