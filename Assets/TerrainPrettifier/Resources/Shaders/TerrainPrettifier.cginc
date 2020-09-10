#ifndef TERRAIN_PRETTIFIER_INCLUDED
#define TERRAIN_PRETTIFIER_INCLUDED

#define NULL_HEIGHT -9999

float3		_TerrainCenter;
float3		_TerrainSize;

sampler2D	_Heightmap;
float4		_HeightmapBounds;
float4		_HeightmapTexelSize;
float4		_HeightmapPixelSize;
float4		_HeightBounds;
float4		_HeightmapScaleOffset;

sampler2D	_BlueNoise64;
half		_TerrainMarcherSampleCount;
half		_TerrainMarcherMaxDist;
half		_TerrainMarcherMinStep;
half		_TerrainMarcherMaxSlope;

float GetNoise (float2 screenUV)
{
	float2 uv = screenUV * _ScreenParams.xy / 64;
	return tex2Dlod(_BlueNoise64, float4(uv, 0, 0));
}

float2 BoxIntersection (float3 RO, float3 RD, float3 C, float3 S)
{
	float tmin, tmax;
	float3 bounds[2] = { C - S * 0.5, C + S * 0.5 };

	float3 orig = RO;
	float3 dir = RD;
	float3 invdir = 1 / dir;

	bool sgn[3] = { invdir.x < 0, invdir.y < 0, invdir.z < 0 };

	float tymin, tymax, tzmin, tzmax; 

	tmin =  (bounds[sgn[0]].x   - orig.x) * invdir.x; 
	tmax =  (bounds[1-sgn[0]].x - orig.x) * invdir.x; 
	tymin = (bounds[sgn[1]].y   - orig.y) * invdir.y; 
	tymax = (bounds[1-sgn[1]].y - orig.y) * invdir.y; 

	if ((tmin > tymax) || (tymin > tmax)) 
		return -1;
	if (tymin > tmin) 
		tmin = tymin; 
	if (tymax < tmax) 
		tmax = tymax; 

	tzmin = (bounds[sgn[2]].z   - orig.z) * invdir.z; 
	tzmax = (bounds[1-sgn[2]].z - orig.z) * invdir.z; 

	if ((tmin > tzmax) || (tzmin > tmax)) 
		return -1;
	if (tzmin > tmin) 
		tmin = tzmin; 
	if (tzmax < tmax) 
		tmax = tzmax;

	if (tmax < 0)
		return -1;

	return float2(tmin, tmax);
}

float GetTerrainHeight (sampler2D heightMap, float2 uv, float4 texelSize, float2 scaleOffset)
{	
	uv *= float2((texelSize.z-1) / texelSize.z, (texelSize.w-1) / texelSize.w);
	uv += texelSize.xy * 0.5;

	// if (abs(uv.x-0.5) > 0.5 || abs(uv.y - 0.5) > 0.5)
	// 	return NULL_HEIGHT;

	float height = tex2Dlod(heightMap, float4(uv.xy, 0, 0)).r * scaleOffset.x * 2 + scaleOffset.y;

	return height;
}

float2 GetTerrainUV (float2 worldPosXZ)
{
	return (worldPosXZ - _HeightmapBounds.xy) * _HeightmapBounds.zw;
}

float2 GetTerrainUV (float3 worldPos)
{
	return GetTerrainUV(worldPos.xz);
}

float GetTerrainHeight (float2 worldPosXZ)
{
	float2 uv = GetTerrainUV(worldPosXZ);
	// if (abs(uv.x-0.5) > 0.5 || abs(uv.y-0.5) > 0.5)
	// 	return 0;
	// else
	return GetTerrainHeight(_Heightmap, uv, _HeightmapPixelSize, _HeightmapScaleOffset);
}

float GetTerrainHeight (float x, float z)
{
	return GetTerrainHeight(float2(x, z));
}

float GetTerrainHeight (float3 worldPos)
{
	return GetTerrainHeight(worldPos.xz);
}

float3 GetTerrainNormal (float3 p, float3 width = 1)
{
	float eps = _HeightmapTexelSize.z * width;
	return normalize(float3(GetTerrainHeight(p.x - eps, p.z) - GetTerrainHeight(p.x + eps, p.z),
							2.0f * eps,
							GetTerrainHeight(p.x, p.z - eps) - GetTerrainHeight(p.x, p.z + eps)));
}

