
Code
[[
	#define ArrowOpacity 			1.0									// Transparency of arrow

	// Base colors, inversed when passed by unit
	#define LandBaseColor 			float3( 0.21, 0.175, 0.175 )		// Base color of arrow
	#define LandOutlineColorMult 	3.0									// Outline color of arrow
	#define WaterBaseColor 			float3( 0.0275, 0.0825, 0.275 )		// Base color of arrow in water
	#define WaterOutlineColorMult 	3.5									// Outline color of arrow in water

	#define ArrowHighlightColor 		float3( 1.0, 0.5, 0.1 )			// Color of selection highlight
	#define ArrowHighlightAreaSize			0.55
	#define ArrowHighlightAreaSoftness		0.01
	#define ArrowHighlightAreaEndsLength	0.03
	#define ArrowHighlightAreaEndsSoftness	0.05
	#define ArrowNonSelectedFade			0.4

	// Settings for the inner animated arrow
	#define ArrowSpacing 			4.0									// Spacing between each arrow, lower means more small arrows
	#define ArrowSpeed 				1.0									// Animation speed
	#define ArrowUvScaling 			1.0									// Scale of the inner small arrow

	// FLatmap settings
	#define FlatmapOpacity 			1.0									// Spacing between each arrow, lower means more small arrows
	#define FlatmapArrowSpacing 	2.0									// Animation speed
	#define FlatmapUvScaling 		0.2									// Scale of the inner small arrow

]]