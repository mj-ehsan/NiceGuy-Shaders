//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 0.1

//license
//CC0 ^_^


//Thanks Lord of Lunacy, Leftfarian, and other devs for helping me. <3
//Thanks Alea for testing. <3

//Credits:
//Thanks Crosire for ReShade.
//https://reshade.me/

//Thanks Jakob for DRME.
//https://github.com/JakobPCoder/ReshadeMotionEstimation

//I learnt a lot from qUINT_SSR. Thanks Pascal Gilcher.
//https://github.com/martymcmodding/qUINT

//Also a lot from DH_RTGI. Thanks Demien Hambert.
//https://github.com/AlucardDH/dh-reshade-shaders

//Thanks Radegast for Unity Sponza Test Scene.
//https://mega.nz/#!qVwGhYwT!rEwOWergoVOCAoCP3jbKKiuWlRLuHo9bf1mInc9dDGE

//Thanks Timothy Lottes and AMD for the Tonemapper and the Inverse Tonemapper.
//https://gpuopen.com/learn/optimized-reversible-tonemapper-for-resolve/

//Thanks Eric Reinhard for the Luminance Tonemapper and  the Inverse.
//https://www.cs.utah.edu/docs/techreports/2002/pdf/UUCS-02-001.pdf

//Thanks sujay for the noise function. Ported from ShaderToy.
//https://www.shadertoy.com/view/lldBRn

//////////////////////////////////////////
//TO DO
//1- [v]Add another spatial filtering pass
//2- [ ]Add Hybrid GI/Reflection
//3- [ ]Add Simple Mode UI with setup assist
//4- [ ]Add internal comaptibility with Volumetric Fog V1 and V2
//      By using the background texture provided by VFog to blend the Reflection.
//      Then Blending back the fog to the image. This way fog affects the reflection.
//      But the reflection doesn't break the fog.
//5- [ ]Add ACEScg and or Filmic inverse tonemapping as optional alternatives to Timothy Lottes
//6- [ ]Add AO support
//7- [ ]Add second temporal pass after second spatial pass.
//8- [ ]Add Spatiotemporal upscaling. have to either add jitter to the RayMarching pass or a checkerboard pattern.
//9- [ ]Add Smooth Normals.

///////////////Include/////////////////////

#include "ReShadeUI.fxh"
#include "ReShade.fxh"
#if exists("MotionVectors.fxh")
 #include "MotionVectors.fxh"
#endif

uniform float Timer < source = "timer"; >;

#define pix float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

#define LDepth ReShade::GetLinearizedDepth

#define PI 3.1415927
#define PI2 2*PI
#define rad(x) (x/360)*PI2 

//#ifndef MAXIMUM_RAY_STEPS
#undef MAXIMUM_RAY_STEPS
 #define MAXIMUM_RAY_STEPS 32
//#endif

#define RAYSTEPS MAXIMUM_RAY_STEPS

#define AspectRatio (BUFFER_WIDTH/BUFFER_HEIGHT)          

#ifndef RESOLUTION_SCALE_
 #define RESOLUTION_SCALE_ 0.67
#endif

//#ifndef INTERPOLATED_RENDER
// #define INTERPOLATED_RENDER 0
//#endif

//#if INTERPOLATED_RENDER > 0
// #define RENDER_HEIGHT 0.5
//#else
 #define RENDER_HEIGHT 1
//#endif

#ifndef MAX_MipFilter
 #define MAX_MipFilter 2 //Maximum Number of mips for disocclusion filtering.
#endif

#if MAX_MipFilter > 9
 #undef MAX_MipFilter
 #define MAX_MipFilter 9 //Clamps the value to 9 to avoid compiling issues.
#endif

///////////////Include/////////////////////
///////////////Textures-Samplers///////////

texture TexColor : COLOR;
sampler sTexColor {Texture = TexColor; SRGBTexture = false;};

texture TexDepth : DEPTH;
sampler sTexDepth {Texture = TexDepth;};

texture SSSR_ReflectionTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_ReflectionTex { Texture = SSSR_ReflectionTex; };

//texture SSSR_AOTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = R8; };
//sampler sSSSR_AOTex { Texture = SSSR_AOTex; };

texture SSSR_POGColTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_POGColTex { Texture = SSSR_POGColTex; };

texture SSSR_OGColTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_OGColTex { Texture = SSSR_OGColTex; };

texture SSSR_FilterTex0  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex0 { Texture = SSSR_FilterTex0; };

texture SSSR_FilterTex1  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex1 { Texture = SSSR_FilterTex1; };

texture SSSR_FilterTex2  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex2 { Texture = SSSR_FilterTex2; };

texture SSSR_HistoryTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_HistoryTex { Texture = SSSR_HistoryTex; };

texture SSSR_PDepthTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = R8; };
sampler sSSSR_PDepthTex { Texture = SSSR_PDepthTex; };

texture SSSR_PNormalTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_PNormalTex { Texture = SSSR_PNormalTex; };

