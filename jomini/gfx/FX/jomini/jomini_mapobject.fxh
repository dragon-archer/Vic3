Includes = {
	"cw/heightmap.fxh"
}

VertexStruct VS_INPUT_PDXMESH_MAPOBJECT
{
    float3 Position					: POSITION;
	float3 Normal      				: TEXCOORD0;
	float4 Tangent					: TEXCOORD1;
	float2 UV0						: TEXCOORD2;

@ifdef PDX_MESH_UV1		
	float2 UV1						: TEXCOORD3;
@endif
@ifdef PDX_MESH_UV2		
	float2 UV2						: TEXCOORD4;
@endif

	uint Index24_Packed1_Opacity6_Sign1 	: TEXCOORD5;
};

VertexStruct VS_INPUT_DEBUGNORMAL_BATCHED
{
    float3 Position			: POSITION;
	float3 Normal 			: TEXCOORD0
	uint InstanceIndex 		: TEXCOORD4;
	
	uint VertexID           : PDX_VertexID;
};

VertexStruct VS_OUTPUT_DEBUGNORMAL_BATCHED
{
    float4 Position 	: PDX_POSITION;
};

VertexStruct VS_OUTPUT_MAPOBJECT_SHADOW
{
	float4 Position					: PDX_POSITION;
	float2 UV 						: TEXCOORD0;
	uint Index24_Packed1_Opacity6_Sign1 	: TEXCOORD1;
}

BufferTexture PackedMapObjectBuffer
{
	Ref = JominiMeshPackedBatchTransforms
	type = float4
}

BufferTexture NonPackedMapObjectBuffer
{
	Ref = JominiMeshNonPackedBatchTransforms
	type = float4
}

Code
[[
	float4x4 GetWorldMatrixMapObject( in uint InstanceIndex, in bool IsPacked )
	{
		if ( IsPacked )
		{
			float4 PackedTransform = PdxReadBuffer4( PackedMapObjectBuffer, InstanceIndex );

			float3 Translation = float3( PackedTransform.x, GetHeight( PackedTransform.xy ), PackedTransform.y );
			float Scale = PackedTransform.z;
			float SinYaw = sin(PackedTransform.w);
			float CosYaw = cos(PackedTransform.w);

			return float4x4(
				Scale * CosYaw, 	0,					Scale * SinYaw, 	Translation.x,
				0, 					Scale, 				0, 					Translation.y,
				- Scale * SinYaw, 	0, 					Scale * CosYaw, 	Translation.z,
				0, 					0, 					0, 					1
			);
		}
		return Create4x4( PdxReadBuffer4( NonPackedMapObjectBuffer, ( InstanceIndex * 4 ) + 0 ),
			PdxReadBuffer4( NonPackedMapObjectBuffer, ( InstanceIndex * 4 ) + 1 ),
			PdxReadBuffer4( NonPackedMapObjectBuffer, ( InstanceIndex * 4 ) + 2 ),
			PdxReadBuffer4( NonPackedMapObjectBuffer, ( InstanceIndex * 4 ) + 3 ) );
	}
	uint UnpackAndGetMapObjectInstanceIndex( in uint Index24_Packed1_Opacity6_Sign1 )
	{
		return ( Index24_Packed1_Opacity6_Sign1 >> 8 ) & uint(0x00ffffff);
	}
	bool UnpackAndGetMapObjectPackedFlag( in uint Index24_Packed1_Opacity6_Sign1 )
	{
		return ( Index24_Packed1_Opacity6_Sign1 & uint(0x00000080) ) != 0;
	}
	float UnpackAndGetMapObjectOpacity( in uint Index24_Packed1_Opacity6_Sign1 )
	{
		const float OpacityScale = 1.0f / float(0x0000007E);
		float Opacity = float(uint(Index24_Packed1_Opacity6_Sign1 & uint(0x0000007E))) * OpacityScale;
		if( (Index24_Packed1_Opacity6_Sign1 & uint(0x00000001) ) != 0 )
		{
			Opacity *= -1.0f;
		}
		return Opacity;
	}
	float4x4 UnpackAndGetMapObjectWorldMatrix( in uint Index24_Packed1_Opacity6_Sign1 )
	{
		uint InstanceIndex = UnpackAndGetMapObjectInstanceIndex( Index24_Packed1_Opacity6_Sign1 );
		bool IsPacked = UnpackAndGetMapObjectPackedFlag( Index24_Packed1_Opacity6_Sign1 );
		return GetWorldMatrixMapObject( InstanceIndex, IsPacked );
	}
	void UnpackMapObjectInstanceData( in uint Index24_Packed1_Opacity6_Sign1, out uint InstanceIndex, out uint IsPacked, out float Opacity )
	{
		InstanceIndex = UnpackAndGetMapObjectInstanceIndex( Index24_Packed1_Opacity6_Sign1 );
		IsPacked = UnpackAndGetMapObjectPackedFlag( Index24_Packed1_Opacity6_Sign1 );
		Opacity = UnpackAndGetMapObjectOpacity( Index24_Packed1_Opacity6_Sign1 );
	}
]]

