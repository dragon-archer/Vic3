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
	                                
	float TonemapShoulderStrength;	//108
	float TonemapLinearStrength;	//112
	float TonemapLinearAngle;		//116
	float TonemapToeStrength;		//120
	float TonemapToeNumerator;		//124
	float TonemapToeDenominator;	//128	
	float TonemapLinearWhite;		//132
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
		
			return ToGamma( inColor );
		}

	]]
}

