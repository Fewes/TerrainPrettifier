Shader "Hidden/SatelliteProcessor"
{
	SubShader
	{
		Cull Off
		ZWrite Off
		ZTest Always

		CGINCLUDE
		#include "UnityCG.cginc"

		struct v2f
		{
			float4 vertex 	: SV_POSITION;
			float2 texcoord	: TEXCOORD0;
		};

		v2f vert (appdata_full v)
		{
			v2f o;
			UNITY_INITIALIZE_OUTPUT(v2f, o);

			o.vertex 	= UnityObjectToClipPos(v.vertex);
			o.texcoord 	= v.texcoord;

			return o;
		}

		float4 		_Random[512];
		float2		_PixelSize;

		sampler2D 	_MainTex;
		int 		_Passes;
		int 		_Pass;
		float 		_LumThreshold;
		float 		_SatThreshold;
		float		_Edge;
		float		_Radius;
		float		_MaintainHue;
		int			_Output;

		float GetLuminance (float3 color)
		{
			return dot(color, float3(0.3, 0.59, 0.11));
		}

		float3 rgb2hsv (float3 c)
		{
			float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
			float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
			float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

			float d = q.x - min(q.w, q.y);
			float e = 1.0e-10;
			return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
		}

		float3 hsv2rgb (float3 c)
		{
			float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
			float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
			return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
		}

		float3 SampleTex (sampler2D tex, float2 uv)
		{
			if (uv.x < 0) uv.x = -uv.x;
			if (uv.x > 1) uv.x = 2 - uv.x;
			if (uv.y < 0) uv.y = -uv.y;
			if (uv.y > 1) uv.y = 2 - uv.y;

			float3 color = tex2D(tex, uv);
#ifndef UNITY_COLORSPACE_GAMMA
			color = pow(color, 1.0 / 2.2);
#endif
			return color;
		}
		ENDCG

		Pass // Process
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			half4 frag (v2f i) : SV_Target
			{
				float3 color = SampleTex(_MainTex, i.texcoord);
				float3 color0 = color;
				float3 hsv = 0;

				// UNITY_LOOP
				// for (int u = 0; u < _Passes; u++)
				// {
					hsv = rgb2hsv(color);

					// float luminance = GetLuminance(color);
					float delta = saturate(((1-hsv.z) - (1-_LumThreshold)) / _Edge) * saturate(((1-hsv.y) - (1-_SatThreshold)) / _Edge);
					
					// float3 newColor = lerp(color, SampleTex(_MainTex, i.texcoord + _Random[_Pass] * _Radius * _PixelSize * (_Pass+1)), delta);
					// float3 newColor = lerp(color, SampleTex(_MainTex, i.texcoord + _Random[_Pass] * _Radius * _PixelSize * 1000), delta);
					float3 newColor = lerp(color, SampleTex(_MainTex, i.texcoord + _Random[_Pass]), delta);
					float3 newHsv = rgb2hsv(newColor);
					if (newHsv.z > hsv.z && newHsv.z < _LumThreshold)
						color = newColor;
				// }

				hsv = rgb2hsv(color);
				hsv.x = lerp(hsv.x, rgb2hsv(color0).x, _MaintainHue);
				color = hsv2rgb(hsv);

				// if (_Output == 0.0)
					color = pow(color, 2.2);
				
				return float4(color, 1);
			}
			ENDCG
		}

		Pass // Display
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			half4 frag (v2f i) : SV_Target
			{
				float3 color = SampleTex(_MainTex, i.texcoord);
				
				return float4(color, 1);
			}
			ENDCG
		}
	}
}