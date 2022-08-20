//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 0.5

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
//3- [v]Add Simple Mode UI with setup assist
//4- [ ]Add internal comaptibility with Volumetric Fog V1 and V2
//      By using the background texture provided by VFog to blend the Reflection.
//      Then Blending back the fog to the image. This way fog affects the reflection.
//      But the reflection doesn't break the fog.
//5- [ ]Add ACEScg and or Filmic inverse tonemapping as optional alternatives to Timothy Lottes
//6- [v]Add AO support
//7- [x]Add second temporal pass after second spatial pass.
//8- [o]Add Spatiotemporal upscaling. have to either add jitter to the RayMarching pass or a checkerboard pattern.
//9- [ ]Add Smooth Normals.
//10-[ ]Use pre-calulated blue noise instead of white. From https://www.shadertoy.com/view/sdVyWc

///////////////Include/////////////////////

#include "ReShadeUI.fxh"
#include "ReShade.fxh"
#include "NGLightingUI.fxh"

uniform float Timer < source = "timer"; >;
uniform float Frame < source = "framecount"; >;

#define pix float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

#define LDepth ReShade::GetLinearizedDepth

#define PI 3.1415927
#define PI2 2*PI
#define rad(x) (x/360)*PI2 
///////////////Include/////////////////////
///////////////PreProcessor-Definitions////

#ifndef UI_DIFFICULTY
 #define UI_DIFFICULTY 0
#endif

#define AspectRatio (BUFFER_WIDTH/BUFFER_HEIGHT)          

#ifndef SMOOTH_NORMALS
 #define SMOOTH_NORMALS 1
#endif

#ifndef RESOLUTION_SCALE_
 #define RESOLUTION_SCALE_ 0.67
#endif

//#ifndef INTERPOLATED_RENDER
// #define INTERPOLATED_RENDER 0
//#endif

//#if INTERPOLATED_RENDER > 0
// #define RENDER_HEIGHT 0.5
//#else
 #define RENDER_HEIGHT 1 //WIP.
//#endif

#ifndef MAX_MipFilter
 #define MAX_MipFilter 2 //Maximum Number of mips for disocclusion filtering.
#endif

#if MAX_MipFilter > 9
 #undef MAX_MipFilter
 #define MAX_MipFilter 9 //Clamps the value to 9 to avoid compiling issues.
#endif

//Full res denoising on all passes. Otherwise only Spatial Filter 1 will be full res.
#ifndef HQ_UPSCALING
 #define HQ_UPSCALING 1
#endif

//#ifndef HQ_SPECULAR_REPROJECTION
 #define HQ_SPECULAR_REPROJECTION 0  //WIP!
//#endif

//Blur radius adaptivity threshold depending on the number of accumulated frames per pixel
#define Off       80  //Default is 160 //no filter
#define VerySmall 60   //Default is 80  //one 3*3 cross filter, TODO
#define Small     40   //Default is 40  //one 3*3 box filter
#define Medium    20   //Default is 20  //one 5*5 box filter
#define Large     10   //Default is 10  //two pass (3*3 and 3*3) Atrous 9*9 box filter
#define VeryLarge 5    //Default is 5   //two pass (3*3 and 5*5) Atrous 15*15 box filter

//if the History Length is lower than this threshold, edge avoiding function will be ignored to make
//sure the temporally underaccumulated pixel is getting enough spatial accumulation.
//HistoryFix0 should be lower or equal to HistoryFix1 in order to avoid artifacts.
#define HistoryFix0 1 //for the Spatial Filter 0  Default is 1
#define HistoryFix1 2 //for the Spatial Filter 1. Default is 2

//Motion Based Deghostin Threshold is the minimum value to be multiplied to the history length.
//Higher value causes more ghosting but less blur. Too low values might result in strong flickering in motion.
#define MBSDThreshold 0.05 //Default is 0.05
#define MBSDMultiplier 90 //Default is 90

//Temporal Refine min blend value. lower is more stable but ghosty and too low values may introduce banding
#define TRThreshold 0.001

//Smooth Normals configs. It uses a separable bilateral blur which uses only normals as determinator. 
#define SNThreshold 0.5 //Bilateral Blur Threshold for Smooth normals passes
#if SMOOTH_NORMALS <= 1 //13*13 10taps
 #define SNWidth 6 //Blur pixel offset for Smooth Normals
 #define SNSamples 1 //actually SNSamples*4+6!
