Includes = {
	"jomini/texture_decals_base.fxh"
	"jomini/portrait_user_data.fxh"
}

PixelShader =
{
	TextureSampler CoaPatternMask
	{
		Ref = PdxMeshCustomTexture5
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}

	Code
	[[
		#ifdef COA_ENABLED
			void ApplyCoa( in VS_OUTPUT_PDXMESHPORTRAIT Input, inout float4 Diffuse, float4 Color1, float4 Color2, float2 Offset, float2 Scale, PdxTextureSampler2D CoaTexture ) 
			{
				float4 Mask = PdxTex2D( CoaPatternMask, Input.UV0 );

				// Check for coa first
				if ( Mask.b > 0.5f ) {
					float2 UV = Offset + Input.UV2 * Scale;
					Diffuse *= PdxTex2D( CoaTexture, UV );
				} 
				else if ( Mask.r > 0.5f ) 
				{
					Diffuse *= Color1;
				} else if ( Mask.g > 0.5f ) {
					Diffuse *= Color2;
				}
			}			
		#endif
	]]
}