float GetTerrainOcclusion (float3 rayStart, float3 rayDir, float k = 10, float noise = 0)
{
	float s = 1.0;
	float h_prev = 1e20;

	float t = _HeightmapTexelSize.x; // Offset ray by a full heightmap texel to prevent self-intersection
	t += _TerrainMarcherMinStep * noise;

	[loop]
	for (int i = 0; i < _TerrainMarcherSampleCount; i++)
	{
		float3 p = rayStart + rayDir * t;

		[branch]
		if (p.y > _HeightBounds.y)
			break;

		float height = GetTerrainHeight(p);

		// Map
		float h = p.y - height;

		[branch]
		if (h < 0.001)
		{
			s = 0;
			t = 0;
			break;
		}

#ifdef BANDING_FIX
		// https://iquilezles.org/www/articles/rmshadows/rmshadows.htm
		float y = h*h / (h_prev * 2);
		float d = sqrt(h*h - y*y);
		s = min(s, k * d / max(t - y, 0));
#else
		s = min(s, k * h / t);
#endif
		h_prev = h;

		t += max(h * _TerrainMarcherMaxSlope, _TerrainMarcherMinStep);

		if (t > _TerrainMarcherMaxDist)
			break;
	}

    return max(s, 0);
}

float GetTerrainDistance (float3 rayStart, float3 rayDir, float noise = 0)
{
	float s = 1.0;
	float h_prev = 1e20;

	float k = 10000;

	float t = _HeightmapTexelSize.x; // Offset ray by a full heightmap texel to prevent self-intersection
	t += _TerrainMarcherMinStep * noise;

	[loop]
	for (int i = 0; i < _TerrainMarcherSampleCount; i++)
	{
		float3 p = rayStart + rayDir * t;

		[branch]
		if (rayDir.y > 0 && p.y > _HeightBounds.y)
			break;

		float height = GetTerrainHeight(p);

		// if (height == NULL_HEIGHT)
		// 	return 1.0 / 0.0;

		// Map
		float h = p.y - height;

		[branch]
		if (h < 0.001)
		{
			return t;
			// s = 0;
			// t = 0;
			// break;
		}

#ifdef BANDING_FIX
		// https://iquilezles.org/www/articles/rmshadows/rmshadows.htm
		float y = h*h / (h_prev * 2);
		float d = sqrt(h*h - y*y);
		s = min(s, k * d / max(t - y, 0));
#else
		s = min(s, k * h / t);
#endif
		if (s < 0.5)
			return t;

		h_prev = h;

		t += max(h * _TerrainMarcherMaxSlope, _TerrainMarcherMinStep);

		if (t > _TerrainMarcherMaxDist)
			break;
	}

    return 1.0 / 0.0;
}

float ComputeTerrainCavity (float3 worldPos, float width = 1)
{
	float h0 = GetTerrainHeight(worldPos);
	float h1 = GetTerrainHeight(worldPos + float3(1, 0, 0) * _HeightmapTexelSize.z * width);
	float h2 = GetTerrainHeight(worldPos - float3(1, 0, 0) * _HeightmapTexelSize.z * width);
	float h3 = GetTerrainHeight(worldPos + float3(0, 0, 1) * _HeightmapTexelSize.w * width);
	float h4 = GetTerrainHeight(worldPos - float3(0, 0, 1) * _HeightmapTexelSize.w * width);

	float sum = 0;
	sum += h0 - h1;
	sum += h0 - h2;
	sum += h0 - h3;
	sum += h0 - h4;

	return sum / (_HeightmapTexelSize.z * width);
}

float ComputeCavity (sampler2D heightmap, float2 uv, float4 texelSize)
{
	int width = 3;
	int span = (width-1) / 2;

	float h0 = tex2D(heightmap, uv).r;
	float sum = 0;
	for (int x = -span; x <= span; x++)
	{
		for (int y = -span; y <= span; y++)
		{
			float2 offset = float2(x, y) * texelSize.xy;
			sum += h0 - tex2D(heightmap, uv + offset).r;
		}
	}
	sum /= (width*width);
	return sum;
}

#endif // TERRAIN_PRETTIFIER_INCLUDED