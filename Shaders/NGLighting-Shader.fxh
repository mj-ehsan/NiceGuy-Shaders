//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 0.9.1

//Thanks Lord of Lunacy, Leftfarian, and other devs for helping me. <3
//Thanks Alea & MassiHancer for testing. <3

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
//7- [v]Add second temporal pass after second spatial pass.
//8- [o]Add Spatiotemporal upscaling. have to either add jitter to the RayMarching pass or a checkerboard pattern.
//9- [v]Add Smooth Normals.
//10-[v]Use pre-calulated blue noise instead of white. From Nvidia's SpatioTemporal Blue Noise sequence
//11-[v]Add depth awareness to smooth normals. To do so, add depth in the alpha channel of 
//	  NormTex and NormTex1 for optimization.
//12-[v]Make normal based edge awareness of all passes based on angular distance of the 2 normals.
//13-[o]Make sample distance of smooth normals exponential.
//14-[ ]

///////////////Include/////////////////////

#include "ReShadeUI.fxh"
#include "ReShade.fxh"
#include "NGLightingUI.fxh"

uniform float Timer < source = "timer"; >;
uniform float Frame < source = "framecount"; >;

static const float2 pix = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

#define LDepth ReShade::GetLinearizedDepth

#define FAR_PLANE RESHADE_DEPTH_LINEARIZATION_FAR_PLANE 

#define PI 3.1415927
static const float PI2div360 = PI/180;
#define rad(x) x*PI2div360
///////////////Include/////////////////////
///////////////PreProcessor-Definitions////

#include "NGLighting-Configs.fxh"

///////////////PreProcessor-Definitions////
///////////////Textures-Samplers///////////

texture TexColor : COLOR;
sampler sTexColor {Texture = TexColor; SRGBTexture = false;};

texture texMotionVectors { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler SamplerMotionVectors { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

texture SSSR_ReflectionTex  { Width = BUFFER_WIDTH*NGL_RESOLUTION_SCALE; Height = BUFFER_HEIGHT*NGL_RESOLUTION_SCALE; Format = RGBA16f; };
sampler sSSSR_ReflectionTex { Texture = SSSR_ReflectionTex; };

texture SSSR_POGColTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16f; };
sampler sSSSR_POGColTex { Texture = SSSR_POGColTex; };

texture SSSR_FilterTex0  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f;};
sampler sSSSR_FilterTex0 { Texture = SSSR_FilterTex0; };

texture SSSR_FilterTex1  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f;};
sampler sSSSR_FilterTex1 { Texture = SSSR_FilterTex1; };

texture SSSR_FilterTex2  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_FilterTex2 { Texture = SSSR_FilterTex2; };

texture SSSR_HistoryTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_HistoryTex { Texture = SSSR_HistoryTex; };

texture SSSR_NormTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_NormTex { Texture = SSSR_NormTex; };

texture SSSR_LowResDepthTex  { Width = BUFFER_WIDTH*NGL_RESOLUTION_SCALE*RES_M; Height = BUFFER_HEIGHT*NGL_RESOLUTION_SCALE*RES_M; Format = R16f; };
sampler sSSSR_LowResDepthTex { Texture = SSSR_LowResDepthTex; };

texture SSSR_HLTex0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_HLTex0 { Texture = SSSR_HLTex0; };

texture SSSR_HLTex1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sSSSR_HLTex1 { Texture = SSSR_HLTex1; };

texture SSSR_RoughTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sSSSR_RoughTex { Texture = SSSR_RoughTex; };

///////////////Textures-Samplers///////////
///////////////UI//////////////////////////
///////////////UI//////////////////////////
///////////////Vertex Shader///////////////
///////////////Vertex Shader///////////////
///////////////Functions///////////////////

//from: https://www.shadertoy.com/view/XsSfzV
// by Nikos Papadopoulos, 4rknova / 2015
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
float3 toYCC(float3 rgb)
{
	const float Y  =  .299 * rgb.x + .587 * rgb.y + .114 * rgb.z; // Luminance
	const float Cb = -.169 * rgb.x - .331 * rgb.y + .500 * rgb.z; // Chrominance Blue
	const float Cr =  .500 * rgb.x - .419 * rgb.y - .081 * rgb.z; // Chrominance Red
    return float3(Y,Cb + 128./255.,Cr + 128./255.);
}

float3 toRGB(float3 ycc)
{
    const float3 c = ycc - float3(0., 128./255., 128./255.);
    
    float R = c.x + 1.400 * c.z;
	float G = c.x - 0.343 * c.y - 0.711 * c.z;
	float B = c.x + 1.765 * c.y;
    return float3(R,G,B);
}

float2 sampleMotion(float2 texcoord)
{
    return tex2D(SamplerMotionVectors, texcoord).rg;
}

float WN(float2 co)
{
  return frac(sin(dot(co.xy ,float2(1.0,73))) * 437580.5453);
}

float3 WN3dts(float2 co, float HL)
{
	co += (Frame%HL)/120.3476687;
	return float3( WN(co), WN(co+0.6432168421), WN(co+0.19216811));
}

float IGN(float2 n)
{
    float f = 0.06711056 * n.x + 0.00583715 * n.y;
    return frac(52.9829189 * frac(f));
}

