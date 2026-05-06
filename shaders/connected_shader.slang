// Long exposure camera simulation
// - Tap to start shooting, tap again to complete or wait for shutter speed
// - Tap on complete to return to idle
// - Toggle rearFlash for front/rear curtain sync
// - Adjust exposure to control accumulation brightness

import foundation;

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

[range(0.0, 50.0, 5.0)]
uniform float flashIntensity;

[toggle(false)]
uniform bool rearFlash;

[range(-1.0, 1.0, 0.0)]
uniform float temperature;

[range(-3.0, 3.0, 0.0)]
uniform float exposure;

[range(-1.0, 1.0, 0.0)]
uniform float contrast;

[range(-1.0, 1.0, 0.0)]
uniform float saturation;

[range(-1.0, 1.0, 0.0)]
uniform float highlights;

[range(-1.0, 1.0, 0.0)]
uniform float shadows;

[range(-1.0, 1.0, 0.0)]
uniform float whites;

[range(-1.0, 1.0, 0.0)]
uniform float blacks;

[rgb(0.5, 0.5, 0.5)]
uniform float3 shadowTint;

[rgb(0.5, 0.5, 0.5)]
uniform float3 midtoneTint;

[rgb(0.5, 0.5, 0.5)]
uniform float3 highlightTint;

[range(0, 1, 0)]
uniform float hueTarget;

[range(0, 0.5, 0.1)]
uniform float hueRange;

[range(0, 1, 0.5)]
uniform float sMin;

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

float3 toLinear(float3 c) { return pow(max(float3(0.0), c), 2.2); }
float3 toGamma(float3 c) { return pow(max(float3(0.0), c), 1.0 / 2.2); }

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 cam = toLinear(cameraTex.Sample(samp, uv));
    float4 prev = backbuffer.Sample(samp, uv);

    // color grading
    float3 graded = cam;

    // white balance (temperature)
    graded.r *= 1.0 + temperature * 0.5;
    graded.g *= 1.0 - abs(temperature) * 0.1;
    graded.b *= 1.0 - temperature * 0.5;

    // EV exposure
    graded *= pow(2.0, exposure);

    // convert to gamma space for tone adjustments
    graded = toGamma(graded);

    // blacks: lift the bottom end
    graded = graded + blacks * (1.0 - graded) * (1.0 - graded);

    // whites: push the top end
    graded = graded + whites * graded * graded;

    // shadows: affect dark regions
    float3 shadowMask = 1.0 - graded;
    shadowMask = shadowMask * shadowMask;
    graded = graded + shadows * shadowMask * 0.5;

    // highlights: affect bright regions
    float3 highlightMask = graded * graded;
    graded = graded + highlights * highlightMask * 0.5;

    // contrast: S-curve around mid-gray
    graded = (graded - 0.5) * (1.0 + contrast) + 0.5;

    // saturation
    float3 lum = dot(graded, float3(0.2126, 0.7152, 0.0722));
    graded = lerp(lum, graded, 1.0 + saturation);

    // color tinting by tonal range
    float lum2 = dot(graded, float3(0.2126, 0.7152, 0.0722));
    float shadowMask2 = 1.0 - smoothstep(0.0, 0.5, lum2);
    float highlightMask2 = smoothstep(0.5, 1.0, lum2);
    float midtoneMask = 1.0 - shadowMask2 - highlightMask2;

    float3 shadowShift = (shadowTint - 0.5) * 2.0;
    float3 midtoneShift = (midtoneTint - 0.5) * 2.0;
    float3 highlightShift = (highlightTint - 0.5) * 2.0;

    float3 tint = shadowShift * shadowMask2 + midtoneShift * midtoneMask + highlightShift * highlightMask2;
    graded += tint;

    graded = saturate(graded);

    // hue-based accumulation filter
    let hsv = rgb2hsv(graded);
    let saturationCoeff = (1.0 - smoothstep(0, hueRange, min(abs(hsv.r - hueTarget), abs(1.0 - hueTarget))))
        * smoothstep(sMin, sMin + 0.1, hsv.g);

    // back to linear for accumulation
    graded = toLinear(graded);

    // grain
    float noise = hash(uv * resolution + float2(time * 1000.0, 0.0)) * 2.0 - 1.0;
    graded += noise * grain;

    let s = state[0];

    switch (s.status) {
    case Status.Idle:
        float3 idle = graded * (saturationCoeff * shutterSpeed + flashIntensity * s.avgDeltaTime);
        return float4(toGamma(idle), 1.0);

    case Status.Flashing: {
        float3 base = rearFlash ? toLinear(prev.rgb) : float3(0.0);
        float3 acc = base + graded * flashIntensity * deltaTime;
        return float4(toGamma(acc), 1.0);
    }

    case Status.Shooting: {
        float elapsed = time - s.startTime;

        float3 base = (s.frameCount == 0 && rearFlash) ? float3(0.0) : toLinear(prev.rgb);
        float3 acc = base + graded * deltaTime * saturationCoeff;

        float3 result = toGamma(acc);

        float progress = saturate(elapsed / shutterSpeed);
        float barH = 0.006;
        if (uv.y > 1.0 - barH && uv.x < progress) {
            result = float3(1.0, 0.4, 0.2);
        }

        return float4(result, 1.0);
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
