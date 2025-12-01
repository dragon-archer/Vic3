Includes = {
	"jomini/posteffect_base.fxh"
}


VertexStruct VS_OUTPUT_SAMPLER
{
    float4 position	: PDX_POSITION;
	float2 uv		: TEXCOORD0;
};


ConstantBuffer( PdxConstantBuffer2 )
{
	float2 InvBloomSize;
	float2 UVScale;
};


VertexShader =
{
	MainCode VertexShader
	{
		Input = "VS_INPUT_FULLSCREEN"
		Output = "VS_OUTPUT_SAMPLER"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_SAMPLER VertexOut;
				VertexOut.position = float4( Input.position, 0.0, 1.0 );

				VertexOut.uv = Input.position.xy * 0.5 + 0.5;
				VertexOut.uv.y = 1.0 - VertexOut.uv.y;
				
				VertexOut.uv *= UVScale;

				return VertexOut;
			}
		]]
	}
}

PixelShader =
{
	TextureSampler Source
	{
		Ref = PdxTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	
	Code
	[[			

		float KarisAverage( float4 col )
		{
			float luma = dot(LUMINANCE_VECTOR, col.rgb) * 0.25f; //The multiplication is because the color input is actually 4 colours combined!
			return 1.0f / (1.0f + luma);
		}
		
		float Max3(float3 s)
		{
			return max(max(s.x, s.y), s.z);
		}
			
		// [Jimenez14] (https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/)
		//	https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom
		// . . . . . . .
		// . A . B . C .
		// . . D . E . .
		// . F . G . H .
		// . . I . J . .
		// . K . L . M .
		// . . . . . . .
		float4 DownsampleBox13Tap(PdxTextureSampler2D source, float2 uv, float2 texelSize)
		{			
			float4 A = PdxTex2DLod0( source, uv + texelSize * float2( -1.0f, -1.0f ) );
			float4 B = PdxTex2DLod0( source, uv + texelSize * float2(  0.0f, -1.0f ) );
			float4 C = PdxTex2DLod0( source, uv + texelSize * float2(  1.0f, -1.0f ) );
			
			float4 K = PdxTex2DLod0( source, uv + texelSize * float2( -1.0f,  1.0f ) );
			float4 L = PdxTex2DLod0( source, uv + texelSize * float2(  0.0f,  1.0f ) );
			float4 M = PdxTex2DLod0( source, uv + texelSize * float2(  1.0f,  1.0f ) );
			
			float4 F = PdxTex2DLod0( source, uv + texelSize * float2( -1.0f,  0.0f ) );
			float4 G = PdxTex2DLod0( source, uv + texelSize * float2(  0.0f,  0.0f ) );
			float4 H = PdxTex2DLod0( source, uv + texelSize * float2(  1.0f,  0.0f ) );
			
			float4 D = PdxTex2DLod0( source, uv + texelSize * float2( -0.5f, -0.5f ) );
			float4 E = PdxTex2DLod0( source, uv + texelSize * float2(  0.5f, -0.5f ) );
			float4 I = PdxTex2DLod0( source, uv + texelSize * float2( -0.5f,  0.5f ) );
			float4 J = PdxTex2DLod0( source, uv + texelSize * float2(  0.5f,  0.5f ) );
			
			// https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom
			float4 o = G * 0.125f;
			o += ( A + C + K + M ) * 0.03125f;
			o += ( B + H + F + L ) * 0.0625f;
			o += ( D + E + I + J ) * 0.125f;
			
			//-------
			//float br = Max3(G.rgb);			
			//if (br < 1.0f)
			//	return float4(0,0,0,1);			
			//return G;
			//-------
			
			return o;
		}
		
		float4 DownsampleBox13TapWithFilter(PdxTextureSampler2D source, float2 uv, float2 texelSize)
		{			
			float4 A = PdxTex2DLod0( source, uv + texelSize * float2( -1.0f, -1.0f ) );
			float4 B = PdxTex2DLod0( source, uv + texelSize * float2(  0.0f, -1.0f ) );
			float4 C = PdxTex2DLod0( source, uv + texelSize * float2(  1.0f, -1.0f ) );
			float4 D = PdxTex2DLod0( source, uv + texelSize * float2( -0.5f, -0.5f ) );
			float4 E = PdxTex2DLod0( source, uv + texelSize * float2(  0.5f, -0.5f ) );
			float4 F = PdxTex2DLod0( source, uv + texelSize * float2( -1.0f,  0.0f ) );
			float4 G = PdxTex2DLod0( source, uv + texelSize * float2(  0.0f,  0.0f ) );
			float4 H = PdxTex2DLod0( source, uv + texelSize * float2(  1.0f,  0.0f ) );
			float4 I = PdxTex2DLod0( source, uv + texelSize * float2( -0.5f,  0.5f ) );
			float4 J = PdxTex2DLod0( source, uv + texelSize * float2(  0.5f,  0.5f ) );
			float4 K = PdxTex2DLod0( source, uv + texelSize * float2( -1.0f,  1.0f ) );
			float4 L = PdxTex2DLod0( source, uv + texelSize * float2(  0.0f,  1.0f ) );
			float4 M = PdxTex2DLod0( source, uv + texelSize * float2(  1.0f,  1.0f ) );
								
			float4 Group0 = ( A + B + F + G ) * 0.125f / 4.0f;
			float4 Group1 = ( B + C + G + H ) * 0.125f / 4.0f;
			float4 Group2 = ( F + G + K + L ) * 0.125f / 4.0f;
			float4 Group3 = ( G + H + L + M ) * 0.125f / 4.0f;
			float4 Group4 = ( D + E + I + J ) * 0.5f   / 4.0f;
						
			Group0 *= KarisAverage( Group0 );
			Group1 *= KarisAverage( Group1 );
			Group2 *= KarisAverage( Group2 );
			Group3 *= KarisAverage( Group3 );
			Group4 *= KarisAverage( Group4 );
			
			float4 Result =  Group0 + Group1 + Group2 + Group3 + Group4;
			
			
			//-------
			//float br = Max3(Result.rgb);			
			//if (br < 1.0f)
			//	return float4(0,0,0,1);			
			//return G;
			//-------
			
			return Result;
		}
		
		// . . . . . . .
		// . . A . B . .
		// . . . . . . .
		// . . C . D . .
		// . . . . . . .
		float4 DownsampleBox4TapWithFilter(PdxTextureSampler2D source, float2 uv, float2 texelSize)
		{			
			float4 d = texelSize.xyxy * float4(-1, -1, +1, +1) * 0.5f;

			float4 A = PdxTex2DLod0( source, uv + d.xy );
			float4 B = PdxTex2DLod0( source, uv + d.zy );
			float4 C = PdxTex2DLod0( source, uv + d.xw );
			float4 D = PdxTex2DLod0( source, uv + d.zw );

			/* Karis's luma weighted average (using brightness instead of luma) */
			float s1w = 1.0 / ( Max3( A.rgb ) + 1.0 );
			float s2w = 1.0 / ( Max3( B.rgb ) + 1.0 );
			float s3w = 1.0 / ( Max3( C.rgb ) + 1.0 );
			float s4w = 1.0 / ( Max3( D.rgb ) + 1.0 );
			
			float one_div_wsum = 1.0 / ( s1w + s2w + s3w + s4w );

			return ( A * s1w + B * s2w + C * s3w + D * s4w ) * one_div_wsum;
		}
		
		float4 DownsampleBox4Tap(PdxTextureSampler2D source, float2 uv, float2 texelSize)
		{			
			float4 d = texelSize.xyxy * float4(-1, -1, +1, +1) * 0.5f;

			float4 A = PdxTex2DLod0( source, uv + d.xy );
			float4 B = PdxTex2DLod0( source, uv + d.zy );
			float4 C = PdxTex2DLod0( source, uv + d.xw );
			float4 D = PdxTex2DLod0( source, uv + d.zw );
			
			//return float4(1,0,0,1);
			
			return ( A + B + C + D ) * (1.0 / 4.0);
		}
		
		// . . . . .
		// . A B C . 
		// . D E F . 
		// . G H I . 
		// . . . . . 
		float4 Upsample9Tent( PdxTextureSampler2D source, float2 uv, float2 radiusInUv )
		{			
			//Note that radiusInUv means that this filter DOES NOT map to pixels, it has "holes" in it.
			//See slide 161 of [Jimenez14]
			//We do reuse the constant buffer variable 'InvBloomSize'
			
			float4 A = PdxTex2DLod0( source, uv + ( radiusInUv * float2( -1.0f, -1.0f ) ) );
			float4 B = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  0.0f, -1.0f ) ) );
			float4 C = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  1.0f, -1.0f ) ) );
																					  
			float4 D = PdxTex2DLod0( source, uv + ( radiusInUv * float2( -1.0f,  0.0f ) ) );
			float4 E = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  0.0f,  0.0f ) ) );
			float4 F = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  1.0f,  0.0f ) ) );
																					  
			float4 G = PdxTex2DLod0( source, uv + ( radiusInUv * float2( -1.0f,  1.0f ) ) );
			float4 H = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  0.0f,  1.0f ) ) );
			float4 I = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  1.0f,  1.0f ) ) );
		
			//-------
			//return E;
			//-------
			
			float4 o = E * 4.0f / 16.0f;
			o += ( B + D + F + H ) * 2.0f / 16.0f;
			o += ( A + C + G + I ) * 1.0f / 16.0f;
						
			return o;
		}
		
		float4 Upsample4Tent( PdxTextureSampler2D source, float2 uv, float2 radiusInUv )
		{			
			//Note that radiusInUv means that this filter DOES NOT map to pixels, it has "holes" in it.
			//See slide 161 of [Jimenez14]
			//We do reuse the constant buffer variable 'InvBloomSize'
			
			float4 A = PdxTex2DLod0( source, uv + ( radiusInUv * float2( -1.0f, -1.0f ) ) );
			float4 C = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  1.0f, -1.0f ) ) );
			
			float4 G = PdxTex2DLod0( source, uv + ( radiusInUv * float2( -1.0f,  1.0f ) ) );
			float4 I = PdxTex2DLod0( source, uv + ( radiusInUv * float2(  1.0f,  1.0f ) ) );		

											
			return (A + C + G + I) * (1.0 / 4.0);
		}
	
	]]
	
	MainCode upsample_high_quality
	{
		Input = "VS_OUTPUT_SAMPLER"
		Output = "PDX_COLOR"
		Code
		[[					
			PDX_MAIN
			{
				return float4(Upsample9Tent( Source, Input.uv, InvBloomSize ).rgb, 1.0);
			}
		]]
	}
	
	MainCode upsample_low_quality
	{
		Input = "VS_OUTPUT_SAMPLER"
		Output = "PDX_COLOR"
		Code
		[[					
			PDX_MAIN
			{
				return float4(Upsample4Tent( Source, Input.uv, InvBloomSize ).rgb, 1.0);
			}
		]]
	}
	
	MainCode downsample_high_quality
	{
		Input = "VS_OUTPUT_SAMPLER"
		Output = "PDX_COLOR"
		Code
		[[		
			PDX_MAIN
			{
				return float4(DownsampleBox13Tap( Source, Input.uv, InvBloomSize ).rgb, 1.0);
			}
		]]
	}

	MainCode downsample_filter_high_quality
	{
		Input = "VS_OUTPUT_SAMPLER"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				return float4(DownsampleBox13TapWithFilter( Source, Input.uv, InvBloomSize ).rgb, 1.0);
			}
		]]
	}
	
	MainCode downsample_low_quality
	{
		Input = "VS_OUTPUT_SAMPLER"
		Output = "PDX_COLOR"
		Code
		[[		
			PDX_MAIN
			{
				return float4(DownsampleBox4Tap( Source, Input.uv, InvBloomSize ).rgb, 1.0);
			}
		]]
	}

	MainCode downsample_filter_low_quality
	{
		Input = "VS_OUTPUT_SAMPLER"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				return float4(DownsampleBox4TapWithFilter( Source, Input.uv, InvBloomSize ).rgb, 1.0);
			}
		]]
	}
}


BlendState BlendState
{
	BlendEnable = no
}

BlendState BlendStateUp
{
	BlendEnable = yes
	SourceBlend = "ONE"
	DestBlend = "ONE"
	BlendOp = "ADD"
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
	DepthWriteEnable = no
}


Effect Bloom_Downsample_13_Filter
{
	VertexShader = "VertexShader"
	PixelShader = "downsample_filter_high_quality"
}

Effect Bloom_Downsample_13
{
	VertexShader = "VertexShader"
	PixelShader = "downsample_high_quality"
}

Effect Bloom_Downsample_4_Filter
{
	VertexShader = "VertexShader"
	PixelShader = "downsample_filter_low_quality"
}

Effect Bloom_Downsample_4
{
	VertexShader = "VertexShader"
	PixelShader = "downsample_low_quality"
}

Effect Bloom_Upsample_9_Tent
{
	VertexShader = "VertexShader"
	PixelShader = "upsample_high_quality"
	BlendState = BlendStateUp
}

Effect Bloom_Upsample_4_Tent
{
	VertexShader = "VertexShader"
	PixelShader = "upsample_low_quality"
	BlendState = BlendStateUp
}
