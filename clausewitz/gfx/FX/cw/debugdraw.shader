
VertexStruct VS_INPUT
{
    float3 vPosition  : POSITION;
};

VertexStruct VS_OUTPUT
{
    float4  vPosition : PDX_POSITION;
 	float4  vColor	  : TEXCOORD1;
};


ConstantBuffer( PdxConstantBuffer0 )
{
	float4x4 Transform;
	float4 Color;
};


VertexShader =
{
	MainCode VertexShader
	{
		Input = "VS_INPUT"
		Output = "VS_OUTPUT"
		Code	
		[[
			PDX_MAIN
			{
			    VS_OUTPUT Out;
				
				float3 Position = Input.vPosition.xyz;
				
			    Out.vPosition = FixProjectionAndMul( Transform, float4( Position, 1.0 ) );	
				Out.vColor = Color;
			    return Out;
			}
		]]
	}
	
}

PixelShader =
{
	MainCode PixelShader
	{	
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
			  	float4 OutColor = Input.vColor;
			    return OutColor;
			}
		]]
	}
}

RasterizerState rasterizer_no_culling
{
	CullMode = "none"
}

Effect DebugDraw
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	RasterizerState = "rasterizer_no_culling"
}

