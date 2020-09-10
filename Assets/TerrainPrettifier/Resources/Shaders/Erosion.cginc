#ifndef TERRAIN_PROCESSOR_EROSION_INCLUDED
#define TERRAIN_PROCESSOR_EROSION_INCLUDED

#define M_PI 3.14159265358979

float2 Hash (float2 x)
{
    float2 k = float2( 0.3183099, 0.3678794 );
    x = x * k + k.yx;
    return -1.0 + 2.0 * frac( 16.0 * k * frac( x.x*x.y*(x.x+x.y)) );
}

float2 Hash2 (float2 p)
{
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
	return frac(sin(p) * 43758.5453);
}

float3 Erosion (float2 p, float2 dir)
{
	float2 ip 	= floor(p);
	float2 fp 	= frac(p);
	float  f 	= 2 * M_PI;
	float3 va 	= 0;
	float  wt 	= 0;

	for (int i = -2; i <= 1; i++)
	{
		for (int j = -2; j <= 1; j++)
		{
			float2 o = float2(i, j);
			float2 h = Hash((ip - o) * 0.5) * 0.5;
			float2 pp = fp + o - h;
			float d = dot(pp, pp);
			float w = exp(-d * 2.0);
			wt += w;
			float mag = dot(pp, dir);
			va += float3(cos(mag * f), -sin(mag * f) * (pp + dir)) * w;
		}
	}

	return va / wt;
}

float ErosionFBM (float3 worldPos, float3 normal, float a, int o, float f)
{
	float2 dir = normal.zy * float2(1.0, -1.0);
	dir = normal.zx * float2(1, -1);

	float3 h = 0;
	// float a = 0.7 * (smoothstep(0.3, 0.5, normal.y * 0.5 + 0.5)); //smooth the valleys
	// float a = 1;// - normal.y;
	// float f = 0.001;
	for (int i = 0; i < o; i++)
	{
		h += Erosion(worldPos.xz * f, dir + h.zy * float2(1, -1)) * a * float3(1.0, f, f);
		a *= 0.4;
		f *= 2.0;
	}

	return h.x;
}

#endif // TERRAIN_PROCESSOR_EROSION_INCLUDED