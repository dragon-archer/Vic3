Includes = {
	"cw/camera.fxh"
	"cw/gpu_spline.fxh"
}

struct SControlPoint
{
	float2 _Position;
	int _SegmentIdx;
	int _Pad0;
};

StructuredBufferTexture ControlPointBuffer
{
	Ref = PdxBufferTexture0
	Type = SControlPoint
}

struct SAtomics
{
	int _NumEmittedSegments;
	int _NumEmittedPatches;
	int _Pad2;
	int _Pad3;
};

RWStructuredBufferTexture AtomicsBuffer
{
	Ref = PdxRWBufferTexture1
	Type = SAtomics
}

RWStructuredBufferTexture VisibleSegmentsBuffer
{
	Ref = PdxRWBufferTexture2
	type = uint
}

struct SGfxDispatchIndirectArgs
{
	uint _ThreadGroupCountX;
	uint _ThreadGroupCountY;
	uint _ThreadGroupCountZ;
};

RWStructuredBufferTexture DispatchIndirectBuffer
{
	Ref = PdxRWBufferTexture3
	type = SGfxDispatchIndirectArgs
}

struct SGfxDrawInstancedIndirectArgs
{
	uint _VertexCountPerInstance;
	uint _InstanceCount;
	uint _StartVertexLocation;
	uint _StartInstanceLocation;
};

RWStructuredBufferTexture DrawIndirectBuffer
{
	Ref = PdxRWBufferTexture4
	Type = SGfxDrawInstancedIndirectArgs
}

struct SSegmentInfo
{
	int _StartIdx;
	int _EndIdx;
	bool _Looping;
	int _StartPatchIndex;

	int4 _AABB;
};

# TODO[TS]: Should we alias this resource as both RW and not? We only write to it in one rarely used shader.
RWStructuredBufferTexture SegmentInfoBuffer
{
	Ref = PdxRWBufferTexture0
	Type = SSegmentInfo
}

Code
[[
	float2 GetPointOnCubicBSpline( float T, float2 P0, float2 P1, float2 P2, float2 P3 )
	{
		return ( P0 * ( 1.0f - 3.0f * T + 3.0f * T * T - T * T * T ) + P1 * ( 4.0f - 6.0f * T * T + 3.0f * T * T * T ) + P2 * ( 1.0f + 3.0f * T + 3.0f * T * T - 3.0f * T * T * T ) + P3 * T * T * T ) * ( 1.0f / 6.0f );
	}

	float2 GetDerivativeOnCubicBSpline( float T, float2 P0, float2 P1, float2 P2, float2 P3 )
	{
		return ( P0 * ( -3.0f + 6.0f * T - 3.0f * T * T ) + P1 * ( -12.0f * T + 9.0f * T * T ) + P2 * ( 3.0f + 6.0f * T - 9.0f * T * T ) + P3 * ( 3.0f * T * T ) ) * ( 1.0f / 6.0f );
	}

	float2 GetTangentOnCubicBSpline( float T, float2 P0, float2 P1, float2 P2, float2 P3 )
	{
		return normalize( GetDerivativeOnCubicBSpline( T, P0, P1, P2, P3 ) );
	}
]]

