Includes = {
	"cw/camera.fxh"
	"cw/quaternion.fxh"
}

ConstantBuffer( PdxFlipbookConstants )
{
	int2 FlipbookDimensions;
};

VertexStruct VS_INPUT_PARTICLE
{
	float2 UV0              				: TEXCOORD0;
	float3 Position							: TEXCOORD1;	 
	float4 RotQ             				: TEXCOORD2;	// Rotation relative to world or camera when billboarded.
	float4 SizeAndOffset    				: TEXCOORD3;	// SizeAndOffset.zw contains the local pivot offset
	float4 BillboardAxisAndFlipbookTime		: TEXCOORD4;	//	Position.w contains the flipbook time.
	float4 Color            				: TEXCOORD5;
};

VertexStruct VS_OUTPUT_PARTICLE
{
    float4 Pos     			: PDX_POSITION;
	float4 Color   			: COLOR;
	float2 UV0     			: TEXCOORD0;
	float2 UV1				: TEXCOORD1;
	float3 WorldSpacePos	: TEXCOORD2;
	float FrameBlend		: TEXCOORD3;
};

Code
[[
	uint CalcCurrentFrame( int Columns, int Rows, float Time )
	{
		int TotalFrames = ( Columns * Rows );
		return uint( TotalFrames * Time );
	}

	float CalcFrameBlend(int Columns, int Rows, float Time)
	{
		uint TotalFrames = ( Columns * Rows );
		return frac(TotalFrames * Time);
	}

	float2 CalcCellUV( uint CurrentFrame, float2 UV, int Columns, int Rows, float Time )
	{
		float2 CellUV;
		CellUV.x = float( CurrentFrame % Columns ) / Columns;
		CellUV.y = float( CurrentFrame / Columns ) / Rows;
		
		UV.x = ( UV.x / Columns );
		UV.y = ( UV.y / Rows );
		
		return CellUV + UV;
	}
]]

VertexShader =
{
	MainCode VertexParticle
	{				
		Input = "VS_INPUT_PARTICLE"
		Output = "VS_OUTPUT_PARTICLE"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PARTICLE Out;
				float3 InitialOffset = float3( ( Input.UV0 - Input.SizeAndOffset.zw - 0.5f ) * Input.SizeAndOffset.xy, 0 );
				float3 Offset = RotateVector( Input.RotQ, InitialOffset );
				float Alpha = 0.0f;

				#ifdef BILLBOARD
					float3 WorldPos = Input.Position.xyz + Offset.x * CameraRightDir + Offset.y * CameraUpDir;

					if( Input.BillboardAxisAndFlipbookTime.x != 0.0 || 
						Input.BillboardAxisAndFlipbookTime.y != 0.0 || 
						Input.BillboardAxisAndFlipbookTime.z != 0.0 )
					{
						float3 Up = normalize( RotateVector( Input.RotQ, Input.BillboardAxisAndFlipbookTime.xyz ) );
						float3 ToCameraDir = normalize( CameraPosition - Input.Position.xyz );
						float3 Right = normalize( cross( ToCameraDir, Up ) );
						WorldPos = Input.Position.xyz + InitialOffset.x * Right + InitialOffset.y * Up;

						#ifdef FADE_STEEP_ANGLES
							float3 Direction = cross( Right, Up );
							float fresnel = saturate( pow( 1.0f - abs( dot( ToCameraDir, Direction ) ), 2.0f ) * 2.5f );
							Alpha = Input.Color.a * fresnel;
						#else
							Alpha = Input.Color.a;
						#endif
					}
					else
					{
						//Cannot fade steep angles because the lack of a particle normal
						Alpha = Input.Color.a;
					}
				#else
					float3 WorldPos = Input.Position.xyz + Offset;
					//Cannot fade steep angles because the lack of a particle normal
					Alpha = Input.Color.a;
				#endif

				uint CurrentFrame = CalcCurrentFrame( FlipbookDimensions.x, FlipbookDimensions.y, Input.BillboardAxisAndFlipbookTime.w );
				Out.Pos = FixProjectionAndMul( ViewProjectionMatrix, float4( WorldPos, 1.0f ) );
				Out.UV0 = CalcCellUV( CurrentFrame, float2( Input.UV0.x, 1.0f - Input.UV0.y ), FlipbookDimensions.x, FlipbookDimensions.y, Input.BillboardAxisAndFlipbookTime.w );
				Out.UV1 = CalcCellUV( CurrentFrame + 1, float2( Input.UV0.x, 1.0f - Input.UV0.y ), FlipbookDimensions.x, FlipbookDimensions.y, Input.BillboardAxisAndFlipbookTime.w );
				Out.FrameBlend = CalcFrameBlend( FlipbookDimensions.x, FlipbookDimensions.y, Input.BillboardAxisAndFlipbookTime.w );
				Out.Color = float4(Input.Color.rgb, Alpha);
				Out.WorldSpacePos = WorldPos;
				
				return Out;
			}
		]]
	}
}


PixelShader =
{
	TextureSampler DiffuseMap
	{
		Ref = PdxTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

	MainCode PixelColor
	{
		Input = "VS_OUTPUT_PARTICLE"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				return Input.Color;
			}
		]]
	}
}