Code
[[
	// The C++ layout is SVariationRenderConstants followed by CDecalEntityData::SMeshData followed by SColorMaskRemapInterval
	//	struct SVariationRenderConstants
	//	{
	//		struct STransform
	//		{
	//			float		_Scale = 1.0f;
	//			float		_Rotation = 0.0f;
	//			CVector2f	_Offset = CVector2f::Zero();
	//		};
	//		STransform	_Transforms[4];
	//		CVector4f	_ColorMaskIndices;
	//		CVector4f	_NormalMapIndices;
	//		CVector4f	_PropertyIndices;
	//		float		_RandomNumber;
	//		float		_UseColorOverrides; // Used as bool
	//	};
	//	struct SColorMaskRemapInterval
	//	{
	//		CVector2f _Interval = CVector2f{ 0.0f, 1.0f };
	//	};
	//	struct SMeshData
	//	{
	//		float _BodyPartIndex = 0.0f;
	//	};

	// Also, note thata the Data[] array is of type float4.

	struct SPatternDesc
	{
		float 	_Scale;
		float	_Rotation;
		float2	_Offset;
		float	_ColorMaskIndex;
		float	_NormalMapIndex;
		float	_PropertyMapIndex;
		bool	_UseColorOverrides;
		bool	_UseOpacity;
	};

	SPatternDesc GetPatternDesc( uint InstanceIndex, uint PatternIndex )
	{
		SPatternDesc Desc;
		uint Offset = InstanceIndex + PDXMESH_USER_DATA_OFFSET;
		Desc._Scale = Data[Offset + PatternIndex].r;
		Desc._Rotation = Data[Offset + PatternIndex].g;
		Desc._Offset = Data[Offset + PatternIndex].ba;
		Desc._ColorMaskIndex = Data[Offset + 4][PatternIndex];
		Desc._NormalMapIndex = Data[Offset + 5][PatternIndex];
		Desc._PropertyMapIndex = Data[Offset + 6][PatternIndex];
		Desc._UseOpacity = Data[Offset + 7][PatternIndex] > 0.0f;
		Desc._UseColorOverrides = Data[Offset + 8].g > 0.0f;
		return Desc;
	}

	float GetRandomNumber( uint InstanceIndex )
	{
		uint Offset = InstanceIndex + PDXMESH_USER_DATA_OFFSET + 8;
		return Data[Offset].r;
	}

	float2 GetColorMaskRemapInterval( uint InstanceIndex )
	{
		uint Offset = InstanceIndex + PDXMESH_USER_DATA_OFFSET + 8;
		return Data[Offset].ba;
	}

	uint GetBodyPartIndex( uint InstanceIndex )
	{
		uint Offset = InstanceIndex + PDXMESH_USER_DATA_OFFSET + 9;
		return uint( Data[Offset].r );
	}
]]
