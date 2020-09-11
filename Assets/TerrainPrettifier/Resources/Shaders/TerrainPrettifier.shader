Shader "TerrainPrettifier/Processor"
{
	SubShader
	{
		Cull Off
		ZWrite Off
		ZTest Always

		CGINCLUDE
		#include "UnityCG.cginc"
		#include "UnityLightingCommon.cginc"
		#include "TerrainPrettifier.cginc"
		#include "Erosion.cginc"
		#include "ShadowRemoval.cginc"

		struct v2f
		{
			float4 vertex 		: SV_POSITION;
			float2 texcoord		: TEXCOORD0;
		};

		sampler2D 	_MainTex;
		float4		_MainTex_TexelSize;

		v2f vert (appdata_full v)
		{
			v2f o;
			UNITY_INITIALIZE_OUTPUT(v2f, o);

			o.vertex 	= UnityObjectToClipPos(v.vertex);
			o.texcoord 	= v.texcoord;

			return o;
		}
		ENDCG

		Pass // Denoise (bilateral filter)
		{
			// Based on https://www.shadertoy.com/view/4dfGDH

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#define KERNEL_SIZE 15
			#define SIGMA 10.0
			#define BSIGMA 0.1

			static const float kernel [KERNEL_SIZE] = {
				0.031225216, 0.033322271, 0.035206333,
				0.036826804, 0.038138565, 0.039104044,
				0.039695028, 0.039894000, 0.039695028,
				0.039104044, 0.038138565, 0.036826804,
				0.035206333, 0.033322271, 0.031225216
			};

			float normpdf (float x, float sigma)
			{
				return 0.39894 * exp(-0.5*x*x/(sigma*sigma))/sigma;
			}

			float normpdf3 (float3 v, float sigma)
			{
				return 0.39894 * exp(-0.5*dot(v,v)/(sigma*sigma))/sigma;
			}

			float _DenoiseStrength;

			float frag (v2f i) : SV_Target
			{
				float tap0 = tex2D(_Heightmap, i.texcoord).r;

				float sum 		= 0;
				float weightSum = 0;

				int span = (KERNEL_SIZE-1) / 2;

				float bZ = 1.0 / normpdf(0.0, BSIGMA);
				for (int x = -span; x <= span; ++x)
				{
					for (int y = -span; y <= span; ++y)
					{
						float2 offset = float2(x, y) * _HeightmapPixelSize.xy;
						float  tap = tex2D(_Heightmap, i.texcoord + offset).r;
						float weight = normpdf3(tap - tap0, BSIGMA) * bZ * kernel[span+y] * kernel[span+x];
						weightSum += weight;
						sum += tap * weight;

					}
				}

				return lerp(tap0, sum / weightSum, _DenoiseStrength);
			}
			ENDCG
		}

		Pass // Ridge maker
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			float _RidgeStrength;
			float _RidgeSharpness;

			float frag (v2f i) : SV_Target
			{
				float height = tex2D(_Heightmap, i.texcoord).r;

				float3 worldPos = 0;
				worldPos.xz = lerp(_HeightmapBounds.xy, _HeightmapBounds.xy + 1.0 / _HeightmapBounds.zw, i.texcoord);
				worldPos.y = GetTerrainHeight(worldPos);

				float3 normal = GetTerrainNormal(worldPos, 1.0 / _RidgeSharpness);

				height = tex2D(_Heightmap, i.texcoord + normal.xz * _RidgeStrength * _HeightmapPixelSize.x).r;

				return height;
			}
			ENDCG
		}

		Pass // Erosion
		{
			// Erosion noise based on https://www.shadertoy.com/view/MtGcWh

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			float _ErosionStrength;
			int   _ErosionOctaves;
			float _ErosionFrequency;
			float _ErosionSlopeMask;
			float _ErosionSlopeSharpness;

			float frag (v2f i) : SV_Target
			{
				float height = tex2D(_Heightmap, i.texcoord).r;

				float3 worldPos = 0;
				worldPos.xz = lerp(_HeightmapBounds.xy, _HeightmapBounds.xy + 1.0 / _HeightmapBounds.zw, i.texcoord);
				worldPos.y = GetTerrainHeight(worldPos);

				float3 normal = GetTerrainNormal(worldPos, 1.0 / _ErosionSlopeSharpness);

				float cavity = ComputeTerrainCavity(worldPos, 10);
				cavity = 1 - abs(cavity);

				// float erosion = ErosionFBM(worldPos, normal, _ErosionStrength, _ErosionOctaves, _ErosionFrequency) * pow(1-normal.y, _ErosionSlopeMask);
				float erosion = ErosionFBM(worldPos, normal, 1, _ErosionOctaves, _ErosionFrequency * 0.05)-1;
				// erosion = clamp(erosion, -0.5, 0.5);

				erosion *= pow(max(0.001, 1-normal.y), _ErosionSlopeMask);

				height += (erosion / _HeightmapScaleOffset.x) * _ErosionStrength;

				return height;
			}
			ENDCG
		}

		Pass // Shadow removal
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			float4 		_RandomDirections[512];

			float3		_ShadowColor;
			int 		_Pass;
			float 		_LumThreshold;
			float 		_SatThreshold;
			float		_Edge;
			float		_Radius;

			float3 SampleTex (sampler2D tex, float2 uv)
			{
				if (uv.x < 0) uv.x = -uv.x;
				if (uv.x > 1) uv.x = 2 - uv.x;
				if (uv.y < 0) uv.y = -uv.y;
				if (uv.y > 1) uv.y = 2 - uv.y;

				float3 color = tex2D(tex, uv);
// #ifndef UNITY_COLORSPACE_GAMMA
// 				color = pow(color, 1.0 / 2.2);
// #endif
				return color;
			}

			float3 frag (v2f i) : SV_Target
			{
				float2 dir = _RandomDirections[_Pass];

				float3 color = tex2D(_MainTex, i.texcoord);

				float3 color1 = tex2D(_MainTex, i.texcoord - dir * _MainTex_TexelSize.xy * 8);
				float3 HSV = rgb2hsv(color + 0.001);
				float3 HSV1 = rgb2hsv(color1 + 0.001);
				if (HSV1.z < HSV.z)
					HSV = HSV1;
				float delta = 1;

				// float lum = GetLuminance(color1);
				float lum = max(color1.r * 0.3, max(color1.g * 0.59, color1.b * 0.11));

				// Luminance threshold
				delta *= smoothstep((1-_Edge) * 0.5, 1 - (1-_Edge) * 0.5, saturate((1-lum) - (1-_LumThreshold)));

				// Saturation threshold
				delta *= HSV.y < _SatThreshold;
				
				float3 newColor = SampleTex(_MainTex, i.texcoord + dir * _MainTex_TexelSize.xy * _Radius);
				color = lerp(color, newColor, delta);
				
				return color;
			}
			ENDCG
		}

		Pass // Cavity generator
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#define BLEND_MODE 1 // 1 = overlay, 2 = soft light

			float _CavityIntensity;
			float _CavityRadius;

			float3 Blend (float3 base, float3 blend)
			{
#if BLEND_MODE == 1
				return base < 0.5 ? (2.0 * base * blend) : (1.0 - 2.0 * (1.0 - base) * (1.0 - blend));
#else
				return (blend < 0.5) ? (2.0 * base * blend + base * base * (1.0 - 2.0 * blend)) : (sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend));
#endif
			}

			float3 frag (v2f i) : SV_Target
			{
				float height = tex2D(_Heightmap, i.texcoord).r;

				float3 worldPos = 0;
				worldPos.xz = lerp(_HeightmapBounds.xy, _HeightmapBounds.xy + 1.0 / _HeightmapBounds.zw, i.texcoord);
				worldPos.y = GetTerrainHeight(worldPos);

				float3 color = tex2D(_MainTex, i.texcoord);

				float cavity = ComputeTerrainCavity(worldPos, _CavityRadius);
				
				color = lerp(color, Blend(color, cavity*0.5+0.5), _CavityIntensity);
				
				return color;
			}
			ENDCG
		}
	}
}