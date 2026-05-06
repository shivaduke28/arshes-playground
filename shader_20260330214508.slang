uniform float time;
uniform float2 resolution;
uniform int frame;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

static const int W = 64;
static const int H = 64;
static const float period = 1.0;

struct State {
  float3 color;
  float x;
  float y;
}

[range(0, 1, 0.1)]
uniform float scaleByLuminance;

[size(W * H)]
RWStructuredBuffer<State> buffer;

[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
void computeMain(uint3 id : SV_DispatchThreadID) {
  uint idx = id.y * W + id.x;
    let uv = float2(id.x / float(W), id.y / float(H));
    let color = cameraTex.SampleLevel(samp, uv, 0);
    var state = buffer[idx];
    state.color = color;
    if (frame == 0) {
    state.x = id.x / float(W);
    state.y = 1 - id.y / float(H);
  } else {
    state.x += 0.001 * sin(time + idx);
    state.y += 0.001 * cos(time + idx);
  }
  buffer[idx] = state;
}

static const var QuadPositions = Array<float2, 4>(
    float2(-1.0, 1.0),
    float2(1.0, 1.0),
    float2(-1.0, -1.0),
    float2(1.0, -1.0));

struct VertexOut {
  float4 position : SV_Position;
  float3 color : COLOR;
};

float2 rot(float2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float luminance(float3 c) {
  return dot(c, float3(0.299, 0.587, 0.114));
}

[primitive(4, W * H)]
[shader("vertex")]
VertexOut vertexMain(uint id : SV_VertexID, uint iid : SV_InstanceID) {
  VertexOut v;
  uint idx = iid;  
  let state = buffer[idx];
  let color = state.color;
  var posOS = QuadPositions[id] * 0.9 / float(W);
  var l = saturate(luminance(color));
  posOS *= 1 - scaleByLuminance + scaleByLuminance * l;
  posOS = rot(posOS, time * 4 + idx);
  var pos = posOS + float2(state.x, state.y) * 2. - 1.;
  v.position = float4(pos.x, pos.y, 0, 1);
  v.color = state.color;
  return v;
}

[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target {
  return float4(input.color, 1);
}