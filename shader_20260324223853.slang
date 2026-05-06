uniform var time : float;
uniform var cameraTex : Texture2D<float4>;
uniform var backbuffer : Texture2D<float4>;
uniform var sampler : SamplerState;

[size(2)]
RWStructuredBuffer<float2> PositionBuffer;

struct VertexInput
{
    uint vid : SV_VertexID;
    uint iid : SV_InstanceID;
}

struct VertexOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
}

static const var QuadPositions = Array<float2, 4>(
    float2(-1.0, 1.0),
    float2(1.0, 1.0),
    float2(-1.0, -1.0),
    float2(1.0, -1.0));
static const var QuadUVs = Array<float2, 4>(
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0));

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
func computePosition()
{
    PositionBuffer[0] = float2(0.5, 0.5);
    PositionBuffer[1] = float2(-0.5, -0.5);
}

[primitive(4, 2)]
[shader("vertex")]
func vertexMain(uint vid: SV_VertexID, uint iid: SV_InstanceID)->VertexOutput
{
    // 以下の行のようにRWStructuredBufferとUniformの値の両方を
    // vertex shader内で同時に使い、
    // かつfragment shaderでもuniformにアクセスすると
    // コンパイルエラーになる
    let pos = PositionBuffer[iid] * frac(time);

    // 以下のどちらかの行ではエラーにならない
    // let pos = PositionBuffer[iid];
    // let pos = float2(frac(time));

    let v = QuadPositions[vid] * 0.5;

    var vout : VertexOutput;
    vout.position = float4(v + pos, 0.0, 1.0);
    vout.uv = QuadUVs[vid];

    return vout;
}

[shader("fragment")]
func fragmentMain(vout: VertexOutput)->float4
{
    return cameraTex.Sample(sampler, vout.uv);

    // fragment shaderを以下に置き換えれば
    // vertex shader内でRWStructuredBufferとUniformの両方を使っても
    // エラーにならない
    // return float4(vout.uv, 0.0, 1.0);
}
