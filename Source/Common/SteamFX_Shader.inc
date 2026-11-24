'''
struct Puff
{
    float4 bounds;
    float4 axes;
    float4 density;
    float4 turbulence;
};

cbuffer SteamFrame : register(b0)
{
    float4 region;
    float4 tint; // RGB and padding
    float4 appearance;
    Puff puffs[96];
};

uint mixBits(uint x)
{
    x = (x ^ (x >> 16)) * 0x7FEB352D;
    x = (x ^ (x >> 15)) * 0x846CA68B;
    return x ^ (x >> 16);
}

float lattice(int2 p)
{
    uint value = mixBits((uint)p.x * 0x9E3779B9 ^ (uint)p.y * 0x85EBCA6B);
    return (value & 0xFFFF) * (1.0 / 65535.0);
}

float noiseField(float2 p)
{
    int2 cell = (int2)floor(p);
    float2 f = frac(p);
    f = f * f * (3 - 2 * f);
    float a = lerp(lattice(cell), lattice(cell + int2(1, 0)), f.x);
    float b = lerp(lattice(cell + int2(0, 1)), lattice(cell + int2(1, 1)), f.x);
    return lerp(a, b, f.y);
}

float2 evaluatePuff(Puff puff, float2 position)
{
    float2 delta = position - puff.bounds.xy;
    [branch] if (any(abs(delta) > puff.bounds.zw)) return 0;
    float2 q = float2(dot(delta, puff.axes.xy), dot(delta, puff.axes.zw));
    float warp = puff.turbulence.x;
    float vortex = puff.turbulence.y;
    [branch] if (any(abs(q) > 1.1 + warp + vortex * 0.4)) return 0;
    float2 npos = q * float2(2.08, 1.58) + float2(puff.density.y, -puff.density.z * 0.78);
    float n = noiseField(npos) - 0.5;
    float m = noiseField(npos * float2(1, 1.26) + float2(19.37, 8.52)) - 0.5;
    float curl = vortex * (m + n * 0.46);
    q.x += n * warp + curl * q.y * 0.48;
    q.y += m * warp - curl * q.x * 0.48;
    float radial = dot(q, q);
    [branch] if (radial >= 1) return 0;
    float edge = 1 - radial;
    edge = edge * edge * (1 + radial * (1 - appearance.y));
    float textureNoise = noiseField((npos + float2(n * 0.82, m)) *
        float2(appearance.x, appearance.x * 0.77));
    float filament = smoothstep(0, 1, 0.34 + n * 0.94 + m * 0.46 + textureNoise * 0.61);
    float depth = puff.density.x * edge * (0.18 + 0.82 * filament) *
        (1 - puff.turbulence.z * 0.25 + puff.turbulence.z * 0.45 * textureNoise);
    float light = puff.density.w * (1 - appearance.z * (1 - filament) * 0.66);
    return float2(depth, depth * light);
}

float4 SteamPixel(float4 pos : SV_Position) : SV_Target
{
    [branch] if (any(pos.xy < region.xy) || any(pos.xy > region.zw)) return 0;
    float2 sum = 0;
    [loop] for (uint i = 0; i < (uint)appearance.w; ++i)
        sum += evaluatePuff(puffs[i], pos.xy);
    [branch] if (sum.x <= 0.001) return 0;
    float alpha = 0.94 * (1 - exp(-sum.x));
    return float4(tint.rgb * (sum.y / sum.x) * alpha, alpha);
}
'''
