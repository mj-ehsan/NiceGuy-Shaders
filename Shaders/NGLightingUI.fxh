//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 0.9.2 - UI

//license
//CC0 ^_^
/*
uniform float temp_var0 <
	ui_type = "slider";
	ui_max  = 128;
> = 0;
uniform float temp_var1 <
	ui_type = "slider";
	ui_max  = 128;
> = 0;
*/
#if UI_DIFFICULTY == 1

uniform int Hints<
	ui_text = "This shader is in -ALPHA PHASE-, expect major changes.\n\n"
			  "Set UI_DIFFICULTY to 0 to make the UI simpler if you want.\n"
			  "Advanced categories are unnecessary options that\n"
			  "can break the look of the shader if modified improperly.\n\n"
			  "Use with ReShade_MotionVectors at Half Resolution.\n"
			  "Using higher resolutions for the motion vector only makes it WORSE "
			  "when the game is using temporal filters (TAA,DLSS2,FSR2,TAAU,TSR,etc.)";
			  //"Disabing NGL_HYBRID_MODE can give you better performance\n"
			  //"But you can use only one effect (either GI or Reflection).\n"
			  //"Don't forget to give me feedbacks in reshade discord";
			  
	ui_category = "Hints - Please Read for good results.";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

#if !NGL_HYBRID_MODE
uniform int GI <
	ui_type = "combo";
	ui_label = "Mode";
	ui_items = "Reflection\0GI\0";
> = 1;
#endif

#define UseCatrom 0
#define SharpenGI 0

uniform bool UI_ExcludeSky<
	ui_label = "Exclude Sky";
	ui_category = "Ray Tracing";
	ui_tooltip = "Excludes the sky from the GI/Reflection.";
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
	ui_tooltip = "Adds tiny details to the lighting.";
	ui_min = 0.0;
	ui_max = 5.0;
> = 0.0;

uniform float roughness <
	ui_label = "Roughness";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Blurriness of the reflections.";
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.4;

uniform float RAYINC <
	ui_label = "Ray Increment";
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "Increases ray length at the cost of accuracy.";
	ui_category_closed = true;
	ui_min = 1;
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
> = 16;

uniform float RAYDEPTH <
	ui_label = "Surface depth";
	ui_type = "slider";
	ui_category = "Ray Tracing (Advanced)";
	ui_tooltip = "More coherency at the cost of accuracy.";
	ui_category_closed = true;
	ui_min = 0.05;
	ui_max = 10;
> = 2;

uniform int MAX_Frames <
	ui_label = "History Length";
	ui_type = "slider";
	ui_category = "Denoiser (Advanced)";
	ui_tooltip = "Higher values increase smoothness\n"
				 "while preserves more details. But\n"
				 "introduces more temporal lag.";
	ui_category_closed = true;
	ui_min = 8;
	ui_max = 64;
> = 64;

uniform float Sthreshold <
	ui_label = "Spatial Denoiser\nThreshold";
	ui_type = "slider";
	ui_category = "Denoiser (Advanced)";
	ui_tooltip = "Reduces noise at the cost of detail.";
	ui_category_closed = true;
> = 0.003;

static const bool HLFix = 1;

uniform float EXP <
	ui_label = "Fresnel Exponent";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Blending intensity for shiny materials.";
	ui_min = 1;
	ui_max = 10;
> = 4;

uniform float AO_Intensity_Background <
	ui_label = "Image AO";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Radius of AO for the image.";
> = 1;

uniform float AO_Intensity_Reflection <
	ui_label = "GI AO";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Radius of AO for the GI.";
> = 1;

uniform float depthfade <
	ui_label = "Depth Fade";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Higher values decrease the intesity on distant objects.\n"
				 "Reduces blending issues within in-game fogs.";
	ui_min = 0;
	ui_max = 1;
> = 0.8;

uniform bool LinearConvert <
	ui_type = "radio";
	ui_label = "sRGB to Linear";
	ui_category = "Color Management";
	ui_tooltip = "Disable if the game is HDR";
	ui_category_closed = true;
> = 1;



uniform float2 SatExp <
	ui_type = "slider";
	ui_label = "Saturation\n& Exposure";
	ui_category = "Color Management";
	ui_tooltip = "Left slider is Saturation. Right one is Exposure.";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 2;
> = float2(1,1);

