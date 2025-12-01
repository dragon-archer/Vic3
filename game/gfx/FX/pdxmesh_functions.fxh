Includes = {
	"cw/pdxmesh.fxh"
	"cw/terrain.fxh"
	"cw/camera.fxh"
	"cw/utility.fxh"
	"jomini/jomini_water.fxh"
	"sharedconstants.fxh"
}

VertexShader =
{
	TextureSampler WindMapTree
	{
		Ref = WindMapTree
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler FlowMapTexture
	{
		Ref = JominiWaterTexture2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
}

PixelShader =
{
	TextureSampler SolLowTexture
	{
		Ref = SolLowTexture
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
}

struct SStandardMeshUserData
{
	float _CountryIndex;
	float _RandomValue;
	float _Padding02;
	float _Padding03;
	float4 _OffsetAndScale;
};

struct SBuildingMeshUserdata
{
	float4 _LightColor;
	float _SolValue;
	float _RandomValue;
	float _ShouldLightActivate;
	float _Padding04;
};

struct SRevolutionMeshUserdata
{
	float _IgColorIndex;
	float _Padding01;
	float _Padding02;
	float _Padding03;
};

Code
[[
	uint GetUserDataUint( uint InstanceIndex )
	{
		return uint( Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ].x );
	}
	float GetUserDataFloat( uint InstanceIndex )
	{
		return uint( Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ].x );
	}
	int GetUserDataCountryIndex( uint InstanceIndex )
	{
		return int( Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ].x );
	}
	float4 GetUserDataBuildingLightColor( uint InstanceIndex )
	{
		return Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ];
	}
	float GetUserDataPrettyValue( uint InstanceIndex )
	{
		return Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 1 ].x;
	}
	float GetUserDataRandomValueCity( uint InstanceIndex )
	{
		return Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 1 ].y;
	}
	float GetUserDataShouldLightActivate( uint InstanceIndex )
	{
		return Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 1 ].z;
	}

	SStandardMeshUserData GetStandardMeshUserData( uint InstanceIndex )
	{
		SStandardMeshUserData UserData;
		UserData._CountryIndex = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ].x;
		UserData._RandomValue = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ].y;
		UserData._OffsetAndScale = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 1 ];
		return UserData;
	}
]]

