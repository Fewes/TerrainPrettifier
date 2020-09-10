using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.IO;

[CustomEditor(typeof(TerrainPrettifier)), CanEditMultipleObjects]
public class TerrainPrettifierEditor : Editor
{
	// http://tips.hecomi.com/entry/2016/10/15/004144
	public static class CustomUI
	{
		public static bool Foldout (string title, bool display)
		{
			var style = new GUIStyle("ShurikenModuleTitle");
			style.font = new GUIStyle(EditorStyles.label).font;
			style.border = new RectOffset(15, 7, 4, 4);
			style.fixedHeight = 22;
			style.contentOffset = new Vector2(20f, -2f);

			var rect = GUILayoutUtility.GetRect(16f, 22f, style);
			GUI.Box(rect, title, style);

			var e = Event.current;

			var toggleRect = new Rect(rect.x + 4f, rect.y + 2f, 13f, 13f);
			if (e.type == EventType.Repaint) {
				EditorStyles.foldout.Draw(toggleRect, false, false, display, false);
			}

			if (e.type == EventType.MouseDown && rect.Contains(e.mousePosition)) {
				display = !display;
				e.Use();
			}

			return display;
		}

		public static bool FoldoutWithToggle (string title, bool display, ref bool toggle)
		{
			var style = new GUIStyle("ShurikenModuleTitle");
			style.font = new GUIStyle(EditorStyles.label).font;
			style.border = new RectOffset(15, 7, 4, 4);
			style.fixedHeight = 22;
			style.contentOffset = new Vector2(20f, -2f);

			var rect = GUILayoutUtility.GetRect(16f, 22f, style);
			GUI.Box(rect, title, style);

			var subRect = rect;
			subRect.x = subRect.max.x - subRect.height;
			toggle = GUI.Toggle(subRect, toggle, "");

			var e = Event.current;

			var toggleRect = new Rect(rect.x + 4f, rect.y + 2f, 13f, 13f);
			if (e.type == EventType.Repaint) {
				EditorStyles.foldout.Draw(toggleRect, false, false, display, false);
			}

			if (e.type == EventType.MouseDown && rect.Contains(e.mousePosition)) {
				display = !display;
				e.Use();
			}

			return display;
		}

	}
	TerrainPrettifier	prettifier;
	Terrain				terrain			=> prettifier.terrain;
	TerrainData			terrainData		=> terrain.terrainData;
	Bounds				terrainBounds
	{
		get
		{
			var bounds = terrainData.bounds;
			bounds.center += terrain.transform.position;
			return bounds;
		}
	}

	Vector4[] randomDirections;

	void OnEnable ()
	{
		if (Application.isPlaying)
			return;

		prettifier = (TerrainPrettifier)target;

		CacheProperties();

		if (!hasBackupData)
		{
			BackupOriginalData();
		}

		Random.InitState(123);
		randomDirections = new Vector4[512];
		for (int i = 0; i < randomDirections.Length; i++)
		{
			randomDirections[i] = Random.insideUnitCircle;
		}

		ProcessHeightmap();
	}

	void OnDisable ()
	{
		CheckRenderer(true);
	}

	#region GUI
	SerializedProperty
		propHeightmapProcessorEnabled,
		propSatelliteProcessorEnabled,
		propDenoise,
		propRidges,
		propErosion,
		propSatellite,
		propShadowRemoval,
		propCavityGenerator,
		propRenderer;

	void CacheProperties ()
	{
		propHeightmapProcessorEnabled = serializedObject.FindProperty("heightmapProcessorEnabled");
		propSatelliteProcessorEnabled = serializedObject.FindProperty("satelliteProcessorEnabled");
		propDenoise			= serializedObject.FindProperty("denoiser");
		propRidges			= serializedObject.FindProperty("ridges");
		propErosion			= serializedObject.FindProperty("erosion");
		propSatellite		= serializedObject.FindProperty("satellite");
		propShadowRemoval	= serializedObject.FindProperty("shadowRemoval");
		propCavityGenerator	= serializedObject.FindProperty("cavityGenerator");
		propRenderer		= serializedObject.FindProperty("renderer");
	}