#elif SMOOTH_NORMALS == 2 //17*17 14taps
 #define SNWidth 4
 #define SNSamples 2
#elif SMOOTH_NORMALS > 2 //41*41 86taps
 #warning "SMOOTH_NORMALS 3 is slow and should to be used for photography or old games. Otherwise set to 2 or 1."
 #define SNWidth 1
 #define SNSamples 20
#endif

///////////////PreProcessor-Definitions////
///////////////Textures-Samplers///////////

texture TexColor : COLOR;
sampler sTexColor {Texture = TexColor; SRGBTexture = false;};

texture TexDepth : DEPTH;
sampler sTexDepth {Texture = TexDepth;};

//texture SSSR_Noise <source="NG-BlueNoise.png";> { Width = 1024; Height = 768; Format=R8; };
//sampler sSSSR_Noise { Texture = SSSR_Noise; };

texture texMotionVectors < pooled = false; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler SamplerMotionVectors { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

texture SSSR_ReflectionTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_ReflectionTex { Texture = SSSR_ReflectionTex; };

#if HQ_UPSCALING == 0

texture SSSR_POGColTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSSR_POGColTex { Texture = SSSR_POGColTex; };

texture SSSR_OGColTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_OGColTex { Texture = SSSR_OGColTex; };

texture SSSR_FilterTex0  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex0 { Texture = SSSR_FilterTex0; };

texture SSSR_FilterTex1  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex1 { Texture = SSSR_FilterTex1; };

texture SSSR_FilterTex2  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex2 { Texture = SSSR_FilterTex2; };

texture SSSR_HistoryTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_HistoryTex { Texture = SSSR_HistoryTex; };

texture SSSR_PDepthTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sSSSR_PDepthTex { Texture = SSSR_PDepthTex; };

texture SSSR_PNormalTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSSR_PNormalTex { Texture = SSSR_PNormalTex; };

texture SSSR_NormTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_NormTex { Texture = SSSR_NormTex; };

texture SSSR_NormTex1  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_NormTex1 { Texture = SSSR_NormTex1; };

texture SSSR_PosTex  { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA8; };
sampler sSSSR_PosTex { Texture = SSSR_PosTex; };

texture SSSR_HLTex0 { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = R16f; };
sampler sSSSR_HLTex0 { Texture = SSSR_HLTex0; };

texture SSSR_HLTex1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16f; };
sampler sSSSR_HLTex1 { Texture = SSSR_HLTex1; };

texture SSSR_MaskTex { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = R8; };
sampler sSSSR_MaskTex { Texture = SSSR_MaskTex; };

texture SSSR_HitDistTex { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_HitDistTex { Texture = SSSR_HitDistTex; };
#else //HQ_UPSCALING

texture SSSR_POGColTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSSR_POGColTex { Texture = SSSR_POGColTex; };

texture SSSR_OGColTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSSR_OGColTex { Texture = SSSR_OGColTex; };

texture SSSR_FilterTex0  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex0 { Texture = SSSR_FilterTex0; };

texture SSSR_FilterTex1  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex1 { Texture = SSSR_FilterTex1; };

texture SSSR_FilterTex2  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; MipLevels = MAX_MipFilter; };
sampler sSSSR_FilterTex2 { Texture = SSSR_FilterTex2; };

texture SSSR_HistoryTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSSR_HistoryTex { Texture = SSSR_HistoryTex; };

texture SSSR_PDepthTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sSSSR_PDepthTex { Texture = SSSR_PDepthTex; };

texture SSSR_PNormalTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSSR_PNormalTex { Texture = SSSR_PNormalTex; };

texture SSSR_NormTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_NormTex { Texture = SSSR_NormTex; };

texture SSSR_NormTex1  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_NormTex1 { Texture = SSSR_NormTex1; };

texture SSSR_PosTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSSR_PosTex { Texture = SSSR_PosTex; };

texture SSSR_HLTex0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16f; };
sampler sSSSR_HLTex0 { Texture = SSSR_HLTex0; };

texture SSSR_HLTex1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16f; };
sampler sSSSR_HLTex1 { Texture = SSSR_HLTex1; };

texture SSSR_MaskTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sSSSR_MaskTex { Texture = SSSR_MaskTex; };

