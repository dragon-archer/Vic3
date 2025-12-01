# Contains common structures used for all GPU spline shaders.

ConstantBuffer( GpuSplineConstants )
{
	int _SegmentCount;
	int _SegmentBufferSize;
	int _ControlPointCount;
	int _ControlPointBufferSize;

	int _TessellationFactor;
	float _MinWorldHeight;
	float _MaxWorldHeight;
	float _MaxSplineWidth;

	float4 _FrustumPlanes[4];
}

struct SPatchData
{
	float4 _Points[8];

	int _StartControlPoint;
	int _EndControlPoint;
	int _SegmentIdx;
	int _IdxWithinEmittedPatch;
};

RWStructuredBufferTexture PatchDataBuffer
{
	Ref = GpuSplinePatchDataBuffer
	Type = SPatchData
}

RWStructuredBufferTexture PatchLengthsBuffer
{
	Ref = GpuSplinePatchLengthsBuffer
	Type = uint
}

Code
[[
	// We need to do a prefix sum over the lengths of the patches, but we can only do prefix sums
	// on arrays of uints. So we scale by this value first, then scale down afterwards.
	#define SCALING_FACTOR 1000.0f
]]