	public override void OnInspectorGUI ()
	{
		if (Application.isPlaying)
		{
			EditorGUILayout.HelpBox("Editing is disabled during Play Mode", MessageType.Info);
			return;
		}

		//DrawDefaultInspector();

		serializedObject.Update();

		bool heightmapNeedsProcessing = false;
		bool heightmapProcessorEnabled = prettifier.heightmapProcessorEnabled;
		prettifier.heightmapFoldout = CustomUI.FoldoutWithToggle("Height Map Processor", prettifier.heightmapFoldout, ref heightmapProcessorEnabled);
		if (heightmapProcessorEnabled != prettifier.heightmapProcessorEnabled)
		{
			Undo.RecordObject(prettifier, "Modified heightmapProcessorEnabled");
			prettifier.heightmapProcessorEnabled = heightmapProcessorEnabled;
			heightmapNeedsProcessing = true;
		}
		if (prettifier.heightmapFoldout)
		{
			EditorGUI.BeginChangeCheck();
			EditorGUILayout.PropertyField(propDenoise);
			EditorGUILayout.PropertyField(propRidges);
			EditorGUILayout.PropertyField(propErosion);
			if (EditorGUI.EndChangeCheck())
			{
				heightmapNeedsProcessing = true;
			}

			if (GUILayout.Button("Process Height Map"))
			{
				heightmapNeedsProcessing = true;
			}

			if (GUILayout.Button("Apply To Terrain"))
			{
				if (EditorUtility.DisplayDialog("Apply terrain modification?", "Are you sure you wish to apply the prettified result to the terrain object?\n"
					+ "This is a destructive operation that can only be reversed by restoring the backup.", "Do it!", "Cancel"))
				{
					
				}
			}

			GUILayout.Space(4);

			if (GUILayout.Button("Backup Current"))
			{
				if (EditorUtility.DisplayDialog("Backup current data?", "Are you sure you wish to overwrite the backup data with the current data? This is not an undoable operation!", "Do it!", "Cancel"))
				{
					BackupOriginalData();
				}
			}

			if (GUILayout.Button("Restore Backup"))
			{
				if (EditorUtility.DisplayDialog("Restore backup data?", "Are you sure you wish to overwrite the current data with the backup data? This is not an undoable operation!", "Do it!", "Cancel"))
				{
					RestoreOriginalData();
				}
			}
		}
		if (heightmapNeedsProcessing)
		{
			serializedObject.ApplyModifiedProperties();
			ProcessHeightmap();
		}

		EditorGUILayout.Space();

		bool satellitemapNeedsProcessing = false;
		bool satelliteProcessorEnabled = prettifier.satelliteProcessorEnabled;
		prettifier.satelliteFoldout = CustomUI.FoldoutWithToggle("Satellite Map Processor", prettifier.satelliteFoldout, ref satelliteProcessorEnabled);
		if (satelliteProcessorEnabled != prettifier.satelliteProcessorEnabled)
		{ 
			Undo.RecordObject(prettifier, "Modified satelliteProcessorEnabled");
			prettifier.satelliteProcessorEnabled = satelliteProcessorEnabled;
			satellitemapNeedsProcessing = true;
		}
		if (prettifier.satelliteFoldout)
		{
			EditorGUI.BeginChangeCheck();
			EditorGUILayout.PropertyField(propSatellite);
			EditorGUILayout.PropertyField(propShadowRemoval);
			EditorGUILayout.PropertyField(propCavityGenerator);
			if (EditorGUI.EndChangeCheck())
			{
				satellitemapNeedsProcessing = true;
			}

			if (GUILayout.Button("Process Satellite Map"))
			{
				satellitemapNeedsProcessing = true;
			}
		}
		if (satellitemapNeedsProcessing)
		{
			serializedObject.ApplyModifiedProperties();
			ProcessSatelliteMap();
		}

		EditorGUILayout.Space();

		prettifier.previewFoldout = CustomUI.Foldout("Preview", prettifier.previewFoldout);
		if (prettifier.previewFoldout)
		{
			EditorGUILayout.PropertyField(propRenderer);
		}

		SetMaterialParameters(previewMaterial, heightmapBuffer.color ? heightmapBuffer.color : terrainData.heightmapTexture);
		SetPreviewMaterialParameters();

		serializedObject.ApplyModifiedProperties();
	}
	#endregion

