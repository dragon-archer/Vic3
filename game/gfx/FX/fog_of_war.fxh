Includes = {
	#"fog_of_war_impl.fxh"
	"jomini/jomini.fxh"
	"jomini/jomini_fog_of_war.fxh"
	"cw/utility.fxh"
}

PixelShader = {
	ConstantBuffer( GameFogOfWar )
	{
		float4 _FoWShadowColor;
		float4 _FoWCloudsColor;
		float4 _FoWCloudsColorSecondary;

		float _FoWCloudsColorGradientMin;
		float _FoWCloudsColorGradientMax;

		float _FoWCloudHeight;

		float _FoWShadowMult;
		float _FoWShadowTexStart;
		float _FoWShadowTexStop;

		float _FoWShadowAlphaStart;
		float _FoWShadowAlphaStop;

		float _FowShadowLayer1Min;
		float _FowShadowLayer1Max;
		float _FowShadowLayer2Min;
		float _FowShadowLayer2Max;
		float _FowShadowLayer3Min;
		float _FowShadowLayer3Max;

		float _FoWCloudsAlphaStart;
		float _FoWCloudsAlphaStop;

		float _FoWMasterStart;
		float _FoWMasterStop;
		int _FoWMasterUVTiling;
		float _FoWMasterUVRotation;
		float2 _FoWMasterUVScale;
		float2 _FoWMasterUVSpeed;

		float _FoWLayer1Min;
		float _FoWLayer1Max;
		int _FoWLayer1Tiling;

		float _FoWLayer2Min;
		float _FoWLayer2Max;
		float _FoWLayer2Balance;
		int _FoWLayer2Tiling;

		float _FoWLayer3Min;
		float _FoWLayer3Max;
		float _FoWLayer3Balance;
		int _FoWLayer3Tiling;

		float _FoWShowAlphaMask;

		float2 _FoWLayer1Speed;
		float2 _FoWLayer2Speed;
		float2 _FoWLayer3Speed;

	}
	
	#// Fog of war fade out on close zoom
	Code [[
		#define FowFadeEnd			150.0
		#define FowFadeStart		101.0
	]]

	TextureSampler FogOfWarAlpha
	{
		Ref = JominiFogOfWar
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler FogOfWarNoise
	{
		Ref = GameFogOfWarNoise
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	Code [[
		float SampleFowNoiseLowSpec( in float3 Coordinate )
		{
				// Uv tiling
				float2 MasterUVTiling = _FoWMasterUVTiling * Coordinate.xz * InverseWorldSize;
				MasterUVTiling.x *= _FoWMasterUVScale.x;
				MasterUVTiling.y *= _FoWMasterUVScale.y;
				float2 UV = MasterUVTiling * _FoWLayer1Tiling;

				// Animation
				float2 AnimUV = float2(_FoWLayer1Speed.x * _FoWMasterUVSpeed.x, _FoWLayer1Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				UV += AnimUV * _FoWMasterUVScale;

				// Layer sample
				float Layer1 = PdxTex2D( FogOfWarNoise, UV ).r;
				Layer1 = smoothstep( _FoWLayer1Min, _FoWLayer1Max, Layer1 );

				// Detail noise blending
				float Cloud = smoothstep( _FoWLayer1Min, _FoWLayer1Max, Layer1 );
				return Cloud;
		}

		float SampleFowNoise( in float3 Coordinate )
		{

				// Uv tiling and animation
				float2 MasterUVTiling = _FoWMasterUVTiling * Coordinate.xz * InverseWorldSize;

				// Scale
				MasterUVTiling.x *= _FoWMasterUVScale.x;
				MasterUVTiling.y *= _FoWMasterUVScale.y;

				float2 UV = MasterUVTiling * _FoWLayer1Tiling;
				float2 UV2 = MasterUVTiling * _FoWLayer2Tiling;
				float2 UV3 = MasterUVTiling * _FoWLayer3Tiling;

				// Animation
				float2 AnimUV = float2(_FoWLayer1Speed.x * _FoWMasterUVSpeed.x, _FoWLayer1Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				float2 AnimUV2 = float2(_FoWLayer2Speed.x * _FoWMasterUVSpeed.x, _FoWLayer2Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				float2 AnimUV3 = float2(_FoWLayer3Speed.x * _FoWMasterUVSpeed.x, _FoWLayer3Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				UV += AnimUV * _FoWMasterUVScale;
				UV2 += AnimUV2 * _FoWMasterUVScale;
				UV3 +=AnimUV3 * _FoWMasterUVScale;

				// Layers sample
				float Layer1 = PdxTex2D( FogOfWarNoise, UV ).g;
				float Layer2 = PdxTex2D( FogOfWarNoise, UV2 ).g;
				float Layer3 = PdxTex2D( FogOfWarNoise, UV3 ).g;

				// Layers min/max adjustment
				Layer1 = smoothstep( _FoWLayer1Min, _FoWLayer1Max, Layer1 );
				Layer2 = smoothstep( _FoWLayer2Min, _FoWLayer2Max, Layer2 );
				Layer3 = smoothstep( _FoWLayer3Min, _FoWLayer3Max, Layer3 );

				// Detail noise blending
				float Cloud = Overlay(Layer1, Layer2, _FoWLayer2Balance );
				Cloud = Overlay(Cloud, Layer3, _FoWLayer3Balance );

				return Cloud;
		}

		float SampleFowReflection( in float2 Coordinate )
		{
				// Uv tiling and animation
				float2 MasterUVTiling = _FoWMasterUVTiling * Coordinate * InverseWorldSize;

				// Scale
				MasterUVTiling.x *= _FoWMasterUVScale.x;
				MasterUVTiling.y *= _FoWMasterUVScale.y;

				float2 UV = MasterUVTiling * _FoWLayer1Tiling;
				float2 UV2 = MasterUVTiling * _FoWLayer2Tiling;
				float2 UV3 = MasterUVTiling * _FoWLayer3Tiling;

				// Animation
				float2 AnimUV = float2(_FoWLayer1Speed.x * _FoWMasterUVSpeed.x, _FoWLayer1Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				float2 AnimUV2 = float2(_FoWLayer2Speed.x * _FoWMasterUVSpeed.x, _FoWLayer2Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				float2 AnimUV3 = float2(_FoWLayer3Speed.x * _FoWMasterUVSpeed.x, _FoWLayer3Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				UV += AnimUV * _FoWMasterUVScale;
				UV2 += AnimUV2 * _FoWMasterUVScale;
				UV3 +=AnimUV3 * _FoWMasterUVScale;

				// Layers sample
				float Layer1 = PdxTex2D( FogOfWarNoise, UV ).g;
				float Layer2 = PdxTex2D( FogOfWarNoise, UV2 ).g;
				float Layer3 = PdxTex2D( FogOfWarNoise, UV3 ).g;

				// Layers min/max adjustment
				Layer1 = smoothstep( _FoWLayer1Min, _FoWLayer1Max, Layer1 );
				Layer2 = smoothstep( _FoWLayer2Min, _FoWLayer2Max, Layer2 );
				Layer3 = smoothstep( _FoWLayer3Min, _FoWLayer3Max, Layer3 );

				// Detail noise blending
				float Cloud = Overlay(Layer1, Layer2, _FoWLayer2Balance );
				Cloud = Overlay(Cloud, Layer3, _FoWLayer3Balance );

				return Cloud;
		}

		float SampleFowNoiseShadow( in float3 Coordinate )
		{

				// Uv tiling and animation
				float2 MasterUVTiling = _FoWMasterUVTiling * Coordinate.xz * InverseWorldSize;

				// Scale
				MasterUVTiling.x *= _FoWMasterUVScale.x;
				MasterUVTiling.y *= _FoWMasterUVScale.y;

				float2 UV = MasterUVTiling * _FoWLayer1Tiling;
				float2 UV2 = MasterUVTiling * _FoWLayer2Tiling;
				float2 UV3 = MasterUVTiling * _FoWLayer3Tiling;

				// Animation
				float2 AnimUV = float2(_FoWLayer1Speed.x * _FoWMasterUVSpeed.x, _FoWLayer1Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				float2 AnimUV2 = float2(_FoWLayer2Speed.x * _FoWMasterUVSpeed.x, _FoWLayer2Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				float2 AnimUV3 = float2(_FoWLayer3Speed.x * _FoWMasterUVSpeed.x, _FoWLayer3Speed.y * _FoWMasterUVSpeed.y) * FogOfWarTime * 0.01f;
				UV += AnimUV * _FoWMasterUVScale;
				UV2 += AnimUV2 * _FoWMasterUVScale;
				UV3 +=AnimUV3 * _FoWMasterUVScale;

				// Layers sample
				float Layer1 = PdxTex2D( FogOfWarNoise, UV ).a;
				float Layer2 = PdxTex2D( FogOfWarNoise, UV2 ).a;
				float Layer3 = PdxTex2D( FogOfWarNoise, UV3 ).a;

				// Layers min/max adjustment
				Layer1 = LevelsScan( Layer1, _FowShadowLayer1Min, _FowShadowLayer1Max);
				Layer2 = LevelsScan( Layer2, _FowShadowLayer2Min, _FowShadowLayer2Max);
				Layer3 = LevelsScan( Layer3, _FowShadowLayer3Min, _FowShadowLayer3Max);

				// Detail noise blending
				float Cloud = Overlay(Layer1, Layer2 );
				Cloud = Overlay(Cloud, Layer3 );

				return Cloud;
		}

		float3 GameApplyFogOfWar( in float3 Color, in float3 Coordinate, float ShadowMultiplier = 1.0 )
		{
			#ifdef PDX_DEBUG_FOW_OFF
				return Color;
			#endif

			#ifdef JOMINI_DISABLE_FOG_OF_WAR
				return Color;
			#endif


			// Alpha fade
			float FadeStart = FowFadeEnd - FowFadeStart;
			float DistanceBlend = FadeStart - CameraPosition.y + FowFadeStart;
			DistanceBlend = RemapClamped( DistanceBlend, 0.0, FadeStart, 0.0, 1.0 );

			float Alpha = 1.0 - PdxTex2D( FogOfWarAlpha, Coordinate.xz * InverseWorldSize ).r;
			Alpha = lerp( Alpha, 0.0, DistanceBlend );
			
			#ifdef PDX_DEBUG_FOW_MASK
				return float4( Alpha.rrr, 1.0f );
			#endif
			if( _FoWShowAlphaMask > 0.0f ) 
			{
				return vec3( 1.0f - Alpha );
			}

			float ShadowAlpha = smoothstep( _FoWShadowAlphaStart, _FoWShadowAlphaStop, Alpha ) * _FoWShadowColor.a;
			float CloudsAlpha = smoothstep( _FoWCloudsAlphaStart, _FoWCloudsAlphaStop, Alpha ) * _FoWCloudsColor.a;

			// Paralax offset
			float3 ToCam = normalize( CameraPosition - Coordinate );
			float ParalaxDist = ( _FoWCloudHeight - Coordinate.y ) / ToCam.y;
			float3 ParalaxCoord = Coordinate + ToCam * ParalaxDist;

			// Sun shadow offset
			float ShadowCordDist = ( _FoWCloudHeight - Coordinate.y ) / ToSunDir.y;
			Coordinate =  Coordinate + ToSunDir * ShadowCordDist;

			// Cloud and shadow texture
			#ifdef LOW_QUALITY_SHADERS
				float CloudTex = smoothstep( _FoWMasterStart, _FoWMasterStop, SampleFowNoiseLowSpec( ParalaxCoord ) );
				float ShadowTex = smoothstep( _FoWShadowTexStart, _FoWShadowTexStop, SampleFowNoiseLowSpec( Coordinate ) );
			#else
				float CloudTex = smoothstep( _FoWMasterStart, _FoWMasterStop, SampleFowNoise( ParalaxCoord ) );
				float ShadowTex = smoothstep( _FoWShadowTexStart, _FoWShadowTexStop, SampleFowNoiseShadow( Coordinate ) );
			#endif

			// Apply Fog of war and cloud shadow
			float3 FinalColor = lerp( Color, _FoWShadowColor.rgb, _FoWShadowMult * ShadowAlpha );					// Fow darkness
			FinalColor = lerp( FinalColor, _FoWShadowColor.rgb, _FoWShadowMult * ShadowTex * ShadowMultiplier );	// Cloud Shadow

			// Apply clouds
			float GradientControl = smoothstep( _FoWCloudsColorGradientMin, _FoWCloudsColorGradientMax, CloudTex );
			float3 CloudsColor = lerp( _FoWCloudsColorSecondary.rgb, _FoWCloudsColor.rgb, GradientControl );
			FinalColor = lerp( FinalColor, CloudsColor, CloudTex * CloudsAlpha );

			return FinalColor;
		}

		float3 GameApplyFogOfWarMultiSampled( in float3 Color, in float3 Coordinate, PdxTextureSampler2D FogOfWarAlphaMask )
		{
			#ifdef PDX_DEBUG_FOW_OFF
			return Color;
			#endif

			float Alpha = GetFogOfWarAlphaMultiSampled( Coordinate, FogOfWarAlphaMask );
			#ifdef PDX_DEBUG_FOW_MASK
			return float4( Alpha.rrr, 1.0f );
			#endif

			if( _FoWShowAlphaMask > 0.0f ) 
			{
				return vec3( 1.0f - Alpha );
			}
			return FogOfWarBlend( Color, Alpha );
		}

		// Post process
		float4 GameApplyFogOfWar( in float3 WorldSpacePos, PdxTextureSampler2D FogOfWarAlphaMask )
		{
			#ifdef PDX_DEBUG_FOW_OFF
			return vec4(0);
			#endif

			float Alpha = GetFogOfWarAlpha( WorldSpacePos, FogOfWarAlphaMask );

			#ifdef PDX_DEBUG_FOW_MASK
			return float4( Alpha.rrr, 1.0f );
			#endif

			return FOG_OF_WAR_BLEND_FUNCTION( Alpha );
		}

		#undef ApplyFogOfWar
		#undef ApplyFogOfWarMultiSampled
		#define ApplyFogOfWar GameApplyFogOfWar
		#define ApplyFogOfWarMultiSampled GameApplyFogOfWarMultiSampled
	]]
}
