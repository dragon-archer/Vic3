
BufferTexture GeometryDataBuffer
{
	Ref = PdxGeometryDataBuffer
	type = uint
}

BufferTexture Mesh2InstanceBuffer
{
	Ref = PdxMesh2InstanceBuffer
	type = uint
}

# Technically pixel shaders as well but we cannot really do that currently in out shader format and it is not used there
# this helps with catching errors in compute/ray tracing shaders
VertexShader =
{
	ConstantBuffer( PdxMesh2BatchConstants )
	{
		uint _GeometryTypeDataOffset;
	};
}

Code
[[
	struct STypeData
	{
		float3 _BoundingSphereCenter;
		float _BoundingSphereRadius;
		
		float3 _BoundingBoxMin;
		float3 _BoundingBoxMax;
		
		uint _GeometryDataBufferOffset;
		uint _Numindices;
		uint _IndexDataOffset;
		
		uint _PositionDataOffset;
		
		// TODO - PSGE-6681 - Shader Defines, how do we want to deal with this, separate formats might complicate shared compute shader code
	#ifdef PDX_MESH2_QTANGENT
		uint _QTangentDataOffset;
	#endif
	
	#ifdef PDX_MESH2_NORMAL
		uint _NormalDataOffset;
	#endif
	#ifdef PDX_MESH2_TANGENT
		uint _TangentDataOffset;
	#endif
	
	#ifdef PDX_MESH2_UV0
		uint _Uv0DataOffset;
	#endif
	#ifdef PDX_MESH2_UV1
		uint _Uv1DataOffset;
	#endif
	#ifdef PDX_MESH2_UV2
		uint _Uv2DataOffset;
	#endif
	#ifdef PDX_MESH2_UV3
		uint _Uv3DataOffset;
	#endif
	
	#ifdef PDX_MESH2_COLOR0
		uint _Color0DataOffset;
	#endif
	#ifdef PDX_MESH2_COLOR1
		uint _Color1DataOffset;
	#endif
	
	#ifdef PDX_MESH2_SKIN
		uint _SkinVertexDataOffset;
		
		#ifdef PDX_MESH2_SKIN_EXTERNAL
			uint _SkinExternalDataOffset; // For versions that stores count/offset in vertex stream and actual skinning data separately
		#endif
	#endif
	};
	
	struct SInstanceData
	{
		uint _JointTransformsOffset;
		float4x4 _Transform;
	};
	
	float3 DecompressPosition( STypeData TypeData, float3 CompressedPosition )
	{
		return lerp( TypeData._BoundingBoxMin, TypeData._BoundingBoxMax, CompressedPosition.xyz );
	}
	
	
	uint2 Read2( PdxBufferUint Buf, uint Offset )
	{
		return uint2( Buf[Offset], Buf[Offset + 1] );
	}
	float2 Read2Float( PdxBufferUint Buf, uint Offset )
	{
		return asfloat( Read2( Buf, Offset ) );
	}
	
	uint3 Read3( PdxBufferUint Buf, uint Offset )
	{
		return uint3( Buf[Offset], Buf[Offset + 1], Buf[Offset + 2] );
	}
	float3 Read3Float( PdxBufferUint Buf, uint Offset )
	{
		return asfloat( Read3( Buf, Offset ) );
	}
	
	uint4 Read4( PdxBufferUint Buf, uint Offset )
	{
		return uint4( Buf[Offset], Buf[Offset + 1], Buf[Offset + 2], Buf[Offset + 3] );
	}
	float4 Read4Float( PdxBufferUint Buf, uint Offset )
	{
		return asfloat( Read4( Buf, Offset ) );
	}
	
	#define PDX_MESH2_MATRIX34_DATA_STRIDE 12
	float4x4 ReadMatrix34( PdxBufferUint Buf, uint Offset )
	{	
		float4 XAxis = float4( Read3Float( Buf, Offset ), 0.0 );
		float4 YAxis = float4( Read3Float( Buf, Offset + 3 ), 0.0 );
		float4 ZAxis = float4( Read3Float( Buf, Offset + 6 ), 0.0 );
		float4 Translation = float4( Read3Float( Buf, Offset + 9 ), 1.0 );
		return Create4x4( XAxis, YAxis, ZAxis, Translation );
	}
	

	// Note that offsets are known at compile time so even tho it looks like we always load all this data the compiler should throw away all fields that are unused
	STypeData LoadTypeData( uint TypeDataOffset )
	{
		STypeData TypeData;
		
		TypeData._BoundingSphereCenter = asfloat( Read3( GeometryDataBuffer, TypeDataOffset ) );
		TypeDataOffset += 3;
		TypeData._BoundingSphereRadius = asfloat( GeometryDataBuffer[TypeDataOffset++] );
		
		TypeData._BoundingBoxMin = asfloat( Read3( GeometryDataBuffer, TypeDataOffset ) );
		TypeDataOffset += 3;
		TypeData._BoundingBoxMax = asfloat( Read3( GeometryDataBuffer, TypeDataOffset ) );
		TypeDataOffset += 3;
		
		TypeData._Numindices = GeometryDataBuffer[TypeDataOffset++];
		TypeData._IndexDataOffset = GeometryDataBuffer[TypeDataOffset++];
		
		TypeData._PositionDataOffset = GeometryDataBuffer[TypeDataOffset++];
		
	#ifdef PDX_MESH2_QTANGENT
		TypeData._QTangentDataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	
	#ifdef PDX_MESH2_NORMAL
		TypeData._NormalDataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_TANGENT
		TypeData._TangentDataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
		
	#ifdef PDX_MESH2_UV0
		TypeData._Uv0DataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_UV1
		TypeData._Uv1DataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_UV2
		TypeData._Uv2DataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_UV3
		TypeData._Uv3DataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	
	#ifdef PDX_MESH2_COLOR0
		TypeData._Color0DataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_COLOR1
		TypeData._Color1DataOffset = GeometryDataBuffer[TypeDataOffset++];
	#endif
	
	#ifdef PDX_MESH2_SKIN
		TypeData._SkinVertexDataOffset = GeometryDataBuffer[TypeDataOffset++];
		
		#ifdef PDX_MESH2_SKIN_EXTERNAL
			TypeData._SkinExternalDataOffset = GeometryDataBuffer[TypeDataOffset++];
		#endif
	#endif
	
		return TypeData;
	}
	
	#define PDX_MESH2_INSTANCE_DATA_STRIDE 13
	SInstanceData LoadInstanceData( uint InstanceDataOffset )
	{
		SInstanceData InstanceData;
		InstanceData._JointTransformsOffset = Mesh2InstanceBuffer[InstanceDataOffset++];
		
		InstanceData._Transform = ReadMatrix34( Mesh2InstanceBuffer, InstanceDataOffset );
		//InstanceDataOffset += PDX_MESH2_MATRIX34_DATA_STRIDE;
		
		return InstanceData;
	}
	
	SInstanceData LoadInstanceDataForInstanceIndex( uint InstanceIndex )
	{
		return LoadInstanceData( InstanceIndex * PDX_MESH2_INSTANCE_DATA_STRIDE );
	}
	
	
	float2 ReadPackedFloat2( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 2;
		return asfloat( Read2( GeometryDataBuffer, DataBufferOffset ) );
	}
	float3 ReadPackedFloat3( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 3;
		return asfloat( Read3( GeometryDataBuffer, DataBufferOffset ) );
	}
	float4 ReadPackedFloat4( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 4;
		return asfloat( Read4( GeometryDataBuffer, DataBufferOffset ) );
	}
	
	
	// Unpack 2 int16 packed into a uint32
	int2 UnpackInt16_x2( int Packed )
	{
		return int2( Packed << 16, Packed ) >> 16;
	}
	// Unpack 2 snorm16 packed into a uint32
	float2 UnpackSnorm16_x2( int Packed )
	{
		return clamp( float2( UnpackInt16_x2( Packed ) ) / 32767.0, vec2( -1.0 ), vec2( 1.0 ) );
	}
	
	// Unpack 2 uint16 packed into a uint32
	uint2 UnpackUint16_x2( uint Packed )
	{
		return uint2( Packed & 0xffff, Packed >> 16 );
	}
	// Unpack 2 unorm16 packed into a uint32
	float2 UnpackUnorm16_x2( uint Packed )
	{
		return float2( UnpackUint16_x2( Packed ) ) / UINT16_MAX;
	}
	
	// Unpack 4 uint8 packed into a uint32
	uint4 UnpackUint8_x4( uint Packed )
	{
		return uint4( Packed & 0xff, ( Packed >> 8 ) & 0xff, ( Packed >> 16 ) & 0xff, Packed >> 24 );
	}
	// Unpack 4 unorm8 packed into a uint32
	float4 UnpackUnorm8_x4( uint Packed )
	{
		return float4( UnpackUint8_x4( Packed ) ) / UINT8_MAX;
	}
	
	
	// Reads 4 snorm16 compressed values and convert to float4 (better naming is welcomed)
	float4 ReadPackedFloat4_Snorm16( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 2; // 2 snorm16 values in each uint, so 2 uint for 4 values
		int2 Data = asint( Read2( GeometryDataBuffer, DataBufferOffset ) );
		return float4( UnpackSnorm16_x2( Data.x ), UnpackSnorm16_x2( Data.y ) );
	}
	
	// Reads 2 unorm16 compressed values and convert to float2
	float2 ReadPackedFloat2_Unorm16( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID; // 2 unorm16 values in each uint
		uint Data = GeometryDataBuffer[DataBufferOffset];
		return UnpackUnorm16_x2( Data );
	}
	
	// Reads 4 unorm16 compressed values and convert to float4
	float4 ReadPackedFloat4_Unorm16( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 2; // 2 unorm16 values in each uint, so 2 uint for 4 values
		uint2 Data = Read2( GeometryDataBuffer, DataBufferOffset );
		return float4( UnpackUnorm16_x2( Data.x ), UnpackUnorm16_x2( Data.y ) );
	}
	
	// Reads 4 unorm8 compressed values and convert to float4
	float4 ReadPackedFloat4_Unorm8( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID; // 4 unorm8 values in each uint
		uint Data = GeometryDataBuffer[DataBufferOffset];
		return UnpackUnorm8_x4( Data );
	}
	
	
	void HandleIndexBuffer( STypeData TypeData, inout uint VertexID )
	{
	#ifndef USE_IB
		#ifdef PDX_MESH2_INDEX_UINT_16
			uint DataBufferOffset = TypeData._IndexDataOffset + VertexID / 2;
			uint PackedIndex = GeometryDataBuffer[DataBufferOffset];
			uint2 IndexUint16 = UnpackUint16_x2( PackedIndex );
			VertexID = IndexUint16[ mod(VertexID, 2) ];
		#else
			uint DataBufferOffset = TypeData._IndexDataOffset + VertexID;
			VertexID = GeometryDataBuffer[DataBufferOffset];
		#endif
	#endif
	}
	
	float3 GetPositionForType( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
	
	#ifdef PDX_MESH2_POSITION_COMPRESSED
	
		float4 CompressedPosition = ReadPackedFloat4_Unorm16( TypeData._PositionDataOffset, VertexID );
		return DecompressPosition( TypeData, CompressedPosition.xyz );
		
	#else
	
		return ReadPackedFloat3( TypeData._PositionDataOffset, VertexID );
		
	#endif
	}
	
	void GetNormalAndTangentForType( STypeData TypeData, uint VertexID, out float3 Normal, out float3 Tangent, out float BitangentDir )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_QTANGENT
		float4 QTangent = normalize( ReadPackedFloat4_Snorm16( TypeData._QTangentDataOffset, VertexID ) );
		// Extract "rotation matrix x-axis" from quaternion
		Normal = float3( 1, 0, 0 ) + float3( -2, 2, -2 ) * QTangent.y * QTangent.yxw + float3( -2, 2, 2 ) * QTangent.z * QTangent.zwx;
		// Extract y-axis
		Tangent = float3( 0, 1, 0 ) + float3( 2, -2, 2 ) * QTangent.x * QTangent.yxw + float3( -2, -2, 2 ) * QTangent.z * QTangent.wzy;
		BitangentDir = sign( QTangent.w );
	#else
		#ifdef PDX_MESH2_NORMAL
			#ifdef PDX_MESH2_NORMAL_COMPRESSED
				Normal = normalize( ReadPackedFloat4_Snorm16( TypeData._NormalDataOffset, VertexID ).xyz );
			#else
				Normal = ReadPackedFloat3( TypeData._NormalDataOffset, VertexID );
			#endif
		#else
			Normal = float3( 0.0, 0.0, 0.0 );
		#endif
		
		#ifdef PDX_MESH2_TANGENT
			#ifdef PDX_MESH2_TANGENT_COMPRESSED
				float4 TangentData = ReadPackedFloat4_Snorm16( TypeData._TangentDataOffset, VertexID );
				TangentData.xyz = normalize( TangentData.xyz );
			#else
				float4 TangentData = ReadPackedFloat4( TypeData._TangentDataOffset, VertexID );
			#endif
			Tangent = TangentData.xyz;
			BitangentDir = TangentData.w;
		#else
			Tangent = float3( 0.0, 0.0, 0.0 );
			BitangentDir = 0.0;
		#endif
	#endif
	}
	
	float2 GetUv0( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_UV0
		#ifdef PDX_MESH2_UV0_COMPRESSED
			return ReadPackedFloat2_Unorm16( TypeData._Uv0DataOffset, VertexID );
		#else
			return ReadPackedFloat2( TypeData._Uv0DataOffset, VertexID );
		#endif
	#else
		return float2( 0.0, 0.0 );
	#endif
	}
	
	float4 GetColor0( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_COLOR0
		#ifdef PDX_MESH2_COLOR0_COMPRESSED
			return ReadPackedFloat4_Unorm8( TypeData._Color0DataOffset, VertexID );
		#else
			return ReadPackedFloat4( TypeData._Color0DataOffset, VertexID );
		#endif
	#else
		return float4( 0.0, 0.0, 0.0, 0.0 );
	#endif
	}


	struct SSkinningData
	{
		uint _NumBones;
		
		// In this mode just store the data read from the "vertex stream"
	#ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
		uint4 _BoneIndices;
		float4 _BoneWeights;
	#else
		uint _BoneDataOffset;
	#endif
	};
	
	
	// Unpack 2 uints, the first uses "NumBitsForX" bits the second uses "32 - NumBitsForX" bits
	uint2 UnpackUintX_UintY( uint Packed, const uint NumBitsForX )
	{
		const uint YMask = ( 1u << ( 32 - NumBitsForX ) ) - 1;
		return uint2( Packed >> ( 32 - NumBitsForX ), Packed & YMask );
	}
	
	// Unpack 1 uint and 1 normalized float, the uint uses "NumBitsForX" bits the float uses "32 - NumBitsForX" bits
	// Note that 24 bits for Y is at the limit of what "integer floats" can handle, so NumBitsForX should be >= 8
	void UnpackUintX_UnormY( uint Packed, const uint NumBitsForX, out uint UintXOut, out float UnormYOut )
	{
		uint2 UintX_UintY = UnpackUintX_UintY( Packed, NumBitsForX );
		UintXOut = UintX_UintY.x;
		UnormYOut = float( UintX_UintY.y ) / float( ( 1u << ( 32 - NumBitsForX ) ) - 1 );
	}
	
	
	// Custom format used for skin data, first 6 bits store a "uint6" and last 26 bits store a "uint26"
	uint2 UnpackUint6_Uint26( uint Packed )
	{
		return UnpackUintX_UintY( Packed, 6 );
	}
	
	// Custom format used for skin data, first 8 bits store a "uint8" and last 24 bits store a "unorm24"
	void UnpackUint8_Unorm24( uint Packed, out uint Uint8Out, out float Unorm24Out )
	{
		UnpackUintX_UnormY( Packed, 8, Uint8Out, Unorm24Out );
	}
	// Custom format used for skin data, first 16 bits store a "uint16" and last 16 bits store a "unorm16"
	void UnpackUint16_Unorm16( uint Packed, out uint Uint16Out, out float Unorm16Out )
	{
		UnpackUintX_UnormY( Packed, 16, Uint16Out, Unorm16Out );
	}
	
#if defined( PDX_MESH2_SKIN	) && defined( PDX_MESH2_SKIN_EXTERNAL )
	SSkinningData UnpackSkinningData( STypeData TypeData, uint Packed )
	{
		uint2 Unpacked = UnpackUint6_Uint26( Packed );
		
		SSkinningData SkinningData;
		SkinningData._NumBones = Unpacked.x;
		#if defined( PDX_MESH2_SKIN_EXTERNAL_8_UINT_24_UNORM ) || defined ( PDX_MESH2_SKIN_EXTERNAL_16_UINT_16_UNORM )
			SkinningData._BoneDataOffset = TypeData._SkinExternalDataOffset + Unpacked.y;
		#else
			// Uncompressed each bone influence stores 1 uint32 and one float, see SMesh2BoneInfluence
			SkinningData._BoneDataOffset = TypeData._SkinExternalDataOffset + Unpacked.y * 2;
		#endif
		return SkinningData;
	}
#endif
	
	SSkinningData GetNumBonesForType( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
		SSkinningData SkinningData;
	#ifdef PDX_MESH2_SKIN
		#ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
		
			uint DataBufferOffset = TypeData._SkinVertexDataOffset + VertexID * 5;
			uint2 Data = Read2( GeometryDataBuffer, DataBufferOffset );
			DataBufferOffset += 2;
			float3 BoneWeights = Read3Float( GeometryDataBuffer, DataBufferOffset );
			
			SkinningData._NumBones = 4;
			SkinningData._BoneIndices.xy = UnpackUint16_x2( Data.x );
			SkinningData._BoneIndices.zw = UnpackUint16_x2( Data.y );
			SkinningData._BoneWeights = float4( BoneWeights, 1.0 - BoneWeights.x - BoneWeights.y - BoneWeights.z );
		
		#else

			uint DataBufferOffset = TypeData._SkinVertexDataOffset + VertexID;
			uint Data = GeometryDataBuffer[DataBufferOffset];
			SkinningData = UnpackSkinningData( TypeData, Data );
			
		#endif
	#else
		SkinningData._NumBones = 0;
	#endif
	
		return SkinningData;
	}
	
	void GetBoneIndexAndWeightForType( SSkinningData SkinningData, uint Index, out uint BoneIndexOut, out float BoneWeightOut )
	{
	#ifdef PDX_MESH2_SKIN		
		#ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
			BoneIndexOut = SkinningData._BoneIndices[Index];
			BoneWeightOut = SkinningData._BoneWeights[Index];
		#else
			
			#if defined( PDX_MESH2_SKIN_EXTERNAL_8_UINT_24_UNORM ) || defined ( PDX_MESH2_SKIN_EXTERNAL_16_UINT_16_UNORM )
				uint DataBufferOffset = SkinningData._BoneDataOffset + Index;
				uint CompressedBoneInfluence = GeometryDataBuffer[DataBufferOffset];
				#ifdef PDX_MESH2_SKIN_EXTERNAL_8_UINT_24_UNORM
					UnpackUint8_Unorm24( CompressedBoneInfluence, BoneIndexOut, BoneWeightOut );
				#endif
				#ifdef PDX_MESH2_SKIN_EXTERNAL_16_UINT_16_UNORM
					UnpackUint16_Unorm16( CompressedBoneInfluence, BoneIndexOut, BoneWeightOut );
				#endif
			#else
				uint DataBufferOffset = SkinningData._BoneDataOffset + Index * 2; // Uncompressed each bone influence stores 1 uint32 and one float, see SMesh2BoneInfluence
				BoneIndexOut = GeometryDataBuffer[DataBufferOffset];
				BoneWeightOut = asfloat( GeometryDataBuffer[DataBufferOffset + 1] );
			#endif
	
		#endif
	#else
		BoneIndexOut = 0;
		BoneWeightOut = 0.0;
	#endif
	}
]]