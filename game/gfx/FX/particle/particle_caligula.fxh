Includes = {
	"cw/camera.fxh"
	"cw/quaternion.fxh"
	"cw/particle2.fxh"
}

VertexShader =
{
	MainCode VertexParticleCaligula
	{
		Input = "VS_INPUT_PARTICLE"
		Output = "VS_OUTPUT_PARTICLE"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PARTICLE Out;
				float3 InitialOffset = float3( ( Input.UV0 - Input.SizeAndOffset.zw - 0.5f ) * Input.SizeAndOffset.xy, 0 );

				float4 RotQ = DecodeQuaternion( Input.RotQ );
				float3 Offset = RotateVector( RotQ, InitialOffset );
				float Alpha = 0.0f;

				#ifdef BILLBOARD
					float3 WorldPos = Input.Position.xyz + Offset.x * CameraRightDir + Offset.y * CameraUpDir;

					if( Input.BillboardAxisAndFlipbookTime.x != 0.0 ||
						Input.BillboardAxisAndFlipbookTime.y != 0.0 ||
						Input.BillboardAxisAndFlipbookTime.z != 0.0 )
					{
						float3 Up = normalize( RotateVector( RotQ, Input.BillboardAxisAndFlipbookTime.xyz ) );
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
				Out.Color = float4( Input.Color.rgb, Alpha );
				Out.WorldSpacePos = WorldPos;

				return Out;
			}
		]]
	}
}