VertexShader = 
{
	Code
	[[
		VS_INPUT_PDXMESH PdxMeshConvertInput( in VS_INPUT_PDXMESH_MAPOBJECT Input )
		{
			VS_INPUT_PDXMESH Out;		
			Out.Position = Input.Position;
			Out.Normal = Input.Normal;
			Out.Tangent = Input.Tangent;
			Out.UV0 = Input.UV0;
		#ifdef PDX_MESH_UV1
			Out.UV1 = Input.UV1;
		#endif
		#ifdef PDX_MESH_UV2
			Out.UV2 = Input.UV2;
		#endif
		#ifdef PDX_MESH_SKINNED
			Out.BoneIndex = uint4(0,0,0,0);
			Out.BoneWeight = float3(0,0,0);	//Animated map objects not supported
		#endif
			return Out;
		}
		
		VS_OUTPUT_MAPOBJECT_SHADOW ConvertOutputMapObjectShadow( in VS_OUTPUT_PDXMESHSHADOW Output )
		{
			VS_OUTPUT_MAPOBJECT_SHADOW Out;
			Out.Position 					= Output.Position;
			Out.UV							= Output.UV;
			Out.Index24_Packed1_Opacity6_Sign1 	= 0;
			return Out;
		}
	]]
	
	MainCode VS_jomini_mapobject_shadow
	{		
		Input = "VS_INPUT_PDXMESH_MAPOBJECT"
		Output = "VS_OUTPUT_MAPOBJECT_SHADOW"
		Code
		[[						
			PDX_MAIN
			{			
				uint InstanceIndex;
				bool IsPacked;
				float Opacity;
				UnpackMapObjectInstanceData( Input.Index24_Packed1_Opacity6_Sign1, InstanceIndex, IsPacked, Opacity );
				float4x4 WorldMatrix = GetWorldMatrixMapObject( InstanceIndex, IsPacked );
				
				VS_OUTPUT_MAPOBJECT_SHADOW Out = ConvertOutputMapObjectShadow( PdxMeshVertexShaderShadow( PdxMeshConvertInput( Input ), 0/*Not supported*/, WorldMatrix ) );				
				Out.Index24_Packed1_Opacity6_Sign1 = Input.Index24_Packed1_Opacity6_Sign1;
				return Out;
			}
		]]
	}
	
	MainCode VertexDebugNormalBatched
	{		
		Input = "VS_INPUT_DEBUGNORMAL_BATCHED"
		Output = "VS_OUTPUT_DEBUGNORMAL_BATCHED"
		Code
		[[			
			PDX_MAIN
			{				
				float NormalOffset = float( Input.VertexID % 2 ) /* Multiply here to change the normal lengths*/; 
				
				float4x4 WorldMatrix = UnpackAndGetMapObjectWorldMatrix( Input.InstanceIndex );

				float4 Position = float4( Input.Position + Input.Normal * NormalOffset , 1.f );
				Position = mul( WorldMatrix, Position );

				VS_OUTPUT_DEBUGNORMAL_BATCHED Out;
				Out.Position = Position;
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, Out.Position );
				return Out;
			}
		]]
	}
}

PixelShader =
{
	Code
	[[
		void ApplyDither( in VS_OUTPUT_MAPOBJECT_SHADOW Input )
		{
			float Opacity = UnpackAndGetMapObjectOpacity( Input.Index24_Packed1_Opacity6_Sign1 );
			PdxMeshApplyDitheredOpacity( Opacity, Input.Position.xy );
		}
	]]

	MainCode PS_jomini_mapobject_shadow
	{
		Input = "VS_OUTPUT_MAPOBJECT_SHADOW"
		Output = "void"
		Code
		[[
			PDX_MAIN
			{
				ApplyDither( Input );
			}
		]]
	}

	MainCode PS_jomini_mapobject_shadow_alphablend
	{
		Input = "VS_OUTPUT_MAPOBJECT_SHADOW"
		Output = "void"
		Code
		[[
			#ifndef PDXMESH_AlphaBlendShadowMap
				#define PDXMESH_AlphaBlendShadowMap DiffuseMap
			#endif
			PDX_MAIN
			{
				ApplyDither( Input );
				
				float Alpha = PdxTex2D( PDXMESH_AlphaBlendShadowMap, Input.UV ).a;
				clip( Alpha - 0.5 );
			}
		]]
	}
	
	MainCode PixelDebugNormalBatched
	{
		Input = "VS_OUTPUT_DEBUGNORMAL_BATCHED"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float4 vColor = float4( 0.f, 1.f, 0.25f, 1.f );
				return vColor;
			}
		]]
	}
}


Effect DebugNormalBatched
{
	VertexShader = "VertexDebugNormalBatched"
	PixelShader = "PixelDebugNormalBatched"
}