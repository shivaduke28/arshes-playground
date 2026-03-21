// Long exposure camera simulation
// - Tap to start shooting, tap again to complete or wait for shutter speed
// - Tap on complete to return to idle
// - Toggle rearFlash for front/rear curtain sync
// - Adjust exposure to control accumulation brightness

uniform float time;
uniform float deltaTime;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform Texture2D<float4> backbuffer;
uniform SamplerState samp;
uniform float3 touch;

[range(0.5, 5.0, 2.0)]
uniform float shutterSpeed;

[range(0.1, 2.0, 0.5)]
uniform float exposure;

[range(0.0, 50.0, 5.0)]
uniform float flashIntensity;

[toggle(false)]
uniform bool rearFlash;

[range(0.0, 3.0, 1.0)]
uniform float contrast;

[range(0.0, 3.0, 1.0)]
uniform float saturation;

[range(0.0, 0.1, 0.025)]
uniform float borderWidth;

[range(0.0, 0.3, 0.05)]
uniform float grain;

enum Status {
    Idle = 0,
    Shooting = 1,
    Flashing = 2,
    Complete = 3
};

struct State {
    Status status;
    int frameCount;
    float startTime;
    float prevTouchZ;
    float avgDeltaTime;
};

[size(1)]
RWStructuredBuffer<State> state;

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void updateState(uint3 id : SV_DispatchThreadID) {
    State s = state[0];
    bool tap = touch.z > 0.5 && s.prevTouchZ < 0.5;
    s.prevTouchZ = touch.z;
    s.avgDeltaTime = lerp(s.avgDeltaTime, deltaTime, 0.1);

    switch (s.status) {
    case Status.Idle:
        if (tap) {
            if (rearFlash) {
                s.status = Status.Shooting;
                s.startTime = time;
            } else {
                s.status = Status.Flashing;
            }
            s.frameCount = 0;
        }
        break;
    case Status.Flashing:
        if (rearFlash) {
            s.status = Status.Complete;
        } else {
            s.status = Status.Shooting;
            s.startTime = time;
        }
        break;
    case Status.Shooting:
        s.frameCount = s.frameCount + 1;
        if (tap || time - s.startTime >= shutterSpeed) {
            if (rearFlash) {
                s.status = Status.Flashing;
            } else {
                s.status = Status.Complete;
            }
        }
        break;
    case Status.Complete:
        if (tap) {
            s.status = Status.Idle;
        }
        break;
    }
    state[0] = s;
}

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 cam = cameraTex.Sample(samp, uv);
    float4 prev = backbuffer.Sample(samp, uv);

    float noise = hash(uv * resolution + float2(time * 1000.0, 0.0)) * 2.0 - 1.0;

    // grading: contrast then saturation
    float3 graded = (cam - 0.5) * contrast + 0.5;
    float lum = dot(graded, float3(0.2126, 0.7152, 0.0722));
    graded = lerp(float3(lum), graded, saturation);
    graded += noise * grain;

    let s = state[0];

    switch (s.status) {
    case Status.Idle:
        return float4(graded * (exposure * shutterSpeed + (exposure + flashIntensity) * s.avgDeltaTime), 1.0);

    case Status.Flashing: {
        float3 base = rearFlash ? prev.rgb : float3(0.0);
        float3 acc = base + graded * (exposure + flashIntensity) * deltaTime;
        return float4(acc, 1.0);
    }

    case Status.Shooting: {
        float elapsed = time - s.startTime;

        float3 base = (s.frameCount == 0 && rearFlash) ? float3(0.0) : prev.rgb;
        float3 acc = base + graded * exposure * deltaTime;

        float progress = saturate(elapsed / shutterSpeed);
        float barH = 0.006;
        if (uv.y > 1.0 - barH && uv.x < progress) {
            acc = float3(1.0, 0.4, 0.2);
        }

        return float4(acc, 1.0);
    }

    case Status.Complete: {
        float3 result = prev.rgb;

        float bwX = borderWidth;
        float bwY = borderWidth * resolution.x / resolution.y;
        if (uv.x < bwX || uv.x > 1.0 - bwX || uv.y < bwY || uv.y > 1.0 - bwY) {
            result = float3(1.0);
        }

        return float4(result, 1.0);
    }

    default:
        return float4(cam, 1.0);
    }
}
