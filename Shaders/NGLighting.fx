#include "NGLighting-Shader.fxh"

technique NGLighting<
	ui_label = "NiceGuy Lighting (GI/Reflection)";
	ui_tooltip = "            NiceGuy Lighting 0.9.2 beta            \n"
				 "                  ||By Ehsan2077||                 \n"
				 "|Use with ReShade_MotionVectors at quarter detail.|\n"
				 "|And    don't   forget    to   read   the   hints.|";
>
{
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = GBuffer1;
		RenderTarget0 = SSSR_NormTex;
		RenderTarget1 = SSSR_RoughTex;
	}
#if __RENDERER__ >= 0xa000 // If DX10 or higher
	pass LowResGBuffer
	{
		VertexShader = PostProcessVS;
		PixelShader = CopyGBufferLowRes;
		RenderTarget0 = SSSR_LowResDepthTex;
	}
#endif //RESOLUTION_SCALE
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = RayMarch;
		RenderTarget0 = SSSR_ReflectionTex;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalFilter;
		RenderTarget0 = SSSR_FilterTex0;
		RenderTarget1 = SSSR_HLTex0;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = HistoryBuffer;
		RenderTarget0 = SSSR_POGColTex;
		RenderTarget1 = SSSR_HLTex1;
		RenderTarget2 = SSSR_HistoryTex;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter0;
		RenderTarget0 = SSSR_FilterTex1;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter1;
		RenderTarget0 = SSSR_FilterTex0;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter2;
		RenderTarget0 = SSSR_FilterTex1;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter3;
		RenderTarget0 = SSSR_FilterTex0;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalStabilizer;
		RenderTarget0 = SSSR_FilterTex1;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalStabilizer_CopyBuffer;
		RenderTarget0 = SSSR_FilterTex2;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = Output;
	}
}