texture SSSR_HitDistTex { Width = BUFFER_WIDTH*RESOLUTION_SCALE_; Height = BUFFER_HEIGHT*RESOLUTION_SCALE_*RENDER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_HitDistTex { Texture = SSSR_HitDistTex; };
#endif //HQ_UPSCALING

texture SSSR_PAvglumTex0 { Width = 1; Height = 1; Format = R8; };
sampler sSSSR_PAvglumTex0 { Texture = SSSR_PAvglumTex0; };

texture SSSR_PAvglumTex1 { Width = 1; Height = 1; Format = R8; };
sampler sSSSR_PAvglumTex1 { Texture = SSSR_PAvglumTex1; };

///////////////Textures-Samplers///////////
///////////////UI//////////////////////////
///////////////UI//////////////////////////
///////////////Vertex Shader///////////////
///////////////Vertex Shader///////////////
///////////////Functions///////////////////

float GetSpecularDominantFactor(float NoV, float roughness)
{
	float a = 0.298475 * log(39.4115 - 39.0029 * roughness);
	float f = pow(saturate(1.0 - NoV), 10.8649)*(1.0 - a) + a;
	
	return saturate(f);
}

float2 sampleMotion(float2 texcoord)
{
    return tex2D(SamplerMotionVectors, texcoord).rg;
}

float noise(float2 co)
{
  return frac(sin(dot(co.xy ,float2(1.0,73))) * 437580.5453);
}

float3 noise3dts(float2 co, float s, float frame)
{
	co += sin(frame/120.347668756453546);
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

float3 UVtoPos(float2 texcoord, float depth)
{
	float3 scrncoord = float3(texcoord.xy*2-1, depth * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
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
	float2 T = pix;
	
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
	return color.rgb / ((1.0 + max(1-(IT_Intensity*((GI)?1:roughness)),0.001)) - max(color.r, max(color.g, color.b)));
}

float3 Tonemapper(float3 color)
{//Timothy Lottes fast_reversible
	return color.rgb / ((1.0 + max(1-(IT_Intensity*((GI)?1:roughness)),0.001)) + max(color.r, max(color.g, color.b)));
}

float InvTonemapper(float color)
{//Reinhardt reversible
	return color / (1.001 - color);
}

float dilate(in sampler color, in float2 texcoord, in float2 p, in float mip)
{
	float samples[9];
	
	//258
	//147
	//036
	samples[0] = tex2Dlod(color, float4(texcoord + float2(-p.x, -p.y), 0, mip)).r;
	samples[1] = tex2Dlod(color, float4(texcoord + float2(-p.x,    0), 0, mip)).r;
	samples[2] = tex2Dlod(color, float4(texcoord + float2(-p.x,  p.y), 0, mip)).r;
	samples[3] = tex2Dlod(color, float4(texcoord + float2(   0, -p.y), 0, mip)).r;
	samples[4] = tex2Dlod(color, float4(texcoord + float2(   0,    0), 0, mip)).r;
	samples[5] = tex2Dlod(color, float4(texcoord + float2(   0,  p.y), 0, mip)).r;
	samples[6] = tex2Dlod(color, float4(texcoord + float2( p.x, -p.y), 0, mip)).r;
	samples[7] = tex2Dlod(color, float4(texcoord + float2( p.x,    0), 0, mip)).r;
	samples[8] = tex2Dlod(color, float4(texcoord + float2( p.x,  p.y), 0, mip)).r;
	
	return min9(samples[2],samples[5],samples[8],
				samples[1],samples[4],samples[7],
				samples[0],samples[3],samples[6]);
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
#if SMOOTH_NORMALS <= 0
	normal = blend_normals( Bump(texcoord, BUMP), normal);
#endif
}

float3 SNH(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 color = float4(tex2D(sSSSR_NormTex, texcoord).rgb, 1);
	float  depth = LDepth(texcoord).r;
	float4 s, s1;
	s.a = 1;
	float2 p = pix; p*=SNWidth;
	float T = SNThreshold * saturate(2*(1-depth));
	for (int i = -SNSamples; i <= SNSamples; i++)
	{
		s.rgb = tex2D(sSSSR_NormTex, texcoord + float2(i*p.x, 0)).rgb;
		float  diff  = dot(0.333, abs(s.rgb - color.rgb));
		if( diff < T + 0.0001){s1 += s;}
	}
	return s1.rgb/s1.a;
}

float3 SNV(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 color = float4(tex2D(sSSSR_NormTex1, texcoord).rgb, 1);
	float  depth = LDepth(texcoord).r;
	float4 s, s1;
	s.a = 1;
	float2 p = pix; p*=SNWidth;
	float T = SNThreshold * saturate(2*(1-depth));
	for (int i = -SNSamples; i <= SNSamples; i++)
	{
		s.rgb = tex2D(sSSSR_NormTex1, texcoord + float2(0, i*p.y)).rgb;
		float diff = dot(0.333, abs(s.rgb - color.rgb));
		if( diff < T/2 + 0.0001){s1 += s;}
	}
	s1.rgb = s1.rgb/s1.a;
	s1.rgb = blend_normals( Bump(texcoord, BUMP), s1.rgb);
	return s1.rgb;
}

void RayMarch(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0
#if HQ_SPECULAR_REPROJECTION
,out float4 HitData : SV_Target1
#endif
)
{
	float3 depth    = LDepth  (texcoord); 
#if HQ_SPECULAR_REPROJECTION
	HitData = 0;
#endif
	FinalColor.rgba = float4(tex2D(sTexColor, texcoord).rgb, 0);
	if(depth.x<SkyDepth){
		float3 reflection, Check, image, position, normal, eyedir, raydirR, raydirG, raydir, raypos, noise; float2 UVraypos, p, Itexcoord; float a, raybias, StepNoise, steplength, HL; uint i, j; bool hit;
		p = pix;
		Itexcoord = texcoord + float2(0, p.y);
		HL = tex2D(sSSSR_HLTex0, texcoord).r;
		noise = noise3dts(texcoord, 0, Frame%HL);
		
		position = UVtoPos (texcoord);
		normal   = tex2D(sSSSR_NormTex, texcoord).rgb;
		eyedir   = normalize(position);
	
		raydirR   = lerp(reflect(eyedir, normal), noise-0.5, 0.5);
		raydirG   = reflect(eyedir, normal);
		raybias   = dot(raydirG, raydirR);
		//float3 raydir   	 = lerp(raydirG, raydirR, pow(abs(raybias), 1/pow(roughness, 0.5)));
		raydir    = lerp(raydirG, raydirR, pow(1-(0.5*cos(raybias*PI)+0.5), 1/pow(InvTonemapper((GI)?1:roughness), 0.5)));
		//raydir    = raydirOG;
		
		steplength = 1+noise.x*max(STEPNOISE, 0.01);
		raypos = position + raydir * steplength;
		float raydepth = -RAYDEPTH;
		[loop]for( i = 0; i < UI_RAYSTEPS; i++)
		{
				UVraypos = PostoUV(raypos);
				Check = UVtoPos(UVraypos) - raypos;
				
				hit = Check.z < 0 && Check.z > raydepth * steplength;
				if(hit)
				{
					a=1; a *= UVraypos.y >= 0;
					i += UI_RAYSTEPS;
				}
				if(TemporalRefine&&Check.z < 0) i += UI_RAYSTEPS;
				
				raypos += raydir * steplength;
				steplength *= RAYINC;
		}
		reflection = tex2D(sTexColor, UVraypos.xy).rgb;
		FinalColor.rgb = reflection;
		
		if(GI&&LinearConvert)FinalColor.rgb = pow(abs(FinalColor.rgb), 1 / 2.2);
		FinalColor.rgb = clamp(InvTonemapper(FinalColor.rgb), -1000, 1000);
		
		if(!GI)FinalColor.a = a;
		if( GI)FinalColor.a = saturate(distance(raypos, position)/100);
#if HQ_SPECULAR_REPROJECTION
		HitData.rgb = raypos;
		HitData.a = distance(raypos, position);
#endif
		FinalColor.rgb *= a;
	}//depth check if end
}

void TemporalFilter0(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float mask : SV_Target0)
{//Writes the mask to a texture. Then the texture will be dilated in the next pass to avoid masking edges when camera jitters
	float depth = LDepth(texcoord);
	if(depth>SkyDepth){mask=0;}else{
	float3 normal, past_normal, ogcolor, past_ogcolor; float2 MotionVectors, outbound; float past_depth, HistoryLength;
	//Inputs
	MotionVectors = 0;
	MotionVectors = sampleMotion(texcoord);

	HistoryLength = tex2D(sSSSR_HLTex1, texcoord + MotionVectors).r;
	//Depth
	past_depth = tex2D(sSSSR_PDepthTex, texcoord + MotionVectors).r;
	//Normal
	normal = tex2D(sSSSR_NormTex, texcoord).rgb * 0.5 + 0.5;
	past_normal = tex2D(sSSSR_PNormalTex, texcoord + MotionVectors).rgb;
	//Original Background Color
	ogcolor = tex2D(sTexColor, texcoord).rgb;
	past_ogcolor = tex2D(sSSSR_POGColTex, texcoord + MotionVectors).rgb;
	ogcolor = ogcolor/lum(ogcolor); past_ogcolor = past_ogcolor/lum(past_ogcolor);
	//Disocclusion masking and Motion Estimation Error masking
	outbound = texcoord + MotionVectors;
	outbound = float2(max(outbound.r, outbound.g), min(outbound.r, outbound.g));
	outbound.rg = (outbound.r > 1 || outbound.g < 0);
	mask = abs(lum(normal) - lum(past_normal)) + abs(depth - past_depth)*2 + abs(lum(ogcolor - past_ogcolor))*200000 > Tthreshold;
	mask = max(mask, outbound.r);
	}//sky mask end
}

void TemporalFilter1(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0, out float HLOut : SV_Target1)
{
	float depth = LDepth(texcoord);
	float4 Current, History; float3 Xvirtual, eyedir; float2 MotionVectors, p, pixelUvVirtualPrev; float past_depth, mask, HistoryLength;
	
	MotionVectors = sampleMotion(texcoord);
	HistoryLength = tex2D(sSSSR_HLTex1, texcoord + MotionVectors).r;
	p = pix;
#if HQ_UPSCALING == 0
	p = p/RESOLUTION_SCALE_;
#endif
#if HQ_SPECULAR_REPROJECTION
	float NoV, SDF; float4 HitDist, gWorldToClipPrev; 
	if(!GI)
	{
		past_depth = tex2D(sSSSR_PDepthTex, texcoord + MotionVectors).r;
		gWorldToClipPrev = UVtoPos(texcoord + MotionVectors, past_depth);
			eyedir  = normalize(UVtoPos(texcoord));
		NoV     = dot(eyedir, Normal(texcoord));
		SDF     = GetSpecularDominantFactor(NoV, roughness);
		HitDist = tex2D(sSSSR_HitDistTex, texcoord);
		Xvirtual = HitDist.rgb - eyedir * HitDist.a;
		pixelUvVirtualPrev = PostoUV( gWorldToClipPrev.rgb + Xvirtual/1000);
	}
#endif
	mask = 1-dilate(sSSSR_MaskTex, texcoord, p, 0);
	
	Current = tex2D(sSSSR_ReflectionTex, texcoord).rgba;
	History = tex2D(sSSSR_FilterTex2, texcoord + MotionVectors).rgba;
	HistoryLength = tex2D(sSSSR_HLTex1, texcoord + MotionVectors).r;
	
	HistoryLength *= mask; //sets the history length to 0 for discarded samples
	HLOut = HistoryLength + mask; //+1 for accepted samples
	HLOut = min(HLOut, MAX_Frames*max(sqrt((GI)?1:roughness), max(0.0001, STEPNOISE))); //Limits the linear accumulation to MAX_Frames, The rest will be accumulated exponentialy with the speed = (1-1/Max_Frames)
	
	if(!GI)HLOut = HLOut * max(saturate(1-length(MotionVectors)*(1-roughness)*MBSDMultiplier), MBSDThreshold); //Motion Vector Based Deghosting for specular reflections
	
	HLOut = max(HLOut, 0.001);
	if( TemporalRefine)FinalColor = lerp(History, Current, min((Current.a != 0) ? 1/HLOut : TRThreshold, mask));
	if(!TemporalRefine)FinalColor = lerp(History, Current, min(                   1/HLOut,         mask));
}
//Blur adaptivity agains History Length.
//Shape |Win|Name     |Offsets
//1     :1   Off       0.0-0.0 //TODO for GI
//3cross:5   VerySmall 1.0-0.0 //TODO
//3*1=3 :9   Small     1.0-0.0
//5*1=5 :25  Medium    1.5-0.0
//3*3=9 :81  Large     1.0-3.0
//5*3=15:225 VeryLarge 1.5-5.0
void SpatialFilter0( in float4 vpos : SV_Position, in float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0)
{
	float HLOut = tex2D(sSSSR_HLTex0, texcoord).r;
	if(HLOut<Medium)
	{
		float4 color; float3 snormal, normal, ogcol; float3 offset[8], p; float HLOut, sdepth, depth, lod, samples, Roughness, HitDist, radius;
	
		p = pix;
		samples = 1;
		Roughness = (GI)?1:roughness;
		HitDist = tex2D(sSSSR_HitDistTex, texcoord).a;
		normal = tex2D(sSSSR_NormTex, texcoord).rgb;
		depth = LDepth(texcoord);
		ogcol = tex2D(sTexColor, texcoord).rgb;
		
		HLOut = tex2D(sSSSR_HLTex0, texcoord).r;
		radius = GI?1:saturate(Roughness*8/HLOut)*saturate((HitDist*5)/RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
		lod = min(MAX_MipFilter, max(0, (MAX_MipFilter)-HLOut))*radius;
		//lod = 0;
		
#if HQ_UPSCALING
	p *= radius*pow(2, (lod))*((HLOut<VeryLarge)?5:3)*rcp(RESOLUTION_SCALE_);
#else
	p *= radius*pow(2, (lod))*((HLOut<VeryLarge)?5:3);
#endif
		lod = lod*saturate(Roughness);
		color = tex2Dlod(sSSSR_FilterTex0, float4(texcoord, 0, lod));
		offset = {float3(0,p.y,2),float3(0,-p.y,2),float3(p.x,0,2),float3(-p.x,0,2),float3(p.x,p.y,4),float3(p.x,-p.y,4),float3(-p.x,p.y,4),float3(-p.x,-p.y,4)};
		
		[unroll]for(int i = 0; i <= 7; i++)
		{
			offset[i] += texcoord;
			sdepth = LDepth(offset[i].xy);
			snormal = tex2D(sSSSR_NormTex, offset[i].xy).rgb;
			if((lum(abs(snormal - normal))+abs(sdepth-depth) < Sthreshold) || (HLOut < HistoryFix0 && MAX_Frames > HistoryFix0))
			{
				color += tex2Dlod(sSSSR_FilterTex0, float4(offset[i].xy, 0, lod));//*offset[i].z;
				samples += 1;//offset[i].z;
			}
		}
		color /= samples;
		FinalColor = color;
		normal = normal * 0.5 + 0.5;
		}
	else
	{
		FinalColor = tex2D(sSSSR_FilterTex0, texcoord).rgba;
	}
}

void SpatialFilter1(
	in  float4 vpos       : SV_Position,
	in  float2 texcoord   : TexCoord,
	out float4 FinalColor : SV_Target0,//FilterTex2
	out float3 normal     : SV_Target1,//PNormalTex
	out float  depth      : SV_Target2,//PDepthTex
	out float3 ogcol      : SV_Target3,//POGColTex
	out float  HLOut      : SV_Target4)//HLTex1
{
	float4 color; float3 snormal; float3 offset[8], p; float sdepth, lod, samples, Roughness, HitDist, radius;

	p = pix;
	samples = 1;
	Roughness = (GI)?1:roughness;
	HitDist = tex2D(sSSSR_HitDistTex, texcoord).a;
	normal = tex2D(sSSSR_NormTex, texcoord).rgb;
	depth = LDepth(texcoord);
	ogcol = tex2D(sTexColor, texcoord).rgb;
	
	HLOut = tex2D(sSSSR_HLTex0, texcoord).r;
	radius = GI?1:saturate(Roughness*8/HLOut)*saturate((HitDist*5)/RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	if(HLOut>Off) radius *= (MAX_Frames-HLOut)/MAX_Frames;
	lod = min(MAX_MipFilter, max(0, (MAX_MipFilter)-HLOut))*radius;
	//lod = 0;
#if HQ_UPSCALING
	p *= radius*pow(2, (lod))*((HLOut<VeryLarge||HLOut>=Medium)?1.5:1)*rcp(RESOLUTION_SCALE_);
#else
	p *= radius*pow(2, (lod))*((HLOut<VeryLarge||HLOut>=Medium)?1.5:1);
#endif
	lod = lod*saturate(Roughness);
	color = tex2Dlod(sSSSR_FilterTex1, float4(texcoord, 0, lod));
	
	offset = 
	{
		float3(0,p.y,2),float3(0,-p.y,2),
		float3(p.x,0,2),float3(-p.x,0,2),
		float3(p.x,p.y,4),float3(p.x,-p.y,4),
		float3(-p.x,p.y,4),float3(-p.x,-p.y,4)
	};
	
	[unroll]for(int i = 0; i <= 7; i++)
	{
		offset[i] += texcoord;
		sdepth = LDepth(offset[i].xy);
		snormal = tex2D(sSSSR_NormTex, offset[i].xy).rgb;
		if((lum(abs(snormal - normal))+abs(sdepth-depth) < Sthreshold) || (HLOut < HistoryFix1 && MAX_Frames > HistoryFix1))
		{
			color += tex2Dlod(sSSSR_FilterTex1, float4(offset[i].xy, 0, lod))*offset[i].z;
			samples += offset[i].z;
		}
	}
	color /= samples;
	FinalColor = color;
	normal = normal * 0.5 + 0.5;
}
	
void output(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float3 FinalColor : SV_Target0)
{
	float4 Background, Reflection; float3 albedo, BGOG, normal; float2 AO; float depth, Fresnel;
	
	Background   = tex2D(sTexColor, texcoord).rgba;
	depth        = LDepth(texcoord);
	if(depth>=SkyDepth){FinalColor = Background.rgb;} else{
	BGOG		 = Background.rgb;
	Reflection   = tex2D(sSSSR_FilterTex2, texcoord).rgba;
	
	if(!GI){
	normal = tex2D(sSSSR_NormTex, texcoord).rgb;
	Fresnel      = lerp(0.05, 1, (pow(abs(1 - dot(normal, normalize(UVtoPos (texcoord)))), lerp(EXP, 0, roughness))));}
	
	if(GI){
	AO.r = saturate(Reflection.a / AO_Radius_Background);
	AO.g = saturate(Reflection.a / AO_Radius_Reflection);
	AO = pow(AO, AO_Intensity);}
	
	if(GI)if(LinearConvert) Reflection.rgb = pow(abs(Reflection.rgb), 2.2);
	Reflection.rgb = Tonemapper(Reflection.rgb);
	
	Reflection.rgb = lerp(lum(Reflection.rgb), Reflection.rgb, SatExp.r); Reflection.rgb *= SatExp.g;
	
	albedo = lerp(Background.rgb, Background.rgb/dot(Background.rgb, 1), 0);
	
	if(debug==1)Background.rgb = (GI)?0.5:0;
	if(GI)FinalColor = lerp(AO.r*Background.rgb + Reflection.rgb*Background.rgb*AO.g, Background.rgb, (HLFix&&!debug==1)?pow(abs(Background.rgb),1.5):0);
	else  FinalColor = lerp( lerp(Background.rgb, Reflection.rgb, Fresnel), Background.rgb,  (HLFix&&!debug==1)?pow(abs(Background.rgb),1.5):0);
	if(debug==0)FinalColor = lerp(FinalColor, BGOG.rgb, pow(abs(depth), InvTonemapper(depthfade)));}
	if(debug==2)FinalColor = depth;
	if(debug==3)FinalColor = tex2D(sSSSR_NormTex, texcoord).rgb * 0.5 + 0.5;
	if(debug==4)FinalColor = tex2D(sSSSR_HLTex1, texcoord).r/MAX_Frames;
	//FinalColor = tex2D(sSSSR_HitDistTex, texcoord).rgb/1000;
}

///////////////Pixel Shader////////////////
///////////////Techniques//////////////////
technique NGLighting<
	ui_label = "NiceGuy Lighting (GI/Reflection)";
	ui_tooltip = "             NiceGuy Lighting 0.5alpha             \n"
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
	}
#if SMOOTH_NORMALS > 0
	pass SmoothNormalHpass
	{
		VertexShader = PostProcessVS;
		PixelShader = SNH;
		RenderTarget = SSSR_NormTex1;
	}
	pass SmoothNormalVpass
	{
		VertexShader = PostProcessVS;
		PixelShader = SNV;
		RenderTarget = SSSR_NormTex;
	}
#endif
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = RayMarch;
		RenderTarget0 = SSSR_ReflectionTex;
#if HQ_SPECULAR_REPROJECTION
		RenderTarget1 = SSSR_HitDistTex;
#endif
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
