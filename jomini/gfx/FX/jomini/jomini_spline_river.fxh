Includes = {
	"jomini/jomini_spline.fxh"
}

# Please note that this file is for the spline system
# ( thus it has nothing to do with "border splines" )

ConstantBuffer( JominiRiver )
{
	float _TextureUvScale;
	float _FlowNormalUvScale;
	float _FlowNormalSpeed;
	float _RiverFoamFactor;
	float _NoiseScale;
	float _NoiseSpeed;
	float _FlattenMult;

	float _OceanFadeRate;
	float _BankAmount;
	float _BankFade;
	float _Depth;
	float _DepthWidthPower;
	float _DepthFakeFactor;
	int _ParallaxIterations;
}

PixelShader =
{
	struct SAnchorData
	{
		float _Depth;
	};

	BindlessResources
	{
		StructuredBufferTexture { SAnchorData }
	};

	Code
	[[
#if !defined( PDX_ENABLE_SPLINE_GRAPHICS1 )
		#define FADE_IN_DISTANCE 2.0
		#define FADE_OUT_DISTANCE 2.0

		float CalcEdgeTransparency( VS_SPLINE_OUTPUT Input )
		{
			float SegmentEnd = Input.MaxU;
			
			float InTransparency = clamp(Input.UV.x / FADE_IN_DISTANCE, 0, 1);
			float OutTransparency = 1.0 - clamp((SegmentEnd - Input.UV.x - 2) / FADE_OUT_DISTANCE, 0, 1);

			float Transparency =  clamp(InTransparency - OutTransparency, 0, 1);
			Transparency *= Transparency;

			return Transparency;
		}
#endif

#define DEFAULT_ANCHOR_DEPTH -1.0f

		float GetInterpolatedAnchorDepth( VS_SPLINE_OUTPUT Input )
		{
#if !defined( PDX_ENABLE_SPLINE_GRAPHICS1 ) && !defined( PDX_DIRECTX_11 )
			StructuredBuffer<SAnchorData> AnchorData = GetBindlessStructuredBufferTextureUniform<SAnchorData>( _AnchorDataHandle );

			float AnchorDepth1 = AnchorData[ Input.DataIndex1 ]._Depth;
			float AnchorDepth2 = AnchorData[ Input.DataIndex2 ]._Depth;

			if( AnchorDepth1 == DEFAULT_ANCHOR_DEPTH )
			{
				AnchorDepth1 = _Depth;
			}

			if( AnchorDepth2 == DEFAULT_ANCHOR_DEPTH )
			{
				AnchorDepth2 = _Depth;
			}

			return lerp( AnchorDepth1, AnchorDepth2, Input.DataDelta );
#else
			return _Depth;
#endif
		}

		float CalcDepth( float2 UV, VS_SPLINE_OUTPUT Input )
		{
			return GetInterpolatedAnchorDepth( Input ) * ( 1.0f - pow( cos( ( UV.y ) * 2.0f * PI ) * 0.5f + 0.5f, 2.0f ) );
		}

		float CalcDepth( float2 UV, VS_SPLINE_OUTPUT Input, PdxTextureSampler2D BottomNormal )
		{
			float ShoreAmount = 1.0f + _BankAmount;
			float CenterOffset = ( ShoreAmount - 1.0f ) / 2.0f;

			float Depth = GetInterpolatedAnchorDepth( Input ) * ( 1.0f - pow( cos( clamp( UV.y * ShoreAmount - CenterOffset, 0.0f, 1.0f ) * 2.0f * PI ) * 0.5f + 0.5f, _DepthWidthPower ) );

			float SampledDepth = 1.0f - PdxTex2D( BottomNormal, UV ).b;
			Depth *= SampledDepth;
			Depth = clamp( Depth, 0.001f, 10.0f );	// Some functions do not like 0 depth

			return Depth;
		}
	]]

}