ComputeShader =
{
	MainCode CS_SplineSegmentCulling
	{
		VertexStruct CS_INPUT
		{
			# x = Segment index
			# y = unused
			# z = unused
			uint3 DispatchThreadID : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 64 1 1 }
		Code
		[[
			float CalcDistanceFromPlane( float3 Point, float4 Plane )
			{
				return dot( Plane.xyz, Point ) + Plane.w;
			}

			PDX_MAIN
			{
				const uint SegmentIdx = Input.DispatchThreadID.x;

				if ( SegmentIdx >= _SegmentCount )
				{
					return;
				}

				const SSegmentInfo SegmentInfo = SegmentInfoBuffer[ SegmentIdx ];

				// Frustum culling: https://www.cse.chalmers.se/~uffe/vfc.pdf
				for ( int plane = 0; plane < 4; ++plane ) // We skip the near and far plane.
				{
					float3 p = float3( SegmentInfo._AABB.x, _MinWorldHeight, SegmentInfo._AABB.y );
					const float3 PlaneNormal = _FrustumPlanes[ plane ].xyz;

					if ( PlaneNormal.x <= 0.0f )
					{
						p.x = SegmentInfo._AABB.z;
					}

					if ( PlaneNormal.y <= 0.0f )
					{
						p.y = _MaxWorldHeight;
					}

					if ( PlaneNormal.z <= 0.0f )
					{
						p.z = SegmentInfo._AABB.w;
					}

					if ( CalcDistanceFromPlane( p, _FrustumPlanes[ plane ] ) > 0.0f )
					{
						return;
					}
				}

				//Write result.
				uint WrittenSegmentIdx;
				InterlockedAdd( AtomicsBuffer[ 0 ]._NumEmittedSegments, 1, WrittenSegmentIdx );
				VisibleSegmentsBuffer[ WrittenSegmentIdx ] = SegmentIdx;

				// EndIdx is inclusoive. start=0, end=1 would mean one patch between the two points, plus one if we're looping
				int NumControlPoints = SegmentInfo._EndIdx - SegmentInfo._StartIdx + ( SegmentInfo._Looping ? 1 : 0 );
				int PatchWriteOffset;
				// Note: _NumPatchesWritten refers to the number of patches we send to the tessellator (which means that
				// we definitely partially tessellate them for the purposes of UV calculation), but it does not mean that
				// they will output their patch info or be rendered (they still may be culled later).
				InterlockedAdd( AtomicsBuffer[ 0 ]._NumEmittedPatches, NumControlPoints, PatchWriteOffset );
				SegmentInfoBuffer[ SegmentIdx ]._StartPatchIndex = PatchWriteOffset;

				const uint JobSize = 64;
				InterlockedMax( DispatchIndirectBuffer[ 0 ]._ThreadGroupCountX, ( WrittenSegmentIdx + 1 + JobSize - 1 ) / JobSize );
				InterlockedMax( DispatchIndirectBuffer[ 0 ]._ThreadGroupCountY, NumControlPoints ); // Largest segment size
			}
		]]
	}

	MainCode CS_SplineReset
	{
		VertexStruct CS_INPUT
		{
		};

		Input = "CS_INPUT"
		NumThreads = { 1 1 1 }
		Code
		[[
			PDX_MAIN
			{
				// TODO[TS]: Do we care that some of these could be elided?
				DispatchIndirectBuffer[ 0 ]._ThreadGroupCountX = 0;
				DispatchIndirectBuffer[ 0 ]._ThreadGroupCountY = 0;
				DispatchIndirectBuffer[ 0 ]._ThreadGroupCountZ = 1;

				DrawIndirectBuffer[ 0 ]._VertexCountPerInstance = _TessellationFactor * 2; // Vertex count
				DrawIndirectBuffer[ 0 ]._InstanceCount = 0;
				DrawIndirectBuffer[ 0 ]._StartVertexLocation = 0;
				DrawIndirectBuffer[ 0 ]._StartInstanceLocation = 0;

				AtomicsBuffer[ 0 ]._NumEmittedSegments = 0;
				AtomicsBuffer[ 0 ]._NumEmittedPatches = 0;
				AtomicsBuffer[ 0 ]._Pad2 = 0;
				AtomicsBuffer[ 0 ]._Pad3 = 0;
			}
		]]
	}

	MainCode CS_SplineSegmentAABBGeneration
	{
		VertexStruct CS_INPUT
		{
			# x = Control point index
			# y = unused
			# z = unused
			uint3 DispatchThreadID : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 512 1 1 }
		Code
		[[
			PDX_MAIN
			{
				int ControlPointIdx = Input.DispatchThreadID.x;
				if ( ControlPointIdx >= _ControlPointCount )
				{
					return;
				}

				int SegmentIdx = ControlPointBuffer[ ControlPointIdx ]._SegmentIdx;
				int2 ControlPointPosition = (int2)ControlPointBuffer[ ControlPointIdx ]._Position;

				// NOTE[TS]: Currently this relies on that we're starting from an AABB of (INT32_MAX, INT32_MAX, INT32_MIN, INT_32MIN)
				// Swizzling here makes the value const for some reason, so we just index the vector.
				InterlockedMin( SegmentInfoBuffer[ SegmentIdx ]._AABB[ 0 ], ControlPointPosition.x - (int)_MaxSplineWidth);
				InterlockedMin( SegmentInfoBuffer[ SegmentIdx ]._AABB[ 1 ], ControlPointPosition.y - (int)_MaxSplineWidth);
				InterlockedMax( SegmentInfoBuffer[ SegmentIdx ]._AABB[ 2 ], ControlPointPosition.x + (int)_MaxSplineWidth);
				InterlockedMax( SegmentInfoBuffer[ SegmentIdx ]._AABB[ 3 ], ControlPointPosition.y + (int)_MaxSplineWidth);
			}
		]]
	}

	MainCode CS_SplineTessellate
	{
		VertexStruct CS_INPUT
		{
			# x = Visible segment index
			# y = Control point index within segment
			# z = unused
			uint3 DispatchThreadID : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 64 1 1 }
		Code
		[[
			PDX_MAIN
			{
				// TODO[TS]: Something is funny in this shader, should be gone over and commented well
				int VisibleSegmentIdx = Input.DispatchThreadID.x;
				if ( VisibleSegmentIdx >= AtomicsBuffer[ 0 ]._NumEmittedSegments )
				{
					return;
				}

				int SegmentIdx = VisibleSegmentsBuffer[ VisibleSegmentIdx ];
				SSegmentInfo SegmentInfo = SegmentInfoBuffer[ SegmentIdx ];

				uint ControlPointIdx = SegmentInfo._StartIdx + Input.DispatchThreadID.y;
				if ( ControlPointIdx > SegmentInfo._EndIdx )
				{
					return;
				}

				SControlPoint Point1 = ControlPointBuffer[ ControlPointIdx + 0 ];
				SControlPoint Point2 = ControlPointBuffer[ ControlPointIdx + 1 ];
				SControlPoint Point3 = ControlPointBuffer[ ControlPointIdx + 2 ];

				float2 Point0Position;
				float2 Point1Position = Point1._Position;
				float2 Point2Position;
				float2 Point3Position;

				// 0 = First control point in segment
				uint LastLocalControlPointIdx = SegmentInfo._EndIdx - SegmentInfo._StartIdx;
				uint LocalControlPointIdx = ControlPointIdx - SegmentInfo._StartIdx;

				int PatchIdx = SegmentInfo._StartPatchIndex + Input.DispatchThreadID.y;
				PatchDataBuffer[ PatchIdx ]._SegmentIdx = SegmentIdx;
				PatchDataBuffer[ PatchIdx ]._IdxWithinEmittedPatch = LocalControlPointIdx;

				// Handle control points within a segment
				if ( LocalControlPointIdx < LastLocalControlPointIdx )
				{
					Point2Position = ControlPointBuffer[ ControlPointIdx + 1 ]._Position;

					float2 ControlPointDelta = Point2Position - Point1Position;

					PatchDataBuffer[ PatchIdx ]._StartControlPoint = ControlPointIdx;
					PatchDataBuffer[ PatchIdx ]._EndControlPoint = ControlPointIdx + 1;

					if ( LocalControlPointIdx == 0 )
					{
						if ( SegmentInfo._Looping )
						{
							Point0Position = ControlPointBuffer[ SegmentInfo._EndIdx ]._Position;
						}
						else
						{
							Point0Position = Point1Position - ControlPointDelta;
						}
					}

					if ( LocalControlPointIdx > 0 )
					{
						Point0Position = ControlPointBuffer[ ControlPointIdx - 1 ]._Position;
					}

					if ( LocalControlPointIdx < LastLocalControlPointIdx - 1 )
					{
						Point3Position = ControlPointBuffer[ ControlPointIdx + 2 ]._Position;
					}

					if ( LocalControlPointIdx == LastLocalControlPointIdx - 1 )
					{
						if ( SegmentInfo._Looping )
						{
							Point3Position = ControlPointBuffer[ SegmentInfo._StartIdx ]._Position;
						}
						else
						{
							Point3Position = Point2Position + ControlPointDelta;
						}
					}
				}

				// Handle last control point within a segment
				if ( LocalControlPointIdx == LastLocalControlPointIdx )
				{
					Point0Position = ControlPointBuffer[ ControlPointIdx - 1 ]._Position;

					if ( SegmentInfo._Looping )
					{
						// If we are looping, we need to adjust our right control point to point back at the start.
						Point2Position = ControlPointBuffer[ SegmentInfo._StartIdx ]._Position;
						Point3Position = ControlPointBuffer[ SegmentInfo._StartIdx + 1 ]._Position;
					}
					else
					{
						return;
					}
				}

				// Increment number of indirect instances, which also is the index which we write into
				// TODO[TS]: This is a bit scary! We're relying on that the sum of the emitted patches is equal to the final _InstanceCount!
				InterlockedAdd( DrawIndirectBuffer[ 0 ]._InstanceCount, 1 );

				float Length = 0.0f;
				float2 PreviousPosition;
				const float PER_TESSELLATED_POINT_T = 1.0 / ( (float)(_TessellationFactor - 1 ) );
				for ( int i = 0; i < _TessellationFactor; ++i )
	 			{
					float CurveT = float( i ) * PER_TESSELLATED_POINT_T;
					float2 Position = GetPointOnCubicBSpline( CurveT, Point0Position, Point1Position, Point2Position, Point3Position );
					PatchDataBuffer[ PatchIdx ]._Points[ i ].xy = Position;
					float2 Tangent = GetTangentOnCubicBSpline( CurveT, Point0Position, Point1Position, Point2Position, Point3Position );
					PatchDataBuffer[ PatchIdx ]._Points[ i ].zw = float2( Tangent.y, -Tangent.x );

					if ( i > 0 )
					{
						// TODO[TS]: This behavior is not completely correct! We should only be grabbing t = 0/.3/.6/1 points for length consideration
						// (this is for when we have adaptive tessellation - tessellation count should not influence UVs)
						Length += length( Position - PreviousPosition );
					}
					PreviousPosition = Position;
				}

				PatchLengthsBuffer[ PatchIdx ] = uint( Length * SCALING_FACTOR );
			}
		]]
	}
}

Effect SplineCull
{
	ComputeShader = "CS_SplineSegmentCulling"
}

Effect SplineTessellate
{
	ComputeShader = "CS_SplineTessellate"
}

Effect SplineReset
{
	ComputeShader = "CS_SplineReset"
}

Effect SplineSegmentAABBGeneration
{
	ComputeShader = "CS_SplineSegmentAABBGeneration"
}
