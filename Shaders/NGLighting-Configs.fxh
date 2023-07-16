#define AspectRatio BUFFER_WIDTH/BUFFER_HEIGHT

//Depth Buffer res for ray marching
#define RES_M 0.5

//=============================================================//
//==================UI PreCompile Settings=====================//
//=============================================================//

#ifndef NGL_UI_DIFFICULTY
 #define NGL_UI_DIFFICULTY 0
#endif

#ifndef NGL_RESOLUTION_SCALE
 #define NGL_RESOLUTION_SCALE 0.67
#endif

static const float2 RT_RES = NGL_RESOLUTION_SCALE * BUFFER_SCREEN_SIZE;

#ifndef NGL_HYBRID_MODE
 #define NGL_HYBRID_MODE 0
#endif

//=============================================================//
//=====================HDR Conversion==========================//
//=============================================================//

//Tonemapping mode : 1 = Timothy Lottes || 0 = Reinhardt
#define TM_Mode 1
#define IT_Intensity 1.00
//clamps the maximum luma of pixels to avoid unsolvable fireflies
#define LUM_MAX 25

//=============================================================//
//=====================Simple UI Preset========================//
//=============================================================//

#define STEPNOISE 2

#if !UI_DIFFICULTY

//simple UI mode preset
#define fov 50
#define UseCatrom false
#define SharpenGI false
#define RAYINC 2
#define RAYDEPTH 5
#define MAX_Frames 16
#define Sthreshold 0.003
#define AO_Radius_Background 1
#define AO_Radius_Reflection 1
#define SkyDepth 0.99

#endif

//=============================================================//
//===================Temporal Stabilizer=======================//
//=============================================================//

//Temporal stabilizer Intensity
#define TSIntensity 0.7
//Temporal Stabilizer Clamping kernel shape
#define   TEMPORAL_STABILIZER_MINMAX_CLAMPING 1
#define TEMPORAL_STABILIZER_VARIANCE_CLIPPING 0

//=============================================================//
//========================Filtering============================//
//=============================================================//

#define Spatial_Filter_NormalT           100.0
#define Spatial_Filter_DepthT            100.0
#define Spatial_Filter_LuminanceT        0.25
#define Spatial_Filter_AmbeintOcclusionT 5.000

#define Temporal_Filter_MVErrorT   0.010 //0.010 //lower = more sensitive
#define Temporal_Filter_DepthT     0.010 //0.005
#define Temporal_Filter_LuminanceT 1.000 //1.000
#define Temporal_Filter_AntiLagT   Temporal_Filter_MVErrorT
