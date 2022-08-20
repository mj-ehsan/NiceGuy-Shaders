//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 0.4 - UI

//license
//CC0 ^_^


#if UI_DIFFICULTY == 1
uniform int Hints<
	ui_text = "This shader is in -ALPHA PHASE-, expect bugs.\n\n"
			  "Set UI_DIFFICULTY to 0 to make the UI simpler if you want.\n"
			  "Advanced categories are unnecessary options that\n"
			  "can break the look of the shader if modified improperly.";
			  
	ui_category = "Hints - Please Read for good results.";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

uniform bool GI <
	ui_label = "GI Mode";
	ui_tooltip = "When enabled, gives you Ambient Occlusion and Indirect Lighting.\n"
				 "When disabled, gives you shiny or rough reflections.";
> = 1;

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
	ui_tooltip = "Adds tiny details to the reflection/GI.";
	ui_min = 0.0;
	ui_max = 1;
> = 1;

uniform float roughness <
	ui_label = "Roughness";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Blurriness of the reflections. Only works with GI mode disabled.";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.4;

uniform bool TemporalRefine <
	ui_label = "Temporal Refining (EXPERIMENTAL)";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "EXPERIMENTAL! Expect issues\n"
				 "Reduce (Surface depth) and increase (Step Length Jitter)\n"
				 "Then enable this option to have more accurate Reflection/GI.";
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
	ui_max = 32;
> = 12;

uniform float RAYDEPTH <
	ui_label = "Surface depth";
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "More coherency at the cost of accuracy.";
	ui_category_closed = true;
	ui_min = 0.05;
	ui_max = 10;
> = 2;
//#define RAYDEPTH 10000

uniform float STEPNOISE <
	ui_label = "Step Length Jitter";
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "Reduces artifacts but produces more noise.\n";
	ui_category_closed = true;
	ui_min = 0.0;
	ui_max = 1;
> = 0.15;

uniform float Tthreshold <
	ui_label = "Temporal Denoiser Threshold";
	ui_type = "slider";
	ui_category = "Denoiser (Advanced)";
	ui_tooltip = "Reduces noise but produces more ghosting.";
	ui_category_closed = true;
> = 0.025;

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
> = 0.015;

//uniform bool HLFix <
//	ui_label = "Fix Highlights";
//	ui_category = "Blending Options";
//	ui_tooltip = "Fixes bad blending in bright areas of background/reflections.";
//> = 1;
static const bool HLFix = 1;

uniform float EXP <
	ui_label = "Fresnel Exponent";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Blending intensity for shiny materials. Only works with GI mode disabled.";
	ui_min = 1;
	ui_max = 10;
> = 4;

uniform float AO_Radius_Background <
	ui_label = "Image AO";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Radius of the effective Ray Marched AO. Only works with GI mode enabled.";
> = 1;

uniform float AO_Radius_Reflection <
	ui_label = "GI AO";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Radius of the effective Ray Marched AO. Only works with GI mode enabled.";
> = 1;

uniform float AO_Intensity <
	ui_label = "AO Power";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Power of both layers of AO. Only works with GI mode enabled.";
> = 1;

uniform float depthfade <
	ui_label = "Depth Fade";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Higher values decrease the intesity on distant objects.\n"
				 "Reduces blending issues with in-game fogs.";
	ui_min = 0;
	ui_max = 1;
> = 0.8;

uniform bool LinearConvert <
	ui_type = "radio";
	ui_label = "sRGB to Linear";
	ui_category = "Color Management";
	ui_tooltip = "Converts from sRGB to Linear";
	ui_category_closed = true;
> = 1;

uniform float IT_Intensity <
	ui_type = "slider";
	ui_label = "Inverse Tonemapper Intensity";
	ui_category = "Color Management";
	ui_tooltip = "intensity of Inverse Tonemapping.";
	ui_category_closed = true;
	ui_max = 0.9;
> = 0.5;

uniform float2 SatExp <
	ui_type = "slider";
	ui_label = "Saturation || Exposure";
	ui_category = "Color Management";
	ui_tooltip = "Left slider is Saturation. Right one is Exposure.";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 2;
> = float2(1,1);

uniform uint debug <
	ui_type = "combo";
	ui_items = "None\0Reflections\0Depth\0Normal\0Accumulation\0";
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
#endif

#if UI_DIFFICULTY == 0

uniform int Hints<
	ui_text = "This shader is in -ALPHA PHASE-, expect bugs.\n\n"
			  "Set UI_DIFFICULTY to 1 if you want access to more settings.\n";
	ui_category = "Hints - Please Read!";
	ui_label = " ";
	ui_type = "radio";
>;

uniform bool GI <
	ui_label = "GI Mode";
	ui_tooltip = "When enabled, gives you Ambient Occlusion and Indirect Lighting.\n"
				 "When disabled, gives you shiny or rough reflections.";
> = 1;

static const float fov = 65;

uniform float BUMP <
	ui_label = "Bump mapping";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Adds tiny details to the reflection/GI.";
	ui_min = 0.0;
	ui_max = 1;
> = 1;

uniform float roughness <
	ui_label = "Roughness";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Blurriness of the reflections. Only works with GI mode disabled.";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.4;

#define TemporalRefine 0
#define RAYINC 2
#define UI_RAYSTEPS 12
//#define RAYDEPTH (1-GI)*2.5+GI*5
#define RAYDEPTH 2
//#define STEPNOISE (1-GI)*0.25*roughness+GI*0.25
#define STEPNOISE 0.25
#define Tthreshold 0.03
#define MAX_Frames 64
#define Sthreshold 0.04
#define HLFix  1

uniform float EXP <
	ui_label = "Reflection Intensity";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Only works with GI mode disabled.";
	ui_min = 1;
	ui_max = 10;
> = 4;

#define AO_Radius_Background 1
#define AO_Radius_Reflection 1

uniform float AO_Intensity <
	ui_label = "AO Power";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Only works with GI mode enabled.";
> = 1;

uniform float depthfade <
	ui_label = "Depth Fade";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Higher values decrease the intesity on distant objects.\n"
				 "Reduces blending issues with in-game fogs.";
	ui_min = 0;
	ui_max = 1;
> = 0.8;

uniform bool LinearConvert <
	ui_type = "radio";
	ui_label = "sRGB to Linear";
	ui_category = "Color Management";
	ui_tooltip = "Converts from sRGB to Linear";
	ui_category_closed = true;
> = 1;

#define IT_Intensity 0.75

uniform float2 SatExp <
	ui_type = "slider";
	ui_label = "Saturation || Exposure";
	ui_category = "Color Management";
	ui_tooltip = "Left slider is Saturation. Right one is Exposure.";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = float2(1,1);

uniform uint debug <
	ui_type = "combo";
	ui_items = "None\0Reflections\0Depth\0Normal\0Accumulation\0";
	ui_category = "Extra";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = 0;

#define SkyDepth 0.99

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

#endif