texture SSSR_NormTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_NormTex { Texture = SSSR_NormTex; };

texture SSSR_PosTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_PosTex { Texture = SSSR_PosTex; };

texture SSSR_HLTex0 { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = R16f; };
sampler sSSSR_HLTex0 { Texture = SSSR_HLTex0; };

texture SSSR_HLTex1 { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = R16f; };
sampler sSSSR_HLTex1 { Texture = SSSR_HLTex1; };

texture SSSR_MaskTex { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = R8; };
sampler sSSSR_MaskTex { Texture = SSSR_MaskTex; };

///////////////Textures-Samplers///////////
///////////////UI//////////////////////////

uniform int Hints<
	ui_text = "This shader is in -ALPHA PHASE-, expect bugs.\n\n"
			  "Advanced categories are unnecessary options that\n"
			  "can break the look of the shader if modified\n"
			  "improperly. Modification of the shader will be\n"
			  "simplified in the future. These complex settings\n"
			  "of the current version will be kept and are accesible\n"
			  "Using PreProcessor Defenitions.\n\n"
			  "To use NiceGuy Lighting for reflections, do all these steps:\n"
			  "1- Blending Options > GI Mode : off\n"
			  "2- Blending Options > AO Intensity : 0\n"
			  "3- Color Management > sRGB to Linear : off\n"
			  "4- Color Management > Inverse Tonemapper Intensity : reduce\n"
			  "5- Color Management > Saturation and color : reduce\n"
			  "6- Ray Tracing > Roughness : reduce\n"
			  "7- Psuedo-Fresnel Exponent : something more than 1";
			  
	ui_category = "Hints - Please Read for good results";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

uniform float fov <
	ui_label = "Field of View";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Set it according to the game's field of view.";
	ui_min = 50;
	ui_max = 120;
> = 70;

uniform float BUMP <
	ui_label = "Bump mapping";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Makes shiny reflections more detailed.";
	ui_min = 0.0;
	ui_max = 1;
> = 0;

uniform float roughness <
	ui_label = "Roughness";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Set to 1 for GI.";
	ui_min = 0.0;
	ui_max = 1.0;
> = 1;

uniform bool TemporalRefine <
	ui_label = "Temporal Refining (EXPERIMENTAL)";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "EXPERIMENTAL! Expect issues\n"
				 "Reduce (Surface depth) and increase (Step Length Jitter)\n"
				 "Then enable this option to have more accurate Ray Marching.";
	ui_category_closed = true;
> = 0;
//#define TemporalRefine false

uniform float RAYINC <
	ui_label = "Ray Increment";
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "Increases ray length at the cost of accuracy.";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 2;
> = 2;

uniform uint UI_RAYSTEPS <
	ui_label = "Max Steps"; 
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "Increases ray length at the cost of performance.";
	ui_category_closed = true;
	ui_min = 1;
	ui_max = RAYSTEPS;
> = 16;

uniform float RAYDEPTH <
	ui_label = "Surface depth";
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "More coherency at the cost of accuracy.";
	ui_category_closed = true;
	ui_min = 0.01;
	ui_max = 5;
> = 1;
//#define RAYDEPTH 10000

uniform float STEPNOISE <
	ui_label = "Step Length Jitter";
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "Reduces artifacts but produces more noise.\n";
				 //"Read (Temporal Refining)'s tooltip for more.";
	ui_category_closed = true;
	ui_min = 0.0;
	ui_max = 0.5;
> = 0.15;

uniform float Tthreshold <
	ui_label = "Temporal Denoiser Threshold";
	ui_type = "slider";
	ui_category = "Denoiser (Advanced)";
	ui_tooltip = "Reduces noise but produces more ghosting.";
	ui_category_closed = true;
> = 0.04;

uniform int MAX_Frames <
	ui_label = "History Length";
	ui_type = "slider";
	ui_category = "Denoiser (Advanced)";
	ui_tooltip = "Higher values increase both the blur size\n"
				 "and the temporal accumulation effectiveness.";
	ui_category_closed = true;
	ui_min = 1;
	ui_max = 64;
> = 64;

uniform float Sthreshold <
	ui_label = "Spatial Denoiser Threshold";
	ui_type = "slider";
	ui_category = "Denoiser (Advanced)";
	ui_tooltip = "Reduces noise at the cost of detail.";
	ui_category_closed = true;
> = 0.04;

uniform bool DualPass <
	ui_type = "radio";
	ui_label = "Additional Filtering";
	ui_category = "Denoiser (Advanced)";
	ui_tooltip = "Makes blur more stable at the little cost of performance.";
	ui_category_closed = true;
> = 1;

uniform bool GI <
	ui_label = "GI Mode";
	ui_category = "Blending Options";
	ui_tooltip = "Enable this and set (Roughness) to 2 to achieve GI.";
> = 1;