VertexShader =
{
	Code
	[[

		void CalculateSineAnimation( float2 UV, inout float3 Position, inout float3 Normal, inout float4 Tangent, float Seed )
		{
			float AnimSeed = UV.x;
			const float LARGE_WAVE_FREQUENCY = 3.14f;	// Higher values simulates higher wind speeds / more turbulence
			const float SMALL_WAVE_FREQUENCY = 9.0f;	// Higher values simulates higher wind speeds / more turbulence
			const float WAVE_LENGTH_POW = 1.0f;			// Higher values gives higher frequency at the end of the flag
			const float WAVE_LENGTH_INV_SCALE = 7.0f;	// Higher values gives higher frequency overall
			const float WAVE_SCALE = 0.2f;				// Higher values gives a stretchier flag
			const float ANIMATION_SPEED = 0.5f;			// Speed

			float RandomOffset = CalcRandom( Seed );
			float Time = ( GlobalTime + RandomOffset ) * ANIMATION_SPEED;

			float LargeWave = sin( Time * LARGE_WAVE_FREQUENCY );
			float SmallWaveV = Time * SMALL_WAVE_FREQUENCY - pow( AnimSeed, WAVE_LENGTH_POW ) * WAVE_LENGTH_INV_SCALE;
			float SmallWaveD = -( WAVE_LENGTH_POW * pow( AnimSeed, WAVE_LENGTH_POW ) * WAVE_LENGTH_INV_SCALE );
			float SmallWave = sin( SmallWaveV );
			float CombinedWave = SmallWave + LargeWave;

			float Wave = WAVE_SCALE * AnimSeed * CombinedWave;
			float Derivative = WAVE_SCALE * ( LargeWave + SmallWave + cos( SmallWaveV ) * SmallWaveD );
			float3 AnimationDir = cross( Tangent.xyz, float3( 0.0, 1.0, 0.0 ) );

			Position += AnimationDir * Wave;

			float2 WaveTangent = normalize( float2( 1.0f, Derivative ) );
			float3 WaveNormal = normalize( float3( WaveTangent.y, 0.0f, -WaveTangent.x ));
			Normal = normalize( WaveNormal ); // wave normal strength
		}

		float3 WindTransform( float3 Position, float4x4 WorldMatrix )
		{
			float3 WorldSpacePos = mul( WorldMatrix, float4( Position, 1.0f ) ).xyz;
			float2 MapCoords = float2( WorldSpacePos.x / MapSize.x, 1.0 - WorldSpacePos.z / MapSize.y );

			float3 FlowMap = PdxTex2DLod0( FlowMapTexture, MapCoords ).rgb;
			float3 FlowDir = FlowMap.xyz * 2.0 - 1.0;
			FlowDir = FlowDir / ( length( FlowDir ) + 0.000001 ); // Intel did not like normalize()

			float WindMap = PdxTex2DLod0( WindMapTree, MapCoords ).r;

			float WorldX = GetMatrixData( WorldMatrix, 0, 3 );
			float WorldY = GetMatrixData( WorldMatrix, 2, 3 );
			float Noise = CalcNoise( GlobalTime * TreeSwayLoopSpeed + TreeSwayWindStrengthSpatialModifier * float2( WorldX, WorldY ) );
			float WindSpeed = Noise * Noise;
			float Phase = GlobalTime * TreeSwaySpeed + TreeSwayWindClusterSizeModifier * ( WorldX + WorldY );
			float3 Offset = normalize( float3( FlowDir.x, 0.0f, FlowDir.z ) );
			Offset = mul( Offset, CastTo3x3( WorldMatrix ) );
			float HeightFactor = saturate( Position.y * TreeHeightImpactOnSway );
			HeightFactor *= HeightFactor;

			float wave = sin( Phase ) + 0.5f;
			Position += TreeSwayScale * WindMap * HeightFactor * wave * Offset * WindSpeed;

			return Position;
		}

		float3 WindTransformBush( float3 Position, float4x4 WorldMatrix )
		{
			float3 WorldSpacePos = mul( WorldMatrix, float4( Position, 1.0f ) ).xyz;
			float2 MapCoords = float2( WorldSpacePos.x / MapSize.x, 1.0 - WorldSpacePos.z / MapSize.y );

			float3 FlowMap = PdxTex2DLod0( FlowMapTexture, MapCoords ).rgb;
			float3 FlowDir = FlowMap.xyz * 2.0 - 1.0;
			FlowDir = FlowDir / ( length( FlowDir ) + 0.000001 ); // Intel did not like normalize()

			float WindMap = PdxTex2DLod0( WindMapTree, MapCoords ).r;

			float WorldX = GetMatrixData( WorldMatrix, 0, 3 );
			float WorldY = GetMatrixData( WorldMatrix, 2, 3 );
			float Noise = CalcNoise( GlobalTime * TreeSwayLoopSpeed + TreeSwayWindStrengthSpatialModifier * float2( WorldX, WorldY ) );
			float WindSpeed = Noise * Noise;
			float Phase = GlobalTime * TreeSwaySpeed + TreeSwayWindClusterSizeModifier * ( WorldX + WorldY );
			float3 Offset = normalize( float3( FlowDir.x, 0.0f, FlowDir.z ) );
			Offset = mul( Offset, CastTo3x3( WorldMatrix ) );
			float HeightFactor = saturate( Position.y * TreeHeightImpactOnSway * BUSH_TREE_HEIGHT_IMPACT );
			HeightFactor *= HeightFactor;

			float wave = sin( Phase ) + 0.5f;
			Position += TreeSwayScale * BUSH_TREE_SWAY_SCALE * WindMap * HeightFactor * wave * Offset * WindSpeed;

			return Position;
		}

		float3 WindTransformMedium( float3 Position, float4x4 WorldMatrix )
		{
			float3 WorldSpacePos = mul( WorldMatrix, float4( Position, 1.0f ) ).xyz;
			float2 MapCoords = float2( WorldSpacePos.x / MapSize.x, 1.0 - WorldSpacePos.z / MapSize.y );

			float3 FlowMap = PdxTex2DLod0( FlowMapTexture, MapCoords ).rgb;
			float3 FlowDir = FlowMap.xyz * 2.0 - 1.0;
			FlowDir = FlowDir / ( length( FlowDir ) + 0.000001 ); // Intel did not like normalize()

			float WindMap = PdxTex2DLod0( WindMapTree, MapCoords ).r;

			float WorldX = GetMatrixData( WorldMatrix, 0, 3 );
			float WorldY = GetMatrixData( WorldMatrix, 2, 3 );
			float Noise = CalcNoise( GlobalTime * TreeSwayLoopSpeed + TreeSwayWindStrengthSpatialModifier * float2( WorldX, WorldY ) );
			float WindSpeed = Noise * Noise;
			float Phase = GlobalTime * TreeSwaySpeed * MEDIUM_TREE_SWAY_SPEED + TreeSwayWindClusterSizeModifier * ( WorldX + WorldY );
			float3 Offset = normalize( float3( FlowDir.x, 0.0f, FlowDir.z ) );
			Offset = mul( Offset, CastTo3x3( WorldMatrix ) );
			float HeightFactor = saturate( Position.y * TreeHeightImpactOnSway * MEDIUM_TREE_HEIGHT_IMPACT );
			HeightFactor *= HeightFactor;

			float wave = sin( Phase ) + 0.5f;
			Position += TreeSwayScale * MEDIUM_TREE_SWAY_SCALE * WindMap * HeightFactor * wave * Offset * WindSpeed;

			return Position;
		}

		float3 WindTransformTall( float3 Position, float4x4 WorldMatrix )
		{
			float3 WorldSpacePos = mul( WorldMatrix, float4( Position, 1.0f ) ).xyz;
			float2 MapCoords = float2( WorldSpacePos.x / MapSize.x, 1.0 - WorldSpacePos.z / MapSize.y );

			float3 FlowMap = PdxTex2DLod0( FlowMapTexture, MapCoords ).rgb;
			float3 FlowDir = FlowMap.xyz * 2.0 - 1.0;
			FlowDir = FlowDir / ( length( FlowDir ) + 0.000001 ); // Intel did not like normalize()

			float WindMap = PdxTex2DLod0( WindMapTree, MapCoords ).r;

			float WorldX = GetMatrixData( WorldMatrix, 0, 3 );
			float WorldY = GetMatrixData( WorldMatrix, 2, 3 );
			float Noise = CalcNoise( GlobalTime * TreeSwayLoopSpeed + TreeSwayWindStrengthSpatialModifier * float2( WorldX, WorldY ) );
			float WindSpeed = Noise * Noise;
			float Phase = GlobalTime * TreeSwaySpeed * TALL_TREE_SWAY_SPEED + TreeSwayWindClusterSizeModifier * ( WorldX + WorldY );
			float3 Offset = normalize( float3( FlowDir.x, 0.0f, FlowDir.z ) );
			Offset = mul( Offset, CastTo3x3( WorldMatrix ) );
			float HeightFactor = saturate( Position.y * TreeHeightImpactOnSway * TALL_TREE_HEIGHT_IMPACT );
			HeightFactor *= HeightFactor;

			float wave = sin( Phase ) + 0.5f;
			Position += TreeSwayScale * TALL_TREE_SWAY_SCALE * WindMap * HeightFactor * wave * Offset * WindSpeed;

			return Position;
		}

		float3 SnapToWaterLevel( float3 PositionY, float4x4 WorldMatrix )
		{
			float3 WorldSpacePos = mul( WorldMatrix, float4( float3( 0.0f, 0.0f, 0.0f ), 1.0f ) ).xyz;

			float Height = GetHeight( WorldSpacePos.xz );
			PositionY += ( _WaterHeight - WorldSpacePos.y );

			return PositionY;
		}

	]]
}

