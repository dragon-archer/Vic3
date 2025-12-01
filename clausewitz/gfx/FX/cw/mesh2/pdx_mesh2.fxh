Includes = {
	"cw/mesh2/pdx_mesh2_geometry.fxh"
	"cw/mesh2/pdx_mesh2_skinning.fxh"
}

BufferTexture Mesh2InstanceDataBuffer
{
	Ref = PdxMesh2InstanceDataBuffer
	type = uint
}

BufferTexture Mesh2TransformsBuffer
{
	Ref = PdxMesh2TransformsBuffer
	type = uint
}


# Technically pixel shaders as well but we cannot really do that currently in our shader format and it is not used there
# this helps with catching errors in compute/ray tracing shaders
VertexShader =
{
	ConstantBuffer( PdxMesh2BatchConstants )
	{
		uint _GeometryTypeDataOffset;
	};
	
	ConstantBuffer( PdxMesh2InstanceConstants )
	{
		uint _InstanceDataOffset;
		uint _InstanceDataStride;
	};
}

Code
[[
	struct PDXMESH2_VERTEX_INPUT
	{
		float3 _Position;
		float3 _Normal;
		float3 _Tangent;
		float _BitangentDir;
		
		float2 _Uv0;
		float2 _Uv1;
		float2 _Uv2;
		float2 _Uv3;
		
		float4 _Color0;
		float4 _Color1;
		
	#ifdef PDX_MESH2_SKIN
		SSkinningData _SkinningData;
	#endif
	};
	
	struct PDXMESH2_INSTANCE_INPUT
	{
		float4x4 _WorldMatrix;
		float _BlendValue;
		
	#ifdef PDX_MESH2_SKIN
		uint2 _SkinningTransformsOffset;
	#endif
	};

	struct PDXMESH2_OUTPUT
	{
		float4 _Position;
		float3 _WorldSpacePosition;
		float _BlendValue;
		
		float3 _Normal;
		float3 _Tangent;
		float3 _Bitangent;
		
		float2 _Uv0;
		float2 _Uv1;
		float2 _Uv2;
		float2 _Uv3;
		
		float4 _Color0;
		float4 _Color1;
	};
	
	
	float4x4 LoadInstanceTransform( uint TransformIndex )
	{
		uint Offset = TransformIndex * PDX_MESH2_MATRIX34_DATA_STRIDE;
		return ReadMatrix34( Mesh2TransformsBuffer, Offset );
	}
	
	void BuildTangentFrame( float3x3 Transform, float3 Normal, float3 Tangent, float BitangentDir, out float3 NormalOut, out float3 TangentOut, out float3 BitangentOut )
	{
		NormalOut = normalize( mul( Transform, Normal ) );
		TangentOut = normalize( mul( Transform, Tangent ) );
		BitangentOut = normalize( cross( NormalOut, TangentOut ) * BitangentDir );
	}

	
	PDXMESH2_VERTEX_INPUT PdxMesh2VertexInputFromGeometryBuffer( STypeData TypeData, uint VertexID )
	{
		PDXMESH2_VERTEX_INPUT Out;
		
		Out._Position = GetPositionForType( TypeData, VertexID );
		GetNormalAndTangentForType( TypeData, VertexID, Out._Normal, Out._Tangent, Out._BitangentDir );

		Out._Uv0 = GetUv0( TypeData, VertexID );
		Out._Uv1 = GetUv1( TypeData, VertexID );
		Out._Uv2 = GetUv2( TypeData, VertexID );
		Out._Uv3 = GetUv3( TypeData, VertexID );
		
		Out._Color0 = GetColor0( TypeData, VertexID );
		Out._Color1 = GetColor1( TypeData, VertexID );
		
	#ifdef PDX_MESH2_SKIN
		Out._SkinningData = GetSkinningDataForType( TypeData, VertexID );
	#endif

		return Out;
	}
	
	// Not sure if we will be able to keep this alive once we start adding "custom" instance data?
	PDXMESH2_INSTANCE_INPUT PdxMesh2InstanceInputFromInstanceID( uint InstanceID, uint InstanceDataOffset, uint InstanceDataStride )
	{
		PDXMESH2_INSTANCE_INPUT Out;
		
		uint InstanceDataIndex = InstanceDataOffset + InstanceID * InstanceDataStride;

		uint TransformIndex = Mesh2InstanceDataBuffer[ InstanceDataIndex ];
		Out._WorldMatrix = LoadInstanceTransform( TransformIndex );

		Out._BlendValue = asfloat( Mesh2InstanceDataBuffer[ InstanceDataIndex + 1 ] );
	
	#ifdef PDX_MESH2_SKIN
		uint2 SkinningTransformsOffset = UnpackUintX_UintY( Mesh2InstanceDataBuffer[ InstanceDataIndex + 2 ], 8 );
		Out._SkinningTransformsOffset = SkinningTransformsOffset;
	#endif
	
		return Out;
	}
	
	PDXMESH2_OUTPUT PdxMesh2VertexShader( PDXMESH2_VERTEX_INPUT VertexInput, PDXMESH2_INSTANCE_INPUT InstanceInput )
	{
		PDXMESH2_OUTPUT Out;

		float3 Position = VertexInput._Position;

		float3 Normal = VertexInput._Normal;
		float3 Tangent = VertexInput._Tangent;
		float BitangentDir = VertexInput._BitangentDir;

	#ifdef PDX_MESH2_SKIN
	
		float3 SkinnedPosition = vec3( 0.0 );
		float3 SkinnedNormal = vec3( 0.0 );
		float3 SkinnedTangent = vec3( 0.0 );
		for( uint i = 0; i < VertexInput._SkinningData._NumBones; ++i )
		{
			uint BoneIndex;
			float BoneWeight;
			GetBoneIndexAndWeightForType( VertexInput._SkinningData, i, BoneIndex, BoneWeight );
	
			ProcessSkinning( InstanceInput._SkinningTransformsOffset, BoneIndex, BoneWeight, Position, Normal, Tangent, SkinnedPosition, SkinnedNormal, SkinnedTangent );
		}
		
		Position = SkinnedPosition;
		Normal = SkinnedNormal;
		Tangent = SkinnedTangent;

	#endif

		float4 TransformedPosition = mul( InstanceInput._WorldMatrix, float4( Position, 1.0 ) );
		Out._Position = FixProjectionAndMul( ViewProjectionMatrix, TransformedPosition );
		Out._WorldSpacePosition = TransformedPosition.xyz;
		Out._BlendValue = InstanceInput._BlendValue;
		
		BuildTangentFrame( CastTo3x3( InstanceInput._WorldMatrix ), Normal, Tangent, BitangentDir, Out._Normal, Out._Tangent, Out._Bitangent );
		
		Out._Uv0 = VertexInput._Uv0;
		Out._Uv1 = VertexInput._Uv1;
		Out._Uv2 = VertexInput._Uv2;
		Out._Uv3 = VertexInput._Uv3;
		
		Out._Color0 = VertexInput._Color0;
		Out._Color1 = VertexInput._Color1;
		
		return Out;
	}
]]