uniform bool HLFix <
	ui_label = "Fix Highlights";
	ui_category = "Blending Options";
	ui_tooltip = "Fixes bad blending in bright areas of background/reflections.";
> = 1;

uniform float EXP <
	ui_label = "Psuedo-Fresnel Exponent";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Blending intensity for shiny materials. Set to 0 for GI.";
	ui_min = 0.0;
	ui_max = 10;
> = 0;

uniform float AO_Radius <
	ui_label = "AO Radius";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Radius of the effective Ray Marched AO.";
> = 0.5;

uniform float AO_Intensity <
	ui_label = "AO Intensity";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "AO Intensity :| yes just that...";
> = 0.5;

uniform float depthfade <
	ui_label = "Depth Fade";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Higher values decrease the intesity on distant objects.\n"
				 "Reduces blending issues with in-game fogs.";
	ui_min = 0;
	ui_max = 1;
> = 0.3;

uniform bool LinearConvert <
	ui_type = "radio";
	ui_label = "sRGB to Linear";
	ui_category = "Color Management";
	ui_tooltip = "Converts from sRGB to Linear";
	ui_category_closed = true;
> = 1;

/*uniform bool InvTonemap <
	ui_type = "radio";
	ui_label = "Inverse Tonemapping";
	ui_category = "Color Management";
	ui_tooltip = "reproduces HDR image using Timothy Lottes Inverse Tonemapping";
	ui_category_closed = true;
> = 1;*/

uniform float IT_Intensity <
	ui_type = "slider";
	ui_label = "Inverse Tonemapper Intensity";
	ui_category = "Color Management";
	ui_tooltip = "intensity of Inverse Tonemapping";
	ui_category_closed = true;
	ui_max = 0.9;
> = 0.75;

uniform float2 SatExp <
	ui_type = "slider";
	ui_label = "Saturation || Exposure";
	ui_category = "Color Management";
	ui_tooltip = "Left slider is Saturation. Right one is Exposure.";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 2;
> = float2(1,2);

uniform uint debug <
	ui_type = "combo";
	ui_items = "None\0Reflections\0Depth\0Normal\0TempDebugView\0";
	ui_category = "Extra";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = 0;

uniform float SkyDepth <
	ui_type = "slider";
	ui_label = "Sky Masking Depth";
	ui_tooltip = "Minimum depth to consider sky and exclude from the calculation.";
	ui_category = "Extra";
	ui_category_closed = true;
> = 0.99;

/*uniform float TEMP_UIVAR <
	ui_type = "slider";
	ui_category = "Debug";
	ui_min = 0;
	ui_max = 1;
> = 0.25;*/

uniform int Credits<
	ui_text = "Thanks Lord of Lunacy, Leftfarian, and other devs for helping me. <3\n"
			  "Thanks Alea for testing.<3\n\n"

			  "Credits:\n"
			  "Thanks Crosire for ReShade.\n"
			  "https://reshade.me/\n\n"

			  "Thanks Jakob for DRME.\n"
			  "https://github.com/JakobPCoder/ReshadeMotionEstimation\n\n"

			  "I learnt as lot from qUINT_SSR. Thanks Pascal Gilcher.\n"
			  "https://github.com/martymcmodding/qUINT\n\n"

			  "Also a lot from DH_RTGI. Thanks Demien Hambert.\n"
			  "https://github.com/AlucardDH/dh-reshade-shaders\n\n"
			  
			  "Thanks Nvidia for <<Ray Tracing Gems II>> for ReBlur\n"
			  "https://link.springer.com/chapter/10.1007%2F978-1-4842-7185-8_49\n\n"

			  "Thanks Radegast for Unity Sponza Test Scene.\n"
			  "https://mega.nz/#!qVwGhYwT!rEwOWergoVOCAoCP3jbKKiuWlRLuHo9bf1mInc9dDGE\n\n"

			  "Thanks Timothy Lottes and AMD for the Tonemapper and the Inverse Tonemapper.\n"
			  "https://gpuopen.com/learn/optimized-reversible-tonemapper-for-resolve/\n\n"

			  "Thanks Eric Reinhard for the Luminance Tonemapper and  the Inverse.\n"
			  "https://www.cs.utah.edu/docs/techreports/2002/pdf/UUCS-02-001.pdf\n\n"

			  "Thanks sujay for the noise function. Ported from ShaderToy.\n"
			  "https://www.shadertoy.com/view/lldBRn";
			  
	ui_category = "Credits";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

///////////////UI//////////////////////////
///////////////Vertex Shader///////////////
///////////////Vertex Shader///////////////
///////////////Functions///////////////////

float noise(float2 co)
{
  return frac(sin(dot(co.xy ,float2(1.0,73))) * 437580.5453);
}

float3 noise3dts(float2 co, float s, bool t)
{
	co += sin(Timer/120.347668756453546)*t;
	co += s/16.3542625435332254;
	return float3( noise(co), noise(co+0.6432168421), noise(co+0.19216811));
}