PixelShader =
{
	Code
	[[
		void DebugRandomSeed( inout float3 Color, float Seed, float Variance = 1.0 )
		{
			Color = float3( 1.0, 0.0, 0.0 );
			float3 HSV_ = RGBtoHSV( Color );
			HSV_.x += float( Seed * Variance );
			Color = HSVtoRGB( HSV_ );
		}

		void AddBacklight( inout float3 Base, float3 AddColor, float3 Normal, float3 Light, float Intensity = 0.5 )
		{
				float3 InverseLight = saturate( 1.0 - dot( Normal, Light ) );
				Base = saturate( ( Base + ( AddColor * Intensity * InverseLight ) ) );
		}

		void ApplyStandardOfLiving( inout float3 Color, float2 Uv, float SolValue, float3 WorldSpacePos, float3 Normal )
		{
			float SolHigh = _SolDebugHigh;
			float SolLow = _SolDebugLow;

			if ( SolValue < 0.5 )
			{
				SolLow += SolValue * 2.0;
			}
			else
			{
				SolHigh += ( SolValue - 0.5 ) * 2.0;
			}

			SolHigh = saturate( SolHigh );
			SolLow = saturate( SolLow );

			float LocalHeight = WorldSpacePos.y - GetHeight( WorldSpacePos.xz );
			float TintAngleModifier = saturate( 1.0 - dot( Normal, float3( 0.0, 1.0, 0.0 ) ) );	// Removes tint from angles facing upwards
			float TintTopBlend = saturate( RemapClamped( LocalHeight - _SolHighTintHeight + _SolHighTintContrast, 0.0, _SolHighTintContrast, 0.0, 1.0 ) );
			float TintBottomBlend = ( 1.0 - RemapClamped( LocalHeight - _SolLowTintHeight, 0.0, _SolLowTintContrast, 0.0, 1.0 ) );

			float3 SolLowColor = PdxTex2D( SolLowTexture, Uv ).rgb;

			float3 HSV_ = RGBtoHSV( Color );
			HSV_.x *= _SolHighHue; 			// Hue
			HSV_.y *= _SolHighSaturation; 	// Saturation
			HSV_.z *= _SolHighValue; 		// Value
			float3 SaturatedColor = saturate( HSVtoRGB( HSV_ ) );

			Color = lerp( Color, SaturatedColor, TintTopBlend * SolHigh );
			Color = lerp( Color, Overlay( Color, SolLowColor ), TintBottomBlend * TintAngleModifier * SolLow );
		}
	]]
}
