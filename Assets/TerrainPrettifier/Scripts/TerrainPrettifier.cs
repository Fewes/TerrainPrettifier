using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TerrainPrettifier : MonoBehaviour
{
	public bool heightmapFoldout = true;
	public bool satelliteFoldout = true;
	public bool previewFoldout   = true;

	Terrain _terrain;
	public Terrain terrain
	{
		get
		{
			if (!_terrain)
				_terrain = GetComponent<Terrain>();
			return _terrain;
		}
	}

	public Texture2D satellite;

	public bool heightmapProcessorEnabled	= true;

	public bool satelliteProcessorEnabled	= true;

	[System.Serializable]
	public class Denoiser
	{
		public bool		enabled		= true;
		[Range(0, 4)]
		public float	strength	= 2f;
	}

	public Denoiser denoiser = new Denoiser();

	[System.Serializable]
	public class RidgeMaker
	{
		public bool		enabled		= true;
		[Range(0, 100)]
		public float	strength	= 5f;
		[Range(0, 1)]
		public float	sharpness	= 0.5f;
	}

	public RidgeMaker ridges = new RidgeMaker();

	[System.Serializable]
	public class Erosion
	{
		public bool		enabled			= true;
		[Range(0, 10)]
		public float	strength		= 0.22f;
		[Range(1, 12)]
		public int		octaves			= 5;
		[Range(0, 1)]
		public float	frequency		= 0.15f;
		[Range(0, 1)]
		public float	slopeMask		= 0.02f;
		[Range(0, 1)]
		public float	slopeSharpness	= 0.75f;
	}

	public Erosion erosion = new Erosion();

	[System.Serializable]
	public class Renderer
	{
		[Range(0, 360)]
		public float	sunAzimuth	= 45;
		[Range(0, 90)]
		public float	sunAltitude	= 15;
		[Range(0, 10)]
		public float	exposure	= 1;

		public bool		lighting	= true;

		public bool		shadows		= true;

		public bool		albedo		= true;
		[Range(0, 1)]
		public float	maxSlope	= 0.5f;
		[Range(128, 1024)]
		public int		sampleCount	= 512;
	}

	public new Renderer renderer = new Renderer();

	[System.Serializable]
	public class ShadowRemoval
	{
		public bool		enabled				= true;
		[ColorUsage(false)]
		public Color	shadowColor			= Color.black;
		[Range(1, 64)]
		public int		passes				= 16;
		[Range(0, 1)]
		public float	luminanceThreshold	= 0.5f;
		[Range(0, 1)]
		public float	saturationThreshold	= 0.5f;
		[Range(0, 1)]
		public float	edge				= 0.1f;
		[Range(0, 64)]
		public float	radius				= 1.0f;
	}

	public ShadowRemoval shadowRemoval = new ShadowRemoval();

	[System.Serializable]
	public class CavityGenerator
	{
		public bool		enabled		= true;
		[Range(0, 2)]
		public float	intensity	= 0.25f;
		[Range(1, 16)]
		public float	radius		= 1f;
	}

	public CavityGenerator cavityGenerator = new CavityGenerator();
}
