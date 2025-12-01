Includes = {
	"cw/mesh2/pdx_mesh2.fxh"
}


BufferTexture Mesh2BatchStateBuffer
{
	Ref = PdxMesh2BatchStateBuffer
	type = uint
}
BufferTexture Mesh2RenderStateBuffer
{
	Ref = PdxMesh2RenderStateBuffer
	type = uint
}
BufferTexture Mesh2MeshInstanceStateBuffer
{
	Ref = PdxMesh2MeshInstanceStateBuffer
	type = uint
}

RWBufferTexture Mesh2DrawcallRwBuffer
{
	Ref = PdxMesh2DrawcallRwBuffer
	type = uint
}
RWBufferTexture Mesh2InstanceIndicesRwBuffer
{
	Ref = PdxMesh2InstanceIndicesRwBuffer
	type = uint
}

BufferTexture Mesh2CompactedInstanceIndicesBuffer
{
	Ref = PdxMesh2CompactedInstanceIndicesBuffer
	type = uint
}


Code
[[
	#define PDX_MESH2_RENDER_STATE_DATA_STRIDE 8
	uint GetBatchStateIndex( uint RenderStateIndex, uint SubPassIndex )
	{
		uint DataOffset = RenderStateIndex * PDX_MESH2_RENDER_STATE_DATA_STRIDE;
		return Mesh2RenderStateBuffer[ DataOffset + SubPassIndex ];
	}


	struct SMeshInstanceStateData
	{
		float3 _BoundingSphereCenter;
		float _BoundingSphereRadius;
		uint _NumUnloddedMeshes;
		uint _NumLods;
	};
	#define PDX_MESH2_MESH_INSTANCE_STATE_DATA_STRIDE ( 256 / 4 )
	
	SMeshInstanceStateData LoadMeshInstanceStateData( uint MeshInstanceStateIndex )
	{
		uint DataOffset = MeshInstanceStateIndex * PDX_MESH2_MESH_INSTANCE_STATE_DATA_STRIDE;
		
		SMeshInstanceStateData MeshInstanceStateData;
		MeshInstanceStateData._BoundingSphereCenter = asfloat( Read3( Mesh2MeshInstanceStateBuffer, DataOffset ) );
		DataOffset += 3;
		MeshInstanceStateData._BoundingSphereRadius = asfloat( Mesh2MeshInstanceStateBuffer[DataOffset++] );
		MeshInstanceStateData._NumUnloddedMeshes = Mesh2MeshInstanceStateBuffer[DataOffset++];
		MeshInstanceStateData._NumLods = Mesh2MeshInstanceStateBuffer[DataOffset++];
		
		return MeshInstanceStateData;
	}


	struct SInstanceIndexAndMeshInstanceStateIndex
	{
		uint _InstanceIndex;
		uint _MeshInstanceStateIndex;
	};
	#define PDX_MESH2_COMPACTED_INSTANCE_INDICES_DATA_STRIDE 2
	
	SInstanceIndexAndMeshInstanceStateIndex LoadCompactedInstanceIndicesData( uint DataOffset )
	{
		SInstanceIndexAndMeshInstanceStateIndex Data;
		Data._InstanceIndex = Mesh2CompactedInstanceIndicesBuffer[DataOffset++];
		Data._MeshInstanceStateIndex = Mesh2CompactedInstanceIndicesBuffer[DataOffset++];
		return Data;
	}
	
	SInstanceIndexAndMeshInstanceStateIndex LoadCompactedInstanceIndicesDataForIndex( uint Index )
	{
		return LoadCompactedInstanceIndicesData( Index * PDX_MESH2_COMPACTED_INSTANCE_INDICES_DATA_STRIDE );
	}
	
	
	float CalcDistanceFromPlane( float3 Point, float4 Plane )
	{
		return dot( Plane.xyz, Point ) + Plane.w;
	}
	
	bool SphereIntersectsFrustum( float3 Center, float Radius, float4 FrustumPlanes[6] )
	{		
		for ( int i = 0; i < 6; ++i )
		{
			float DistanceFromPlane = CalcDistanceFromPlane( Center, FrustumPlanes[i] );
			if ( DistanceFromPlane > Radius )
			{
				return false;
			}
		}
		
		return true;
	}
	
	float CalcLengthSquared( float3 Vec )
	{
		return dot( Vec, Vec );
	}
	
	// From https://zeux.io/2023/01/12/approximate-projected-bounds/
	bool ProjectSphere( float3 c, float r, float znear, float P00, float P11, out float4 Aabb )
	{
		if (c.z < r + znear)
		{
			return false;
		}

		float3 cr = c * r;
		float czr2 = c.z * c.z - r * r;

		float vx = sqrt(c.x * c.x + czr2);
		float minx = (vx * c.x - cr.z) / (vx * c.z + cr.x);
		float maxx = (vx * c.x + cr.z) / (vx * c.z - cr.x);

		float vy = sqrt(c.y * c.y + czr2);
		float miny = (vy * c.y - cr.z) / (vy * c.z + cr.y);
		float maxy = (vy * c.y + cr.z) / (vy * c.z - cr.y);

		Aabb = float4( minx * P00, miny * P11, maxx * P00, maxy * P11 );
		// clip space -> uv space
		Aabb = Aabb.xwzy * float4( 0.5, -0.5, 0.5, -0.5 ) + vec4( 0.5 );

		return true;
	}
	
	void CalculateTransformedBoundingSphere( SInstanceData InstanceData, SMeshInstanceStateData MeshInstanceStateData, out float4 BoundingSphereOut )
	{
		BoundingSphereOut.xyz = mul( InstanceData._Transform, float4( MeshInstanceStateData._BoundingSphereCenter, 1.0 ) ).xyz;
	
		float4x4 TransposedTransform = transpose( InstanceData._Transform );
		float MaxScaling = sqrt( max( max( CalcLengthSquared( TransposedTransform[0].xyz ), CalcLengthSquared( TransposedTransform[1].xyz ) ), CalcLengthSquared( TransposedTransform[2].xyz ) ) );
		BoundingSphereOut.w = MeshInstanceStateData._BoundingSphereRadius * MaxScaling;
	}
	
	void CalculateTransformedBoundingSphere( SInstanceIndexAndMeshInstanceStateIndex InstanceIndexAndMeshInstanceStateIndex, out float4 BoundingSphereOut )
	{
		SInstanceData InstanceData = LoadInstanceDataForInstanceIndex( InstanceIndexAndMeshInstanceStateIndex._InstanceIndex );
		SMeshInstanceStateData MeshInstanceStateData = LoadMeshInstanceStateData( InstanceIndexAndMeshInstanceStateIndex._MeshInstanceStateIndex );
		CalculateTransformedBoundingSphere( InstanceData, MeshInstanceStateData, BoundingSphereOut );
	}
	
	bool CalculateOcclusionSettings( float4 BoundingSphere, float ZNear, float4x4 ViewMatrix, float4x4 ProjectionMatrix, uint2 DepthPyramidSize, uint DepthPyramidMaxMipLevel, 
									 out float4 DepthPyramidUvRectOut, out float DepthPyramidLevelOut, out float SphereDepthOut )
	{
		float3 ViewSpaceSphereCenter = mul( ViewMatrix, float4( BoundingSphere.xyz, 1 ) ).xyz;
		if ( !ProjectSphere( ViewSpaceSphereCenter, BoundingSphere.w, ZNear, ProjectionMatrix[0][0], ProjectionMatrix[1][1], DepthPyramidUvRectOut ) )
		{
			return false;
		}
		
		float2 AabbSize = ( DepthPyramidUvRectOut.zw - DepthPyramidUvRectOut.xy ) * DepthPyramidSize;
		DepthPyramidLevelOut = ceil( log2( max( AabbSize.x, AabbSize.y ) ) );
		DepthPyramidLevelOut = clamp( DepthPyramidLevelOut, 0, DepthPyramidMaxMipLevel );
		
		// Since this can be quite conservative check if next lower level mip only touches a 2x2 region, if so use it
		float NextMipLevel = max( DepthPyramidLevelOut - 1, 0 );
		uint2 NextMipLevelSize = DepthPyramidSize >> uint( NextMipLevel );
		uint2 MinTexel = DepthPyramidUvRectOut.xy * NextMipLevelSize;
		uint2 MaxTexel = DepthPyramidUvRectOut.zw * NextMipLevelSize;
		uint2 RegionSize = MaxTexel - MinTexel;		
		if ( RegionSize.x <= 1 && RegionSize.y <= 1 )
		{
			DepthPyramidLevelOut = NextMipLevel;
		}
		
		SphereDepthOut = ( ViewSpaceSphereCenter.z - BoundingSphere.w );
		
		return true;
	}

	float CalculateScreenSize( float3 CameraPos, float3 ObjectPos, float ObjectRadius, float LodScale )
	{
		const float Epsilon = 0.00001;
		float DistanceToObject = length( ObjectPos - CameraPos );
		return ( LodScale * ObjectRadius ) / max( DistanceToObject, Epsilon );
	}
	
	uint CalculateLod( SMeshInstanceStateData MeshInstanceStateData, SInstanceIndexAndMeshInstanceStateIndex InstanceIndexAndMeshInstanceStateIndex, float4 BoundingSphere, float LodScale )
	{
		uint ScreenPercentageDataOffset = ( InstanceIndexAndMeshInstanceStateIndex._MeshInstanceStateIndex * PDX_MESH2_MESH_INSTANCE_STATE_DATA_STRIDE ) + 6;
		float InstanceScreenSize = CalculateScreenSize( CameraPosition, BoundingSphere.xyz, BoundingSphere.w, LodScale );

		uint LodIndex = MeshInstanceStateData._NumLods - 1;
		for ( ; LodIndex > 0; --LodIndex )
		{
			if ( InstanceScreenSize < asfloat( Mesh2MeshInstanceStateBuffer[ ScreenPercentageDataOffset + LodIndex ] ) )
			{
				break;
			}
		}
		
		return LodIndex;
	}
]]