uniform float time;
uniform float2 resolution;



[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
  return float4(uv,0,1);
}