Includes = {
	"cw/camera.fxh"
	"cw/fullscreen_vertexshader.fxh"
}

PixelShader =
{		
	MainCode DownsamplePixelShader
	{	
		ConstantBuffer( PdxConstantBuffer0 )
		{
			uint2 _SourceSize;
			uint2 _DestinationSize;
			uint _LinearizeDepth;
		};
		
		Texture Source
		{
			Ref = PdxTexture0
			format = float
		} 
		
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			float LinearizeDepth( float Depth )
			{
				return ZNear * ZFar / ( ZFar + Depth * ( ZNear - ZFar ) );
			}
			
			float ReadValue( uint2 ReadIndex )
			{
				return ( _LinearizeDepth == 1 ) ? LinearizeDepth( Source[ReadIndex].x ) : Source[ReadIndex].x;
			}
			
			PDX_MAIN
			{
				uint2 WriteIndex = Input.position.xy;
				uint2 ReadIndex = uint2( WriteIndex ) * 2;
				
				float4 Values = float4( ReadValue( ReadIndex ).x, 
										ReadValue( ReadIndex + uint2(1,0) ).x,
										ReadValue( ReadIndex + uint2(0,1) ).x,
										ReadValue( ReadIndex + uint2(1,1) ).x );

				float Max = max( Values.x, max( Values.y, max( Values.z, Values.w ) ) );
				
				float2 Ratio = float2( _SourceSize ) / float2( _DestinationSize );
				bool NeedExtraSampleX = Ratio.x > 2.0;
				bool NeedExtraSampleY = Ratio.y > 2.0;
    
				Max = NeedExtraSampleX ? max( Max, max( ReadValue( ReadIndex + uint2(2,0) ), ReadValue( ReadIndex + uint2(2,1) ) ) ) : Max;
				Max = NeedExtraSampleY ? max( Max, max( ReadValue( ReadIndex + uint2(0,2) ), ReadValue( ReadIndex + uint2(1,2) ) ) ) : Max;
				Max = (NeedExtraSampleX && NeedExtraSampleY) ? max( Max, ReadValue( ReadIndex + uint2(2,2) ) ) : Max;

				return vec4( Max );
			}		
		]]
	}
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
	DepthWriteEnable = no
}

Effect DownsampleDepth
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "DownsamplePixelShader"
}
