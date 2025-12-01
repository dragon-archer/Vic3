Includes = {
	"cw/camera.fxh"
	"cw/mesh2/pdx_mesh2_culling.fxh"
}

ComputeShader =
{
	VertexStruct CS_INPUT
	{
		uint3 GlobalId : PDX_DispatchThreadID
		uint LocalIndex : PDX_GroupIndex
	};

	MainCode ComputeShader_ClearDrawcallBuffer
	{
		ConstantBuffer( PdxConstantBuffer0 )
		{
			uint _NumDrawcalls;
		};
		
		Input = "CS_INPUT"
		NumThreads = { 128 1 1 }
		Code 
		[[
			PDX_MAIN
			{
				uint DrawcallIndex = min( Input.GlobalId.x, _NumDrawcalls );
				uint DrawcallBufferIndex = DrawcallIndex * 5; // Each drawcall argument is 5 32 bit values
				
				Mesh2DrawcallRwBuffer[DrawcallBufferIndex + 1] = 0; // Second value is "_InstanceCount"
			}
		]]
	}
	
	MainCode ComputeShader_DoCulling
	{
		Texture DepthPyramid
		{
			Ref = PdxTexture0
			format = float
		}
		Sampler DepthPyramidSampler
		{
			MagFilter = "Point"
			MinFilter = "Point"
			MipFilter = "Point"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}

		ConstantBuffer( PdxConstantBuffer0 )
		{
			uint2 _DepthPyramidSize;
			uint _DepthPyramidMaxMipLevel;
			uint _NumInstances;
			uint _SubPassIndex;
			float _LodScale;
		};
		
		ConstantBuffer( PdxConstantBuffer1 )
		{
			float4 _FrustumPlanes[6];
		};
		
		Input = "CS_INPUT"
		NumThreads = { 128 1 1 }
		Code 
		[[
			void WriteMeshes( uint DataOffset, uint NumMeshes, uint InstanceIndex )
			{
				for ( uint i = 0; i < NumMeshes; ++i )
				{
					uint RenderStateIndex = Mesh2MeshInstanceStateBuffer[DataOffset++];
					uint BatchStateIndex = GetBatchStateIndex( RenderStateIndex, _SubPassIndex );
					if ( BatchStateIndex == UINT32_MAX )
					{
						continue;
					}
					
					uint DrawcallBufferIndex = BatchStateIndex * 5; // Drawcall buffer matches batch state array, each drawcall argument is 5 32 bit values
				
					uint IndexToWrite = 0;
					InterlockedAdd( Mesh2DrawcallRwBuffer[DrawcallBufferIndex + 1], 1, IndexToWrite ); // Increment "_InstanceCount", we also use the returned value as the position we should write into
					
					uint StartInstanceLocation = Mesh2DrawcallRwBuffer[DrawcallBufferIndex + 4];
					Mesh2InstanceIndicesRwBuffer[StartInstanceLocation + IndexToWrite] = InstanceIndex;
				}
			}
			
			void WriteMeshesForUnlodded( SMeshInstanceStateData MeshInstanceStateData, SInstanceIndexAndMeshInstanceStateIndex InstanceIndexAndMeshInstanceStateIndex )
			{
				uint DataOffset = ( InstanceIndexAndMeshInstanceStateIndex._MeshInstanceStateIndex * PDX_MESH2_MESH_INSTANCE_STATE_DATA_STRIDE ) + 6 + MeshInstanceStateData._NumLods * 3;
				WriteMeshes( DataOffset, MeshInstanceStateData._NumUnloddedMeshes, InstanceIndexAndMeshInstanceStateIndex._InstanceIndex );
			}
			
			void WriteMeshesForLod( SMeshInstanceStateData MeshInstanceStateData, SInstanceIndexAndMeshInstanceStateIndex InstanceIndexAndMeshInstanceStateIndex, uint Lod )
			{
				uint MeshLodDataOffset = ( InstanceIndexAndMeshInstanceStateIndex._MeshInstanceStateIndex * PDX_MESH2_MESH_INSTANCE_STATE_DATA_STRIDE ) + 6;
				uint NumMeshes = Mesh2MeshInstanceStateBuffer[MeshLodDataOffset + MeshInstanceStateData._NumLods + Lod];
				uint LodDataOffset = Mesh2MeshInstanceStateBuffer[MeshLodDataOffset + MeshInstanceStateData._NumLods * 2 + Lod];
				uint DataOffset = MeshLodDataOffset + LodDataOffset;
				WriteMeshes( DataOffset, NumMeshes, InstanceIndexAndMeshInstanceStateIndex._InstanceIndex );				
			}

			PDX_MAIN
			{			
				if ( Input.GlobalId.x < _NumInstances )
				{
					SInstanceIndexAndMeshInstanceStateIndex InstanceIndexAndMeshInstanceStateIndex = LoadCompactedInstanceIndicesDataForIndex( Input.GlobalId.x );

					float4 BoundingSphere;
					CalculateTransformedBoundingSphere( InstanceIndexAndMeshInstanceStateIndex, BoundingSphere );

				#ifdef PDX_MESH2_ENABLE_FRUSTUM_CULLING
					if ( !SphereIntersectsFrustum( BoundingSphere.xyz, BoundingSphere.w, _FrustumPlanes ) )
					{
						return;
					}
				#endif
					
				#ifdef PDX_MESH2_ENABLE_OCCLUSION_CULLING
					float4 DepthPyramidUvRect;
					float DepthPyramidLevel;
					float SphereDepth;
					if ( CalculateOcclusionSettings( BoundingSphere, ZNear, ViewMatrix, ProjectionMatrix, _DepthPyramidSize, _DepthPyramidMaxMipLevel, DepthPyramidUvRect, DepthPyramidLevel, SphereDepth ) )
					{
						float4 DepthPyramidDepths = float4(
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.xy, DepthPyramidLevel ).x,
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.zy, DepthPyramidLevel ).x,
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.xw, DepthPyramidLevel ).x,
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.zw, DepthPyramidLevel ).x
						);
						float DepthPyramidDepth = max( max( DepthPyramidDepths[0], DepthPyramidDepths[1] ), max( DepthPyramidDepths[2], DepthPyramidDepths[3] ) );			
						
						if ( SphereDepth > DepthPyramidDepth )
						{
							return;
						}
					}
				#endif
				
					// If we reach here we are visible
				
					SMeshInstanceStateData MeshInstanceStateData = LoadMeshInstanceStateData( InstanceIndexAndMeshInstanceStateIndex._MeshInstanceStateIndex );
					
					// Write out all the unlodded meshes
					WriteMeshesForUnlodded( MeshInstanceStateData, InstanceIndexAndMeshInstanceStateIndex );
					
					// Write out active lodded meshes if we have lods
					if ( MeshInstanceStateData._NumLods > 0 )
					{
						uint Lod = CalculateLod( MeshInstanceStateData, InstanceIndexAndMeshInstanceStateIndex, BoundingSphere, _LodScale );
						WriteMeshesForLod( MeshInstanceStateData, InstanceIndexAndMeshInstanceStateIndex, Lod );
					}
				}
			}
		]]
	}
}

Effect Mesh2_ClearDrawcallBuffer
{
	ComputeShader = "ComputeShader_ClearDrawcallBuffer"
}

Effect Mesh2_DoCulling
{
	ComputeShader = "ComputeShader_DoCulling"
}