float3 UVtoPos(float2 texcoord)
{
	float3 scrncoord = float3(texcoord.xy*2-1, LDepth(texcoord) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	scrncoord.xy *= scrncoord.z * (rad(fov*0.5));
	scrncoord.x *= AspectRatio;
	//scrncoord.xy *= ;
	
	return scrncoord.xyz;
}

float2 PostoUV(float3 position)
{
	float2 scrnpos = position.xy;
	scrnpos /= rad(fov/2);
	scrnpos.x /= AspectRatio;
	scrnpos /= position.z;
	
	return scrnpos/2 + 0.5;
}
	

float3 Normal(float2 texcoord)
{
	float2 p = pix;
	float3 u,d,l,r,u2,d2,l2,r2;
	
	u = UVtoPos( texcoord + float2( 0, p.y));
	d = UVtoPos( texcoord - float2( 0, p.y));
	l = UVtoPos( texcoord + float2( p.x, 0));
	r = UVtoPos( texcoord - float2( p.x, 0));
	
	p *= 2;
	
	u2 = UVtoPos( texcoord + float2( 0, p.y));
	d2 = UVtoPos( texcoord - float2( 0, p.y));
	l2 = UVtoPos( texcoord + float2( p.x, 0));
	r2 = UVtoPos( texcoord - float2( p.x, 0));
	
	/*u = tex2Dfetch( sSSSR_PosTex, texcoord + int2( 0, p.y)).rgb;
	d = tex2Dfetch( sSSSR_PosTex, texcoord - int2( 0, p.y)).rgb;
	l = tex2Dfetch( sSSSR_PosTex, texcoord + int2( p.x, 0)).rgb;
	r = tex2Dfetch( sSSSR_PosTex, texcoord - int2( p.x, 0)).rgb;
	
	p *= 2;
	
	u2 = tex2Dfetch( sSSSR_PosTex, texcoord + int2( 0, p.y)).rgb;
	d2 = tex2Dfetch( sSSSR_PosTex, texcoord - int2( 0, p.y)).rgb;
	l2 = tex2Dfetch( sSSSR_PosTex, texcoord + int2( p.x, 0)).rgb;
	r2 = tex2Dfetch( sSSSR_PosTex, texcoord - int2( p.x, 0)).rgb;*/
	
	u2 = u + (u - u2);
	d2 = d + (d - d2);
	l2 = l + (l - l2);
	r2 = r + (r - r2);
	
	float3 c = UVtoPos( texcoord);
	
	float3 v = u-c; float3 h = r-c;
	
	if( abs(d2.z-c.z) < abs(u2.z-c.z) ) v = c-d;
	if( abs(l2.z-c.z) < abs(r2.z-c.z) ) h = c-l;
	
	return normalize(cross( v, h));
}

float3 Bump(float2 texcoord, float height)
{
	float2 p = pix;
	float2 T = p * 1.0 ;/// (LDepth(texcoord) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	float2 offset[4] =
	{
		float2( T.x,   0),
		float2(-T.x,   0),
		float2(   0, T.y),
		float2(   0,-T.y)
	};
	
	float3 s[5];
	s[0] = tex2D(sTexColor, texcoord + offset[0]).rgb * height;
	s[1] = tex2D(sTexColor, texcoord + offset[1]).rgb * height;
	s[2] = tex2D(sTexColor, texcoord + offset[2]).rgb * height;
	s[3] = tex2D(sTexColor, texcoord + offset[3]).rgb * height;
	s[4] = tex2D(sTexColor, texcoord).rgb * height;
	
	float3 XB = s[4]-s[0];
	float3 YB = s[4]-s[2];
	
	float3 bump = float3(XB.x*2, YB.y*2, 1);
	bump = normalize(bump);
	return bump;
}

float3 blend_normals(float3 n1, float3 n2)
{
    //return normalize(float3(n1.xy*n2.z + n2.xy*n1.z, n1.z*n2.z));
    n1 += float3( 0, 0, 1);
    n2 *= float3(-1, -1, 1);
    return n1*dot(n1, n2)/n1.z - n2;
}

float4 InvTonemap(inout float4 color)
{
	color = (color<0.5) ? color/(1.4-color) : color; //Reinhardt
	return 1;
}

float3 Tonemap(inout float3 color)
{
	color = (color<0.5) ? color/(1+color) : color; //Modified Reinhardt
	return 0;
}

float lum(in float3 color)
{
	return dot(0.333333333, color);
}

float min3(float a, float b, float c)
{
	return min(min(a,b),c);
}

float min9(float a, float b, float c, float d, float e, float f, float g, float h, float i)
{
	return min3(min3(a,b,c),min3(d,e,f),min3(g,h,i));
}

float3 InvTonemapper(float3 color)
{//Timothy Lottes fast_reversible
	return color.rgb / ((1.0 + max(1-IT_Intensity,0.001)) - max(color.r, max(color.g, color.b)));
}

float3 Tonemapper(float3 color)
{//Timothy Lottes fast_reversible
	return color.rgb / ((1.0 + max(1-IT_Intensity,0.001)) + max(color.r, max(color.g, color.b)));
}

float InvTonemapper(float color)
{//Reinhardt reversible
	return color / (1.001 - color);
}

float dilate(in sampler color, in float2 texcoord, in float2 p)
{
	float samples[9];
	
	//258
	//147
	//036
	samples[0] = tex2D(color, texcoord + float2(texcoord + float2(-p.x, -p.y))).r;
	samples[1] = tex2D(color, texcoord + float2(texcoord + float2(-p.x,    0))).r;
	samples[2] = tex2D(color, texcoord + float2(texcoord + float2(-p.x,  p.y))).r;
	samples[3] = tex2D(color, texcoord + float2(texcoord + float2(   0, -p.y))).r;
	samples[4] = tex2D(color, texcoord + float2(texcoord + float2(   0,    0))).r;
	samples[5] = tex2D(color, texcoord + float2(texcoord + float2(   0,  p.y))).r;
	samples[6] = tex2D(color, texcoord + float2(texcoord + float2( p.x, -p.y))).r;
	samples[7] = tex2D(color, texcoord + float2(texcoord + float2( p.x,    0))).r;
	samples[8] = tex2D(color, texcoord + float2(texcoord + float2( p.x,  p.y))).r;
	
	return min9(samples[2],samples[5],samples[8],
				samples[1],samples[4],samples[7],
				samples[0],samples[3],samples[6]);
}

float dilate2(in sampler color, in float2 texcoord, in float2 p)
{
	float samples[25];
	//  |  |  |  |  |
	//  | 2| 5| 8|  |
	//  | 1| 4| 7|  |
	//  | 0| 3| 6|  |
	//  |  |  |  |  |
	samples[0] = tex2D(color, texcoord + float2(texcoord + float2(-p.x, -p.y))).r;
	samples[1] = tex2D(color, texcoord + float2(texcoord + float2(-p.x,    0))).r;
	samples[2] = tex2D(color, texcoord + float2(texcoord + float2(-p.x,  p.y))).r;
	samples[3] = tex2D(color, texcoord + float2(texcoord + float2(   0, -p.y))).r;
	samples[4] = tex2D(color, texcoord + float2(texcoord + float2(   0,    0))).r;
	samples[5] = tex2D(color, texcoord + float2(texcoord + float2(   0,  p.y))).r;
	samples[6] = tex2D(color, texcoord + float2(texcoord + float2( p.x, -p.y))).r;
	samples[7] = tex2D(color, texcoord + float2(texcoord + float2( p.x,    0))).r;
	samples[8] = tex2D(color, texcoord + float2(texcoord + float2( p.x,  p.y))).r;
	
	float2 p2 = p*2;
	//13|15|17|19|24|
	//12|  |  |  |23|
	//11|  |  |  |22|
	//10|  |  |  |21|
	// 9|14|16|18|20|
	samples[9]  = tex2D(color, texcoord + float2(texcoord + float2(-p2.x, -p2.y))).r;
	samples[10] = tex2D(color, texcoord + float2(texcoord + float2(-p2.x,  -p.y))).r;
	samples[11] = tex2D(color, texcoord + float2(texcoord + float2(-p2.x,     0))).r;
	samples[12] = tex2D(color, texcoord + float2(texcoord + float2(-p2.x,   p.y))).r;
	samples[13] = tex2D(color, texcoord + float2(texcoord + float2(-p2.x,  p2.y))).r;
	samples[14] = tex2D(color, texcoord + float2(texcoord + float2( -p.x, -p2.y))).r;
	samples[15] = tex2D(color, texcoord + float2(texcoord + float2( -p.x,  p2.y))).r;
	samples[16] = tex2D(color, texcoord + float2(texcoord + float2(    0, -p2.y))).r;
	samples[17] = tex2D(color, texcoord + float2(texcoord + float2(    0,  p2.y))).r;
	samples[18] = tex2D(color, texcoord + float2(texcoord + float2(  p.x, -p2.y))).r;
	samples[19] = tex2D(color, texcoord + float2(texcoord + float2(  p.x,  p2.y))).r;
	samples[20] = tex2D(color, texcoord + float2(texcoord + float2( p2.x, -p2.y))).r;
	samples[21] = tex2D(color, texcoord + float2(texcoord + float2( p2.x,  -p.y))).r;
	samples[22] = tex2D(color, texcoord + float2(texcoord + float2( p2.x,     0))).r;
	samples[23] = tex2D(color, texcoord + float2(texcoord + float2( p2.x,   p.y))).r;
	samples[24] = tex2D(color, texcoord + float2(texcoord + float2( p2.x,  p2.y))).r;

	
	return min3(min9(samples[ 2],samples[ 5],samples[ 8],
					 samples[ 1],samples[ 4],samples[ 7],
					 samples[ 0],samples[ 3],samples[ 6]),
				min9(samples[ 9],samples[10],samples[11],
					 samples[12],samples[13],samples[14],
					 samples[15],samples[16],samples[17]),
		   min3(min3(samples[18],samples[19],samples[20]),
				min3(samples[21],samples[22],samples[23]),
					 samples[24]));
}

///////////////Functions///////////////////
///////////////Pixel Shader////////////////

void GBuffer0
(
	float4 vpos : SV_Position,
	float2 texcoord : TexCoord,
	out float3 Position : SV_Target1) //SSSR_PosTex
{
	Position = UVtoPos (texcoord);
}

void GBuffer1
(
	float4 vpos : SV_Position,
	float2 texcoord : TexCoord,
	out float3 normal : SV_Target) //SSSR_NormTex
{
	normal = Normal(texcoord.xy);
	normal = blend_normals( Bump(texcoord, BUMP), normal);
	//normal = normal * 0.5 + 0.5;
}

/*void GBuffer2
(
	float4 vpos : SV_Position,
	float2 texcoord : TexCoord,
	out float3 normal : SV_Target) //SSSR_NormTex
{
	normal = tex2D(sSSSR_NormTex, texcoord).rgb;
	//normal = normal * 0.5 + 0.5;
}*/

void RayMarch(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0)//, out float RayLength : SV_Target1)
{
	float3 depth    = LDepth  (texcoord);
	FinalColor.rgba = float4(tex2D(sTexColor, texcoord).rgb, 0);
	if(depth.x<SkyDepth){
		float3 reflection, Check, image, position, normal, eyedir, raydirR, raydirG, raydirOG, raydir, raypos; float2 UVraypos, p, Itexcoord; float a, raybias, StepNoise, steplength; uint i, j; bool hit;
		p = pix;
		Itexcoord = texcoord + float2(0, p.y);
		
		position = UVtoPos (texcoord);
		normal   = tex2D(sSSSR_NormTex, texcoord).rgb;
		eyedir   = normalize(position);
	
		raydirR   = lerp(reflect(eyedir, normal), noise3dts(texcoord, 0, MAX_Frames>8) - 0.5, 0.5);
		raydirG   = reflect(eyedir, normal);
		raybias   = dot(raydirG, raydirR);
		//float3 raydir   	 = lerp(raydirG, raydirR, pow(abs(raybias), 1/pow(roughness, 0.5)));
		raydirOG  = lerp(raydirG, raydirR, pow(1-(0.5*cos(raybias*PI)+0.5), 1/pow(InvTonemapper(roughness), 0.5)));
		raydir    = raydirOG;
		
		StepNoise = noise3dts(texcoord,0,1).x;
		steplength = 1+StepNoise*STEPNOISE;
		raypos = position + raydir * steplength;
	
		[loop]for( i = 0; i < RAYSTEPS; i++)
		{
			if(j < UI_RAYSTEPS)
			{
				UVraypos = PostoUV(raypos);
				Check = UVtoPos(UVraypos) - raypos;
				
				hit = Check.z < 0 && Check.z > -RAYDEPTH * steplength;
				if(hit)
				{
					a=1; a *= UVraypos.y >= 0;
					j += RAYSTEPS;
				}
				raypos += raydir * steplength;
				steplength *= RAYINC;
				j++;
			}
		}
		reflection = tex2D(sTexColor, UVraypos.xy).rgb;
		FinalColor.rgb = reflection;
		
		if(LinearConvert)FinalColor.rgb = pow(abs(FinalColor.rgb), 1 / 2.2);
		FinalColor.rgb = clamp(InvTonemapper(FinalColor.rgb), -1000, 1000);
		
		FinalColor.a = a*pow(abs(1 - dot(normal, eyedir)), EXP);
		
		float RayLength = saturate((steplength-2) * rcp(RAYSTEPS * AO_Radius * 10));
		FinalColor.rgb *= lerp(1, RayLength, AO_Intensity);
		FinalColor.rgb  = clamp(FinalColor.rgb, 0.0001, 1000);
		//FinalColor.a = 1;
	}//depth check if end
}

void TemporalFilter0(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float mask : SV_Target0)
{//Writes the mask to a texture. Then the texture will be dilated in the next pass to avoid masking edges when camera jitters
	//Definitions
	/*float4 Current, History; */float3 normal, past_normal, ogcolor, past_ogcolor; float2 MotionVectors, outbound; float depth, past_depth, HistoryLength;
	//Inputs
	MotionVectors = 0;
#if exists("MotionVectors.fxh")
	MotionVectors = sampleMotion(texcoord);
#endif
	HistoryLength = tex2D(sSSSR_HLTex1, texcoord + MotionVectors).r;
	//Depth
	depth = LDepth(texcoord);
	past_depth = tex2D(sSSSR_PDepthTex, texcoord + MotionVectors).r;
	//Normal
	normal = tex2D(sSSSR_NormTex, texcoord).rgb * 0.5 + 0.5;
	past_normal = tex2D(sSSSR_PNormalTex, texcoord + MotionVectors).rgb;
	//Original Background Color
	ogcolor = tex2D(sTexColor, texcoord).rgb;
	past_ogcolor = tex2D(sSSSR_POGColTex, texcoord + MotionVectors).rgb;
	//Disocclusion masking and Motion Estimation Error masking
	outbound = texcoord + MotionVectors;
	outbound = float2(max(outbound.r, outbound.g), min(outbound.r, outbound.g));
	outbound.rg = (outbound.r > 1 || outbound.g < 0);
	mask = abs(lum(normal) - lum(past_normal)) + abs(depth - past_depth) + abs(lum(ogcolor.rgb) - lum(past_ogcolor.rgb))*0.5 > Tthreshold;
	mask = max(mask, outbound.r);
	}

void TemporalFilter1(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0, out float HLOut : SV_Target1)
{
	float4 Current, History; float2 MotionVectors, p; float mask, HistoryLength;
#if exists("MotionVectors.fxh")
	MotionVectors = sampleMotion(texcoord);
#endif
	HistoryLength = tex2D(sSSSR_HLTex1, texcoord + MotionVectors).r;
	p = pix; p = p/RESOLUTION_SCALE_;
	//mask = tex2D(sSSSR_MaskTex, texcoord).r;
	mask = 1-dilate(sSSSR_MaskTex, texcoord/2, p);
	Current = tex2D(sSSSR_ReflectionTex, texcoord).rgba;
	History = tex2D(sSSSR_FilterTex2, texcoord + MotionVectors).rgba;
	
	HistoryLength *= mask; //sets the history length to 0 for discarded samples
	HLOut = HistoryLength + mask; //+1 for accepted samples
	HLOut = min(HLOut, MAX_Frames*max(sqrt(roughness), 2*STEPNOISE)); //Limits the linear accumulation to MAX_Frames, The rest will be accumulated exponentialy with the speed = (1-1/Max_Frames)

	if( TemporalRefine)FinalColor = lerp(History, Current, min((Current.a != 0) ? 1/HLOut : 0.01, mask));
	if(!TemporalRefine)FinalColor = lerp(History, Current, min(                   1/HLOut,     mask));
}

void SpatialFilter0( in float4 vpos : SV_Position, in float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0)
{
	float HLOut = tex2D(sSSSR_HLTex0, texcoord).r;
	if(!DualPass||HLOut>((MAX_MipFilter*64)/float(MAX_Frames))){ FinalColor = tex2D(sSSSR_FilterTex0, texcoord).rgba;}
	else{
	float4 color; float3 snormal, normal, ogcol; float2 offset[8], p; float sdepth, depth, lod, samples;

	p = pix;
	samples = 1;

	normal = tex2D(sSSSR_NormTex, texcoord).rgb;
	depth = LDepth(texcoord);
	ogcol = tex2D(sTexColor, texcoord).rgb;
	

	lod = min(MAX_MipFilter, max(0, (MAX_MipFilter)-HLOut));
	//lod = 0;
	p *= saturate(roughness)*pow(2, (lod))*4.5;
	lod = lod*saturate(roughness);
	color = tex2Dlod(sSSSR_FilterTex0, float4(texcoord, 0, lod));
	offset = {float2(0,p.y),float2(0,-p.y),float2(p.x,0),float2(-p.x,0),float2(p.x,p.y),float2(p.x,-p.y),float2(-p.x,p.y),float2(-p.x,-p.y)};
	
	[unroll]for(int i = 0; i <= 7; i++)
	{
		offset[i] += texcoord;
		sdepth = LDepth(offset[i]);
		snormal = tex2D(sSSSR_NormTex, offset[i]).rgb;
		if(lum(abs(snormal - normal))+abs(sdepth-depth) < Sthreshold)
		{
			color += tex2Dlod(sSSSR_FilterTex0, float4(offset[i].xy, 0, lod));
			samples += 1;
		}
	}
	color /= samples;
	FinalColor = color;
	normal = normal * 0.5 + 0.5;
	}
}
	

void SpatialFilter1(
	in  float4 vpos       : SV_Position,
	in  float2 texcoord   : TexCoord,
	out float4 FinalColor : SV_Target0,//FilterTex1
	out float3 normal     : SV_Target1,//PNormalTex
	out float  depth      : SV_Target2,//PDepthTex
	out float3 ogcol      : SV_Target3,//POGColTex
	out float  HLOut      : SV_Target4)//HLTex1
{
	float4 color; float3 snormal; float2 offset[8], p; float sdepth, lod, samples;

	p = pix;
	samples = 1;

	normal = tex2D(sSSSR_NormTex, texcoord).rgb;
	depth = LDepth(texcoord);
	ogcol = tex2D(sTexColor, texcoord).rgb;
	
	HLOut = tex2D(sSSSR_HLTex0, texcoord).r;
	lod = min(MAX_MipFilter, max(0, (MAX_MipFilter)-HLOut));
	//lod = 0;
	p *= saturate(roughness)*pow(2, (lod))*1.5;
	lod = lod*saturate(roughness);
	color = tex2Dlod(sSSSR_FilterTex1, float4(texcoord, 0, lod));
	offset = {float2(0,p.y),float2(0,-p.y),float2(p.x,0),float2(-p.x,0),float2(p.x,p.y),float2(p.x,-p.y),float2(-p.x,p.y),float2(-p.x,-p.y)};
	
	[unroll]for(int i = 0; i <= 7; i++)
	{
		offset[i] += texcoord;
		sdepth = LDepth(offset[i]);
		snormal = tex2D(sSSSR_NormTex, offset[i]).rgb;
		if(lum(abs(snormal - normal))+abs(sdepth-depth) < Sthreshold)
		{
			color += tex2Dlod(sSSSR_FilterTex1, float4(offset[i].xy, 0, lod));
			samples += 1;
		}
	}
	color /= samples;
	FinalColor = color;
	normal = normal * 0.5 + 0.5;
}



void output(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float3 FinalColor : SV_Target0)
{
	float4 Background = tex2D(sTexColor, texcoord).rgba;
	float4 Reflection = tex2D(sSSSR_FilterTex2, texcoord).rgba;
	float4 BGOG = Background;
	float depth = LDepth(texcoord);
	//Reflection.rgb = Tonemapper(Reflection.rgb);
	//Reflection.rgb *= Reflection.a;
	if(HLFix&&debug!=1)Reflection.a = saturate(Reflection.a + lum(Reflection.rgb)*Reflection.a) - lum(Background.rgb);
	Reflection.a *= 1-saturate((depthfade/(1-depthfade))*depth);
	Reflection.a = saturate(Reflection.a);
	
	//if(LinearConvert)Background.rgb = pow(abs(Background.rgb), 1/2.2);
	//Background.rgb = InvTonemapper(Background.rgb);
	
	if(LinearConvert) Reflection.rgb = pow(abs(Reflection.rgb), 2.2);
	Reflection.rgb = Tonemapper(Reflection.rgb);
	
	Reflection.rgb = lerp(lum(Reflection.rgb), Reflection.rgb, SatExp.r);
	Reflection.rgb *= SatExp.g;
	
	float3 albedo = lerp(Background.rgb, Background.rgb/dot(Background.rgb, 1), 0);
	if( GI)FinalColor = lerp(Background.rgb, Reflection.rgb*albedo, Reflection.a);
	if(!GI)FinalColor = lerp(Background.rgb, Reflection.rgb, Reflection.a);
	
	//FinalColor = Tonemapper(FinalColor);
	//if(LinearConvert)FinalColor.rgb = pow(abs(FinalColor.rgb), 2.2);
	
	FinalColor = lerp(FinalColor.rgb, BGOG.rgb, depth>=SkyDepth);//Sky Mask
	
	if(LinearConvert) Reflection.rgb = pow(abs(Reflection.rgb), 2.2);
	
	if(debug==1)FinalColor = Tonemapper(Reflection.rgb)*Reflection.a;
	if(debug==2)FinalColor = depth;
	if(debug==3)FinalColor = tex2D(sSSSR_NormTex, texcoord).rgb * 0.5 + 0.5;
	if(debug==4)FinalColor = tex2D(sSSSR_HLTex1, texcoord).r/MAX_Frames;
	float mask = tex2D(sSSSR_MaskTex, texcoord).r;
	float2 p = pix;
	//FinalColor = 1-dilate(sSSSR_MaskTex, texcoord/2, p);
}

///////////////Pixel Shader////////////////
///////////////Techniques//////////////////
technique NGLighting<
	ui_label = "NiceGuy Lighting (GI/Reflection)";
	ui_tooltip = "      NiceGuy Lighting 0.1alpha      \n"
				 "           ||By Ehsan2077||          \n"
				 "|Use with  DRME  at quarter  detail.|\n"
				 "|And don't forget to read the hints.|";
>
{
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = GBuffer0;
		RenderTarget0 = SSSR_PosTex;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = GBuffer1;
		RenderTarget0 = SSSR_NormTex;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = RayMarch;
		RenderTarget0 = SSSR_ReflectionTex;
		//RenderTarget1 = SSSR_AOTex;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalFilter0;
		RenderTarget0 = SSSR_MaskTex;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalFilter1;
		RenderTarget0 = SSSR_FilterTex0;
		RenderTarget1 = SSSR_HLTex0;
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
		RenderTarget0 = SSSR_FilterTex2;
		RenderTarget1 = SSSR_PNormalTex;
		RenderTarget2 = SSSR_PDepthTex;
		RenderTarget3 = SSSR_POGColTex;
		RenderTarget4 = SSSR_HLTex1;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = output;
	}
}
///////////////Techniques//////////////////
