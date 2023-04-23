//Noiseless Ringingless sharpening
//Written by MJ_Ehsan for Reshade
//Version 1.0

//License:
//CC0 ^_^

///////////////Include/////////////////////

#include "ReShadeUI.fxh"
#include "ReShade.fxh"

#define pix float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
#define LDepth ReShade::GetLinearizedDepth

#define PI 3.1415926535

///////////////Include/////////////////////
///////////////Textures-Samplers///////////

texture TexColor : COLOR;
sampler sTexColor {Texture = TexColor; SRGBTexture = true;};

texture DTex {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
sampler sDTex {Texture = DTex; SRGBTexture = true;};

///////////////Textures-Samplers///////////
///////////////UI//////////////////////////

uniform float UI_EdgeSharpness <
	ui_type = "slider";
	ui_label = "Edge Sharpness intensity";
	ui_max = 1;
> = 1;

uniform float UI_TextureSharpness <
	ui_type = "slider";
	ui_label = "Texture Clarity intensity";
	ui_max = 1;
> = 1;

uniform float UI_Overshoot <
	ui_type = "slider";
	ui_label = "Overshoot intensity";
> = 0.667;

///////////////UI//////////////////////////
///////////////Functions///////////////////

float lum(float3 a)
{
	return (a.r + a.g + a.b) * 0.33333333;
}

///////////////Functions///////////////////
///////////////Vertex Shader///////////////
///////////////Vertex Shader///////////////
///////////////Pixel Shader////////////////

//The target of this sharpening filter is to have the least amount of
//undesired ringing artifact, and still leave some overshoot to prod-
//ce a sharper image. Also it tries to ignore film grain using a bil-
//ateral gaussian filter to produce the unsharp mask.
//===================================================================
//===================================================================
//Denoiser is from https://www.shadertoy.com/view/4dfGDH
//It uses gaussian weighs both for color difference and for spatial 
//difference.
#define SIGMA 2
#define BSIGMA 0.2

#ifndef DENOISER_SIZE
 #define DENOISER_SIZE 5
#endif

float normpdf(in float x, in float sigma)
{
	return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}

float normpdf3(in float3 v, in float sigma)
{
	return 0.39894*exp(-0.5*dot(v,v)/(sigma*sigma))/sigma;
}


float3 Denoiser(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 c = tex2D(sTexColor, texcoord.xy).rgb;
	float2 p = pix;
	//declare stuff
	const int kSize = (DENOISER_SIZE-1)/2;
	float kernel[DENOISER_SIZE];
	float3 final_colour = 0;
	
	//create the 1-D kernel
	[unroll]for (int j = 0; j <= kSize; ++j)
		kernel[kSize+j] = kernel[kSize-j] = normpdf(float(j), SIGMA);
	
	float Z;
	float3 cc;
	float factor;
	float bZ = rcp(normpdf(0, BSIGMA));
	//read out the texels
	[unroll]for (int i=-kSize; i <= kSize; ++i){
	[unroll]for (int j=-kSize; j <= kSize; ++j){
		cc = tex2D(sTexColor, texcoord.xy+float2(i,j)*p).rgb;
		factor = normpdf3(cc-c, BSIGMA)*bZ*kernel[kSize+j]*kernel[kSize+i];
		Z += factor;
		final_colour += factor*cc;
	}
	}
	
	return final_colour/Z;
}

//The sharpener uses min/max clamping to reduce ringing.
//It also uses variance to calculate the desirable over-
//shoot amount, as well as the sharpness strength. Vari-
//ance is also used to blend between noisy mean and den-
//oised mean for unsharp mask.
float3 PS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	//fetch center pixels
	float3 color = tex2D(sTexColor, texcoord).rgb;
	float3 blurcenter = tex2D(sDTex, texcoord).rgb;
	
	float2 p = pix;
	const float radius = 1;
	//total sample count
	float s = radius*2+1; s*=s;
	
	float3 Min = color;
	float3 Max = color;
	float3 PreSqr = color * color;
	float3 mean1 = color;
	float3 mean2 = blurcenter;
	
	float2 pr = p * 0.70710678; //turns the square to circle
	//circle pattern to make the blur appear smoother
	float2 offset[8];
	offset = {
		float2(-pr.x,-pr.y),float2(0, p.y),float2( pr.x,-pr.y),
		float2(-p.x,     0),			   float2( p.x,     0),
		float2(-pr.x, pr.y),float2(0,-p.y),float2( pr.x, pr.y)};
		
	//[unroll]for(float x = -radius; x <= radius; x ++){
	//[unroll]for(float y = -radius; y <= radius; y ++)
	[unroll]for(int x = 0; x < 8; x++)
	{
		//ignore centers as they are already fetched
		//if(x==0&&y==0)continue;
		
		//fetches the smoothed texture
		float3 sColor = tex2D(sDTex, (texcoord) + offset[x]).rgb;
		mean2 += sColor;
		
		//fetches the original texture
		float3 sMainColor = tex2D(sTexColor, (texcoord) + offset[x]).rgb;
		//stores minimum and maximum neighbors of the original texture
		Min = min(Min, sMainColor);
		Max = max(Max, sMainColor);
		//stores the values required for variance estimation from the original texture
		PreSqr += sMainColor*sMainColor;
		mean1 += sMainColor;
	}
	//divison by the number of samples
	mean2 /= s; mean1 /= s;
	
	//calculate variance
	PreSqr /= s; //square each sample and average all
	float3 PostSqr = mean1 * mean1; //average all samples then square
	//take the difference between them and root square it to inverse those squares
	float3 Deviation = sqrt(abs(PostSqr - PreSqr));
	//average deviation of rgb channels as the sharpening strength
	float  SWeight = dot(Deviation, 0.33333);
	//Clamping weight, more variance = less overshoot
	float  CWeight = 1-SWeight;
	CWeight *= CWeight;
	//Sharpening intensity, more variance = less intensity
	float Intensity = CWeight * 256;
	CWeight /= lerp(256, 20, sqrt(UI_Overshoot));
	
	//if variance is low, use the non-denoised image
	mean1 = lerp(mean2, mean1, SWeight);
	//makes the unsharp mask for edges
	float3 esharp = (blurcenter - mean1.rgb) * UI_EdgeSharpness * Intensity * SWeight;
	//makes the other mask for textures
	float3 tsharp = (color - blurcenter) * saturate(1-abs(esharp));
	tsharp *= UI_TextureSharpness * 1024;
	float tslum  = lum(tsharp);
	float Minlum = lum(Min);
	float Maxlum = lum(Max);
	tsharp = 
		tslum >= Maxlum ? tsharp * Maxlum :
		tslum <= Minlum ? tsharp * Minlum : tsharp;
	tsharp /= 24;
	
	//applies the unsharp mask
	esharp += color;
	//applies the clamping
	esharp = lerp(clamp(esharp, Min, Max), esharp, CWeight);
	//applies the texture sharpening
	esharp += clamp(lum(tsharp), -0.5, 0.5);
	
	//return blurcenter;
	return esharp;
}

///////////////Pixel Shader////////////////
///////////////Techniques//////////////////

technique Sharpifier
< ui_label = "Sharpifier";
  ui_tooltip = "                 Sharpifier               \n"
			   "              ||By Ehsan2077||            \n"
			   "|This  sharpness filter aims to  minimize|\n"
			   "|common  artifacts  of  other  sharpening|\n"
			   "|shaders such as ringing and noise boost.|\n";>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = Denoiser;
		RenderTarget = DTex;
		SRGBWriteEnable = true;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS;
		SRGBWriteEnable = true;
	}
}
///////////////Techniques//////////////////
