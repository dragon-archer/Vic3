Includes = {
	"cw/utility.fxh"
	"cw/fullscreen_vertexshader.fxh"
	"cw/camera.fxh"
}

ConstantBuffer( PdxConstantBuffer1 )
{
	float2 InvDownSampleSize;		//0
	float2 ScreenResolution;		//8
	float2 InvScreenResolution;		//16
	float LumWhite2;				//24
	float FixedExposureValue;		//28	
	float3 HSV;						//32
	float BrightThreshold;			//44
	float3 ColorBalance;			//48
	float Dummy2;					//60	
	float3 LevelsMin;				//64
	float MiddleGrey;				//76
	float3 LevelsMax;				//80
	float Dummy3;					//92
	float3 BloomParams;				//96		

	# Uncharted
	float TonemapShoulderStrength;	//108
	float TonemapLinearStrength;	//112
	float TonemapLinearAngle;		//116
	float TonemapToeStrength;		//120
	float TonemapToeNumerator;		//124
	float TonemapToeDenominator;	//128	
	float TonemapLinearWhite;		//132

	# AgX
	# TODO: Find a better way to reuse unused values...
	float AgxMiddleGrey;			//136
	float AgxSlope;					//140
	float AgxToePower;				//144
	float AgxShoulderPower;			//148
	float AgxMinEv;					//152
	float AgxMaxEv;					//156
	float AgxSaturation;			//160
};