	#region Data handling
	string projectPath => Application.dataPath.Replace("Assets", "");
	string terrainDataPath => projectPath + AssetDatabase.GetAssetPath(terrainData);
	string terrainDataBackupPath
	{
		get
		{
			var originalPath = terrainDataPath;
			string fDir = Path.GetDirectoryName(originalPath);
			string fName = Path.GetFileNameWithoutExtension(originalPath);
			string fExt = Path.GetExtension(originalPath);
			return (fDir + "/" + fName + "_Backup" + fExt).Replace("\\", "/");
		}
	}
	bool hasBackupData => File.Exists(terrainDataBackupPath);

	void BackupOriginalData ()
	{
		File.Copy(terrainDataPath, terrainDataBackupPath, true);
		AssetDatabase.Refresh();
	}

	void RestoreOriginalData ()
	{
		if (!hasBackupData)
			return;

		File.Copy(terrainDataBackupPath, terrainDataPath, true);
		AssetDatabase.Refresh();
	}
	#endregion

	#region Processing
	Material _material;
	Material material
	{
		get
		{
			if (!_material)
				_material = new Material(Shader.Find("TerrainPrettifier/Processor"));
			return _material;
		}
	}

	const int SHADER_PASS_DENOISE			= 0;
	const int SHADER_PASS_RIDGEMAKER		= 1;
	const int SHADER_PASS_EROSION			= 2;
	const int SHADER_PASS_SHADOW_REMOVAL	= 3;
	const int SHADER_PASS_CAVITY_GENERATOR	= 4;

	class DoubleBuffer
	{
		RenderTexture _color;
		RenderTexture _buffer;
		public RenderTexture color  => _color;
		public RenderTexture buffer => _buffer;

		public void Check (RenderTexture input, RenderTextureFormat format, bool mipmaps = false)
		{
			if (!input)
				return;

			int width = input.width;
			int height = input.height;

			if (!_color || _color.width != width || _color.height != height || _color.format != format)
			{
				var descriptor = input.descriptor;
				descriptor.colorFormat = format;
				if (mipmaps)
				{
					descriptor.useMipMap = true;
					descriptor.autoGenerateMips = true;
				}
				_color  = new RenderTexture(descriptor);
				_color.Create();

				_buffer = new RenderTexture(descriptor);
				_buffer.Create();
			}
		}

		public void Check (RenderTexture input)
		{
			Check(input, input.format);
		}

		public void Check (Texture2D input, RenderTextureFormat format, bool mipmaps = false)
		{
			if (!input)
				return;

			int width = input.width;
			int height = input.height;

			if (!_color || _color.width != width || _color.height != height || _color.format != format)
			{
				var descriptor = new RenderTextureDescriptor(width, height, format, 0, 0);
				descriptor.colorFormat = format;
				if (mipmaps)
				{
					descriptor.useMipMap = true;
					descriptor.autoGenerateMips = true;
				}
				_color  = new RenderTexture(descriptor);
				_color.Create();

				_buffer = new RenderTexture(descriptor);
				_buffer.Create();
			}
		}

		public void Blit (Material material, int pass, bool autoSwap)
		{
			material.SetTexture("_Maintex", color);
			Graphics.Blit(color, buffer, material, pass);
			if (autoSwap)
				Swap();
		}

		public void Blit (Material material, int pass)
		{
			Blit(material, pass, true);
		}

		public void Swap ()
		{
			var tmp = _color;
			_color = _buffer;
			_buffer = tmp;
		}
	}

	DoubleBuffer heightmapBuffer = new DoubleBuffer();

