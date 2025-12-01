# SJominiEnvironmentValues
ConstantBuffer( JominiEnvironment )
{
	float3 	AmbientPosX;
	float	CubemapIntensity;
	float3 	AmbientNegX;
	float3 	AmbientPosY;
	float3 	AmbientNegY;
	float3 	AmbientPosZ;
	float3 	AmbientNegZ;
	float3 	ShadowAmbientPosX;
	float3 	ShadowAmbientNegX;
	float3 	ShadowAmbientPosY;
	float3 	ShadowAmbientNegY;
	float3 	ShadowAmbientPosZ;
	float3 	ShadowAmbientNegZ;
	float	FogMax;
	
	float3	SunDiffuse;
	float	SunIntensity;
	float3	ToSunDir;
	
	float	FogBegin2;
	float3	FogColor;
	float	FogEnd2;

	# this rotation matrix is used to rotate cubemap sampling vectors, thus "faking" a rotation of the cubemap
	float4x4 CubemapYRotation;

	float TreeSwayLoopSpeed;
	float TreeSwayWindStrengthSpatialModifier;
	float TreeSwaySpeed;
	float TreeSwayWindClusterSizeModifier;
	float3 TreeSwayWorldDirection; //will be normalized
	float TreeHeightImpactOnSway;
	float TreeSwayScale;
};
