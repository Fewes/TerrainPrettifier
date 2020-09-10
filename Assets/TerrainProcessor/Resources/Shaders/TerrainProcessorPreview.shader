Shader "TerrainProcessor/Preview"
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
			#include "TerrainProcessor.cginc"
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
			float3 _SunRemovalDir;

			int _Lighting;
			int _Shadows;
			int _Albedo;

			half4 frag (v2f i) : SV_Target
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
					color = 0.5;

				float cavity = ComputeTerrainCavity(worldPos, 2);
				color *= 1 + cavity * 0.25;

				if (abs(worldPos.x - _TerrainCenter.x) > _TerrainSize.x * 0.5 || abs(worldPos.z - _TerrainCenter.z) > _TerrainSize.z * 0.5)
					discard;

				float3 normal = GetTerrainNormal(worldPos);

				float fresnel = pow(1 - max(0, dot(-rayDir, normal)), 8) * unity_AmbientSky;
				// color += fresnel;

				/*
				// float shadowRemovalLum = max(0, dot(normal, _SunRemovalDir)*0.5+0.5);
				float shadowRemovalLum = dot(normal, _SunRemovalDir);

				float3 sunRemovalDir = _SunRemovalDir;

				// float delta = 1 - saturate((color.r) / 0.3);
				float delta = pow(-shadowRemovalLum, 0.5);

				float lum = color.r;
				float _LumThreshold = 0.1;
				float _Edge = 0.1;
				delta *= saturate(((1-lum) - (1-_LumThreshold)) / _Edge);

				if (delta > 0)
				{
					float3 prev = worldPos;
					UNITY_LOOP
					for (int u = 0; u < 2048; u++)
					{
						float3 p = worldPos + sunRemovalDir * (u+1) * _HeightmapTexelSize.z;
						float  h = GetTerrainHeight(p);
						if (h < p.y)
						{
							float2 uv = GetTerrainUV((prev + p) * 0.5);
							// float delta = shadowRemovalLum+1;
							// delta = 1-saturate(delta);
							// delta = smoothstep(0.0, 0.5, delta);
							color = lerp(color, tex2D(_Satellite, uv), delta);
							break;
						}

						prev = p;
					}
				}
				*/

				if (_Lighting == 1.0)
				{
					float ao = lerp(1, saturate(ComputeTerrainCavity(worldPos, 40) + 1), 0.3);

					float shadowBias = 10;
					float shadowDist = GetTerrainDistance(worldPos + _WorldSpaceLightPos0 * shadowBias, _WorldSpaceLightPos0, noise);
					float atten = _Shadows == 1.0 ? GetTerrainOcclusion(worldPos + _WorldSpaceLightPos0 * shadowBias, _WorldSpaceLightPos0, 100, noise) : 1;
					
					color *= max(0, dot(normal, _WorldSpaceLightPos0)) * atten * _LightColor0 + unity_AmbientSky * max(0, normal.y) * ao;
				}

				// color = ComputeCavity(_Heightmap, texcoord, _HeightmapPixelSize) * 1000;

				// if (screenUV.x > 0.5)
				// 	color = shadowRemovalLum;

				//take the curl of the normal to get the gradient facing down the slope
				
				// float erosion = ErosionFBM(worldPos, normal, 0.005);// * (1-normal.y);

				// color = erosion*0.5+0.5;

				// color = tex2D(_FlowBuffer, texcoord);
				
				return float4(color, 1);
			}
			ENDCG
		}
	}
}