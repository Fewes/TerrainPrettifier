Shader "TerrainPrettifier/Preview"
{
	Properties
	{
		_Color ("Color", Color) = (1, 1, 1, 1)
	}
	SubShader
	{
		ZWrite Off
		ZTest Always
		Cull Front

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"
			#include "UnityLightingCommon.cginc"
			#include "TerrainPrettifier.cginc"
			#include "Erosion.cginc"

			struct v2f
			{
				float4 vertex 		: SV_POSITION;
				float2 texcoord		: TEXCOORD0;
				float3 worldPos 	: TEXCOORD1;
				float4 screenPos 	: TEXCOORD2;
			};

			half4		_Color;

			v2f vert (appdata_full v)
			{
				v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);

				o.vertex 	= UnityObjectToClipPos(v.vertex);
				o.texcoord 	= v.texcoord;
				o.worldPos	= mul(UNITY_MATRIX_M, v.vertex);
				o.screenPos	= ComputeScreenPos(o.vertex);

				return o;
			}

			sampler2D _Satellite;
			float3 _SunDir;
			float _Exposure;

			int _Lighting;
			int _Shadows;
			int _Albedo;

			float3 AmbientColor (float3 sunDir)
			{
				float f = 1 - max(0, sunDir.y);
				f *= f;
				f *= f;
				f *= f;
				f *= f;
				f *= f;
				float3 color = lerp(float3(0.15, 0.22, 0.3), float3(1, 0.25, 0), f * 0.4);
				return color * (1-f * 0.99) * 0.75;
			}

			float3 SunColor (float3 sunDir)
			{
				float f = 1 - max(0, sunDir.y);
				f *= f;
				f *= f;
				f *= f;
				float3 color = lerp(float3(1, 0.95, 0.84), float3(1, 0.4, 0), f);
				f *= f;
				f *= f;
				color = lerp(color, float3(1, 0, 0), f*f*f*f);
				return color * (1-f);
			}

			half3 frag (v2f i) : SV_Target
			{
				float2 screenUV = i.screenPos.xy / i.screenPos.w;
				float  noise 	= GetNoise(screenUV);
				float3 rayStart = _WorldSpaceCameraPos;
				float3 rayDir 	= normalize(i.worldPos - rayStart);
				half3  color 	= _Color;

				float2 boundsIntersection = BoxIntersection(rayStart, rayDir, _TerrainCenter, _TerrainSize);
				if (boundsIntersection.y < 0)
					discard;

				rayStart += rayDir * max(0, boundsIntersection.x);

				float dist = GetTerrainDistance(rayStart, rayDir, noise);
				if (dist > _TerrainMarcherMaxDist)
					discard;

				float3 worldPos = rayStart + rayDir * dist;
				float2 texcoord = GetTerrainUV(worldPos.xz);
				color = tex2D(_Satellite, texcoord);
				if (_Albedo == 0.0)
					color = float3(0.95, 0.1, 0.1);
					// color = 0.5;

				float cavity = ComputeTerrainCavity(worldPos, 2);
				// color *= 1 + cavity * 0.3;

				if (abs(worldPos.x - _TerrainCenter.x) > _TerrainSize.x * 0.5 || abs(worldPos.z - _TerrainCenter.z) > _TerrainSize.z * 0.5)
					discard;

				float3 normal = GetTerrainNormal(worldPos);

				if (_Lighting == 1.0)
				{
					float shadowBias = 10;
					float atten = _Shadows == 1.0 ? GetTerrainOcclusion(worldPos + _SunDir * shadowBias, _SunDir, 100, noise) : 1;
					float occlusion = lerp(1, saturate(ComputeTerrainCavity(worldPos, 40) + 1), 0.3);

					if (_Albedo == 0.0)
					{
						float fresnel = pow(1 - max(0, dot(-rayDir, normal)), 2) * AmbientColor(_SunDir);
						color += fresnel;

						float3 R = reflect(rayDir, normal);
						color += pow(saturate(dot(R, _SunDir)), 10) * SunColor(_SunDir) * atten * 0.1;
					}
						
					color *= max(0, dot(normal, _SunDir)) * atten * SunColor(_SunDir) + AmbientColor(_SunDir) * max(0, normal.y) * occlusion;
				}
				
				return color * _Exposure;
			}
			ENDCG
		}
	}
}