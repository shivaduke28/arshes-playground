uniform float3 touch;

struct State {
  float2 position;
  float radius;
}

[size(1)]
RWStructuredBuffer<State> state;

[dispatch(1,1,1)]
[numthreads(1,1,1)]
[shader("compute")]
void updateState(uint3 id : SV_DispatchThreadID) {
  var s = state[0];
  if (touch.z > 0) {
    s.position = lerp(s.position, float2(touch.x, touch.y), 0.08);
    s.radius = lerp(s.radius, 0.2, 0.05);
    state[0] = s;
  } else {
    s.radius = lerp(s.radius, 0, 0.1);
    state[0] = s;
  }
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
  var s = state[0];
  float3 col = 1;
  col *= step(s.radius, length(s.position - uv));
  return float4(col, 1);
}