PixelShader = 
{
	TextureSampler DepthBuffer
	{
		Ref = JominiDepthBuffer
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler DepthBufferMultiSampled
	{
		Ref = JominiDepthBufferMultiSampled
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		MultiSampled = yes
	}

	Code
	[[
		float SampleDepthBuffer( float2 UV, float2 Resolution )
		{
		#ifdef MULTI_SAMPLED
			int2 PixelIndex = int2( UV * Resolution );
			float Depth = PdxTex2DMultiSampled( DepthBufferMultiSampled, PixelIndex, 0 ).r;
		#else
			float Depth = PdxTex2DLod0( DepthBuffer, UV ).r;
		#endif
			return Depth;
		}
		float GetViewSpaceDepth( float2 UV, float2 Resolution )
		{
			float Depth = SampleDepthBuffer( UV, Resolution );
			return CalcViewSpaceDepth( Depth );
		}

		// Exposure 
		static const float3 LUMINANCE_VECTOR = float3( 0.2125, 0.7154, 0.0721 );
		static const float CubeSize = 32.0;
		float3 Exposure(float3 inColor)
		{
		#ifdef EXPOSURE_ADJUSTED
			float AverageLuminance = PdxTex2DLod0(AverageLuminanceTexture, vec2(0.5)).r;
			return inColor * (MiddleGrey / AverageLuminance);
		#endif

		#ifdef EXPOSURE_AUTO_KEY_ADJUSTED
			float AverageLuminance = PdxTex2DLod0(AverageLuminanceTexture, vec2(0.5)).r;
			float AutoKey = 1.13 - (2.0 / (2.0 + log10(AverageLuminance + 1.0)));
			return inColor * (AutoKey / AverageLuminance);
		#endif

		#ifdef EXPOSURE_FIXED
			return inColor * FixedExposureValue;
		#endif
		
			return inColor;
		}


		// Tonemapping

		// Uncharted 2 - John Hable 2010
		float3 HableFunction(float3 color)
		{
			float a = TonemapShoulderStrength;
			float b = TonemapLinearStrength;
			float c = TonemapLinearAngle;
			float d = TonemapToeStrength;
			float e = TonemapToeNumerator;
			float f = TonemapToeDenominator;
			
			return color =  ( ( color * ( a * color + c * b ) + d * e ) / ( color * ( a * color + b ) + d * f ) ) - e / f;
		}
		float3 ToneMapUncharted2(float3 color)
		{
			float ExposureBias = 2.0;
			float3 curr = HableFunction( ExposureBias * color );

			float W = TonemapLinearWhite;
			float3 whiteScale = 1.0 / HableFunction( vec3 ( W ) );
			return saturate( curr * whiteScale );
		}

		// Filmic - John Hable
		float3 ToneMapFilmic_Hable(float3 color)
		{
			color = max( vec3( 0 ), color - 0.004f );
			color = saturate( ( color * (6.2 * color + 0.5) ) / ( color * (6.2 * color + 1.7 ) + 0.06 ) );
			return color;
		}
		
		// Aces filmic - Krzysztof Narkowicz
		float3 ToneMapAcesFilmic_Narkowicz(float3 color)
		{
			float a = 2.51f;
			float b = 0.03f;
			float c = 2.43f;
			float d = 0.89f;
			float e = 0.14f;

			color = saturate( ( color * ( a * color + b ) ) / ( color * ( c * color + d ) + e ) );
			return color;
		}


		// Aces filmic - Stephen Hill
		float3x3 SHInputMat()
		{
			return Create3x3(
				float3( 0.59719, 0.35458, 0.04823 ),
				float3( 0.07600, 0.90834, 0.01566 ),
				float3( 0.02840, 0.13383, 0.83777 ) );
		}
		float3x3 SHOutputMat()
		{
			return Create3x3(
				float3( 1.60475, -0.53108, -0.07367 ),
				float3( -0.10208,  1.10813, -0.00605 ),
				float3( -0.00327, -0.07276,  1.07602 ) );
		}
		float3 RRTAndODTFit( float3 v )
		{
			float3 a = v * ( v + 0.0245786f ) - 0.000090537f;
			float3 b = v * ( 0.983729f * v + 0.4329510f ) + 0.238081f;
			return a / b;
		}
		float3 ToneMapAcesFilmic_Hill( float3 color )
		{
			float ExposureBias = 1.8;
			color = color * ExposureBias;

			color = mul( SHInputMat(), color);
			color = RRTAndODTFit( color );
			color = mul( SHOutputMat(), color);

			return saturate( color );
		}

		// AgX
		// Implementation based on https://iolite-engine.com/blog_posts/minimal_agx_implementation

		// Mean error^2: 3.6705141e-06
		float3 agxDefaultContrastApprox(float3 x)
		{
			float3 x2 = x * x;
			float3 x4 = x2 * x2;

			return + 15.5	* x4 * x2
				- 40.14		* x4 * x
				+ 31.96		* x4
				- 6.868		* x2 * x
				+ 0.4298	* x2
				+ 0.1191	* x
				- 0.00232;
		}

		float3 AgxImpl_Base(float3 color)
		{
			const float3x3 agx_mat = float3x3(
				0.842479062253094,  0.0423282422610123, 0.0423756549057051,
				0.0784335999999992, 0.878468636469772,  0.0784336,
				0.0792237451477643, 0.0791661274605434, 0.879142973793104
			);

			const float min_ev = -12.47393f;
			const float max_ev = 4.026069f;

			
			// Input transform (inset)
			color = mul(agx_mat, color);

			// Log2 space encoding
			color = clamp(log2(color), min_ev, max_ev);
			color = (color - min_ev) / (max_ev - min_ev);

			// Apply sigmoid function approximation
			color = agxDefaultContrastApprox(color);

			return color;
		}

		float3 AgxImpl_Eotf(float3 color)
		{
			const float3x3 agx_mat_inv = float3x3(
				 1.19687900512017,   -0.0528968517574562, -0.0529716355144438,
				-0.0980208811401368,  1.15190312990417,   -0.0980434501171241,
				-0.0990297440797205, -0.0989611768448433,  1.15107367264116
			);
				
			// Inverse input transform (outset)
			color = mul(agx_mat_inv, color);
			
			// sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
			// NOTE: We're linearizing the output here. Comment/adjust when
			// *not* using a sRGB render target
			color = pow(color, float3(2.2, 2.2, 2.2));

			return color;
		}

		float3 ToneMapAgx(float3 color)
		{
			color = AgxImpl_Base(color);
			color = AgxImpl_Eotf(color);
			return color;
		}

		///////////////////////////////////////////////////////////////////////
		// AgX with custom input
		///////////////////////////////////////////////////////////////////////

		// https://www.shadertoy.com/view/dtSGD1

		float3 OpenDomainToNormalizedLog2( float3 OpenDomain, float MiddleGrey, float MinEv, float MaxEv )
		{
			float TotalExposure = MaxEv - MinEv;

			float3 OutputLog = clamp( log2( OpenDomain / MiddleGrey ), MinEv, MaxEv );

			return ( OutputLog - MinEv ) / TotalExposure;
		}


		float AgXScale( float XPivot, float YPivot, float SlopePivot, float Power )
		{
			return pow( pow( ( SlopePivot * XPivot ), -Power ) * ( pow( ( SlopePivot * ( XPivot / YPivot ) ), Power ) - 1.0 ), -1.0 / Power );
		}

		float AgXHyperbolic( float X, float Power )
		{
			return X / pow( 1.0 + pow( X, Power ), 1.0f / Power );
		}

		float AgXTerm( float X, float XPivot, float SlopePivot, float Scale )
		{
			return ( SlopePivot * ( X - XPivot ) ) / Scale;
		}

		float AgXCurve( float X, float XPivot, float YPivot, float SlopePivot, float ToePower, float ShoulderPower, float Scale )
		{
			if( Scale < 0.0f )
			{
				return Scale * AgXHyperbolic( AgXTerm( X, XPivot, SlopePivot, Scale ), ToePower ) + YPivot;
			}
			return Scale * AgXHyperbolic( AgXTerm( X, XPivot, SlopePivot, Scale ), ShoulderPower ) + YPivot;
		}

		float AgXFullCurve( float X, float XPivot, float YPivot, float SlopePivot, float ToePower, float ShoulderPower )
		{
			float ScaleXPivot = X >= XPivot ? 1.0f - XPivot : XPivot;
			float ScaleYPivot = X >= XPivot ? 1.0f - YPivot : YPivot;

			float ToeScale = AgXScale( ScaleXPivot, ScaleYPivot, SlopePivot, ToePower );
			float ShoulderScale = AgXScale( ScaleXPivot, ScaleYPivot, SlopePivot, ShoulderPower );

			float Scale = X >= XPivot ? ShoulderScale : -ToeScale;

			return AgXCurve( X, XPivot, YPivot, SlopePivot, ToePower, ShoulderPower, Scale );
		}

		float3 ToneMapAgx2( float3 Color )
		{
			float XPivot = abs( AgxMinEv ) / ( AgxMaxEv - AgxMinEv );
			float YPivot = 0.5f;

			float3 LogV = OpenDomainToNormalizedLog2( Color, AgxMiddleGrey, AgxMinEv, AgxMaxEv );

			float OutputR = AgXFullCurve( LogV.r, XPivot, YPivot, AgxSlope, AgxToePower, AgxShoulderPower );
			float OutputG = AgXFullCurve( LogV.g, XPivot, YPivot, AgxSlope, AgxToePower, AgxShoulderPower );
			float OutputB = AgXFullCurve( LogV.b, XPivot, YPivot, AgxSlope, AgxToePower, AgxShoulderPower );

			Color = clamp( float3( OutputR, OutputG, OutputB ), 0.0, 1.0 );

			float3 LuminanceWeight = float3( 0.2126729f,  0.7151522f,  0.0721750f );
			float LuminancedColor = dot( Color, LuminanceWeight );
			float3 Desaturation = float3( LuminancedColor, LuminancedColor, LuminancedColor );
			Color = lerp( Desaturation, Color, AgxSaturation );
			Color = clamp( Color, 0.f, 1.f );

			return Color;
		}

		///////////////////////////////////////////////////////////////////////
		// Common start
		///////////////////////////////////////////////////////////////////////

		float3 ToneMap(float3 inColor)
		{
		#ifdef TONEMAP_REINHARD
			float3 retColor = inColor / (1.0 + inColor);
			return ToGamma( saturate( retColor ) );
		#endif

		#ifdef TONEMAP_REINHARD_MODIFIED
			float Luminance = dot( inColor, LUMINANCE_VECTOR );
			float LDRLuminance = ( Luminance * (1.0 + ( Luminance / LumWhite2 ) ) ) / ( 1.0 + Luminance );
			float vScale = LDRLuminance / Luminance;
			return ToGamma( saturate( inColor * vScale ) );
		#endif

		#ifdef TONEMAP_FILMIC_HABLE
			return ToneMapFilmic_Hable( inColor );
		#endif

		#ifdef TONEMAP_FILMICACES_NARKOWICZ
			return ToGamma( ToneMapAcesFilmic_Narkowicz( inColor ) );
		#endif

		#ifdef TONEMAP_FILMICACES_HILL
			return ToGamma( ToneMapAcesFilmic_Hill( inColor ) );
		#endif

		#ifdef TONEMAP_UNCHARTED
			return ToGamma( ToneMapUncharted2( inColor ) );
		#endif

		#ifdef TONEMAP_AGX
			// return ToGamma( ToneMapAgx( inColor ) );
			return ToneMapAgx2( inColor );
		#endif
		
			return ToGamma( inColor );
		}

	]]
}