uniform uint debug <
	ui_type = "combo";
	ui_items = "None\0Lighting\0Depth\0Normal\0Accumulation\0Roughness Map\0Variance\0";
	ui_category = "Extra";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 6;
> = 0;

uniform float SkyDepth <
	ui_type = "slider";
	ui_label = "Sky Masking Depth";
	ui_tooltip = "Minimum depth to consider sky and exclude from the calculation.";
	ui_category = "Extra";
	ui_category_closed = true;
> = 0.99;

uniform int Credits<
	ui_text = "Thanks Lord of Lunacy, Leftfarian, and other devs for helping me. <3\n"
			  "Thanks Alea and MassiHancer for testing.<3\n\n"

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

uniform int Preprocessordefinitionstooltip<
	ui_text = "NGL_RESOLUTION_SCALE : Lower values are much faster but may be a bit blurrier.\n\n"
			  
			  "NGL_UI_DIFFICULTY    : 0 is EZ, 1 is for ReShade shamans."//\n\n"

			  "NGL_HYBRID_MODE      : 0 means you can use only one effect at a time. Either GI or Reflection. 1 means you have both effects simultaniously but it's a slower (less than 2 times)";
	ui_category = "Preprocessor definitions tooltip";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

#else

uniform int Hints<
	ui_text = "This shader is in -ALPHA PHASE-, expect major changes.\n\n"
			  "Set UI_DIFFICULTY to 1 if you want access to more settings.\n"
			  "Advanced categories are unnecessary options that\n"
			  "can break the look of the shader if modified improperly.\n\n"
			  "Use with ReShade_MotionVectors at Quarter Resolution.\n"
			  "Using higher resolutions for the motion vector only makes it WORSE "
			  "when the game is using temporal filters (TAA,DLSS2,FSR2,TAAU,TSR,etc.)";
	ui_category = "Hints - Please Read!";
	ui_label = " ";
	ui_type = "radio";
>;

#if !NGL_HYBRID_MODE
uniform int GI <
	ui_type = "combo";
	ui_label = "Mode";
	ui_items = "Reflection\0GI\0";
> = 1;
#endif

uniform int UI_QUALITY_PRESET <
	ui_type = "combo";
	ui_label = "Quality Preset";
	ui_items = "Low (16)\0Medium (64)\0High (160)\0Very High (320)\0Extreme (500)\0";
> = 1;

uniform bool UI_ExcludeSky<
	ui_label = "Exclude Sky";
	ui_category = "Ray Tracing";
	ui_tooltip = "Excludes the sky from the GI/Reflection.";
> = 1;

uniform float BUMP <
	ui_label = "Bump mapping";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Adds tiny details to the lighting.";
	ui_min = 0.0;
	ui_max = 5.0;
> = 0.0;

uniform float roughness <
	ui_label = "Roughness";
	ui_type = "slider";
	ui_category = "Ray Tracing";
	ui_tooltip = "Blurriness of the reflections.";
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.4;

uniform float EXP <
	ui_label = "Reflection rim fade";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_min = 1;
	ui_max = 10;
> = 4;

uniform float AO_Intensity <
	ui_label = "AO Power";
	ui_type = "slider";
	ui_category = "Blending Options";
	ui_tooltip = "Ambient Occlusion falloff curve";
> = 0.67;

#define AO_Intensity_Background AO_Intensity
#define AO_Intensity_Reflection AO_Intensity/2

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
	ui_tooltip = "Disable if the game is HDR";
	ui_category_closed = true;
> = 1;

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
	ui_items = "None\0Lighting\0Depth\0Normal\0Accumulation\0Roughness Map\0";
	ui_category = "Extra";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = 0;

uniform int Credits<
	ui_text = "Thanks Lord of Lunacy, Leftfarian, and other devs for helping me. <3\n"
			  "Thanks Alea and MassiHancer for testing.<3\n\n"

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

uniform int Preprocessordefinitionstooltip<
	ui_text = "NGL_RESOLUTION_SCALE : Lower values are much faster but may be a bit blurrier.\n\n"
			  
			  "NGL_UI_DIFFICULTY    : 0 is EZ, 1 is for ReShade shamans."//\n\n"

			  "NGL_HYBRID_MODE      : 0 means you can use only one effect at a time. Either GI or Reflection. 1 means you have both effects simultaniously but it's a slower (less than 2 times)";
	ui_category = "Preprocessor definitions tooltip";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

#endif