float3 IGN3dts(float2 texcoord, float HL)
{
	float3 Noise;
	const float2 seed = texcoord*BUFFER_SCREEN_SIZE+(Frame%HL)*5.588238;
	Noise.r = IGN(seed);
	Noise.g = IGN(seed + 91.534651 + 189.6854);
	Noise.b = IGN(seed + 167.28222 + 281.9874);
	
	float3 OutColor = 1;
	sincos(Noise.x * PI * 2, OutColor.x, OutColor.y);
	OutColor.z = Noise.y * 2.0 - 0.5;
	OutColor  *= Noise.z;
	
	return OutColor * 0.5 + 0.5;
}

texture SSSR_BlueNoise <source="BlueNoise-64frames128x128.png";> { Width = 1024; Height = 1024; Format = RGBA8;};
sampler sSSSR_BlueNoise { Texture = SSSR_BlueNoise; AddressU = REPEAT; AddressV = REPEAT; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

float3 BN3dts(float2 texcoord, float HL)
{
	texcoord *= BUFFER_SCREEN_SIZE; //convert to pixel index
	
	texcoord = texcoord%128; //limit to texture size
	
	const float frame = Frame%HL; //limit frame index to history length
	int2 F;
	F.x = frame%8; //Go from left to right each frame. start over after 8th
	F.y = floor(frame/8)%8; //Go from top to buttom each 8 frame. start over after 8th
	F *= 128; //Each step jumps to the next texture 
	texcoord += F;
	
	texcoord /= 1024; //divide by atlas size
	float3 Tex = tex2D(sSSSR_BlueNoise, texcoord).rgb;
	return Tex;
}

float3 UVtoPos(float2 texcoord)
{
	float3 scrncoord = float3(texcoord.xy*2-1, LDepth(texcoord) * FAR_PLANE);
	scrncoord.xy *= scrncoord.z;
	scrncoord.x *= AspectRatio;
	scrncoord.xy *= rad(fov);
	//scrncoord.xy *= ;
	
	return scrncoord.xyz;
}

float3 UVtoPos(float2 texcoord, float depth)
{
	float3 scrncoord = float3(texcoord.xy*2-1, depth * FAR_PLANE);
	scrncoord.xy *= scrncoord.z;
	scrncoord.x *= AspectRatio;
	scrncoord *= rad(fov);
	//scrncoord.xy *= ;
	
	return scrncoord.xyz;
}

float2 PostoUV(float3 position)
{
	float2 scrnpos = position.xy;
	scrnpos /= rad(fov);
	scrnpos.x /= AspectRatio;
	scrnpos /= position.z;
	
	return scrnpos/2 + 0.5;
}
	
float3 Normal(float2 texcoord)
{
	float2 p = pix;
	float3 u2,d2,l2,r2;
	
	const float3 u = UVtoPos( texcoord + float2( 0, p.y));
	const float3 d = UVtoPos( texcoord - float2( 0, p.y));
	const float3 l = UVtoPos( texcoord + float2( p.x, 0));
	const float3 r = UVtoPos( texcoord - float2( p.x, 0));
	
	p *= 2;
	
	u2 = UVtoPos( texcoord + float2( 0, p.y));
	d2 = UVtoPos( texcoord - float2( 0, p.y));
	l2 = UVtoPos( texcoord + float2( p.x, 0));
	r2 = UVtoPos( texcoord - float2( p.x, 0));
	
	u2 = u + (u - u2);
	d2 = d + (d - d2);
	l2 = l + (l - l2);
	r2 = r + (r - r2);
	
	const float3 c = UVtoPos( texcoord);
	
	float3 v = u-c; float3 h = r-c;
	
	if( abs(d2.z-c.z) < abs(u2.z-c.z) ) v = c-d;
	if( abs(l2.z-c.z) < abs(r2.z-c.z) ) h = c-l;
	
	return normalize(cross( v, h));
}

float lum(in float3 color)
{
	return (color.r+color.g+color.b)/3;
}

float3 ClampLuma(float3 color, float luma)
{
	const float L = lum(color);
	color /= L;
	color *= L > luma ? luma : L;
	return color;
}

float3 GetRoughTex(float2 texcoord, float4 normal)
{
	float2 p = pix;
	
	if(!GI)
	{
		//depth threshold to validate samples
		const float Threshold = 0.0002;
		float facing = dot(normal.rgb, normalize(UVtoPos(texcoord, normal.w)));
		facing *= facing * 500;
		//calculating curve and levels
		const float  roughfac = (1 - roughness);
		const float2 fromrough = float2(lerp(0, 0.1, saturate(roughness*10)), 0.8);
		const float2 torough = float2(0, pow(abs(roughness), roughfac));
		
		const float3 center = toYCC(tex2D(sTexColor, texcoord).rgb);
		const float depth = LDepth(texcoord);

		float Roughness, SampleDepth;
		float3 SampleColor;
		//cross (+)
		float2 offsets[4] = {float2(p.x,0), float2(-p.x,0),float2( 0,-p.y),float2(0,p.y)};
		[unroll]for(int x; x < 4; x++)
		{
			offsets[x] += texcoord;
			SampleDepth = LDepth(offsets[x]);
			
			SampleColor = toYCC(tex2D( sTexColor, offsets[x]).rgb);
			SampleColor = min(abs(center.g - SampleColor.g) * exp(-abs(SampleDepth - depth)*facing), 0.25);
			Roughness += SampleColor.r;
		}
		
		Roughness = pow( Roughness, roughfac*0.66);
		Roughness = clamp(Roughness, fromrough.x, fromrough.y);
		Roughness = (Roughness - fromrough.x) / ( 1 - fromrough.x );
		Roughness = Roughness / fromrough.y;
		Roughness = clamp(Roughness, torough.x, torough.y);
		
		return saturate(sqrt(Roughness));
	} 
	else return 0;//RoughnessTex
}

#define BT 1000
float3 Bump(float2 texcoord, float height)
{
	float2 p = pix;
	
	float3 s[3];
	s[0] = tex2D(sTexColor, texcoord + float2(p.x, 0)).rgb;
	s[1] = tex2D(sTexColor, texcoord + float2(0, p.y)).rgb;
	s[2] = tex2D(sTexColor, texcoord).rgb;
	const float LC = rcp(lum(s[0]+s[1]+s[2])) * height;
	s[0] *= LC; s[1] *= LC; s[2] *= LC;
	float d[3];
	d[0] = LDepth(texcoord + float2(p.x, 0));
	d[1] = LDepth(texcoord + float2(0, p.y));
	d[2] = LDepth(texcoord);
	
	//s[0] *= saturate(1-abs(d[0] - d[2])*1000);
	//s[1] *= saturate(1-abs(d[1] - d[2])*1000);
	
	float3 XB = s[2]-s[0];
	float3 YB = s[2]-s[1];
	
	float3 bump = float3(lum(XB)*saturate(1-abs(d[0] - d[2])*BT), lum(YB)*saturate(1-abs(d[1] - d[2])*BT), 1);
	bump = normalize(bump);
	return bump;
}

float3 BlendBump(float3 n1, float3 n2)
{
    n1 += float3( 0, 0, 1);
    n2 *= float3(-1, -1, 1);
    return n1 * dot(n1, n2) / n1.z - n2;
}

static const float LinearGamma = 0.454545;
static const float sRGBGamma = 2.2;

#if TM_Mode
 #define GetL max(max(color.r, color.g), color.b)
#else
 #define GetL color
#endif

float3 InvTonemapper(float3 color)
{
	if(LinearConvert)color = pow(color, LinearGamma);
	const float3 L = GetL;
	color = color / ((1.0 + max(1-IT_Intensity,0.00001)) - L);
	return color;
}

float3 Tonemapper(float3 color)
{
	const float3 L = GetL;
	color = color / ((1.0 + max(1-IT_Intensity,0.00001)) + L);
	if(LinearConvert)color = pow(color, sRGBGamma);
	return (color);
}

float InvTonemapper(float color)
{//Reinhardt reversible
	return color / (1.001 - color);
}

bool IsSaturated(float2 coord)
{
	return coord.x > 1 || coord.x < 0 || coord.y > 1 || coord.y < 0;
}

// The following code is licensed under the MIT license: https://gist.github.com/TheRealMJP/bc503b0b87b643d3505d41eab8b332ae
// Samples a texture with Catmull-Rom filtering, using 9 texture fetches instead of 16.
// See http://vec3.ca/bicubic-filtering-in-fewer-taps/ for more details
float4 tex2Dcatrom(in sampler tex, in float2 uv, in float2 texsize)
{
	float4 result = 0.0f;
	
	if(true){
    const float2 samplePos = uv * texsize;
    const float2 texPos1 = floor(samplePos - 0.5f) + 0.5f;

    const float2 f = samplePos - texPos1;

    const float2 w0 = f * (-0.5f + f * (1.0f - 0.5f * f));
    const float2 w1 = 1.0f + f * f * (-2.5f + 1.5f * f);
    const float2 w2 = f * (0.5f + f * (2.0f - 1.5f * f));
    const float2 w3 = f * f * (-0.5f + 0.5f * f);
	
	const float2 w12 = w1 + w2;
    const float2 offset12 = w2 / (w1 + w2);

    float2 texPos0 = texPos1 - 1;
    float2 texPos3 = texPos1 + 2;
    float2 texPos12 = texPos1 + offset12;

    texPos0 /= texsize;
    texPos3 /= texsize;
    texPos12 /= texsize;

    result += tex2D(tex, float2(texPos0.x, texPos0.y)) * w0.x * w0.y;
    result += tex2D(tex, float2(texPos12.x, texPos0.y)) * w12.x * w0.y;
    result += tex2D(tex, float2(texPos3.x, texPos0.y)) * w3.x * w0.y;
    result += tex2D(tex, float2(texPos0.x, texPos12.y)) * w0.x * w12.y;
    result += tex2D(tex, float2(texPos12.x, texPos12.y)) * w12.x * w12.y;
    result += tex2D(tex, float2(texPos3.x, texPos12.y)) * w3.x * w12.y;
    result += tex2D(tex, float2(texPos0.x, texPos3.y)) * w0.x * w3.y;
    result += tex2D(tex, float2(texPos12.x, texPos3.y)) * w12.x * w3.y;
    result += tex2D(tex, float2(texPos3.x, texPos3.y)) * w3.x * w3.y;
	} //UseCatrom
	else{
	result = tex2D(tex, uv);
	} //UseBilinear
    return max(0, result);
}

float GetRoughness(float2 texcoord)
{
	return GI?1:tex2Dlod(sSSSR_RoughTex, float4(texcoord,0,0)).x;
}

#define VARIANCE_INTERSECTION_MAX_T 10000
float3 ClipToAABB( float3 inHistoryColour, float3 inCurrentColour, float3 inBBCentre, float3 inBBExtents )
{
	const float3 direction = inCurrentColour - inHistoryColour;
	const float3 intersection = ( ( inBBCentre - sign( direction ) * inBBExtents ) - inHistoryColour ) / direction;
	const float3 possibleT = intersection >= 0.0f.xxx ? intersection : VARIANCE_INTERSECTION_MAX_T + 1.f;
	const float3 t = min( VARIANCE_INTERSECTION_MAX_T, min( possibleT.x, min( possibleT.y, possibleT.z ) ) );
	
	return float3( t < VARIANCE_INTERSECTION_MAX_T ? inHistoryColour + direction * t : inHistoryColour );
}

void GetNormalAndDepthFromGeometry(in float2 texcoord, out float3 Normal, out float Depth)
{
	float4 Geometry = tex2Dlod(sSSSR_NormTex, float4(texcoord,0,0));
	Normal = Geometry.xyz;
	Depth = Geometry.w;
}

float2 GetVariance(float2 texcoord, float4 color, float size)
{
	float2 p = pix;
	/*float4 Input = tex2D(sSSSR_HLTex0, texcoord+p/2);
	Input += tex2D(sSSSR_HLTex0, texcoord-p/2);
	Input += tex2D(sSSSR_HLTex0, texcoord+float2(p.x,-p.y)/2);
	Input += tex2D(sSSSR_HLTex0, texcoord-float2(p.x,-p.y)/2);
	Input /= 4;*/
	float4 Input = tex2D(sSSSR_HLTex0, texcoord);
	const float GI_Var = sqrt(abs(Input.b - Input.g * Input.g));
	const float AO_Var = Input.a;
	
	const float mul = 1 + max(0, 8 - Input.r)*0.5;
	float2 Var = sqrt(float2(GI_Var, AO_Var) * mul) * rsqrt(size);
	
	Var /= min(1, dot(16, abs(color.yz - 0.5)));
	
	return Var;
}

///////////////Functions///////////////////
///////////////Pixel Shader////////////////

void GBuffer1
(
	float4 vpos : SV_Position,
	float2 texcoord : TexCoord,
	out float4 normal : SV_Target0,
	out float roughness : SV_Target1) //SSSR_NormTex
{
	normal.xyz = Normal(texcoord.xy);
	normal.xyz = BlendBump(normal.xyz, Bump(texcoord, BUMP));
	
	normal.w   = LDepth(texcoord.xy);

	roughness = GetRoughTex(texcoord, normal).x;
}

void CopyGBufferLowRes(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float Depth : SV_Target0)
{
	Depth = LDepth(texcoord)*FAR_PLANE;
}

#define LDepthLoRes(texcoord) tex2Dlod(sSSSR_LowResDepthTex, float4(texcoord.xy, 0, 0)).r
void DoRayMarch(float3 noise, float3 position, float3 raydir, out float3 Reflection, out float HitDistance, out float IsHit) 
{
	float3 raypos; float2 UVraypos; float Check, steplength; bool hit; uint i;
	float bias = -position.z * rcp(FAR_PLANE);
	
	steplength = (1 + noise.x * STEPNOISE) * position.z * 0.005;
	raypos = position + raydir * steplength;
	
	float raydepth = -RAYDEPTH;
	
#if UI_DIFFICULTY == 1
	const float RayInc = RAYINC;
	[loop]for(i = 0; i < UI_RAYSTEPS; i++)
#else
	const int RaySteps[5] = {17, 65, 161, 321, 501}; 
	const float RayIncPreset[5] = {2, 1.14, 1.045, 1.02, 1.012};
	const float RayInc = RayIncPreset[UI_QUALITY_PRESET];
	[loop]for(i = 0; i < RaySteps[UI_QUALITY_PRESET]; i++)
#endif
	{
		UVraypos = PostoUV(raypos);
		if(IsSaturated(UVraypos.xy))break;
		Check = LDepthLoRes(UVraypos) - raypos.z; //FAR_PLANE is multiplied in the texture

		if(Check < bias && Check > raydepth * steplength)
		{
			IsHit = 1;
			break;
		}
		
		raypos += raydir * steplength;
		if(UI_ExcludeSky && raypos.z > FAR_PLANE-10)break;
		steplength *= RayInc;
	}
	float3 HitNormal = tex2D(sSSSR_NormTex, UVraypos.xy).rgb;
	float  HitFacing = pow(dot(raydir, HitNormal), 1);
	Reflection = tex2D(sTexColor, UVraypos.xy).rgb * (HitFacing >= 0 || !GI) * IsHit;
	HitDistance = IsHit ? distance(raypos, position) : FAR_PLANE;
}

void RayMarch(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0
#if NGL_HYBRID_MODE
, out float4 FinalColor2 : SV_Target1
#endif
)
{
	const float4 Geometry = tex2D(sSSSR_NormTex, texcoord);
	const float FadeFac = saturate(pow((depthfade*depthfade), Geometry.w));
	if(FadeFac<0.01||Geometry.w>SkyDepth)
	{ 
#if NGL_HYBRID_MODE
		FinalColor = float4(0,0.5,0.5,1);
		FinalColor2 = float4(0,0.5,0.5,0);
#else
		FinalColor = float4(0,0.5,0.5,GI?1:0);		
#endif
	}
	else
	{
		float HitDistance = 0;
		float Roughness = GetRoughness(texcoord);
		float HL = max(1, tex2D(sSSSR_HLTex0, texcoord).r);
		
		float3 BlueNoise  = BN3dts(texcoord, max(1,HL));
		float3 IGNoise    = IGN3dts(texcoord, max(MAX_Frames,1)); //Interleaved Gradient Noise
		float3 WhiteNoise = WN3dts(texcoord, MAX_Frames);
		
		float3 noise = (HL <= 0) ? IGNoise :
					   (HL > 64) ? WhiteNoise :
								   BlueNoise;
								   
		float3 position = UVtoPos (texcoord);
		float3 normal   = Geometry.xyz;
		float3 eyedir   = normalize(position);
		
		float3 raydirG   = reflect(eyedir, normal);
		float3 raydirR   = normalize(noise*2-1);
		if(dot(raydirR, normal)>0) raydirR *= -1;
		
		float raybias    = dot(raydirG, raydirR);
		
		float3 raydir;
		float4 reflection;
		float IsHit;
		if(!GI)raydir = lerp(raydirG, raydirR, pow(1-(0.5*cos(raybias*PI)+0.5), rsqrt(InvTonemapper((GI)?1:Roughness))));
		else raydir = raydirR;
		
		DoRayMarch(IGNoise, position, raydir, reflection.rgb, HitDistance, IsHit);
		
		FinalColor.rgb = max(ClampLuma(InvTonemapper(reflection.rgb), LUM_MAX),0);
		
		
		if(!GI)FinalColor.a = IsHit * FadeFac;
		else
		{
			FinalColor.a = saturate(5*HitDistance/FAR_PLANE);
			FinalColor.rgb *= IsHit;
			//depth fade
			FinalColor.rgb *= FadeFac;
			FinalColor.a    = lerp(1, FinalColor.a, FadeFac);
		}
		FinalColor.rgb = toYCC(FinalColor.rgb);
	}//depth check if end
	//FinalColor.a  =1;
}//ReflectionTex

void TemporalFilter(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0, out float4 HistoryLength : SV_Target1)
{
	const float2 MotionVectors = sampleMotion(texcoord);
	const float2 PastUV  = texcoord + MotionVectors;
	const float4 normal  = tex2D(sSSSR_NormTex, texcoord);
	const float  facing  = dot(normal.xyz, normalize(UVtoPos(texcoord)));
	const float  depth   = normal.w;
	
	const float2 past_ogcolor = tex2D(sSSSR_POGColTex, PastUV).xy;
	const float  curr_ogcolor = dot(1, toYCC(tex2D(sTexColor, texcoord).rgb).gb);
	const float  past_depth   = past_ogcolor.y;
	
	float4 Current = tex2D(sSSSR_ReflectionTex, texcoord);
	float4 History = tex2D(sSSSR_HistoryTex, PastUV);
	
	float4 M1 = Current, M2 = Current * Current;
	float4 Min = 1e+7, Max = 0;
	
	static const float r = 3;
	static const float area = pow(r * 2 + 1, 2);
	
	float mask;
	float4 Clamped_History;
	
	if(depth < SkyDepth)
	{
		[unroll]for(int xx = -r; xx <= r; xx++){
		[unroll]for(int yy = -r; yy <= r; yy++)
		{
			if(xx==0&&yy==0)continue;
			
			float4 sCurrent = tex2Doffset(sSSSR_ReflectionTex, texcoord, int2(xx, yy));
			float  slum     = lum(sCurrent.rgb);
			
			M1 += sCurrent;
			M2 += sCurrent * sCurrent;
			
			Min = min(Min, sCurrent);
			Max = max(Max, sCurrent);
		}}

		M1 /= area;
		M2 /= area;
	
		float4 Var = sqrt(abs(M1 * M1 - M2)) / 2;
		
		Clamped_History = History;
		Clamped_History.rgb = ClipToAABB(History.rgb, Current.rgb, M1.rgb - Var.rgb, M1.rgb + Var.rgb);
		Clamped_History.rgb = clamp(History.rgb, M1.rgb - Var.rgb, M1.rgb + Var.rgb);
		Clamped_History.a   = clamp(History.a, M1.a - Var.a, M1.a + Var.a);
		
		mask =
				abs(depth - past_depth) * facing      < Temporal_Filter_DepthT
				&& abs(Clamped_History.r - History.r) < Temporal_Filter_LuminanceT
				&& abs(curr_ogcolor - past_ogcolor.x) < Temporal_Filter_AntiLagT
		;
			
		bool inbound = PastUV.x <= 1 || PastUV.x >= 0 || PastUV.y <= 1 || PastUV.y >= 0;
		mask *= inbound;
	}
	else
	{
		mask = 0;
		Clamped_History = 1;
	}
	
	HistoryLength    = tex2D(sSSSR_HLTex1, PastUV);
	HistoryLength.r *= saturate(mask); //sets the history length to 0 for discarded samples
	HistoryLength.r  = min(HistoryLength.r, MAX_Frames); //Limits the linear accumulation to MAX_Frames, The rest will be accumulated exponentialy with the speed = (1-1/Max_Frames)

	HistoryLength.r++;
	FinalColor = lerp(Clamped_History, HistoryLength.r <= 4 ? M1 : Current, 1 / HistoryLength.r);
	if(HistoryLength.r > 4)
	{
		HistoryLength.g = lerp(HistoryLength.g, Current.z, 1 / HistoryLength.r);//GI lum M1
		HistoryLength.b = lerp(HistoryLength.b, Current.z * Current.z, 1 / HistoryLength.r);//GI lum M2
		HistoryLength.a = lerp(HistoryLength.a, Current.a * Current.a, 1 / HistoryLength.r);//AO M2
	}
	else
	{
		HistoryLength.gba = float3(M1.z, M2.z, M2.w);
	}
	HistoryLength.a = sqrt(abs(HistoryLength.a - FinalColor.a * FinalColor.a));//AO Var

	FinalColor = max(1e-6, FinalColor);
}
    
void AdaptiveBox(in int size, in sampler Tex, in float2 texcoord, out float4 FinalColor
#if NGL_HYBRID_MODE
, in sampler Tex2, out float4 FinalColor2
#endif
)
{
	float3 normal; float depth;
	GetNormalAndDepthFromGeometry(texcoord, normal, depth);
		
	if(Sthreshold == 0 || depth >= SkyDepth)FinalColor = tex2Dlod(Tex, float4(texcoord,0,0));
#if NGL_HYBRID_MODE
	if(Sthreshold == 0 || depth >= SkyDepth)FinalColor2 = tex2Dlod(Tex2, float4(texcoord,0,0));
#endif
	else{
		
		float HL = tex2D(sSSSR_HLTex0, texcoord).r;
		
		float2 p = pix;
		p /= NGL_RESOLUTION_SCALE;
		p *= size * clamp(8 - HL, 1, 2);
		
		float4 color      = tex2Dlod(Tex, float4(texcoord, 0, 0));
		float2 color_lum  = color.xw;

		float4 sColor     = color;
		float2 weight_sum = 1;
		
		float2 Variance = GetVariance(texcoord, color, size);
		//Variance = 1000000;
		static const float
		normal_mul     = Spatial_Filter_NormalT,
		depth_mul      = Spatial_Filter_DepthT / (dot(normalize(UVtoPos(texcoord)), normal));
		const float2 lum_threshold      = float2(Spatial_Filter_LuminanceT, Spatial_Filter_AmbeintOcclusionT) / Variance.x;
		
		float4 offset = float4(0,0,0,0);
		float4 color_sample;
		float2 sample_lum;
		float2 weight; float wd, wn; float2 wl;
		float3 snormal;
		float  sdepth;
		float  offsetlength;
		float4 Min = 1e+7, Max = 0;
		
#if NGL_HYBRID_MODE
		float4 color2      = tex2Dlod(Tex2, float4(texcoord, 0, 0));
		float2 color_lum2  = float2(Tonemapper(lum(color2.rgb)), color2.a);
		float4 sColor2     = color2;
		float2 weight_sum2 = 1;
		float4 Min2 = 1e+7, Max2 = 0;
#endif
		static const int r = 1;
		[unroll]for(int x = -r; x <= r; x++){
		[unroll]for(int y = -r; y <= r; y++){
			if(x==0&&y==0)continue;
			offset.xy = float2(x,y) * p;
			offsetlength = length(offset.xy * BUFFER_SCREEN_SIZE);
			offset.xy += texcoord;
			
			GetNormalAndDepthFromGeometry(offset.xy, snormal, sdepth);
			color_sample = tex2Dlod(Tex, offset);
			
			Min = min(Min, color_sample);
			Max = max(Max, color_sample);
			
			sample_lum = color_sample.xw;
			
			wn = pow(saturate(dot(snormal, normal)), Spatial_Filter_NormalT);
			wd = abs(sdepth - depth) * depth_mul * rcp(offsetlength);
			wl = abs(color_lum.xy - sample_lum.xy) * lum_threshold.xy;
			
			weight = saturate(exp(-wl - wd) * wn);
			
			sColor += color_sample * weight.xxxy;
			weight_sum += weight;
			
#if NGL_HYBRID_MODE
			color_sample = tex2Dlod(Tex2, offset);
			sample_lum = ignore_lum_diff ? color_lum2 : float2(Tonemapper(lum(color_sample.rgb)), color_sample.a);
			
			Min2 = min(Min2, color_sample);
			Max2 = max(Max2, color_sample);
			
			weight = saturate(exp(-abs(color_lum2 - sample_lum) * lum_threshold  - wn - wd));
			
			sColor2 += color_sample * weight.xxxy;
			weight_sum2 += weight;
#endif
		}}
		sColor /= weight_sum.xxxy;
		sColor = clamp(sColor, Min, Max);
		FinalColor = max(sColor, 1e-6);
#if NGL_HYBRID_MODE
		sColor2 /= weight_sum2.xxxy;
		FinalColor2 = max(sColor2, 1e-6);
#endif
	}
}

void SpatialFilter0( in float4 vpos : SV_Position, in float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0
#if NGL_HYBRID_MODE
, out float4 FinalColor2 : SV_Target1
#endif
)
{
#if !NGL_HYBRID_MODE
	AdaptiveBox(1, sSSSR_FilterTex0, texcoord, FinalColor);
#else
	AdaptiveBox(1, sSSSR_FilterTex0, texcoord, FinalColor, sSSSR_FilterTex0_2, FinalColor2);
#endif
}
		
void SpatialFilter1( in float4 vpos : SV_Position, in float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0
#if NGL_HYBRID_MODE
, out float4 FinalColor2 : SV_Target1
#endif
)
{
#if !NGL_HYBRID_MODE
	AdaptiveBox(2, sSSSR_FilterTex1, texcoord, FinalColor);
#else
	AdaptiveBox(2, sSSSR_FilterTex1, texcoord, FinalColor, sSSSR_FilterTex1_2, FinalColor2);
#endif
}

void SpatialFilter2(in  float4 vpos : SV_Position,in  float2 texcoord : TexCoord,out float4 FinalColor : SV_Target0//FilterTex1
#if NGL_HYBRID_MODE
	, out float4 FinalColor2 : SV_Target4//FilterTex1_2
#endif
)
{
#if !NGL_HYBRID_MODE
	AdaptiveBox(4, sSSSR_FilterTex0, texcoord, FinalColor);
#else
	AdaptiveBox(4, sSSSR_FilterTex0, texcoord, FinalColor, sSSSR_FilterTex0_2, FinalColor2);
#endif
}

void SpatialFilter3(in  float4 vpos : SV_Position,in  float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0//FilterTex0
#if NGL_HYBRID_MODE
	, out float4 FinalColor2 : SV_Target2//FilterTex0_2
#endif
)
{
#if !NGL_HYBRID_MODE
	AdaptiveBox(8, sSSSR_FilterTex1, texcoord, FinalColor);
#else
	AdaptiveBox(8, sSSSR_FilterTex1, texcoord, FinalColor, sSSSR_FilterTex1_2, FinalColor2);
#endif
}

void HistoryBuffer
(
	in float4 vpos          : SV_Position,
	in  float2 texcoord     : TexCoord,
	out float2 Ogcol        : SV_Target0,//POGColTex
	out float4  HLOut        : SV_Target1,//HLTex1
	out float4 ColorHistory : SV_Target2 //HistoryTex
)
{
	HLOut      = tex2D(sSSSR_HLTex0, texcoord);
	float3 OGC = toYCC(tex2D(sTexColor, texcoord).rgb);
	float Depth = tex2D(sSSSR_NormTex, texcoord).w;
	Ogcol      = float2(OGC.y+OGC.z, Depth);
	
	ColorHistory = tex2D(sSSSR_FilterTex0, texcoord);
}

void TemporalStabilizer(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0)
{
	float HL = tex2D(sSSSR_HLTex0, texcoord).r;
	float2 p = pix / NGL_RESOLUTION_SCALE;
	
	float Roughness = tex2D(sSSSR_RoughTex, texcoord).x;
	float2 MotionVectors = sampleMotion(texcoord);

	float4 current = tex2D(sSSSR_FilterTex0, texcoord);
	float4 history = tex2Dcatrom(sSSSR_FilterTex2, texcoord +  MotionVectors, BUFFER_SCREEN_SIZE);
	history.rgb = (history.rgb);
	float4 CurrToYCC = float4((current.rgb), current.a);
	
	float4 SharpenMin = 1000000, SharpenMax = -1000000;
	float4 SharpenMean = current;
	
#if TEMPORAL_STABILIZER_MINMAX_CLAMPING
	float4 Max = CurrToYCC, Min = CurrToYCC;
#endif
	float4 PreSqr = CurrToYCC * CurrToYCC, PostSqr = CurrToYCC;

	float4 SCurrent; int x, y;
	int r = 1;
	int area = r*2+1; area*=area;
	
	[unroll]for(int x = -r; x <= r; x++){
	[unroll]for(int y = -r; y <= r; y++)
	{
		if(x==0&&y==0)continue;
		SCurrent = tex2D(sSSSR_FilterTex0, texcoord + int2(x,y) * p);
		
		SharpenMin = min(SCurrent, SharpenMin);
		SharpenMax = max(SCurrent, SharpenMax);
		
		SCurrent.rgb = (SCurrent.rgb);
#if TEMPORAL_STABILIZER_MINMAX_CLAMPING
		Max = max(SCurrent, Max);
		Min = min(SCurrent, Min);
#endif
		PreSqr += SCurrent * SCurrent;
		PostSqr += SCurrent;
	}}
	//Min/Max Clamping
#if TEMPORAL_STABILIZER_MINMAX_CLAMPING
	float4 chistory = clamp(history, Min, Max);
#else
	float4 chistory = history;
#endif
	//Variance Clipping
	PostSqr /= area; PreSqr /= area;
	float4 Var = sqrt(abs(PostSqr * PostSqr - PreSqr));
	Var = pow(Var, 0.7);
	Var.xyz *= CurrToYCC.x;
#if TEMPORAL_STABILIZER_VARIANCE_CLIPPING
	chistory = clamp(chistory, CurrToYCC - Var, CurrToYCC + Var);
#endif

	float4 diff = saturate((abs(chistory - history)));
	diff.r = diff.g + diff.b;
	
	chistory.rgb = (chistory.rgb);
	
	float2 outbound = texcoord + MotionVectors;
	outbound = float2(max(outbound.r, outbound.g), min(outbound.r, outbound.g));
	outbound.rg = (outbound.r > 1 || outbound.g < 0);
	
	float4 LerpFac = TSIntensity                        //main factor
					*(1 - outbound.r)                   //0 if the pixel is out of boundary
					//*max(0.85, pow(GI ? 1 : Roughness, 1.0)) //decrease if roughness is low
					*max(0.5, saturate(1 - diff.rrra*10))                  //decrease if the difference between original and clamped history is high
					*max(0.7, 1 - 5 * length(MotionVectors))  //decrease if movement is fast
					;
	LerpFac = saturate(LerpFac);
	FinalColor = lerp(current, chistory, LerpFac);
#if TEMPORAL_STABILIZER_MINMAX_CLAMPING
	FinalColor = clamp(FinalColor, max(1e-7, SharpenMin), SharpenMax);
#endif
}

void TemporalStabilizer_CopyBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 FinalColor : SV_Target0)
{
	FinalColor = tex2D(sSSSR_FilterTex1, texcoord).rgba;
}

