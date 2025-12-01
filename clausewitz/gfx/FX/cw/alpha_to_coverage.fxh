PixelShader =
{
	Code
	[[
		// Implements https://medium.com/@bgolus/anti-aliased-alpha-test-the-esoteric-alpha-to-coverage-8b177335ae4f

	    float RescaleAlphaByMipLevel( float Alpha, float2 UV, PdxTextureSampler2D Sampler )
	    {
	    	// 0.25 approximates the loss of density from mip mapping
			const float MIP_SCALE = 0.25f;
			return Alpha * ( 1.0f + ( PdxCalculateLod( Sampler, UV ) * MIP_SCALE ) );
	    }

		// This `Cutoff` value (between [0.0, 1.0]) can be tweaked to change the "thickness"
		// of the edges where the transparency is, lower value -> thicker edge
	    float SharpenAlpha( float Alpha, float Cutoff )
	    {
			float Result = ( ( Alpha - Cutoff ) / max( fwidth( Alpha ), 0.0001f ) ) + 0.5f;
			return saturate( Result );
	    }
	]]
}
