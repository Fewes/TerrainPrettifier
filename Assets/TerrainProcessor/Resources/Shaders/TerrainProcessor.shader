Shader "TerrainProcessor/Processor"
{
	SubShader
	{
		Cull Off
		ZWrite Off
		ZTest Always

		CGINCLUDE
		#include "UnityCG.cginc"
		#include "UnityLightingCommon.cginc"
		#include "TerrainProcessor.cginc"
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

				height += erosion * _ErosionStrength;

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

			float3 rgb2xyz( float3 c ) {
			    float3 tmp;
			    tmp.x = ( c.r > 0.04045 ) ? pow( ( c.r + 0.055 ) / 1.055, 2.4 ) : c.r / 12.92;
			    tmp.y = ( c.g > 0.04045 ) ? pow( ( c.g + 0.055 ) / 1.055, 2.4 ) : c.g / 12.92,
			    tmp.z = ( c.b > 0.04045 ) ? pow( ( c.b + 0.055 ) / 1.055, 2.4 ) : c.b / 12.92;
			    const float3x3 mat = float3x3(
					0.4124, 0.3576, 0.1805,
			        0.2126, 0.7152, 0.0722,
			        0.0193, 0.1192, 0.9505 
				);
			    return 100.0 * mul(tmp, mat);
			}

			float3 xyz2lab( float3 c ) {
			    float3 n = c / float3(95.047, 100, 108.883);
			    float3 v;
			    v.x = ( n.x > 0.008856 ) ? pow( n.x, 1.0 / 3.0 ) : ( 7.787 * n.x ) + ( 16.0 / 116.0 );
			    v.y = ( n.y > 0.008856 ) ? pow( n.y, 1.0 / 3.0 ) : ( 7.787 * n.y ) + ( 16.0 / 116.0 );
			    v.z = ( n.z > 0.008856 ) ? pow( n.z, 1.0 / 3.0 ) : ( 7.787 * n.z ) + ( 16.0 / 116.0 );
			    return float3(( 116.0 * v.y ) - 16.0, 500.0 * ( v.x - v.y ), 200.0 * ( v.y - v.z ));
			}

			float3 rgb2lab( float3 c )
			{
				float3 lab = xyz2lab( rgb2xyz( c ) );
				return float3( lab.x / 100.0, 0.5 + 0.5 * ( lab.y / 127.0 ), 0.5 + 0.5 * ( lab.z / 127.0 ));
			}

			half4 frag (v2f i) : SV_Target
			{
				float2 dir = _RandomDirections[_Pass];

				float3 color = tex2D(_MainTex, i.texcoord);
				float3 color1 = tex2D(_MainTex, i.texcoord - dir * _MainTex_TexelSize.xy * 8);
				float3 color0 = color;
				float3 HSV = rgb2hsv(color + 0.001);
				float3 HSV1 = rgb2hsv(color1 + 0.001);
				if (HSV1.z < HSV.z)
					HSV = HSV1;
				float delta = 1;

				// Luminance threshold
				delta *= smoothstep((1-_Edge) * 0.5, 1 - (1-_Edge) * 0.5, saturate((1-HSV.z) - (1-_LumThreshold)));

				// Saturation threshold
				// delta *= saturate(((1-HSV.y) - (1-_SatThreshold)) / _Edge);
				// delta *= smoothstep((1-_Edge) * 0.5, 1 - (1-_Edge) * 0.5, saturate((1-HSV.y) - (1-_SatThreshold)));
				float3 shadowHSV = rgb2hsv(_ShadowColor);
				// delta += 1 - saturate(length(HSV.x - shadowHSV.x) / _SatThreshold);
				
				float3 newColor = SampleTex(_MainTex, i.texcoord + dir * _MainTex_TexelSize.xy * _Radius);
				// if (rgb2hsv(newColor).z < HSV.z)
					color = lerp(color, newColor, delta);

				// delta = dot(rgb2xyz(color), rgb2xyz(_ShadowColor)) * 0.1;
				// delta = delta < _SatThreshold;
				// delta = smoothstep(_SatThreshold, 1, delta);

				// color = lerp(color, float3(1, 0, 0), delta);
				
				return float4(color, 1);
			}
			ENDCG
		}
	}
}