	void ProcessHeightmap ()
	{
		var heightmap = terrainData.heightmapTexture;

		heightmapBuffer.Check(heightmap);

		// Initial blit
		Graphics.Blit(heightmap, heightmapBuffer.color);

		if (prettifier.heightmapProcessorEnabled)
		{
			// Bilateral smoothing
			if (prettifier.denoiser.enabled)
			{
				for (int i = 0; i < Mathf.CeilToInt(prettifier.denoiser.strength); i++)
				{
					SetMaterialParameters(material, heightmapBuffer.color);
					material.SetFloat("_DenoiseStrength", Mathf.Clamp01(prettifier.denoiser.strength - i));
					heightmapBuffer.Blit(material, SHADER_PASS_DENOISE);
				}
			}

			// Ridge maker
			if (prettifier.ridges.enabled)
			{
				SetMaterialParameters(material, heightmapBuffer.color);
				heightmapBuffer.Blit(material, SHADER_PASS_RIDGEMAKER);
			}

			// Erosion
			if (prettifier.erosion.enabled)
			{
				SetMaterialParameters(material, heightmapBuffer.color);
				heightmapBuffer.Blit(material, SHADER_PASS_EROSION);
			}
		}

		SetMaterialParameters(previewMaterial, heightmapBuffer.color);
		SetPreviewMaterialParameters();
	}

	DoubleBuffer satellitemapBuffer = new DoubleBuffer();

	void ProcessSatelliteMap ()
	{
		var satellitemap = prettifier.satellite;

		if (!satellitemap)
			return;

		satellitemapBuffer.Check(satellitemap, RenderTextureFormat.ARGB32);

		// Initial blit
		Graphics.Blit(satellitemap, satellitemapBuffer.color);

		if (prettifier.satelliteProcessorEnabled)
		{
			if (prettifier.shadowRemoval.enabled)
			{
				material.SetColor("_ShadowColor", prettifier.shadowRemoval.shadowColor);
				material.SetVectorArray("_RandomDirections", randomDirections);
				material.SetFloat("_LumThreshold", prettifier.shadowRemoval.luminanceThreshold);
				material.SetFloat("_SatThreshold", prettifier.shadowRemoval.saturationThreshold);
				material.SetFloat("_Edge", prettifier.shadowRemoval.edge);
				material.SetFloat("_Radius", prettifier.shadowRemoval.radius);

				for (int i = 0; i < prettifier.shadowRemoval.passes; i++)
				{
					material.SetTexture("_MainTex", satellitemapBuffer.color);
					material.SetInt("_Pass", i);
					satellitemapBuffer.Blit(material, SHADER_PASS_SHADOW_REMOVAL);
				}
			}

			if (prettifier.cavityGenerator.enabled)
			{
				SetMaterialParameters(material, heightmapBuffer.color ? heightmapBuffer.color : terrainData.heightmapTexture);
				material.SetFloat("_CavityIntensity", prettifier.cavityGenerator.intensity);
				material.SetFloat("_CavityRadius", prettifier.cavityGenerator.radius);
				satellitemapBuffer.Blit(material, SHADER_PASS_CAVITY_GENERATOR);
			}
		}
	}