float3 RITM(in float3 color){return color/max(1 - color, 0.001);}
float3 RTM(in float3 color){return color / (1 + color);}

void Output(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float3 FinalColor : SV_Target0)
{
	FinalColor = 0;
	float2 p = pix;
	float3 Background = tex2D(sTexColor, texcoord).rgb;
	float  Depth      = LDepth(texcoord);
	float  Roughness  = tex2D(sSSSR_RoughTex, texcoord).x;
	float HL = tex2D(sSSSR_HLTex0, texcoord).r;
	
	//Lighting debug
	if(debug==1)Background = 0.5;
	
	//if(Depth>=SkyDepth)FinalColor = Background;
	if(debug == 0 || debug == 1)
	{
		if(GI)
		{
			float4 GI = tex2D(sSSSR_FilterTex1, texcoord).rgba;
			GI.rgb = max(0, toRGB(GI.rgb));
			//Changes the InvTonemapper to reinhardt for blending
			GI.rgb = Tonemapper(GI.rgb);
			GI.rgb = RITM(GI.rgb);
			//Invtonemaps the background so we can blend it with GI in HDR space. Gives better results.
			float3 HDR_Background = RITM(Background);
			
			//calculate AO Intensity
			float2 AO = GI.aa;
			AO.r = saturate(pow(AO.r, AO_Intensity_Background));
			AO.g = saturate(pow(AO.g, AO_Intensity_Reflection));
			
			//modify saturation and exposure
			GI.rgb *= (SatExp.g * ((debug==1) ? 6 : 2));
			GI.rgb = lerp(lum(GI.rgb), GI.rgb, SatExp.r);
			
			//apply AO
			float3 Img_AO = HDR_Background * AO.r;
			float3  GI_AO = GI.rgb * AO.g;
			//apply GI
			float3 Img_GI = Img_AO + GI_AO * Background;
			Img_GI = RTM(Img_GI);
			//fix highlights by reducing the GI intensity
			FinalColor = Img_GI;
		}
		else 
		{
			float4 Reflection = tex2D(sSSSR_FilterTex1, texcoord);
			Reflection.rgb = max(0, toRGB(Reflection.rgb));
			//Switch inverse tonemapping from Thimoty lottes to Reinhardt for blending
			Reflection.rgb = Tonemapper(Reflection.rgb);
			Reflection.rgb = RITM(Reflection.rgb);
			
			//calculate Fresnel
			float3 Normal  = tex2D(sSSSR_NormTex, texcoord).rgb;
			float3 Eyedir  = normalize(UVtoPos(texcoord));
			float  Coeff   = pow(abs(1 - dot(Normal, Eyedir)), lerp(EXP, 0, Roughness));
			float  Fresnel = saturate(lerp(0.05, 1, Coeff))*Reflection.a;
			
			//apply Reflection
			float3 Img_Reflection = lerp(RITM(Background), Reflection.rgb, Fresnel);
			Img_Reflection = RTM(Img_Reflection);
			//fix highlights by reducing the Reflection intensity
			FinalColor = Img_Reflection;
		}
	}
	
	//debug views: depth, normal, history length, roughness
	else if(debug == 2) FinalColor = sqrt(Depth);
	else if(debug == 3) FinalColor = tex2D(sSSSR_NormTex, texcoord).rgb * 0.5 + 0.5;
	else if(debug == 4) FinalColor = tex2D(sSSSR_HLTex1, texcoord).r/MAX_Frames;
	else if(debug == 5) FinalColor = Roughness;
	//else if(debug == 6) FinalColor = GetVariance(texcoord).r/1;
	//Avoids covering menues in black
	if(Depth <= 0.0001) FinalColor = Background;
	FinalColor += IGN3dts(texcoord, 1) * rcp(256);
	
	//FinalColor = tex2D(sSSSR_FilterTex1, texcoord).a;
	//float4 color = tex2D(sSSSR_FilterTex0, texcoord);
	//float2 Variance = GetVariance(texcoord)/sqrt(1);
	//Variance = Variance / dot(20, abs(color.yz - 0.5));
	//FinalColor = Variance.r;
	
}

///////////////Pixel Shader////////////////
///////////////Techniques//////////////////
///////////////Techniques//////////////////