VertexShader =
{
	VertexStruct VS_INPUT_PDXMESH2
	{
	@ifdef USE_VB
			float3 Position			: POSITION;
			
		@ifdef PDX_MESH2_NORMAL
			float3 Normal      		: NORMAL;
		@endif

		@ifdef PDX_MESH2_TANGENT
			float4 Tangent			: TANGENT;
		@endif
		@ifdef PDX_MESH2_QTANGENT
			float4 QTangent			: TANGENT;
		@endif
			
		@ifdef PDX_MESH2_UV0
			float2 Uv0				: TEXCOORD0;
		@endif
		@ifdef PDX_MESH2_UV1
			float2 Uv1				: TEXCOORD1;
		@endif
		@ifdef PDX_MESH2_UV2
			float2 Uv2				: TEXCOORD2;
		@endif
		@ifdef PDX_MESH2_UV3
			float2 Uv3				: TEXCOORD3;
		@endif

		@ifdef PDX_MESH2_COLOR0
			float4 Color0			: COLOR0;
		@endif
		@ifdef PDX_MESH2_COLOR1
			float4 Color1			: COLOR1;
		@endif
		
		@ifdef PDX_MESH2_SKIN
			@ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
				uint4 BoneIndex 		: SKIN0;
				float3 BoneWeight		: SKIN1;
			@else
				uint SkinData 			: SKIN;
			@endif
		@endif
	@endif

		uint VertexID 			: PDX_VertexID;
		uint InstanceID			: PDX_InstanceID;
	};
	
	Code
	[[
	#ifdef USE_VB
		float3 GetPosition( VS_INPUT_PDXMESH2 Input, STypeData TypeData )
		{
			#ifdef PDX_MESH2_POSITION_COMPRESSED
				return DecompressPosition( TypeData, Input.Position );
			#else
				return Input.Position;
			#endif
		}
		
		void GetNormalAndTangent( VS_INPUT_PDXMESH2 Input, out float3 Normal, out float3 Tangent, out float BitangentDir )
		{
			#ifdef PDX_MESH2_QTANGENT
				float4 QTangent = normalize( Input.QTangent );
				// Extract "rotation matrix x-axis" from quaternion
				Normal = float3( 1, 0, 0 ) + float3( -2, 2, -2 ) * QTangent.y * QTangent.yxw + float3( -2, 2, 2 ) * QTangent.z * QTangent.zwx;
				// Extract y-axis
				Tangent = float3( 0, 1, 0 ) + float3( 2, -2, 2 ) * QTangent.x * QTangent.yxw + float3( -2, -2, 2 ) * QTangent.z * QTangent.wzy;
				BitangentDir = sign( QTangent.w );
			#else
				#ifdef PDX_MESH2_NORMAL
					Normal = Input.Normal;
				#else
					Normal = float3( 0.0, 0.0, 0.0 );
				#endif
				
				#ifdef PDX_MESH2_TANGENT
					Tangent = Input.Tangent.xyz;
					BitangentDir = Input.Tangent.w;
				#else
					Tangent = float3( 0.0, 0.0, 0.0 );
					BitangentDir = 0.0;
				#endif
			#endif
		}
		
		float2 GetUv0( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV0
				return Input.Uv0;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		float2 GetUv1( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV1
				return Input.Uv1;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		float2 GetUv2( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV2
				return Input.Uv2;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		float2 GetUv3( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV3
				return Input.Uv3;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		
		float4 GetColor0( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_COLOR0
				return Input.Color0;
			#else
				return float4( 0.0, 0.0, 0.0, 0.0 );
			#endif
		}
		float4 GetColor1( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_COLOR1
				return Input.Color1;
			#else
				return float4( 0.0, 0.0, 0.0, 0.0 );
			#endif
		}
		
		PDXMESH2_VERTEX_INPUT PdxMesh2VertexInputFromVertexBuffer( VS_INPUT_PDXMESH2 Input, STypeData TypeData )
		{
			PDXMESH2_VERTEX_INPUT Out;
			
			Out._Position = GetPosition( Input, TypeData );
			GetNormalAndTangent( Input, Out._Normal, Out._Tangent, Out._BitangentDir );

			Out._Uv0 = GetUv0( Input );
			Out._Uv1 = GetUv1( Input );
			Out._Uv2 = GetUv2( Input );
			Out._Uv3 = GetUv3( Input );
			
			Out._Color0 = GetColor0( Input );
			Out._Color1 = GetColor1( Input );
			
		#ifdef PDX_MESH2_SKIN

			#if defined( PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT )
				Out._SkinningData._NumBones = 4;
				Out._SkinningData._BoneIndices = Input.BoneIndex;
				Out._SkinningData._BoneWeights = float4( Input.BoneWeight.xyz, 1.0 - Input.BoneWeight.x - Input.BoneWeight.y - Input.BoneWeight.z );
			#else
				Out._SkinningData = UnpackSkinningData( TypeData, Input.SkinData );
			#endif
			
		#endif

			return Out;
		}
	#endif
	
		PDXMESH2_VERTEX_INPUT PdxMesh2LoadVertexInput( VS_INPUT_PDXMESH2 Input )
		{
			STypeData TypeData = LoadTypeData( _GeometryTypeDataOffset );
			
			PDXMESH2_VERTEX_INPUT Out;
			
			#ifdef USE_VB
				Out = PdxMesh2VertexInputFromVertexBuffer( Input, TypeData );
			#else
				Out = PdxMesh2VertexInputFromGeometryBuffer( TypeData, Input.VertexID );
			#endif
			
			return Out;
		}
		
		PDXMESH2_INSTANCE_INPUT PdxMesh2LoadInstanceInput( VS_INPUT_PDXMESH2 Input )
		{
			return PdxMesh2InstanceInputFromInstanceID( Input.InstanceID, _InstanceDataOffset, _InstanceDataStride );
		}
	]]
}