	void SetMaterialParameters (Material material, Texture heightmap)
	{
		CheckRenderer();

		var bounds = terrainBounds;
		renderer.transform.position   = bounds.center;
		renderer.transform.localScale = bounds.size;

		var heightmapBounds = new Vector4(bounds.min.x, bounds.min.z, 1f / bounds.size.x, 1f / bounds.size.z);
		//var heightmap = terrainData.heightmapTexture;
		//previewMaterial.SetTexture("_Heightmap", buffer.color ? buffer.color : heightmap);
		/*
		if (buffer.color)
			previewMaterial.SetTexture("_Heightmap", buffer.color);
		else
			previewMaterial.SetTexture("_Heightmap", Texture2D.blackTexture);
		*/

		material.SetTexture("_Heightmap", heightmap);
				
		material.SetVector("_TerrainCenter", bounds.center);
		material.SetVector("_TerrainSize", bounds.size);
		material.SetVector("_HeightmapBounds", heightmapBounds);
		float texelSizeX = bounds.size.x / heightmap.width;
		float texelSizeZ = bounds.size.z / heightmap.height;
		material.SetVector("_HeightmapTexelSize", new Vector4(1f / texelSizeX, 1f / texelSizeZ, texelSizeX, texelSizeZ));
		material.SetVector("_HeightmapPixelSize", new Vector4(1f / heightmap.width, 1f / heightmap.height, heightmap.width, heightmap.height));
		material.SetVector("_HeightBounds", new Vector4(bounds.min.y, bounds.max.y, 0, 0));
		material.SetVector("_HeightmapScaleOffset", new Vector4(terrain.terrainData.heightmapScale.y, terrain.transform.position.y, 0, 0));

		material.SetFloat("_TerrainMarcherSampleCount", prettifier.renderer.sampleCount);
		material.SetFloat("_TerrainMarcherMaxDist", 100000);
		material.SetFloat("_TerrainMarcherMinStep", 0);
		material.SetTexture("_BlueNoise64", blueNoise64);

		if (satellitemapBuffer.color)
			material.SetTexture("_Satellite", satellitemapBuffer.color);
		else
			material.SetTexture("_Satellite", prettifier.satellite ? prettifier.satellite : Texture2D.whiteTexture);

		material.SetVector("_SunDir", Quaternion.AngleAxis(prettifier.renderer.sunAzimuth, Vector3.up) * Quaternion.AngleAxis(prettifier.renderer.sunAltitude, -Vector3.right) * Vector3.forward);
		material.SetFloat("_Exposure", prettifier.renderer.exposure);

		material.SetFloat("_RidgeStrength", prettifier.ridges.strength);
		material.SetFloat("_RidgeSharpness", Mathf.Pow(Mathf.Max(prettifier.ridges.sharpness, 0.001f), 2));

		material.SetFloat("_ErosionStrength", Mathf.Pow(prettifier.erosion.strength, 4));
		material.SetInt("_ErosionOctaves", prettifier.erosion.octaves);
		material.SetFloat("_ErosionFrequency", prettifier.erosion.frequency);
		material.SetFloat("_ErosionSlopeMask", prettifier.erosion.slopeMask);
		material.SetFloat("_ErosionSlopeSharpness", prettifier.erosion.slopeSharpness);
	}

	void SetPreviewMaterialParameters ()
	{
		previewMaterial.SetInt("_Lighting", prettifier.renderer.lighting ? 1 : 0);
		previewMaterial.SetInt("_Shadows", prettifier.renderer.shadows ? 1 : 0);
		previewMaterial.SetInt("_Albedo", prettifier.renderer.albedo ? 1 : 0);
		previewMaterial.SetFloat("_TerrainMarcherMaxSlope", prettifier.renderer.maxSlope);
	}
	#endregion

	#region Rendering
	Mesh _unitCube;
	Mesh unitCube
	{
		get
		{
			if (!_unitCube)
				_unitCube = (Resources.Load("Meshes/UnitCube") as GameObject).GetComponent<MeshFilter>().sharedMesh;
			return _unitCube;
		}
	}

	Material _previewMaterial;
	Material previewMaterial
	{
		get
		{
			if (!_previewMaterial)
				_previewMaterial = Resources.Load("Materials/TerrainPrettifierPreview") as Material;
			return _previewMaterial;
		}
	}

	Texture2D _blueNoise64;
	Texture2D blueNoise64
	{
		get
		{
			if (!_blueNoise64)
				_blueNoise64 = Resources.Load("Textures/BlueNoise64") as Texture2D;
			return _blueNoise64;
		}
	}

	MeshRenderer renderer;

	void CheckRenderer (bool destroy = false)
	{
		if (!unitCube)
		{
			Debug.LogError("Meshes/UnitCube not found!");
			return;
		}

		if (!renderer)
		{
			var go = GameObject.Find(terrain.name + "_TerrainPrettifierRenderer");
			if (go)
				renderer = go.GetComponent<MeshRenderer>();
		}

		if (destroy)
		{
			if (renderer)
				DestroyImmediate(renderer);
		}
		else
		{
			if (!renderer)
			{
				var go = new GameObject(terrain.name + "_TerrainPrettifierRenderer");
				go.hideFlags = HideFlags.HideAndDontSave;
				var meshFilter = go.AddComponent<MeshFilter>();
				meshFilter.mesh = unitCube;
				renderer = go.AddComponent<MeshRenderer>();
				renderer.sharedMaterial = previewMaterial;
			}
		}
	}
	#endregion
}
