using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using System.Collections;
using System.Collections.Generic;
using System.IO;

public class SatelliteProcessor : EditorWindow
{
	Material _material;
	Material material
	{
		get
		{
			if (!_material)
				_material = new Material(Shader.Find("Hidden/SatelliteProcessor"));
			return _material;
		}
	}

	[SerializeField]
	Texture2D	input;
	[SerializeField, Range(1, 512)]
	int			passes				= 128;
	[SerializeField, Range(0, 1)]
	float		luminanceThreshold	= 0.35f;
	[SerializeField, Range(0, 1)]
	float		saturationThreshold	= 0.35f;
	[SerializeField, Range(0, 1)]
	float		edge				= 0.005f;
	[SerializeField, Range(0, 64)]
	float		radius				= 1f;
	[SerializeField, Range(0, 1)]
	float		maintainHue			= 0.0f;

	Vector4[]	random;

	class DoubleBuffer
	{
		public RenderTexture color;
		public RenderTexture buffer;

		public void Check (Texture2D input, bool output)
		{
			int width = input.width;
			int height = input.height;

			if (!output)
			{
				width = Mathf.Min(width, 1024);
				height = Mathf.Min(height, 1024);
			}

			if (!color || color.width != width || color.height != height)
			{
				color  = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32);
				color.useMipMap = true;
				color.autoGenerateMips = false;
				color.Create();

				buffer = new RenderTexture(color);
				buffer.Create();
			}
		}

		public void Swap ()
		{
			var tmp = color;
			color = buffer;
			buffer = tmp;
		}
	}

	DoubleBuffer buffer = new DoubleBuffer();

	[MenuItem("Tools/Satellite Processor")]
	static void Init ()
	{
		SatelliteProcessor window  = (SatelliteProcessor)EditorWindow.GetWindow(typeof(SatelliteProcessor), false, "Satellite Processor");
		window.Show();
	}

	void OnEnable ()
	{
		var data = EditorPrefs.GetString("SatelliteProcessor", JsonUtility.ToJson(this, false));
		JsonUtility.FromJsonOverwrite(data, this);

		Random.InitState(123456789);
		random = new Vector4[512];
		for (int i = 0; i < random.Length; i++)
			random[i] = Random.insideUnitCircle;

		input = null;

		Render(false);
	}
 
	void OnDisable ()
	{
		var data = JsonUtility.ToJson(this, false);
		EditorPrefs.SetString("SatelliteProcessor", data);
	}

	void UpdateMaterial (bool output)
	{
		material.SetVectorArray("_Random", random);
		material.SetInt("_Passes", passes);
		material.SetFloat("_LumThreshold", luminanceThreshold);
		material.SetFloat("_SatThreshold", saturationThreshold);
		material.SetFloat("_Edge", edge);
		material.SetFloat("_Radius", radius);
		material.SetFloat("_MaintainHue", maintainHue);
		material.SetInt("_Output", output ? 1 : 0);
		if (input)
		{
			//material.SetTexture("_MainTex", input);
			material.SetVector("_PixelSize", new Vector2(1f / input.width, 1f / input.height));
		}
	}

	void Render (bool output)
	{
		if (!input)
			return;

		buffer.Check(input, output);

		UpdateMaterial(output);

		material.SetInt("_Pass", 0);
		material.SetTexture("_MainTex", input);
		Graphics.Blit(input, buffer.color, material, 0);

		for (int i = 0; i < passes-1; i++)
		{
			material.SetInt("_Pass", i);
			material.SetTexture("_MainTex", buffer.color);
			Graphics.Blit(buffer.color, buffer.buffer, material, 0);

			buffer.Swap();
		}

		buffer.color.GenerateMips();
	}

	void OnGUI ()
	{
		var rect = new Rect();
		rect.x = 0;
		rect.y = 0;
		rect.width = Screen.width / 2;
		rect.height = rect.width;
		GUILayout.BeginHorizontal();

		if (!buffer.color)
			Render(false);

		if (input)
		{
			material.SetTexture("_MainTex", input);
			Graphics.DrawTexture(rect, input, material, 1);
		}
		else
		{
			GUI.Box(rect, "Assign an input texture");
		}

		rect.x = rect.width;

		if (buffer.color)
		{
			material.SetTexture("_MainTex", buffer.color);
			Graphics.DrawTexture(rect, buffer.color, material, 1);
		}
		else
		{
			GUI.Box(rect, "Assign an input texture");
		}

		GUILayout.EndHorizontal();

		GUILayout.Space(rect.height + 4);

		EditorGUI.BeginChangeCheck();
		input				= EditorGUILayout.ObjectField("Input", input, typeof (Texture2D), false) as Texture2D;
		passes				= EditorGUILayout.IntSlider("Passes", passes, 1, 64);
		luminanceThreshold	= EditorGUILayout.Slider("Luminance Threshold", luminanceThreshold, 0, 1);
		saturationThreshold	= EditorGUILayout.Slider("Saturation Threshold", saturationThreshold, 0, 1);
		edge				= EditorGUILayout.Slider("Edge", edge, 0, 1);
		radius				= EditorGUILayout.Slider("Radius", radius, 0, 4);
		maintainHue			= EditorGUILayout.Slider("Maintain Hue", maintainHue, 0, 1);
		if (EditorGUI.EndChangeCheck())
			Render(false);

		if (GUILayout.Button("Output"))
			Output();
	}

	void Output ()
	{
		var outputDir = AssetDatabase.GetAssetPath(input);
		outputDir = Path.GetDirectoryName(outputDir);
		Render(true);

		var tex = new Texture2D(input.width, input.height, TextureFormat.RGBA32, false);
		RenderTexture.active = buffer.color;
		tex.ReadPixels(new Rect(0, 0, input.width, input.height), 0, 0);
		RenderTexture.active = null;

		byte[] bytes;
		bytes = tex.EncodeToJPG(100);
		
		File.WriteAllBytes(outputDir + "/" + input.name + "_Processed.jpg", bytes);
		DestroyImmediate(tex);

		AssetDatabase.Refresh();
	}
}